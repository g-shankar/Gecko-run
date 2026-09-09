extends SceneTree
## Gecko Run — P17 tests: combo multiplier.
##
## 1. First bug: combo=1, +10 points (1x).
## 2. Second bug quickly: combo=2, +20 points (2x).
## 3. Combo caps at 8x.
## 4. Death resets combo.
## 5. Combo expires after COMBO_WINDOW without scoring.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _initialize() -> void:
	var gs_script: Script = load("res://scripts/systems/game_state.gd")
	var gs: Node = gs_script.new()
	gs.name = "GameState"
	root.add_child(gs)
	gs.start_run()

	# --- 1: first bug ---
	gs.collect_bug()
	check(gs.combo == 1, "first scoring action: combo=1")
	check(gs.score == 10, "first bug: +10 (1x) (score=%d)" % gs.score)

	# --- 2: second bug (within window) ---
	gs.collect_bug()
	check(gs.combo == 2, "second action: combo=2")
	check(gs.score == 30, "second bug: +20 (2x), total 30 (score=%d)" % gs.score)

	# --- 3: near-miss at combo 2 ---
	gs.register_near_miss()
	# combo becomes 3, multiplier 3x, +150. Total: 30 + 150 = 180.
	check(gs.combo == 3, "near-miss bumps combo to 3")
	check(gs.score == 180, "near-miss at 3x: +150 (score=%d)" % gs.score)

	# --- 4: cap at 8x ---
	for i in 10:
		gs.collect_bug()
	check(gs.combo == 8, "combo caps at 8 (combo=%d)" % gs.combo)
	var score_before: int = gs.score
	gs.collect_bug() # Should still be 8x: +80.
	check(gs.score == score_before + 80, "capped at 8x: +80 (score=%d)" % gs.score)

	# --- 5: death resets ---
	gs.register_death()
	check(gs.combo == 0, "death resets combo")
	gs.respawn()
	gs.collect_bug()
	check(gs.score == score_before + 80 + 10, "after death: back to 1x (score=%d)" % gs.score)

	# --- 6: expiry ---
	gs.collect_bug() # combo=2
	check(gs.combo == 2, "combo rebuilt to 2")
	# Simulate 5 seconds passing (window is 4s).
	for i in 300: # 300 frames at 60fps = 5s
		await process_frame
	check(gs.combo == 0, "combo expires after window (combo=%d)" % gs.combo)

	print("--- P17: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
