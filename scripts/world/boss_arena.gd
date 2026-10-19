class_name BossArena
extends Node3D
## ボス部屋。プレイヤーが中に入ると霧の壁が入口を閉じ、ボス戦が始まる。
## プレイヤーが死ぬか、ボスを倒すと開く。

signal battle_started(boss: Boss)
signal battle_ended(victory: bool)

var boss: Boss
var player: Player
var arena_radius := 20.0
var entrance_pos := Vector3.ZERO
var fog_wall: StaticBody3D
var fog_col: CollisionShape3D
var fog_mesh: MeshInstance3D
var active := false


func setup_gate(entrance: Vector3, width: float, height: float) -> void:
	entrance_pos = entrance
	fog_wall = StaticBody3D.new()
	fog_wall.collision_layer = Actor.LAYER_WORLD
	add_child(fog_wall)
	fog_wall.global_position = entrance
	fog_col = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.6)
	fog_col.shape = bs
	fog_col.position.y = height * 0.5
	fog_wall.add_child(fog_col)
	fog_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	fog_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.75, 0.55, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.7, 0.4)
	mat.emission_energy_multiplier = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_mesh.material_override = mat
	fog_mesh.position.y = height * 0.5
	fog_wall.add_child(fog_mesh)
	_set_gate(false)


func _set_gate(closed: bool) -> void:
	fog_col.disabled = not closed
	fog_mesh.visible = closed


func _physics_process(_delta: float) -> void:
	if boss == null or player == null:
		return
	if active:
		if player.is_dead:
			end_battle(false)
		return
	if boss.is_dead or GameState.boss_defeated or player.is_dead:
		return
	var center := global_position
	var flat := Vector2(player.global_position.x - center.x, player.global_position.z - center.z)
	# 入口から2m以上中に入ったら開始（霧の壁にプレイヤーが挟まらないように）
	if flat.length() < arena_radius - 2.0:
		start_battle()


func start_battle() -> void:
	active = true
	_set_gate(true)
	boss.engage(player)
	battle_started.emit(boss)


func end_battle(victory: bool) -> void:
	if not active:
		return
	active = false
	_set_gate(false)
	battle_ended.emit(victory)


## 復活・休息時に呼ばれる
func reset_arena() -> void:
	active = false
	_set_gate(false)
