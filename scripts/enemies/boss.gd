class_name Boss
extends Enemy
## ボス「灰冠の守護者 ヴォルグレイン」。巨体・高HP・高強靭度。
## 近距離: 薙ぎ払い / 踏みつけ衝撃波、中距離: 叩きつけ、遠距離: 跳躍攻撃。
## HPが半分を切ると第2形態（速度上昇・予備動作短縮・薙ぎ払いの返し斬り追加）。

signal phase_changed(phase: int)

var phase := 1
var engaged := false


func setup() -> void:
	display_name = "灰冠の守護者 ヴォルグレイン"
	max_health = 1800.0
	ash_reward = 5000
	move_speed = 3.4
	aggro_range = 0.0
	turn_speed = 3.5
	max_poise = 160.0
	poise_regen = 6.0
	stagger_time = 1.6
	preferred_distance = 4.0
	think_delay = 0.9
	lock_height = 3.4
	can_aggro = false
	always_aggro = true
	build_body({
		"height": 5.2, "radius": 1.2,
		"body_color": Color(0.27, 0.25, 0.24),
		"weapon_color": Color(0.5, 0.45, 0.4), "weapon_length": 3.0,
		"eye_color": Color(1.0, 0.6, 0.15), "eye_energy": 4.0, "horns": true,
	})
	add_attack(AttackData.create({
		"id": "sweep", "damage": 70.0, "poise_damage": 40.0,
		"windup": 0.95, "active": 0.3, "recovery": 1.0,
		"hit_radius": 2.2, "hit_offset_start": Vector3(3.5, 2.0, -2.0),
		"hit_offset_end": Vector3(-3.5, 2.0, -2.6), "lunge_speed": 2.0,
		"max_range": 6.0, "weight": 3.0, "anim": "slash_r", "knockback": 6.0,
		"followup_id": "sweep_back", "followup_chance": 0.0,
	}))
	add_attack(AttackData.create({
		"id": "sweep_back", "damage": 65.0, "poise_damage": 40.0,
		"windup": 0.5, "active": 0.3, "recovery": 1.1,
		"hit_radius": 2.2, "hit_offset_start": Vector3(-3.5, 2.0, -2.0),
		"hit_offset_end": Vector3(3.5, 2.0, -2.6), "lunge_speed": 2.0,
		"weight": 0.0, "anim": "slash_l", "knockback": 6.0,
	}))
	add_attack(AttackData.create({
		"id": "slam", "damage": 95.0, "poise_damage": 60.0,
		"windup": 1.2, "active": 0.2, "recovery": 1.4, "tracking": 0.8,
		"hit_radius": 2.4, "hit_offset_start": Vector3(0, 4.5, -2.5),
		"hit_offset_end": Vector3(0, 0.8, -5.0), "lunge_speed": 1.5,
		"min_range": 2.0, "max_range": 7.5, "weight": 2.0, "anim": "overhead", "knockback": 7.0,
	}))
	add_attack(AttackData.create({
		"id": "leap", "damage": 85.0, "poise_damage": 60.0,
		"windup": 1.0, "active": 0.55, "recovery": 1.3, "tracking": 0.9,
		"hit_radius": 3.0, "hit_offset_start": Vector3(0, 1.0, -2.5),
		"hit_offset_end": Vector3(0, 1.0, -2.5),
		"lunge_speed": 22.0, "homing_lunge": true, "hop_height": 3.0,
		"min_range": 8.0, "max_range": 25.0, "cooldown": 5.0, "weight": 3.0,
		"anim": "stomp", "knockback": 8.0,
	}))
	add_attack(AttackData.create({
		"id": "stomp", "damage": 55.0, "poise_damage": 50.0,
		"windup": 1.0, "active": 0.15, "recovery": 1.0,
		"hit_radius": 4.6, "hit_offset_start": Vector3(0, 0.8, 0),
		"hit_offset_end": Vector3(0, 0.8, 0), "hop_height": 1.0,
		"max_range": 4.5, "cooldown": 7.0, "weight": 1.5, "anim": "stomp", "knockback": 9.0,
	}))


## ボス部屋に入った時に呼ばれ、戦闘を開始する
func engage(player: Player) -> void:
	if is_dead or engaged:
		return
	engaged = true
	target = player
	can_aggro = true
	_begin_chase()
	think_timer = 1.2


func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if not is_dead and phase == 1 and health <= max_health * 0.5:
		_enter_phase_two()


func _enter_phase_two() -> void:
	phase = 2
	speed_mult = 1.25
	windup_mult = 0.85
	think_delay = 0.6
	(attacks["sweep"] as AttackData).followup_chance = 0.7
	(attacks["stomp"] as AttackData).weight = 2.5
	phase_changed.emit(phase)


func reset_enemy() -> void:
	super.reset_enemy()
	engaged = false
	can_aggro = false
	phase = 1
	speed_mult = 1.0
	windup_mult = 1.0
	think_delay = 0.9
	(attacks["sweep"] as AttackData).followup_chance = 0.0
	(attacks["stomp"] as AttackData).weight = 1.5
