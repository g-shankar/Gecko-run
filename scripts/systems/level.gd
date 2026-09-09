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
	"speed": "res://scripts/systems/speed_pickup.gd",
	"footstep": "res://scripts/systems/footstep.gd",
	"bicycle": "res://scripts/systems/bicycle.gd",
	"bird": "res://scripts/systems/bird.gd",
	"car": "res://scripts/systems/car.gd",
	"sprinkler": "res://scripts/systems/sprinkler.gd",
	"bug": "res://scripts/systems/bug_pickup.gd",
	"dog": "res://scripts/systems/dog.gd",
	"mower": "res://scripts/systems/mower.gd",
}

const HAZARD_NAMES := {
	"shield": "ShieldPickup",
	"speed": "SpeedPickup",
	"footstep": "Footstep", # + A/B/C per instance.
	"bicycle": "Bicycle",
	"bird": "Bird",
	"car": "BackingCar",
	"sprinkler": "Sprinkler",
	"bug": "Bug",
	"dog": "Dog", # + A/B per instance.
	"mower": "Mower",
}

## P20: the pergola — the gecko-fantasy ceiling route. Two climbable posts
## hold a climbable slab; wall-running to a post top transitions onto the
## slab's underside (see gecko_controller._try_ceiling_transition).
const PERGOLA_Z := -16.0

@export var level_data: Resource ## A LevelData (level_data.gd). Null = default route.

var spawned: Array[Node3D] = [] ## Every hazard/pickup this level created.
var _type_counts := {} ## How many of each type spawned (for A/B names).


func _ready() -> void:
	add_to_group("level") ## P26: the frontend finds the level here.
	if level_data == null:
		var script: Script = load("res://scripts/systems/level_data.gd")
		level_data = script.new() # Default route: Backyard 1.
	_build_all()


## P26: swap the whole route at runtime (map select). Clears every spawned
## hazard plus the pergola/start-line build products, then rebuilds from
## the new route script. Collision, spawn and timing logic are untouched —
## only WHICH route data feeds them changes.
func load_route(route_script: String) -> void:
	_clear_route()
	var script: Script = load(route_script)
	if script == null:
		push_warning("Level: unknown route script '%s'." % route_script)
		return
	level_data = script.new()
	_build_all()


## P26: tear down a built route. Immediate free() (not queue_free) so a
## same-frame rebuild never sees stale siblings or duplicate node names.
## Called from UI context, never from inside physics — safe.
func _clear_route() -> void:
	for h in spawned:
		if is_instance_valid(h):
			h.free()
	spawned.clear()
	_type_counts.clear()
	for n in ["Pergola", "StartLine"]:
		var old := get_node_or_null(n)
		if old != null:
			old.free()


func _build_all() -> void:
	_build_start_line()
	for spawn in (level_data.get("spawns") as Array):
		_spawn_hazard(spawn)
	_build_ceiling_route() ## P20: pergola with the climbable ceiling.
	_place_fence() ## P21: the fence stands at the route's end.
	_stretch_ground() ## P21: the visual ground must cover the long route.
	_repaint_pergola() ## P26: re-apply the wood skin after a rebuild.
	_refresh_driveway() ## P29: wet driveway only on Backyard Dash.


## P29: route swaps reuse the same BackyardArt node; the wet driveway must
## hide when the player switches to Fence Line mid-session.
func _refresh_driveway() -> void:
	var art := get_parent().get_node_or_null("BackyardArt")
	if art != null and art.has_method("refresh_driveway_for_map"):
		art.refresh_driveway_for_map()


## P26: BackyardArt paints the pergola once at startup; after a route swap
## the new pergola needs the same treatment.
func _repaint_pergola() -> void:
	var art := get_parent().get_node_or_null("BackyardArt")
	if art != null and art.has_method("paint_pergola"):
		art.paint_pergola()


## P21: the fence is the finish gate — park it at the data's fence_z.
func _place_fence() -> void:
	var fence := get_parent().get_node_or_null("Fence")
	if fence != null:
		(fence as Node3D).position.z = float(level_data.get("fence_z"))


## P21: the ground visual is a 120x120 plane; the long route needs more.
## Collision is an infinite WorldBoundaryShape3D, so only the visual moves.
func _stretch_ground() -> void:
	var ground := get_parent().get_node_or_null("Ground") as MeshInstance3D
	if ground != null and ground.mesh is PlaneMesh:
		var pm := ground.mesh as PlaneMesh
		pm.size = Vector2(120, 560)
		ground.position = Vector3(0, 0, -214) # Covers z +66 .. -494.


## P20: build the pergola — posts you climb, a slab underside you run on.
func _build_ceiling_route() -> void:
	var pergola := Node3D.new()
	pergola.name = "Pergola"
	add_child(pergola)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.roughness = 0.9
	pergola.add_child(_make_climbable_box(
		Vector3(0.4, 2.4, 0.4), Vector3(-2.2, 1.2, PERGOLA_Z), wood, "PergolaPostL"))
	pergola.add_child(_make_climbable_box(
		Vector3(0.4, 2.4, 0.4), Vector3(2.2, 1.2, PERGOLA_Z), wood, "PergolaPostR"))
	pergola.add_child(_make_climbable_box(
		Vector3(6.0, 0.3, 5.0), Vector3(0, 2.55, PERGOLA_Z), wood, "PergolaTop"))


## P20: a climbable StaticBody3D box (collision + mesh). The "climbable"
## group is what the gecko's feeler rays look for.
func _make_climbable_box(size: Vector3, pos: Vector3, mat: Material, box_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.add_to_group("climbable")
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	return body


func _spawn_hazard(spawn: Dictionary) -> void:
	var type: String = spawn.get("type", "")
	var script_path: String = HAZARD_SCRIPTS.get(type, "")
	if script_path == "":
		push_warning("Level: unknown hazard type '%s'." % type)
		return
	var hazard: Area3D = (load(script_path) as Script).new()
	hazard.position = spawn.get("pos", Vector3.ZERO)
	# P21: difficulty curve — the data can tighten a hazard's telegraph.
	if spawn.has("warn") and hazard is HazardBase:
		(hazard as HazardBase).warn_time = float(spawn["warn"])
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
