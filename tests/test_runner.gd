extends Node
## ヘッドレス自動テスト。本編シーンを毎回作り直し、実際の物理・当たり判定で検証する。
## 実行: tools/run_tests.sh（Windows: tools\run_tests.bat）

const MAIN_SCENE := preload("res://scenes/main.tscn")

var main: Node
var failures: Array[String] = []
var passed := 0
var current := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tests := [
		"test_boot",
		"test_player_light_attack_hits_grunt",
		"test_light_combo_chains",
		"test_grunt_attacks_player",
		"test_dodge_iframes",
		"test_dodge_through_real_attack",
		"test_guard_blocks",
		"test_guard_break",
		"test_stamina_gates_actions",
		"test_kill_grunt_gives_ash",
		"test_lock_on",
		"test_heal_flask",
		"test_elite_combo_and_ranges",
		"test_boss_attack_by_distance",
		"test_boss_fight_flow",
		"test_boss_phase_two",
		"test_death_drop_and_recover",
		"test_second_death_loses_drop",
		"test_checkpoint_rest_resets_enemies",
		"test_secret_wall_and_chest",
		"test_fall_death",
		"test_pause_toggle",
	]
	for t: String in tests:
		current = t
		await _setup()
		var before := failures.size()
		await call(t)
		if failures.size() == before:
			passed += 1
			print("  PASS  ", t)
		else:
			print("  FAIL  ", t)
		await _teardown()
	print("")
	print("結果: %d / %d PASS" % [passed, tests.size()])
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _setup() -> void:
	get_tree().paused = false
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await frames(3)


func _teardown() -> void:
	get_tree().paused = false
	main.queue_free()
	await frames(2)


# ---------------------------------------------------------------- ヘルパー

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(ceil(s * 60.0)))


func player() -> Player:
	return main.player


func first(cls: Script) -> Enemy:
	for e: Enemy in main.level.enemies:
		if is_instance_of(e, cls):
			return e
	return null


## 指定した敵以外のAIを止める
func isolate(keep: Array) -> void:
	for e: Enemy in main.level.enemies:
		if not keep.has(e):
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.visible = false
			e.collision_layer = 0


## プレイヤーを敵の正面 dist の位置に置き、互いに向き合わせる
func face_off(e: Enemy, dist: float, at: Vector3 = Vector3(0, 0.1, 5)) -> void:
	e.place(at, 0.0)
	var p := player()
	p.global_position = at + Vector3(0, 0, -dist)
	p.face_instantly(e.global_position - p.global_position)
	e.face_instantly(p.global_position - e.global_position)
	p.velocity = Vector3.ZERO
	main.camera_rig.snap_to_target()
	# 着地を待つ（空中では攻撃・回避・ガードできない）
	for i in 30:
		await get_tree().physics_frame
		if p.is_on_floor():
			break


# ---------------------------------------------------------------- テスト

func test_boot() -> void:
	check(player() != null, "プレイヤーが生成されていない")
	check(main.level.enemies.size() == 8, "敵の数が足りない: %d" % main.level.enemies.size())
	check(main.level.checkpoints.size() == 2, "篝火が2つない")
	await seconds(0.5)
	check(player().is_on_floor(), "プレイヤーが床に立っていない")
	check(player().global_position.y > -1.0, "プレイヤーが落下した")
	for e: Enemy in main.level.enemies:
		check(e.global_position.y > -1.0, "%s が床を抜けた" % e.display_name)


func test_player_light_attack_hits_grunt() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	await face_off(g, 1.6)
	await frames(2)
	player().request_action("light")
	await seconds(0.5)
	check(g.health < g.max_health, "弱攻撃が当たっていない (HP %.0f)" % g.health)
	check(is_equal_approx(g.health, g.max_health - 28.0), "ダメージ量が想定外: %.1f" % g.health)


func test_light_combo_chains() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	g.max_health = 9999.0
	g.set_health_full()
	await face_off(g, 1.6)
	await frames(2)
	var seen := {}
	for i in 100:
		if player().state != Player.State.ATTACK or player().attack_phase == 2:
			player().request_action("light")
		if player().state == Player.State.ATTACK:
			seen[player().current_attack.id] = true
		await frames(1)
	check(seen.has("light1") and seen.has("light2") and seen.has("light3"),
		"3連撃にならない: %s" % str(seen.keys()))
	check(g.health <= g.max_health - 28.0 - 30.0 - 38.0 + 0.1, "3連撃のダメージ不足: %.0f" % g.health)


