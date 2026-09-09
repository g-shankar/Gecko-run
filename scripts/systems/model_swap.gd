class_name ModelSwap
## P25: real 3D models replace primitive hazard/prop visuals. VISUALS ONLY.
##
## Tripo GLBs are imported as PackedScenes. Each entry below records the
## model's native extents (measured at import) so swaps scale deterministically
## without runtime AABB walks. Collision shapes, spawn positions, and gameplay
## timing are never touched — only MeshInstance3D visuals are hidden/replaced.

## Native model data: { glb_path, size_xyz, min_y } in model units.
const MODELS := {
	"sprinkler": {
		"path": "res://assets/models/sprinkler.glb",
		"size": Vector3(0.90, 1.00, 0.96), "min_y": -0.50, "verts": 10249,
	},
	"bicycle": {
		"path": "res://assets/models/bicycle.glb",
		"size": Vector3(0.48, 1.00, 0.94), "min_y": -0.50, "verts": 13152,
	},
	"car": {
		"path": "res://assets/models/car.glb",
		"size": Vector3(1.00, 0.53, 0.54), "min_y": -0.26, "verts": 7596,
		"tame_metal": true, # P25: Tripo car paint renders mirror-chrome
		                     # under the sky; clamp to a satin finish.
	},
	"bird": {
		"path": "res://assets/models/bird.glb",
		"size": Vector3(1.00, 0.62, 0.69), "min_y": -0.31, "verts": 6571,
	},
	"fence": {
		"path": "res://assets/models/fence.glb",
		"size": Vector3(0.22, 0.54, 1.00), "min_y": -0.27, "verts": 9226,
	},
	"plant_a": {
		"path": "res://assets/models/plant_a.glb",
		"size": Vector3(1.00, 0.56, 0.97), "min_y": -0.28, "verts": 636,
	},
	"plant_b": {
		"path": "res://assets/models/plant_b.glb",
		"size": Vector3(0.84, 0.76, 0.83), "min_y": -0.41, "verts": 1009,
	},
	"bed": {
		"path": "res://assets/models/bed.glb",
		"size": Vector3(0.70, 0.25, 1.00), "min_y": -0.12, "verts": 8199,
	},
}


## Instance a model, scale it uniformly so `target` (in meters, applied to the
## model's longest horizontal axis) is met, rest its base on the wrapper's
## origin, and return the wrapper. Returns null if the GLB fails to load
## (caller keeps the primitive fallback).
static func make_visual(model_name: String, target_longest_m: float) -> Node3D:
	if not MODELS.has(model_name):
		return null
	var spec: Dictionary = MODELS[model_name]
	var packed: PackedScene = load(spec["path"])
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var size: Vector3 = spec["size"]
	var longest: float = maxf(size.x, size.z)
	if longest < 0.001:
		inst.queue_free()
		return null
	var s: float = target_longest_m / longest
	var wrapper := Node3D.new()
	wrapper.name = "ModelVisual_" + model_name
	wrapper.add_child(inst)
	inst.scale = Vector3.ONE * s
	inst.position.y = -float(spec["min_y"]) * s
	if bool(spec.get("tame_metal", false)):
		_tame_metal(inst)
	return wrapper


## P25: clamp mirror-like metallic materials to a satin finish (per-instance
## surface overrides; the imported GLB is untouched). Used on the car.
## P28.5: keep the ORM/normal textures — only the property multipliers drop,
## so the paint keeps its PBR detail instead of going flat.
static func _tame_metal(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for si in mesh.get_surface_count():
				var m := mesh.surface_get_material(si) as StandardMaterial3D
				if m != null and m.metallic > 0.25:
					var d := m.duplicate() as StandardMaterial3D
					d.metallic = 0.15
					d.roughness = 0.55
					mi.set_surface_override_material(si, d)
	for c in n.get_children():
		_tame_metal(c)


## Uniform-scale a model so its HEIGHT becomes target_height_m (for the
## sprinkler head, where vertical size matters more than footprint).
static func make_visual_by_height(model_name: String, target_height_m: float) -> Node3D:
	if not MODELS.has(model_name):
		return null
	var spec: Dictionary = MODELS[model_name]
	var packed: PackedScene = load(spec["path"])
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var size: Vector3 = spec["size"]
	if size.y < 0.001:
		inst.queue_free()
		return null
	var s: float = target_height_m / size.y
	var wrapper := Node3D.new()
	wrapper.name = "ModelVisual_" + model_name
	wrapper.add_child(inst)
	inst.scale = Vector3.ONE * s
	inst.position.y = -float(spec["min_y"]) * s
	return wrapper
