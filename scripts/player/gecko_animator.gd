class_name GeckoAnimator
extends Node
## Gecko Run — P28.5 procedural gecko animation. VISUALS ONLY.
##
## The Tripo hero has no rig, so the run cycle is built from layered sine
## motion on the visual node (never the CharacterBody3D, never the hitbox):
## body bob, spine-undulation pitch, roll sway, bank into steering, a rapid
## small paddle oscillation for the legs, a phase-shifted whole-body yaw
## wave for the tail, dash stretch, landing squash (via juice()), and an
## idle look-around when the run is not active.
##
## Visual-local frame (hero rotated 90° about Y, facing -Z): X = forward,
## Y = up, Z = lateral. So rotation.z pitches the nose, rotation.x rolls
## the body (banks), rotation.y yaws. Euler order is YXZ.
##
## Frequencies stay LOW (stride 1.4–3.2 Hz scaled by speed) and amplitudes
## small — smooth locomotion, never vibration.

## --- Tuning (all consts: no magic numbers in the motion code) ---
const BOB_AMP := 0.030 ## Body bob, meters (vertical).
const PITCH_AMP := 0.035 ## Spine undulation, radians.
const ROLL_AMP := 0.030 ## Roll sway, radians.
const YAW_AMP := 0.030 ## Tail-sway yaw wave, radians (phase-shifted).
const PADDLE_AMP := 0.020 ## Leg-paddle illusion, radians (2x stride freq).
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
const DEAD_STATE := "DEAD"

var _gecko: CharacterBody3D
var _visual: MeshInstance3D
var _base_pos := Vector3.ZERO
var _base_rot_y := 0.0
var _base_scale := Vector3.ONE

var _phase := 0.0 ## Stride phase, radians.
var _idle_t := 0.0 ## Idle clock, seconds.
var _run_blend := 0.0 ## 1 = running, 0 = idle/menu. Eased, never snaps.
var _bank := 0.0 ## Smoothed lean, radians.
var _juice := Vector3.ONE ## Squash/stretch multiplier (landing, takeoff).
var _stretch := Vector3.ONE ## Dash/boost multiplier.
var _juice_tween: Tween


## Wire to the controller + visual. Call BEFORE add_child (setup first so
## _process never runs on half-initialized refs).
func setup(gecko: CharacterBody3D, visual: MeshInstance3D) -> void:
	_gecko = gecko
	_visual = visual
	if _visual != null:
		_base_pos = _visual.position
		_base_rot_y = _visual.rotation.y
		_base_scale = _visual.scale


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
	_write_scale()


func _write_scale() -> void:
	if _visual != null:
		_visual.scale = _base_scale * _juice * _stretch


func _process(delta: float) -> void:
	if _gecko == null or _visual == null:
		return
	if str(_gecko.get("stat_state")) == DEAD_STATE:
		return # Flattened by die(): hold the pose, don't dance.
	var running: bool = _gecko._gs_running()
	var target_blend := 1.0 if running else 0.0
	_run_blend = move_toward(_run_blend, target_blend, BLEND_RATE * delta)
	var rb := _run_blend

	var vel: Vector3 = _gecko.velocity
	var h_speed: float = Vector2(vel.x, vel.z).length()
	var stride_hz: float = lerpf(STRIDE_MIN_HZ, STRIDE_MAX_HZ,
		clampf(h_speed / STRIDE_REF_SPEED, 0.0, 1.0))
	_phase += TAU * lerpf(0.4, stride_hz, rb) * delta
	_idle_t += delta

	# Lean into steering: bank with lateral velocity, smoothed.
	var bank_target := clampf(vel.x * BANK_GAIN, -BANK_MAX, BANK_MAX) * rb
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-8.0 * delta))

	var p2 := _phase * 2.0
	var idle_w := 1.0 - rb
	var bob: float = BOB_AMP * sin(p2) * rb \
		+ IDLE_BREATH_AMP * sin(_idle_t * 2.6) * idle_w
	var pitch: float = (PITCH_AMP * sin(p2 + 0.6) \
		+ PADDLE_AMP * sin(p2 + 1.1)) * rb
	var roll: float = (ROLL_AMP * sin(_phase + PI * 0.5) \
		+ PADDLE_AMP * sin(p2 + 2.0)) * rb + _bank
	var yaw: float = YAW_AMP * sin(_phase * 0.5 + 1.0) * rb \
		+ (IDLE_YAW_AMP * sin(_idle_t * 1.4) \
		+ 0.05 * sin(_idle_t * 0.53)) * idle_w

	_visual.position = Vector3(_base_pos.x, _base_pos.y + bob, _base_pos.z)
	_visual.rotation = Vector3(roll, _base_rot_y + yaw, pitch)

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
