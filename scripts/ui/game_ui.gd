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


func _fe() -> Node:
	return get_tree().get_first_node_in_group("frontend_ui")
##   process_mode = ALWAYS so buttons still work while paused.

var _start_screen: Control ## P26: the main menu (title + PLAY/GECKOS/PROFILE).
var _menu_player_label: Label ## P26: "GECKO · BEST 1234" chip on the menu.
var _hud: Control
var _pause_menu: Control
var _game_over: Control
var _score_label: Label
var _lives_label: Label
var _shield_label: Label
var _near_miss_label: Label ## P15: "NEAR MISS +50!" popup.
var _near_miss_timer: float = 0.0
var _combo_label: Label ## P17: "COMBO x3" indicator.
var _mission_popup_label: Label ## P18: "MISSION COMPLETE!" popup.
var _mission_popup_timer: float = 0.0
var _speed_label: Label ## P19: "SPEED!" indicator while boosted.
var _final_score_label: Label
var _best_label: Label
## --- P27: pitch-deck HUD ---
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const ABILITY_DEFS := [
	{ "id": "boost", "icon": "⚡", "name": "BOOST" },
	{ "id": "shield", "icon": "🛡", "name": "SHIELD" },
	{ "id": "camo", "icon": "🌿", "name": "CAMO" },
	{ "id": "tongue", "icon": "👅", "name": "TONGUE" },
]
## Key-art loadout: 2/1/1/2 charges per run.
const ABILITY_START_CHARGES := { "boost": 2, "shield": 1, "camo": 1, "tongue": 2 }
const STREAK_EVERY := 15 ## P27: bugs per bonus ability charge.
const CHARGE_CAP := 5 ## P27: no hoarding.
var _bug_label: Label ## P27: "🪲 12/25" top-right.
var _timer_label: Label ## P27: run timer MM:SS.
var _minimap: Control ## P27: the circular route map.
var _mission_body: Label ## P27: objective text in the mission panel.
var _ability_buttons := {} ## id -> Button.
var _ability_badges := {} ## id -> Label (charge count).
var _charges := {} ## id -> int, reset to ABILITY_START_CHARGES each run.
var _next_streak_at: int = STREAK_EVERY ## P27: next bug count that grants a charge.
var _bug_total: int = 25 ## P27: bug spawns on the current route.
var _last_minimap_progress: float = -1.0 ## P27: throttle minimap repaints.
var _last_minimap_meters: float = -1.0 ## P27: repaint on map switch too.
## P27: _refresh_ability_buttons only touches the buttons when the visible
## state actually changed — hammering theme overrides 60x/s cost ~9 ms/frame
## (P22's frame-count assumptions caught it).
var _ability_sig: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_ui") ## P26: the frontend hides this menu under its screens.
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
	gs.bugs_changed.connect(_on_bugs_changed) ## P27: bug counter + streak charges.
	gs.deaths_changed.connect(_on_deaths_changed)
	gs.near_misses_changed.connect(_on_near_miss)
	gs.combo_changed.connect(_on_combo_changed)
	gs.mission_completed.connect(_on_mission_completed)


func _on_state_changed(new_state: int) -> void:
	if new_state == _gs().State.READY:
		_refresh_menu() ## P26: player chip on the main menu.
		_show_only(_start_screen)
	elif new_state == _gs().State.RUNNING:
		_show_only(_hud)
		get_tree().paused = false
		_reset_ability_run() ## P27: fresh 2/1/1/2 loadout, streak armed.
	elif new_state == _gs().State.FINISHED:
		_update_game_over()
		_show_only(_game_over)


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "SCORE %d" % new_score ## P22: points, not meters.


func _on_deaths_changed(new_count: int) -> void:
	var left: int = maxi(_gs().max_lives - new_count, 0)
	_lives_label.text = "♥".repeat(left) if left > 0 else "—"


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
	var gs := _gs()
	# Shield / speed / ability indicators follow the gecko — no GameState
	# needed (P19's test runs the HUD with the autoload dropped).
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null:
		_shield_label.visible = int(gecko.get("shield_charges")) > 0
		# P19: speed indicator follows the boost timer.
		_speed_label.visible = float(gecko.get("_speed_boost_timer") or 0.0) > 0.0
		_refresh_ability_buttons(gecko) ## P27: change-detected, cheap.
	if gs == null:
		return # Unit-test mode: run counters have no driver.
	# P27: run timer MM:SS (only touch the label when the second changes).
	var t: int = int(gs.get("run_time"))
	var stamp := "%02d:%02d" % [t / 60, t % 60]
	if _timer_label.text != stamp:
		_timer_label.text = stamp
	_update_mission_tracker() ## P18, P27: into the mission panel now.
	_update_minimap() ## P27: change-detected.


