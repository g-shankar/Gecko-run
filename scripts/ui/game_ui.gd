extends CanvasLayer
## Gecko Run — game UI (spec P14).
##
## One CanvasLayer owning four screens: Start, HUD, Pause, Game Over.
## The game can be started, paused, and restarted from UI alone — no
## keyboard needed. Buttons are big; this is a mobile game.
##
## LEARNING NOTES (for Gowrishankar):
## - CanvasLayer draws ABOVE the 3D world, always on screen. HUD lives here.
## - Control nodes are Godot's UI building blocks: Labels show text,
##   Buttons are tappable. Anchors pin them to screen edges.
## - get_tree().paused freezes the 3D world. The UI sets
##   process_mode = ALWAYS so buttons still work while paused.

func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")
##   process_mode = ALWAYS so buttons still work while paused.

var _start_screen: Control
var _hud: Control
var _pause_menu: Control
var _game_over: Control
var _score_label: Label
var _lives_label: Label
var _shield_label: Label
var _near_miss_label: Label ## P15: "NEAR MISS +50!" popup.
var _near_miss_timer: float = 0.0
var _combo_label: Label ## P17: "COMBO x3" indicator.
var _mission_label: Label ## P18: mission tracker ("BUGS 7/15").
var _mission_popup_label: Label ## P18: "MISSION COMPLETE!" popup.
var _mission_popup_timer: float = 0.0
var _speed_label: Label ## P19: "SPEED!" indicator while boosted.
var _skin_buttons: Array = [] ## P23: character-select swatches.
var _final_score_label: Label
var _best_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_start_screen()
	_build_hud()
	_build_pause_menu()
	_build_game_over()
	var gs := _gs()
	if gs == null:
		# No GameState (unit test): hide UI, don't connect.
		for p in [_start_screen, _hud, _pause_menu, _game_over]:
			p.visible = false
		return
	_show_only(_start_screen)
	gs.state_changed.connect(_on_state_changed)
	gs.score_changed.connect(_on_score_changed)
	gs.deaths_changed.connect(_on_deaths_changed)
	gs.near_misses_changed.connect(_on_near_miss)
	gs.combo_changed.connect(_on_combo_changed)
	gs.mission_completed.connect(_on_mission_completed)


func _on_state_changed(new_state: int) -> void:
	if new_state == _gs().State.READY:
		_refresh_skin_buttons() ## P23: show the persisted choice.
		_show_only(_start_screen)
	elif new_state == _gs().State.RUNNING:
		_show_only(_hud)
		get_tree().paused = false
	elif new_state == _gs().State.FINISHED:
		_update_game_over()
		_show_only(_game_over)


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "SCORE %d" % new_score ## P22: points, not meters.


func _on_deaths_changed(new_count: int) -> void:
	var left: int = _gs().max_lives - new_count
	_lives_label.text = "Lives: %d" % maxi(left, 0)


## P15: flash the near-miss popup center-screen. The juice.
## P22: shows the ACTUAL award (50 x current combo), not a stale "+50!".
func _on_near_miss(_new_count: int) -> void:
	_near_miss_label.text = "NEAR MISS +%d!" % (50 * maxi(1, _gs().combo))
	_near_miss_label.visible = true
	_near_miss_label.modulate.a = 1.0
	_near_miss_timer = 1.2


## P17: show/hide the combo multiplier.
func _on_combo_changed(new_combo: int) -> void:
	if new_combo >= 2:
		_combo_label.text = "COMBO x%d" % new_combo
		_combo_label.visible = true
	else:
		_combo_label.visible = false


## P18: flash "MISSION COMPLETE!" center-screen.
func _on_mission_completed(_mission_id: String) -> void:
	_mission_popup_label.visible = true
	_mission_popup_label.modulate.a = 1.0
	_mission_popup_timer = 1.6