func test_grunt_attacks_player() -> void:
	var g := first(Grunt)
	isolate([g])
	await face_off(g, 1.5)
	player().input_enabled = false
	var hp := player().health
	var saw_windup := false
	for i in 240:
		await frames(1)
		if g.state == Enemy.State.ATTACK and g.attack_phase == 0:
			saw_windup = true
		if player().health < hp:
			break
	check(saw_windup, "雑魚が予備動作に入らない")
	check(player().health < hp, "雑魚の攻撃が当たらない")


func test_dodge_iframes() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	await face_off(g, 1.5)
	player().input_enabled = false
	player().request_action("dodge")
	await frames(6)
	check(player().state == Player.State.DODGE, "回避が始まらない")
	check(player().invulnerable, "回避中に無敵になっていない")
	var r := player().receive_attack(g.attacks["slash"], g)
	check(r == Actor.HitResult.DODGED, "無敵中に被弾した")
	check(is_equal_approx(player().health, player().max_health), "無敵中にHPが減った")
	await seconds(0.7)
	check(player().state == Player.State.FREE, "回避後に自由状態へ戻らない")
	check(not player().invulnerable, "回避後も無敵のまま")


## 実際の敵の攻撃を、予備動作を見てから回避して無傷でいられるか
func test_dodge_through_real_attack() -> void:
	var g := first(Grunt)
	isolate([g])
	await face_off(g, 1.5)
	player().input_enabled = false
	g.think_timer = 0.0
	var dodged := false
	for i in 240:
		await frames(1)
		# 予備動作の残り0.15秒で回避（＝見てから避ける）
		if not dodged and g.state == Enemy.State.ATTACK and g.attack_phase == 0 \
				and g.state_time > g.current_attack.windup - 0.15:
			player().request_action("dodge")
			dodged = true
		if dodged and g.state != Enemy.State.ATTACK:
			break
	check(dodged, "攻撃が来なかった")
	check(is_equal_approx(player().health, player().max_health), "予備動作を見て回避したのに被弾した")


func test_guard_blocks() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	await face_off(g, 1.5)
	player().input_enabled = false
	player().guard_input = true
	await frames(2)
	check(player().guarding, "ガード状態にならない")
	var st := player().stamina
	var r := player().receive_attack(g.attacks["slash"], g)
	check(r == Actor.HitResult.BLOCKED, "ガードできない")
	check(is_equal_approx(player().health, player().max_health - 30.0 * Player.GUARD_CHIP), "削りダメージが想定外")
	check(player().stamina < st, "ガードでスタミナが減らない")


func test_guard_break() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	await face_off(g, 1.5)
	player().input_enabled = false
	player().guard_input = true
	await frames(2)
	player().stamina = 5.0
	var r := player().receive_attack(g.attacks["slash"], g)
	check(r == Actor.HitResult.HIT, "スタミナ不足でもガードできてしまう")
	check(player().state == Player.State.STAGGER, "ガードブレイクで怯まない")


func test_stamina_gates_actions() -> void:
	isolate([])
	player().input_enabled = false
	player().stamina = 0.0
	player().regen_timer = 5.0
	player().request_action("light")
	await frames(3)
	check(player().state == Player.State.FREE, "スタミナ0で攻撃できてしまう")
	player().request_action("dodge")
	await frames(3)
	check(player().state == Player.State.FREE, "スタミナ0で回避できてしまう")
	# 先行入力が残っていると回復した瞬間に回避が出る（仕様）ので消してから確認
	player().buffered = ""
	player().regen_timer = 0.0
	await seconds(1.0)
	check(player().stamina > 30.0, "スタミナが回復しない: %.1f" % player().stamina)


func test_kill_grunt_gives_ash() -> void:
	var g := first(Grunt)
	isolate([g])
	g.set_physics_process(false)
	await face_off(g, 1.6)
	g.health = 10.0
	await frames(2)
	player().request_action("light")
	await seconds(0.6)
	check(g.is_dead, "HP0で撃破扱いにならない")
	check(GameState.ash == g.ash_reward, "残灰が入らない: %d" % GameState.ash)
	check(g.collision_layer == 0, "撃破後も当たり判定が残っている")


