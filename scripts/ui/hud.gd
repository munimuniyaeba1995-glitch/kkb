class_name HUD
extends CanvasLayer
## 画面表示一式: HP/スタミナ、ボスHP、残灰、回復薬、操作プロンプト、通知、
## 死亡・勝利の大見出し、ロックオンマーカー、ポーズメニュー、操作説明。
## 見た目の部品と色は UITheme にまとめてある。

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

const TOUCH_HELP_TEXT := """左側をなぞる … 移動（スティックが指の位置に出る）
右側の空いた所をなぞる … カメラ
剣 … 弱攻撃（連打で3連撃）　大剣 … 強攻撃
矢印 … 回避（短く押す・出始めは無敵）／長押しでダッシュ
盾 … 押している間ガード　↑ … ジャンプ
照準 … 近くの敵にロックオン　小瓶 … 回復薬を飲む
手 … 篝火・宝箱の近くで表示（調べる）　II … ポーズ"""

## アイコンを1つ描くだけの部品
class IconView extends Control:
	var icon := "ember"
	var color := UITheme.GOLD

	func _init(i: String, c: Color, px: float) -> void:
		icon = i
		color = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		UITheme.draw_icon(self, icon, size * 0.5, minf(size.x, size.y) * 0.5, color)


## 左上の紋章（王冠のメダリオン）
class Emblem extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(58, 58)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.05, 0.04, 0.04, 0.85))
		draw_arc(c, r - 1, 0, TAU, 40, UITheme.GOLD, 2.0, true)
		draw_arc(c, r * 0.82, 0, TAU, 40, Color(UITheme.GOLD_DIM, 0.6), 1.0, true)
		UITheme.draw_icon(self, "crown", c + Vector2(0, -r * 0.05), r * 0.5, UITheme.GOLD)


## ロックオンの照準（ひし形と円弧が回る）
class Reticle extends Control:
	func _init() -> void:
		size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var t := Time.get_ticks_msec() * 0.002
		for i in 3:
			var a := t + i * TAU / 3.0
			draw_arc(c, 17, a, a + 0.9, 8, UITheme.GOLD_BRIGHT, 2.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 0), c + Vector2(0, 6),
			c + Vector2(-5, 0)]), Color(1, 0.95, 0.8))


