class_name UITheme
extends RefCounted
## 画面デザインの共通部品（ダークファンタジー調: 黒地・くすんだ金の縁取り・明朝系の文字）。
## 色と部品はすべてここで決め、HUD・タッチ操作・タイトルが同じ見た目になるようにする。

const GOLD := Color(0.83, 0.68, 0.42)
const GOLD_DIM := Color(0.55, 0.44, 0.27)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.55)
const INK := Color(0.04, 0.035, 0.04, 0.88)
const INK_LIGHT := Color(0.12, 0.1, 0.09, 0.9)
const TEXT := Color(0.93, 0.89, 0.8)
const TEXT_DIM := Color(0.68, 0.64, 0.57)
const HP := Color(0.68, 0.1, 0.08)
const HP_TRAIL := Color(0.95, 0.8, 0.45)
const STAMINA := Color(0.3, 0.58, 0.28)
const BOSS := Color(0.62, 0.12, 0.06)
const EMBER := Color(1.0, 0.55, 0.2)

static var _theme: Theme
static var _serif: Font


const SERIF_PATH := "res://assets/fonts/NotoSerifJP-SemiBold-subset.ttf"


## 明朝体（同梱の Noto Serif JP。ゲームで使う文字だけに絞ってある）。
## どの端末・ブラウザでも同じ見た目になる。足りない文字は端末のフォントで補う
static func serif() -> Font:
	if _serif == null:
		var f: FontFile = load(SERIF_PATH)
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Hiragino Mincho ProN", "Yu Mincho", "Noto Serif CJK JP", "serif"])
		f.fallbacks = [sys]
		_serif = f
	return _serif


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = serif()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("normal", "Button", frame(INK, GOLD_DIM, 1, 6))
	t.set_stylebox("hover", "Button", frame(INK_LIGHT, GOLD, 1, 6))
	t.set_stylebox("pressed", "Button", frame(Color(0.25, 0.18, 0.1, 0.95), GOLD_BRIGHT, 2, 6))
	t.set_stylebox("hover_pressed", "Button", frame(Color(0.25, 0.18, 0.1, 0.95), GOLD_BRIGHT, 2, 6))
	t.set_stylebox("focus", "Button", frame(Color(0, 0, 0, 0), GOLD_BRIGHT, 2, 6))
	t.set_stylebox("disabled", "Button", frame(INK, Color(0.3, 0.28, 0.25), 1, 6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_focus_color", "Button", GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", "Button", GOLD_BRIGHT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	_theme = t
	return t


static func frame(bg: Color, border: Color, width: int, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


static func panel_style() -> StyleBoxFlat:
	var sb := frame(Color(0.03, 0.025, 0.03, 0.92), GOLD_DIM, 1, 4)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	return sb


## 金の細い縁取りが付いたゲージ
static func bar(fill_color: Color, size: Vector2, trail: bool = false) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	if trail:
		bg.bg_color = Color(0, 0, 0, 0)
	else:
		bg.bg_color = Color(0.02, 0.02, 0.02, 0.8)
		bg.border_color = GOLD_DIM
		bg.set_border_width_all(1)
		bg.shadow_color = Color(0, 0, 0, 0.5)
		bg.shadow_size = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.border_color = fill_color.lightened(0.35)
	fill.border_width_top = 0 if trail else 2
	fill.set_expand_margin_all(-1.0)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


static func label(text: String, font_size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------ アイコン（コードで描く）

## アイコンを描く。c=中心, r=大きさ。HUDとタッチボタンで共通
static func draw_icon(ci: CanvasItem, icon: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(2.0, r * 0.12)
	match icon:
		"sword":
			ci.draw_line(c + Vector2(-r * 0.55, r * 0.55), c + Vector2(r * 0.6, -r * 0.6), col, w * 1.3, true)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.15), c + Vector2(-r * 0.15, r * 0.6), col, w, true)
			ci.draw_circle(c + Vector2(-r * 0.68, r * 0.68), w * 0.9, col)
		"heavy":
			# 大剣: 幅広の刃と衝撃線
			var pts := PackedVector2Array([c + Vector2(-r * 0.12, -r * 0.75), c + Vector2(r * 0.12, -r * 0.75),
				c + Vector2(r * 0.16, r * 0.3), c + Vector2(-r * 0.16, r * 0.3)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_line(c + Vector2(-r * 0.45, r * 0.35), c + Vector2(r * 0.45, r * 0.35), col, w, true)
			ci.draw_line(c + Vector2(0, r * 0.35), c + Vector2(0, r * 0.75), col, w * 1.3, true)
			ci.draw_line(c + Vector2(-r * 0.75, -r * 0.2), c + Vector2(-r * 0.45, -r * 0.05), col, w * 0.7, true)
			ci.draw_line(c + Vector2(r * 0.75, -r * 0.2), c + Vector2(r * 0.45, -r * 0.05), col, w * 0.7, true)
		"dodge":
			# 回り込む矢印
			ci.draw_arc(c, r * 0.5, PI * 0.9, PI * 2.3, 20, col, w, true)
			var tip := c + Vector2(cos(PI * 2.3), sin(PI * 2.3)) * r * 0.5
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.28, -r * 0.05),
				tip + Vector2(-r * 0.1, -r * 0.3), tip + Vector2(-r * 0.05, r * 0.2)]), col)
		"shield":
			var sp := PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.55), c + Vector2(r * 0.5, -r * 0.55),
				c + Vector2(r * 0.45, r * 0.1), c + Vector2(0, r * 0.7), c + Vector2(-r * 0.45, r * 0.1)])
			ci.draw_colored_polygon(sp, col)
			ci.draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.5), Color(0, 0, 0, 0.5), w * 0.8, true)
		"jump":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(r * 0.5, -r * 0.1),
				c + Vector2(-r * 0.5, -r * 0.1)]), col)
			ci.draw_line(c + Vector2(0, -r * 0.15), c + Vector2(0, r * 0.65), col, w * 1.4, true)
		"lock":
			ci.draw_arc(c, r * 0.5, 0, TAU, 24, col, w, true)
			for i in 4:
				var d := Vector2.RIGHT.rotated(i * PI * 0.5)
				ci.draw_line(c + d * r * 0.3, c + d * r * 0.75, col, w, true)
			ci.draw_circle(c, w * 1.1, col)
		"flask":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.14, -r * 0.7), Vector2(r * 0.28, r * 0.35)), col)
			ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.48, col)
			ci.draw_circle(c + Vector2(0, r * 0.28), r * 0.3, Color(1.0, 0.55, 0.2, 0.95))
		"interact":
			# 手のひら（拾う・調べる）
			ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.38, col)
			for i in 4:
				var x := (i - 1.5) * r * 0.2
				ci.draw_line(c + Vector2(x, r * 0.05), c + Vector2(x * 1.1, -r * 0.62), col, w * 1.2, true)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.45), Vector2(r * 0.22, r * 0.9)), col)
			ci.draw_rect(Rect2(c + Vector2(r * 0.13, -r * 0.45), Vector2(r * 0.22, r * 0.9)), col)
		"ember":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.6, 0),
				c + Vector2(0, r), c + Vector2(-r * 0.6, 0)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.5), c + Vector2(r * 0.3, 0),
				c + Vector2(0, r * 0.5), c + Vector2(-r * 0.3, 0)]), Color(1, 0.9, 0.6))
		"crown":
			var cp := PackedVector2Array([c + Vector2(-r, r * 0.45), c + Vector2(-r * 0.85, -r * 0.4),
				c + Vector2(-r * 0.4, r * 0.05), c + Vector2(0, -r * 0.75), c + Vector2(r * 0.4, r * 0.05),
				c + Vector2(r * 0.85, -r * 0.4), c + Vector2(r, r * 0.45)])
			ci.draw_colored_polygon(cp, col)
			ci.draw_rect(Rect2(c + Vector2(-r, r * 0.55), Vector2(r * 2.0, r * 0.18)), col)


