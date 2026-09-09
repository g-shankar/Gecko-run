extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — dog hazard (spec P28).
##
## A big golden retriever lies beside the route. IDLE: it lounges (breathing
## bob) and waits — it only stirs when the gecko enters its trigger radius
## (~10 m). TELEGRAPH (0.8 s): BARK — a red "!" pops above its head, it rears
## up (wind-up) and locks onto the gecko's lane. ACTIVE: it LUNGES at the
## gecko — sideways to the locked lane and forward to meet the runner —
## the hitbox is live only here. RECOVERY: it settles back to rest.
##
## Fairness: the "!" + wind-up always precede the hitbox; the lunge target is
## locked at telegraph start, so steering to the far lane dodges it.

@export var trigger_radius: float = 10.0 ## P28: the dog only stirs this close.
## ~0.8 s telegraph at 9 m/s covers ~7 m, so the bark must start ~10 m out
## for the lunge to meet a running gecko. (Spec said ~6 m; 6 m whiffs —
## the gecko is already past the dog before the lunge lands.)
@export var windup_height: float = 0.35 ## How high the dog rears in telegraph.
@export var lunge_forward: float = 3.5 ## How far (m) the lunge reaches back
## toward the incoming gecko (+z). The dog leaps AT the gecko, not just
## sideways — the dodge is to leave the locked lane during the bark.

var _rest_pos: Vector3
var _target_pos: Vector3
var _dog: Node3D ## P28: Tripo golden-retriever model wrapper (or primitive).
var _bark: Label3D ## BARK warning: red "!" above the head.
var _breath_t: float = 0.0


func _ready() -> void:
	idle_time = 0.4 # Re-check the trigger radius this often.
	warn_time = 0.8 # The BARK dodge window.
	active_time = 0.45 # The lunge is quick.
	recovery_time = 1.2
	one_shot = false
	_rest_pos = position
	_target_pos = _rest_pos
	_build()
	super._ready()


func _build() -> void:
	# Hit zone: the dog's head/paws when it lunges. Small and tight — the
	# dodge is "don't be in that lane", not "thread a needle".
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(1.3, 1.1, 1.7)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.55, 0.2)
	add_child(zone)
	# Dog visual: P28 Tripo golden retriever (lying down). Primitive lying
	# dog if the GLB is missing.
	_dog = Node3D.new()
	_dog.name = "DogVisual"
	add_child(_dog)
	var model := ModelSwap.make_visual("dog", 1.3)
	if model == null:
		_build_primitive_dog()
	else:
		_dog.add_child(model)
	_face_track()
	# BARK icon: a red "!" billboard above the head. The warning.
	_bark = Label3D.new()
	_bark.text = "!"
	_bark.font_size = 96
	_bark.modulate = Color(1.0, 0.15, 0.1, 1.0)
	_bark.outline_size = 12
	_bark.outline_modulate = Color(1, 1, 1, 1)
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.position = Vector3(0, 1.7, 0)
	_bark.visible = false
	add_child(_bark)


## Face the track so the lunge reads as "at the gecko", not sideways.
func _face_track() -> void:
	# Model native orientation is checked visually at import (see P28
	# screenshots); the primitive is built facing -Z.
	_dog.rotation.y = -PI / 2.0 if _rest_pos.x > 0.0 else PI / 2.0


