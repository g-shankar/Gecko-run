extends CanvasLayer
## Gecko Run — P26 front-end journey.
##
## Launch -> (first time) name entry -> main menu (in GameUI) ->
## journey/worlds -> map select -> run -> results -> map select.
##
## A second CanvasLayer above GameUI owning the pre/post-run screens:
## name entry, gecko select (real 3D hero preview), journey, map select,
## profile, plus the run-start fade-in. GameUI keeps HUD/pause/game-over.
## Touch-first: big buttons, no tiny text.

var _name_entry: Control
var _gecko_select: Control
var _journey: Control
var _map_select: Control
var _profile: Control
var _fade: ColorRect

var _name_input: LineEdit

var _preview_gecko: MeshInstance3D
var _preview_angle: float = 0.0
var _skin_name_label: Label
var _skin_buttons: Array = []
var _swiping := false
var _swipe_from := Vector2.ZERO

var _map_card_box: VBoxContainer
var _profile_name_label: Label
var _profile_stats_label: Label


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func _ready() -> void:
	add_to_group("frontend_ui")
	_build_fade()
	_build_name_entry()
	_build_gecko_select()
	_build_journey()
	_build_map_select()
	_build_profile()
	_show_only(null)
	var gs := _gs()
	if gs == null:
		return # Unit test: screens exist, nothing drives them.
	gs.state_changed.connect(_on_state_changed)
	_on_state_changed(int(gs.get("current_state")))


func _process(delta: float) -> void:
	if _gecko_select.visible and _preview_gecko != null:
		_preview_angle += delta * 0.7
		_preview_gecko.rotation.y = _preview_angle


func _on_state_changed(new_state: int) -> void:
	var gs := _gs()
	if gs == null:
		return
	var READY: int = _gs().State.READY
	var RUNNING: int = _gs().State.RUNNING
	if new_state == READY:
		if String(gs.get("player_name")).is_empty():
			_name_input.text = "GECKO"
			_show_only(_name_entry)
		elif String(gs.get("return_to")) == "maps":
			gs.set("return_to", "menu")
			_refresh_map_cards()
			_show_only(_map_select)
		else:
			_show_only(null) # Main menu (GameUI) shows underneath.
	elif new_state == RUNNING:
		_show_only(null)
	else:
		_show_only(null) # DEAD: HUD stays. FINISHED: game over shows.


# --- public API: driven by the GameUI main menu and the game-over screen ---

func show_journey() -> void:
	_show_only(_journey)


func show_geckos() -> void:
	_refresh_skin_ui()
	_show_only(_gecko_select)


func show_profile() -> void:
	_refresh_profile()
	_show_only(_profile)


func show_name_entry(prefill: String) -> void:
	_name_input.text = prefill
	_show_only(_name_entry)


func back_to_menu() -> void:
	_show_only(null)


## P26: the whole "tap a map and play" path — swap the route, reset the
## gecko and camera, open with a fade + camera sweep, and go.
func start_map(map_id: String) -> void:
	var gs := _gs()
	if gs == null:
		return
	var route := WorldData.route_for_map(map_id)
	if route.is_empty():
		return
	gs.set("current_map_id", map_id)
	var level := get_tree().get_first_node_in_group("level")
	if level != null and level.has_method("load_route"):
		level.call("load_route", route)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("reset_for_new_run"):
		gecko.call("reset_for_new_run")
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("intro_sweep"):
		rig.call("intro_sweep")
	gs.call("start_run")
	_play_fade_in()


func _play_fade_in() -> void:
	_fade.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_OUT)


# --- construction helpers ---

func _show_only(panel: Control) -> void:
	for p in [_name_entry, _gecko_select, _journey, _map_select, _profile]:
		p.visible = (p == panel)
	# P26: hide the GameUI main menu while a frontend screen is up so titles
	# and buttons never double up. It returns only when we land on the menu
	# at READY — never mid-run, never on a results screen.
	var gs := _gs()
	var ready_state: int = gs.State.READY if gs != null else -1
	var show_menu: bool = panel == null and gs != null and int(gs.get("current_state")) == ready_state
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("set_menu_hidden"):
		ui.call("set_menu_hidden", not show_menu)


func _make_button(text: String, min_size := Vector2(320, 84), font_size := 32) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
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


func _screen() -> Control:
	var s := Control.new()
	_full_rect(s)
	s.visible = false
	add_child(s)
	return s


func _dim(parent: Control, alpha := 0.62) -> void:
	var d := ColorRect.new()
	d.color = Color(0.02, 0.08, 0.05, alpha)
	_full_rect(d)
	parent.add_child(d)


func _title(parent: Control, text: String, y: float) -> void:
	var t := _make_label(text, 56)
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.position = Vector2(-400, y)
	t.size = Vector2(800, 80)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(t)


