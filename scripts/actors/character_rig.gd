class_name CharacterRig
extends Node3D
## 素材なしで動く「仮の見た目」。プリミティブ形状を組み合わせ、攻撃・回避・被弾の
## 状態に合わせて腕と体の姿勢をコードで補間する（プロシージャル・アニメーション）。
## 後で本物の3Dモデル+AnimationPlayerに差し替える時も、呼び出し側のAPIはこのまま使える。

## 腕の回転（度）と肩の位置ずれ。windup=振りかぶり / end=振り抜き
const POSES := {
	"rest": {"rot": Vector3(-55, -10, 0), "pos": Vector3.ZERO},
	"guard": {"rot": Vector3(-20, 40, 0), "pos": Vector3(0, 0, -0.1)},
	"slash_r": {
		"windup": {"rot": Vector3(-5, -115, 0), "pos": Vector3.ZERO},
		"end": {"rot": Vector3(-20, 95, 0), "pos": Vector3.ZERO},
	},
	"slash_l": {
		"windup": {"rot": Vector3(-5, 100, 0), "pos": Vector3.ZERO},
		"end": {"rot": Vector3(-20, -100, 0), "pos": Vector3.ZERO},
	},
	"overhead": {
		"windup": {"rot": Vector3(135, 0, 0), "pos": Vector3(0, 0.1, 0.1)},
		"end": {"rot": Vector3(-75, 0, 0), "pos": Vector3(0, -0.1, -0.2)},
	},
	"thrust": {
		"windup": {"rot": Vector3(5, 0, 0), "pos": Vector3(0, 0, 0.5)},
		"end": {"rot": Vector3(-5, 0, 0), "pos": Vector3(0, 0, -0.7)},
	},
	"stomp": {
		"windup": {"rot": Vector3(150, 0, 0), "pos": Vector3(0, 0.2, 0)},
		"end": {"rot": Vector3(-85, 0, 0), "pos": Vector3(0, -0.3, -0.2)},
	},
}

var height := 1.8
var radius := 0.35
var body_pivot: Node3D
var arm: Node3D
var off_arm: Node3D
var weapon_mesh: MeshInstance3D
var body_mat: StandardMaterial3D
var weapon_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var base_body_color := Color.GRAY
var base_eye_energy := 1.0
var _flash_time := 0.0
var _walk_phase := 0.0
var _hop := 0.0


## cfg: height, radius, body_color, weapon_color, weapon_length, eye_color, shield(bool), horns(bool)
func build(cfg: Dictionary) -> void:
	height = cfg.get("height", 1.8)
	radius = cfg.get("radius", 0.35)
	base_body_color = cfg.get("body_color", Color(0.4, 0.4, 0.45))
	var weapon_len: float = cfg.get("weapon_length", 1.1)

	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	body_pivot.position.y = height * 0.5
	add_child(body_pivot)

	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = base_body_color
	body_mat.roughness = 0.85
	weapon_mat = StandardMaterial3D.new()
	weapon_mat.albedo_color = cfg.get("weapon_color", Color(0.7, 0.7, 0.75))
	weapon_mat.metallic = 0.7
	weapon_mat.roughness = 0.35
	weapon_mat.emission_enabled = true
	weapon_mat.emission = Color(1.0, 0.35, 0.1)
	weapon_mat.emission_energy_multiplier = 0.0
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = cfg.get("eye_color", Color(0.9, 0.8, 0.5))
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_mat.albedo_color
	base_eye_energy = cfg.get("eye_energy", 1.5)
	eye_mat.emission_energy_multiplier = base_eye_energy

	# 胴体（足元からの高さ height の 0.78 を占めるカプセル）
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radial_segments = 16
	cap.rings = 4
	cap.radius = radius
	cap.height = height * 0.78
	torso.mesh = cap
	torso.material_override = body_mat
	torso.position.y = -height * 0.5 + cap.height * 0.5
	body_pivot.add_child(torso)

	# 頭
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radial_segments = 16
	sph.rings = 8
	sph.radius = radius * 0.62
	sph.height = radius * 1.24
	head.mesh = sph
	head.material_override = body_mat
	var head_y := height * 0.5 - radius * 0.6
	head.position.y = head_y
	body_pivot.add_child(head)

	# 目（正面 -Z 側に2つ）
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radial_segments = 8
		em.rings = 4
		em.radius = radius * 0.11
		em.height = radius * 0.22
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(side * radius * 0.25, head_y + radius * 0.05, -radius * 0.55)
		body_pivot.add_child(eye)

	if cfg.get("horns", false):
		for side: float in [-1.0, 1.0]:
			var horn := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.radial_segments = 12
			cone.rings = 1
			cone.top_radius = 0.0
			cone.bottom_radius = radius * 0.15
			cone.height = radius * 0.9
			horn.mesh = cone
			horn.material_override = weapon_mat
			horn.position = Vector3(side * radius * 0.4, head_y + radius * 0.6, 0)
			horn.rotation_degrees = Vector3(0, 0, -side * 30)
			body_pivot.add_child(horn)

	# 武器を持つ右腕（肩を支点に回転）
	arm = Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(radius * 1.15, height * 0.22, 0)
	body_pivot.add_child(arm)
	var arm_len := height * 0.3
	var arm_mesh := MeshInstance3D.new()
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(radius * 0.4, radius * 0.4, arm_len)
	arm_mesh.mesh = arm_box
	arm_mesh.material_override = body_mat
	arm_mesh.position.z = -arm_len * 0.5
	arm.add_child(arm_mesh)
	weapon_mesh = MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(radius * 0.18, radius * 0.45, weapon_len)
	weapon_mesh.mesh = blade
	weapon_mesh.material_override = weapon_mat
	weapon_mesh.position.z = -arm_len - weapon_len * 0.5
	arm.add_child(weapon_mesh)

	# 左腕（盾持ちならガード時に構える）
	off_arm = Node3D.new()
	off_arm.position = Vector3(-radius * 1.15, height * 0.22, 0)
	off_arm.rotation_degrees = Vector3(-70, 10, 0)
	body_pivot.add_child(off_arm)
	var off_mesh := MeshInstance3D.new()
	off_mesh.mesh = arm_box
	off_mesh.material_override = body_mat
	off_mesh.position.z = -arm_len * 0.5
	off_arm.add_child(off_mesh)
	if cfg.get("shield", false):
		var shield := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(radius * 1.6, radius * 2.0, 0.08)
		shield.mesh = sb
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.35, 0.28, 0.2)
		smat.metallic = 0.4
		shield.material_override = smat
		shield.position = Vector3(0, 0, -arm_len)
		shield.rotation_degrees = Vector3(70, 0, 0)
		off_arm.add_child(shield)

	_apply_arm(POSES["rest"])


