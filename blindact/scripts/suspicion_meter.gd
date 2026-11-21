class_name SuspicionMeter
extends Control
## How sure he is that you can see: an eye that opens wider and reddens, a
## bar that fills (marks at 50 % and 80 %), and each time he notices
## something a red pulse with the reason under it.

const BAR_X := 66.0
const BAR_Y := 34.0
const BAR_W := 230.0
const BAR_H := 10.0

var value := 0.0          # shown, 0..1
var target := 0.0
var _pulse := 0.0
var _reason_t := 0.0
var _t := 0.0
var _label: Label
var _reason: Label
var mic_db := -90.0
var mic_thr := -30.0
var mic_on := false


func _ready() -> void:
	custom_minimum_size = Vector2(320, 98)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UIWidgets.label(tr("SUSP_LABEL"), 18, Color(0.78, 0.84, 0.9, 0.9))
	_label.position = Vector2(BAR_X, 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_reason = UIWidgets.label("", 18, Color(0.96, 0.42, 0.38))
	_reason.position = Vector2(BAR_X, 52)
	_reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_reason.add_theme_constant_override("shadow_offset_x", 2)
	_reason.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_reason)


## The microphone strip: your voice against the line he can hear.
func set_mic(db: float, thr: float, on: bool) -> void:
	mic_db = db
	mic_thr = thr
	mic_on = on


func set_value(v: float) -> void:
	target = clampf(v, 0.0, 1.0)


func notice(reason_key: String, amount: float) -> void:
	_pulse = 1.0
	_reason.text = "%s  +%d" % [tr(reason_key), int(round(amount))]
	_reason_t = 2.6


func _process(delta: float) -> void:
	_t += delta
	value = move_toward(value, target, delta * (1.2 if target > value else 0.4))
	_pulse = maxf(0.0, _pulse - delta * 1.4)
	_reason_t = maxf(0.0, _reason_t - delta)
	_reason.modulate.a = clampf(_reason_t / 0.6, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var col := Color(0.76, 0.83, 0.9).lerp(Color(0.93, 0.12, 0.1), smoothstep(0.25, 0.85, value))
	col.a = 0.92
	# the eye: lids open with suspicion; the pupil narrows to a point
	var c := Vector2(30, 40) + Vector2(sin(_t * 40.0), cos(_t * 37.0)) * 1.5 * _pulse
	var open := lerpf(0.3, 1.0, value) + 0.15 * _pulse
	var up := PackedVector2Array()
	var lo := PackedVector2Array()
	for i in 25:
		var f := float(i) / 24.0
		var x := lerpf(-24.0, 24.0, f)
		var h := sin(f * PI) * 15.0 * open
		up.append(c + Vector2(x, -h))
		lo.append(c + Vector2(x, h * 0.75))
	draw_polyline(up, col, 2.0, true)
	draw_polyline(lo, col, 2.0, true)
	var r := 6.0 + 4.0 * open
	draw_circle(c, r, Color(col.r, col.g, col.b, 0.25 + 0.5 * value))
	draw_arc(c, r, 0.0, TAU, 24, col, 1.5, true)
	draw_circle(c, lerpf(3.0, 1.2, value), Color(0.02, 0.02, 0.02, 0.95))
	# the bar, with the 50 % and 80 % marks
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W, BAR_H), Color(0.06, 0.07, 0.08, 0.82))
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W * value, BAR_H), col)
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W, BAR_H), Color(0.62, 0.68, 0.74, 0.6), false, 1.0)
	for m: float in [0.5, 0.8]:
		draw_line(Vector2(BAR_X + BAR_W * m, BAR_Y - 3), Vector2(BAR_X + BAR_W * m, BAR_Y + BAR_H + 3), Color(0.85, 0.9, 0.95, 0.55), 1.0)
	if _pulse > 0.0:
		draw_rect(Rect2(BAR_X - 3, BAR_Y - 3, BAR_W + 6, BAR_H + 6), Color(1.0, 0.2, 0.15, _pulse * 0.85), false, 2.0)
	# the microphone: -60..0 dB, a tick at the level he can hear
	var my := 84.0
	draw_rect(Rect2(BAR_X, my, BAR_W, 5.0), Color(0.06, 0.07, 0.08, 0.82))
	if mic_on:
		var lv := clampf((mic_db + 60.0) / 60.0, 0.0, 1.0)
		var th := clampf((mic_thr + 60.0) / 60.0, 0.0, 1.0)
		draw_rect(Rect2(BAR_X, my, BAR_W * lv, 5.0), Color(0.95, 0.15, 0.12, 0.95) if mic_db > mic_thr else Color(0.55, 0.85, 0.7, 0.85))
		draw_line(Vector2(BAR_X + BAR_W * th, my - 3), Vector2(BAR_X + BAR_W * th, my + 8), Color(1, 1, 1, 0.8), 1.5)
	else:
		draw_line(Vector2(BAR_X, my + 2.5), Vector2(BAR_X + BAR_W, my + 2.5), Color(0.6, 0.3, 0.3, 0.7), 1.0)
