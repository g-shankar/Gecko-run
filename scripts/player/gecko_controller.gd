extends CharacterBody3D

const DebugHUDScript := preload("res://scripts/dev/debug_hud.gd")

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
## P4.6 = dev metrics HUD (fps, speed, distance, jump stats).
## P5 = wall detection + adhesion (two feeler rays, stick on contact).
## P6-P7 = wall movement + transitions. P8 = dash. STUNNED/DEAD arrive with hazards (P10+).

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
@export var wall_detect_dist: float = 1.2 ## Ray length: how far ahead walls are "seen".
@export var wall_latch_dist: float = 0.55 ## Attach when a climbable wall is this close (m).
@export var adhere_press_speed: float = 2.0 ## Press-into-wall speed while adhered (m/s).
@export var adhere_grace_time: float = 0.4 ## Time allowed to reach the wall face
## after latching (s). Must cover wall_latch_dist / adhere_press_speed with
## margin, or the gecko lets go just before touching.

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

## Playtest stats surfaced on the dev HUD (P4.6) — numbers beat vibes.
var stat_jumps: int = 0
var stat_last_peak: float = 0.0
var stat_steer: float = 0.0
var _jump_start_y: float = 0.0

## P5 wall adhesion: the surface we're stuck to, a string copy of `state` for
## the HUD, and a short grace timer so the first contact frames can't
## detach us before the press velocity closes the last few centimeters.
var wall_normal: Vector3 = Vector3.UP
var stat_state: String = "RUN"
var _adhere_grace: float = 0.0

@onready var _wall_ray_l: RayCast3D = $WallRayL
@onready var _wall_ray_r: RayCast3D = $WallRayR


func _ready() -> void:
	_ensure_input_actions()
	# The feeler rays must ignore the gecko's own body, and their length
	# follows the exported tuning (the .tscn value is only a default).
	for ray: RayCast3D in [_wall_ray_l, _wall_ray_r]:
		ray.add_exception(self)
		ray.target_position = Vector3(0.0, 0.0, -wall_detect_dist)
	floor_snap_length = 0.15 # A little extra glue for wall adhesion (P5).
	var hud := DebugHUDScript.new()
	hud.setup(self)
	add_child(hud)


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
	if state == MoveState.RUN or state == MoveState.AIR:
		_check_wall_adhesion()
	_update_jump_timers(delta)
	match state:
		MoveState.RUN, MoveState.AIR:
			_apply_run_movement(delta)
		MoveState.ADHERE_WALL:
			_apply_adhere_movement(delta)
		_:
			pass # ADHERE_CEILING, DASH, STUNNED, DEAD arrive in later prompts.
	move_and_slide()
	# Track jump peak for the dev HUD: highest point above jump start.
	if stat_jumps > 0 and not is_on_floor():
		stat_last_peak = maxf(stat_last_peak, global_position.y - _jump_start_y)


## is_on_floor() reflects the LAST move_and_slide() call — the standard pattern.
## ADHERE_* states are sticky: only their own logic (P6/P7) may leave them.
func _update_state() -> void:
	if state == MoveState.ADHERE_WALL or state == MoveState.ADHERE_CEILING:
		return
	state = MoveState.RUN if is_on_floor() else MoveState.AIR
	stat_state = MoveState.keys()[state]


## P5: scan the two feeler rays for a "climbable" surface. Detection range is
## wall_detect_dist, but we only LATCH on contact (dist <= wall_latch_dist) —
## the gecko should touch the wall, not stick to thin air a meter away.
func _check_wall_adhesion() -> void:
	var best_normal := Vector3.ZERO
	var best_dist := wall_latch_dist
	for ray: RayCast3D in [_wall_ray_l, _wall_ray_r]:
		if not ray.is_colliding():
			continue
		var collider: Object = ray.get_collider()
		if not (collider is Node and (collider as Node).is_in_group("climbable")):
			continue
		var dist: float = ray.get_collision_point().distance_to(ray.global_position)
		if dist < best_dist:
			best_dist = dist
			best_normal = ray.get_collision_normal()
	if best_normal != Vector3.ZERO:
		_attach_to_wall(best_normal)


## P5: stick to the wall. The CharacterBody3D trick: point `up_direction` at
## the wall, and the wall itself counts as "floor" — gravity-style snapping
## then keeps the gecko glued instead of sliding off.
func _attach_to_wall(normal: Vector3) -> void:
	state = MoveState.ADHERE_WALL
	stat_state = "ADHERE_WALL"
	wall_normal = normal.normalized()
	up_direction = wall_normal
	_adhere_grace = adhere_grace_time
	# Reorient the capsule: local +Y becomes the wall normal (belly to the
	# wall), local forward (-Z) becomes "up the wall". Build an orthonormal,
	# right-handed basis: x = y cross z.
	var fwd: Vector3 = Vector3.UP - wall_normal * Vector3.UP.dot(wall_normal)
	if fwd.length() < 0.05:
		# Degenerate case (surface nearly horizontal — ceiling territory, P7):
		# keep the current heading, projected onto the surface plane.
		fwd = -global_transform.basis.z
		fwd = fwd - wall_normal * fwd.dot(wall_normal)
	fwd = fwd.normalized()
	var z_axis: Vector3 = -fwd
	var x_axis: Vector3 = wall_normal.cross(z_axis).normalized()
	global_transform.basis = Basis(x_axis, wall_normal, z_axis).orthonormalized()
	velocity = -wall_normal * adhere_press_speed


## P5: while adhered, just stick. Press gently into the surface; traveling
## along it arrives in P6. If the surface ends, let go and fall.
func _apply_adhere_movement(delta: float) -> void:
	stat_steer = 0.0
	_adhere_grace -= delta
	if _adhere_grace <= 0.0 and not is_on_floor():
		_detach_from_wall()
		return
	velocity = -wall_normal * adhere_press_speed


## Any exit from the wall restores world-up so gravity and floor detection
## behave normally again. (P7 will add the proper push-off jump.)
func _detach_from_wall() -> void:
	up_direction = Vector3.UP
	state = MoveState.AIR
	stat_state = "AIR"


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
	if state == MoveState.ADHERE_WALL:
		# P5: jumping while stuck just lets go (world-up jump, then fall).
		# P7 replaces this with a real push-off-the-wall jump.
		up_direction = Vector3.UP
	velocity.y = jump_velocity
	_buffer_timer = 0.0 # Consume both so one press = one jump.
	_coyote_timer = 0.0
	state = MoveState.AIR
	stat_state = "AIR"
	stat_jumps += 1
	_jump_start_y = global_position.y
	stat_last_peak = 0.0


func _apply_run_movement(delta: float) -> void:
	# 1. Steering: keyboard axis + touch drag, blended and clamped to -1..+1.
	#    Ease sideways velocity toward the target instead of snapping —
	#    that easing IS the feel.
	var steer_input: float = clampf(
		Input.get_axis("steer_left", "steer_right") + _touch_steer, -1.0, 1.0)
	stat_steer = steer_input # Surfaced on the dev HUD.
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
