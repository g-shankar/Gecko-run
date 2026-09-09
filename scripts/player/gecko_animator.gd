class_name GeckoAnimator
extends Node
## Gecko Run — procedural gecko animation. VISUALS ONLY.
##
## Drives the articulated rig from GeckoRig (9 parts: body, head, 3 tail
## sections, 4 legs on pivots). When the rig is present, the run cycle is a
## real diagonal gait: LF+RH swing together, RF+LH antiphase, legs lift
## through recovery, the tail carries a traveling wave, and the head
## stabilizes against body bob. Body bob is small (0.012 m) — the motion
## lives in the limbs, not in bouncing the torso.
##
## When the rig is absent (segmentation failed), falls back to layered
## sine motion on the visual node. Never touches the CharacterBody3D.
##
## Pivot-local frame (mesh frame, BEFORE the carrier's 90° Y rotation):
## +X = head/front, Y = up, Z = lateral.
##   legs: rotation.z swings fore/aft (+ = forward), rotation.x abducts.
##   tail (chained): rotation.y sways lateral, rotation.z lifts.
##   head: rotation.z nods (+ = nose up), rotation.y yaws.
## Body motion still goes on the visual carrier in its own frame
## (X = forward, Y = up, Z = lateral after the Y rotation):
## rotation.z pitches, rotation.x rolls/banks, rotation.y yaws.

## --- Tuning (all consts: no magic numbers in the motion code) ---
const BOB_AMP := 0.012 ## Body bob, meters. Small — limbs do the work.
const PITCH_AMP := 0.020 ## Spine undulation, radians.
const ROLL_AMP := 0.018 ## Roll sway, radians.
const LEG_SWING := 0.55 ## Leg fore/aft swing, radians.
const LEG_LIFT := 0.38 ## Extra forward/up rotation during recovery.
const LEG_ABDUCT := 0.10 ## Lateral leg flare, radians.
const LEG_TRAIL := 0.50 ## Airborne legs trail back, radians.
const TAIL_AMP := 0.22 ## Tail sway base, radians (grows toward tip).
const TAIL_LIFT := 0.06 ## Tail vertical ripple, radians.
const HEAD_NOD := 0.06 ## Head counter-nod, radians (2x stride).
const IDLE_YAW_AMP := 0.12 ## Look-around when not running, radians.
const IDLE_BREATH_AMP := 0.008 ## Idle breathing bob, meters.
const STRIDE_MIN_HZ := 1.4 ## Stride rate at standstill.
const STRIDE_MAX_HZ := 3.2 ## Stride rate at 9 m/s.
const STRIDE_REF_SPEED := 9.0 ## Speed that maps to STRIDE_MAX_HZ.
const BANK_MAX := 0.30 ## Max lean into steering, radians.
const BANK_GAIN := 0.10 ## Bank radians per m/s of lateral velocity.
const JUICE_TIME := 0.22 ## Squash/stretch recovery, seconds.
const DASH_STRETCH := Vector3(1.16, 0.94, 0.96) ## Elongate forward on dash.
const BOOST_STRETCH := Vector3(1.08, 0.97, 0.98) ## Milder stretch on boost.
const BLEND_RATE := 5.0 ## Run<->idle crossfade speed.
const AIR_BLEND_RATE := 6.0 ## Grounded<->airborne crossfade speed.
const DEAD_STATE := "DEAD"

var _gecko: CharacterBody3D
var _visual: MeshInstance3D
var _base_pos := Vector3.ZERO
var _base_rot_y := 0.0
var _base_scale := Vector3.ONE

## Rig pivots ({} = rigid fallback). Set via setup().
var _head: Node3D
var _tail: Array = []
var _legs := {} ## "LF"/"RF"/"LH"/"RH" -> Node3D
var _rigged := false

var _phase := 0.0 ## Stride phase, radians.
var _idle_t := 0.0 ## Idle clock, seconds.
var _run_blend := 0.0 ## 1 = running, 0 = idle/menu. Eased, never snaps.
var _air_blend := 0.0 ## 1 = airborne, 0 = grounded. Eased.
var _bank := 0.0 ## Smoothed lean, radians.
var _juice := Vector3.ONE ## Squash/stretch multiplier (landing, takeoff).
var _stretch := Vector3.ONE ## Dash/boost multiplier.
var _juice_tween: Tween


