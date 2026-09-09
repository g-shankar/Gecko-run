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


func _on_state_changed(new_state: int) -> void:
	if new_state == _gs().State.READY:
		_show_only(_start_screen)
	elif new_state == _gs().State.RUNNING:
		_show_only(_hud)
		get_tree().paused = false
	elif new_state == _gs().State.FINISHED:
		_update_game_over()
		_show_only(_game_over)


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "%d m" % new_score


func _on_deaths_changed(new_count: int) -> void:
	var left: int = _gs().max_lives - new_count
	_lives_label.text = "Lives: %d" % maxi(left, 0)


func _process(_delta: float) -> void:
	# Shield indicator follows the gecko.
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null:
		_shield_label.visible = int(gecko.get("shield_charges")) > 0


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


func _on_start_pressed() -> void:
	_gs().current_state = _gs().State.RUNNING


# --- HUD ---

func _build_hud() -> void:
	_hud = Control.new()
	_full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_score_label = _make_label("0 m", 40)
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
	_final_score_label = _make_label("0 m", 40)
	_final_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_final_score_label.position = Vector2(-200, 270)
	_final_score_label.size = Vector2(400, 60)
	_final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.add_child(_final_score_label)
	_best_label = _make_label("Best: 0 m", 28)
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
	_final_score_label.text = "%d m" % _gs().score
	_best_label.text = "Best: %d m" % _gs().best_score


func _restart_run() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("reset_for_new_run"):
		gecko.reset_for_new_run()
	_gs().reset_run()
	_gs().current_state = _gs().State.RUNNING
