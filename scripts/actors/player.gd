class_name Player
extends Actor
## プレイヤー。状態機械で「自由移動 / 攻撃 / 回避 / 被弾 / 回復 / 死亡」を管理する。
## 行動はすべて request_action() を通るので、入力・テストのどちらからでも同じ挙動になる。

signal stamina_changed(current: float, max_value: float)
signal lock_target_changed(target: Node3D)
signal guarded
signal healed

enum State { FREE, ATTACK, DODGE, STAGGER, HEAL, DEAD }

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.8
const GUARD_SPEED := 2.0
const ACCEL := 32.0
const AIR_ACCEL := 6.0
const JUMP_VELOCITY := 5.6
const JUMP_COST := 12.0
const DODGE_SPEED := 8.5
const DODGE_TIME := 0.6
## 回避の無敵時間（開始からの秒数）
const IFRAME_START := 0.03
const IFRAME_END := 0.4
const DODGE_COST := 18.0
const SPRINT_COST := 14.0
const STAMINA_REGEN := 40.0
const REGEN_DELAY := 0.6
const EXHAUST_DELAY := 1.3
const GUARD_REGEN_MULT := 0.4
## ガード成功時に受けるダメージの割合と、ダメージ1あたりのスタミナ消費
const GUARD_CHIP := 0.15
const GUARD_STAMINA_MULT := 0.9
const HEAL_TIME := 1.1
const HEAL_APPLY_AT := 0.6
const BUFFER_TIME := 0.35
const TAP_THRESHOLD := 0.25
const LOCK_RANGE := 20.0
const LOCK_BREAK_RANGE := 28.0
const KILL_HEIGHT := -25.0

var max_stamina := 100.0
var stamina := 100.0
var attack_power := 1.0
var damage_taken_mult := 1.0
var state := State.FREE
var state_time := 0.0
var current_attack: AttackData
var attack_phase := 0
var combo_index := 0
var hit_list: Array = []
var light_combo: Array[AttackData] = []
var heavy_attack: AttackData
var buffered := ""
var buffer_timer := 0.0
var guarding := false
var guard_input := false
var invulnerable := false
var sprinting := false
var regen_timer := 0.0
var dodge_held := false
var dodge_held_time := 0.0
var dodge_dir := Vector3.FORWARD
var stagger_duration := 0.4
var knock := Vector3.ZERO
var heal_applied := false
var camera_rig: CameraRig
var lock_target: Enemy
var last_safe_position := Vector3.ZERO
var input_enabled := true
## テスト用の移動入力上書き
var use_move_override := false
var move_override := Vector2.ZERO


func _ready() -> void:
	team = 0
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	hit_mask = LAYER_ENEMY
	max_health = 300.0
	add_to_group("player")
	make_capsule_collision(0.35, 1.8)
	rig = CharacterRig.new()
	add_child(rig)
	rig.build({
		"height": 1.8, "radius": 0.35,
		"body_color": Color(0.32, 0.3, 0.36),
		"weapon_color": Color(0.78, 0.78, 0.82),
		"weapon_length": 1.0, "eye_color": Color(0.6, 0.8, 1.0), "eye_energy": 0.6,
		"shield": true,
	})
	_define_attacks()
	set_health_full()
	stamina = max_stamina
	last_safe_position = global_position


