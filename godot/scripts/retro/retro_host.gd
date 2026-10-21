class_name RetroHost
extends Node3D
## VRT's front door to the libretro-godot fork: installs bundled cores, starts
## and stops content, feeds input, and exposes the current frame + field.
##
## Directory layout (libretro-godot convention) under user://retro:
##   cores/<core>_libretro[_android].so   copied from the bundle on startup
##   save/<core>/<game>.srm, states/<core>/<game>.state
##   system/<core>/ (BIOS), core_options/, temp/
## Cores must run from app-private storage: /sdcard is noexec on Android.

signal content_started(entry: ContentLibrary.Entry)
signal content_failed(message: String)
signal content_stopped
## The core stopped by itself (a video reached its end, a game quit).
signal content_ended(entry: ContentLibrary.Entry)

## Desktop: cores come from the repo's cores/linux-x86_64 (tools/fetch_cores.sh).
## Android: from res://cores_bundle, packed into the APK.
const BUNDLE_ANDROID := "res://cores_bundle"
const BUNDLE_DESKTOP := "res://../cores/linux-x86_64"

var root := ProjectSettings.globalize_path("user://retro")
var current: ContentLibrary.Entry
var libretro: Node3D

var _last_serial := -1
var downloader: CoreDownloader
var _pending: ContentLibrary.Entry  # launch waiting for its core to download

## The core for a launch is being fetched; the launch resumes when it lands.
signal core_downloading(entry: ContentLibrary.Entry)
var _state_waiting := false


func _ready() -> void:
	libretro = ClassDB.instantiate("Libretro")
	add_child(libretro)
	libretro.connect("content_load_failed", _on_load_failed)
	libretro.connect("savestate_ready", _on_savestate_ready)
	libretro.call("SetInputEnabled", false)  # InputRouter drives the ports
	install_cores()
	install_system_files()
	downloader = CoreDownloader.new(root.path_join("cores"))
	add_child(downloader)
	downloader.installed.connect(_on_core_ready)
	downloader.failed.connect(func(core, why):
		if _pending and _pending.core == core:
			_pending = null
			content_failed.emit("Could not download the %s core (%s). Check the headset's internet connection." % [core, why]))
	# Fetch the rest in the background so first launches are instant.
	for core in CoreRegistry.CORES:
		if not CoreRegistry.CORES[core].get("bundled", false):
			downloader.request(core)


## Copy bundled cores into root/cores when missing or changed (size check).
func install_cores() -> void:
	var src := BUNDLE_ANDROID if OS.get_name() == "Android" else ProjectSettings.globalize_path(BUNDLE_DESKTOP)
	var dst := root.path_join("cores")
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		if f.get_extension() != "so":
			continue
		var from := src.path_join(f)
		var to := dst.path_join(f)
		var data := FileAccess.get_file_as_bytes(from)
		if FileAccess.file_exists(to) and FileAccess.open(to, FileAccess.READ).get_length() == data.size():
			continue
		var out := FileAccess.open(to, FileAccess.WRITE)
		out.store_buffer(data)
		out.close()
		print("VRT: installed core ", f)


## User-supplied system files (BIOS, DeeVee's optional libdvdcss.so.2) go in
## a reachable folder, /sdcard/VRT/system/<core>/, and are mirrored into each
## core's private system folder (user://retro/system/<core>/), which users
## cannot reach on a Quest. VRT ships none of them.
const USER_SYSTEM_DIR := "/sdcard/VRT/system"


func install_system_files() -> void:
	if OS.get_name() != "Android" or not DirAccess.dir_exists_absolute(USER_SYSTEM_DIR):
		return
	for core in DirAccess.get_directories_at(USER_SYSTEM_DIR):
		var src := USER_SYSTEM_DIR.path_join(core)
		var dst := root.path_join("system").path_join(core)
		DirAccess.make_dir_recursive_absolute(dst)
		for f in DirAccess.get_files_at(src):
			var data := FileAccess.get_file_as_bytes(src.path_join(f))
			var to := dst.path_join(f)
			if FileAccess.file_exists(to) and FileAccess.open(to, FileAccess.READ).get_length() == data.size():
				continue
			var out := FileAccess.open(to, FileAccess.WRITE)
			if out:
				out.store_buffer(data)
				out.close()
				print("VRT: installed system file %s/%s" % [core, f])


func start(entry: ContentLibrary.Entry) -> void:
	if not downloader.is_installed(entry.core):
		_pending = entry
		downloader.request(entry.core)
		core_downloading.emit(entry)
		return
	stop()
	var path := ContentLibrary.resolve_launch_path(entry, root.path_join("temp/content"))
	if path == "":
		content_failed.emit("Nothing playable in %s" % entry.path.get_file())
		return
	var save_dir := root.path_join("save").path_join(entry.core)
	DirAccess.make_dir_recursive_absolute(save_dir)
	libretro.call("SetSramPath", save_dir.path_join(entry.title + ".srm"))
	_apply_managed_options(entry.core)
	_run_t = 0.0  # restart the start-up grace period (see _process)
	libretro.call("StartContent", root, entry.core, path)
	current = entry
	_last_serial = -1
	print("VRT: started ", entry.core, " ", path)
	content_started.emit(entry)


