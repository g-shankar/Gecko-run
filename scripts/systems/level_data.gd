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
## Types: "shield", "footstep", "bicycle", "bird", "car".
@export var spawns: Array = [
	{ "type": "shield", "pos": Vector3(0, 0, -4) },
	{ "type": "footstep", "pos": Vector3(0, 0, -6) },
	{ "type": "bicycle", "pos": Vector3(0, 0, -9) },
	{ "type": "bird", "pos": Vector3(0, 0, -11) },
	{ "type": "footstep", "pos": Vector3(0, 0, -13) },
	{ "type": "car", "pos": Vector3(6, 0, -17) },
]
@export var fence_z: float = -20.0 ## Where the climbable fence stands.