func _apply_arm(pose: Dictionary) -> void:
	arm.rotation_degrees = pose["rot"]
	arm.position = Vector3(radius * 1.15, height * 0.22, 0) + (pose["pos"] as Vector3)


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"rot": (a["rot"] as Vector3).lerp(b["rot"], t),
		"pos": (a["pos"] as Vector3).lerp(b["pos"], t),
	}


## 攻撃中の姿勢。phase: 0=予備動作, 1=判定, 2=硬直 / t: その段階の進行度 0〜1
func pose_attack(anim: String, phase: int, t: float, hop_height: float = 0.0) -> void:
	var def: Dictionary = POSES.get(anim, POSES["slash_r"])
	var rest: Dictionary = POSES["rest"]
	match phase:
		0:
			_apply_arm(_blend(rest, def["windup"], ease(t, 0.4)))
			# 振りかぶりで体を少し後ろに反らす（予備動作を読みやすく）
			body_pivot.rotation.x = lerpf(0.0, 0.18, t)
			_hop = 0.0
		1:
			_apply_arm(_blend(def["windup"], def["end"], ease(t, 0.6)))
			body_pivot.rotation.x = lerpf(0.18, -0.2, t)
			_hop = sin(t * PI) * hop_height
		2:
			_apply_arm(_blend(def["end"], rest, ease(t, 2.0)))
			body_pivot.rotation.x = lerpf(-0.2, 0.0, t)
			_hop = 0.0
	body_pivot.position.y = height * 0.5 + _hop


func pose_idle(delta: float, move_speed: float, guarding: bool = false) -> void:
	var target: Dictionary = POSES["guard"] if guarding else POSES["rest"]
	var k := 1.0 - exp(-14.0 * delta)
	arm.rotation_degrees = arm.rotation_degrees.lerp(target["rot"], k)
	arm.position = arm.position.lerp(Vector3(radius * 1.15, height * 0.22, 0) + (target["pos"] as Vector3), k)
	var off_target := Vector3(-10, 25, 0) if guarding else Vector3(-70, 10, 0)
	off_arm.rotation_degrees = off_arm.rotation_degrees.lerp(off_target, k)
	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, 0.0, k)
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, 0.0, k)
	# 歩行の上下揺れ
	if move_speed > 0.2:
		_walk_phase += delta * move_speed * 2.2
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, k)
	body_pivot.position.y = height * 0.5 + absf(sin(_walk_phase)) * 0.06 * height


## 回避の前転。t: 0〜1
func pose_roll(t: float) -> void:
	body_pivot.rotation.x = -TAU * ease(t, 0.8)
	body_pivot.position.y = height * 0.5 - sin(t * PI) * height * 0.25


func pose_stagger(t: float) -> void:
	body_pivot.rotation.x = sin(t * PI) * 0.45
	_apply_arm(POSES["rest"])


func pose_dead(t: float) -> void:
	body_pivot.rotation.x = lerpf(0.0, PI * 0.5, ease(clampf(t, 0.0, 1.0), 0.5))
	body_pivot.position.y = lerpf(height * 0.5, radius, clampf(t, 0.0, 1.0))


func reset_pose() -> void:
	body_pivot.rotation = Vector3.ZERO
	body_pivot.position.y = height * 0.5
	_apply_arm(POSES["rest"])
	set_telegraph(0.0)


## 予備動作の警告発光（武器と目が赤く光る）。amount: 0〜1
func set_telegraph(amount: float) -> void:
	weapon_mat.emission_energy_multiplier = amount * 4.0
	eye_mat.emission_energy_multiplier = base_eye_energy + amount * 4.0


func flash_hit() -> void:
	_flash_time = 0.1
	body_mat.albedo_color = Color(1, 1, 1)


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			body_mat.albedo_color = base_body_color
