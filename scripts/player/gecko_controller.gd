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
## PROMPT HISTORY: P2 = run + steer. P3 = jump (+coyote/buffer). P4 = camera.
## P4.5 = touch controls (swipe steer, tap jump) for phone playtests.
## P5-P7 = wall adhesion. P8 = dash. STUNNED/DEAD arrive with hazards (P10+).

## --- Tuning (spec §7) -------------------------------------------------------
@export var run_speed: float = 5.0     ## Constant auto-forward speed (m/s).
@export var steer_speed: float = 3.2   ## Top sideways speed (m/s).
@export var steer_accel: float = 18.0  ## How snappy steering feels (m/s^2).
@export var gravity: float = 22.0      ## Snappier than Earth's 9.8: arcade feel.
@export var jump_velocity: float = 6.5 ## Takeoff speed (m/s). Peak height = v^2 / 2g.
@export var coyote_time: float = 0.12  ## Grace period to jump AFTER leaving a ledge.
@export var jump_buffer: float = 0.12  ## Remembers a press made just BEFORE landing.
@export var touch_steer_pixels: float = 120.0 ## Drag distance (px) for full steer.
@export var tap_max_time: float = 0.25  ## A press longer than this is not a tap.
@export var tap_max_dist: float = 24.0  ## Finger travel (px) beyond this is not a tap.

## --- State ------------------------------------------------------------------
## Full state list from spec §7; only RUN/AIR are used so far.
enum MoveState { RUN, AIR, ADHERE_WALL, ADHERE_CEILING, DASH, STUNNED, DEAD }
var state: MoveState = MoveState.RUN

## Jump-forgiveness timers (spec §7). They make the game feel fair:
## - coyote: "I pressed jump a blink after running off the edge — it still worked."
## - buffer: "I pressed jump a blink before landing — it still worked."
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0

## Touch state (P4.5): one active finger drives steering; a quick tap jumps.
var _touch_active: bool = false
var _touch_start: Vector2 = Vector2.ZERO
var _touch_time: float = 0.0
var _touch_moved: bool = false
var _touch_steer: float = 0.0


func _ready() -> void:
	_ensure_input_actions()


## Touch controls for the phone playtest builds — Subway Surfers grammar:
## drag horizontally to steer, quick tap to jump. Keyboard still works too.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_active = true
			_touch_start = touch.position
			_touch_time = 0.0
			_touch_moved = false
			_touch_steer = 0.0
		else:
			# Finger lifted: quick + barely moved = tap = jump (via the
			# same buffer the keyboard uses, so coyote/buffer rules apply).
			if _touch_active and not _touch_moved and _touch_time <= tap_max_time:
				_buffer_timer = jump_buffer
			_touch_active = false
			_touch_steer = 0.0
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_active:
			var dx: float = drag.position.x - _touch_start.x
			if absf(dx) > tap_max_dist:
				_touch_moved = true # It's a drag, not a tap: no jump on release.
			_touch_steer = clampf(dx / touch_steer_pixels, -1.0, 1.0)


func _physics_process(delta: float) -> void:
	if _touch_active:
		_touch_time += delta
	_update_state()
	_update_jump_timers(delta)
	match state:
		MoveState.RUN, MoveState.AIR:
			_apply_run_movement(delta)
		_:
			pass # ADHERE_*, DASH, STUNNED, DEAD arrive in later prompts.
	move_and_slide()


## is_on_floor() reflects the LAST move_and_slide() call — the standard pattern.
func _update_state() -> void:
	state = MoveState.RUN if is_on_floor() else MoveState.AIR


## Ticks the two forgiveness timers, then fires a jump if a buffered press and
## a valid jump window overlap. Runs BEFORE movement so the jump velocity is
## picked up by _apply_run_movement() in the same frame (no 1-frame delay).
func _update_jump_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
	if Input.is_action_just_pressed("jump"):
		_buffer_timer = jump_buffer
	else:
		_buffer_timer -= delta
	if _buffer_timer > 0.0 and _coyote_timer > 0.0:
		_do_jump()


func _do_jump() -> void:
	velocity.y = jump_velocity
	_buffer_timer = 0.0 # Consume both so one press = one jump.
	_coyote_timer = 0.0
	state = MoveState.AIR


func _apply_run_movement(delta: float) -> void:
	# 1. Steering: keyboard axis + touch drag, blended and clamped to -1..+1.
	#    Ease sideways velocity toward the target instead of snapping —
	#    that easing IS the feel.
	var steer_input: float = clampf(
		Input.get_axis("steer_left", "steer_right") + _touch_steer, -1.0, 1.0)
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
	_add_key_action(&"jump", [KEY_SPACE])


func _add_key_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
