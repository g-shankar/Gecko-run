extends Node
## Autoload singleton: run state machine, score, deaths, run timer, bug count.
## Other systems read/write through here; UI hooks into the signals.

enum State { READY, RUNNING, DEAD, FINISHED }

signal state_changed(new_state: State)
signal score_changed(new_score: int)
signal bugs_changed(new_count: int)
signal deaths_changed(new_count: int)
signal near_misses_changed(new_count: int) ## P15: near-miss counter for UI.
signal combo_changed(new_combo: int) ## P17: combo multiplier for UI.
signal mission_completed(mission_id: String) ## P18: retention-layer hook.

var current_state: State = State.READY:
	set(value):
		if value != current_state:
			current_state = value
			state_changed.emit(current_state)

var score: int = 0:
	set(value):
		score = value
		score_changed.emit(score)

var deaths: int = 0:
	set(value):
		deaths = value
		deaths_changed.emit(deaths)

var bug_count: int = 0:
	set(value):
		bug_count = value
		bugs_changed.emit(bug_count)

var near_miss_count: int = 0: ## P15: survived-it-close counter.
	set(value):
		near_miss_count = value
		near_misses_changed.emit(near_miss_count)

var combo: int = 0: ## P17: consecutive scoring actions without dying.
	set(value):
		combo = value
		combo_changed.emit(combo)

var combo_timer: float = 0.0 ## P17: seconds left before combo expires.
const COMBO_WINDOW: float = 4.0 ## P17: scoring actions refresh the combo.
const COMBO_MAX: int = 8 ## P17: 8x is the ceiling.

## P18: missions — the retention layer. Each dict: id, label, target,
## progress, done, unit. Progress is derived from the counters above.
var missions: Array = []
const MISSION_BONUS: int = 100 ## P18: points per completed mission.

var max_lives: int = 3 ## P14: deaths per run before game over.

var best_score: int = 0 ## P14: best distance, persisted.

var run_time: float = 0.0


func _ready() -> void:
	_load_best()
	reset_run()


func _process(delta: float) -> void:
	if current_state == State.RUNNING:
		run_time += delta
		_update_missions() ## P18: survive-time mission ticks here.
		# P17: combo expires if no scoring action within the window.
		if combo > 0:
			combo_timer -= delta
			if combo_timer <= 0.0:
				combo = 0


func reset_run() -> void:
	score = 0
	deaths = 0
	bug_count = 0
	near_miss_count = 0
	combo = 0
	combo_timer = 0.0
	run_time = 0.0
	_init_missions()
	current_state = State.READY


## P18: the three launch missions. Data, not code — new missions are new dicts.
func _init_missions() -> void:
	missions = [
		{ "id": "bugs", "label": "BUGS", "target": 15, "progress": 0, "done": false, "unit": "" },
		{ "id": "near_miss", "label": "NEAR MISS", "target": 3, "progress": 0, "done": false, "unit": "" },
		{ "id": "survive", "label": "SURVIVE", "target": 45, "progress": 0, "done": false, "unit": "s" },
	]


## P18: refresh mission progress from the run counters. Completing one pays
## MISSION_BONUS points and fires the hook the UI listens to.
func _update_missions() -> void:
	for m in missions:
		if bool(m["done"]):
			continue
		match String(m["id"]):
			"bugs":
				m["progress"] = bug_count
			"near_miss":
				m["progress"] = near_miss_count
			"survive":
				m["progress"] = int(run_time)
		if int(m["progress"]) >= int(m["target"]):
			m["done"] = true
			add_score(MISSION_BONUS)
			mission_completed.emit(String(m["id"]))


## P14: call when a run ends. Saves best.
func finish_run() -> void:
	if score > best_score:
		best_score = score
		_save_best()
	current_state = State.FINISHED


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://gecko_run.cfg") == OK:
		best_score = int(cfg.get_value("records", "best_score", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_score", best_score)
	cfg.save("user://gecko_run.cfg")


func start_run() -> void:
	reset_run()
	current_state = State.RUNNING


func register_death() -> void:
	deaths += 1
	combo = 0 ## P17: death breaks the combo.
	combo_timer = 0.0
	current_state = State.DEAD


func respawn() -> void:
	# Instant respawn at last checkpoint; checkpoint logic lives in mission_director.
	current_state = State.RUNNING


func add_score(points: int) -> void:
	score += points


func collect_bug() -> void:
	bug_count += 1
	_bump_combo()
	add_score(10 * _multiplier())
	_update_missions() ## P18.


## P15: the gecko survived a hazard's ACTIVE phase from close range.
## P17: worth 50 x combo multiplier — the "one more run" juice.
func register_near_miss() -> void:
	near_miss_count += 1
	_bump_combo()
	add_score(50 * _multiplier())
	_update_missions() ## P18.


## P17: scoring actions build the combo (up to COMBO_MAX). Each action
## refreshes the timer.
func _bump_combo() -> void:
	combo = mini(combo + 1, COMBO_MAX)
	combo_timer = COMBO_WINDOW


## P17: 1x for the first action, 2x for the second, etc.
func _multiplier() -> int:
	return maxi(1, combo)