## P18: the mission panel shows the first incomplete mission's progress.
## P27: friendlier objective text; all done: celebrate.
func _update_mission_tracker() -> void:
	var gs := _gs()
	if gs == null or _mission_body == null:
		return
	for m in (gs.get("missions") as Array):
		if not bool(m["done"]):
			_mission_body.text = _mission_body_text(m)
			return
	_mission_body.text = "🏁 ALL MISSIONS DONE!"


## P27: "Eat bugs  7/15" reads better than "BUGS 7/15".
func _mission_body_text(m: Dictionary) -> String:
	var target := int(m["target"])
	var prog := mini(int(m["progress"]), target)
	match String(m["id"]):
		"bugs":
			return "Eat bugs   %d/%d" % [prog, target]
		"near_miss":
			return "Near-miss hazards   %d/%d" % [prog, target]
		"survive":
			return "Survive the run   %ds/%ds" % [prog, target]
	return "%s %d/%d%s" % [String(m["label"]), prog, target, String(m["unit"])]


## P27: gecko z -> 0..1 along the route. Pure math, easy to unit-test:
## Backyard Dash is 364 m (z 6 to -358), Fence Line 196 m (z 6 to -190).
func route_progress(gecko_z: float, start_z: float, fence_z: float) -> float:
	var total: float = start_z - fence_z
	if total <= 0.0:
		return 0.0
	return clampf((start_z - gecko_z) / total, 0.0, 1.0)


## P27: drive the minimap from the live route + gecko position. Redraws only
## when the dot actually moved — a full canvas repaint every frame cost
## ~8 ms/frame in headless and slowed the whole game loop (P22 caught it).
func _update_minimap() -> void:
	if _minimap == null:
		return
	var level := get_tree().get_first_node_in_group("level")
	var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
	if level == null or gecko == null:
		return
	var data: Resource = level.get("level_data")
	if data == null:
		return
	var start_z: float = (data.get("start_position") as Vector3).z
	var fence_z: float = float(data.get("fence_z"))
	var prog := route_progress(gecko.global_position.z, start_z, fence_z)
	if absf(prog - _last_minimap_progress) < 0.002 \
			and _last_minimap_meters == start_z - fence_z:
		return
	_last_minimap_progress = prog
	_last_minimap_meters = start_z - fence_z
	_minimap.set("progress", prog)
	_minimap.set("route_meters", start_z - fence_z)
	_minimap.queue_redraw()


## P27: a run starts with the key-art loadout and the streak counter armed.
func _reset_ability_run() -> void:
	_charges = ABILITY_START_CHARGES.duplicate()
	_next_streak_at = STREAK_EVERY
	_ability_sig = "" ## Force the button refresh below.
	_compute_bug_total()
	_update_bug_label()
	_refresh_ability_buttons(get_tree().get_first_node_in_group("gecko"))


## P27: the "12/25" in the key art — total = bug spawns on this route.
func _compute_bug_total() -> void:
	_bug_total = 25
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		return
	var data: Resource = level.get("level_data")
	if data == null:
		return
	var n := 0
	for s in (data.get("spawns") as Array):
		if String((s as Dictionary).get("type", "")) == "bug":
			n += 1
	if n > 0:
		_bug_total = n


func _update_bug_label() -> void:
	var gs := _gs()
	if gs == null or _bug_label == null:
		return
	_bug_label.text = "🪲 %d/%d" % [int(gs.get("bug_count")), _bug_total]


## P27: bug counter + the streak rule: every 15 bugs = +1 random ability
## charge (capped at 5 each), so eating well keeps the bar stocked.
func _on_bugs_changed(new_count: int) -> void:
	_update_bug_label()
	var gs := _gs()
	if gs == null:
		return
	while new_count >= _next_streak_at:
		_grant_streak_charge()
		_next_streak_at += STREAK_EVERY


