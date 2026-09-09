extends Area3D
class_name BugPickup
## Gecko Run — bug pickup (spec: the coin-collect loop).
##
## A glowing bug hovers and bobs. Touch it: +10 points, bug counter++.
## Bugs are placed in lines and arcs along the route — the "just one more"
## trail that pulls the player forward. Like Subway Surfers coins, but
## crunchier.
##
## LEARNING NOTES (for Gowrishankar):
## - Area3D + body_entered: same pattern as hazards, but instead of
##   killing, it rewards. The level spawns these from LevelData.
## - queue_free() after collection: the bug is gone. One-shot by nature.

signal collected

var _mesh: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _base_y: float = 0.0
var _bob_phase: float = 0.0
var _collected: bool = false


func _ready() -> void:
	add_to_group("bug") ## P27: the tongue finds bugs through this group.
	_build()
	_base_y = position.y
	_bob_phase = randf() * TAU
	body_entered.connect(_on_body_entered)


func _build() -> void:
	# Hit zone: generous so it feels good on mobile.
	var zone := CollisionShape3D.new()
	var zone_shape := SphereShape3D.new()
	zone_shape.radius = 0.6
	zone.shape = zone_shape
	add_child(zone)
	# The bug: a small emissive sphere (firefly).
	_mesh = MeshInstance3D.new()
	var bug_mesh := SphereMesh.new()
	bug_mesh.radius = 0.18
	bug_mesh.height = 0.36
	_mesh.mesh = bug_mesh
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(1.0, 0.85, 0.2, 1.0) # Golden.
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.75, 0.15, 1.0)
	_glow_mat.emission_energy_multiplier = 2.0
	_mesh.material_override = _glow_mat
	add_child(_mesh)
	# Wings: two tiny translucent planes.
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := PlaneMesh.new()
		wing_mesh.size = Vector2(0.25, 0.15)
		wing.mesh = wing_mesh
		var wing_mat := StandardMaterial3D.new()
		wing_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.4)
		wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wing.material_override = wing_mat
		wing.position = Vector3(side * 0.2, 0.1, 0)
		wing.rotation.z = side * 0.4
		wing.name = "Wing"
		add_child(wing)


func _process(delta: float) -> void:
	if _collected:
		return
	# Bob and spin: alive, noticeable, collectible.
	_bob_phase += delta * 3.0
	position.y = _base_y + sin(_bob_phase) * 0.15
	rotation.y += delta * 2.0


func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if not body.is_in_group("gecko"):
		return
	_collect(Color(0.4, 1.0, 0.3)) ## P22: green pop.


## P27: eat this bug without touching it — the super tongue's path. Same
## reward as walking into it, so the tongue is never a worse deal.
func collect_remote() -> void:
	_collect(Color(1.0, 0.45, 0.3)) ## Tongue-red pop.


func _collect(burst_color: Color) -> void:
	if _collected:
		return
	_collected = true
	collected.emit()
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs != null and gs.has_method("collect_bug"):
		gs.collect_bug()
	FX.burst(get_tree().root, global_position, burst_color)
	queue_free()
