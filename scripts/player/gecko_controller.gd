extends CharacterBody3D


func _gs() -> Node:
	# GameState autoload, via tree lookup (works in game and in --script tests).
	# Returns null if not present (e.g. unit tests that don't need it).
	return get_tree().root.get_node_or_null("GameState")


func _gs_running() -> bool:
	var gs := _gs()
	return gs == null or gs.current_state == gs.State.RUNNING

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
@export var speed_ramp: float = 0.15  ## P16: +m/s per second of run time.
@export var max_speed: float = 9.0    ## P16: speed ramp ceiling (m/s).
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
@export var wall_run_speed: float = 4.2 ## Auto-climb speed along the wall (m/s).
@export var wall_jump_push: float = 4.5 ## Wall-jump shove AWAY from the surface (m/s).
@export var wall_jump_up: float = 5.0 ## Wall-jump boost ALONG the surface, upward (m/s).
@export var adhere_cooldown: float = 0.35 ## After a wall jump, ignore walls this
## long (s) — otherwise a feeler ray catches the same wall mid-arc and
## re-sticks instantly.
@export var dash_speed: float = 12.0 ## Dash velocity (m/s).
@export var dash_duration: float = 0.18 ## How long a dash lasts (s).
@export var dash_cooldown_time: float = 1.2 ## Spam prevention (s).

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
var stat_deaths: int = 0 ## P10: times squashed.
var shield_charges: int = 0 ## P12: hits the shield can still absorb.
var _shield_timer: float = 0.0 ## P12: shield expiry countdown.
var _shield_bubble: MeshInstance3D ## P12: the visible bubble.
var _speed_boost_timer: float = 0.0 ## P19: seconds of 1.5x speed left.
var _speed_trail: MeshInstance3D ## P19: motion-streak visual during boost.
const SPEED_BOOST_DURATION: float = 6.0 ## P19: boost length (s).
const SPEED_BOOST_MULT: float = 1.5 ## P19: speed multiplier while boosted.
## P27: camouflage — birds won't dive and ground hazards won't trigger while
## active. The gecko goes semi-transparent so the player can see it working.
var _camo_timer: float = 0.0 ## P27: seconds of camouflage left.
const CAMO_DURATION: float = 5.0 ## P27: camo length (s).
## P27: super tongue — eats every bug within TONGUE_RANGE meters.
var _tongue_timer: float = 0.0 ## P27: tongue-flick visual lifetime.
var _tongue_mesh: MeshInstance3D ## P27: the visible tongue flick.
const TONGUE_RANGE: float = 6.0 ## P27: tongue eating radius (m).
## P27: dev stats overlay. Hidden by default (F1 toggles) — it is a debug
## tool, not part of the game UI.
var _debug_hud: CanvasLayer
var _spawn_pos: Vector3 ## P10: where a respawn puts you.
var _last_dist: int = 0 ## P15: last distance banked into the score.
var _respawn_timer: float = 0.0 ## P10: countdown while DEAD.
var _jump_start_y: float = 0.0

## P5 wall adhesion: the surface we're stuck to, a string copy of `state` for
## the HUD, and a short grace timer so the first contact frames can't
## detach us before the press velocity closes the last few centimeters.
var wall_normal: Vector3 = Vector3.UP
var stat_state: String = "RUN"
var _adhere_grace: float = 0.0
var _adhere_cooldown: float = 0.0 ## P7: grace after a wall jump (no re-stick).
var _kick_timer: float = 0.0 ## P7: after a wall kick, the shove-off momentum
## is preserved briefly instead of being stomped by the auto-run.
var _dash_timer: float = 0.0 ## P8: time left in the current dash.
var _dash_cooldown: float = 0.0 ## P8: time until dash is available again.
var _dash_requested: bool = false ## P8: set by the mobile dash button.

## P22: squash & stretch target the VISUAL only — the CollisionShape3D (the
## hitbox) is a sibling, so it never pulses. P23: the visual is the Tripo
## hero gecko, rotated 90° about Y to face -Z, so its local Y is the
## gecko's up and local Z is lateral.
@onready var _visual: MeshInstance3D = $MeshInstance3D
var _squash_tween: Tween ## P22: the active scale-recovery tween, if any.
var _animator: GeckoAnimator ## P28.5: procedural run cycle (no rig).

