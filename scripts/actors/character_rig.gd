class_name CharacterRig
extends Node3D
## 素材なしで動くキャラクターの見た目。関節（骨盤・背骨・首・肩・肘・股・膝）を持つ人型を
## プリミティブ形状で組み立て、攻撃・回避・被弾・歩行の姿勢をコードで補間する（プロシージャル・アニメーション）。
## 後で本物の3Dモデル+AnimationPlayerに差し替える時も、呼び出し側のAPIはこのまま使える。
##
## 体型（archetype）:
##   "knight"   … プレイヤー。兜・肩当て・外套・剣と盾
##   "ghoul"    … 灰憑きの兵。痩せて前かがみ、長い腕、肋骨、背中の骨棘、鉤爪
##   "brute"    … 黒鉄の処刑人。巨体、角兜、棘付き肩当て、大鉈
##   "colossus" … 灰冠の守護者。角の王冠、四つ目、胸の燃える亀裂、背骨の棘、大剣

## 右腕（肩）の回転（度）と位置ずれ（1.8m基準、身長に比例）。windup=振りかぶり / end=振り抜き
const POSES := {
	"rest": {"rot": Vector3(-70, -10, 0), "pos": Vector3.ZERO},
	"guard": {"rot": Vector3(-30, 40, 0), "pos": Vector3(0, 0, -0.1)},
	"slash_r": {
		"windup": {"rot": Vector3(-5, -115, 0), "pos": Vector3.ZERO},
		"end": {"rot": Vector3(-25, 95, 0), "pos": Vector3.ZERO},
	},
	"slash_l": {
		"windup": {"rot": Vector3(-5, 100, 0), "pos": Vector3.ZERO},
		"end": {"rot": Vector3(-25, -100, 0), "pos": Vector3.ZERO},
	},
	"overhead": {
		"windup": {"rot": Vector3(135, 0, 0), "pos": Vector3(0, 0.1, 0.1)},
		"end": {"rot": Vector3(-85, 0, 0), "pos": Vector3(0, -0.1, -0.2)},
	},
	"thrust": {
		"windup": {"rot": Vector3(-10, 0, 0), "pos": Vector3(0, 0, 0.5)},
		"end": {"rot": Vector3(-20, 0, 0), "pos": Vector3(0, 0, -0.7)},
	},
	"stomp": {
		"windup": {"rot": Vector3(150, 0, 0), "pos": Vector3(0, 0.2, 0)},
		"end": {"rot": Vector3(-95, 0, 0), "pos": Vector3(0, -0.3, -0.2)},
	},
}
## 肘の固定の曲がり（度）。腕を下ろした時に剣先が前を向く
const ELBOW_BEND := 28.0
## 体型ごとの比率: width=胴の太さ, shoulder=肩幅, limb=手足の太さ, arm=腕の長さ, hunch=前かがみ(ラジアン)
const ARCHETYPES := {
	"knight": {"width": 1.0, "shoulder": 1.0, "limb": 1.0, "arm": 1.0, "hunch": 0.0, "head": 1.0},
	"ghoul": {"width": 0.72, "shoulder": 0.9, "limb": 0.62, "arm": 1.35, "hunch": 0.5, "head": 0.85},
	"brute": {"width": 1.35, "shoulder": 1.4, "limb": 1.45, "arm": 1.2, "hunch": 0.3, "head": 0.95},
	"colossus": {"width": 1.3, "shoulder": 1.35, "limb": 1.35, "arm": 1.35, "hunch": 0.38, "head": 1.25},
}

var height := 1.8
var radius := 0.35
var archetype := "knight"
var body_pivot: Node3D
var spine: Node3D
var arm: Node3D
var off_arm: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var cape: Node3D
var weapon_mesh: MeshInstance3D
var body_mat: StandardMaterial3D
var weapon_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var base_eye_energy := 1.0
var _flash_mats: Array[StandardMaterial3D] = []
var _flash_colors: Array[Color] = []
var _flash_time := 0.0
var _walk_phase := 0.0
var _hop := 0.0
var _hunch := 0.0
var _shoulder_pos := Vector3.ZERO
var _pose_scale := 1.0
var _draw_distance := 60.0