func test_lock_on() -> void:
	var e := first(Elite)
	isolate([e])
	e.set_physics_process(false)
	await face_off(e, 6.0)
	main.camera_rig.yaw = player().rotation.y
	player().toggle_lock_on()
	check(player().lock_target == e, "ロックオンできない")
	await seconds(0.5)
	var to_e: Vector3 = e.global_position - player().global_position
	check(main.camera_rig.flat_forward().angle_to(Vector3(to_e.x, 0, to_e.z).normalized()) < 0.2,
		"カメラがロック対象を向かない")
	player().toggle_lock_on()
	check(player().lock_target == null, "ロック解除できない")


func test_heal_flask() -> void:
	isolate([])
	player().input_enabled = false
	player().take_damage(200.0)
	var flasks := GameState.flasks
	player().request_action("heal")
	await seconds(1.3)
	check(GameState.flasks == flasks - 1, "回復薬が減らない")
	check(player().health > 100.0 + 100.0, "HPが回復しない: %.0f" % player().health)


func test_elite_combo_and_ranges() -> void:
	var e := first(Elite)
	isolate([e])
	await face_off(e, 2.0)
	player().input_enabled = false
	player().max_health = 99999.0
	player().set_health_full()
	var seen := {}
	for i in 60 * 12:
		await frames(1)
		if e.state == Enemy.State.ATTACK:
			seen[e.current_attack.id] = true
	check(seen.size() >= 3, "強敵の攻撃パターンが少ない: %s" % str(seen.keys()))
	check(seen.has("combo2"), "強敵がコンボをつながない: %s" % str(seen.keys()))


func test_boss_attack_by_distance() -> void:
	var b: Boss = main.level.boss
	isolate([b])
	b.target = player()
	player().global_position = b.global_position + b.forward_dir() * 15.0
	var far := b.choose_attack(15.0)
	check(far != null and far.id == "leap", "遠距離で跳躍攻撃を選ばない")
	b.cooldowns.clear()
	player().global_position = b.global_position + b.forward_dir() * 3.0
	var ids := {}
	for i in 30:
		var a := b.choose_attack(3.0)
		if a:
			ids[a.id] = true
	check(not ids.has("leap"), "近距離で跳躍攻撃を選んだ")
	check(ids.has("sweep") and ids.has("stomp"), "近距離技のバリエーション不足: %s" % str(ids.keys()))


func test_boss_fight_flow() -> void:
	var b: Boss = main.level.boss
	isolate([b])
	var arena: BossArena = main.level.arena
	check(not arena.active, "最初からボス戦が始まっている")
	player().global_position = arena.global_position + Vector3(0, 0.2, 14)
	player().input_enabled = false
	await frames(3)
	check(arena.active, "ボス部屋に入ってもボス戦が始まらない")
	check(not arena.fog_col.disabled, "霧の壁が閉じない")
	check(main.hud.boss_box.visible, "ボスHPゲージが表示されない")
	check(b.engaged, "ボスが起動しない")
	var hp := player().health
	for i in 60 * 10:
		await frames(1)
		if player().health < hp:
			break
	check(player().health < hp, "ボスの攻撃が当たらない")
	# 撃破
	player().respawn(b.global_position + b.forward_dir() * 3.0, 0)
	player().face_instantly(b.global_position - player().global_position)
	b.health = 20.0
	b.set_physics_process(false)
	await frames(10)
	player().request_action("heavy")
	await seconds(0.9)
	check(b.is_dead, "ボスを倒せない（HP %.0f）" % b.health)
	check(GameState.boss_defeated, "ボス撃破が記録されない")
	check(not arena.active and arena.fog_col.disabled, "撃破後に霧の壁が開かない")
	check(not main.hud.boss_box.visible, "撃破後もボスゲージが残る")


func test_boss_phase_two() -> void:
	var b: Boss = main.level.boss
	isolate([b])
	check(b.phase == 1, "初期フェーズが1でない")
	b.take_damage(b.max_health * 0.55)
	check(b.phase == 2, "HP半分で第2形態にならない")
	check(b.windup_mult < 1.0, "第2形態で予備動作が短くならない")
	b.reset_enemy()
	check(b.phase == 1 and is_equal_approx(b.health, b.max_health), "再配置でボスが戻らない")


