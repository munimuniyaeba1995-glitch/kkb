class_name Enemy
extends Actor
## 敵AIの基底。待機 → 追跡 → 攻撃（予備動作→判定→硬直）→ 追跡… を繰り返す。
## 派生クラスは setup() で能力値・攻撃パターン・見た目を定義するだけでよい。

signal defeated(enemy: Enemy)
signal attack_started(enemy: Enemy, attack: AttackData)

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD, RETURN }

var display_name := "敵"
var ash_reward := 50
var move_speed := 3.0
var aggro_range := 11.0
var leash_range := 30.0
var turn_speed := 7.0
## 強靭度。被弾ごとに poise_damage だけ減り、0で怯む
var max_poise := 25.0
var poise := 25.0
var poise_regen := 10.0
var stagger_time := 0.8
var radius := 0.4
var body_height := 1.8
## ロックオンマーカーの高さ
var lock_height := 1.2
## 追跡を止めて攻撃に移る距離
var preferred_distance := 1.6
## 攻撃と攻撃の間の考える時間（秒）
var think_delay := 0.5
var speed_mult := 1.0
var windup_mult := 1.0
var can_aggro := true
var always_aggro := false
## id -> AttackData。weight が 0 の攻撃はコンボの続きとしてだけ使われる
var attacks: Dictionary = {}

var state := State.IDLE
var state_time := 0.0
var current_attack: AttackData
var attack_phase := 0
var hit_list: Array = []
var target: Player
var home_position := Vector3.ZERO
var home_yaw := 0.0
var cooldowns: Dictionary = {}
var think_timer := 0.0
var knock := Vector3.ZERO
var current_lunge := 0.0
var rng := RandomNumberGenerator.new()
var collision: CollisionShape3D


func _ready() -> void:
	team = 1
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	hit_mask = LAYER_PLAYER
	add_to_group("enemies")
	setup()
	set_health_full()
	poise = max_poise


## 派生クラスで上書きする
func setup() -> void:
	pass


func build_body(cfg: Dictionary) -> void:
	radius = cfg.get("radius", radius)
	body_height = cfg.get("height", body_height)
	rig = CharacterRig.new()
	add_child(rig)
	rig.build(cfg)
	collision = make_capsule_collision(radius, body_height)


func add_attack(a: AttackData) -> void:
	attacks[a.id] = a


## 配置場所を決める（再配置時に戻る場所になる）
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	home_position = pos
	home_yaw = yaw


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and not target.is_dead


func _physics_process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Player
	state_time += delta
	for k: String in cooldowns:
		cooldowns[k] = float(cooldowns[k]) - delta
	if state != State.ATTACK and state != State.STAGGER:
		poise = minf(max_poise, poise + poise_regen * delta)

	match state:
		State.IDLE:
			_state_idle(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)
		State.RETURN:
			_state_return(delta)
		State.DEAD:
			_state_dead()
			return

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	if s != State.ATTACK:
		rig.set_telegraph(0.0)


func _dist_to_target() -> float:
	var to := target.global_position - global_position
	return Vector2(to.x, to.z).length()


func _state_idle(delta: float) -> void:
	_brake(delta, 10.0)
	rig.pose_idle(delta, 0.0)
	if can_aggro and _target_valid() and _dist_to_target() < aggro_range:
		_begin_chase()


func _begin_chase() -> void:
	_set_state(State.CHASE)
	think_timer = rng.randf_range(0.2, 0.6)


func _state_chase(delta: float) -> void:
	if not _target_valid():
		_set_state(State.RETURN)
		return
	if not always_aggro and global_position.distance_to(home_position) > leash_range:
		_set_state(State.RETURN)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	face_towards(to, delta, turn_speed)
	think_timer -= delta
	if think_timer <= 0.0:
		var atk := choose_attack(dist)
		if atk:
			start_attack(atk)
			return
	var desired := Vector3.ZERO
	if dist > preferred_distance:
		desired = to.normalized() * move_speed * speed_mult
	velocity.x = move_toward(velocity.x, desired.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 20.0 * delta)
	rig.pose_idle(delta, Vector2(velocity.x, velocity.z).length())


## 距離に合う攻撃を重み付きランダムで選ぶ
func choose_attack(dist: float) -> AttackData:
	var to := (target.global_position - global_position)
	to.y = 0.0
	if forward_dir().dot(to.normalized()) < 0.6:
		return null
	var candidates: Array[AttackData] = []
	var total := 0.0
	for a: AttackData in attacks.values():
		if a.weight <= 0.0 or dist < a.min_range or dist > a.max_range:
			continue
		if float(cooldowns.get(a.id, 0.0)) > 0.0:
			continue
		candidates.append(a)
		total += a.weight
	if candidates.is_empty():
		return null
	var roll := rng.randf() * total
	for a in candidates:
		roll -= a.weight
		if roll <= 0.0:
			return a
	return candidates[-1]


