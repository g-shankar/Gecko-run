class_name GeckoRig
extends RefCounted
## Gecko Run — procedural articulation rig for the static Tripo hero mesh.
##
## The hero GLB is a single static mesh (no skeleton, no animations). This
## rig segments it with MeshDataTool into 9 articulated parts (body, head,
## 3 tail sections, 4 legs), each parented to a pivot Node3D, so
## GeckoAnimator can drive a real diagonal-gait run cycle instead of
## bouncing the whole mesh.
##
## Mesh frame (BEFORE the visual carrier's 90° Y rotation): +X = head/front,
## Y = up, Z = lateral. All pivot positions are in this mesh frame; the
## carrier rotation applies uniformly to the whole rig subtree.
##
## Segmentation is heuristic but deterministic: head = far +X cap, tail =
## far -X cap split into 3 bands, legs = low-Y lateral clusters split by a
## 2-means on (x, y*2) into front/hind (robust when a mid-stride pose parks
## legs near each other), body = everything else. Faces touching a part
## boundary are emitted into EVERY part they touch (double coverage) so no
## gaps open when parts rotate relative to each other.
##
## Results are cached per source mesh (the player and the onboarding trio
## share one segmentation). build() returns {} on any failure and callers
## must fall back to the rigid mesh.

## --- Segmentation tuning (mesh units, hero is ~0.5 long) ---
const HEAD_X := 0.30 ## Verts with x > this belong to the head.
const TAIL_X := -0.10 ## Verts with x < this belong to the tail.
const LEG_Y := -0.02 ## Leg verts sit below this height.
const LEG_Z := 0.06 ## Leg verts are at least this far lateral.
const HEAD_PIVOT := Vector3(0.30, 0.045, 0.0)
const KMEANS_ITERS := 25

## Segmented part data, cached per source mesh instance id. Stores
## per-part FACE lists (triples of original vertex ids) plus pivots, so
## _instantiate can rebuild pivot-relative meshes without re-segmenting.
static var _cache := {}


## Build (or fetch from cache) the rig for a hero mesh. Returns a dict:
##   {"root": Node3D, "pivots": {"head": Node3D, "tail": [Node3D x3],
##    "legs": {"LF": Node3D, "RF": Node3D, "LH": Node3D, "RH": Node3D}},
##    "meshes": [MeshInstance3D x9]}
## or {} when segmentation fails (caller falls back to the rigid mesh).
static func build(hero_mesh: ArrayMesh) -> Dictionary:
	if hero_mesh == null or hero_mesh.get_surface_count() < 1:
		return {}
	var key := hero_mesh.get_instance_id()
	if _cache.has(key):
		return _instantiate(_cache[key])
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(hero_mesh, 0) != OK:
		return {}
	var data := _segment(mdt)
	if data.is_empty():
		return {}
	data["material"] = hero_mesh.surface_get_material(0)
	_cache[key] = data
	return _instantiate(data)


## 2-means on x: splits one side's leg verts into front/hind even when the
## mid-stride pose parks them almost on top of each other. Returns
## [front_ids, hind_ids] (front = higher mean x).
static func _kmeans2(mdt: MeshDataTool, ids: Array) -> Array:
	if ids.size() < 2:
		return [ids, []]
	var ax := 0.0
	for i in ids:
		ax += mdt.get_vertex(i).x
	ax /= ids.size()
	var c0 := ax + 0.05
	var c1 := ax - 0.05
	var g0: Array = []
	var g1: Array = []
	for _it in KMEANS_ITERS:
		g0.clear()
		g1.clear()
		for i in ids:
			var vx := mdt.get_vertex(i).x
			if absf(vx - c0) < absf(vx - c1):
				g0.append(i)
			else:
				g1.append(i)
		if g0.is_empty() or g1.is_empty():
			break
		var n0 := 0.0
		var n1 := 0.0
		for i in g0:
			n0 += mdt.get_vertex(i).x
		for i in g1:
			n1 += mdt.get_vertex(i).x
		var nn0: float = n0 / g0.size()
		var nn1: float = n1 / g1.size()
		if absf(nn0 - c0) < 0.00001 and absf(nn1 - c1) < 0.00001:
			break
		c0 = nn0
		c1 = nn1
	var m0 := 0.0
	var m1 := 0.0
	for i in g0:
		m0 += mdt.get_vertex(i).x
	for i in g1:
		m1 += mdt.get_vertex(i).x
	var mean0 := m0 / maxf(g0.size(), 1.0)
	var mean1 := m1 / maxf(g1.size(), 1.0)
	if g0.is_empty() or (not g1.is_empty() and mean1 > mean0):
		return [g1, g0]
	return [g0, g1]


