class_name LevelRuins
extends Node3D
## 最初のエリア「灰降る廃都・外縁」。プリミティブ形状だけで組み立てる。
##
## 配置（-Z方向が奥）:
##   廃墟の前庭 (z +15〜-20) … 開始地点・篝火1・雑魚2・宝箱・西壁に隠し通路
##   崩れた回廊 (z -20〜-45) … 雑魚2
##   処刑場跡   (z -45〜-75) … 強敵1・雑魚2・枯れ木の森
##   ボス前     (z -75〜-82) … 篝火2
##   王冠の間   (中心 z -102, 半径20) … ボス

var spawn_position := Vector3(0, 0.1, 10.4)
var spawn_yaw := 0.0
var checkpoints: Array[Checkpoint] = []
var enemies: Array[Enemy] = []
var boss: Boss
var arena: BossArena

var mat_stone: StandardMaterial3D
var mat_stone_dark: StandardMaterial3D
var mat_ground: StandardMaterial3D
var mat_dirt: StandardMaterial3D
var mat_wood: StandardMaterial3D
var mat_arena: StandardMaterial3D

## 小物はこの距離より遠いと描画しない（霧で見えないため。スマホの描画負荷対策）
const PROP_DRAW_DISTANCE := 55.0
## 大きな壁・床の描画距離
const WALL_DRAW_DISTANCE := 110.0


func build() -> void:
	_make_materials()
	_build_environment()
	_build_forecourt()
	_build_corridor()
	_build_plaza()
	_build_boss_area()


func _mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _make_materials() -> void:
	mat_stone = _mat(Color(0.34, 0.32, 0.31))
	mat_stone_dark = _mat(Color(0.2, 0.19, 0.2))
	mat_ground = _mat(Color(0.23, 0.22, 0.2))
	mat_dirt = _mat(Color(0.2, 0.17, 0.14))
	mat_wood = _mat(Color(0.18, 0.13, 0.1))
	mat_arena = _mat(Color(0.17, 0.16, 0.17), 0.7)


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.07, 0.1)
	sky_mat.sky_horizon_color = Color(0.32, 0.24, 0.2)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky_mat.ground_horizon_color = Color(0.25, 0.2, 0.17)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.27, 0.25)
	env.fog_density = 0.018
	env.glow_enabled = true
	env.glow_intensity = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("world_env")
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.75, 0.78, 0.9)
	moon.light_energy = 0.7
	moon.rotation_degrees = Vector3(-50, 35, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 80.0
	moon.add_to_group("sun")
	add_child(moon)


# ------------------------------------------------------------ 組み立て用ヘルパー

## 衝突付きの箱。pos は箱の底面中心
func box(size: Vector3, pos: Vector3, mat: Material, yaw_deg: float = 0.0, collide: bool = true) -> Node3D:
	var root: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = Actor.LAYER_WORLD
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		col.position.y = size.y * 0.5
		body.add_child(col)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position.y = size.y * 0.5
	mi.visibility_range_end = WALL_DRAW_DISTANCE if maxf(size.x, size.z) > 6.0 else PROP_DRAW_DISTANCE
	root.add_child(mi)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	return root


## 2点間に壁を立てる
func wall(from: Vector2, to: Vector2, height: float = 4.0, thick: float = 1.0, mat: Material = null) -> void:
	var d := to - from
	var mid := (from + to) * 0.5
	var yaw := rad_to_deg(atan2(d.x, d.y))
	box(Vector3(thick, height, d.length()), Vector3(mid.x, 0, mid.y), mat if mat else mat_stone, yaw)


func pillar(pos: Vector3, height: float = 5.0, r: float = 0.45) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = height
	col.shape = cs
	col.position.y = height * 0.5
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 12
	cm.rings = 1
	cm.top_radius = r * 0.9
	cm.bottom_radius = r
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat_stone
	mi.position.y = height * 0.5
	mi.visibility_range_end = PROP_DRAW_DISTANCE
	body.add_child(mi)
	body.position = pos
	add_child(body)


func dead_tree(pos: Vector3, height: float = 6.0) -> void:
	pillar(pos, height, 0.3)
	var last := get_child(get_child_count() - 1)
	(last.get_child(1) as MeshInstance3D).material_override = mat_wood
	for i in 3:
		var branch := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 12
		cm.rings = 1
		cm.top_radius = 0.02
		cm.bottom_radius = 0.12
		cm.height = height * 0.4
		branch.mesh = cm
		branch.material_override = mat_wood
		branch.position = Vector3(0, height * (0.55 + i * 0.13), 0)
		branch.rotation_degrees = Vector3(0, i * 130.0, 55.0)
		branch.visibility_range_end = PROP_DRAW_DISTANCE
		last.add_child(branch)


func brazier(pos: Vector3, energy: float = 2.0) -> void:
	pillar(pos, 1.2, 0.3)
	var fire := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 16
	sm.rings = 8
	sm.radius = 0.25
	sm.height = 0.4
	fire.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.5, 0.2)
	m.emission_enabled = true
	m.emission = Color(1, 0.45, 0.1)
	m.emission_energy_multiplier = 6.0
	fire.material_override = m
	fire.position = pos + Vector3(0, 1.35, 0)
	fire.visibility_range_end = PROP_DRAW_DISTANCE
	add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.55, 0.25)
	light.light_energy = energy
	light.omni_range = 10.0
	light.position = pos + Vector3(0, 1.8, 0)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 35.0
	light.distance_fade_length = 10.0
	add_child(light)


