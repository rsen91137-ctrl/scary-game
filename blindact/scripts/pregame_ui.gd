class_name PregameUI
extends Control
## UI over the red sketch eye: difficulty list, microphone calibration and
## the typed backstory. Emits signals; the pregame director does the rest.

signal difficulty_chosen(index: int)
signal back_requested
signal calibration_done(use_mic: bool)
signal story_finished
signal control_focused(ctrl: Control)

const DIFFS := [
	["DIFF_EASY", "DIFF_EASY_D", false],
	["DIFF_NORMAL", "DIFF_NORMAL_D", true],
	["DIFF_HARD", "DIFF_HARD_D", false],
	["DIFF_NIGHTMARE", "DIFF_NIGHTMARE_D", false],
]

var mic: MicMonitor
var diff_panel: VBoxContainer
var diff_desc: Label
var diff_buttons: Array[HorrorButton] = []
var cal_panel: VBoxContainer
var cal_status: Label
var cal_meter: Control
var btn_begin: HorrorButton
var btn_retry: HorrorButton
var btn_skip: HorrorButton
var story_label: Label
var skip_hint: Label

var _sfx_hover: AudioStreamPlayer
var _sfx_click: AudioStreamPlayer
var _sfx_back: AudioStreamPlayer
var _cal_phase := ""
var _cal_t := 0.0
var _noise_acc := 0.0
var _noise_n := 0
var _noise := -60.0
var _gasp := -90.0
var _story_lines: Array[String] = []
var _story_i := -1
var _story_t := 0.0
var _story_len := 0.0
var _skip_hold := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sfx_hover = _player("res://assets/audio/ui_hover.ogg", -10.0)
	_sfx_click = _player("res://assets/audio/ui_click.ogg", -4.0)
	_sfx_back = _player("res://assets/audio/ui_back.ogg", -6.0)
	_build_difficulty()
	_build_calibration()
	_build_story()
	diff_panel.visible = false
	cal_panel.visible = false


func _player(path: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.volume_db = vol
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer) -> void:
	if p.stream:
		p.pitch_scale = _rng.randf_range(0.95, 1.05)
		p.play()


func _lower_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.anchor_left = 0.0
	v.anchor_right = 1.0
	v.anchor_top = 0.55
	v.anchor_bottom = 0.97
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	return v


# ---------------------------------------------------------------------------
# difficulty
# ---------------------------------------------------------------------------
func _build_difficulty() -> void:
	diff_panel = _lower_box()
	diff_panel.add_child(UIWidgets.label("DIFF_TITLE", 30, Color(0.86, 0.2, 0.16), true, 6))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	diff_panel.add_child(gap)
	for d: Array in DIFFS:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := HorrorButton.new(d[0], 34)
		b.custom_minimum_size = Vector2(300, 52)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.hovered.connect(_play.bind(_sfx_hover))
		b.focus_entered.connect(_on_diff_focus.bind(DIFFS.find(d), b))
		b.pressed.connect(_on_diff_pressed.bind(DIFFS.find(d)))
		if not bool(d[2]):
			b.modulate = Color(1, 1, 1, 0.5)
		row.add_child(b)
		diff_panel.add_child(row)
		diff_buttons.append(b)
	diff_desc = UIWidgets.label("", 22, UIWidgets.COL_DIM)
	diff_desc.custom_minimum_size = Vector2(0, 64)
	diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diff_panel.add_child(diff_desc)
	var back := HorrorButton.new("BTN_BACK", 26)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 44)
	back.hovered.connect(_play.bind(_sfx_hover))
	back.pressed.connect(func() -> void:
		_play(_sfx_back)
		back_requested.emit())
	diff_panel.add_child(back)


func show_difficulty() -> void:
	diff_panel.visible = true
	cal_panel.visible = false
	diff_panel.modulate.a = 0.0
	create_tween().tween_property(diff_panel, "modulate:a", 1.0, 0.8)
	diff_buttons[1].grab_focus.call_deferred()


