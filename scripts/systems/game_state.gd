extends Node
## Autoload singleton: run state machine, score, deaths, run timer, bug count.
## Other systems read/write through here; UI hooks into the signals.

enum State { READY, RUNNING, DEAD, FINISHED }

signal state_changed(new_state: State)
signal score_changed(new_score: int)
signal bugs_changed(new_count: int)
signal deaths_changed(new_count: int)
signal near_misses_changed(new_count: int) ## P15: near-miss counter for UI.

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

var max_lives: int = 3 ## P14: deaths per run before game over.

var best_score: int = 0 ## P14: best distance, persisted.

var run_time: float = 0.0


func _ready() -> void:
	_load_best()
	reset_run()


func _process(delta: float) -> void:
	if current_state == State.RUNNING:
		run_time += delta


func reset_run() -> void:
	score = 0
	deaths = 0
	bug_count = 0
	near_miss_count = 0
	run_time = 0.0
	current_state = State.READY


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
	current_state = State.DEAD


func respawn() -> void:
	# Instant respawn at last checkpoint; checkpoint logic lives in mission_director.
	current_state = State.RUNNING


func add_score(points: int) -> void:
	score += points


func collect_bug() -> void:
	bug_count += 1
	add_score(10)


## P15: the gecko survived a hazard's ACTIVE phase from close range.
## Worth 50 points — the "one more run" juice.
func register_near_miss() -> void:
	near_miss_count += 1
	add_score(50)
