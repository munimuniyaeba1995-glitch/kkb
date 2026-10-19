class_name HUD
extends CanvasLayer
## 画面表示一式: HP/スタミナ、ボスHP、残灰、回復薬、操作プロンプト、通知、
## 死亡・勝利の大見出し、ロックオンマーカー、ポーズメニュー、操作説明。

signal resume_pressed
signal title_pressed
## ポーズ中も HUD は動き続けるので、ポーズ操作はここで受け取る
signal pause_toggle_requested

const CONTROLS_TEXT := """移動 ………… WASD / 左スティック
カメラ ……… マウス / 右スティック（矢印キーでも可）
ダッシュ …… Space 長押し / B 長押し
回避 ………… Space 短押し / B（回避の出始めは無敵）
ジャンプ …… F / A
弱攻撃 ……… 左クリック / RB（連打で3連撃）
強攻撃 ……… Shift+左クリック または C / RT
ガード ……… 右クリック長押し / LB（スタミナで受ける）
ロックオン … Q・ホイールクリック / 右スティック押し込み
回復薬 ……… R / X
調べる・休息 E / Y
ポーズ ……… Esc / Start　　操作説明の表示切替 … F1"""

var player: Player
var hp_bar: ProgressBar
var hp_back: ProgressBar
var stamina_bar: ProgressBar
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_name: Label
var ash_label: Label
var flask_label: Label
var prompt_label: Label
var notify_label: Label
var big_label: Label
var lock_marker: ColorRect
var pause_panel: PanelContainer
var help_panel: PanelContainer
var notify_queue: Array[String] = []
var notify_time := 0.0
var boss_ref: Boss


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 左上: HP / スタミナ
	var bars := VBoxContainer.new()
	bars.position = Vector2(32, 28)
	bars.add_theme_constant_override("separation", 6)
	root.add_child(bars)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(360, 18)
	bars.add_child(hp_stack)
	hp_back = _bar(Color(0.9, 0.85, 0.6), Vector2(360, 18))
	hp_stack.add_child(hp_back)
	hp_bar = _bar(Color(0.7, 0.1, 0.1), Vector2(360, 18), true)
	hp_stack.add_child(hp_bar)
	stamina_bar = _bar(Color(0.2, 0.6, 0.25), Vector2(300, 12))
	bars.add_child(stamina_bar)

	# 左下: 回復薬
	flask_label = _label("", 22)
	flask_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flask_label.position = Vector2(32, -64)
	root.add_child(flask_label)

	# 右下: 残灰（経験値）
	ash_label = _label("", 24)
	ash_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ash_label.position = Vector2(-260, -64)
	ash_label.custom_minimum_size = Vector2(230, 0)
	ash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ash_label)

	# 下中央: ボスHP
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss_box.position = Vector2(-450, -130)
	boss_box.custom_minimum_size = Vector2(900, 0)
	boss_name = _label("", 22)
	boss_box.add_child(boss_name)
	boss_bar = _bar(Color(0.65, 0.12, 0.08), Vector2(900, 14))
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	root.add_child(boss_box)

	# 中央下: 操作プロンプト
	prompt_label = _label("", 24)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position = Vector2(-300, 150)
	prompt_label.custom_minimum_size = Vector2(600, 0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	# 上中央: 通知
	notify_label = _label("", 24)
	notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notify_label.position = Vector2(-450, 90)
	notify_label.custom_minimum_size = Vector2(900, 0)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notify_label)

	# 中央: 大見出し（死亡・勝利）
	big_label = _label("", 72)
	big_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.visible = false
	root.add_child(big_label)

	lock_marker = ColorRect.new()
	lock_marker.size = Vector2(12, 12)
	lock_marker.pivot_offset = Vector2(6, 6)
	lock_marker.rotation = PI * 0.25
	lock_marker.color = Color(1, 0.95, 0.8, 0.9)
	lock_marker.visible = false
	lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lock_marker)

	help_panel = _panel()
	var help_label := _label(CONTROLS_TEXT, 18)
	help_panel.add_child(help_label)
	help_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_panel.position = Vector2(-560, 24)
	help_panel.visible = false
	root.add_child(help_panel)

	_build_pause_menu(root)
	GameState.ash_changed.connect(_on_ash_changed)
	GameState.flasks_changed.connect(_on_flasks_changed)
	GameState.notify.connect(notify)
	_on_ash_changed(GameState.ash)
	_on_flasks_changed(GameState.flasks, GameState.flask_max)