func _on_diff_focus(i: int, b: Control) -> void:
	diff_desc.text = DIFFS[i][1]
	diff_desc.add_theme_color_override("font_color", UIWidgets.COL_DIM)
	if not bool(DIFFS[i][2]):
		diff_desc.text = tr(DIFFS[i][1]) + "\n— " + tr("DIFF_WIP") + " —"
	control_focused.emit(b)


func _on_diff_pressed(i: int) -> void:
	if not bool(DIFFS[i][2]):
		_play(_sfx_back)
		diff_desc.text = "DIFF_WIP_MSG"
		diff_desc.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))
		_shake = 0.35
		return
	_play(_sfx_click)
	var tw := create_tween()
	tw.tween_property(diff_panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		diff_panel.visible = false
		difficulty_chosen.emit(i))


# ---------------------------------------------------------------------------
# microphone calibration
# ---------------------------------------------------------------------------
func _build_calibration() -> void:
	cal_panel = _lower_box()
	cal_panel.anchor_top = 0.5
	cal_panel.add_child(UIWidgets.label("CAL_TITLE", 30, Color(0.86, 0.2, 0.16), true, 6))
	var intro := UIWidgets.label("CAL_INTRO", 24, UIWidgets.COL_TEXT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cal_panel.add_child(intro)
	var hp := UIWidgets.label("CAL_HEADPHONES", 18, UIWidgets.COL_DIM)
	cal_panel.add_child(hp)
	cal_status = UIWidgets.label("CAL_QUIET", 28, Color(0.95, 0.85, 0.8), true)
	cal_status.custom_minimum_size = Vector2(0, 80)
	cal_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cal_panel.add_child(cal_status)
	cal_meter = Control.new()
	cal_meter.custom_minimum_size = Vector2(560, 22)
	cal_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cal_meter.draw.connect(_draw_meter)
	cal_panel.add_child(cal_meter)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 30)
	cal_panel.add_child(h)
	btn_begin = HorrorButton.new("CAL_BEGIN", 30)
	btn_retry = HorrorButton.new("CAL_RETRY", 24)
	btn_skip = HorrorButton.new("CAL_SKIP", 24)
	for b: HorrorButton in [btn_retry, btn_begin, btn_skip]:
		b.custom_minimum_size = Vector2(230, 52)
		b.hovered.connect(_play.bind(_sfx_hover))
		h.add_child(b)
	btn_begin.pressed.connect(func() -> void:
		if _cal_phase == "done":
			_play(_sfx_click)
			cal_panel.visible = false
			calibration_done.emit(true))
	btn_retry.pressed.connect(func() -> void:
		_play(_sfx_click)
		start_calibration())
	btn_skip.pressed.connect(func() -> void:
		_play(_sfx_back)
		cal_panel.visible = false
		calibration_done.emit(false))


func show_calibration() -> void:
	cal_panel.visible = true
	diff_panel.visible = false
	cal_panel.modulate.a = 0.0
	create_tween().tween_property(cal_panel, "modulate:a", 1.0, 0.8)
	start_calibration()


func start_calibration() -> void:
	_cal_phase = "quiet"
	_cal_t = 0.0
	_noise_acc = 0.0
	_noise_n = 0
	_gasp = -90.0
	cal_status.text = "CAL_QUIET"
	btn_begin.modulate.a = 0.35
	btn_skip.grab_focus.call_deferred()


func _update_calibration(delta: float) -> void:
	if _cal_phase == "" or _cal_phase == "done" or _cal_phase == "nomic" or mic == null:
		return
	_cal_t += delta
	if _cal_phase == "quiet":
		if _cal_t > 0.6:
			_noise_acc += mic.level_db
			_noise_n += 1
		if _cal_t >= 3.0:
			if not mic.has_input() or _noise_n == 0:
				_cal_phase = "nomic"
				cal_status.text = "CAL_NO_MIC"
				return
			_noise = _noise_acc / float(_noise_n)
			_cal_phase = "gasp"
			_cal_t = 0.0
			cal_status.text = "CAL_SPEAK"
	elif _cal_phase == "gasp":
		_gasp = maxf(_gasp, mic.level_db)
		var heard := _gasp > _noise + 10.0 and mic.level_db < _gasp - 8.0 and _cal_t > 0.8
		if heard or _cal_t > 7.0:
			Settings.mic_noise_db = _noise
			Settings.mic_voice_db = maxf(_gasp, _noise + 12.0)
			Settings.mic_calibrated = true
			Settings.save_settings()
			_cal_phase = "done"
			cal_status.text = "CAL_DONE"
			btn_begin.modulate.a = 1.0
			btn_begin.grab_focus.call_deferred()