## Options VRT owns, written into the core's .opt before every start. The
## frontend saves every option to the file, so a default from an older core
## build (DeeVee's deinterlace used to default to Bwdif) would otherwise stick.
const MANAGED_OPTIONS := {
	# VRT draws interlace on the tube itself; never deinterlace in the core.
	"deevee": {"deevee_deinterlace": "crt"},
}


## Options the TV sets at runtime (e.g. DeeVee's TV Display Type from the
## TV type and WIDESCREEN setting), on top of MANAGED_OPTIONS.
var option_overrides := {}


## Set a core option VRT owns: written before the core's next start, and
## applied live if that core is running.
func set_core_option(core: String, key: String, value: String) -> void:
	if not core in option_overrides:
		option_overrides[core] = {}
	option_overrides[core][key] = value
	if current and current.core == core:
		libretro.call("SetCoreOption", key, value)


func _apply_managed_options(core: String) -> void:
	if not core in MANAGED_OPTIONS and not core in option_overrides:
		return
	var path := root.path_join("core_options").path_join(core + ".opt")
	var opts: Dictionary = MANAGED_OPTIONS.get(core, {}).duplicate()
	opts.merge(option_overrides.get(core, {}), true)
	var lines := PackedStringArray()
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var key := line.get_slice("=", 0).strip_edges()
			if key in opts:
				line = '%s = "%s"' % [key, opts[key]]
				opts.erase(key)
			lines.append(line)
	for key in opts:
		lines.append('%s = "%s"' % [key, opts[key]])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")


var _run_t := 0.0


func _process(delta: float) -> void:
	if current == null:
		_run_t = 0.0
		return
	_run_t += delta
	# Grace period: a core is "starting", not yet running, for a moment.
	if _run_t > 2.0 and not libretro.call("IsRunning"):
		var e := current
		stop()
		content_ended.emit(e)


func _on_core_ready(core: String) -> void:
	if _pending and _pending.core == core:
		var e := _pending
		_pending = null
		start(e)


func stop() -> void:
	if current == null:
		return
	libretro.call("RequestSramFlush")
	libretro.call("StopContent")
	current = null
	content_stopped.emit()


func is_running() -> bool:
	return current != null


## Current frame; re-read every frame (a resolution change makes a new texture).
func video_texture() -> Texture2D:
	return libretro.call("GetVideoTexture")


## enum vrt_field of the current frame: 0 progressive, 1 top, 2 bottom.
func video_field() -> int:
	return libretro.call("GetVideoField")


## Frames that landed since the last call (0 = none, >1 = some were skipped
## between our render frames, which matters for field persistence later).
func take_new_frames() -> int:
	var serial: int = libretro.call("GetVideoFrameSerial")
	var n := 0 if _last_serial < 0 else serial - _last_serial
	_last_serial = serial
	return n


func set_joypad(port: int, mask: int, lx := 0, ly := 0, rx := 0, ry := 0) -> void:
	libretro.call("SetJoypadState", port, mask, lx, ly, rx, ry)


## uv in [0,1]^2 over the video output (top-left origin).
func set_pointer(port: int, uv: Vector2, pressed: bool) -> void:
	var x := int(clampf(uv.x * 2.0 - 1.0, -1.0, 1.0) * 32767.0)
	var y := int(clampf(uv.y * 2.0 - 1.0, -1.0, 1.0) * 32767.0)
	libretro.call("SetPointerState", port, x, y, pressed)


func quick_save() -> void:
	if current and not _state_waiting:
		_state_waiting = true
		libretro.call("RequestSaveState")


func quick_load() -> void:
	if current == null:
		return
	var f := FileAccess.open(_state_path(), FileAccess.READ)
	if f == null:
		return
	var frame := f.get_64()
	libretro.call("RequestLoadState", f.get_buffer(f.get_length() - 8), frame)


func _state_path() -> String:
	var d := root.path_join("states").path_join(current.core)
	DirAccess.make_dir_recursive_absolute(d)
	return d.path_join(current.title + ".state")


func _on_savestate_ready(data: PackedByteArray, frame: int) -> void:
	_state_waiting = false
	if current == null:
		return
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	f.store_64(frame)
	f.store_buffer(data)
	print("VRT: saved state ", _state_path(), " (", data.size(), " bytes)")


func _on_load_failed(message: String) -> void:
	push_warning("VRT: content failed: " + message)
	current = null
	content_failed.emit(message)


func _exit_tree() -> void:
	stop()