## P23: the Tripo hero gecko (decimated to ~9.6k verts). Only the mesh is
## swapped — the CharacterBody3D, collision capsule and this script stay.
const HERO_SCENE: PackedScene = preload("res://assets/gecko/hero_gecko.glb")
## P23: hero footprint vs the 0.5-wide collision capsule.
const VISUAL_BASE_SCALE := 0.85

@onready var _wall_ray_l: RayCast3D = $WallRayL
@onready var _wall_ray_r: RayCast3D = $WallRayR


func _ready() -> void:
	_ensure_input_actions()
	_spawn_pos = global_position
	_last_dist = 0
	_swap_hero_mesh() ## P23: capsule visual -> Tripo gecko (fallback: capsule).
	_animator = GeckoAnimator.new() ## P28.5: procedural run cycle, no rig.
	_animator.setup(self, _visual)
	add_child(_animator)
	GeckoSkins.apply_skin(_visual, _selected_skin()) ## P23: persisted choice.
	_build_shield_bubble()
	_build_speed_trail() ## P19.
	_build_rim_light() ## P28.5+: subtle rim so the hero reads first.
	# The feeler rays must ignore the gecko's own body, and their length
	# follows the exported tuning (the .tscn value is only a default).
	for ray: RayCast3D in [_wall_ray_l, _wall_ray_r]:
		ray.add_exception(self)
		ray.target_position = Vector3(0.0, 0.0, -wall_detect_dist)
	floor_snap_length = 0.15 # A little extra glue for wall adhesion (P5).
	var hud := DebugHUDScript.new()
	hud.setup(self)
	hud.visible = false ## P27: dev stats behind a toggle, off by default.
	_debug_hud = hud
	add_child(hud)
	_build_tongue() ## P27.


## P23: swap the capsule mesh for the Tripo hero gecko. The imported .glb
## is a PackedScene (not a Mesh), so we instance it once, steal the
## ArrayMesh (its surface material carries the PBR textures), and free it.
## If anything fails, the capsule stays — the game never breaks.
func _swap_hero_mesh() -> void:
	var inst: Node = HERO_SCENE.instantiate()
	var hero_mi := _find_first_mesh(inst)
	if hero_mi != null and hero_mi.mesh != null:
		_visual.mesh = hero_mi.mesh
		_visual.scale = Vector3.ONE * VISUAL_BASE_SCALE
	inst.queue_free()


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _find_first_mesh(c)
		if found != null:
			return found
	return null


## P23: the player's persisted skin choice (GameState), default 0.
func _selected_skin() -> int:
	var gs := _gs()
	if gs != null and "selected_skin" in gs:
		return int(gs.selected_skin)
	return 0