func _define_attacks() -> void:
	light_combo = [
		AttackData.create({
			"id": "light1", "damage": 28.0, "poise_damage": 12.0, "stamina_cost": 14.0,
			"windup": 0.2, "active": 0.12, "recovery": 0.38, "cancel_after": 0.12,
			"hit_radius": 0.85, "hit_offset_start": Vector3(0.9, 1.1, -0.7),
			"hit_offset_end": Vector3(-0.9, 1.1, -0.7), "lunge_speed": 2.5, "anim": "slash_r",
		}),
		AttackData.create({
			"id": "light2", "damage": 30.0, "poise_damage": 12.0, "stamina_cost": 14.0,
			"windup": 0.18, "active": 0.12, "recovery": 0.38, "cancel_after": 0.12,
			"hit_radius": 0.85, "hit_offset_start": Vector3(-0.9, 1.1, -0.7),
			"hit_offset_end": Vector3(0.9, 1.1, -0.7), "lunge_speed": 2.5, "anim": "slash_l",
		}),
		AttackData.create({
			"id": "light3", "damage": 38.0, "poise_damage": 18.0, "stamina_cost": 16.0,
			"windup": 0.26, "active": 0.14, "recovery": 0.5, "cancel_after": 0.2,
			"hit_radius": 0.7, "hit_offset_start": Vector3(0, 1.1, -0.6),
			"hit_offset_end": Vector3(0, 1.1, -1.7), "lunge_speed": 5.0, "anim": "thrust",
		}),
	]
	heavy_attack = AttackData.create({
		"id": "heavy", "damage": 62.0, "poise_damage": 35.0, "stamina_cost": 28.0,
		"windup": 0.5, "active": 0.15, "recovery": 0.6, "cancel_after": 0.3,
		"hit_radius": 1.0, "hit_offset_start": Vector3(0, 1.8, -0.8),
		"hit_offset_end": Vector3(0, 0.6, -1.5), "lunge_speed": 2.0, "anim": "overhead",
	})


# ---------------------------------------------------------------- 入力

func _read_input(delta: float) -> void:
	if Input.is_action_just_pressed("dodge"):
		dodge_held = true
		dodge_held_time = 0.0
	if dodge_held:
		dodge_held_time += delta
		if not Input.is_action_pressed("dodge"):
			if dodge_held_time < TAP_THRESHOLD:
				request_action("dodge")
			dodge_held = false
	sprinting = dodge_held and dodge_held_time >= TAP_THRESHOLD and stamina > 0.0 \
		and _move_vector().length() > 0.1
	if Input.is_action_just_pressed("attack_light"):
		request_action("heavy" if Input.is_key_pressed(KEY_SHIFT) else "light")
	if Input.is_action_just_pressed("attack_heavy"):
		request_action("heavy")
	if Input.is_action_just_pressed("jump"):
		request_action("jump")
	if Input.is_action_just_pressed("use_item"):
		request_action("heal")
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock_on()
	guard_input = Input.is_action_pressed("guard")


## 行動を先行入力として登録する（"light" "heavy" "dodge" "jump" "heal"）
func request_action(action: String) -> void:
	buffered = action
	buffer_timer = BUFFER_TIME


func _move_vector() -> Vector3:
	var v2 := move_override if use_move_override \
		else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fwd := camera_rig.flat_forward() if camera_rig else Vector3.FORWARD
	var right := camera_rig.flat_right() if camera_rig else Vector3.RIGHT
	return (right * v2.x - fwd * v2.y).limit_length(1.0)


# ---------------------------------------------------------------- メインループ

