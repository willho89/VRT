class_name TubeMesh
extends RefCounted
## Builds the faceplate surface for a CrtProfile: a curved grid whose UVs are
## the visible picture area (0..1, top-left origin) and which extends a little
## past it, as real glass does under the bezel. The phosphor mask is evaluated
## from UV * visible size, so UVs are kept proportional to arc length closely
## enough at consumer curvatures (sagitta of a few cm over half a metre).

const SEGMENTS := Vector2i(48, 36)
const MARGIN := 0.04  # glass beyond the picture on each side, fraction of size


static func build(p: CrtProfile) -> ArrayMesh:
	var size := p.size_m()
	var r := p.curvature_radius_mm / 1000.0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for j in SEGMENTS.y + 1:
		for i in SEGMENTS.x + 1:
			var uv := Vector2(float(i) / SEGMENTS.x, float(j) / SEGMENTS.y)
			uv = uv * (1.0 + 2.0 * MARGIN) - Vector2(MARGIN, MARGIN)
			var x := (uv.x - 0.5) * size.x
			var y := (0.5 - uv.y) * size.y
			var pos := Vector3(x, y, 0.0)
			var n := Vector3(0, 0, 1)
			match p.curvature:
				CrtProfile.Curvature.SPHERICAL:
					pos.z = sqrt(maxf(r * r - x * x - y * y, 0.0)) - r
					n = Vector3(x, y, pos.z + r).normalized()
				CrtProfile.Curvature.CYLINDRICAL:
					pos.z = sqrt(maxf(r * r - x * x, 0.0)) - r
					n = Vector3(x, 0, pos.z + r).normalized()
			verts.append(pos)
			normals.append(n)
			uvs.append(uv)

	var row := SEGMENTS.x + 1
	for j in SEGMENTS.y:
		for i in SEGMENTS.x:
			var a := j * row + i
			idx.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.regen_normal_maps()  # tangents for the parallax-through-glass offset
	return mesh


## Depth of the faceplate edge behind its centre (for placing the bezel).
static func edge_sag(p: CrtProfile) -> float:
	var r := p.curvature_radius_mm / 1000.0
	var half := p.size_m() * (0.5 + MARGIN)
	match p.curvature:
		CrtProfile.Curvature.SPHERICAL:
			return r - sqrt(maxf(r * r - half.length_squared(), 0.0))
		CrtProfile.Curvature.CYLINDRICAL:
			return r - sqrt(maxf(r * r - half.x * half.x, 0.0))
	return 0.0