## cfg: archetype, height, radius, body_color, cloth_color, skin_color, weapon_color,
##      weapon_length, eye_color, eye_energy, shield(bool), draw_distance
func build(cfg: Dictionary) -> void:
	height = cfg.get("height", 1.8)
	radius = cfg.get("radius", 0.35)
	archetype = cfg.get("archetype", "knight")
	_draw_distance = cfg.get("draw_distance", 40.0)
	_pose_scale = height / 1.8
	var a: Dictionary = ARCHETYPES[archetype]
	var h := height
	var w: float = a["width"]
	var limb: float = a["limb"] * h
	_hunch = a["hunch"]

	body_mat = _mat(cfg.get("body_color", Color(0.4, 0.4, 0.45)), 0.55, 0.5)
	var cloth := _mat(cfg.get("cloth_color", Color(0.12, 0.1, 0.1)), 0.0, 0.95)
	var skin := _mat(cfg.get("skin_color", Color(0.45, 0.42, 0.38)), 0.0, 0.85)
	var bone := _mat(Color(0.62, 0.58, 0.5), 0.0, 0.7)
	weapon_mat = _mat(cfg.get("weapon_color", Color(0.7, 0.7, 0.75)), 0.8, 0.3)
	weapon_mat.emission_enabled = true
	weapon_mat.emission = Color(1.0, 0.35, 0.1)
	weapon_mat.emission_energy_multiplier = 0.0
	eye_mat = _mat(cfg.get("eye_color", Color(0.9, 0.8, 0.5)), 0.0, 0.5)
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_mat.albedo_color
	base_eye_energy = cfg.get("eye_energy", 1.5)
	eye_mat.emission_energy_multiplier = base_eye_energy
	var ember := _mat(Color(1.0, 0.45, 0.12), 0.0, 0.5)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.4, 0.1)
	ember.emission_energy_multiplier = 3.0
	# 質感（模様と凹凸）。被弾時の白い点滅は色を掛け合わせるので、模様を付けた後の色を覚えておく
	Surface.apply(body_mat, "stone" if archetype == "colossus" else "metal")
	Surface.apply(cloth, "cloth")
	Surface.apply(skin, "skin")
	Surface.apply(bone, "skin")
	Surface.apply(weapon_mat, "metal")
	for m in [body_mat, cloth, skin, bone]:
		_flash_mats.append(m)
		_flash_colors.append(m.albedo_color)
	# 皮膚が見える体型は胴・手足に皮膚の色を使う
	var flesh := skin if archetype == "ghoul" else body_mat

	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	body_pivot.position.y = h * 0.5
	add_child(body_pivot)

	# ---- 骨盤と脚
	_part(body_pivot, _box(Vector3(0.28 * h * w, 0.1 * h, 0.17 * h * w)), cloth if archetype == "ghoul" else body_mat,
		Vector3(0, 0.01 * h, 0))
	var hip_x := 0.085 * h * w
	leg_l = _joint(body_pivot, Vector3(-hip_x, -0.02 * h, 0))
	leg_r = _joint(body_pivot, Vector3(hip_x, -0.02 * h, 0))
	# 騎士は布のズボン＋鉄のすね当て、怪物は素肌（または甲殻）
	var thigh_mat := cloth if archetype == "knight" else flesh
	var shin_mat := body_mat if archetype == "knight" or archetype == "brute" else flesh
	knee_l = _leg(leg_l, h, limb, thigh_mat, shin_mat)
	knee_r = _leg(leg_r, h, limb, thigh_mat, shin_mat)

	# ---- 背骨（前かがみはここで傾ける）
	spine = _joint(body_pivot, Vector3(0, 0.04 * h, 0))
	spine.rotation.x = -_hunch
	_part(spine, _box(Vector3(0.22 * h * w, 0.14 * h, 0.14 * h * w)), flesh, Vector3(0, 0.08 * h, 0))
	var chest_w := 0.34 * h * w * float(a["shoulder"])
	if archetype == "knight" or archetype == "ghoul":
		_part(spine, _box(Vector3(chest_w, 0.17 * h, 0.2 * h * w)), body_mat, Vector3(0, 0.23 * h, 0))
	else:
		var chest := _part(spine, _sphere(0.5, 22), body_mat, Vector3(0, 0.23 * h, 0))
		chest.scale = Vector3(chest_w, 0.22 * h, 0.24 * h * w)
	var shoulder_y := 0.29 * h
	var shoulder_x := chest_w * 0.5 + 0.03 * h
	_shoulder_pos = Vector3(shoulder_x, shoulder_y, 0)

	# ---- 首と頭
	var head_scale: float = a["head"]
	var head_r := 0.07 * h * head_scale
	var head_z := -0.06 * h if archetype == "ghoul" else 0.0
	var neck_y := 0.3 * h if archetype == "brute" or archetype == "colossus" else 0.33 * h
	if archetype == "colossus":
		head_z = -0.05 * h
	var neck := _joint(spine, Vector3(0, neck_y, head_z * 0.5))
	_part(neck, _cyl(0.035 * h, 0.04 * h, 0.06 * h), flesh, Vector3(0, 0.02 * h, 0))
	var head := _joint(neck, Vector3(0, 0.085 * h, head_z * 0.5))
	if archetype != "knight":
		head.rotation.x = _hunch * 0.8   # 前かがみでも顔は前を見る
	_part(head, _sphere(head_r), flesh if archetype == "ghoul" else body_mat, Vector3.ZERO)

	# ---- 右腕（武器）と左腕
	arm = _joint(spine, _shoulder_pos)
	_build_arm(arm, h, limb, float(a["arm"]), flesh, true, cfg)
	off_arm = _joint(spine, Vector3(-shoulder_x, shoulder_y, 0))
	_build_arm(off_arm, h, limb, float(a["arm"]), flesh, false, cfg)
	off_arm.rotation_degrees = Vector3(-80, 10, 0)

	# ---- 体型ごとの装飾
	match archetype:
		"knight":
			_build_knight(head, head_r, h, w, shoulder_x, shoulder_y, cloth)
		"ghoul":
			_build_ghoul(head, head_r, h, w, bone, cloth)
		"brute":
			_build_brute(head, head_r, h, w, shoulder_x, shoulder_y, bone, cloth)
		"colossus":
			_build_colossus(head, head_r, h, w, shoulder_x, shoulder_y, bone, cloth, ember)
	_apply_arm(POSES["rest"])