func _centered(parent: Control, c: Control, pos: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.position = pos
	parent.add_child(c)


# --- name entry ---

func _build_name_entry() -> void:
	_name_entry = _screen()
	_dim(_name_entry, 0.72)
	_title(_name_entry, "WHO'S PLAYING?", 150)
	_name_input = LineEdit.new()
	_name_input.max_length = 12
	_name_input.text = "GECKO"
	_name_input.custom_minimum_size = Vector2(480, 84)
	_name_input.add_theme_font_size_override("font_size", 40)
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centered(_name_entry, _name_input, Vector2(-240, -100))
	var go := _make_button("LET'S GO")
	_centered(_name_entry, go, Vector2(-160, 20))
	go.pressed.connect(_on_name_confirmed.bind(false))
	var skip := _make_button("SKIP", Vector2(320, 64), 26)
	_centered(_name_entry, skip, Vector2(-160, 130))
	skip.pressed.connect(_on_name_confirmed.bind(true))


func _on_name_confirmed(skipped: bool) -> void:
	var gs := _gs()
	if gs == null:
		return
	if skipped:
		gs.call("set_player_name", "GECKO")
	else:
		gs.call("set_player_name", _name_input.text)
	_show_only(null)


# --- gecko select (real 3D hero preview) ---

func _build_gecko_select() -> void:
	_gecko_select = _screen()
	_dim(_gecko_select)
	_title(_gecko_select, "CHOOSE YOUR GECKO", 60)
	# 3D turntable preview.
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_CENTER)
	svc.position = Vector2(-210, -260)
	svc.size = Vector2(420, 300)
	svc.custom_minimum_size = Vector2(420, 300)
	svc.stretch = true
	_gecko_select.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(420, 300)
	svc.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 0.5, 1.05)
	cam.look_at(Vector3(0, 0.2, 0), Vector3.UP)
	cam.fov = 38.0
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.25
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 0.06
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.10, 0.16, 0.10)
	dmat.roughness = 0.9
	disc.material_override = dmat
	disc.position = Vector3(0, -0.03, 0)
	vp.add_child(disc)
	var packed := load("res://assets/gecko/hero_gecko.glb") as PackedScene
	if packed != null:
		var inst: Node = packed.instantiate()
		var src := _find_first_mesh(inst)
		if src != null and src.mesh != null:
			_preview_gecko = MeshInstance3D.new()
			_preview_gecko.mesh = src.mesh
			_preview_gecko.scale = Vector3.ONE * 0.85 # P23 VISUAL_BASE_SCALE.
			vp.add_child(_preview_gecko)
		inst.queue_free()
	svc.gui_input.connect(_on_preview_input)
	# Skin name + arrows.
	_skin_name_label = _make_label("", 34)
	_skin_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centered(_gecko_select, _skin_name_label, Vector2(-210, 60))
	_skin_name_label.size = Vector2(420, 50)
	var prev := _make_button("<", Vector2(84, 84), 44)
	_centered(_gecko_select, prev, Vector2(-330, 40))
	prev.pressed.connect(_cycle_skin.bind(-1))
	var next := _make_button(">", Vector2(84, 84), 44)
	_centered(_gecko_select, next, Vector2(246, 40))
	next.pressed.connect(_cycle_skin.bind(1))
	# Skin buttons row.
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.position = Vector2(-280, 140)
	row.size = Vector2(560, 68)
	row.add_theme_constant_override("separation", 8)
	_gecko_select.add_child(row)
	_skin_buttons.clear()
	for i in GeckoSkins.count():
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 64)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", GeckoSkins.skin_tint(i).lightened(0.35))
		b.pressed.connect(_on_skin_chosen.bind(i))
		row.add_child(b)
		_skin_buttons.append(b)
	var done := _make_button("DONE")
	_centered(_gecko_select, done, Vector2(-160, 230))
	done.pressed.connect(back_to_menu)


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _find_first_mesh(c)
		if found != null:
			return found
	return null


func _on_preview_input(event: InputEvent) -> void:
	var touch := false
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
		touch = true
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
		touch = true
	if not touch:
		return
	if pressed:
		_swiping = true
		_swipe_from = pos
	elif released and _swiping:
		_swiping = false
		var dx := pos.x - _swipe_from.x
		if dx > 60.0:
			_cycle_skin(-1)
		elif dx < -60.0:
			_cycle_skin(1)


func _cycle_skin(dir: int) -> void:
	var gs := _gs()
	var sel := int(gs.get("selected_skin")) if gs != null else 0
	_on_skin_chosen((sel + dir + GeckoSkins.count()) % GeckoSkins.count())


func _on_skin_chosen(index: int) -> void:
	var gs := _gs()
	if gs == null:
		return
	gs.call("set_skin", index)
	if _preview_gecko != null:
		GeckoSkins.apply_skin(_preview_gecko, index)
	var gecko := get_tree().get_first_node_in_group("gecko")
	if gecko != null and gecko.has_method("apply_selected_skin"):
		gecko.call("apply_selected_skin")
	_refresh_skin_ui()


