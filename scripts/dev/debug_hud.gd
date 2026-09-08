class_name DebugHUD
extends CanvasLayer
## Gecko Run — dev metrics overlay (P4.6).
##
## LEARNING NOTES (for Gowrishankar):
## - A CanvasLayer draws 2D UI on top of the 3D world, independent of the camera.
## - This HUD exists so playtest feedback can use NUMBERS, not vibes:
##   "the jump feels floaty" becomes "peak 1.4 m at 5 m/s — let's try 0.9 m".
## - It is a dev tool: it will be hidden/removed long before any public build.

var _label: Label
var _gecko: CharacterBody3D
var _start_z: float = 0.0


## Called by the gecko itself (it knows who it is; the HUD just displays).
func setup(gecko: CharacterBody3D) -> void:
	_gecko = gecko
	_start_z = gecko.global_position.z


func _ready() -> void:
	layer = 10 # Draw above everything else.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.04, 0.55)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_label)
	add_child(panel)


func _process(_delta: float) -> void:
	if _gecko == null:
		return
	var v: Vector3 = _gecko.velocity
	var speed: float = Vector2(v.x, v.z).length()
	var dist: float = _start_z - _gecko.global_position.z
	_label.text = "DEV  %d fps    state %s\n%.1f m/s    dist %.1f m\njumps %d    peak %.2f m    steer %+.2f" % [
		Engine.get_frames_per_second(),
		_gecko.stat_state,
		speed,
		dist,
		_gecko.stat_jumps,
		_gecko.stat_last_peak,
		_gecko.stat_steer,
	]
