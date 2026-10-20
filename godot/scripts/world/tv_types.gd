class_name TvTypes
extends RefCounted
## TV types: one JSON file each (format in docs/tv-types.md), describing the
## set's name, cabinet (built-in, procedural box or a glTF model next to the
## JSON), tube size and shape, mask, phosphors, beam and glass.
##
## Looked for in res://tvs (bundled) and the user's folders (UserDefs), so new
## sets can be added without rebuilding: /sdcard/VRT/tvs on Quest.

const DEFAULT_ID := "vcr_combo_25"

var types: Array[Dictionary] = []   # parsed JSON + "dir" + "profile"


func load_all() -> void:
	types = UserDefs.load_all("tvs")
	for t in types:
		t.profile = CrtProfile.from_dict(t)
	print("VRT: TV types ", types.map(func(t): return t.id))


func find(id: String) -> Dictionary:
	return UserDefs.find(types, id, DEFAULT_ID)


func index_of(id: String) -> int:
	return UserDefs.index_of(types, id)


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
