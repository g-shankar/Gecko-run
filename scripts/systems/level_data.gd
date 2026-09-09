extends Resource
class_name LevelData
## Gecko Run — level definition as data (spec P13).
##
## A level is just a list of "spawn X at position Y". The Level node reads
## this and builds the route. New worlds (NYC, Tokyo...) are new LevelData
## resources with the same hazard types — reskin + reconfigure, not rebuild.
##
## LEARNING NOTES (for Gowrishankar):
## - "Data-driven" means the WHAT (which hazards, where) lives in data,
##   and the HOW (spawning, timing) lives in code. Designers tweak data
##   without touching code. That's how games ship 100 levels.
## - A Resource is Godot's data container: it saves to a .tres file you
##   can edit in the inspector, and it loads fast.

@export var level_name: String = "Backyard 1"
@export var start_position: Vector3 = Vector3(0, 0, 6)
## Each spawn: {"type": <hazard id>, "pos": <Vector3>}.
## Types: "shield", "footstep", "bicycle", "bird", "car", "sprinkler", "bug".
@export var spawns: Array = [
	{ "type": "shield", "pos": Vector3(0, 0, -4) },
	{ "type": "bug", "pos": Vector3(-1.0, 0.8, -5) },
	{ "type": "bug", "pos": Vector3(0.0, 0.8, -5.5) },
	{ "type": "bug", "pos": Vector3(1.0, 0.8, -6) },
	{ "type": "footstep", "pos": Vector3(0, 0, -6) },
	{ "type": "sprinkler", "pos": Vector3(-1.5, 0, -8) },
	{ "type": "bug", "pos": Vector3(1.5, 0.8, -9) },
	{ "type": "bug", "pos": Vector3(1.5, 0.8, -10) },
	{ "type": "bicycle", "pos": Vector3(0, 0, -11) },
	{ "type": "bug", "pos": Vector3(-1.0, 1.2, -12) },
	{ "type": "bug", "pos": Vector3(0.0, 1.5, -12.5) },
	{ "type": "bug", "pos": Vector3(1.0, 1.2, -13) },
	{ "type": "bird", "pos": Vector3(0, 0, -13) },
	{ "type": "footstep", "pos": Vector3(0, 0, -15) },
	{ "type": "bug", "pos": Vector3(0, 0.8, -16) },
	{ "type": "bug", "pos": Vector3(0, 0.8, -17) },
	{ "type": "car", "pos": Vector3(6, 0, -19) },
]
@export var fence_z: float = -20.0 ## Where the climbable fence stands.
