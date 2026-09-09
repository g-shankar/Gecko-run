extends Node3D
class_name Level
## Gecko Run — level builder (spec P13).
##
## Reads a LevelData and spawns the route: start line, hazards, fence.
## The route order tells a tiny story: grab the shield, dodge the shoe,
## cross the bike lane, watch the sky, dodge another shoe, respect the car,
## then climb the fence.

const HAZARD_SCRIPTS := {
	"shield": "res://scripts/systems/shield_pickup.gd",
	"footstep": "res://scripts/systems/footstep.gd",
	"bicycle": "res://scripts/systems/bicycle.gd",
	"bird": "res://scripts/systems/bird.gd",
	"car": "res://scripts/systems/car.gd",
	"sprinkler": "res://scripts/systems/sprinkler.gd",
	"bug": "res://scripts/systems/bug_pickup.gd",
}

const HAZARD_NAMES := {
	"shield": "ShieldPickup",
	"footstep": "Footstep", # + A/B/C per instance.
	"bicycle": "Bicycle",
	"bird": "Bird",
	"car": "BackingCar",
	"sprinkler": "Sprinkler",
	"bug": "Bug",
}

@export var level_data: Resource ## A LevelData (level_data.gd). Null = default route.

var spawned: Array[Node3D] = [] ## Every hazard/pickup this level created.
var _type_counts := {} ## How many of each type spawned (for A/B names).


func _ready() -> void:
	if level_data == null:
		var script: Script = load("res://scripts/systems/level_data.gd")
		level_data = script.new() # Default route: Backyard 1.
	_build_start_line()
	for spawn in (level_data.get("spawns") as Array):
		_spawn_hazard(spawn)


func _spawn_hazard(spawn: Dictionary) -> void:
	var type: String = spawn.get("type", "")
	var script_path: String = HAZARD_SCRIPTS.get(type, "")
	if script_path == "":
		push_warning("Level: unknown hazard type '%s'." % type)
		return
	var hazard: Area3D = (load(script_path) as Script).new()
	hazard.position = spawn.get("pos", Vector3.ZERO)
	# Stable names (FootstepA, Bicycle, ...) so tests and debuggers can
	# find them under Level/.
	var count: int = int(_type_counts.get(type, 0)) + 1
	_type_counts[type] = count
	var base_name: String = HAZARD_NAMES.get(type, type.capitalize())
	if count > 1 or type == "footstep":
		base_name += String.chr(64 + count) # A, B, C...
	hazard.name = base_name
	add_child(hazard)
	spawned.append(hazard)


## P13: a white start line across the track. "The run starts HERE."
func _build_start_line() -> void:
	var line := MeshInstance3D.new()
	var line_mesh := PlaneMesh.new()
	line_mesh.size = Vector2(8.0, 0.4)
	line.mesh = line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = line_mat
	line.position = Vector3(0, 0.02, (level_data.get("start_position") as Vector3).z)
	line.name = "StartLine"
	add_child(line)
