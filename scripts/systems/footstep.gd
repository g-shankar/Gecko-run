extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — footstep hazard (spec P10).
##
## A giant shoe hovers, then: TELEGRAPH (a shadow grows on the ground at YOUR
## x position — move!) → ACTIVE (the shoe slams down) → RECOVERY (it lifts).
## The shadow locks onto your x when the telegraph starts, so standing still
## gets you squashed. Steering or dashing clear is the dodge.
##
## The node itself is placed in the editor; the shoe, shadow, and hit zone
## are built procedurally here so the .tscn stays machine-clean.

@export var hover_height: float = 3.0 ## Shoe hover height (m).
@export var shoe_size: Vector3 = Vector3(1.3, 0.9, 2.2)

var _shoe: Node3D ## P29: was a MeshInstance3D box; now a sneaker model wrapper.
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _home_x: float = 0.0
var _target_x: float = 0.0
var _slam_y: float = 0.0


func _ready() -> void:
	_home_x = position.x
	_slam_y = shoe_size.y * 0.5
	_build()
	super._ready()


func _build() -> void:
	# Hit zone: covers the shoe's footprint at ground level.
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(shoe_size.x + 0.3, 1.0, shoe_size.z + 0.3)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.5, 0)
	add_child(zone)
	# The shoe: a real sneaker (Tripo) fitted to the stomp footprint.
	# The slam animation targets _shoe.position, which works on the wrapper.
	_shoe = _fit_sneaker()
	if _shoe == null:
		_shoe = _shoe_box_fallback()
	else:
		# The wrapper's origin is the sole: slam to the ground, not to
		# half the box height (the fallback keeps the old math).
		_slam_y = 0.05
	_shoe.position = Vector3(0, hover_height, 0)
	add_child(_shoe)
	# The telegraph shadow: a dark ellipse on the ground.
	_shadow = MeshInstance3D.new()
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(shoe_size.x + 0.3, shoe_size.z + 0.3)
	_shadow.mesh = shadow_mesh
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_color = Color(0.05, 0.02, 0.02, 0.0)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = _shadow_mat
	_shadow.position = Vector3(0, 0.03, 0)
	_shadow.visible = false
	add_child(_shadow)


## P29: fit the Tripo sneaker to the stomp footprint (x=1.3 wide,
## z=2.2 long). Whichever horizontal axis is longest becomes the length
## (rotated onto Z); the base rests at the wrapper origin so the slam
## math (_slam_y etc.) is unchanged. Returns null if the GLB is missing.
func _fit_sneaker() -> Node3D:
	if not ModelSwap.MODELS.has("sneaker"):
		return null
	var spec: Dictionary = ModelSwap.MODELS["sneaker"]
	var packed: PackedScene = load(spec["path"])
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var size: Vector3 = spec["size"]
	var longest: float = maxf(size.x, size.z)
	if longest < 0.001:
		inst.queue_free()
		return null
	var s: float = shoe_size.z / longest
	var wrap := Node3D.new()
	wrap.name = "SneakerShoe"
	wrap.add_child(inst)
	inst.scale = Vector3.ONE * s
	inst.position.y = -float(spec["min_y"]) * s
	if size.x > size.z:
		# Length lies along X natively: rotate it onto Z.
		wrap.rotation.y = PI / 2.0
	return wrap


## P29 fallback: the old brown box if the sneaker GLB is missing.
func _shoe_box_fallback() -> Node3D:
	var box := MeshInstance3D.new()
	var shoe_mesh := BoxMesh.new()
	shoe_mesh.size = shoe_size
	box.mesh = shoe_mesh
	var shoe_mat := StandardMaterial3D.new()
	shoe_mat.albedo_color = Color(0.45, 0.28, 0.15, 1.0) # Leather brown.
	shoe_mat.roughness = 0.8
	box.material_override = shoe_mat
	return box


func _on_telegraph() -> void:
	# Lock onto the gecko's lane. This is the mind game: the shadow tells
	# you where it lands, and you have warn_time to not be there.
	var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
	if gecko != null:
		_target_x = clampf(gecko.global_position.x, -3.0, 3.0)
	else:
		_target_x = _home_x
	_shadow.visible = true


func _on_activate() -> void:
	# The slam happens in _tick_phase (fast ease-in). Nothing needed here.
	pass


func _on_recover() -> void:
	pass


func _on_idle() -> void:
	_shadow.visible = false
	_target_x = _home_x


func _tick_phase(_delta: float) -> void:
	match phase:
		Phase.TELEGRAPH:
			var t: float = 1.0 - (_phase_timer / warn_time)
			# Shadow grows and darkens; shoe slides to the target lane.
			var s: float = lerpf(0.3, 1.0, t)
			_shadow.scale = Vector3(s, 1.0, s)
			_shadow_mat.albedo_color.a = lerpf(0.0, 0.55, t)
			position.x = lerpf(_home_x, _target_x, t)
			_shoe.position = Vector3(0, hover_height, 0)
		Phase.ACTIVE:
			var t: float = 1.0 - (_phase_timer / active_time)
			# Slam: accelerate downward (t^2), so it reads as a STOMP.
			var y: float = lerpf(hover_height, _slam_y, t * t)
			_shoe.position = Vector3(0, y, 0)
			_shadow.scale = Vector3.ONE
			_shadow_mat.albedo_color.a = 0.55
		Phase.RECOVERY:
			var t: float = 1.0 - (_phase_timer / recovery_time)
			_shoe.position = Vector3(0, lerpf(_slam_y, hover_height, t), 0)
			_shadow_mat.albedo_color.a = lerpf(0.55, 0.0, t)
			if t >= 1.0:
				_shadow.visible = false
		Phase.IDLE:
			_shoe.position = Vector3(0, hover_height, 0)
			position.x = lerpf(position.x, _home_x, 0.1)
