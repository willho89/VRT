class_name TvTypes
extends RefCounted
## TV types: one JSON file each (format in docs/tv-types.md), describing the
## set's name, cabinet (built-in, procedural box or a glTF model next to the
## JSON), tube size and shape, mask, phosphors, beam and glass.
##
## Looked for in res://tvs (bundled) and the user's folders, so new sets can be
## added without rebuilding: /sdcard/VRT/tvs on Quest, user://tvs elsewhere. A
## user file with the same "id" as a bundled one replaces it.

const BUILTIN_DIR := "res://tvs"
const DEFAULT_ID := "vcr_combo_25"

var types: Array[Dictionary] = []   # parsed JSON + "dir" + "profile"


func load_all() -> void:
	types.clear()
	var dirs := [BUILTIN_DIR, "user://tvs"]
	if OS.get_name() == "Android":
		dirs.append("/sdcard/VRT/tvs")
		dirs.append("/sdcard/Android/data/%s/files/tvs" % VrtSettings.PKG)
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if f.get_extension().to_lower() == "json":
				_add(d, d.path_join(f))
	types.sort_custom(func(a, b): return a.get("order", 100) < b.get("order", 100))
	print("VRT: TV types ", types.map(func(t): return t.id))


func find(id: String) -> Dictionary:
	for t in types:
		if t.id == id:
			return t
	for t in types:
		if t.id == DEFAULT_ID:
			return t
	return types[0] if not types.is_empty() else {}


func index_of(id: String) -> int:
	for i in types.size():
		if types[i].id == id:
			return i
	return 0


## The cabinet node for a type: built-in, procedural box, or its glTF model
## (falling back to a box if the model will not load).
static func make_cabinet(t: Dictionary) -> Node3D:
	var cfg: Dictionary = t.get("cabinet", {})
	var p: CrtProfile = t.profile
	if cfg.has("model"):
		var m := CabinetModel.new(t.dir.path_join(cfg.model), cfg)
		if m.loaded:
			return m
	match cfg.get("builtin", "box"):
		"vcr_combo":
			return CabinetVcrCombo.new()
	return CabinetBox.new(p.size_m(), cfg)


func _add(dir: String, path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("id"):
		push_warning("VRT: not a TV type: " + path)
		return
	data.dir = dir
	data.profile = CrtProfile.from_dict(data)
	data.short_name = str(data.get("short_name", data.get("name", data.id))).left(12).to_upper()
	for i in types.size():
		if types[i].id == data.id:
			types[i] = data
			return
	types.append(data)