## Segment the mesh. Returns {"faces": {part_id: [[a,b,c]...]},
## "pivots": {part_id: Vector3}, "verts": PackedVector3Array} or {}.
## part_ids: body, head, tail1..3, leg_LF/RF/LH/RH. Face triples hold
## vertex ids into "verts"; boundary faces are listed under every part
## they touch (double coverage).
static func _segment(mdt: MeshDataTool) -> Dictionary:
	var n := mdt.get_vertex_count()
	if n < 100:
		return {}
	var verts := PackedVector3Array()
	verts.resize(n)
	for i in n:
		verts[i] = mdt.get_vertex(i)
	# Pass 1: per-vertex part id.
	var vid_part := {}
	var leg_ids: Array = []
	var tail_ids: Array = []
	for i in n:
		var v: Vector3 = verts[i]
		if v.x > HEAD_X:
			vid_part[i] = "head"
		elif v.x < TAIL_X:
			vid_part[i] = "tail?"
			tail_ids.append(i)
		elif v.y < LEG_Y and absf(v.z) > LEG_Z:
			vid_part[i] = "leg?"
			leg_ids.append(i)
		else:
			vid_part[i] = "body"
	# Pass 2: legs -> 4 clusters (side by z sign, front/hind by k-means).
	var left: Array = []
	var right: Array = []
	for i in leg_ids:
		if verts[i].z < 0.0:
			left.append(i)
		else:
			right.append(i)
	var leg_of := {}
	if left.size() >= 4:
		var s := _kmeans2(mdt, left)
		for i in s[0]:
			leg_of[i] = "leg_LF"
		for i in s[1]:
			leg_of[i] = "leg_LH"
	if right.size() >= 4:
		var s2 := _kmeans2(mdt, right)
		for i in s2[0]:
			leg_of[i] = "leg_RF"
		for i in s2[1]:
			leg_of[i] = "leg_RH"
	for i in leg_ids:
		if leg_of.has(i):
			vid_part[i] = leg_of[i]
		else:
			return {} # Leg clustering failed; caller falls back.
	# Pass 3: tail -> 3 bands by x (tail1 = front band at body).
	if tail_ids.size() < 12:
		return {}
	var min_x := 999.0
	var max_x := -999.0
	for i in tail_ids:
		min_x = minf(min_x, verts[i].x)
		max_x = maxf(max_x, verts[i].x)
	var span := maxf(max_x - min_x, 0.001)
	for i in tail_ids:
		var t := (verts[i].x - min_x) / span
		if t < 0.34:
			vid_part[i] = "tail3"
		elif t < 0.67:
			vid_part[i] = "tail2"
		else:
			vid_part[i] = "tail1"
	# Pass 4: per-face part assignment with double coverage at boundaries.
	var part_ids := ["body", "head", "tail1", "tail2", "tail3",
		"leg_LF", "leg_RF", "leg_LH", "leg_RH"]
	var faces := {}
	for pid in part_ids:
		faces[pid] = []
	var fcount := mdt.get_face_count()
	for f in fcount:
		var va := mdt.get_face_vertex(f, 0)
		var vb := mdt.get_face_vertex(f, 1)
		var vc := mdt.get_face_vertex(f, 2)
		var ps := {}
		ps[vid_part[va]] = true
		ps[vid_part[vb]] = true
		ps[vid_part[vc]] = true
		var tri := [va, vb, vc]
		for pid in ps.keys():
			(faces[pid] as Array).append(tri)
	for pid in part_ids:
		if (faces[pid] as Array).is_empty():
			return {}
	# Pass 5: pivots (mesh frame).
	var pivots := {}
	pivots["body"] = Vector3.ZERO
	pivots["head"] = HEAD_PIVOT
	var tb1 := min_x + span * 0.67
	var tb2 := min_x + span * 0.34
	pivots["tail1"] = Vector3(tb1, 0.03, 0.0)
	pivots["tail2"] = Vector3(tb2, 0.03, 0.0)
	pivots["tail3"] = Vector3(min_x + span * 0.10, 0.03, 0.0)
	for key in ["leg_LF", "leg_RF", "leg_LH", "leg_RH"]:
		var top_y := -999.0
		var mean := Vector3.ZERO
		var cnt := 0
		for i in n:
			if vid_part.get(i) == key:
				var v: Vector3 = verts[i]
				mean += v
				top_y = maxf(top_y, v.y)
				cnt += 1
		mean /= maxf(cnt, 1.0)
		pivots[key] = Vector3(mean.x, top_y, mean.z)
	return {"faces": faces, "pivots": pivots, "verts": verts,
		"face_count": fcount}