func _grant_streak_charge() -> void:
	var ids: Array = []
	for def in ABILITY_DEFS:
		var id := String(def["id"])
		if int(_charges.get(id, 0)) < CHARGE_CAP:
			ids.append(id)
	if ids.is_empty():
		return
	var pick := String(ids[randi() % ids.size()])
	_charges[pick] = int(_charges[pick]) + 1
	_refresh_ability_buttons(get_tree().get_first_node_in_group("gecko"))


## P27: tap an ability slot: spend a charge, fire the real mechanic.
func _on_ability_pressed(id: String) -> void:
	if int(_charges.get(id, 0)) <= 0:
		return
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko == null:
		return
	var fired := true
	match id:
		"boost":
			if gecko.has_method("give_speed_boost"):
				gecko.call("give_speed_boost")
		"shield":
			if gecko.has_method("give_shield"):
				gecko.call("give_shield")
		"camo":
			if gecko.has_method("give_camo"):
				gecko.call("give_camo")
		"tongue":
			if gecko.has_method("fire_tongue"):
				gecko.call("fire_tongue")
		_:
			fired = false
	if fired:
		_charges[id] = int(_charges[id]) - 1
		_refresh_ability_buttons(gecko)


## P27: badges show charges; empty slots dim + disable; the active ability
## glows gold. Change-detected: touching buttons 60x/s (theme overrides,
## label text) cost ~9 ms/frame in headless — now it only runs on change.
func _refresh_ability_buttons(gecko: Variant) -> void:
	var sig := ""
	var actives := {}
	for def in ABILITY_DEFS:
		var id := String(def["id"])
		var active := false
		if gecko != null:
			match id:
				"boost":
					active = float(gecko.get("_speed_boost_timer") or 0.0) > 0.0
				"shield":
					active = int(gecko.get("shield_charges")) > 0
				"camo":
					active = gecko.has_method("is_camouflaged") \
						and bool(gecko.call("is_camouflaged"))
				"tongue":
					active = float(gecko.get("_tongue_timer") or 0.0) > 0.0
		actives[id] = active
		sig += "%s:%d:%d;" % [id, int(_charges.get(id, 0)), int(active)]
	if sig == _ability_sig:
		return
	_ability_sig = sig
	for def in ABILITY_DEFS:
		var id := String(def["id"])
		var btn := _ability_buttons.get(id) as Button
		if btn == null:
			continue
		var n := int(_charges.get(id, 0))
		(_ability_badges[id] as Label).text = str(n)
		btn.disabled = n <= 0
		btn.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if bool(actives[id]) else Color.WHITE)


func _show_only(panel: Control) -> void:
	for p in [_start_screen, _hud, _pause_menu, _game_over]:
		p.visible = (p == panel)


## P26: the frontend calls this so its screens never double up with the
## menu. State changes still route through _on_state_changed as before.
func set_menu_hidden(hidden: bool) -> void:
	if _start_screen != null:
		_start_screen.visible = not hidden


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


# --- Main menu (was the P14 start screen; P26 made it a real menu) ---

