class_name Room
extends Node3D
## The empty VR room: walls, floor and a TV stand, lit only by the CRT
## (shaders/room_lit.gdshader) plus a dim ambient.

const SIZE := Vector3(4.0, 2.8, 5.0)
const ROOM_SHADER := preload("res://shaders/room_lit.gdshader")
const STAND_TOP := 0.55

var floor_body := StaticBody3D.new()


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ROOM_SHADER
	var box := BoxMesh.new()
	box.size = SIZE
	box.flip_faces = true
	# Vertex density for the per-vertex screen light (~8 cm grid).
	box.subdivide_width = 48
	box.subdivide_height = 32
	box.subdivide_depth = 60
	var walls := MeshInstance3D.new()
	walls.mesh = box
	walls.material_override = mat
	walls.position = Vector3(0, SIZE.y / 2.0, -1.0)
	add_child(walls)

	floor_body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	add_child(floor_body)

	var stand := MeshInstance3D.new()
	var stand_mat := ShaderMaterial.new()
	stand_mat.shader = ROOM_SHADER
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(0.9, STAND_TOP, 0.5)
	stand_mesh.subdivide_width = 18
	stand_mesh.subdivide_height = 10
	stand_mesh.subdivide_depth = 10
	stand.mesh = stand_mesh
	stand.material_override = stand_mat
	stand.position = Vector3(0, STAND_TOP / 2.0, -1.6)
	add_child(stand)


func set_shown(shown: bool) -> void:
	visible = shown
	floor_body.collision_layer = (1 << 0) if shown else 0
