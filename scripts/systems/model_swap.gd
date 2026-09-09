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
	"dog": {
		"path": "res://assets/models/dog.glb",
		"size": Vector3(1.00, 0.44, 0.38), "min_y": -0.22, "verts": 8409,
	},
	"mower": {
		"path": "res://assets/models/mower.glb",
		"size": Vector3(0.68, 0.73, 1.00), "min_y": -0.36, "verts": 8817,
	},
	# P29 (measured at import 2026-09-09; decimated for the mobile budget).
	"sneaker": {
		"path": "res://assets/models/sneaker.glb",
		"size": Vector3(0.37, 0.45, 1.00), "min_y": -0.22, "verts": 13060,
	},
	"grass_tuft": {
		"path": "res://assets/models/grass_tuft.glb",
		"size": Vector3(1.00, 0.81, 0.96), "min_y": -0.41, "verts": 293392,
	},
	"bush_round": {
		"path": "res://assets/models/bush_round.glb",
		"size": Vector3(0.96, 0.69, 0.99), "min_y": -0.35, "verts": 13538,
	},
	"bush_tall": {
		"path": "res://assets/models/bush_tall.glb",
		"size": Vector3(0.46, 1.00, 0.46), "min_y": -0.50, "verts": 4110,
	},
	"flowers": {
		"path": "res://assets/models/flowers.glb",
		"size": Vector3(1.00, 0.53, 1.00), "min_y": -0.26, "verts": 2564,
	},
	"tree": {
		"path": "res://assets/models/tree.glb",
		"size": Vector3(0.89, 0.86, 1.00), "min_y": -0.43, "verts": 17286,
	},
	# P29: Tripo areca palm + hibiscus, gltfpack-decimated to the mobile budget.
	"palm": {
		"path": "res://assets/models/palm.glb",
		"size": Vector3(0.90, 0.89, 1.00), "min_y": -0.45, "verts": 8216,
	},
	"hibiscus": {
		"path": "res://assets/models/hibiscus.glb",
		"size": Vector3(0.96, 0.87, 1.00), "min_y": -0.44, "verts": 6143,
	},
}


## P29: merge every MeshInstance3D surface of a registered GLB into one
## ArrayMesh, preserving each surface's material. `material_fn` (optional)
## maps each imported material to its replacement (e.g. a wind-sway shader).
## Returns null if the GLB is missing or exceeds max_verts.
static func merge_model_mesh(model_name: String, max_verts: int,
		material_fn: Callable = Callable()) -> ArrayMesh:
	if not MODELS.has(model_name):
		return null
	var packed: PackedScene = load(MODELS[model_name]["path"])
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var meshes: Array = []
	var stack := [inst]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				meshes.append(mi)
		for c in cur.get_children():
			stack.push_back(c)
	var out := ArrayMesh.new()
	var total_verts := 0
	for mi in meshes:
		var mesh := (mi as MeshInstance3D).mesh
		var xform: Transform3D = (mi as MeshInstance3D).transform
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			if arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total_verts += verts.size()
			if total_verts > max_verts:
				inst.queue_free()
				return null
			var baked := PackedVector3Array()
			baked.resize(verts.size())
			for vi in verts.size():
				baked[vi] = xform * verts[vi]
			arrays[Mesh.ARRAY_VERTEX] = baked
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var bn := PackedVector3Array()
				bn.resize(normals.size())
				var nbasis := xform.basis.orthonormalized()
				for ni in normals.size():
					bn[ni] = nbasis * normals[ni]
				arrays[Mesh.ARRAY_NORMAL] = bn
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var src_mat := mesh.surface_get_material(si)
			var final_mat: Material = src_mat
			if material_fn.is_valid() and src_mat != null:
				final_mat = material_fn.call(src_mat)
			if final_mat != null:
				out.surface_set_material(out.get_surface_count() - 1, final_mat)
	inst.queue_free()
	return out if out.get_surface_count() > 0 else null
## Instance a model, scale it uniformly so `target` (in meters, applied to the
## model's longest horizontal axis) is met, rest its base on the wrapper's
## origin, and return the wrapper. Returns null if the GLB fails to load
## (caller keeps the primitive fallback).
## P29: Tripo ships every model with metallic=1.0 — under the sky ambient
## that renders foliage/plastic as blue sky reflections (the blue blocky
## shrub in the P28 dog screenshot was the sprinkler model doing exactly
## this). Every model gets tamed to a dielectric satin finish; the imported
## GLB is untouched (per-instance surface overrides). Visuals only.
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
	_tame_metal(inst) ## P29: same all-metal fix as make_visual.
	return wrapper