var player: Player
var root: Control
var hp_bar: ProgressBar
var hp_back: ProgressBar
var stamina_bar: ProgressBar
var status_box: HBoxContainer
var resource_row: HBoxContainer
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_name: Label
var ash_label: Label
var flask_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var notify_label: Label
var big_band: ColorRect
var big_label: Label
var lock_marker: Reticle
var pause_panel: PanelContainer
var help_panel: PanelContainer
var help_label: Label
var stats_label: Label
var quality_buttons: Array[Button] = []
var touch_button: Button
var stats_button: Button
var notify_queue: Array[String] = []
var notify_time := 0.0
var boss_ref: Boss


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)

	# 左上: 紋章 + HP / スタミナ
	status_box = HBoxContainer.new()
	status_box.add_theme_constant_override("separation", 10)
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_box)
	status_box.add_child(Emblem.new())
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 6)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	status_box.add_child(bars)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(380, 16)
	bars.add_child(hp_stack)
	hp_back = UITheme.bar(UITheme.HP_TRAIL, Vector2(380, 16))
	hp_stack.add_child(hp_back)
	hp_bar = UITheme.bar(UITheme.HP, Vector2(380, 16), true)
	hp_stack.add_child(hp_bar)
	stamina_bar = UITheme.bar(UITheme.STAMINA, Vector2(300, 10))
	bars.add_child(stamina_bar)

	# 回復薬と残灰（PCは左下、タッチ時は左上）
	resource_row = HBoxContainer.new()
	resource_row.add_theme_constant_override("separation", 8)
	resource_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(resource_row)
	resource_row.add_child(IconView.new("flask", UITheme.TEXT, 30))
	flask_label = UITheme.label("", 22)
	resource_row.add_child(flask_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	resource_row.add_child(gap)
	resource_row.add_child(IconView.new("ember", UITheme.EMBER, 26))
	ash_label = UITheme.label("", 22)
	resource_row.add_child(ash_label)

	# ボスHP
	boss_box = VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 4)
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_name = UITheme.label("", 24, UITheme.GOLD)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_bar = UITheme.bar(UITheme.BOSS, Vector2(900, 14))
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	root.add_child(boss_box)

	# 中央下: 操作プロンプト
	prompt_panel = PanelContainer.new()
	prompt_panel.add_theme_stylebox_override("panel", UITheme.frame(UITheme.INK, UITheme.GOLD_DIM, 1, 4))
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label = UITheme.label("", 22)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false
	root.add_child(prompt_panel)

	# 上中央: 通知
	notify_label = UITheme.label("", 26, UITheme.TEXT)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notify_label)

	# 中央: 大見出し（死亡・勝利）。黒い帯の上に出す
	big_band = ColorRect.new()
	big_band.color = Color(0, 0, 0, 0.65)
	big_band.anchor_left = 0.0
	big_band.anchor_right = 1.0
	big_band.anchor_top = 0.5
	big_band.anchor_bottom = 0.5
	big_band.offset_top = -80
	big_band.offset_bottom = 80
	big_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_band.visible = false
	root.add_child(big_band)
	big_label = UITheme.label("", 76)
	big_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_band.add_child(big_label)

	lock_marker = Reticle.new()
	lock_marker.visible = false
	root.add_child(lock_marker)

	help_panel = PanelContainer.new()
	help_label = UITheme.label(CONTROLS_TEXT, 18)
	help_panel.add_child(help_label)
	help_panel.visible = false
	root.add_child(help_panel)

	# 性能表示（FPS・描画命令数・メモリ）。最適化の確認用
	stats_label = UITheme.label("", 16, UITheme.TEXT_DIM)
	root.add_child(stats_label)

	_build_pause_menu()
	GameState.ash_changed.connect(_on_ash_changed)
	GameState.flasks_changed.connect(_on_flasks_changed)
	GameState.notify.connect(notify)
	_on_ash_changed(GameState.ash)
	_on_flasks_changed(GameState.flasks, GameState.flask_max)


func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(IconView.new("crown", UITheme.GOLD, 34))
	var title := UITheme.label("  休 息  ", 34, UITheme.GOLD)
	head.add_child(title)
	head.add_child(IconView.new("crown", UITheme.GOLD, 34))
	v.add_child(head)
	v.add_child(_menu_button("再開する", func() -> void: resume_pressed.emit()))

	# 画質（低/中/高）
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	var ql := UITheme.label("画質", 22, UITheme.TEXT_DIM)
	ql.custom_minimum_size = Vector2(80, 0)
	qrow.add_child(ql)
	for i in GameSettings.QUALITY_NAMES.size():
		var b := _menu_button(GameSettings.QUALITY_NAMES[i], func() -> void: GameSettings.set_quality(i))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(100, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quality_buttons.append(b)
		qrow.add_child(b)
	v.add_child(qrow)
	touch_button = _menu_button("", func() -> void:
		GameSettings.set_touch_controls(not GameSettings.touch_controls))
	v.add_child(touch_button)
	stats_button = _menu_button("", func() -> void:
		GameSettings.set_show_stats(not GameSettings.show_stats))
	v.add_child(stats_button)
	v.add_child(_menu_button("操作説明", toggle_help))
	v.add_child(_menu_button("タイトルへ戻る", func() -> void: title_pressed.emit()))
	pause_panel.visible = false
	root.add_child(pause_panel)
	GameSettings.changed.connect(_refresh_settings)
	_refresh_settings()


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_press)
	return b


func _refresh_settings() -> void:
	for i in quality_buttons.size():
		quality_buttons[i].set_pressed_no_signal(i == int(GameSettings.quality))
	touch_button.text = "タッチ操作：" + ("オン" if GameSettings.touch_controls else "オフ")
	stats_button.text = "性能表示：" + ("オン" if GameSettings.show_stats else "オフ")
	stats_label.visible = GameSettings.show_stats
	_apply_layout()


