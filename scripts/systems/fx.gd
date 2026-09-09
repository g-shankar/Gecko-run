class_name FX
extends RefCounted
## Gecko Run — P22: one-shot game-feel effects. Pure juice, no gameplay.
##
## burst() spawns a short-lived CPUParticles3D at a world position, fires it
## once, and frees it after a second. Callers: bug pickups (green pop),
## near-misses (gold flash). CPU particles keep it cheap on mobile.


## Fire a one-shot burst and return it (so tests can see it happened).
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 14) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh ## CPUParticles3D takes a single mesh (draw_pass_1 is GPU-only).
	p.amount = amount
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 0.85
	p.spread = 60.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -7, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	# Auto-cleanup: the burst long outlives its particles.
	var tree := parent.get_tree()
	if tree != null:
		var timer := tree.create_timer(1.2)
		timer.timeout.connect(p.queue_free)
	return p