## Wire to the controller + visual + rig pivots. Call BEFORE add_child.
## pivots = {"head": Node3D, "tail": [Node3D x3], "legs": {...}} or {}
## for the rigid fallback.
func setup(gecko: CharacterBody3D, visual: MeshInstance3D,
		pivots: Dictionary = {}) -> void:
	_gecko = gecko
	_visual = visual
	if _visual != null:
		_base_pos = _visual.position
		_base_rot_y = _visual.rotation.y
		_base_scale = _visual.scale
	if not pivots.is_empty() and pivots.has("head"):
		_head = pivots["head"]
		_tail = pivots.get("tail", [])
		_legs = pivots.get("legs", {})
		_rigged = _head != null and _tail.size() == 3 and _legs.size() == 4


## P22 squash & stretch, routed through the animator so it composes with the
## dash stretch instead of fighting it. Snaps immediately (tests and game
## feel read the impact on the SAME frame), then eases back over JUICE_TIME.
## (width, height) follow the old convention: height -> local Y, width ->
## local Z (lateral); local X (forward) stays 1.
func juice(width: float, height: float) -> void:
	if _juice_tween != null and _juice_tween.is_valid():
		_juice_tween.kill()
	_juice = Vector3(1.0, height, width)
	_write_scale()
	_juice_tween = create_tween()
	_juice_tween.tween_property(self, "_juice", Vector3.ONE, JUICE_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Full reset (respawn): kill tweens, restore rest pose synchronously.
func reset() -> void:
	if _juice_tween != null and _juice_tween.is_valid():
		_juice_tween.kill()
	_juice = Vector3.ONE
	_stretch = Vector3.ONE
	_bank = 0.0
	_run_blend = 0.0
	_air_blend = 0.0
	_write_scale()
	_write_rest_pose()


func _write_scale() -> void:
	if _visual != null:
		_visual.scale = _base_scale * _juice * _stretch


## Rest pose for every pivot (used by reset and the rigid-fallback path).
func _write_rest_pose() -> void:
	if not _rigged:
		return
	_head.rotation = Vector3.ZERO
	for tp in _tail:
		(tp as Node3D).rotation = Vector3.ZERO
	for key in _legs.keys():
		(_legs[key] as Node3D).rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if _gecko == null or _visual == null:
		return
	if str(_gecko.get("stat_state")) == DEAD_STATE:
		return # Flattened by die(): hold the pose, don't dance.
	var running: bool = _gecko._gs_running()
	var target_blend := 1.0 if running else 0.0
	_run_blend = move_toward(_run_blend, target_blend, BLEND_RATE * delta)
	var rb := _run_blend
	# Airborne blend: real jumps get the trailing pose; grounded gets gait.
	var airborne: bool = not _gecko.is_on_floor()
	var at := 1.0 if airborne else 0.0
	_air_blend = move_toward(_air_blend, at, AIR_BLEND_RATE * delta)
	var ab := _air_blend

	var vel: Vector3 = _gecko.velocity
	var h_speed: float = Vector2(vel.x, vel.z).length()
	var stride_hz: float = lerpf(STRIDE_MIN_HZ, STRIDE_MAX_HZ,
		clampf(h_speed / STRIDE_REF_SPEED, 0.0, 1.0))
	_phase += TAU * lerpf(0.4, stride_hz, rb) * delta
	_idle_t += delta

	# Lean into steering: bank with lateral velocity, smoothed.
	var bank_target := clampf(vel.x * BANK_GAIN, -BANK_MAX, BANK_MAX) * rb
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-8.0 * delta))

	if _rigged:
		_animate_rigged(delta, rb, ab)
	else:
		_animate_rigid(delta, rb)

	# Dash stretch (and a milder one for the speed boost): eased so it
	# punches in and relaxes out without popping.
	var want := Vector3.ONE
	var st: String = str(_gecko.get("stat_state"))
	if st == "DASH":
		want = DASH_STRETCH
	elif float(_gecko.get("_speed_boost_timer") or 0.0) > 0.0:
		want = BOOST_STRETCH
	_stretch = _stretch.lerp(want, 1.0 - exp(-10.0 * delta))
	_write_scale()