func _refresh_skin_ui() -> void:
	var gs := _gs()
	var sel := int(gs.get("selected_skin")) if gs != null else 0
	_skin_name_label.text = GeckoSkins.skin_name(sel)
	GeckoSkins.apply_skin(_preview_gecko, sel) ## The turntable shows the real skin.
	for i in _skin_buttons.size():
		var b := _skin_buttons[i] as Button
		b.text = ("▶ " if i == sel else "") + GeckoSkins.skin_short(i)


# --- journey / worlds ---

func _build_journey() -> void:
	_journey = _screen()
	_dim(_journey)
	_title(_journey, "WORLD TOUR", 70)
	var list := VBoxContainer.new()
	list.set_anchors_preset(Control.PRESET_CENTER)
	list.position = Vector2(-340, -205)
	list.size = Vector2(680, 410)
	list.add_theme_constant_override("separation", 16)
	_journey.add_child(list)
	for w in WorldData.WORLDS:
		var wid := String(w["id"])
		var b := _make_button("", Vector2(680, 126), 28)
		if bool(w["unlocked"]):
			b.text = "🌴  %s\n%s\nTAP TO EXPLORE" % [String(w["name"]), String(w["tagline"])]
			b.pressed.connect(_on_world_pressed.bind(wid))
		else:
			b.text = "???\nCOMING SOON"
			b.disabled = true
			b.modulate = Color(0.45, 0.45, 0.45)
		list.add_child(b)
	var back := _make_button("‹ MENU", Vector2(320, 64), 26)
	_centered(_journey, back, Vector2(-160, 240))
	back.pressed.connect(back_to_menu)


func _on_world_pressed(world_id: String) -> void:
	if world_id == "florida":
		_refresh_map_cards()
		_show_only(_map_select)


# --- map select ---

func _build_map_select() -> void:
	_map_select = _screen()
	_dim(_map_select)
	_title(_map_select, "FLORIDA", 70)
	var sub := _make_label("PICK YOUR MAP", 26)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-400, 150)
	sub.size = Vector2(800, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_select.add_child(sub)
	_map_card_box = VBoxContainer.new()
	_map_card_box.set_anchors_preset(Control.PRESET_CENTER)
	_map_card_box.position = Vector2(-300, -140)
	_map_card_box.size = Vector2(600, 300)
	_map_card_box.add_theme_constant_override("separation", 18)
	_map_select.add_child(_map_card_box)
	var back := _make_button("‹ WORLDS", Vector2(320, 64), 26)
	_centered(_map_select, back, Vector2(-160, 220))
	back.pressed.connect(show_journey)


func _refresh_map_cards() -> void:
	for c in _map_card_box.get_children():
		c.queue_free()
	var gs := _gs()
	for m in WorldData.maps_for_world("florida"):
		var mid := String(m["id"])
		var best := 0
		if gs != null:
			best = int((gs.get("map_best") as Dictionary).get(mid, 0))
		var b := _make_button("", Vector2(600, 120), 28)
		b.text = "%s\n%s   BEST %d" % [String(m["name"]), String(m["desc"]), best]
		b.pressed.connect(start_map.bind(mid))
		_map_card_box.add_child(b)


# --- profile ---

func _build_profile() -> void:
	_profile = _screen()
	_dim(_profile)
	_title(_profile, "PROFILE", 90)
	_profile_name_label = _make_label("", 40)
	_profile_name_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_profile_name_label.position = Vector2(-400, 190)
	_profile_name_label.size = Vector2(800, 60)
	_profile_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile.add_child(_profile_name_label)
	_profile_stats_label = _make_label("", 28)
	_profile_stats_label.set_anchors_preset(Control.PRESET_CENTER)
	_profile_stats_label.position = Vector2(-300, -80)
	_profile_stats_label.size = Vector2(600, 220)
	_profile_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile.add_child(_profile_stats_label)
	var rename := _make_button("RENAME", Vector2(320, 68), 28)
	_centered(_profile, rename, Vector2(-160, 90))
	rename.pressed.connect(_on_rename_pressed)
	var back := _make_button("‹ MENU", Vector2(320, 64), 26)
	_centered(_profile, back, Vector2(-160, 190))
	back.pressed.connect(back_to_menu)


func _on_rename_pressed() -> void:
	var gs := _gs()
	show_name_entry(String(gs.get("player_name")) if gs != null else "GECKO")


func _refresh_profile() -> void:
	var gs := _gs()
	if gs == null:
		return
	_profile_name_label.text = "🦎  " + String(gs.get("player_name"))
	var maps_unlocked := 0
	for w in WorldData.unlocked_worlds():
		maps_unlocked += (w["maps"] as Array).size()
	_profile_stats_label.text = (
		"RUNS  %d\nBEST  %d PTS\nBUGS EATEN  %d\nNEAR MISSES  %d\nMISSIONS DONE  %d\nMAPS UNLOCKED  %d"
		% [
			int(gs.get("total_runs")),
			int(gs.get("best_score")),
			int(gs.get("total_bugs")),
			int(gs.get("total_near_miss")),
			int(gs.get("missions_completed_total")),
			maps_unlocked,
		]
	)


# --- run-start fade ---

func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_full_rect(_fade)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)
