extends Area3D
## Gecko Run — speed boost pickup (spec P19, the second power-up).
##
## A crackling orange orb. Touch it and the gecko gets 6 s of 1.5x speed
## with an FOV kick and a speed-trail visual. Re-arms 12 s after being
## taken, same rhythm as the shield pickup.

@export var rearm_time: float = 12.0
@export var boost_duration: float = 6.0

var _orb: MeshInstance3D
var _rearm_timer: float = 0.0
var _spin: float = 0.0


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)
	set_physics_process(true)


func _build() -> void:
	var zone := CollisionShape3D.new()
	var zone_shape := SphereShape3D.new()
	zone_shape.radius = 0.8
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.8, 0)
	add_child(zone)
	_orb = MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.35
	orb_mesh.height = 0.7
	_orb.mesh = orb_mesh
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(1.0, 0.55, 0.1, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.55, 0.1, 1.0)
	orb_mat.emission_energy_multiplier = 2.0
	_orb.material_override = orb_mat
	_orb.position = Vector3(0, 0.8, 0)
	add_child(_orb)


func _physics_process(delta: float) -> void:
	_spin += delta
	if _rearm_timer > 0.0:
		_rearm_timer -= delta
		if _rearm_timer <= 0.0:
			_orb.visible = true
		return
	# Bob and spin while waiting to be grabbed.
	_orb.position.y = 0.8 + sin(_spin * 3.5) * 0.12
	_orb.rotation.y = _spin * 3.0


func _on_body_entered(body: Node3D) -> void:
	if _rearm_timer > 0.0:
		return
	if body.is_in_group("gecko") and body.has_method("give_speed_boost"):
		body.give_speed_boost()
		_orb.visible = false
		_rearm_timer = rearm_time