## Instantiate rig nodes from cached data. Meshes are built pivot-relative;
## pivots sit at anatomical joints in mesh frame.
static func _instantiate(data: Dictionary) -> Dictionary:
	var faces: Dictionary = data["faces"]
	var pivots: Dictionary = data["pivots"]
	var verts: PackedVector3Array = data["verts"]
	var base_mat: Material = data.get("material")
	var root := Node3D.new()
	root.name = "GeckoRig"
	var meshes: Array = []
	# Body: no pivot, direct child of root.
	var body_mi := _make_mi(faces["body"], verts, Vector3.ZERO, base_mat)
	root.add_child(body_mi)
	meshes.append(body_mi)
	# Head.
	var head_piv := Node3D.new()
	head_piv.name = "HeadPivot"
	head_piv.position = pivots["head"]
	root.add_child(head_piv)
	var head_mi := _make_mi(faces["head"], verts, pivots["head"], base_mat)
	head_piv.add_child(head_mi)
	meshes.append(head_mi)
	# Tail: chained pivots (tail1 parented to root, tail2 to tail1, ...).
	# Child pivot positions are relative to their parent pivot.
	var tail_pivs: Array = []
	var parent: Node3D = root
	var parent_pos := Vector3.ZERO
	for t in ["tail1", "tail2", "tail3"]:
		var tp := Node3D.new()
		tp.name = "TailPivot" + t.substr(4)
		var tp_pos: Vector3 = pivots[t]
		tp.position = tp_pos - parent_pos
		parent.add_child(tp)
		var tmi := _make_mi(faces[t], verts, tp_pos, base_mat)
		tp.add_child(tmi)
		meshes.append(tmi)
		tail_pivs.append(tp)
		parent = tp
		parent_pos = tp_pos
	# Legs.
	var leg_names := {"leg_LF": "LF", "leg_RF": "RF",
		"leg_LH": "LH", "leg_RH": "RH"}
	var leg_pivs := {}
	for key in leg_names.keys():
		var lp := Node3D.new()
		lp.name = "LegPivot_" + str(leg_names[key])
		lp.position = pivots[key]
		root.add_child(lp)
		var lmi := _make_mi(faces[key], verts, pivots[key], base_mat)
		lp.add_child(lmi)
		meshes.append(lmi)
		leg_pivs[str(leg_names[key])] = lp
	var out_pivots := {"head": head_piv, "tail": tail_pivs, "legs": leg_pivs}
	return {"root": root, "pivots": out_pivots, "meshes": meshes}


## Build one ArrayMesh from a face list. Verts are emitted pivot-relative
## as a triangle soup; SurfaceTool generates smooth normals. Double-covered
## boundary faces appear in each touching part's list, keeping seams shut.
static func _make_mi(face_list: Array, verts: PackedVector3Array,
		pivot: Vector3, base_mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# NOTE: MeshDataTool vertex ids are only valid while the MDT lives, so
	# the segmented data carries its own verts copy; faces index into it.
	for f in face_list:
		# face_list stores packed face triples; see _segment.
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		st.add_vertex(verts[a] - pivot)
		st.add_vertex(verts[b] - pivot)
		st.add_vertex(verts[c] - pivot)
	st.generate_normals()
	var mesh := st.commit()
	if base_mat != null:
		mesh.surface_set_material(0, base_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