# ------------------------------------------------------------ 部品

func _mat(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float, seg: int = 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


func _cyl(top: float, bottom: float, h: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## 手足の一節。knight は箱（鎧）、怪物はカプセル（筋肉・骨）。axis_z=true なら -Z 方向に伸びる
func _limb(parent: Node3D, length: float, thick: float, mat: Material, axis_z: bool) -> MeshInstance3D:
	var mesh: Mesh
	if archetype == "knight":
		mesh = _box(Vector3(thick, thick, length) if axis_z else Vector3(thick, length, thick * 1.1))
	else:
		var c := CapsuleMesh.new()
		c.radius = thick * 0.55
		c.height = maxf(length + thick * 0.3, c.radius * 2.0)
		c.radial_segments = 12
		c.rings = 3
		mesh = c
	var pos := Vector3(0, 0, -length * 0.5) if axis_z else Vector3(0, -length * 0.5, 0)
	var rot := Vector3(90, 0, 0) if axis_z and archetype != "knight" else Vector3.ZERO
	return _part(parent, mesh, mat, pos, rot)


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.visibility_range_end = _draw_distance
	# 小さな部品（目・棘・肋骨・爪など）は影を落とさない（影の描画命令を減らす）
	if mesh.get_aabb().get_longest_axis_size() < height * 0.12:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 脚: 太もも → 膝 → すね → 足。膝の Node3D を返す
func _leg(hip: Node3D, h: float, limb: float, flesh: Material, armor: Material) -> Node3D:
	var thigh_len := 0.24 * h
	var shin_len := 0.23 * h
	_limb(hip, thigh_len, 0.085 * limb, flesh, false)
	var knee := _joint(hip, Vector3(0, -thigh_len, 0))
	_limb(knee, shin_len, 0.072 * limb, armor, false)
	_part(knee, _box(Vector3(0.07 * limb, 0.035 * h, 0.13 * h)), armor, Vector3(0, -shin_len - 0.01 * h, -0.03 * h))
	return knee


## 腕: 上腕 → 肘（固定の曲がり）→ 前腕 → 手 → 武器/盾。-Z 方向へ伸びる
func _build_arm(shoulder: Node3D, h: float, limb: float, arm_mul: float, flesh: Material,
		weapon_side: bool, cfg: Dictionary) -> void:
	var upper := 0.16 * h * arm_mul
	var fore := 0.15 * h * arm_mul
	_limb(shoulder, upper, 0.068 * limb, flesh, true)
	var elbow := _joint(shoulder, Vector3(0, 0, -upper))
	elbow.rotation_degrees.x = ELBOW_BEND
	_limb(elbow, fore, 0.06 * limb, body_mat if archetype != "ghoul" else flesh, true)
	var hand := _joint(elbow, Vector3(0, 0, -fore))
	_part(hand, _box(Vector3(0.06 * limb, 0.05 * limb, 0.06 * limb)), flesh, Vector3.ZERO)
	if weapon_side:
		_build_weapon(hand, h, cfg)
	elif cfg.get("shield", false):
		var shield_mat := Surface.apply(_mat(Color(0.3, 0.24, 0.17), 0.3, 0.6), "wood")
		_flash_mats.append(shield_mat)
		_flash_colors.append(shield_mat.albedo_color)
		var s := _part(elbow, _box(Vector3(0.2 * h, 0.27 * h, 0.025 * h)), shield_mat,
			Vector3(-0.04 * h, 0, -fore * 0.55), Vector3(60, 0, 0))
		var boss := _part(s, _sphere(0.035 * h, 8), weapon_mat, Vector3(0, 0, -0.015 * h))
		boss.scale = Vector3(1, 1, 0.5)
	elif archetype == "ghoul" or archetype == "colossus":
		# 鉤爪
		for i in 3:
			var c := _part(hand, _cyl(0.0, 0.012 * h, 0.07 * h, 5), weapon_mat,
				Vector3((i - 1) * 0.02 * h, 0, -0.04 * h), Vector3(-90, 0, 0))
			c.rotation_degrees.y = (i - 1) * 12.0


func _build_weapon(hand: Node3D, h: float, cfg: Dictionary) -> void:
	var length: float = cfg.get("weapon_length", 1.0)
	match archetype:
		"brute":
			# 大鉈: 柄と幅広の刃
			_part(hand, _box(Vector3(0.03 * h, 0.03 * h, length * 0.45)), _mat(Color(0.15, 0.1, 0.08), 0, 0.9),
				Vector3(0, 0, -length * 0.2))
			weapon_mesh = _part(hand, _box(Vector3(0.025 * h, 0.16 * h, length * 0.65)), weapon_mat,
				Vector3(0, 0.06 * h, -length * 0.6))
		"ghoul":
			# 刃こぼれした錆びた剣
			weapon_mesh = _part(hand, _box(Vector3(0.012 * h, 0.05 * h, length)), weapon_mat,
				Vector3(0, 0, -length * 0.5))
			for i in 3:
				_part(weapon_mesh, _box(Vector3(0.014 * h, 0.03 * h, 0.04 * h)), weapon_mat,
					Vector3(0, 0.025 * h, (i - 1) * length * 0.25), Vector3(35, 0, 0))
		_:
			# 長剣・大剣: 刃・鍔・柄頭
			weapon_mesh = _part(hand, _box(Vector3(0.012 * h, 0.045 * h, length)), weapon_mat,
				Vector3(0, 0, -length * 0.5 - 0.03 * h))
			_part(hand, _box(Vector3(0.025 * h, 0.15 * h, 0.02 * h)), weapon_mat, Vector3(0, 0, -0.03 * h))
			_part(hand, _sphere(0.022 * h, 6), weapon_mat, Vector3(0, 0, 0.05 * h))


func _eyes(head: Node3D, head_r: float, count: int, spread: float) -> void:
	for i in count:
		var row := i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		_part(head, _sphere(head_r * 0.14, 6), eye_mat,
			Vector3(side * head_r * spread, head_r * (0.1 - row * 0.32), -head_r * 0.88))


func _build_knight(head: Node3D, head_r: float, h: float, w: float, sx: float, sy: float, cloth: Material) -> void:
	# 兜（面頬のスリットから目が光る）
	_part(head, _cyl(head_r * 0.95, head_r * 1.05, head_r * 1.6, 10), body_mat, Vector3(0, head_r * 0.1, 0))
	_part(head, _box(Vector3(head_r * 1.5, head_r * 0.12, head_r * 0.2)), eye_mat, Vector3(0, head_r * 0.15, -head_r * 0.95))
	_part(head, _box(Vector3(head_r * 0.25, head_r * 0.8, head_r * 1.4)), cloth, Vector3(0, head_r * 1.05, 0.1 * head_r))
	# 肩当て
	for side: float in [-1.0, 1.0]:
		var p := _part(spine, _sphere(0.07 * h, 10), body_mat, Vector3(side * sx, sy + 0.02 * h, 0))
		p.scale = Vector3(1.2, 0.7, 1.1)
	# 前垂れとベルト
	_part(body_pivot, _box(Vector3(0.18 * h * w, 0.2 * h, 0.02 * h)), cloth, Vector3(0, -0.08 * h, -0.09 * h * w))
	_part(spine, _box(Vector3(0.24 * h * w, 0.03 * h, 0.16 * h * w)), _mat(Color(0.35, 0.25, 0.12), 0.6, 0.4),
		Vector3(0, 0.02 * h, 0))
	_build_cape(h, w, sy, cloth, 0.46)


func _build_ghoul(head: Node3D, head_r: float, h: float, w: float, bone: Material, cloth: Material) -> void:
	_eyes(head, head_r, 2, 0.35)
	# 裂けた口
	_part(head, _box(Vector3(head_r * 0.9, head_r * 0.12, head_r * 0.1)), _mat(Color(0.08, 0.02, 0.02), 0, 1),
		Vector3(0, -head_r * 0.45, -head_r * 0.85))
	# 肋骨
	for i in 4:
		_part(spine, _box(Vector3(0.3 * h * w, 0.012 * h, 0.03 * h)), bone,
			Vector3(0, 0.16 * h + i * 0.035 * h, -0.1 * h * w))
	# 背中の骨棘
	for i in 5:
		_part(spine, _cyl(0.0, 0.02 * h, (0.07 + 0.02 * (i % 3)) * h, 5), bone,
			Vector3(0, 0.06 * h + i * 0.06 * h, 0.08 * h * w), Vector3(60, 0, 0))
	# ぼろ布の腰巻き
	_part(body_pivot, _box(Vector3(0.26 * h * w, 0.16 * h, 0.2 * h * w)), cloth, Vector3(0, -0.06 * h, 0))


func _build_brute(head: Node3D, head_r: float, h: float, w: float, sx: float, sy: float,
		bone: Material, cloth: Material) -> void:
	# 角兜と赤い目のスリット
	_part(head, _cyl(head_r * 0.95, head_r * 1.1, head_r * 1.7, 8), body_mat, Vector3(0, head_r * 0.1, 0))
	_part(head, _box(Vector3(head_r * 1.2, head_r * 0.14, head_r * 0.2)), eye_mat, Vector3(0, head_r * 0.1, -head_r * 1.0))
	for side: float in [-1.0, 1.0]:
		_part(head, _cyl(0.0, head_r * 0.28, head_r * 1.8, 6), bone,
			Vector3(side * head_r * 0.9, head_r * 0.9, 0), Vector3(-15, 0, -side * 40))
	# 棘付きの肩当て
	for side: float in [-1.0, 1.0]:
		var p := _part(spine, _sphere(0.09 * h, 10), body_mat, Vector3(side * sx, sy + 0.02 * h, 0))
		p.scale = Vector3(1.25, 0.8, 1.2)
		for k in 3:
			_part(spine, _cyl(0.0, 0.018 * h, 0.08 * h, 5), bone,
				Vector3(side * (sx + 0.02 * h), sy + 0.08 * h, (k - 1) * 0.05 * h), Vector3(0, 0, -side * 25))
	# 鎖帷子の腰布
	_part(body_pivot, _box(Vector3(0.3 * h * w, 0.2 * h, 0.2 * h * w)), cloth, Vector3(0, -0.08 * h, 0))
	_build_cape(h, w, sy, cloth, 0.4)


func _build_colossus(head: Node3D, head_r: float, h: float, w: float, sx: float, sy: float,
		bone: Material, cloth: Material, ember: Material) -> void:
	_eyes(head, head_r, 4, 0.38)
	# 灰の王冠: 頭を囲む角の輪
	for i in 7:
		var ang := TAU * i / 7.0
		var tall := 2.2 if i == 0 else 1.3 + 0.5 * (i % 2)
		_part(head, _cyl(0.0, head_r * 0.2, head_r * tall, 5), bone,
			Vector3(sin(ang) * head_r * 0.85, head_r * (0.7 + tall * 0.3), -cos(ang) * head_r * 0.85),
			Vector3(-cos(ang) * 18.0, 0, -sin(ang) * 18.0))
	# 顎
	_part(head, _box(Vector3(head_r * 1.2, head_r * 0.35, head_r * 0.6)), bone, Vector3(0, -head_r * 0.75, -head_r * 0.35))
	# 胸の燃える亀裂
	for i in 3:
		_part(spine, _box(Vector3(0.022 * h, 0.13 * h, 0.03 * h)), ember,
			Vector3((i - 1) * 0.055 * h, 0.22 * h, -0.118 * h * w), Vector3(0, 0, (i - 1) * 25.0))
	# 背骨の棘
	for i in 6:
		_part(spine, _cyl(0.0, 0.022 * h, (0.07 + 0.03 * (i % 2)) * h, 5), bone,
			Vector3(0, 0.04 * h + i * 0.055 * h, 0.1 * h * w), Vector3(55, 0, 0))
	# 岩のような肩
	for side: float in [-1.0, 1.0]:
		var p := _part(spine, _sphere(0.1 * h, 8), body_mat, Vector3(side * sx, sy + 0.02 * h, 0))
		p.scale = Vector3(1.2, 0.9, 1.2)
	_build_cape(h, w, sy, cloth, 0.5)


## 背中の外套。移動速度に応じて後ろへなびく
func _build_cape(h: float, w: float, sy: float, cloth: Material, length: float) -> void:
	cape = _joint(spine, Vector3(0, sy + 0.02 * h, 0.1 * h * w))
	_part(cape, _box(Vector3(0.3 * h * w, length * h, 0.012 * h)), cloth, Vector3(0, -length * h * 0.5, 0))


# ------------------------------------------------------------ 姿勢

func _apply_arm(pose: Dictionary) -> void:
	arm.rotation_degrees = pose["rot"]
	arm.position = _shoulder_pos + (pose["pos"] as Vector3) * _pose_scale


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"rot": (a["rot"] as Vector3).lerp(b["rot"], t),
		"pos": (a["pos"] as Vector3).lerp(b["pos"], t),
	}


func _set_legs(swing: float, bend_l: float, bend_r: float) -> void:
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	knee_l.rotation.x = -bend_l
	knee_r.rotation.x = -bend_r


## 攻撃中の姿勢。phase: 0=予備動作, 1=判定, 2=硬直 / t: その段階の進行度 0〜1
func pose_attack(anim: String, phase: int, t: float, hop_height: float = 0.0) -> void:
	var def: Dictionary = POSES.get(anim, POSES["slash_r"])
	var rest: Dictionary = POSES["rest"]
	var lean := 0.0
	match phase:
		0:
			_apply_arm(_blend(rest, def["windup"], ease(t, 0.4)))
			# 振りかぶりで体を後ろに反らす（予備動作を読みやすく）
			lean = lerpf(0.0, 0.2, t)
			_set_legs(lerpf(0.0, 0.35, t), 0.3 * t, 0.1 * t)
			_hop = 0.0
		1:
			_apply_arm(_blend(def["windup"], def["end"], ease(t, 0.6)))
			lean = lerpf(0.2, -0.25, t)
			_set_legs(lerpf(0.35, -0.45, t), 0.2, 0.5 * t)
			_hop = sin(t * PI) * hop_height
		2:
			_apply_arm(_blend(def["end"], rest, ease(t, 2.0)))
			lean = lerpf(-0.25, 0.0, t)
			_set_legs(lerpf(-0.45, 0.0, t), 0.2 * (1.0 - t), 0.5 * (1.0 - t))
			_hop = 0.0
	body_pivot.rotation.x = 0.0
	spine.rotation.x = -_hunch + lean
	body_pivot.position.y = height * 0.5 + _hop
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, -0.3 if phase == 1 else -0.1, 0.3)


