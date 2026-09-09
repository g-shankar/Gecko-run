extends Node3D
## Gecko Run — chase camera rig, gray-box prototype (spec §8).
##
## LEARNING NOTES (for Gowrishankar):
## - The rig itself never rotates; every frame it glides toward a point above
##   the gecko, and the Camera3D re-aims with look_at(). Keeping position and
##   aim separate makes wall-banking (P6) easy later: we will roll the rig
##   without touching the follow logic.
## - Collision avoidance comes from SpringArm3D: it casts a ray along +Z and
##   pulls the camera in when a wall is in the way, so the view never clips
##   through geometry. (P4 acceptance: "never clips through a test wall.")
## - FOV kick on dash (70 -> 82) arrives with dash in P8.

## --- Tuning (spec §8). All exported: no magic numbers below. ---
@export var target: Node3D            ## The gecko to follow. Auto-discovered via the
                                 ## "gecko" group when left unset (see _ready).
@export var follow_height: float = 1.4 ## Camera height above the gecko (m).
@export var follow_back: float = 2.2  ## Resting distance behind the gecko (m).
@export var follow_speed: float = 8.0 ## Higher = tighter/snappier follow.
@export var look_ahead: float = 2.0   ## Aim point this far ahead of the gecko (m).
@export var look_height: float = 0.5  ## Aim point height above the gecko (m).
@export var arm_margin: float = 0.25  ## SpringArm safety margin (m).
@export var bank_speed: float = 6.0 ## How fast the camera rolls when the gecko
                                 ## adheres to a wall (higher = snappier).

@onready var _boom: SpringArm3D = $Boom
@onready var _camera: Camera3D = $Boom/Camera3D

## P6: the camera's smoothed up-vector. Normally world-up; rolls toward the
## wall normal while the gecko is adhered so the wall reads as "ground".
var _bank_up := Vector3.UP


func _ready() -> void:
	# Auto-discover the gecko when no explicit target was assigned.
	# (A NodePath override written on an instanced scene does not reliably
	# resolve in Godot 4, so the gecko registers itself in the "gecko"
	# group instead -- see gecko.tscn. The exported target still wins when
	# someone wires it manually, e.g. in the editor.)
	if target == null:
		target = get_tree().get_first_node_in_group("gecko") as Node3D
	_boom.spring_length = follow_back
	_boom.margin = arm_margin
	if target != null:
		# The ray starts inside the gecko: exclude it so the arm ignores the player.
		_boom.add_excluded_object(target.get_rid())
		# Snap into place on spawn — no opening swoop.
		global_position = target.global_position + Vector3(0.0, follow_height, 0.0)
	else:
		push_warning("CameraRig: no target found; camera will not follow.")


func _process(delta: float) -> void:
	if target == null:
		return
	# P6: roll the camera's up-vector toward the gecko's up_direction. On the
	# floor that's world-up (no visible change); on a wall it becomes the wall
	# normal, so the wall reads as ground. Exponential blend = no snap.
	var up_target := Vector3.UP
	if target is CharacterBody3D:
		up_target = (target as CharacterBody3D).up_direction
	_bank_up = _bank_up.lerp(up_target, 1.0 - exp(-bank_speed * delta)).normalized()
	# Glide toward the follow point, measured along the (possibly banked) up.
	var desired: Vector3 = target.global_position + _bank_up * follow_height
	var blend: float = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, blend)
	# Aim along the gecko's own frame: forward = -basis.z, up = basis.y. On
	# the floor that's down-track; on a wall that's up the surface.
	var basis: Basis = target.global_transform.basis
	var aim: Vector3 = (target.global_position
		- basis.z * look_ahead
		+ basis.y * look_height)
	_camera.look_at(aim, _bank_up)
	# P8: FOV kick on dash (70 -> 82). Eased, so it punches in and relaxes out.
	var fov_target := 70.0
	if target.get("stat_state") == "DASH":
		fov_target = 82.0
	_camera.fov = lerpf(_camera.fov, fov_target, 1.0 - exp(-10.0 * delta))
