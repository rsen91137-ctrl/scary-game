class_name HorrorButton
extends Button
## Text-only menu button. On hover/focus the text brightens, gains a faint
## blood-red glow and thin rules slide out on both sides.

signal hovered

var _h := 0.0
var _was_hot := false
var _t := 0.0


func _init(txt: String = "", size: int = 42) -> void:
	text = txt
	flat = true
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_override("font", UIWidgets.spaced(true, 10))
	add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, UIWidgets.empty_box())
	add_theme_color_override("font_color", UIWidgets.COL_TEXT)
	add_theme_color_override("font_hover_color", UIWidgets.COL_HOT)
	add_theme_color_override("font_focus_color", UIWidgets.COL_HOT)
	add_theme_color_override("font_pressed_color", Color(0.9, 0.3, 0.25))
	add_theme_color_override("font_hover_pressed_color", Color(0.9, 0.3, 0.25))
	add_theme_color_override("font_outline_color", Color(0.35, 0.02, 0.02, 0.0))
	add_theme_constant_override("outline_size", 10)
	custom_minimum_size = Vector2(360, size * 1.7)
	mouse_entered.connect(func() -> void: grab_focus())


func _process(delta: float) -> void:
	_t += delta
	var hot := has_focus() or is_hovered()
	if hot and not _was_hot:
		hovered.emit()
	_was_hot = hot
	_h = move_toward(_h, 1.0 if hot else 0.0, delta * 3.5)
	var glow := 0.28 * _h * (0.85 + 0.15 * sin(_t * 7.0))
	add_theme_color_override("font_outline_color", Color(0.4, 0.02, 0.02, glow))
	queue_redraw()


func _draw() -> void:
	if _h <= 0.001:
		return
	var font_sz := get_theme_font_size("font_size")
	var w := get_theme_font("font").get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
	var cy := size.y * 0.5 + 2.0
	var half := w * 0.5 + 26.0
	var lw := 70.0 * ease(_h, 0.4)
	var col := Color(0.72, 0.1, 0.07, 0.85 * _h)
	var cx := size.x * 0.5
	draw_line(Vector2(cx - half - lw, cy), Vector2(cx - half, cy), col, 1.5, true)
	draw_line(Vector2(cx + half, cy), Vector2(cx + half + lw, cy), col, 1.5, true)
	draw_circle(Vector2(cx - half - lw - 5.0, cy), 2.2 * _h, col)
	draw_circle(Vector2(cx + half + lw + 5.0, cy), 2.2 * _h, col)