func pose_idle(delta: float, move_speed: float, guarding: bool = false) -> void:
	var target: Dictionary = POSES["guard"] if guarding else POSES["rest"]
	var k := 1.0 - exp(-14.0 * delta)
	arm.rotation_degrees = arm.rotation_degrees.lerp(target["rot"], k)
	arm.position = arm.position.lerp(_shoulder_pos + (target["pos"] as Vector3) * _pose_scale, k)
	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, 0.0, k)
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, 0.0, k)
	spine.rotation.x = lerpf(spine.rotation.x, -_hunch - (0.12 if guarding else 0.0), k)
	# 歩行サイクル: 脚を交互に振り、膝を曲げ、反対の腕を振る
	var stride := clampf(move_speed / 4.0, 0.0, 1.6)
	if move_speed > 0.2:
		_walk_phase += delta * (4.0 + move_speed * 1.6) / maxf(_pose_scale, 0.6)
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, k)
	var s := sin(_walk_phase)
	_set_legs(s * 0.5 * stride, maxf(0.0, -s) * 0.9 * stride + 0.05, maxf(0.0, s) * 0.9 * stride + 0.05)
	var off_target := Vector3(-15, 30, 0) if guarding else Vector3(-80 - s * 25.0 * stride, 10, 0)
	off_arm.rotation_degrees = off_arm.rotation_degrees.lerp(off_target, k)
	body_pivot.position.y = height * 0.5 + absf(cos(_walk_phase)) * 0.025 * height * stride
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, -0.08 - 0.12 * stride + sin(_walk_phase * 0.5) * 0.03, k)


