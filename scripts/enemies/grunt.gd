class_name Grunt
extends Enemy
## 雑魚敵「灰憑きの兵」。近づいて斬りつける。少し離れると突きで飛び込んでくる。


func setup() -> void:
	display_name = "灰憑きの兵"
	max_health = 90.0
	ash_reward = 60
	move_speed = 3.2
	aggro_range = 10.0
	max_poise = 20.0
	stagger_time = 0.7
	preferred_distance = 1.5
	think_delay = 0.6
	build_body({
		"height": 1.75, "radius": 0.38,
		"body_color": Color(0.42, 0.38, 0.33),
		"weapon_color": Color(0.45, 0.4, 0.35), "weapon_length": 0.9,
		"eye_color": Color(1.0, 0.55, 0.2), "eye_energy": 2.0,
	})
	add_attack(AttackData.create({
		"id": "slash", "damage": 30.0, "poise_damage": 15.0,
		"windup": 0.65, "active": 0.18, "recovery": 0.8,
		"hit_radius": 0.9, "hit_offset_start": Vector3(0.9, 1.1, -0.8),
		"hit_offset_end": Vector3(-0.9, 1.1, -0.9),
		"lunge_speed": 2.0, "min_range": 0.0, "max_range": 2.3, "weight": 3.0, "anim": "slash_r",
	}))
	add_attack(AttackData.create({
		"id": "lunge", "damage": 34.0, "poise_damage": 18.0,
		"windup": 0.75, "active": 0.3, "recovery": 1.0,
		"hit_radius": 0.7, "hit_offset_start": Vector3(0, 1.1, -1.0),
		"hit_offset_end": Vector3(0, 1.1, -1.4),
		"lunge_speed": 9.0, "min_range": 2.8, "max_range": 6.0, "cooldown": 4.0,
		"weight": 1.5, "anim": "thrust", "knockback": 4.0,
	}))