## Articulated run: diagonal gait on the leg pivots, traveling tail wave,
## stabilizing head, grounded body.
func _animate_rigged(_delta: float, rb: float, ab: float) -> void:
	var p2 := _phase * 2.0
	var idle_w := 1.0 - rb
	# --- Legs: diagonal pairs LF+RH / RF+LH, antiphase. ---
	var pair_phase := {"LF": 0.0, "RH": 0.0, "RF": PI, "LH": PI}
	for key in _legs.keys():
		var piv: Node3D = _legs[key]
		var ph: float = _phase + float(pair_phase.get(key, 0.0))
		var sw := sin(ph)
		# Fore/aft swing plus an extra lift biased into the forward
		# recovery half, so the foot clears the ground coming through
		# and plants during stance. Fades out when airborne.
		var swing: float = (LEG_SWING * sw \
			+ LEG_LIFT * pow(maxf(0.0, sin(ph - 1.1)), 1.5)) * rb
		var abduct: float = LEG_ABDUCT * sin(ph + 0.7) * rb
		# Airborne: legs trail back and tuck.
		swing = lerpf(swing, -LEG_TRAIL, ab)
		abduct = lerpf(abduct, 0.0, ab)
		piv.rotation = Vector3(abduct, 0.0, swing)
	# --- Tail: traveling wave, phase-lagged per section, growing tip. ---
	for i in _tail.size():
		var tp: Node3D = _tail[i]
		var sway: float = TAIL_AMP * (0.6 + 0.4 * float(i)) \
			* sin(_phase - 0.7 - float(i) * 0.85) * rb
		var lift: float = TAIL_LIFT * sin(_phase * 0.5 + float(i) * 0.6) * rb
		# Airborne: tail streams straight behind.
		sway = lerpf(sway, 0.0, ab)
		lift = lerpf(lift, 0.0, ab)
		tp.rotation = Vector3(0.0, sway, lift)
	# --- Head: counter-nod against body bob + idle look-around. ---
	var nod: float = HEAD_NOD * sin(p2 + 0.8) * rb
	var look: float = (IDLE_YAW_AMP * sin(_idle_t * 1.4) \
		+ 0.05 * sin(_idle_t * 0.53)) * idle_w
	_head.rotation = Vector3(0.0, look, nod)
	# --- Body: small grounded bob, subtle pitch/roll, steering bank. ---
	var bob: float = BOB_AMP * sin(p2) * rb * (1.0 - ab) \
		+ IDLE_BREATH_AMP * sin(_idle_t * 2.6) * idle_w
	var pitch: float = PITCH_AMP * sin(p2 + 0.6) * rb * (1.0 - ab)
	var roll: float = ROLL_AMP * sin(_phase + PI * 0.5) * rb + _bank
	var yaw: float = 0.03 * sin(_phase * 0.5 + 1.0) * rb
	_visual.position = Vector3(_base_pos.x, _base_pos.y + bob, _base_pos.z)
	_visual.rotation = Vector3(roll, _base_rot_y + yaw, pitch)


## Rigid fallback: the old layered-sine whole-body motion (no leg/tail
## articulation possible). Used only when segmentation failed.
func _animate_rigid(_delta: float, rb: float) -> void:
	var p2 := _phase * 2.0
	var idle_w := 1.0 - rb
	var bob: float = 0.030 * sin(p2) * rb \
		+ IDLE_BREATH_AMP * sin(_idle_t * 2.6) * idle_w
	var pitch: float = 0.035 * sin(p2 + 0.6) * rb
	var roll: float = 0.030 * sin(_phase + PI * 0.5) * rb + _bank
	var yaw: float = 0.030 * sin(_phase * 0.5 + 1.0) * rb \
		+ (IDLE_YAW_AMP * sin(_idle_t * 1.4) \
		+ 0.05 * sin(_idle_t * 0.53)) * idle_w
	_visual.position = Vector3(_base_pos.x, _base_pos.y + bob, _base_pos.z)
	_visual.rotation = Vector3(roll, _base_rot_y + yaw, pitch)