func _build_pause_menu(root: Control) -> void:
	pause_panel = _panel()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-330, -260)
	pause_panel.custom_minimum_size = Vector2(660, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	var title := _label("ポーズ", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_label(CONTROLS_TEXT, 17))
	var resume := Button.new()
	resume.text = "再開する"
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(resume)
	var to_title := Button.new()
	to_title.text = "タイトルへ戻る"
	to_title.pressed.connect(func() -> void: title_pressed.emit())
	v.add_child(to_title)
	pause_panel.visible = false
	root.add_child(pause_panel)


func _bar(color: Color, size: Vector2, transparent_bg: bool = false) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0) if transparent_bg else Color(0.05, 0.05, 0.05, 0.75)
	bg.border_color = Color(0.5, 0.45, 0.35, 0.0 if transparent_bg else 0.8)
	bg.set_border_width_all(0 if transparent_bg else 1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.88)
	sb.border_color = Color(0.6, 0.5, 0.3)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	return p


func setup(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	_on_health_changed(player.health, player.max_health)
	_on_stamina_changed(player.stamina, player.max_stamina)


func _on_health_changed(current: float, max_value: float) -> void:
	hp_bar.max_value = max_value
	hp_back.max_value = max_value
	hp_bar.value = current
	if current > hp_back.value:
		hp_back.value = current


func _on_stamina_changed(current: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = current


func _on_ash_changed(value: int) -> void:
	ash_label.text = "残灰  %d" % value


func _on_flasks_changed(current: int, max_value: int) -> void:
	flask_label.text = "灰硝子の小瓶  %d / %d   [R]" % [current, max_value]


func show_boss(boss: Boss) -> void:
	boss_ref = boss
	boss_name.text = boss.display_name
	boss_bar.max_value = boss.max_health
	boss_bar.value = boss.health
	if not boss.health_changed.is_connected(_on_boss_health):
		boss.health_changed.connect(_on_boss_health)
	boss_box.visible = true


func hide_boss() -> void:
	boss_box.visible = false


func _on_boss_health(current: float, _max_value: float) -> void:
	boss_bar.value = current


func set_prompt(text: String) -> void:
	prompt_label.text = ("[E] " + text) if text != "" else ""


func notify(text: String) -> void:
	notify_queue.append(text)


func show_big(text: String, color: Color) -> void:
	big_label.text = text
	big_label.add_theme_color_override("font_color", color)
	big_label.modulate.a = 0.0
	big_label.visible = true
	create_tween().tween_property(big_label, "modulate:a", 1.0, 1.2)


func hide_big() -> void:
	big_label.visible = false


func set_paused(paused: bool) -> void:
	pause_panel.visible = paused


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_toggle_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_help"):
		toggle_help()


func _process(delta: float) -> void:
	# HPが減った分を遅れて縮める（被ダメージ量が見やすい）
	if hp_back.value > hp_bar.value:
		hp_back.value = maxf(hp_bar.value, hp_back.value - 120.0 * delta)
	if notify_time > 0.0:
		notify_time -= delta
		notify_label.modulate.a = clampf(notify_time, 0.0, 1.0)
	elif not notify_queue.is_empty():
		notify_label.text = notify_queue.pop_front()
		notify_time = 3.0
	else:
		notify_label.text = ""
	_update_lock_marker()


func _update_lock_marker() -> void:
	lock_marker.visible = false
	if player == null or player.lock_target == null or player.camera_rig == null:
		return
	var cam := player.camera_rig.camera
	var t := player.lock_target
	var world_pos := t.global_position + Vector3.UP * t.lock_height
	if cam.is_position_behind(world_pos):
		return
	lock_marker.position = cam.unproject_position(world_pos) - Vector2(6, 6)
	lock_marker.visible = true
