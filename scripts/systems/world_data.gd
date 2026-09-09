class_name WorldData
extends RefCounted
## Gecko Run — P26 world-tour data.
##
## Worlds are DATA, not scenes: Florida is World 1 today; new worlds plug in
## as new dicts (id, name, tagline, unlocked, maps). Each map points at a
## LevelData route script — the same hazard systems, reconfigured.
## "Reskin + reconfigure, not rebuild" is what makes new worlds cheap.

const WORLDS: Array = [
	{
		"id": "florida",
		"name": "FLORIDA",
		"tagline": "Sunny backyards · World 1",
		"unlocked": true,
		"maps": [
			{
				"id": "florida_backyard",
				"name": "BACKYARD DASH",
				"desc": "The full 364 m gauntlet.",
				"route": "res://scripts/systems/level_data.gd",
			},
			{
				"id": "florida_fenceline",
				"name": "FENCE LINE",
				"desc": "Short, dense, no mercy.",
				"route": "res://scripts/systems/level_data_fenceline.gd",
			},
		],
	},
	{
		"id": "world_2",
		"name": "???",
		"tagline": "Coming soon",
		"unlocked": false,
		"maps": [],
	},
	{
		"id": "world_3",
		"name": "???",
		"tagline": "Coming soon",
		"unlocked": false,
		"maps": [],
	},
]


static func world_count() -> int:
	return WORLDS.size()


static func get_world(world_id: String) -> Dictionary:
	for w in WORLDS:
		if String(w["id"]) == world_id:
			return w
	return {}


static func unlocked_worlds() -> Array:
	var out := []
	for w in WORLDS:
		if bool(w["unlocked"]):
			out.append(w)
	return out


static func maps_for_world(world_id: String) -> Array:
	var w := get_world(world_id)
	if w.is_empty():
		return []
	return w["maps"]


## Find a map anywhere by id. Returns {} when unknown.
static func get_map(map_id: String) -> Dictionary:
	for w in WORLDS:
		for m in (w["maps"] as Array):
			if String(m["id"]) == map_id:
				return m
	return {}


## The LevelData route script for a map id. Empty string when unknown.
static func route_for_map(map_id: String) -> String:
	var m := get_map(map_id)
	if m.is_empty():
		return ""
	return String(m["route"])


static func map_name(map_id: String) -> String:
	var m := get_map(map_id)
	if m.is_empty():
		return map_id
	return String(m["name"])