func test_death_drop_and_recover() -> void:
	isolate([])
	GameState.add_ash(500)
	var death_pos := Vector3(5, 0.1, -5)
	player().global_position = death_pos
	await frames(3)
	player().take_damage(9999.0)
	check(player().is_dead and player().state == Player.State.DEAD, "HP0で死亡しない")
	check(GameState.ash == 0 and GameState.dropped_ash == 500, "残灰がドロップされない")
	main.respawn()
	await frames(2)
	check(not player().is_dead and is_equal_approx(player().health, player().max_health), "復活しない")
	check(player().global_position.distance_to(GameState.respawn_position) < 0.5, "篝火の位置に戻らない")
	check(main.ash_drop != null, "残灰のドロップ物が出ない")
	player().global_position = main.ash_drop.global_position
	await frames(3)
	check(GameState.ash == 500 and not GameState.has_dropped_ash, "ドロップを回収できない")


func test_second_death_loses_drop() -> void:
	isolate([])
	GameState.add_ash(300)
	player().global_position = Vector3(6, 0.1, -8)
	await frames(10)
	player().take_damage(9999.0)
	main.respawn()
	await frames(2)
	GameState.add_ash(40)
	player().global_position = Vector3(-6, 0.1, 6)
	await frames(10)
	player().take_damage(9999.0)
	check(GameState.dropped_ash == 40, "2回目の死亡で前回分が消えていない: %d" % GameState.dropped_ash)
	main.respawn()
	await frames(2)
	check(GameState.has_dropped_ash and GameState.ash == 0, "2回目のドロップ状態が不正")


func test_checkpoint_rest_resets_enemies() -> void:
	var g := first(Grunt)
	g.take_damage(9999.0)
	check(g.is_dead, "前提: 雑魚が倒れていない")
	player().take_damage(100.0)
	GameState.use_flask()
	var cp: Checkpoint = main.level.checkpoints[0]
	player().global_position = cp.global_position + Vector3(0, 0.1, -1.5)
	await frames(2)
	cp.interact(player())
	await frames(2)
	check(not g.is_dead and g.visible, "休息しても敵が復活しない")
	check(g.global_position.distance_to(g.home_position) < 0.5, "敵が初期位置に戻らない")
	check(is_equal_approx(player().health, player().max_health), "休息でHPが回復しない")
	check(GameState.flasks == GameState.flask_max, "休息で回復薬が補充されない")


func test_secret_wall_and_chest() -> void:
	isolate([])
	var wall: SecretWall = null
	for c in main.level.get_children():
		if c is SecretWall:
			wall = c
	check(wall != null, "隠し壁がない")
	player().global_position = Vector3(-18.4, 0.1, 0)
	player().face_instantly(Vector3.LEFT)
	await frames(2)
	player().request_action("light")
	await seconds(0.6)
	check(GameState.is_claimed("forecourt_secret_wall"), "攻撃しても隠し壁が壊れない")
	await seconds(0.6)
	check(not is_instance_valid(wall), "隠し壁が消えない")
	# 奥の宝箱
	var chest: Chest = null
	for c in main.level.get_children():
		if c is Chest and c.chest_id == "forecourt_hidden_chest":
			chest = c
	player().global_position = chest.global_position + Vector3(1.2, 0.1, 0)
	await frames(3)
	check(chest.can_interact(player()), "宝箱を開けられない")
	var ash := GameState.ash
	chest.interact(player())
	check(GameState.ash == ash + 800, "宝箱の中身が入らない")
	check(not chest.can_interact(player()), "宝箱を2回開けられる")


func test_fall_death() -> void:
	isolate([])
	player().global_position = Vector3(0, -30, 0)
	await frames(2)
	check(player().is_dead, "落下しても死なない")


func test_pause_toggle() -> void:
	isolate([])
	main.set_paused(true)
	check(get_tree().paused and main.hud.pause_panel.visible, "ポーズできない")
	main.set_paused(false)
	check(not get_tree().paused and not main.hud.pause_panel.visible, "ポーズ解除できない")