## P23: re-apply the skin live (character select on the start screen).
func apply_selected_skin() -> void:
	GeckoSkins.apply_skin(_visual, _selected_skin())


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
	# P10: while DEAD, just count down to respawn. No movement, no input.
	# P22: this runs BEFORE the _gs_running() gate — register_death() parks
	# GameState in DEAD, and the respawn is what brings the run back. The
	# game-over path never arms the timer, so it can't respawn from there.
	if state == MoveState.DEAD:
		if _respawn_timer > 0.0:
			_respawn_timer -= delta
			# Squash flat for readable feedback.
			scale.y = maxf(0.15, scale.y - delta * 5.0)
			if _respawn_timer <= 0.0:
				_respawn()
		return
	# P14: the run only moves when the GameState says RUNNING.
	# READY (start screen): idle in place. FINISHED (game over): stop.
	# (If no GameState — e.g. unit tests — just run.)
	if not _gs_running():
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 22.0 * delta
		move_and_slide()
		return
	if _touch_active:
		_touch_time += delta
	if _adhere_cooldown > 0.0:
		_adhere_cooldown -= delta
	if _kick_timer > 0.0:
		_kick_timer -= delta
	if _dash_cooldown > 0.0:
		_dash_cooldown -= delta
	# P12: shield expiry.
	if shield_charges > 0:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			shield_charges = 0
			_shield_bubble.visible = false
	# P19: speed boost expiry.
	if _speed_boost_timer > 0.0:
		_speed_boost_timer -= delta
		if _speed_boost_timer <= 0.0:
			_speed_boost_timer = 0.0
			_speed_trail.visible = false
	# P27: camouflage expiry.
	if _camo_timer > 0.0:
		_camo_timer -= delta
		if _camo_timer <= 0.0:
			_camo_timer = 0.0
			_visual.transparency = 0.0
	# P27: tongue-flick visual lifetime.
	if _tongue_timer > 0.0:
		_tongue_timer -= delta
		if _tongue_timer <= 0.0:
			_tongue_timer = 0.0
			_tongue_mesh.visible = false
	# P14: score = meters from the start line.
	# P15: accumulate distance via add_score so near-miss bonuses persist.
	var gs := _gs()
	if gs != null:
		var dist := maxi(0, int(_spawn_pos.z - global_position.z))
		if dist > _last_dist:
			gs.add_score(dist - _last_dist)
			_last_dist = dist
	_update_state()
	# P8: dash on Shift (or the mobile dash button). Only from RUN/AIR, and
	# the cooldown prevents spam.
	var dash_pressed: bool = Input.is_action_just_pressed("dash") or _dash_requested
	_dash_requested = false
	if dash_pressed and _dash_cooldown <= 0.0 and (state == MoveState.RUN or state == MoveState.AIR):
		state = MoveState.DASH
		stat_state = "DASH"
		_dash_timer = dash_duration
		_dash_cooldown = dash_cooldown_time
		FX.burst(get_parent(), global_position + Vector3(0, 0.4, 0.6),
			Color(1.0, 0.9, 0.6), 12) ## P28.5+: dash kick-up behind the gecko.
	if state == MoveState.RUN or state == MoveState.AIR:
		_check_wall_adhesion()
	_update_jump_timers(delta)
	match state:
		MoveState.RUN, MoveState.AIR:
			_apply_run_movement(delta)
		MoveState.ADHERE_WALL, MoveState.ADHERE_CEILING:
			_apply_adhere_movement(delta)
		MoveState.DASH:
			_apply_dash_movement(delta)
		_:
			pass # STUNNED, DEAD arrive in later prompts.
	var was_air := state == MoveState.AIR # P22: captured before the move.
	move_and_slide()
	# P22: landing squash — airborne coming in, on the floor going out.
	# (Takeoff sets AIR but leaves the floor the same frame, so no false hit.)
	if was_air and is_on_floor() and state != MoveState.DEAD:
		_juice_scale(1.25, 0.65)
		FX.burst(get_parent(), global_position + Vector3(0, 0.12, 0),
			Color(0.72, 0.65, 0.52), 10) ## P28.5+: landing dust puff.
	# Track jump peak for the dev HUD: highest point above jump start.
	if stat_jumps > 0 and not is_on_floor():
		stat_last_peak = maxf(stat_last_peak, global_position.y - _jump_start_y)


## is_on_floor() reflects the LAST move_and_slide() call — the standard pattern.
## ADHERE_* states are sticky: only their own logic (P6/P7) may leave them.
func _update_state() -> void:
	if state == MoveState.ADHERE_WALL or state == MoveState.ADHERE_CEILING or state == MoveState.DASH or state == MoveState.DEAD:
		return
	state = MoveState.RUN if is_on_floor() else MoveState.AIR
	stat_state = MoveState.keys()[state]


## P5: scan the two feeler rays for a "climbable" surface. Detection range is
## wall_detect_dist, but we only LATCH on contact (dist <= wall_latch_dist) —
## the gecko should touch the wall, not stick to thin air a meter away.
func _check_wall_adhesion() -> void:
	if _adhere_cooldown > 0.0:
		return # P7: just kicked off; don't catch the same wall mid-arc.
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


## P5: while adhered, just stick. P6: remap controls to the wall — "forward"
## (auto) climbs the surface, steering moves across it. A gentle press into
## the surface keeps it counting as floor. If the surface ends, let go.
## P20: while on a wall, also watch for a climbable ceiling overhead —
## grabbing the pergola slab's underside is the gecko fantasy.
func _apply_adhere_movement(delta: float) -> void:
	_adhere_grace -= delta
	if state == MoveState.ADHERE_WALL and _try_ceiling_transition():
		return
	if _adhere_grace <= 0.0 and not is_on_floor():
		_detach_from_wall()
		return
	# Wall frame from the attach-time basis: local -Z runs up the surface,
	# local X runs across it, local +Y is the wall normal (belly-to-wall).
	var up_wall: Vector3 = -global_transform.basis.z
	var across: Vector3 = global_transform.basis.x
	var steer_input: float = clampf(
		Input.get_axis("steer_left", "steer_right") + _touch_steer, -1.0, 1.0)
	stat_steer = steer_input # Surfaced on the dev HUD.
	velocity = (up_wall * wall_run_speed
		+ across * steer_input * steer_speed
		- wall_normal * adhere_press_speed)