func add_enemy(e: Enemy, pos: Vector3, yaw: float = 0.0) -> Enemy:
	add_child(e)
	e.place(pos, yaw)
	enemies.append(e)
	return e


func add_checkpoint(cp_name: String, pos: Vector3, yaw: float) -> Checkpoint:
	var cp := Checkpoint.new(cp_name)
	cp.position = pos
	cp.rotation.y = yaw
	add_child(cp)
	checkpoints.append(cp)
	return cp


# ------------------------------------------------------------ エリア

func _build_forecourt() -> void:
	box(Vector3(48, 1, 36), Vector3(-3, -1, -2.5), mat_ground)
	wall(Vector2(-20, 15.5), Vector2(20, 15.5))
	wall(Vector2(20, 15.5), Vector2(20, -20))
	# 西の壁: z -2〜+2 の区間だけ偽の壁（隠し通路）
	wall(Vector2(-20, 15.5), Vector2(-20, 2))
	wall(Vector2(-20, -2), Vector2(-20, -20))
	var secret := SecretWall.new("forecourt_secret_wall", Vector3(1.0, 4.0, 4.0))
	secret.position = Vector3(-20, 0, 0)
	add_child(secret)
	# 隠し部屋
	wall(Vector2(-20, 2.5), Vector2(-26, 2.5), 4.0)
	wall(Vector2(-20, -2.5), Vector2(-26, -2.5), 4.0)
	wall(Vector2(-26, 2.5), Vector2(-26, -2.5), 4.0)
	var hidden := Chest.new("forecourt_hidden_chest", "ash:800")
	hidden.position = Vector3(-24.5, 0, 0)
	hidden.rotation.y = -PI * 0.5
	add_child(hidden)
	# 北の壁（中央に回廊への入口）
	wall(Vector2(-20, -20), Vector2(-5, -20))
	wall(Vector2(5, -20), Vector2(20, -20))

	# 廃墟の装飾: 柱の列、崩れた柱、瓦礫
	for z in [6.0, -2.0, -10.0]:
		pillar(Vector3(-9, 0, z), 5.5)
		pillar(Vector3(9, 0, z), 3.0 if z == -2.0 else 5.5)
	box(Vector3(2.5, 1.0, 1.4), Vector3(4, 0, -4), mat_stone_dark, 20)
	box(Vector3(1.2, 0.6, 1.0), Vector3(-4, 0, 3), mat_stone_dark, -35)
	box(Vector3(6, 2.5, 0.8), Vector3(-13, 0, -13), mat_stone, 90)
	box(Vector3(3.5, 1.4, 0.8), Vector3(13, 0, 4), mat_stone, 0)
	brazier(Vector3(-5, 0, -17))
	brazier(Vector3(5, 0, -17))

	add_checkpoint("前庭の篝", Vector3(-1.6, 0, 10.4), PI * 0.5)
	var chest := Chest.new("forecourt_chest", "flask")
	chest.position = Vector3(15, 0, -15)
	chest.rotation.y = PI * 0.25
	add_child(chest)

	add_enemy(Grunt.new(), Vector3(-6, 0.1, -6), 0.3)
	add_enemy(Grunt.new(), Vector3(11, 0.1, -12), -0.6)