func _build_start_screen() -> void:
	_start_screen = Control.new()
	_full_rect(_start_screen)
	add_child(_start_screen)
	var title := _make_label("GECKO RUN", 84)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 120)
	title.size = Vector2(600, 110)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(title)
	var sub := _make_label("A tiny gecko. A big backyard.", 28)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-300, 230)
	sub.size = Vector2(600, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(sub)
	_menu_player_label = _make_label("", 26)
	_menu_player_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu_player_label.position = Vector2(-300, 280)
	_menu_player_label.size = Vector2(600, 40)
	_menu_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_screen.add_child(_menu_player_label)
	var play_btn := _make_button("PLAY")
	play_btn.set_anchors_preset(Control.PRESET_CENTER)
	play_btn.position = Vector2(-160, -120)
	play_btn.pressed.connect(_on_play_pressed)
	_start_screen.add_child(play_btn)
	var geckos_btn := _make_button("GECKOS")
	geckos_btn.set_anchors_preset(Control.PRESET_CENTER)
	geckos_btn.position = Vector2(-160, -20)
	geckos_btn.pressed.connect(_on_geckos_pressed)
	_start_screen.add_child(geckos_btn)
	var profile_btn := _make_button("PROFILE")
	profile_btn.set_anchors_preset(Control.PRESET_CENTER)
	profile_btn.position = Vector2(-160, 80)
	profile_btn.pressed.connect(_on_profile_pressed)
	_start_screen.add_child(profile_btn)


## P26: player chip on the menu. Empty name (first launch) hides the chip —
## the frontend's name entry is showing on top anyway.
func _refresh_menu() -> void:
	var gs := _gs()
	if gs == null:
		return
	var n := String(gs.get("player_name"))
	if n.is_empty():
		_menu_player_label.text = ""
	else:
		_menu_player_label.text = "🦎  %s   ·   BEST %d PTS" % [n, int(gs.get("best_score"))]


func _on_play_pressed() -> void:
	var fe := _fe()
	if fe != null and fe.has_method("show_journey"):
		fe.call("show_journey")


func _on_geckos_pressed() -> void:
	var fe := _fe()
	if fe != null and fe.has_method("show_geckos"):
		fe.call("show_geckos")


func _on_profile_pressed() -> void:
	var fe := _fe()
	if fe != null and fe.has_method("show_profile"):
		fe.call("show_profile")


## P14: kept for the UI-driven start path (and its test). The frontend's
## map cards go through FrontendUI.start_map, which also ends up here.
func _on_start_pressed() -> void:
	_gs().current_state = _gs().State.RUNNING


# --- HUD ---

## P27: the pitch-deck HUD. Layout (1280x720 base, anchored):
## - top-left: "GECKO RUN" two-tone wordmark + tagline + score/lives chips
## - top-right: bug counter, run timer, circular minimap
## - right edge: 4 tappable ability slots (BOOST/SHIELD/CAMO/TONGUE)
## - bottom-left: MISSION panel with the active objective
## - bottom-right: DASH + pause (thumb zone, clear of the ability bar)
func _build_hud() -> void:
	_hud = Control.new()
	_full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	# --- Wordmark: "GECKO" green + "RUN" yellow, chunky outline. ---
	var word := HBoxContainer.new()
	word.set_anchors_preset(Control.PRESET_TOP_LEFT)
	word.position = Vector2(20, 10)
	word.add_theme_constant_override("separation", 16)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(word)
	var gecko_w := _make_label("GECKO", 54)
	gecko_w.add_theme_color_override("font_color", Color(0.38, 0.86, 0.28))
	gecko_w.add_theme_color_override("font_outline_color", Color(0.04, 0.14, 0.05))
	gecko_w.add_theme_constant_override("outline_size", 10)
	word.add_child(gecko_w)
	var run_w := _make_label("RUN", 54)
	run_w.add_theme_color_override("font_color", Color(1.0, 0.82, 0.12))
	run_w.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.02))
	run_w.add_theme_constant_override("outline_size", 10)
	word.add_child(run_w)
	var tagline := _make_label("SMALL GECKO. BIG ADVENTURES.", 20)
	tagline.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tagline.position = Vector2(22, 78)
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(tagline)
	# --- Score / lives chips under the wordmark (restyled, not removed). ---
	_score_label = _make_label("SCORE 0", 30)
	_score_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_score_label.position = Vector2(22, 110)
	_hud.add_child(_score_label)
	_lives_label = _make_label("♥♥♥", 24)
	_lives_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_lives_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lives_label.position = Vector2(22, 146)
	_hud.add_child(_lives_label)
	_shield_label = _make_label("🛡 SHIELD UP", 24)
	_shield_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_shield_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shield_label.position = Vector2(22, 178)
	_shield_label.visible = false
	_hud.add_child(_shield_label)
	_speed_label = _make_label("⚡ SPEED!", 24)
	_speed_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.15))
	_speed_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speed_label.position = Vector2(22, 210)
	_speed_label.visible = false
	_hud.add_child(_speed_label)
	# --- Top-right cluster: bug counter, timer, circular minimap. ---
	_bug_label = _make_label("🪲 0/25", 36)
	_bug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bug_label.position = Vector2(-450, 16)
	_bug_label.size = Vector2(256, 48)
	_bug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_bug_label)
	_timer_label = _make_label("00:00", 32)
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-450, 66)
	_timer_label.size = Vector2(256, 42)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_timer_label)
	_minimap = MinimapScript.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-186, 14)
	_minimap.custom_minimum_size = Vector2(170, 170)
	_minimap.size = Vector2(170, 170)
	_hud.add_child(_minimap)
	# --- Right edge: the ability bar. 88px+ touch targets, charge badges. ---
	var abox := VBoxContainer.new()
	abox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	abox.position = Vector2(-116, -200)
	abox.add_theme_constant_override("separation", 14)
	abox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(abox)
	for def in ABILITY_DEFS:
		var id := String(def["id"])
		var slot := Button.new()
		slot.text = "%s\n%s" % [String(def["icon"]), String(def["name"])]
		slot.custom_minimum_size = Vector2(92, 92)
		slot.add_theme_font_size_override("font_size", 24)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.pressed.connect(_on_ability_pressed.bind(id))
		abox.add_child(slot)
		_ability_buttons[id] = slot
		var badge := _make_badge("0")
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.position = Vector2(-34, -34)
		slot.add_child(badge)
		_ability_badges[id] = badge.get_node("Label")
	# --- Bottom-left: the MISSION panel. ---
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(20, -164)
	panel.custom_minimum_size = Vector2(380, 140)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0, 0, 0, 0.55)
	pstyle.set_corner_radius_all(16)
	pstyle.content_margin_left = 18.0
	pstyle.content_margin_right = 18.0
	pstyle.content_margin_top = 12.0
	pstyle.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", pstyle)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	var pvbox := VBoxContainer.new()
	pvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pvbox)
	var mtitle := _make_label("🎯 MISSION", 20)
	mtitle.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pvbox.add_child(mtitle)
	_mission_body = _make_label("Eat bugs  0/15", 26)
	_mission_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pvbox.add_child(_mission_body)
	# --- Bottom-right thumb zone: DASH + pause, clear of the ability bar. ---
	var dash_btn := Button.new()
	dash_btn.text = "DASH"
	dash_btn.custom_minimum_size = Vector2(100, 100)
	dash_btn.add_theme_font_size_override("font_size", 22)
	dash_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dash_btn.position = Vector2(-120, -120)
	dash_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	dash_btn.pressed.connect(_on_dash_pressed)
	_hud.add_child(dash_btn)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(64, 64)
	pause_btn.add_theme_font_size_override("font_size", 24)
	pause_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pause_btn.position = Vector2(-200, -84)
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
	# P17: combo indicator, top-right under the timer. Hidden until x2.
	_combo_label = _make_label("COMBO x2", 32)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.position = Vector2(-450, 112)
	_combo_label.size = Vector2(256, 40)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.visible = false
	_hud.add_child(_combo_label)
	# P18: mission-complete popup, center-screen above the near-miss one.
	_mission_popup_label = _make_label("MISSION COMPLETE!", 44)
	_mission_popup_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_mission_popup_label.set_anchors_preset(Control.PRESET_CENTER)
	_mission_popup_label.position = Vector2(-220, -140)
	_mission_popup_label.size = Vector2(440, 70)
	_mission_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_popup_label.visible = false
	_hud.add_child(_mission_popup_label)