## P20: stick to a ceiling (pergola slab underside). Same trick as walls:
## point up_direction at the surface normal — here that's DOWN, so the
## gecko hangs upside-down and the ceiling counts as floor.
func _attach_to_ceiling(normal: Vector3) -> void:
	state = MoveState.ADHERE_CEILING
	stat_state = "ADHERE_CEILING"
	wall_normal = normal.normalized()
	up_direction = wall_normal
	_adhere_grace = adhere_grace_time
	# Keep the current heading, projected onto the ceiling plane. If the
	# heading was straight up the wall (degenerate), fall back to down-track.
	var fwd: Vector3 = -global_transform.basis.z
	fwd = fwd - wall_normal * fwd.dot(wall_normal)
	if fwd.length() < 0.05:
		fwd = Vector3(0, 0, -1) - wall_normal * Vector3(0, 0, -1).dot(wall_normal)
	if fwd.length() < 0.05:
		fwd = Vector3(1, 0, 0) - wall_normal * Vector3(1, 0, 0).dot(wall_normal)
	fwd = fwd.normalized()
	var z_axis: Vector3 = -fwd
	var x_axis: Vector3 = wall_normal.cross(z_axis).normalized()
	global_transform.basis = Basis(x_axis, wall_normal, z_axis).orthonormalized()
	velocity = -wall_normal * adhere_press_speed # Press UP into the ceiling.


## P20: while wall-running, cast up-the-surface for a climbable ceiling.
## The pergola posts are 2.4 m tall and meet the slab — climbing into it
## feels like the gecko found a secret highway.
func _try_ceiling_transition() -> bool:
	var up_surface: Vector3 = -global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + up_surface * 0.2,
		global_position + up_surface * 1.5)
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if not (collider is Node and (collider as Node).is_in_group("climbable")):
		return false
	var n: Vector3 = hit.get("normal")
	if n.y > -0.5: # Walls are y≈0, floors y≈+1 — we want ceiling-like (y≈-1).
		return false
	_attach_to_ceiling(n)
	return true


## Any exit from the wall restores world-up so gravity and floor detection
## behave normally again.
func _detach_from_wall() -> void:
	up_direction = Vector3.UP
	_reset_upright_basis()
	state = MoveState.AIR
	stat_state = "AIR"


## P8: the dash. A short horizontal burst at dash_speed; steering is locked
## during it (commitment feels punchy). Light gravity so air dashes arc.
func _apply_dash_movement(delta: float) -> void:
	_dash_timer -= delta
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = fwd.normalized()
	velocity = fwd * dash_speed
	velocity.y -= gravity * delta * 0.3
	if _dash_timer <= 0.0:
		state = MoveState.AIR if not is_on_floor() else MoveState.RUN
		stat_state = MoveState.keys()[state]


## P10: squashed. Freeze, flatten, count it, and come back in under a second.
## Idempotent: a second hit while already dead is ignored.
## P12: if the shield has a charge, it absorbs the hit instead (no death).
func die() -> void:
	if state == MoveState.DEAD:
		return
	if shield_charges > 0:
		shield_charges = 0
		_shield_timer = 0.0
		_shield_bubble.visible = false
		return # Shield ate it. No death, no respawn.
	state = MoveState.DEAD
	stat_state = "DEAD"
	stat_deaths += 1
	# P22: the camera feels it — full trauma shake on death.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("add_trauma"):
		rig.add_trauma(1.0)
	var gs := _gs()
	if gs != null and gs.has_method("register_death"):
		# P22 fix: deaths route through register_death() so the combo breaks.
		# (The old gs.deaths += 1 never reset the combo.)
		gs.register_death()
		if gs.deaths >= gs.max_lives:
			# P14: out of lives. No respawn — the game-over screen takes it.
			gs.finish_run()
			return
	_respawn_timer = 0.8
	velocity = Vector3.ZERO


## P14: full reset for "RUN AGAIN" — back to the start line, fresh lives.
func reset_for_new_run() -> void:
	_respawn()
	stat_deaths = 0


## P12: grant one shield charge (10 s expiry). Called by shield pickups.
func give_shield() -> void:
	shield_charges = 1
	_shield_timer = 10.0
	_shield_bubble.visible = true