func start_attack(a: AttackData) -> void:
	_set_state(State.ATTACK)
	current_attack = a
	attack_phase = 0
	hit_list.clear()
	cooldowns[a.id] = a.cooldown
	attack_started.emit(self, a)


func _state_attack(delta: float) -> void:
	var a := current_attack
	var windup := a.windup * windup_mult
	var t := state_time
	var tt := 0.0
	if t < windup:
		attack_phase = 0
		tt = t / windup
		# 予備動作の前半だけ相手に向き直る。後半は向きが固定されるので横に避けられる
		if tt < a.tracking and _target_valid():
			face_towards(target.global_position - global_position, delta, turn_speed * 1.5)
		_brake(delta, 15.0)
		rig.set_telegraph(tt)
	elif t < windup + a.active:
		if attack_phase != 1:
			attack_phase = 1
			current_lunge = a.lunge_speed
			if a.homing_lunge and _target_valid():
				current_lunge = clampf((_dist_to_target() - radius - 1.0) / a.active, 0.0, a.lunge_speed)
		tt = (t - windup) / a.active
		rig.set_telegraph(1.0 - tt)
		var fwd := forward_dir()
		velocity.x = fwd.x * current_lunge
		velocity.z = fwd.z * current_lunge
		run_hit_query(a, tt, hit_list)
	else:
		attack_phase = 2
		tt = (t - windup - a.active) / a.recovery
		_brake(delta, 25.0)
		if tt >= 1.0:
			_finish_attack(a)
			return
	rig.pose_attack(a.anim, attack_phase, tt, a.hop_height)


func _finish_attack(a: AttackData) -> void:
	if a.followup_id != "" and attacks.has(a.followup_id) and _target_valid() \
			and rng.randf() < a.followup_chance:
		start_attack(attacks[a.followup_id])
		return
	_set_state(State.CHASE)
	think_timer = think_delay * rng.randf_range(0.6, 1.4)


func _state_stagger(delta: float) -> void:
	knock = knock.move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = knock.x
	velocity.z = knock.z
	rig.pose_stagger(minf(state_time / stagger_time, 1.0))
	if state_time >= stagger_time:
		_begin_chase()
		think_timer = 0.3


func _state_return(delta: float) -> void:
	if can_aggro and _target_valid() and _dist_to_target() < aggro_range * 0.7 \
			and global_position.distance_to(home_position) < leash_range * 0.8:
		_begin_chase()
		return
	var to := home_position - global_position
	to.y = 0.0
	if to.length() < 0.5:
		_brake(delta, 20.0)
		rotation.y = lerp_angle(rotation.y, home_yaw, 1.0 - exp(-5.0 * delta))
		set_health_full()
		_set_state(State.IDLE)
		return
	face_towards(to, delta, turn_speed)
	var desired := to.normalized() * move_speed
	velocity.x = desired.x
	velocity.z = desired.z
	rig.pose_idle(delta, move_speed)


func _state_dead() -> void:
	rig.pose_dead(state_time / 0.8)
	if state_time > 3.0 and visible:
		visible = false


func _brake(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func receive_attack(attack: AttackData, attacker: Node3D) -> int:
	if is_dead:
		return HitResult.IGNORED
	take_damage(attack.damage)
	rig.flash_hit()
	if is_dead:
		return HitResult.HIT
	if attacker is Player:
		target = attacker
	if state == State.IDLE or state == State.RETURN:
		_begin_chase()
	poise -= attack.poise_damage
	if poise <= 0.0:
		poise = max_poise
		var push := global_position - attacker.global_position
		push.y = 0.0
		knock = push.normalized() * attack.knockback
		_set_state(State.STAGGER)
	return HitResult.HIT


func die() -> void:
	super.die()
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	collision.set_deferred("disabled", true)
	GameState.add_ash(ash_reward)
	defeated.emit(self)


## チェックポイントで休息した時・死亡して復活した時に呼ばれる
func reset_enemy() -> void:
	global_position = home_position
	rotation = Vector3(0, home_yaw, 0)
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	set_health_full()
	poise = max_poise
	cooldowns.clear()
	visible = true
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	collision.set_deferred("disabled", false)
	rig.reset_pose()
	_set_state(State.IDLE)
