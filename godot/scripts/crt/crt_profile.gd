class_name CrtProfile
extends Resource
## Physical description of one CRT. Units: millimetres unless noted.
## Only one profile is active at a time; swapping one in rebuilds the tube.

enum MaskType { SLOT, DOT, APERTURE }
enum Curvature { SPHERICAL, CYLINDRICAL, FLAT }

@export var display_name := "CRT"

@export_group("Tube")
## Visible picture area (not the nominal diagonal).
@export var visible_size_mm := Vector2(508.0, 381.0)
@export var curvature := Curvature.SPHERICAL
## Radius of the faceplate. Consumer sets ~1.0-1.5 m (1R ~ diagonal).
@export var curvature_radius_mm := 1600.0
@export var corner_radius_mm := 18.0
## Faceplate glass between the outer surface and the phosphor layer.
@export var glass_thickness_mm := 12.0
@export var glass_ior := 1.52

@export_group("Mask")
@export var mask_type := MaskType.SLOT
## Horizontal distance between same-color phosphors (triad pitch). Real 27"
## sets are ~0.8 mm; slightly larger reads better in a headset.
@export var mask_pitch_mm := 1.0
## Slot/dot vertical period (slot masks: one slot + bridge).
@export var mask_vpitch_mm := 1.0
## Fraction of each phosphor period that is lit phosphor (rest is black matrix).
@export_range(0.1, 1.0) var phosphor_duty := 0.70
## Fraction of each slot period that is open slot (rest is bridge).
@export_range(0.1, 1.0) var slot_duty := 0.78

@export_group("Phosphors")
## CIE xy chromaticities of R, G, B (P22 consumer phosphors by default).
@export var primary_r := Vector2(0.625, 0.340)
@export var primary_g := Vector2(0.280, 0.595)
@export var primary_b := Vector2(0.155, 0.070)
@export var white_point := Vector2(0.2831, 0.2971)  # ~9300 K, typical Japanese TVs
## Light remaining one 60 Hz frame later, per channel (P22 green lingers).
@export var persistence := Vector3(0.02, 0.06, 0.01)
@export var peak_nits := 180.0

@export_group("Electron gun")
@export var gamma := 2.4
## Beam spot sigma in scanline heights, at black and at full drive.
@export var beam_sigma_dark := 0.13
@export var beam_sigma_bright := 0.25
## Horizontal spot sigma at black and full drive, in 1/320ths of the picture
## width (source pixels of a 320 px source). Keeps a CRT soft and lets bright
## detail bloom sideways, which still reads from across the room.
@export var beam_sigma_h := Vector2(0.25, 0.40)
## Per-channel convergence error at the screen corners, mm (R and B; G is reference).
@export var convergence_r_mm := Vector2(0.35, -0.2)
@export var convergence_b_mm := Vector2(-0.3, 0.25)

@export_group("Input")
## Connection the console uses; consumer TVs mostly saw composite or RF.
@export var default_input := SignalPresets.Connection.COMPOSITE

@export_group("Geometry")
## Fraction of the active picture hidden under the bezel on each axis.
@export var overscan := Vector2(0.06, 0.05)
## Residual pincushion (+) / barrel (-) after deflection correction.
@export var pincushion := 0.004

@export_group("Glass")
@export var glass_tint := Color(0.42, 0.44, 0.43)  # neutral-density faceplate
@export var glass_roughness := 0.06
## Diffuse glow scattered in the faceplate (halation).
@export var halation := 0.14
## Brightness at the picture corners relative to the centre (beam landing angle).
@export_range(0.0, 1.0) var corner_falloff := 0.78


## 25" mid-90s consumer TV/VCR combo (CabinetVcrCombo), slot mask.
static func vcr_combo_25() -> CrtProfile:
	var p := CrtProfile.new()
	p.display_name = "25\" TV/VCR combo (slot mask)"
	p.visible_size_mm = Vector2(500.0, 375.0)
	return p


