extends Control
## タイトル画面。背景に実際のステージ（廃都）を描き、外套の騎士の後ろ姿をゆっくりカメラが回り込む。
## 「はじめから」「操作説明」「終了」。

var help: Label
var cam: Camera3D
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UITheme.theme()
	_build_backdrop()

	# 左側を暗くして文字を読みやすくする
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.85))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(0.75, 0.5)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = 110
	v.offset_top = -300
	v.offset_right = 760
	add_child(v)

	var crown := HUD.IconView.new("crown", UITheme.GOLD, 70)
	crown.custom_minimum_size = Vector2(560, 70)
	v.add_child(crown)
	var title := UITheme.label("ASHEN CROWN", 92, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(title)
	var sub := UITheme.label("―――  灰 の 王 冠  ―――", 32, UITheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var tag := UITheme.label("失われた王冠を求めて、灰の都へ", 20, UITheme.TEXT_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	v.add_child(spacer)

	var start := _button("はじめから", v)
	start.pressed.connect(_on_start)
	var help_btn := _button("操作説明", v)
	help_btn.pressed.connect(func() -> void: help.visible = not help.visible)
	if not GameSettings.is_mobile():
		var quit := _button("終了", v)
		quit.pressed.connect(func() -> void: get_tree().quit())
	start.grab_focus()

	help = UITheme.label(HUD.TOUCH_HELP_TEXT if GameSettings.touch_controls else HUD.CONTROLS_TEXT, 17)
	var help_panel := PanelContainer.new()
	help_panel.add_child(help)
	help_panel.anchor_left = 1.0
	help_panel.anchor_right = 1.0
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -640
	help_panel.offset_right = -60
	help_panel.offset_top = -200
	add_child(help_panel)
	help.visibility_changed.connect(func() -> void: help_panel.visible = help.visible)
	help.visible = false
	help_panel.visible = false

	var ver := UITheme.label("試作版 v0.3", 16, UITheme.TEXT_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -36)
	add_child(ver)


func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 26)
	parent.add_child(b)
	return b


## 背景の3D: 本編と同じステージ・灯り・霧に、外套の騎士を立たせる
func _build_backdrop() -> void:
	var world := Node3D.new()
	add_child(world)
	var level := LevelRuins.new()
	world.add_child(level)
	level.build()
	var knight := CharacterRig.new()
	world.add_child(knight)
	knight.build({
		"archetype": "knight", "height": 1.8, "radius": 0.35,
		"body_color": Color(0.46, 0.45, 0.48), "cloth_color": Color(0.32, 0.08, 0.07),
		"weapon_color": Color(0.82, 0.82, 0.86), "weapon_length": 0.95,
		"eye_color": Color(0.6, 0.85, 1.0), "eye_energy": 1.2, "shield": true, "draw_distance": 200.0,
	})
	knight.position = Vector3(1.2, 0, 3.5)
	knight.rotation.y = 0.15
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 160
	world.add_child(cam)
	cam.current = true
	_update_camera()
	GameSettings.apply_graphics(get_tree())


func _process(delta: float) -> void:
	_t += delta
	_update_camera()


func _update_camera() -> void:
	var a := 0.25 + sin(_t * 0.08) * 0.12
	cam.position = Vector3(1.2 + sin(a) * 4.5, 1.9, 3.5 + cos(a) * 4.5)
	cam.look_at(Vector3(-0.4, 2.6, -20.0))


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
