class_name FX
extends RefCounted
## 戦闘演出・環境演出をまとめた静的関数。
## スマホのGPU負荷を抑えるため、すべて CPUParticles3D と小さな板ポリゴンで作る。

static var _spark_mesh: QuadMesh
static var _ash_mesh: QuadMesh


static func _particle_mesh(color: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	q.material = m
	return q


## 攻撃が当たった場所に火花を散らす。blocked=true ならガードの金属火花（黄色）
static func hit_spark(parent: Node, pos: Vector3, blocked: bool = false, big: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _spark_mesh == null:
		_spark_mesh = _particle_mesh(Color.WHITE, 0.08)
	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 28 if big else 14
	p.lifetime = 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0 if big else 6.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var grad := Gradient.new()
	if blocked:
		grad.set_color(0, Color(1.0, 0.95, 0.6))
		grad.set_color(1, Color(1.0, 0.6, 0.1, 0.0))
	else:
		grad.set_color(0, Color(1.0, 0.45, 0.2))
		grad.set_color(1, Color(0.5, 0.05, 0.02, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## 画面の周囲に常に舞っている灰。カメラに付けて使う
static func ambient_ash(amount: int) -> CPUParticles3D:
	if _ash_mesh == null:
		_ash_mesh = _particle_mesh(Color(0.75, 0.72, 0.68, 0.7), 0.05)
	var p := CPUParticles3D.new()
	p.add_to_group("ambient_particles")
	p.mesh = _ash_mesh
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 6, 14)
	p.direction = Vector3(0.3, -1, 0.1)
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -0.15, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.local_coords = false
	return p
