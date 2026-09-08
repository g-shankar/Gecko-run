extends Node
## Autoload singleton: run state machine, score, deaths, run timer, bug count.
## Other systems read/write through here; UI hooks into the signals.

enum State { READY, RUNNING, DEAD, FINISHED }

signal state_changed(new_state: State)
signal score_changed(new_score: int)
signal bugs_changed(new_count: int)
signal deaths_changed(new_count: int)

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

var run_time: float = 0.0


func _ready() -> void:
	reset_run()


func _process(delta: float) -> void:
	if current_state == State.RUNNING:
		run_time += delta


func reset_run() -> void:
	score = 0
	deaths = 0
	bug_count = 0
	run_time = 0.0
	current_state = State.READY


func start_run() -> void:
	reset_run()
	current_state = State.RUNNING


func register_death() -> void:
	deaths += 1
	current_state = State.DEAD


func respawn() -> void:
	# Instant respawn at last checkpoint; checkpoint logic lives in mission_director.
	current_state = State.RUNNING


func finish_run() -> void:
	current_state = State.FINISHED


func add_score(points: int) -> void:
	score += points


func collect_bug() -> void:
	bug_count += 1
	add_score(10)