static func generic_shadowmask_27() -> CrtProfile:
	var p := CrtProfile.new()
	p.display_name = "Generic 27\" consumer TV (slot mask)"
	return p


func size_m() -> Vector2:
	return visible_size_mm / 1000.0


## Build a profile from a TV type's JSON (see docs/tv-types.md). Unknown keys
## are ignored and missing ones keep the defaults above, so a definition only
## states what differs from a generic consumer set.
static func from_dict(d: Dictionary) -> CrtProfile:
	var p := CrtProfile.new()
	p.display_name = d.get("name", p.display_name)
	var tube: Dictionary = d.get("tube", {})
	p.visible_size_mm = _v2(tube.get("visible_mm"), p.visible_size_mm)
	p.curvature = {"spherical": Curvature.SPHERICAL, "cylindrical": Curvature.CYLINDRICAL,
			"flat": Curvature.FLAT}.get(tube.get("curvature", ""), p.curvature)
	p.curvature_radius_mm = tube.get("radius_mm", p.curvature_radius_mm)
	p.corner_radius_mm = tube.get("corner_radius_mm", p.corner_radius_mm)
	p.glass_thickness_mm = tube.get("glass_thickness_mm", p.glass_thickness_mm)
	var mask: Dictionary = d.get("mask", {})
	p.mask_type = {"slot": MaskType.SLOT, "dot": MaskType.DOT, "aperture": MaskType.APERTURE}.get(
			mask.get("type", ""), p.mask_type)
	p.mask_pitch_mm = mask.get("pitch_mm", p.mask_pitch_mm)
	p.mask_vpitch_mm = mask.get("vpitch_mm", mask.get("pitch_mm", p.mask_vpitch_mm))
	p.phosphor_duty = mask.get("phosphor_duty", p.phosphor_duty)
	p.slot_duty = mask.get("slot_duty", p.slot_duty)
	var ph: Dictionary = d.get("phosphors", {})
	p.primary_r = _v2(ph.get("red_xy"), p.primary_r)
	p.primary_g = _v2(ph.get("green_xy"), p.primary_g)
	p.primary_b = _v2(ph.get("blue_xy"), p.primary_b)
	p.white_point = _v2(ph.get("white_xy"), p.white_point)
	p.persistence = _v3(ph.get("persistence"), p.persistence)
	p.peak_nits = ph.get("peak_nits", p.peak_nits)
	var gun: Dictionary = d.get("gun", {})
	p.gamma = gun.get("gamma", p.gamma)
	var bs := _v2(gun.get("beam_sigma"), Vector2(p.beam_sigma_dark, p.beam_sigma_bright))
	p.beam_sigma_dark = bs.x
	p.beam_sigma_bright = bs.y
	p.beam_sigma_h = _v2(gun.get("beam_sigma_h"), p.beam_sigma_h)
	p.convergence_r_mm = _v2(gun.get("convergence_r_mm"), p.convergence_r_mm)
	p.convergence_b_mm = _v2(gun.get("convergence_b_mm"), p.convergence_b_mm)
	var geo: Dictionary = d.get("geometry", {})
	p.overscan = _v2(geo.get("overscan"), p.overscan)
	p.pincushion = geo.get("pincushion", p.pincushion)
	var glass: Dictionary = d.get("glass", {})
	if glass.has("tint"):
		p.glass_tint = Color(glass.tint)
	p.glass_roughness = glass.get("roughness", p.glass_roughness)
	p.halation = glass.get("halation", p.halation)
	p.corner_falloff = glass.get("corner_falloff", p.corner_falloff)
	p.default_input = {"rgb": SignalPresets.Connection.RGB, "svideo": SignalPresets.Connection.SVIDEO,
			"composite": SignalPresets.Connection.COMPOSITE, "rf": SignalPresets.Connection.RF}.get(
			d.get("default_input", ""), p.default_input)
	return p


static func _v2(a, fallback: Vector2) -> Vector2:
	return Vector2(a[0], a[1]) if a is Array and a.size() >= 2 else fallback


static func _v3(a, fallback: Vector3) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else fallback