func _process(delta: float) -> void:
	# Shield indicator follows the gecko.
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null:
		_shield_label.visible = int(gecko.get("shield_charges")) > 0
		# P19: speed indicator follows the boost timer.
		_speed_label.visible = float(gecko.get("_speed_boost_timer") or 0.0) > 0.0
	_update_mission_tracker() ## P18.
	# P15: near-miss popup fades out.
	if _near_miss_timer > 0.0:
		_near_miss_timer -= delta
		_near_miss_label.modulate.a = clampf(_near_miss_timer / 1.2, 0.0, 1.0)
		if _near_miss_timer <= 0.0:
			_near_miss_label.visible = false
	# P18: mission popup fades out.
	if _mission_popup_timer > 0.0:
		_mission_popup_timer -= delta
		_mission_popup_label.modulate.a = clampf(_mission_popup_timer / 1.6, 0.0, 1.0)
		if _mission_popup_timer <= 0.0:
			_mission_popup_label.visible = false


## P18: show the first incomplete mission's progress. All done: celebrate.
func _update_mission_tracker() -> void:
	var gs := _gs()
	if gs == null or _mission_label == null:
		return
	for m in (gs.get("missions") as Array):
		if not bool(m["done"]):
			_mission_label.text = "%s %d/%d%s" % [
				String(m["label"]), int(m["progress"]),
				int(m["target"]), String(m["unit"])]
			return
	_mission_label.text = "ALL MISSIONS DONE!"


func _show_only(panel: Control) -> void:
	for p in [_start_screen, _hud, _pause_menu, _game_over]:
		p.visible = (p == panel)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 72)
	b.add_theme_font_size_override("font_size", 32)
	return b


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


# --- Start screen ---

func _build_start_screen() -> void:
	_start_screen = Control.new()
	_full_rect(_start_screen)
	add_child(_start_screen)
	var title := _make_label("GECKO RUN", 72)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 180)
	title.size = Vector2(400, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(title)
	var sub := _make_label("A tiny gecko. A big backyard.", 28)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-200, 280)
	sub.size = Vector2(400, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(sub)
	var start_btn := _make_button("TAP TO START")
	start_btn.set_anchors_preset(Control.PRESET_CENTER)
	start_btn.position = Vector2(-140, -36)
	start_btn.pressed.connect(_on_start_pressed)
	_start_screen.add_child(start_btn)
	_build_skin_select() ## P23: choose-your-gecko, below the start button.


func _on_start_pressed() -> void:
	_gs().current_state = _gs().State.RUNNING


# --- P23: character select ---

## Five tappable swatches on the start screen. Touch-native Buttons; the
## selected one gets a ▶ marker. Persists via GameState and applies live.
func _build_skin_select() -> void:
	var label := _make_label("CHOOSE YOUR GECKO", 24)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-200, 70)
	label.size = Vector2(400, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(label)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.position = Vector2(-265, 112)
	row.size = Vector2(530, 64)
	row.add_theme_constant_override("separation", 6)
	_start_screen.add_child(row)
	_skin_buttons.clear()
	for i in GeckoSkins.count():
		var b := Button.new()
		b.custom_minimum_size = Vector2(100, 60)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", GeckoSkins.skin_tint(i).lightened(0.35))
		b.pressed.connect(_on_skin_pressed.bind(i))
		row.add_child(b)
		_skin_buttons.append(b)
	_refresh_skin_buttons()


func _on_skin_pressed(index: int) -> void:
	var gs := _gs()
	if gs == null:
		return
	gs.set_skin(index)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("apply_selected_skin"):
		gecko.apply_selected_skin()
	_refresh_skin_buttons()


func _refresh_skin_buttons() -> void:
	var gs := _gs()
	var sel := int(gs.selected_skin) if gs != null else 0
	for i in _skin_buttons.size():
		var b := _skin_buttons[i] as Button
		var mark := "▶ " if i == sel else ""
		b.text = mark + GeckoSkins.skin_short(i)


# --- HUD ---

func _build_hud() -> void:
	_hud = Control.new()
	_full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_score_label = _make_label("SCORE 0", 40)
	_score_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_score_label.position = Vector2(20, 16)
	_hud.add_child(_score_label)
	_lives_label = _make_label("Lives: 3", 28)
	_lives_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lives_label.position = Vector2(20, 64)
	_hud.add_child(_lives_label)
	_shield_label = _make_label("SHIELD", 28)
	_shield_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_shield_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shield_label.position = Vector2(20, 104)
	_shield_label.visible = false
	_hud.add_child(_shield_label)
	var pause_btn := _make_button("II")
	pause_btn.custom_minimum_size = Vector2(72, 72)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-92, 16)
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.pressed.connect(_on_pause_pressed)
	_hud.add_child(pause_btn)
	# P15: near-miss popup, center-screen. Hidden until earned.
	_near_miss_label = _make_label("NEAR MISS +50!", 48)
	_near_miss_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_near_miss_label.set_anchors_preset(Control.PRESET_CENTER)
	_near_miss_label.position = Vector2(-200, -60)
	_near_miss_label.size = Vector2(400, 80)
	_near_miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_near_miss_label.visible = false
	_hud.add_child(_near_miss_label)
	# P17: combo indicator, top-right below pause. Hidden until x2.
	_combo_label = _make_label("COMBO x2", 32)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.position = Vector2(-220, 100)
	_combo_label.visible = false
	_hud.add_child(_combo_label)
	# P18: mission tracker, top-left below shield.
	_mission_label = _make_label("BUGS 0/15", 24)
	_mission_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.5))
	_mission_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_mission_label.position = Vector2(20, 144)
	_hud.add_child(_mission_label)
	# P18: mission-complete popup, center-screen above the near-miss one.
	_mission_popup_label = _make_label("MISSION COMPLETE!", 44)
	_mission_popup_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_mission_popup_label.set_anchors_preset(Control.PRESET_CENTER)
	_mission_popup_label.position = Vector2(-220, -140)
	_mission_popup_label.size = Vector2(440, 70)
	_mission_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_popup_label.visible = false
	_hud.add_child(_mission_popup_label)
	# P19: speed indicator, top-left below the mission tracker.
	_speed_label = _make_label("SPEED!", 28)
	_speed_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.15))
	_speed_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speed_label.position = Vector2(20, 184)
	_speed_label.visible = false
	_hud.add_child(_speed_label)


