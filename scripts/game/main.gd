extends Node3D
## ゲーム本編のまとめ役。レベル・プレイヤー・カメラ・HUDを生成し、
## 死亡→復活、休息→敵の再配置、ボス戦の開始/終了、ポーズ、調べる操作をつなぐ。

const RESPAWN_DELAY := 3.5

var level: LevelRuins
var player: Player
var camera_rig: CameraRig
var hud: HUD
var touch: TouchControls
var ash_drop: AshDrop
var death_timer := -1.0


func _ready() -> void:
	level = LevelRuins.new()
	add_child(level)
	level.build()
	GameState.new_game(level.spawn_position, level.spawn_yaw)

	player = Player.new()
	add_child(player)
	player.global_position = level.spawn_position
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.target = player
	player.camera_rig = camera_rig
	camera_rig.snap_to_target()

	hud = HUD.new()
	add_child(hud)
	hud.setup(player)
	hud.resume_pressed.connect(set_paused.bind(false))
	hud.title_pressed.connect(_go_to_title)
	hud.pause_toggle_requested.connect(func() -> void: set_paused(not get_tree().paused))

	for cp in level.checkpoints:
		cp.rested.connect(_on_rested)
	level.arena.player = player
	level.arena.battle_started.connect(hud.show_boss)
	level.arena.battle_ended.connect(func(_v: bool) -> void: hud.hide_boss())
	level.boss.defeated.connect(_on_boss_defeated)
	level.boss.phase_changed.connect(
		func(_p: int) -> void: hud.notify("守護者の王冠が燃え上がる——動きが激しくなった"))
	player.died.connect(_on_player_died)
	player.hit_landed.connect(_on_player_hit_landed)
	for e in level.enemies:
		e.hit_landed.connect(_on_enemy_hit_landed)

	# タッチ操作（スマホ。PCでも設定でON可）。HUD の一部として最前面に置く
	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(touch)
	touch.look.connect(camera_rig.add_look)
	GameSettings.changed.connect(_on_settings_changed)
	_on_settings_changed()
	hud.notify("灰降る廃都・外縁")
	hud.notify("II → 操作説明 で操作を確認" if GameSettings.touch_controls else "F1 で操作説明を表示")


func _process(delta: float) -> void:
	_update_interaction()
	if death_timer >= 0.0:
		death_timer -= delta
		if death_timer < 0.0:
			respawn()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not get_tree().paused \
			and not GameSettings.touch_controls and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	hud.set_paused(paused)
	if paused:
		touch.release_all()
	_update_mouse_mode()


## PCのマウス操作時だけカーソルを隠して固定する（タッチ操作・ポーズ中は表示）
func _update_mouse_mode() -> void:
	if get_tree().paused or GameSettings.touch_controls:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_settings_changed() -> void:
	touch.visible = GameSettings.touch_controls
	if not touch.visible:
		touch.release_all()
	GameSettings.apply_graphics(get_tree())
	_update_mouse_mode()


func _on_player_hit_landed(_target: Node3D, _result: int, attack: AttackData) -> void:
	if attack.damage >= 50.0:
		camera_rig.shake(0.06)


func _on_enemy_hit_landed(target: Node3D, result: int, attack: AttackData) -> void:
	if target == player:
		var amount := 0.1 if result == Actor.HitResult.BLOCKED else 0.18
		camera_rig.shake(amount * (1.6 if attack.damage >= 80.0 else 1.0))


func _go_to_title() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/title.tscn")


## 一番近い「調べられる物」を探してプロンプトを出し、Eで実行する
func _update_interaction() -> void:
	var nearest: Interactable = null
	if not player.is_dead and player.state == Player.State.FREE:
		var best := INF
		for node in get_tree().get_nodes_in_group("interactables"):
			var it := node as Interactable
			if it == null or not it.can_interact(player):
				continue
			var d := it.global_position.distance_to(player.global_position)
			if d < it.radius and d < best:
				best = d
				nearest = it
	hud.set_prompt(nearest.prompt if nearest else "")
	touch.set_interact_available(nearest != null)
	if nearest and Input.is_action_just_pressed("interact"):
		nearest.interact(player)


func _on_rested(cp: Checkpoint) -> void:
	GameState.set_checkpoint(cp.spawn_point(), cp.respawn_yaw)
	player.set_health_full()
	player.stamina = player.max_stamina
	player.stamina_changed.emit(player.stamina, player.max_stamina)
	GameState.refill_flasks()
	reset_world()
	hud.notify("%sで休息した。灰の亡者たちが再び立ち上がる……" % cp.checkpoint_name)


## 敵を初期位置に戻して復活させる（倒したボスは戻らない）
func reset_world() -> void:
	for e in level.enemies:
		if e is Boss and GameState.boss_defeated:
			continue
		e.reset_enemy()
	level.arena.reset_arena()
	hud.hide_boss()


func _on_player_died(_actor: Actor) -> void:
	GameState.on_player_died(player.last_safe_position)
	hud.show_big("灰 に 還 っ た", Color(0.75, 0.1, 0.08))
	death_timer = RESPAWN_DELAY


func respawn() -> void:
	death_timer = -1.0
	hud.hide_big()
	reset_world()
	GameState.refill_flasks()
	player.respawn(GameState.respawn_position, GameState.respawn_yaw)
	if ash_drop and is_instance_valid(ash_drop):
		ash_drop.queue_free()
		ash_drop = null
	if GameState.has_dropped_ash:
		ash_drop = AshDrop.new()
		ash_drop.player = player
		add_child(ash_drop)
		ash_drop.global_position = GameState.dropped_ash_position


func _on_boss_defeated(_enemy: Enemy) -> void:
	GameState.boss_defeated = true
	level.arena.end_battle(true)
	hud.hide_boss()
	hud.show_big("守 護 者 を 討 ち 果 た し た", Color(0.95, 0.75, 0.35))
	get_tree().create_timer(5.0).timeout.connect(hud.hide_big)
	hud.notify("試作版クリア！ 引き続き探索できます（Esc→タイトルへ）")