## 円形の装飾ボタン（タッチ操作・アイコン枠）
static func draw_round_button(ci: CanvasItem, c: Vector2, r: float, icon: String, caption: String,
		pressed: bool, font_size: int, emphasis: bool = false) -> void:
	var fill := Color(0.06, 0.05, 0.05, 0.6) if not pressed else Color(0.35, 0.22, 0.1, 0.85)
	ci.draw_circle(c, r, fill)
	if pressed:
		ci.draw_circle(c, r * 0.8, Color(1.0, 0.6, 0.25, 0.25))
	var rim := GOLD_BRIGHT if pressed else (GOLD if emphasis else GOLD_DIM)
	ci.draw_arc(c, r, 0, TAU, 48, rim, maxf(2.0, r * 0.05), true)
	ci.draw_arc(c, r * 0.86, 0, TAU, 48, Color(rim, 0.35), 1.5, true)
	# 縁の四方の飾り
	for i in 4:
		var d := Vector2.UP.rotated(i * PI * 0.5 + PI * 0.25)
		var p := c + d * r
		ci.draw_colored_polygon(PackedVector2Array([p + d * r * 0.1, p + d.orthogonal() * r * 0.06,
			p - d * r * 0.08, p - d.orthogonal() * r * 0.06]), rim)
	var icon_col := GOLD_BRIGHT if pressed else TEXT
	var icon_c := c - Vector2(0, r * 0.12 if caption != "" else 0.0)
	draw_icon(ci, icon, icon_c, r * 0.42, icon_col)
	if caption != "":
		var f := serif()
		var sz := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		ci.draw_string(f, c + Vector2(-sz.x * 0.5, r * 0.62), caption, HORIZONTAL_ALIGNMENT_CENTER, -1,
			font_size, Color(TEXT, 0.9))