## P19: grant the speed boost (6 s of 1.5x). Called by speed pickups.
func give_speed_boost() -> void:
	_speed_boost_timer = SPEED_BOOST_DURATION
	_speed_trail.visible = true
	var atmo := get_tree().get_first_node_in_group("atmosphere")
	if atmo != null and atmo.has_method("kick_speed_lines"):
		atmo.kick_speed_lines() ## P28.5+: brief radial speed-line flash.


## P27: grant camouflage (5 s). While active, hazards can't see the gecko:
## hazard_base skips the hit and the bird holds its dive. Called by the
## CAMO ability button (and nothing else — no camo pickups on the route).
func give_camo() -> void:
	_camo_timer = CAMO_DURATION
	_visual.transparency = 0.55


## P27: hazards ask this before hitting. True while the camo timer runs.
func is_camouflaged() -> bool:
	return _camo_timer > 0.0


## P27: the super tongue — eats every bug within TONGUE_RANGE meters of the
## gecko, wherever they hover. Called by the TONGUE ability button.
func fire_tongue() -> void:
	_tongue_timer = 0.3
	_tongue_mesh.visible = true
	for b in get_tree().get_nodes_in_group("bug"):
		var b3 := b as Node3D
		if b3 == null:
			continue
		if b3.global_position.distance_to(global_position) > TONGUE_RANGE:
			continue
		if b.has_method("collect_remote"):
			b.call("collect_remote")
	FX.burst(get_tree().root, global_position + Vector3(0, 0.6, -1.0),
		Color(1.0, 0.35, 0.3))


## P27: a quick red flick that sells the tongue. Points forward (-Z), lives
## 0.3 s per fire_tongue().
func _build_tongue() -> void:
	_tongue_mesh = MeshInstance3D.new()
	var tongue := BoxMesh.new()
	tongue.size = Vector3(0.09, 0.09, 2.6)
	_tongue_mesh.mesh = tongue
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.35, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tongue_mesh.material_override = mat
	_tongue_mesh.position = Vector3(0, 0.45, -1.4)
	_tongue_mesh.visible = false
	add_child(_tongue_mesh)


## P27: show/hide the dev stats overlay. Off by default; F1 toggles.
func set_debug_hud(v: bool) -> void:
	if _debug_hud != null:
		_debug_hud.visible = v


func _unhandled_input(event: InputEvent) -> void:
	if _debug_hud == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F1:
			set_debug_hud(not _debug_hud.visible)


## P19: current speed multiplier — 1.5 while boosted, 1.0 otherwise.
func boost_multiplier() -> float:
	return SPEED_BOOST_MULT if _speed_boost_timer > 0.0 else 1.0


## P19: the motion-streak that sells the boost.
func _build_speed_trail() -> void:
	_speed_trail = MeshInstance3D.new()
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.5, 0.4, 1.8)
	_speed_trail.mesh = trail_mesh
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.35)
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_speed_trail.material_override = trail_mat
	_speed_trail.position = Vector3(0, 0.35, 0.9)
	_speed_trail.visible = false
	add_child(_speed_trail)


## P28.5+: subtle rim/fill so the hero reads FIRST against the lush
## dressing (visual hierarchy from the key art). A cheap back-facing
## OmniLight3D, no shadows: parked ahead of the gecko in body space, so from
## the chase camera it rims the gecko's top/back edges. Visual only.
func _build_rim_light() -> void:
	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(0.88, 0.94, 1.0)
	rim.light_energy = 0.55
	rim.omni_range = 5.0
	rim.shadow_enabled = false
	rim.position = Vector3(0, 0.9, -1.4) # Ahead = behind it on screen.
	add_child(rim)


## P12: the translucent bubble that says "you're protected."
func _build_shield_bubble() -> void:
	_shield_bubble = MeshInstance3D.new()
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.55 ## P28.5: smaller for the macro camera.
	bubble_mesh.height = 1.1
	_shield_bubble.mesh = bubble_mesh
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.18)
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_bubble.material_override = bubble_mat
	_shield_bubble.position = Vector3(0, 0.5, 0)
	_shield_bubble.visible = false
	add_child(_shield_bubble)