## The old primitive dog, kept as a fallback if the model is missing.
func _build_primitive_dog() -> void:
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.85, 0.65, 0.35, 1.0) # Golden coat.
	fur.roughness = 0.95
	# Body: long box low to the ground.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.55, 0.45, 1.1)
	body.mesh = body_mesh
	body.material_override = fur
	body.position = Vector3(0, 0.28, 0)
	_dog.add_child(body)
	# Head: box with a snout, held up and alert.
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.4, 0.38, 0.42)
	head.mesh = head_mesh
	head.material_override = fur
	head.position = Vector3(0, 0.62, -0.62)
	_dog.add_child(head)
	var snout := MeshInstance3D.new()
	var snout_mesh := BoxMesh.new()
	snout_mesh.size = Vector3(0.22, 0.2, 0.28)
	snout.mesh = snout_mesh
	snout.material_override = fur
	snout.position = Vector3(0, 0.55, -0.92)
	_dog.add_child(snout)
	# Ears: two floppy boxes.
	for ex in [-0.2, 0.2]:
		var ear := MeshInstance3D.new()
		var ear_mesh := BoxMesh.new()
		ear_mesh.size = Vector3(0.12, 0.28, 0.1)
		ear.mesh = ear_mesh
		ear.material_override = fur
		ear.position = Vector3(ex, 0.72, -0.55)
		_dog.add_child(ear)
	# Tail: curled at the back.
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.16, 0.16, 0.45)
	tail.mesh = tail_mesh
	tail.material_override = fur
	tail.position = Vector3(0, 0.35, 0.68)
	tail.rotation_degrees.x = -25.0
	_dog.add_child(tail)


## P28: the dog only starts its cycle when the gecko is in range. Without
## this, the base machine would telegraph on a timer at a gecko 50 m away.
func _advance() -> void:
	if phase == Phase.IDLE and not _gecko_in_range():
		_enter_phase(Phase.IDLE) # Stay lounging; re-check next tick.
		return
	super._advance()


func _gecko_in_range() -> bool:
	var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
	if gecko == null:
		return false
	return gecko.global_position.distance_to(global_position) < trigger_radius


func _on_idle() -> void:
	_bark.visible = false
	_target_pos = _rest_pos


func _on_telegraph() -> void:
	# Lock onto the gecko's lane NOW — the dodge is to leave it. The lunge
	# also reaches back toward the incoming gecko (+z) so it meets a runner.
	var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
	var gx: float = _rest_pos.x
	if gecko != null:
		gx = clampf(gecko.global_position.x, -3.0, 3.0)
	_target_pos = Vector3(gx, 0, _rest_pos.z + lunge_forward)
	_bark.visible = true


func _on_activate() -> void:
	pass # The lunge runs in _tick_phase; hitbox is live via the base.


func _on_recover() -> void:
	_bark.visible = false


func _tick_phase(delta: float) -> void:
	_breath_t += delta
	match phase:
		Phase.IDLE:
			# Lounging: gentle breathing bob at the rest spot.
			_dog.position.y = 0.02 * sin(_breath_t * 2.5)
			_dog.rotation.z = 0.02 * sin(_breath_t * 2.5)
			position.x = lerpf(position.x, _rest_pos.x, 0.15)
			position.z = lerpf(position.z, _rest_pos.z, 0.15)
		Phase.TELEGRAPH:
			var t: float = 1.0 - (_phase_timer / warn_time)
			# BARK wind-up: the dog rears up, the "!" pulses.
			_dog.position.y = lerpf(0.0, windup_height, t)
			_dog.rotation.z = lerpf(0.0, -0.08, t)
			var pulse: float = 1.0 + 0.18 * sin(t * 20.0)
			_bark.scale = Vector3(pulse, pulse, pulse)
		Phase.ACTIVE:
			var t: float = 1.0 - (_phase_timer / active_time)
			# LUNGE: snap toward the locked lane AND back toward the incoming
			# gecko (fast ease-out), then hold. The hitbox rides along.
			var k: float = clampf(t / 0.45, 0.0, 1.0)
			var e: float = 1.0 - pow(1.0 - k, 3.0)
			position.x = lerpf(_rest_pos.x, _target_pos.x, e)
			position.z = lerpf(_rest_pos.z, _target_pos.z, e)
			_dog.position.y = lerpf(windup_height, 0.05, k)
		Phase.RECOVERY:
			var t: float = 1.0 - (_phase_timer / recovery_time)
			# Settle back to the rest spot.
			position.x = lerpf(_target_pos.x, _rest_pos.x, t)
			position.z = lerpf(_target_pos.z, _rest_pos.z, t)
			_dog.position.y = lerpf(0.05, 0.0, t)
			_dog.rotation.z = lerpf(-0.08, 0.0, t)
