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

var best_score: int = 0 ## P14: best score, persisted. P22: was mislabeled "distance".

var selected_skin: int = 0 ## P23: hero skin index, persisted.

## P26: player profile — local save on device, no server account yet.
## Versioned JSON so future updates can migrate old saves.
const PROFILE_VERSION: int = 1
var profile_path: String = "user://gecko_run_profile.json" ## var: tests isolate.
var player_name: String = "" ## Empty = first launch: ask for a name.
var total_runs: int = 0
var total_bugs: int = 0
var total_near_miss: int = 0
var missions_completed_total: int = 0
var map_best := {} ## map_id -> best score on that map.
var current_map_id: String = "florida_backyard" ## P26: which map is loaded.
var return_to: String = "menu" ## P26: "maps" = game over should land on map select.

var run_time: float = 0.0


func _ready() -> void:
	_load_profile()
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


## P14: call when a run ends. Saves best and records profile stats (P26).
func finish_run() -> void:
	if score > best_score:
		best_score = score
	record_run_end() ## P26: totals, per-map best, persist.
	current_state = State.FINISHED


## P26: load the versioned profile; migrate the legacy cfg on first run.
func _load_profile() -> void:
	player_name = ""
	total_runs = 0
	total_bugs = 0
	total_near_miss = 0
	missions_completed_total = 0
	map_best = {}
	if FileAccess.file_exists(profile_path):
		var f := FileAccess.open(profile_path, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == PROFILE_VERSION:
				player_name = String(data.get("player_name", ""))
				selected_skin = clampi(int(data.get("selected_skin", 0)), 0, 4)
				best_score = int(data.get("best_score", 0))
				total_runs = int(data.get("total_runs", 0))
				total_bugs = int(data.get("total_bugs", 0))
				total_near_miss = int(data.get("total_near_miss", 0))
				missions_completed_total = int(data.get("missions_completed_total", 0))
				map_best = data.get("map_best", {})
				if typeof(map_best) != TYPE_DICTIONARY:
					map_best = {}
				return
	_migrate_legacy_profile()


## P26: first run with the new system — carry best_score/selected_skin over
## from the old ConfigFile save, then write the fresh JSON profile.
func _migrate_legacy_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://gecko_run.cfg") == OK:
		best_score = int(cfg.get_value("records", "best_score", 0))
		selected_skin = clampi(int(cfg.get_value("records", "selected_skin", 0)), 0, 4)
	save_profile()


func save_profile() -> void:
	var data := {
		"version": PROFILE_VERSION,
		"player_name": player_name,
		"selected_skin": selected_skin,
		"best_score": best_score,
		"total_runs": total_runs,
		"total_bugs": total_bugs,
		"total_near_miss": total_near_miss,
		"missions_completed_total": missions_completed_total,
		"map_best": map_best,
	}
	var f := FileAccess.open(profile_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


## P26: set the player name (first launch / rename). Never blank.
func set_player_name(n: String) -> void:
	var clean := n.strip_edges().left(12)
	if clean.is_empty():
		clean = "GECKO"
	player_name = clean
	save_profile()


## P26: fold one finished run into the lifetime stats and persist.
func record_run_end() -> void:
	total_runs += 1
	total_bugs += bug_count
	total_near_miss += near_miss_count
	var done := 0
	for m in missions:
		if bool(m["done"]):
			done += 1
	missions_completed_total += done
	var prev := int(map_best.get(current_map_id, 0))
	if score > prev:
		map_best[current_map_id] = score
	save_profile()


## P23: pick a hero skin; persists immediately so the choice survives.
## P26: persists through the versioned profile, not the legacy cfg.
func set_skin(index: int) -> void:
	selected_skin = clampi(index, 0, 4)
	save_profile()


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
	# P22: game-feel — a small camera kick and a gold flash at the gecko.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("add_trauma"):
		rig.add_trauma(0.35)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null:
		FX.burst(get_tree().root,
			(gecko as Node3D).global_position + Vector3(0, 0.8, 0),
			Color(1.0, 0.85, 0.2))


## P17: scoring actions build the combo (up to COMBO_MAX). Each action
## refreshes the timer.
func _bump_combo() -> void:
	combo = mini(combo + 1, COMBO_MAX)
	combo_timer = COMBO_WINDOW


## P17: 1x for the first action, 2x for the second, etc.
func _multiplier() -> int:
	return maxi(1, combo)
