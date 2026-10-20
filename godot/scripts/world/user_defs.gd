class_name UserDefs
extends RefCounted
## JSON definitions users can add without rebuilding VRT (TV types, rooms):
## bundled ones in res://<kind>, plus the same folder name under /sdcard/VRT,
## the app's own files dir on Quest, and user:// elsewhere. A user file with
## the same "id" as a bundled one replaces it. Each result gets "dir" (for
## relative paths such as models), sorted by "order".


static func load_all(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dirs := ["res://" + kind, "user://" + kind]
	if OS.get_name() == "Android":
		dirs.append("/sdcard/VRT/" + kind)
		dirs.append("/sdcard/Android/data/%s/files/%s" % [VrtSettings.PKG, kind])
	for d in dirs:
		if not d.begins_with("res://") and not DirAccess.dir_exists_absolute(d):
			continue  # optional user folder
		for f in DirAccess.get_files_at(d):
			if f.get_extension().to_lower() != "json":
				continue
			var path: String = d.path_join(f)
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary or not data.has("id"):
				push_warning("VRT: not a %s definition: %s" % [kind, path])
				continue
			data.dir = d
			data.short_name = str(data.get("short_name", data.get("name", data.id))).left(12).to_upper()
			var replaced := false
			for i in out.size():
				if out[i].id == data.id:
					out[i] = data
					replaced = true
			if not replaced:
				out.append(data)
	out.sort_custom(func(a, b): return a.get("order", 100) < b.get("order", 100))
	return out


static func find(defs: Array[Dictionary], id: String, fallback_id: String) -> Dictionary:
	for d in defs:
		if d.id == id:
			return d
	for d in defs:
		if d.id == fallback_id:
			return d
	return defs[0] if not defs.is_empty() else {}


static func index_of(defs: Array[Dictionary], id: String) -> int:
	for i in defs.size():
		if defs[i].id == id:
			return i
	return 0


static func v3(a, fallback: Vector3) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else fallback


## Load a glTF scene from disk at runtime (null on failure).
static func load_gltf(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("VRT: model failed to load: " + path)
		return null
	return doc.generate_scene(state) as Node3D
