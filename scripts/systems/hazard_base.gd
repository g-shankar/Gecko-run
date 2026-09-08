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

@export var idle_time: float = 1.5 ## Breather between attacks (s).
@export var warn_time: float = 0.8 ## Telegraph duration — the dodge window (s).
@export var active_time: float = 0.3 ## The hit is live this long (s).
@export var recovery_time: float = 1.0 ## Wind-down before the next cycle (s).
@export var one_shot: bool = false ## If true, stop after one RECOVERY.
@export var hits_always: bool = false ## If true, the hitbox is live in every
## phase (e.g. a parked car is still a car). Otherwise only during ACTIVE.

var phase: int = Phase.IDLE
var _phase_timer: float = 0.0
var _finished: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Every hazard announces to the gecko directly. (P12's shield will
	# intercept this path to absorb one hit.)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("die"):
		player_hit.connect(gecko.die)
	_enter_phase(Phase.IDLE)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_phase_timer -= delta
	_tick_phase(delta)
	if _phase_timer <= 0.0:
		_advance()


func _advance() -> void:
	match phase:
		Phase.IDLE:
			_enter_phase(Phase.TELEGRAPH)
		Phase.TELEGRAPH:
			_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
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


## Per-frame hook so subclasses can animate (shadow growing, shoe slamming).
func _tick_phase(_delta: float) -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("gecko"):
		return
	if hits_always or phase == Phase.ACTIVE:
		player_hit.emit()


func _check_overlaps() -> void:
	if hits_always or phase == Phase.ACTIVE:
		for body in get_overlapping_bodies():
			if body.is_in_group("gecko"):
				player_hit.emit()
				break


## --- Subclass hooks: override these, don't touch the machine above. ---
func _on_idle() -> void:
	pass


func _on_telegraph() -> void:
	pass


func _on_activate() -> void:
	pass


func _on_recover() -> void:
	pass