func _physics_process(delta: float) -> void:
	state_time += delta
	if buffer_timer > 0.0:
		buffer_timer -= delta
		if buffer_timer <= 0.0:
			buffered = ""
	if input_enabled and state != State.DEAD:
		_read_input(delta)
	_update_lock()

	match state:
		State.FREE:
			_state_free(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DODGE:
			_state_dodge()
		State.STAGGER:
			_state_stagger(delta)
		State.HEAL:
			_state_heal(delta)
		State.DEAD:
			_state_dead()

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_update_stamina(delta)

	if is_on_floor() and state == State.FREE:
		last_safe_position = global_position
	if global_position.y < KILL_HEIGHT and not is_dead:
		take_damage(max_health * 10.0)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	invulnerable = false
	if s != State.FREE:
		guarding = false
		sprinting = false


func _state_free(delta: float) -> void:
	var move := _move_vector()
	guarding = guard_input and is_on_floor()
	var speed := WALK_SPEED
	if guarding:
		speed = GUARD_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	var target_vel := move * speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	if lock_target and not sprinting:
		face_towards(lock_target.global_position - global_position, delta, 14.0)
	elif move.length() > 0.1:
		face_towards(move, delta, 12.0)
	rig.pose_idle(delta, Vector2(velocity.x, velocity.z).length(), guarding)

	if buffered != "":
		_try_start(buffered, true)


## 行動の開始を試みる。成功したら先行入力を消す
func _try_start(action: String, from_free: bool) -> bool:
	var ok := false
	match action:
		"light":
			if stamina > 0.0 and is_on_floor():
				if from_free:
					combo_index = 0
				_start_attack(light_combo[combo_index])
				ok = true
		"heavy":
			if stamina > 0.0 and is_on_floor():
				_start_attack(heavy_attack)
				ok = true
		"dodge":
			if stamina > 0.0 and is_on_floor():
				_start_dodge()
				ok = true
		"jump":
			if stamina > 0.0 and is_on_floor() and from_free:
				velocity.y = JUMP_VELOCITY
				_spend(JUMP_COST)
				ok = true
		"heal":
			if is_on_floor():
				if GameState.use_flask():
					_set_state(State.HEAL)
					heal_applied = false
				else:
					GameState.notify.emit("回復薬が残っていない")
				ok = true
	if ok:
		buffered = ""
		buffer_timer = 0.0
	return ok


func _start_attack(attack: AttackData) -> void:
	_set_state(State.ATTACK)
	current_attack = attack
	attack_phase = 0
	hit_list.clear()
	_spend(attack.stamina_cost)
	var move := _move_vector()
	if lock_target:
		face_instantly(lock_target.global_position - global_position)
	elif move.length() > 0.1:
		face_instantly(move)
	velocity.x = 0.0
	velocity.z = 0.0


func _state_attack(delta: float) -> void:
	var a := current_attack
	var t := state_time
	var tt := 0.0
	if t < a.windup:
		attack_phase = 0
		tt = t / a.windup
		if lock_target:
			face_towards(lock_target.global_position - global_position, delta, 10.0)
		_brake(delta, 20.0)
	elif t < a.windup + a.active:
		attack_phase = 1
		tt = (t - a.windup) / a.active
		var fwd := forward_dir()
		velocity.x = fwd.x * a.lunge_speed
		velocity.z = fwd.z * a.lunge_speed
		run_hit_query(a, tt, hit_list, attack_power)
	else:
		attack_phase = 2
		var rt := t - a.windup - a.active
		tt = rt / a.recovery
		_brake(delta, 20.0)
		if rt >= a.cancel_after and buffered != "":
			var next := buffered
			if next == "light":
				combo_index = (combo_index + 1) % light_combo.size() \
					if a in light_combo else 0
				if _try_start("light", false):
					return
			elif _try_start(next, false):
				return
		if tt >= 1.0:
			_set_state(State.FREE)
			return
	rig.pose_attack(a.anim, attack_phase, tt)


func _start_dodge() -> void:
	_set_state(State.DODGE)
	_spend(DODGE_COST)
	var move := _move_vector()
	dodge_dir = move.normalized() if move.length() > 0.1 else forward_dir()
	face_instantly(dodge_dir)


func _state_dodge() -> void:
	var t := state_time / DODGE_TIME
	invulnerable = state_time >= IFRAME_START and state_time <= IFRAME_END
	var speed := DODGE_SPEED * (1.0 - t * t)
	velocity.x = dodge_dir.x * speed
	velocity.z = dodge_dir.z * speed
	rig.pose_roll(minf(t, 1.0))
	if t >= 1.0:
		rig.reset_pose()
		_set_state(State.FREE)


func _enter_stagger(duration: float, push: Vector3) -> void:
	_set_state(State.STAGGER)
	stagger_duration = duration
	knock = push


func _state_stagger(delta: float) -> void:
	knock = knock.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.x = knock.x
	velocity.z = knock.z
	rig.pose_stagger(minf(state_time / stagger_duration, 1.0))
	if state_time >= stagger_duration:
		_set_state(State.FREE)


func _state_heal(delta: float) -> void:
	var move := _move_vector() * WALK_SPEED * 0.35
	velocity.x = move_toward(velocity.x, move.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, move.z, ACCEL * delta)
	rig.pose_idle(delta, 0.0, true)
	if not heal_applied and state_time >= HEAL_APPLY_AT:
		heal_applied = true
		health = minf(health + GameState.FLASK_HEAL, max_health)
		health_changed.emit(health, max_health)
		healed.emit()
	if state_time >= HEAL_TIME:
		_set_state(State.FREE)


func _state_dead() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	rig.pose_dead(state_time / 0.8)


func _brake(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


# ---------------------------------------------------------------- スタミナ

func _spend(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	regen_timer = EXHAUST_DELAY if stamina <= 0.0 else REGEN_DELAY
	stamina_changed.emit(stamina, max_stamina)


func _update_stamina(delta: float) -> void:
	var before := stamina
	if sprinting and state == State.FREE and Vector2(velocity.x, velocity.z).length() > 0.5:
		stamina = maxf(stamina - SPRINT_COST * delta, 0.0)
		regen_timer = EXHAUST_DELAY if stamina <= 0.0 else REGEN_DELAY * 0.5
	elif regen_timer > 0.0:
		regen_timer -= delta
	elif state == State.FREE or state == State.HEAL or state == State.STAGGER:
		var rate := STAMINA_REGEN * (GUARD_REGEN_MULT if guarding else 1.0)
		stamina = minf(stamina + rate * delta, max_stamina)
	if not is_equal_approx(before, stamina):
		stamina_changed.emit(stamina, max_stamina)


# ---------------------------------------------------------------- 被弾

func receive_attack(attack: AttackData, attacker: Node3D) -> int:
	if is_dead:
		return HitResult.IGNORED
	if invulnerable:
		return HitResult.DODGED
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0.0
	var push := -to_attacker.normalized() * attack.knockback
	var facing := forward_dir().dot(to_attacker.normalized()) > 0.2
	if guarding and state == State.FREE and facing and not attack.unblockable:
		var cost := attack.damage * GUARD_STAMINA_MULT
		if stamina >= cost:
			_spend(cost)
			take_damage(attack.damage * GUARD_CHIP * damage_taken_mult)
			knock = push * 0.4
			velocity.x = knock.x
			velocity.z = knock.z
			guarded.emit()
			return HitResult.BLOCKED
		# ガードブレイク: スタミナが足りないと崩されて大きく怯む
		_spend(stamina)
		take_damage(attack.damage * 0.6 * damage_taken_mult)
		rig.flash_hit()
		if not is_dead:
			_enter_stagger(1.0, push)
		return HitResult.HIT
	take_damage(attack.damage * damage_taken_mult)
	rig.flash_hit()
	if not is_dead:
		_enter_stagger(attack.hitstun, push)
	return HitResult.HIT


func die() -> void:
	_set_state(State.DEAD)
	set_lock(null)
	super.die()


func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	set_health_full()
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)
	buffered = ""
	_set_state(State.FREE)
	rig.reset_pose()
	set_lock(null)
	last_safe_position = pos
	if camera_rig:
		camera_rig.yaw = yaw
		camera_rig.snap_to_target()


# ---------------------------------------------------------------- ロックオン

func toggle_lock_on() -> void:
	if lock_target:
		set_lock(null)
		return
	var cam_fwd := camera_rig.flat_forward() if camera_rig else forward_dir()
	var best: Enemy = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.is_dead or not e.visible:
			continue
		var to := e.global_position - global_position
		var d := to.length()
		if d > LOCK_RANGE:
			continue
		var flat := Vector3(to.x, 0, to.z)
		var ang := cam_fwd.angle_to(flat.normalized()) if flat.length() > 0.01 else 0.0
		if ang > 1.4 and d > 4.0:
			continue
		var score := ang * 6.0 + d * 0.2
		if score < best_score:
			best_score = score
			best = e
	set_lock(best)


func set_lock(t: Enemy) -> void:
	lock_target = t
	if camera_rig:
		camera_rig.lock_target = t
	lock_target_changed.emit(t)


func _update_lock() -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or lock_target.is_dead \
			or lock_target.global_position.distance_to(global_position) > LOCK_BREAK_RANGE:
		set_lock(null)
