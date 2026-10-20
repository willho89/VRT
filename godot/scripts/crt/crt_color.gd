class_name CrtColor
extends RefCounted
## Phosphor primaries -> linear Rec.709/sRGB, from CIE xy chromaticities.
## Full drive on all three guns produces the profile's white point at Y = 1.
## No chromatic adaptation: a 9300 K set looks blue next to D65, as it should.

const XYZ_TO_REC709 := Basis(  # columns
	Vector3(3.2404542, -0.9692660, 0.0556434),
	Vector3(-1.5371385, 1.8760108, -0.2040259),
	Vector3(-0.4985314, 0.0415560, 1.0572252))


static func xy_to_xyz(xy: Vector2) -> Vector3:
	return Vector3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y)


static func phosphor_to_rec709(p: CrtProfile) -> Basis:
	var prim := Basis(xy_to_xyz(p.primary_r), xy_to_xyz(p.primary_g), xy_to_xyz(p.primary_b))
	var scale := prim.inverse() * xy_to_xyz(p.white_point)
	var rgb_to_xyz := Basis(prim.x * scale.x, prim.y * scale.y, prim.z * scale.z)
	return XYZ_TO_REC709 * rgb_to_xyz