func _build_corridor() -> void:
	box(Vector3(10, 1, 26), Vector3(0, -1, -32.5), mat_stone_dark)
	wall(Vector2(-5, -20), Vector2(-5, -45), 6.0)
	wall(Vector2(5, -20), Vector2(5, -45), 6.0)
	# 崩れたアーチ
	for z in [-25.0, -33.0, -41.0]:
		pillar(Vector3(-3.8, 0, z), 6.0, 0.5)
		pillar(Vector3(3.8, 0, z), 6.0 if z != -33.0 else 2.2, 0.5)
		if z != -33.0:
			box(Vector3(8.6, 0.8, 1.0), Vector3(0, 6.0, z), mat_stone, 0, false)
	box(Vector3(1.5, 0.8, 1.5), Vector3(2.5, 0, -36), mat_stone_dark, 30)
	add_enemy(Grunt.new(), Vector3(-1.5, 0.1, -30), 0.0)
	add_enemy(Grunt.new(), Vector3(2, 0.1, -40), 0.2)


func _build_plaza() -> void:
	box(Vector3(34, 1, 32), Vector3(0, -1, -60), mat_dirt)
	wall(Vector2(-5, -45), Vector2(-17, -45))
	wall(Vector2(5, -45), Vector2(17, -45))
	wall(Vector2(-17, -45), Vector2(-17, -75))
	wall(Vector2(17, -45), Vector2(17, -75))
	wall(Vector2(-17, -75), Vector2(-4, -75))
	wall(Vector2(4, -75), Vector2(17, -75))
	# 処刑台
	box(Vector3(6, 0.6, 6), Vector3(0, 0, -60), mat_wood)
	box(Vector3(0.4, 4.5, 0.4), Vector3(-2.5, 0.6, -62.5), mat_wood)
	box(Vector3(0.4, 4.5, 0.4), Vector3(2.5, 0.6, -62.5), mat_wood)
	box(Vector3(5.4, 0.4, 0.4), Vector3(0, 5.1, -62.5), mat_wood, 0, false)
	# 枯れ木の森
	for p: Vector3 in [Vector3(-13, 0, -49), Vector3(-11, 0, -57), Vector3(-14, 0, -66),
			Vector3(12, 0, -51), Vector3(14, 0, -59), Vector3(11, 0, -70), Vector3(-8, 0, -71)]:
		dead_tree(p, randf_range(5.0, 7.5))
	brazier(Vector3(-7, 0, -50), 1.5)
	brazier(Vector3(7, 0, -68), 1.5)
	add_enemy(Elite.new(), Vector3(0, 0.7, -60), 0.0)
	add_enemy(Grunt.new(), Vector3(-10, 0.1, -53), 0.5)
	add_enemy(Grunt.new(), Vector3(10, 0.1, -65), -0.5)


func _build_boss_area() -> void:
	# ボス前の小部屋と篝火2
	box(Vector3(12, 1, 9), Vector3(0, -1, -79), mat_stone_dark)
	wall(Vector2(-4, -75), Vector2(-4, -83))
	wall(Vector2(4, -75), Vector2(4, -83))
	add_checkpoint("王冠の間の前の篝", Vector3(-1.6, 0, -78), PI * 0.5)

	# 円形の闘技場
	var center := Vector3(0, 0, -103)
	var radius := 20.0
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Actor.LAYER_WORLD
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius + 1.0
	cs.height = 1.0
	col.shape = cs
	floor_body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 32
	cm.rings = 1
	cm.top_radius = radius + 1.0
	cm.bottom_radius = radius + 1.0
	cm.height = 1.0
	mi.mesh = cm
	mi.material_override = mat_arena
	floor_body.add_child(mi)
	floor_body.position = center + Vector3(0, -0.5, 0)
	add_child(floor_body)

	# 外周の壁（入口=+Z側だけ開ける）
	var segments := 24
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var mid := (a0 + a1) * 0.5
		if absf(wrapf(mid, -PI, PI)) < 0.2:
			continue
		var p0 := Vector2(center.x + sin(a0) * radius, center.z + cos(a0) * radius)
		var p1 := Vector2(center.x + sin(a1) * radius, center.z + cos(a1) * radius)
		wall(p0, p1, 7.0, 1.2, mat_stone_dark)
	for i in 8:
		var a := TAU * (i + 0.5) / 8
		var p := center + Vector3(sin(a), 0, cos(a)) * (radius - 3.0)
		pillar(p, 9.0, 0.7)
		if i % 2 == 0:
			brazier(center + Vector3(sin(a), 0, cos(a)) * (radius - 5.0), 2.5)

	arena = BossArena.new()
	add_child(arena)
	arena.global_position = center
	arena.arena_radius = radius
	arena.setup_gate(Vector3(0, 0, center.z + radius), 9.0, 6.0)
	boss = Boss.new()
	add_child(boss)
	boss.place(center + Vector3(0, 0.1, -8), PI)
	enemies.append(boss)
	arena.boss = boss
