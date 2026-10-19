extends Control
## タイトル画面。「はじめから」「操作説明」「終了」。

var help: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var title := Label.new()
	title.text = "ASHEN CROWN"
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "灰 の 王 冠"
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.75, 0.45, 0.25))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)

	var start := _button("はじめから", v)
	start.pressed.connect(_on_start)
	var help_btn := _button("操作説明", v)
	help_btn.pressed.connect(func() -> void: help.visible = not help.visible)
	var quit := _button("終了", v)
	quit.pressed.connect(func() -> void: get_tree().quit())
	start.grab_focus()

	help = Label.new()
	help.text = HUD.CONTROLS_TEXT
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	help.visible = false
	v.add_child(help)

	var ver := Label.new()
	ver.text = "試作版 v0.1 — Godot Engine"
	ver.add_theme_color_override("font_color", Color(0.45, 0.43, 0.4))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(20, -40)
	add_child(ver)


func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 48)
	b.add_theme_font_size_override("font_size", 24)
	parent.add_child(b)
	return b


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
