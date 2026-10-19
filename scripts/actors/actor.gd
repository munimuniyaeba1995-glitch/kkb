class_name Actor
extends CharacterBody3D
## プレイヤーと敵の共通基底。HP、被ダメージ、攻撃の当たり判定クエリを持つ。

signal health_changed(current: float, max_value: float)
signal died(actor: Actor)

enum HitResult { IGNORED, HIT, BLOCKED, DODGED }

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

var max_health := 100.0
var health := 100.0
var is_dead := false
## 0=プレイヤー陣営, 1=敵陣営。同じ陣営同士は当たらない
var team := 0
var rig: CharacterRig
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## 攻撃の当たり判定が狙うレイヤー
var hit_mask := LAYER_ENEMY


func set_health_full() -> void:
	health = max_health
	is_dead = false
	health_changed.emit(health, max_health)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		die()


func die() -> void:
	is_dead = true
	died.emit(self)


## 攻撃を受けた時に呼ばれる。派生クラスでガード・回避・怯みを処理する
func receive_attack(attack: AttackData, _attacker: Node3D) -> int:
	if is_dead:
		return HitResult.IGNORED
	take_damage(attack.damage)
	if rig:
		rig.flash_hit()
	return HitResult.HIT


func forward_dir() -> Vector3:
	return -global_transform.basis.z


## 攻撃の判定球を出し、当たった相手に receive_attack を呼ぶ。
## already_hit に入っている相手には同じ攻撃で二度当たらない。
## damage_scale はプレイヤーの攻撃力補正用。
func run_hit_query(attack: AttackData, t: float, already_hit: Array, damage_scale: float = 1.0) -> Array:
	var results_out: Array = []
	var shape := SphereShape3D.new()
	shape.radius = attack.hit_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	var local_offset := attack.hit_offset_start.lerp(attack.hit_offset_end, clampf(t, 0.0, 1.0))
	params.transform = Transform3D(Basis(), global_transform * local_offset)
	params.collision_mask = hit_mask
	params.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 16)
	for h: Dictionary in hits:
		var target: Object = h["collider"]
		if target == null or target == self or already_hit.has(target):
			continue
		if not target.has_method("receive_attack"):
			continue
		if target.get("team") == team:
			continue
		already_hit.append(target)
		var atk := attack
		if not is_equal_approx(damage_scale, 1.0):
			atk = attack.duplicate()
			atk.damage = attack.damage * damage_scale
		var r: int = target.receive_attack(atk, self)
		results_out.append({"target": target, "result": r})
	return results_out


func make_capsule_collision(r: float, h: float) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	col.shape = cap
	col.position.y = h * 0.5
	add_child(col)
	return col


## 指定方向へ体の向きを滑らかに回す
func face_towards(dir: Vector3, delta: float, speed: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-speed * delta))


func face_instantly(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)