func _on_pause_pressed() -> void:
	get_tree().paused = true
	_show_only(_pause_menu)


# --- Pause menu ---

func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_full_rect(_pause_menu)
	add_child(_pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_full_rect(dim)
	_pause_menu.add_child(dim)
	var title := _make_label("PAUSED", 56)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-150, 200)
	title.size = Vector2(300, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_menu.add_child(title)
	var resume_btn := _make_button("RESUME")
	resume_btn.set_anchors_preset(Control.PRESET_CENTER)
	resume_btn.position = Vector2(-140, -80)
	resume_btn.pressed.connect(_on_resume_pressed)
	_pause_menu.add_child(resume_btn)
	var restart_btn := _make_button("RESTART")
	restart_btn.set_anchors_preset(Control.PRESET_CENTER)
	restart_btn.position = Vector2(-140, 20)
	restart_btn.pressed.connect(_on_restart_pressed)
	_pause_menu.add_child(restart_btn)


func _on_resume_pressed() -> void:
	_show_only(_hud)
	get_tree().paused = false


func _on_restart_pressed() -> void:
	get_tree().paused = false
	_restart_run()


# --- Game over ---

func _build_game_over() -> void:
	_game_over = Control.new()
	_full_rect(_game_over)
	add_child(_game_over)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	_full_rect(dim)
	_game_over.add_child(dim)
	var title := _make_label("GAME OVER", 64)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 160)
	title.size = Vector2(400, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.add_child(title)
	_final_score_label = _make_label("SCORE 0", 40)
	_final_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_final_score_label.position = Vector2(-200, 270)
	_final_score_label.size = Vector2(400, 60)
	_final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.add_child(_final_score_label)
	_best_label = _make_label("Best: 0 PTS", 28)
	_best_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_best_label.position = Vector2(-200, 330)
	_best_label.size = Vector2(400, 40)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.add_child(_best_label)
	var restart_btn := _make_button("RUN AGAIN")
	restart_btn.set_anchors_preset(Control.PRESET_CENTER)
	restart_btn.position = Vector2(-140, 60)
	restart_btn.pressed.connect(_on_restart_pressed)
	_game_over.add_child(restart_btn)


func _update_game_over() -> void:
	_final_score_label.text = "SCORE %d" % _gs().score
	_best_label.text = "Best: %d PTS" % _gs().best_score


func _restart_run() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("reset_for_new_run"):
		gecko.reset_for_new_run()
	_gs().reset_run()
	_gs().current_state = _gs().State.RUNNING