## P27: the little dark circle with the charge count on each ability slot.
func _make_badge(text: String) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(32, 32)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.75)
	st.set_corner_radius_all(16)
	st.border_color = Color(1, 1, 1, 0.8)
	st.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.name = "Label"
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## P27: the new HUD's own DASH button (the dev HUD's DASH is hidden with the
## debug overlay now). Same call the old button made.
func _on_dash_pressed() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("request_dash"):
		gecko.request_dash()


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
	restart_btn.position = Vector2(-140, 40)
	restart_btn.pressed.connect(_on_restart_pressed)
	_game_over.add_child(restart_btn)
	# P26: results -> map select, not a dead end.
	var maps_btn := _make_button("MAPS")
	maps_btn.set_anchors_preset(Control.PRESET_CENTER)
	maps_btn.position = Vector2(-140, 140)
	maps_btn.pressed.connect(_on_maps_pressed)
	_game_over.add_child(maps_btn)


func _update_game_over() -> void:
	_final_score_label.text = "SCORE %d" % _gs().score
	_best_label.text = "Best: %d PTS" % _gs().best_score


func _restart_run() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("reset_for_new_run"):
		gecko.reset_for_new_run()
	_gs().reset_run()
	_gs().current_state = _gs().State.RUNNING


## P26: game over -> map select. The frontend lands on the map screen
## (GameState.return_to) instead of the main menu.
func _on_maps_pressed() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("reset_for_new_run"):
		gecko.reset_for_new_run()
	_gs().return_to = "maps"
	_gs().reset_run()
