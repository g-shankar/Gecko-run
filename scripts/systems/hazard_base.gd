class_name HazardBase
extends Area3D
## Gecko Run — reusable hazard lifecycle (spec P9).
##
## Every hazard cycles IDLE -> TELEGRAPH -> ACTIVE -> RECOVERY, then loops
## (or stops if one_shot). Subclasses override the _on_* hooks to animate
## their telegraph/attack/recover. The base handles timing, the phase signal,
## and hit detection: anything in the "gecko" group overlapping during ACTIVE
## emits player_hit.
##
## LEARNING NOTES (for Gowrishankar):
## - A "state machine" is just a variable (phase) plus rules for changing it.
##   Every hazard in the game — footstep, sprinkler, bird — is the SAME
##   machine with different _on_* animations. That's why new hazards are cheap.
## - Area3D (not CharacterBody3D): hazards don't need physics movement, they
##   just need to know "is the player inside me right now?"
## - player_hit is a SIGNAL: the hazard announces "I got someone" and whoever
##   cares (the gecko, for death) listens. The hazard never kills directly.

enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVERY }

signal player_hit
signal phase_changed(new_phase: int)
signal near_miss ## P15: gecko was close during ACTIVE but survived.

@export var idle_time: float = 1.5 ## Breather between attacks (s).
@export var warn_time: float = 0.8 ## Telegraph duration — the dodge window (s).
@export var active_time: float = 0.3 ## The hit is live this long (s).
@export var recovery_time: float = 1.0 ## Wind-down before the next cycle (s).
@export var one_shot: bool = false ## If true, stop after one RECOVERY.
@export var hits_always: bool = false ## If true, the hitbox is live in every
## phase (e.g. a parked car is still a car). Otherwise only during ACTIVE.
@export var near_miss_distance: float = 2.5 ## P15: how close (m) counts as
## a near-miss if the gecko survives the ACTIVE phase.

var phase: int = Phase.IDLE
var _phase_timer: float = 0.0
var _finished: bool = false
var _was_close: bool = false ## P15: gecko entered near-miss range during ACTIVE.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Every hazard announces to the gecko directly. (P12's shield will
	# intercept this path to absorb one hit.)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("die"):
		player_hit.connect(gecko.die)
	# P15: near-misses feed the score via GameState.
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs != null and gs.has_method("register_near_miss"):
		near_miss.connect(gs.register_near_miss)
	_enter_phase(Phase.IDLE)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_phase_timer -= delta
	_tick_phase(delta)
	# P15: during ACTIVE, note if the gecko gets within near-miss range.
	if phase == Phase.ACTIVE and not _was_close:
		var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
		if gecko != null and gecko.global_position.distance_to(global_position) < near_miss_distance:
			_was_close = true
	if _phase_timer <= 0.0:
		_advance()


func _advance() -> void:
	match phase:
		Phase.IDLE:
			_enter_phase(Phase.TELEGRAPH)
		Phase.TELEGRAPH:
			_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			_check_near_miss() # P15: survived it close? That's points.
			_enter_phase(Phase.RECOVERY)
		Phase.RECOVERY:
			if one_shot:
				_finished = true
			else:
				_enter_phase(Phase.IDLE)


func _enter_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	match p:
		Phase.IDLE:
			_phase_timer = idle_time
			_on_idle()
		Phase.TELEGRAPH:
			_phase_timer = warn_time
			_on_telegraph()
		Phase.ACTIVE:
			_phase_timer = active_time
			_on_activate()
			_check_overlaps() # Gecko may already be inside when the hit goes live.
		Phase.RECOVERY:
			_phase_timer = recovery_time
			_on_recover()


## P15: called when ACTIVE ends. If the gecko was close but the run is
## still going (it survived), that's a near-miss: emit for GameState.
func _check_near_miss() -> void:
	var close: bool = _was_close
	_was_close = false
	if not close:
		return
	var gs := get_tree().root.get_node_or_null("GameState")
	# State.RUNNING == 1. If the gecko died, we're DEAD/FINISHED: no points.
	if gs != null and int(gs.get("current_state")) == 1:
		near_miss.emit()


## Per-frame hook so subclasses can animate (shadow growing, shoe slamming).
func _tick_phase(_delta: float) -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("gecko"):
		return
	if _gecko_camouflaged(): ## P27: camo — the hazard never sees the gecko.
		return
	if hits_always or phase == Phase.ACTIVE:
		player_hit.emit()


func _check_overlaps() -> void:
	if _gecko_camouflaged(): ## P27.
		return
	if hits_always or phase == Phase.ACTIVE:
		for body in get_overlapping_bodies():
			if body.is_in_group("gecko"):
				player_hit.emit()
				break


## P27: true while the gecko's camouflage timer runs. Centralized here so
## every hazard (footstep, sprinkler, bicycle, car, bird) honors camo the
## same way — the bird additionally holds its dive (see bird.gd).
func _gecko_camouflaged() -> bool:
	var gecko := get_tree().get_first_node_in_group("gecko")
	return gecko != null and gecko.has_method("is_camouflaged") \
		and bool(gecko.call("is_camouflaged"))


## --- Subclass hooks: override these, don't touch the machine above. ---
func _on_idle() -> void:
	pass


func _on_telegraph() -> void:
	pass


func _on_activate() -> void:
	pass


func _on_recover() -> void:
	pass
