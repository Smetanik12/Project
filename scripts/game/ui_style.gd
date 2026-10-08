class_name UiStyle
extends RefCounted
## Общий вид панелей интерфейса.

const BG := Color(0.07, 0.065, 0.06, 0.86)
const BORDER := Color(0.62, 0.5, 0.33, 0.7)
const ACCENT := Color(1.0, 0.82, 0.45)


static func panel(alpha := 0.86) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BG, alpha)
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	return sb


static func make_panel(alpha := 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(alpha))
	return p


static func button(text: String, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	return b


static func label(text: String, size := 15, col := Color(0.92, 0.9, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Экранирование для RichTextLabel с BBCode.
static func esc(s: String) -> String:
	return s.replace("[", "[lb]")
