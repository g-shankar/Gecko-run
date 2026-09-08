extends CharacterBody3D
## Gecko Run — player controller, gray-box prototype.
##
## LEARNING NOTES (for Gowrishankar):
## - This script extends CharacterBody3D: Godot's physics body made for
##   player-style movement. It gives us `velocity`, `move_and_slide()` and
##   floor detection (`is_on_floor()`) for free.
## - "Forward" is -Z (Godot convention). The gecko ALWAYS runs forward on its
##   own; the player only steers left/right. That is the auto-runner feel.
## - Every tunable number is an @export var, so you can tweak it live in the
##   editor Inspector without touching code. (Spec §7: no magic numbers.)
##
## PROMPT HISTORY: P2 = run + steer. P3 = jump (+coyote/buffer). P5-P7 = wall
## adhesion. P8 = dash. STUNNED/DEAD arrive with hazards (P10+).

## --- Tuning (spec §7) -------------------------------------------------------
@export var run_speed: float = 5.0     ## Constant auto-forward speed (m/s).
@export var steer_speed: float = 3.2   ## Top sideways speed (m/s).
@export var steer_accel: float = 18.0  ## How snappy steering feels (m/s^2).
@export var gravity: float = 22.0      ## Snappier than Earth's 9.8: arcade feel.

## --- State ------------------------------------------------------------------
## Full state list from spec §7; only RUN/AIR are used so far.
enum MoveState { RUN, AIR, ADHERE_WALL, ADHERE_CEILING, DASH, STUNNED, DEAD }
var state: MoveState = MoveState.RUN


func _ready() -> void:
	_ensure_input_actions()


func _physics_process(delta: float) -> void:
	_update_state()
	match state:
		MoveState.RUN, MoveState.AIR:
			_apply_run_movement(delta)
		_:
			pass # ADHERE_*, DASH, STUNNED, DEAD arrive in later prompts.
	move_and_slide()


## is_on_floor() reflects the LAST move_and_slide() call — the standard pattern.
func _update_state() -> void:
	state = MoveState.RUN if is_on_floor() else MoveState.AIR


func _apply_run_movement(delta: float) -> void:
	# 1. Steering: input as -1 (left) .. +1 (right); ease sideways velocity
	#    toward the target instead of snapping — that easing IS the feel.
	var steer_input: float = Input.get_axis("steer_left", "steer_right")
	var target_lateral: float = steer_input * steer_speed
	velocity.x = move_toward(velocity.x, target_lateral, steer_accel * delta)

	# 2. Auto-forward: constant speed, always -Z. The player never controls this.
	velocity.z = -run_speed

	# 3. Gravity: keeps the gecko planted; lets it leave the ground when jumping.
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0 # Landed (or never left): don't pile up downward speed.


## Defines our custom input actions on first run, so the prototype works on any
## machine without hand-editing project.godot. (P3 adds "jump" here.)
func _ensure_input_actions() -> void:
	_add_key_action(&"steer_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"steer_right", [KEY_D, KEY_RIGHT])


func _add_key_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