## 回避の前転。t: 0〜1
func pose_roll(t: float) -> void:
	body_pivot.rotation.x = -TAU * ease(t, 0.8)
	body_pivot.position.y = height * 0.5 - sin(t * PI) * height * 0.25
	_set_legs(0.9 * sin(t * PI), 1.6 * sin(t * PI), 1.6 * sin(t * PI))


func pose_stagger(t: float) -> void:
	body_pivot.rotation.x = sin(t * PI) * 0.35
	spine.rotation.x = -_hunch + sin(t * PI) * 0.3
	_set_legs(-0.2 * sin(t * PI), 0.4 * sin(t * PI), 0.1)
	_apply_arm(POSES["rest"])


func pose_dead(t: float) -> void:
	var k := clampf(t, 0.0, 1.0)
	body_pivot.rotation.x = lerpf(0.0, PI * 0.5, ease(k, 0.5))
	body_pivot.position.y = lerpf(height * 0.5, height * 0.12, k)
	_set_legs(0.0, 0.6 * k, 0.2 * k)


func reset_pose() -> void:
	body_pivot.rotation = Vector3.ZERO
	body_pivot.position.y = height * 0.5
	spine.rotation.x = -_hunch
	_set_legs(0.0, 0.05, 0.05)
	_apply_arm(POSES["rest"])
	set_telegraph(0.0)


## 予備動作の警告発光（武器と目が赤く光る）。amount: 0〜1
func set_telegraph(amount: float) -> void:
	weapon_mat.emission_energy_multiplier = amount * 4.0
	eye_mat.emission_energy_multiplier = base_eye_energy + amount * 4.0


func flash_hit() -> void:
	_flash_time = 0.1
	for m in _flash_mats:
		m.albedo_color = Color(1, 1, 1)


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for i in _flash_mats.size():
				_flash_mats[i].albedo_color = _flash_colors[i]
