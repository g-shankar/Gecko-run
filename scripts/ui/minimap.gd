class_name Minimap
extends Control
## Gecko Run — P27 circular minimap (pitch-deck HUD).
##
## A glassy green disc with the route drawn as a winding sandy line, a
## checkered flag at the finish, and the gecko as a gold dot traveling it.
## The parent (game_ui) sets `progress` (0 = start line, 1 = finish) and
## `route_meters` every frame; the disc redraws itself.
##
## LEARNING NOTES (for Gowrishankar):
## - _draw() is Godot's "paint on this Control" hook: draw_circle, draw_line,
##   draw_arc, draw_rect are the brushes. queue_redraw() asks for a repaint.
## - The route is parametric: _route_point(t) maps 0..1 to a point on the
##   disc, so the gecko dot and the route line always agree.

## 0..1 along the route. Set by the HUD each frame.
var progress: float = 0.0
## Route length in meters, for the "364 m" caption under the disc.
var route_meters: float = 364.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The winding route as seen from above: a gentle S-curve from the bottom
## (start) to the top (finish) of the disc.
func _route_point(t: float, c: Vector2, r: float) -> Vector2:
	var px: float = c.x + sin(t * PI * 1.6) * r * 0.42
	var py: float = c.y + r * 0.80 - t * r * 1.60
	return Vector2(px, py)


func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 5.0
	if r <= 0.0:
		return
	# The disc: dark Florida-green glass.
	draw_circle(c, r, Color(0.06, 0.14, 0.07, 0.80))
	# A few lighter "grass" speckles so it reads as a map, not a void.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 14:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(r * 0.15, r * 0.85)
		var p := c + Vector2(cos(a), sin(a)) * d
		draw_circle(p, rng.randf_range(2.0, 5.0), Color(0.16, 0.32, 0.14, 0.55))
	# The route: sandy path, full length in tan...
	var n := 28
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(_route_point(float(i) / n, c, r))
	for i in n:
		draw_line(pts[i], pts[i + 1], Color(0.82, 0.74, 0.52, 0.9), 6.0)
	# ...with the traveled part glowing gold.
	var done := int(clampf(progress, 0.0, 1.0) * n)
	for i in done:
		draw_line(pts[i], pts[i + 1], Color(1.0, 0.82, 0.25, 0.95), 6.0)
	# The checkered flag at the finish.
	var f := pts[n]
	var pole_top := f + Vector2(0, -22)
	draw_line(f, pole_top, Color(0.9, 0.9, 0.9), 3.0)
	var cell := 5.0
	for cy in 2:
		for cx in 3:
			var col := Color(0.08, 0.08, 0.08) if (cx + cy) % 2 == 0 \
				else Color(0.95, 0.95, 0.95)
			draw_rect(Rect2(pole_top + Vector2(cx * cell, cy * cell),
				Vector2(cell, cell)), col)
	# The gecko: a gold dot with a white ring, riding the route.
	var gp := _route_point(clampf(progress, 0.0, 1.0), c, r)
	draw_circle(gp, 8.0, Color(1.0, 0.80, 0.20))
	draw_arc(gp, 8.0, 0.0, TAU, 24, Color.WHITE, 2.5)
	# The rim.
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.5)
