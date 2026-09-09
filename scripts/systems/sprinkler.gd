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
var _head: MeshInstance3D
var _fan: MeshInstance3D
var _fan_mat: StandardMaterial3D
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
	_head.mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.2, 0.55, 0.25, 1.0) # Sprinkler green.
	head_mat.roughness = 0.5
	_head.material_override = head_mat
	_head.position = Vector3(0, 0.05, 0) # Retracted.
	add_child(_head)
	# Water fan: translucent blue box, pivots at the head.
	_fan = MeshInstance3D.new()
	var fan_mesh := BoxMesh.new()
	fan_mesh.size = Vector3(fan_width, 0.9, fan_length)
	_fan.mesh = fan_mesh
	_fan_mat = StandardMaterial3D.new()
	_fan_mat.albedo_color = Color(0.3, 0.65, 1.0, 0.0)
	_fan_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fan.material_override = _fan_mat
	# Pivot at the head: offset so rotation sweeps the fan.
	_fan.position = Vector3(0, pop_height + 0.45, -fan_length * 0.5)
	_fan.visible = false
	add_child(_fan)
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


func _on_telegraph() -> void:
	_sputter.visible = true
	_sweep_phase = 0.0


func _on_activate() -> void:
	_fan.visible = true
	_sputter.visible = false


func _on_recover() -> void:
	pass


func _on_idle() -> void:
	_fan.visible = false
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
			# Full pressure: head stays up, fan sweeps sinusoidally.
			_head.position.y = pop_height
			_sweep_phase += delta * sweep_speed * TAU
			var ang: float = sin(_sweep_phase) * deg_to_rad(sweep_degrees * 0.5)
			_fan.rotation.y = ang
			_fan_mat.albedo_color.a = 0.45
		Phase.RECOVERY:
			var t: float = 1.0 - (_phase_timer / recovery_time)
			# Pressure drops: fan fades, head retracts.
			_fan_mat.albedo_color.a = lerpf(0.45, 0.0, t)
			_head.position.y = lerpf(pop_height, 0.05, t)
			if t >= 1.0:
				_fan.visible = false
		Phase.IDLE:
			_head.position.y = lerpf(_head.position.y, 0.05, 0.2)