## P10: back to the start, upright, running. Death-to-retry stays under a
## second (spec: the "one more run" feel starts here).
func _respawn() -> void:
	global_position = _spawn_pos
	velocity = Vector3.ZERO
	up_direction = Vector3.UP
	_last_dist = 0 ## P15: distance re-accumulates from the respawn point.
	_reset_upright_basis()
	scale = Vector3.ONE
	if _animator != null:
		_animator.reset() ## P28.5: clears squash/stretch synchronously.
	else:
		_visual.scale = Vector3.ONE * VISUAL_BASE_SCALE ## P22: clear squash/stretch.
		if _squash_tween != null and _squash_tween.is_valid():
			_squash_tween.kill()
	state = MoveState.RUN
	stat_state = "RUN"
	_adhere_cooldown = 0.0
	_kick_timer = 0.0
	_dash_cooldown = 0.0
	shield_charges = 0
	_shield_timer = 0.0
	_shield_bubble.visible = false
	_speed_boost_timer = 0.0 ## P19: boost does not survive death.
	_speed_trail.visible = false
	_camo_timer = 0.0 ## P27: camo does not survive death/respawn.
	_visual.transparency = 0.0
	_tongue_timer = 0.0 ## P27.
	_tongue_mesh.visible = false
	# P22: register_death() parked GameState in DEAD — the run resumes here.
	var gs := _gs()
	if gs != null and gs.has_method("respawn"):
		gs.respawn()


## P8: the mobile dash button calls this (keyboard uses the "dash" action).
func request_dash() -> void:
	_dash_requested = true


## Ticks the two forgiveness timers, then fires a jump if a buffered press and
## a valid jump window overlap. Runs BEFORE movement so the jump velocity is
## picked up by _apply_run_movement() in the same frame (no 1-frame delay).
func _update_jump_timers(delta: float) -> void:
## picked up by _apply_run_movement() in the same frame (no 1-frame delay).
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


## P22: squash & stretch, visual-only. Snaps the visual to (width, height),
## then a BACK-eased tween settles it to normal over 0.22 s — the classic
## cartoon "boing" without touching the hitbox.
## P23: the hero is rotated 90° about Y, so local Y is up and local Z is
## lateral: height squashes local Y, width widens local Z. The base scale
## (0.85) is preserved through the juice.
func _juice_scale(width: float, height: float) -> void:
	if _animator != null:
		_animator.juice(width, height) ## P28.5: composed with dash stretch.
		return
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_visual.scale = Vector3(1.0, height, width) * VISUAL_BASE_SCALE
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE * VISUAL_BASE_SCALE, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _do_jump() -> void:
	if state == MoveState.ADHERE_WALL:
		# P7: the wall kick. Shove away from the surface plus up along it,
		# then AIR with a restored upright frame. Run -> wall -> climb ->
		# kick -> land is the core loop.
		var up_wall: Vector3 = -global_transform.basis.z
		velocity = wall_normal * wall_jump_push + up_wall * wall_jump_up
		_reset_upright_basis()
		up_direction = Vector3.UP
		_adhere_cooldown = adhere_cooldown
		_kick_timer = 0.35
		_juice_scale(0.85, 1.3) ## P22: stretch on the kick.
	elif state == MoveState.ADHERE_CEILING:
		# P20: dropping off the ceiling. Small downward push, keep some
		# horizontal momentum, fall back to the ground.
		_reset_upright_basis()
		up_direction = Vector3.UP
		_adhere_cooldown = adhere_cooldown
		velocity = Vector3(velocity.x * 0.3, -2.0, velocity.z * 0.3)
	else:
		velocity.y = jump_velocity
		_juice_scale(0.85, 1.3) ## P22: stretch on takeoff.
	_buffer_timer = 0.0 # Consume both so one press = one jump.
	_coyote_timer = 0.0
	state = MoveState.AIR
	stat_state = "AIR"
	stat_jumps += 1
	_jump_start_y = global_position.y
	stat_last_peak = 0.0


## P7: restore the upright running frame (face down-track, head up) after
## leaving a wall. Without this the gecko keeps its wall-tilted basis and
## runs sideways through the world.
func _reset_upright_basis() -> void:
	global_transform.basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).orthonormalized()


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
	# P7: right after a wall kick the shove-off momentum is preserved and
	# eased back into the auto-run, so the kick visibly arcs off the wall.
	# P16: speed ramps with run time (the "one more run" tension).
	var gs2 := _gs()
	var effective_speed: float = run_speed
	if gs2 != null:
		effective_speed = minf(run_speed + gs2.run_time * speed_ramp, max_speed)
	effective_speed *= boost_multiplier() ## P19: 1.5x while boosted.
	if _kick_timer > 0.0:
		velocity.z = move_toward(velocity.z, -effective_speed, 30.0 * delta)
	else:
		velocity.z = -effective_speed

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
	_add_key_action(&"dash", [KEY_SHIFT])


func _add_key_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