## タッチ操作時は右下・左下をボタンとスティックが使うので、回復薬・残灰を左上、ボスゲージを上に移す
func _apply_layout() -> void:
	var touch := GameSettings.touch_controls
	_place(status_box, 0.0, 0.0, Vector2(24, 18), 460.0)
	if touch:
		_place(resource_row, 0.0, 0.0, Vector2(34, 86), 420.0)
		_place(boss_box, 0.5, 0.0, Vector2(-360, 16), 720.0)
		boss_bar.custom_minimum_size = Vector2(720, 14)
		_place(notify_label, 0.5, 0.0, Vector2(-450, 118), 900.0)
		_place(stats_label, 0.0, 0.0, Vector2(34, 124), 900.0)
		_place(prompt_panel, 0.5, 0.5, Vector2(-200, 90), 400.0)
	else:
		_place(resource_row, 0.0, 1.0, Vector2(32, -62), 420.0)
		_place(boss_box, 0.5, 1.0, Vector2(-450, -118), 900.0)
		boss_bar.custom_minimum_size = Vector2(900, 14)
		_place(notify_label, 0.5, 0.0, Vector2(-450, 96), 900.0)
		_place(stats_label, 0.0, 0.0, Vector2(34, 90), 900.0)
		_place(prompt_panel, 0.5, 0.5, Vector2(-200, 150), 400.0)
	_place(help_panel, 1.0, 0.0, Vector2(-600, 100 if touch else 24), 560.0)
	_place(pause_panel, 0.5, 0.5, Vector2(-280, -290), 560.0)
	_on_flasks_changed(GameState.flasks, GameState.flask_max)


## アンカー（画面上の基準点 0〜1）と、そこからの位置・幅で配置する
func _place(c: Control, ax: float, ay: float, pos: Vector2, width: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + width
	c.offset_bottom = pos.y + c.get_combined_minimum_size().y


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
	ash_label.text = "%d" % value


func _on_flasks_changed(current: int, max_value: int) -> void:
	var key := "" if GameSettings.touch_controls else "  [R]"
	flask_label.text = "%d / %d%s" % [current, max_value, key]


func show_boss(boss: Boss) -> void:
	boss_ref = boss
	boss_name.text = "— " + boss.display_name + " —"
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
	var key := "" if GameSettings.touch_controls else "[E]  "
	prompt_label.text = (key + text) if text != "" else ""
	prompt_panel.visible = text != ""


func notify(text: String) -> void:
	notify_queue.append(text)


func show_big(text: String, color: Color) -> void:
	big_label.text = text
	big_label.add_theme_color_override("font_color", color)
	big_band.modulate.a = 0.0
	big_band.visible = true
	create_tween().tween_property(big_band, "modulate:a", 1.0, 1.2)


func hide_big() -> void:
	big_band.visible = false


func set_paused(paused: bool) -> void:
	pause_panel.visible = paused


func toggle_help() -> void:
	help_label.text = TOUCH_HELP_TEXT if GameSettings.touch_controls else CONTROLS_TEXT
	help_panel.visible = not help_panel.visible
	_apply_layout()


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
	if stats_label.visible:
		stats_label.text = "FPS %d  描画命令 %d  物体 %d  メモリ %.0fMB  画質:%s" % [
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			GameSettings.QUALITY_NAMES[GameSettings.quality]]


func _update_lock_marker() -> void:
	lock_marker.visible = false
	if player == null or player.lock_target == null or player.camera_rig == null:
		return
	var cam := player.camera_rig.camera
	var t := player.lock_target
	var world_pos := t.global_position + Vector3.UP * t.lock_height
	if cam.is_position_behind(world_pos):
		return
	lock_marker.position = cam.unproject_position(world_pos) - lock_marker.size * 0.5
	lock_marker.visible = true
