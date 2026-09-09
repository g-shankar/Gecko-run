extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — sprinkler hazard (spec P10, the missing 5th hazard).
##
## A pop-up lawn sprinkler. TELEGRAPH: the head pops up with a warning
## sputter (dodge window). ACTIVE: a fan of water sweeps side-to-side —
## time your run through the gap or steer around. RECOVERY: it retracts.
## It's a looper (one_shot=false): the lawn is always thirsty.
##
## The water fan is the hit zone. The sweep is sinusoidal so the pattern
## is readable: the water is always where the fan points.

@export var pop_height: float = 0.45 ## Head pop-up height (m).
@export var sweep_degrees: float = 70.0 ## Fan sweep arc (degrees).
@export var sweep_speed: float = 2.2 ## Oscillations per second during ACTIVE.
@export var fan_length: float = 4.0 ## How far the water reaches (m).
@export var fan_width: float = 0.7 ## Water fan thickness (m).

var _base: MeshInstance3D
var _head: Node3D ## P25: was MeshInstance3D; now a model wrapper (or primitive fallback).
var _fan_pivot: Node3D ## P29: the sweep pivot; carries the droplet spray.
var _spray: GPUParticles3D ## P29: real arcing water droplets (was a glass slab).
var _sputter: MeshInstance3D
var _sweep_phase: float = 0.0


func _ready() -> void:
	_build()
	super._ready()


func _build() -> void:
	# Hit zone: the fan area at gecko height. The fan pivots, so the zone
	# is a wide box covering the full sweep.
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	var sweep_rad: float = deg_to_rad(sweep_degrees)
	var sweep_span: float = fan_length * sin(sweep_rad * 0.5) * 2.0
	zone_shape.size = Vector3(sweep_span + 0.6, 1.2, fan_length + 0.6)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.6, -fan_length * 0.5)
	add_child(zone)
	# Base housing: dark cylinder flush with the lawn.
	_base = MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.22
	base_mesh.bottom_radius = 0.25
	base_mesh.height = 0.18
	_base.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.15, 0.15, 0.16, 1.0)
	base_mat.roughness = 0.7
	_base.material_override = base_mat
	_base.position = Vector3(0, 0.09, 0)
	add_child(_base)
	# Pop-up head: green plastic nozzle.
	_head = MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.13
	head_mesh.bottom_radius = 0.15
	head_mesh.height = 0.35
	(_head as MeshInstance3D).mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.2, 0.55, 0.25, 1.0) # Sprinkler green.
	head_mat.roughness = 0.5
	(_head as MeshInstance3D).material_override = head_mat
	_head.position = Vector3(0, 0.05, 0) # Retracted.
	add_child(_head)
	_swap_head_model() # P25: real sprinkler model; primitive stays on failure.
	# Water spray: real arcing droplets from the nozzle. The pivot sweeps;
	# the droplets live in global space so the arc reads as a fan.
	_fan_pivot = Node3D.new()
	_fan_pivot.name = "FanPivot"
	_fan_pivot.position = Vector3(0, pop_height + 0.25, 0)
	add_child(_fan_pivot)
	_spray = GPUParticles3D.new()
	_spray.name = "Spray"
	_spray.amount = 220
	_spray.lifetime = 0.8
	_spray.local_coords = false
	_spray.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 0.42, -1) # Up-and-out: the arc.
	pm.spread = 13.0
	pm.initial_velocity_min = 4.2
	pm.initial_velocity_max = 6.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	_spray.process_material = pm
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.55, 0.8, 1.0, 0.85)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = drop_mat
	_spray.draw_pass_1 = drop
	_fan_pivot.add_child(_spray)
	# Telegraph sputter: small white puff above the head.
	_sputter = MeshInstance3D.new()
	var sput_mesh := SphereMesh.new()
	sput_mesh.radius = 0.18
	sput_mesh.height = 0.36
	_sputter.mesh = sput_mesh
	var sput_mat := StandardMaterial3D.new()
	sput_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.0)
	sput_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sput_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sputter.material_override = sput_mat
	_sputter.position = Vector3(0, pop_height + 0.2, 0)
	_sputter.visible = false
	add_child(_sputter)


## P25: replace the primitive pop-up head with the Tripo sprinkler model.
## The pop-up animation targets _head.position.y, which works on the wrapper.
## Hit zone, fan telegraph, and timings are untouched.
func _swap_head_model() -> void:
	var model := ModelSwap.make_visual_by_height("sprinkler", 0.55)
	if model == null:
		return
	model.position = _head.position
	_head.queue_free()
	_head = model
	add_child(_head)


func _on_telegraph() -> void:
	_sputter.visible = true
	_sweep_phase = 0.0


func _on_activate() -> void:
	_spray.emitting = true
	_sputter.visible = false


func _on_recover() -> void:
	pass # Spray winds down in _tick_phase (pressure drop at t >= 0.4).


func _on_idle() -> void:
	_spray.emitting = false
	_sputter.visible = false


func _tick_phase(delta: float) -> void:
	match phase:
		Phase.TELEGRAPH:
			var t: float = 1.0 - (_phase_timer / warn_time)
			# Head pops up; sputter puffs and fades.
			_head.position.y = lerpf(0.05, pop_height, t)
			_sputter.visible = true
			var sput_mat := _sputter.material_override as StandardMaterial3D
			sput_mat.albedo_color.a = 0.5 * absf(sin(t * 12.0))
			var s: float = lerpf(0.5, 1.2, t)
			_sputter.scale = Vector3(s, s, s)
		Phase.ACTIVE:
			# Full pressure: head stays up, spray sweeps sinusoidally.
			_head.position.y = pop_height
			_sweep_phase += delta * sweep_speed * TAU
			var ang: float = sin(_sweep_phase) * deg_to_rad(sweep_degrees * 0.5)
			_fan_pivot.rotation.y = ang
		Phase.RECOVERY:
			var t: float = 1.0 - (_phase_timer / recovery_time)
			# Pressure drops: spray stops, head retracts.
			if t >= 0.4:
				_spray.emitting = false
			_head.position.y = lerpf(pop_height, 0.05, t)
		Phase.IDLE:
			_head.position.y = lerpf(_head.position.y, 0.05, 0.2)
