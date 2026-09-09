extends LevelData
class_name LevelDataFenceLine
## Gecko Run — P26 second map: "FENCE LINE".
##
## A shorter, denser route for the Florida map select. Same hazard systems,
## same start line, same fence finish — just a different configuration.
## Warn times run tighter than Backyard Dash: 0.9 s -> 0.75 s -> 0.6 s.


func _init() -> void:
	level_name = "Fence Line"
	start_position = Vector3(0, 0, 6)
	fence_z = -190.0
	spawns = [
		# --- Section A: quick warm-up (warn 0.9) ---
		{ "type": "shield", "pos": Vector3(0, 0, -4) },
		{ "type": "bug", "pos": Vector3(-1.0, 0.8, -5) },
		{ "type": "bug", "pos": Vector3(1.0, 0.8, -6) },
		{ "type": "footstep", "pos": Vector3(0, 0, -8), "warn": 0.9 },
		{ "type": "sprinkler", "pos": Vector3(-1.5, 0, -12), "warn": 0.9 },
		{ "type": "bug", "pos": Vector3(1.5, 0.8, -14) },
		{ "type": "bug", "pos": Vector3(1.5, 0.8, -15) },
		{ "type": "bicycle", "pos": Vector3(0, 0, -17), "warn": 0.9 },
		{ "type": "bird", "pos": Vector3(0, 0, -21), "warn": 0.9 },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -23) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -24) },
		{ "type": "car", "pos": Vector3(6, 0, -26), "warn": 0.9 },
		{ "type": "footstep", "pos": Vector3(0, 0, -30), "warn": 0.9 },
		# --- Section B: pressure builds (warn 0.75) ---
		{ "type": "sprinkler", "pos": Vector3(1.5, 0, -36), "warn": 0.75 },
		{ "type": "bug", "pos": Vector3(-1.5, 0.8, -38) },
		{ "type": "bug", "pos": Vector3(-1.5, 0.8, -39) },
		{ "type": "bicycle", "pos": Vector3(0, 0, -42), "warn": 0.75 },
		{ "type": "footstep", "pos": Vector3(-0.5, 0, -46), "warn": 0.75 },
		{ "type": "bird", "pos": Vector3(0, 0, -50), "warn": 0.75 },
		{ "type": "bug", "pos": Vector3(1.0, 0.8, -52) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -53) },
		{ "type": "bug", "pos": Vector3(-1.0, 0.8, -54) },
		{ "type": "sprinkler", "pos": Vector3(-1.5, 0, -58), "warn": 0.75 },
		{ "type": "speed", "pos": Vector3(2.0, 0, -62) },
		{ "type": "car", "pos": Vector3(-6, 0, -66), "warn": 0.75 },
		{ "type": "footstep", "pos": Vector3(0.5, 0, -70), "warn": 0.75 },
		{ "type": "bicycle", "pos": Vector3(0, 0, -74), "warn": 0.75 },
		# --- Section C: the gauntlet (warn 0.6) ---
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -78) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -79) },
		{ "type": "bird", "pos": Vector3(0, 0, -82), "warn": 0.6 },
		{ "type": "footstep", "pos": Vector3(0, 0, -86), "warn": 0.6 },
		{ "type": "sprinkler", "pos": Vector3(1.5, 0, -90), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(-1.5, 0.8, -92) },
		{ "type": "bug", "pos": Vector3(-1.5, 0.8, -93) },
		{ "type": "bicycle", "pos": Vector3(0, 0, -96), "warn": 0.6 },
		{ "type": "footstep", "pos": Vector3(-0.5, 0, -100), "warn": 0.6 },
		{ "type": "car", "pos": Vector3(6, 0, -104), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -106) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -107) },
		{ "type": "bird", "pos": Vector3(0, 0, -110), "warn": 0.6 },
		{ "type": "sprinkler", "pos": Vector3(-1.5, 0, -114), "warn": 0.6 },
		{ "type": "footstep", "pos": Vector3(0, 0, -118), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(1.0, 0.8, -120) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -121) },
		{ "type": "bug", "pos": Vector3(-1.0, 0.8, -122) },
		{ "type": "bicycle", "pos": Vector3(0, 0, -126), "warn": 0.6 },
		{ "type": "car", "pos": Vector3(-6, 0, -130), "warn": 0.6 },
		{ "type": "shield", "pos": Vector3(0, 0, -134) },
		{ "type": "footstep", "pos": Vector3(0.5, 0, -138), "warn": 0.6 },
		{ "type": "sprinkler", "pos": Vector3(1.5, 0, -142), "warn": 0.6 },
		{ "type": "bird", "pos": Vector3(0, 0, -146), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -148) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -149) },
		{ "type": "footstep", "pos": Vector3(0, 0, -152), "warn": 0.6 },
		{ "type": "bicycle", "pos": Vector3(0, 0, -156), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(1.5, 0.8, -158) },
		{ "type": "bug", "pos": Vector3(1.5, 0.8, -159) },
		{ "type": "sprinkler", "pos": Vector3(-1.5, 0, -162), "warn": 0.6 },
		{ "type": "car", "pos": Vector3(6, 0, -166), "warn": 0.6 },
		{ "type": "footstep", "pos": Vector3(-0.5, 0, -170), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -172) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -173) },
		{ "type": "bug", "pos": Vector3(0.0, 0.8, -174) },
		{ "type": "bird", "pos": Vector3(0, 0, -178), "warn": 0.6 },
		{ "type": "bug", "pos": Vector3(-1.0, 0.8, -180) },
		{ "type": "bug", "pos": Vector3(1.0, 0.8, -181) },
	]
