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
@export var curvature_radius_mm := 1100.0
@export var corner_radius_mm := 28.0
## Faceplate glass between the outer surface and the phosphor layer.
@export var glass_thickness_mm := 12.0
@export var glass_ior := 1.52

@export_group("Mask")
@export var mask_type := MaskType.SLOT
## Horizontal distance between same-color phosphors (triad pitch).
@export var mask_pitch_mm := 0.82
## Slot/dot vertical period (slot masks: one slot + bridge).
@export var mask_vpitch_mm := 0.82
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
@export var beam_sigma_dark := 0.20
@export var beam_sigma_bright := 0.33
## Horizontal spot sigma in source pixels (video bandwidth softness).
@export var beam_sigma_h := 0.45
## Per-channel convergence error at the screen corners, mm (R and B; G is reference).
@export var convergence_r_mm := Vector2(0.35, -0.2)
@export var convergence_b_mm := Vector2(-0.3, 0.25)

@export_group("Geometry")
## Fraction of the active picture hidden under the bezel on each axis.
@export var overscan := Vector2(0.06, 0.05)
## Residual pincushion (+) / barrel (-) after deflection correction.
@export var pincushion := 0.012

@export_group("Glass")
@export var glass_tint := Color(0.42, 0.44, 0.43)  # neutral-density faceplate
@export var glass_roughness := 0.06
## Diffuse glow scattered in the faceplate (halation).
@export var halation := 0.06


static func generic_shadowmask_27() -> CrtProfile:
	var p := CrtProfile.new()
	p.display_name = "Generic 27\" consumer TV (slot mask)"
	return p


func size_m() -> Vector2:
	return visible_size_mm / 1000.0
