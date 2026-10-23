class_name ContentLibrary
extends RefCounted
## Finds playable content under the configured roots.
##
## Layout expected under each root: <root>/<System folder>/<files>, e.g.
## ROMS/Genesis/Sonic 2.zip. Files directly in a root are matched by extension.
## Zips are listed as-is and unpacked at launch (resolve_launch_path), since
## the cores themselves don't read archives.

class Entry:
	var path: String
	var title: String
	var core: String
	var system: String

	func _init(p: String, c: String) -> void:
		path = p
		core = c
		system = CoreRegistry.CORES[c].system
		title = p.get_file().get_basename()

	## A core started without content ("live:<core>", see scan).
	func is_no_content() -> bool:
		return path.begins_with(NO_CONTENT_PREFIX)


## Path of a core's no-content entry: stable, so recents and favourites can
## hold it like any file.
const NO_CONTENT_PREFIX := "live:"


var entries: Array[Entry] = []


## roots: [{"path": String, "core": String (optional)}]. A root with a core
## maps every file in it to that core (e.g. a folder of DVD ISOs, whose .iso
## would otherwise be ambiguous with Sega CD).
func scan(roots: Array) -> void:
	entries.clear()
	for r in roots:
		var root: String = r.path
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		var forced: String = r.get("core", "")
		if forced != "":
			_scan_files(root, forced)
			continue
		_scan_files(root, "")
		for sub in dir.get_directories():
			var core := CoreRegistry.core_for_folder(sub)
			if core != "":
				_scan_files(root.path_join(sub), core)
	# Cores that play without content (X-Streemly's lineup) are always listed.
	for core in CoreRegistry.CORES:
		var label: String = CoreRegistry.CORES[core].get("no_content", "")
		if label != "":
			var e := Entry.new(NO_CONTENT_PREFIX + core, core)
			e.title = label
			entries.append(e)
	entries.sort_custom(func(a: Entry, b: Entry): return a.title.naturalnocasecmp_to(b.title) < 0)


func _scan_files(dir_path: String, folder_core: String) -> void:
	for f in DirAccess.get_files_at(dir_path):
		var path := dir_path.path_join(f)
		var core := ""
		if f.get_extension().to_lower() == "zip":
			core = folder_core  # trust the folder; contents are checked at launch
		else:
			core = CoreRegistry.core_for_file(path, folder_core)
		if core != "":
			entries.append(Entry.new(path, core))


func systems() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		if not e.system in out:
			out.append(e.system)
	return out


func by_system(system: String) -> Array[Entry]:
	return entries.filter(func(e: Entry): return e.system == system)


## Path to hand the core: the file itself, or for a zip the first member the
## core accepts, extracted into temp_dir. Returns "" if nothing usable.
static func resolve_launch_path(entry: Entry, temp_dir: String) -> String:
	if entry.is_no_content():
		return ""
	if entry.path.get_extension().to_lower() != "zip":
		return entry.path
	var zip := ZIPReader.new()
	if zip.open(entry.path) != OK:
		push_warning("VRT: cannot open zip %s" % entry.path)
		return ""
	for member in zip.get_files():
		if CoreRegistry.accepts(entry.core, member):
			DirAccess.make_dir_recursive_absolute(temp_dir)
			var out_path := temp_dir.path_join(member.get_file())
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			if f == null:
				break
			f.store_buffer(zip.read_file(member))
			f.close()
			zip.close()
			return out_path
	zip.close()
	push_warning("VRT: no %s content in %s" % [entry.core, entry.path])
	return ""
