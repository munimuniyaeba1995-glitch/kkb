extends Node
## 実描画でスクリーンショットを撮る（tools/screenshot.sh から実行）。
## 出力: tests/output/*.png

const MAIN_SCENE := preload("res://scenes/main.tscn")


func _ready() -> void:
	GameSettings.persist = false
	DirAccess.make_dir_recursive_absolute("res://tests/output")
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await _wait(1.0)
	await _shot("01_start")
	# 画質ごとの描画負荷（同じ視点で比較）
	for q in [2, 1, 0]:
		GameSettings.set_quality(q)
		await _wait(0.5)
		await RenderingServer.frame_post_draw
		print("perf quality=%s draw_calls=%d objects=%d primitives=%d vram=%.0fMB" % [
			GameSettings.QUALITY_NAMES[q],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	GameSettings.set_quality(1 if GameSettings.touch_controls else 2)

	# 強敵の予備動作（赤く光る）を正面から
	var elite: Enemy = null
	for e: Enemy in main.level.enemies:
		if e is Elite:
			elite = e
	var p: Player = main.player
	p.input_enabled = false
	p.max_health = 99999.0
	p.set_health_full()
	p.global_position = elite.global_position + Vector3(0, 0, 3.2)
	p.face_instantly(elite.global_position - p.global_position)
	main.camera_rig.yaw = p.rotation.y + 0.5
	p.toggle_lock_on()
	main.camera_rig.snap_to_target()
	for i in 600:
		await get_tree().physics_frame
		if elite.state == Enemy.State.ATTACK and elite.attack_phase == 0 and elite.state_time > 0.35:
			break
	await _shot("02_elite_windup")

	# ボス戦
	p.set_lock(null)
	var arena: BossArena = main.level.arena
	p.global_position = arena.global_position + Vector3(0, 0.2, 12)
	p.face_instantly(Vector3.FORWARD)
	main.camera_rig.yaw = 0.0
	main.camera_rig.snap_to_target()
	await _wait(0.3)
	p.toggle_lock_on()
	await _wait(2.5)
	await _shot("03_boss")

	# 死亡画面
	p.take_damage(999999.0)
	await _wait(2.0)
	await _shot("04_death")
	get_tree().quit()


func _wait(s: float) -> void:
	for i in int(s * 60):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var prefix := "touch_" if GameSettings.touch_controls else ""
	img.save_png("res://tests/output/%s%s.png" % [prefix, name])
	print("saved ", name)