func _draw_meter() -> void:
	var w := cal_meter.size.x
	var h := cal_meter.size.y
	cal_meter.draw_rect(Rect2(0, h * 0.35, w, h * 0.3), Color(1, 1, 1, 0.12))
	if mic == null:
		return
	var k := clampf(remap(mic.level_db, -70.0, -10.0, 0.0, 1.0), 0.0, 1.0)
	var col := Color(0.75, 0.1, 0.07) if mic.level_db > mic.threshold_db() else Color(0.8, 0.75, 0.7)
	cal_meter.draw_rect(Rect2(0, h * 0.35, w * k, h * 0.3), col)
	var tk := clampf(remap(mic.threshold_db(), -70.0, -10.0, 0.0, 1.0), 0.0, 1.0)
	if _cal_phase == "done":
		cal_meter.draw_line(Vector2(w * tk, 0), Vector2(w * tk, h), Color(0.9, 0.15, 0.1), 2.0)


# ---------------------------------------------------------------------------
# backstory
# ---------------------------------------------------------------------------
func _build_story() -> void:
	story_label = UIWidgets.label("", 38, Color(0.9, 0.86, 0.82))
	story_label.anchor_left = 0.08
	story_label.anchor_right = 0.92
	story_label.anchor_top = 0.66
	story_label.anchor_bottom = 0.86
	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(story_label)
	skip_hint = UIWidgets.label("STORY_SKIP", 18, Color(0.55, 0.5, 0.48, 0.6))
	skip_hint.anchor_left = 0.7
	skip_hint.anchor_right = 0.97
	skip_hint.anchor_top = 0.93
	skip_hint.anchor_bottom = 0.98
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip_hint.visible = false
	add_child(skip_hint)


func show_story(keys: Array) -> void:
	_story_lines.assign(keys)
	_story_i = -1
	_next_story_line()
	skip_hint.visible = true


func _next_story_line() -> void:
	_story_i += 1
	if _story_i >= _story_lines.size():
		story_label.text = ""
		skip_hint.visible = false
		_story_i = -1
		story_finished.emit()
		return
	story_label.text = tr(_story_lines[_story_i])
	story_label.visible_ratio = 0.0
	_story_t = 0.0
	_story_len = 1.6 + story_label.text.length() * 0.085


func _process(delta: float) -> void:
	_update_calibration(delta)
	if cal_panel.visible:
		cal_meter.queue_redraw()
	if _shake > 0.0:
		_shake -= delta
		diff_panel.position.x = sin(_shake * 90.0) * 10.0 * _shake
	elif diff_panel.position.x != 0.0:
		diff_panel.position.x = 0.0
	if _story_i >= 0:
		_story_t += delta
		var type_t := story_label.text.length() * 0.06
		story_label.visible_ratio = clampf(_story_t / maxf(type_t, 0.01), 0.0, 1.0)
		var fade := 1.0 - smoothstep(_story_len - 0.6, _story_len, _story_t)
		story_label.modulate.a = fade
		if _story_t >= _story_len:
			_next_story_line()
		if Input.is_key_pressed(KEY_SPACE):
			_skip_hold += delta
			if _skip_hold > 0.8:
				_skip_hold = 0.0
				_story_i = _story_lines.size() - 1
				_next_story_line()
		else:
			_skip_hold = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and diff_panel.visible:
		_play(_sfx_back)
		back_requested.emit()
		get_viewport().set_input_as_handled()
