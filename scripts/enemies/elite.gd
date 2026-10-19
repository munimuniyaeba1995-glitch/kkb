class_name Elite
extends Enemy
## 強敵「黒鉄の処刑人」。3連撃コンボ、遠距離からの突進突き、
## わざと溜めてタイミングをずらす振り下ろし（ディレイ攻撃）を使い分ける。


func setup() -> void:
	display_name = "黒鉄の処刑人"
	max_health = 340.0
	ash_reward = 400
	move_speed = 2.8
	aggro_range = 12.0
	turn_speed = 6.0
	max_poise = 55.0
	stagger_time = 1.0
	preferred_distance = 2.2
	think_delay = 0.7
	lock_height = 1.5
	build_body({
		"archetype": "brute", "height": 2.5, "radius": 0.5,
		"body_color": Color(0.14, 0.14, 0.16), "skin_color": Color(0.3, 0.26, 0.24),
		"cloth_color": Color(0.1, 0.08, 0.08),
		"weapon_color": Color(0.32, 0.3, 0.3), "weapon_length": 1.6,
		"eye_color": Color(1.0, 0.12, 0.05), "eye_energy": 4.0,
	})
	add_attack(AttackData.create({
		"id": "combo1", "damage": 40.0, "poise_damage": 20.0,
		"windup": 0.55, "active": 0.2, "recovery": 0.55,
		"hit_radius": 1.1, "hit_offset_start": Vector3(1.2, 1.3, -1.0),
		"hit_offset_end": Vector3(-1.2, 1.3, -1.1), "lunge_speed": 3.0,
		"max_range": 3.0, "weight": 3.0, "anim": "slash_r",
		"followup_id": "combo2", "followup_chance": 0.65,
	}))
	add_attack(AttackData.create({
		"id": "combo2", "damage": 40.0, "poise_damage": 20.0,
		"windup": 0.35, "active": 0.2, "recovery": 0.6,
		"hit_radius": 1.1, "hit_offset_start": Vector3(-1.2, 1.3, -1.0),
		"hit_offset_end": Vector3(1.2, 1.3, -1.1), "lunge_speed": 3.0,
		"weight": 0.0, "anim": "slash_l", "followup_id": "combo3", "followup_chance": 0.5,
	}))
	add_attack(AttackData.create({
		"id": "combo3", "damage": 60.0, "poise_damage": 30.0,
		"windup": 0.5, "active": 0.18, "recovery": 1.1,
		"hit_radius": 1.1, "hit_offset_start": Vector3(0, 2.2, -1.0),
		"hit_offset_end": Vector3(0, 0.5, -1.8), "lunge_speed": 2.0,
		"weight": 0.0, "anim": "overhead", "knockback": 5.0,
	}))
	add_attack(AttackData.create({
		"id": "thrust", "damage": 50.0, "poise_damage": 25.0,
		"windup": 0.7, "active": 0.35, "recovery": 1.0,
		"hit_radius": 0.8, "hit_offset_start": Vector3(0, 1.3, -1.2),
		"hit_offset_end": Vector3(0, 1.3, -1.6), "lunge_speed": 11.0, "homing_lunge": true,
		"min_range": 3.5, "max_range": 8.0, "cooldown": 5.0, "weight": 2.0, "anim": "thrust",
	}))
	# ディレイ攻撃: 長く溜めて、焦って回避したところを狩る
	add_attack(AttackData.create({
		"id": "delayed", "damage": 75.0, "poise_damage": 40.0,
		"windup": 1.3, "active": 0.18, "recovery": 1.2, "tracking": 0.85,
		"hit_radius": 1.2, "hit_offset_start": Vector3(0, 2.2, -1.0),
		"hit_offset_end": Vector3(0, 0.4, -2.0), "lunge_speed": 2.0,
		"max_range": 3.2, "cooldown": 6.0, "weight": 1.5, "anim": "overhead", "knockback": 6.0,
	}))
