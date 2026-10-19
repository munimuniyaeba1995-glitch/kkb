class_name SecretWall
extends StaticBody3D
## 隠し通路をふさぐ「偽の壁」。見た目は普通の壁だが、攻撃すると崩れて消える。
## 敵レイヤーに入れてあるのでプレイヤーの攻撃判定が当たる（ロックオン対象にはならない）。

signal broken

var wall_id := ""
var team := 1
var size := Vector3(4, 4, 1)
var mesh: MeshInstance3D


func _init(id: String = "", wall_size: Vector3 = Vector3(4, 4, 1)) -> void:
	wall_id = id
	size = wall_size


func _ready() -> void:
	collision_layer = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
	mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	# ほんの少しだけ周囲の壁と色が違う（注意深いプレイヤーへのヒント）
	mat.albedo_color = Color(0.33, 0.31, 0.3)
	mat.roughness = 0.95
	mesh.material_override = mat
	mesh.position.y = size.y * 0.5
	add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	col.position.y = size.y * 0.5
	add_child(col)
	if GameState.is_claimed(wall_id):
		queue_free()


func receive_attack(_attack: AttackData, _attacker: Node3D) -> int:
	if GameState.is_claimed(wall_id):
		return Actor.HitResult.IGNORED
	GameState.claim(wall_id)
	GameState.notify.emit("壁が崩れ、隠された通路が現れた")
	broken.emit()
	collision_layer = 0
	var tw := create_tween()
	tw.tween_property(mesh, "scale", Vector3(1, 0.05, 1), 0.5)
	tw.tween_callback(queue_free)
	return Actor.HitResult.HIT
