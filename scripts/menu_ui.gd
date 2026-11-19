class_name MenuUI
extends Control
## Main menu overlay: logo, the two centred buttons (开始游戏 / 设置),
## the settings panel and an ESC "leave?" prompt.

signal start_requested
signal quit_requested

const LOGO_PATH := "res://assets/ui/logo_mask.png"

var logo: TextureRect
var logo_mat: ShaderMaterial
var logo_shadow: TextureRect
var menu_box: VBoxContainer
var btn_start: HorrorButton
var btn_settings: HorrorButton
var settings_panel: PanelContainer
var quit_panel: PanelContainer
var footer_icons: HBoxContainer
var footer_r: Label
var flicker := 1.0               # lamp level fed by the director
var external_glitch := 0.0       # blackout glitch fed by the director
var heart_pulse := 0.0           # heartbeat envelope fed by the director
var _logo_dim := 1.0
var interactive := false

var _t := 0.0
var _alpha := 0.0
var _target_alpha := 0.0
var _glitch := 0.0
var _rng := RandomNumberGenerator.new()
var _sfx_hover: AudioStreamPlayer
var _sfx_click: AudioStreamPlayer
var _sfx_back: AudioStreamPlayer
var _first_control: Control
var _row_icons: Array = []        # [TextureRect, Control] pairs: icon turns red on focus
var _lang_btn: CycleButton

const ICON_IDLE := Color(1.0, 1.0, 1.0, 0.7)
const ICON_HOT := Color(1.0, 0.32, 0.26, 1.0)


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sfx_hover = _player("res://assets/audio/ui_hover.ogg", -10.0)
	_sfx_click = _player("res://assets/audio/ui_click.ogg", -4.0)
	_sfx_back = _player("res://assets/audio/ui_back.ogg", -6.0)

	# ---- title + buttons, centred (buttons sit at the middle of the screen)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	center.add_child(col)

	# CORRIDOR logotype (see tools/gen_logo.py), with a soft dark halo behind it
	var logo_holder := Control.new()
	logo_holder.custom_minimum_size = Vector2(1300, 400)
	logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo_holder)
	var tex: Texture2D = load(LOGO_PATH) if ResourceLoader.exists(LOGO_PATH) else null
	logo_shadow = TextureRect.new()
	logo_shadow.texture = _halo_texture()
	logo_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	logo_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo_shadow.offset_left = -160
	logo_shadow.offset_right = 160
	logo_shadow.offset_top = 40
	logo_shadow.offset_bottom = -40
	logo_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_holder.add_child(logo_shadow)
	logo = TextureRect.new()
	logo.texture = tex
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_mat = ShaderMaterial.new()
	logo_mat.shader = load("res://shaders/logo.gdshader")
	logo.material = logo_mat
	logo_holder.add_child(logo)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	menu_box = VBoxContainer.new()
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_theme_constant_override("separation", 14)
	col.add_child(menu_box)
	btn_start = HorrorButton.new("MENU_START", 44)
	btn_settings = HorrorButton.new("MENU_SETTINGS", 44)
	for b: HorrorButton in [btn_start, btn_settings]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.hovered.connect(_on_hover)
		menu_box.add_child(b)
	btn_start.pressed.connect(_on_start)
	btn_settings.pressed.connect(_on_settings)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 300)
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap2)

	# ---- footer: headphones + lights-off pictograms (bottom left), version (bottom right)
	footer_icons = HBoxContainer.new()
	footer_icons.add_theme_constant_override("separation", 22)
	footer_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer_icons)
	footer_icons.anchor_top = 1.0
	footer_icons.anchor_bottom = 1.0
	footer_icons.offset_left = 48
	footer_icons.offset_top = -78
	footer_icons.offset_right = 300
	footer_icons.offset_bottom = -34
	for icon_path: String in ["res://assets/ui/icon_headphones.svg", "res://assets/ui/icon_lights_off.svg"]:
		var ic := TextureRect.new()
		if ResourceLoader.exists(icon_path):
			ic.texture = load(icon_path)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ic.custom_minimum_size = Vector2(46, 46)
		ic.modulate = Color(1, 1, 1, 0.66)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer_icons.add_child(ic)
	footer_r = UIWidgets.label("VERSION", 19, Color(0.5, 0.48, 0.46, 0.7))
	footer_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(footer_r)
	footer_r.anchor_left = 1.0
	footer_r.anchor_right = 1.0
	footer_r.anchor_top = 1.0
	footer_r.anchor_bottom = 1.0
	footer_r.offset_left = -500
	footer_r.offset_right = -48
	footer_r.offset_top = -64
	footer_r.offset_bottom = -30

	settings_panel = _build_settings()
	settings_panel.visible = false
	add_child(settings_panel)
	quit_panel = _build_quit()
	quit_panel.visible = false
	add_child(quit_panel)

	modulate.a = 0.0
	_set_interactive(false)
	Settings.changed.connect(_sync_from_settings)


func _set_language(i: int) -> void:
	_set_setting("language", I18n.LANGUAGES[i][0])


func _sync_from_settings() -> void:
	if _lang_btn and not _lang_btn.has_focus():
		_lang_btn.set_index(I18n.language_index(Settings.language))


func _halo_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 256
	gt.height = 64
	return gt


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


func show_menu(after: float = 0.0) -> void:
	await get_tree().create_timer(after).timeout
	_target_alpha = 1.0
	_set_interactive(true)
	btn_start.grab_focus.call_deferred()


func snap_visible() -> void:
	_alpha = 1.0
	_target_alpha = 1.0
	modulate.a = 1.0


func hide_menu() -> void:
	_target_alpha = 0.0
	_set_interactive(false)


func _set_interactive(on: bool) -> void:
	interactive = on
	for b: Button in [btn_start, btn_settings]:
		b.disabled = not on
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _on_hover() -> void:
	if interactive:
		_play(_sfx_hover)


func _on_start() -> void:
	if not interactive:
		return
	_play(_sfx_click)
	hide_menu()
	start_requested.emit()


func _on_settings() -> void:
	if not interactive:
		return
	_play(_sfx_click)
	menu_box.visible = false
	settings_panel.visible = true
	settings_panel.modulate.a = 0.0
	create_tween().tween_property(settings_panel, "modulate:a", 1.0, 0.35)
	_first_control.grab_focus.call_deferred()


func _close_settings() -> void:
	_play(_sfx_back)
	Settings.save_settings()
	settings_panel.visible = false
	menu_box.visible = true
	btn_settings.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_panel.visible:
			_close_settings()
		elif quit_panel.visible:
			quit_panel.visible = false
			menu_box.visible = true
			_play(_sfx_back)
			btn_start.grab_focus.call_deferred()
		elif interactive:
			menu_box.visible = false
			quit_panel.visible = true
			_play(_sfx_click)
			(quit_panel.get_meta("stay") as Button).grab_focus.call_deferred()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, _target_alpha, delta * (0.45 if _target_alpha > _alpha else 1.4))
	modulate.a = _alpha
	# the light slit breathes with the nearest lamp; the letters glitch now and then
	var f := clampf(flicker, 0.0, 1.0)
	if _rng.randf() < delta * 0.07:
		_glitch = _rng.randf_range(0.06, 0.22)
	var g := 0.0
	if _glitch > 0.0:
		_glitch -= delta
		g = _rng.randf_range(0.4, 1.0)
	var panel_open := settings_panel.visible or quit_panel.visible
	_logo_dim = move_toward(_logo_dim, 0.12 if panel_open else 1.0, delta * 3.0)
	logo.modulate.a = _logo_dim
	logo_shadow.modulate.a = _logo_dim
	for pair: Array in _row_icons:
		var hot: bool = (pair[1] as Control).has_focus()
		(pair[0] as TextureRect).modulate = (pair[0] as TextureRect).modulate.lerp(ICON_HOT if hot else ICON_IDLE, 1.0 - exp(-delta * 12.0))
	logo_mat.set_shader_parameter("pulse", heart_pulse)
	logo_mat.set_shader_parameter("light", f)
	logo_mat.set_shader_parameter("glitch", maxf(g, external_glitch))
	logo_mat.set_shader_parameter("time_s", _t)
	logo_mat.set_shader_parameter("letters_alpha", (0.78 + 0.22 * f) * (_rng.randf_range(0.55, 1.0) if g > 0.0 else 1.0))


# ---------------------------------------------------------------------------
# settings panel
# ---------------------------------------------------------------------------
func _panel_style() -> StyleBoxFlat:
	var s := UIWidgets.flat_box(Color(0.0, 0.0, 0.0, 0.78), Color(0.6, 0.55, 0.5, 0.18), 1, 0)
	s.content_margin_left = 56
	s.content_margin_right = 56
	s.content_margin_top = 40
	s.content_margin_bottom = 36
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 40
	return s


func _build_settings() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1040, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := UIWidgets.label("SETTINGS_TITLE", 40, UIWidgets.COL_HOT, true, 8)
	v.add_child(head)
	var line := ColorRect.new()
	line.color = Color(0.6, 0.08, 0.06, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	v.add_child(sp)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)

	var controls: Array[Control] = []
	var langs: Array[String] = []
	for lang: Array in I18n.LANGUAGES:
		langs.append(lang[1])
	var lang_ctrl: Control = _cycle_row(grid, "OPT_LANGUAGE", "globe", langs, I18n.language_index(Settings.language), _set_language)
	_lang_btn = lang_ctrl as CycleButton
	controls.append(lang_ctrl)
	controls.append(_slider_row(grid, "OPT_BRIGHTNESS", "sun", 0.5, 1.6, Settings.brightness, func(x: float) -> void: _set_setting("brightness", x), func(x: float) -> String: return "%d%%" % roundi(x * 100.0)))
	var qopts: Array[String] = []
	qopts.assign(Settings.QUALITY_KEYS)
	controls.append(_cycle_row(grid, "OPT_QUALITY", "display", qopts, Settings.quality, func(i: int) -> void: _set_setting("quality", i)))
	controls.append(_cycle_row(grid, "OPT_FULLSCREEN", "fullscreen", _onoff(), 1 if Settings.fullscreen else 0, func(i: int) -> void: _set_setting("fullscreen", i == 1)))
	controls.append(_cycle_row(grid, "OPT_VSYNC", "sync", _onoff(), 1 if Settings.vsync else 0, func(i: int) -> void: _set_setting("vsync", i == 1)))
	controls.append(_cycle_row(grid, "OPT_GRAIN", "film", _onoff(), 1 if Settings.film_grain else 0, func(i: int) -> void: _set_setting("film_grain", i == 1)))
	controls.append(_slider_row(grid, "OPT_SHAKE", "heartbeat", 0.0, 1.5, Settings.shake, func(x: float) -> void: _set_setting("shake", x), func(x: float) -> String: return "%d%%" % roundi(x * 100.0)))
	controls.append(_slider_row(grid, "OPT_MASTER", "volume", 0.0, 1.0, Settings.master_volume, func(x: float) -> void: _set_setting("master_volume", x), func(x: float) -> String: return "%d" % roundi(x * 100.0)))
	controls.append(_slider_row(grid, "OPT_MUSIC", "music", 0.0, 1.0, Settings.music_volume, func(x: float) -> void: _set_setting("music_volume", x), func(x: float) -> String: return "%d" % roundi(x * 100.0)))
	controls.append(_slider_row(grid, "OPT_SFX", "waveform", 0.0, 1.0, Settings.sfx_volume, func(x: float) -> void: _set_setting("sfx_volume", x), func(x: float) -> String: return "%d" % roundi(x * 100.0)))

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 16)
	v.add_child(sp2)
	var back := HorrorButton.new("BTN_BACK", 32)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.hovered.connect(_on_hover)
	back.pressed.connect(_close_settings)
	v.add_child(back)
	controls.append(back)
	_first_control = controls[0]
	# keyboard / gamepad navigation, top to bottom, wrapping
	for i in controls.size():
		var c := controls[i]
		var prev := controls[(i - 1 + controls.size()) % controls.size()]
		var nxt := controls[(i + 1) % controls.size()]
		c.focus_neighbor_top = c.get_path_to(prev)
		c.focus_neighbor_bottom = c.get_path_to(nxt)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(nxt)
	return panel


func _onoff() -> Array[String]:
	var a: Array[String] = ["VAL_OFF", "VAL_ON"]
	return a


func _set_setting(key: String, value: Variant) -> void:
	Settings.set(key, value)
	Settings.apply()


## Row caption: a line icon followed by the (translated) label.
func _row_label(grid: GridContainer, text: String, icon: String) -> TextureRect:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.custom_minimum_size = Vector2(330, 44)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	var path := "res://assets/ui/icons/%s.svg" % icon
	if ResourceLoader.exists(path):
		ic.texture = load(path)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ic.custom_minimum_size = Vector2(32, 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = ICON_IDLE
	h.add_child(ic)
	var l := UIWidgets.label(text, 26, UIWidgets.COL_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	grid.add_child(h)
	return ic


func _slider_row(grid: GridContainer, text: String, icon: String, lo: float, hi: float, val: float, on_change: Callable, fmt: Callable) -> Control:
	var ic := _row_label(grid, text, icon)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = val
	s.custom_minimum_size = Vector2(380, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIWidgets.style_slider(s)
	s.mouse_entered.connect(func() -> void: s.grab_focus())
	grid.add_child(s)
	var vl := UIWidgets.label(fmt.call(val), 22, UIWidgets.COL_DIM)
	vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vl.custom_minimum_size = Vector2(90, 44)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(vl)
	s.value_changed.connect(func(x: float) -> void:
		vl.text = fmt.call(x)
		on_change.call(x))
	s.focus_entered.connect(_on_hover)
	_row_icons.append([ic, s])
	return s


func _cycle_row(grid: GridContainer, text: String, icon: String, opts: Array[String], idx: int, on_change: Callable) -> Control:
	var ic := _row_label(grid, text, icon)
	var c := CycleButton.new(opts, idx)
	c.custom_minimum_size = Vector2(380, 44)
	c.value_changed.connect(func(i: int) -> void:
		_play(_sfx_click)
		on_change.call(i))
	c.focus_entered.connect(_on_hover)
	grid.add_child(c)
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(90, 44)
	grid.add_child(filler)
	_row_icons.append([ic, c])
	return c


func _build_quit() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	v.add_child(UIWidgets.label("QUIT_PROMPT", 34, UIWidgets.COL_HOT, true, 4))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 40)
	v.add_child(h)
	var leave := HorrorButton.new("QUIT_LEAVE", 30)
	var stay := HorrorButton.new("QUIT_STAY", 30)
	leave.custom_minimum_size = Vector2(200, 54)
	stay.custom_minimum_size = Vector2(200, 54)
	for b: HorrorButton in [stay, leave]:
		b.hovered.connect(_on_hover)
		h.add_child(b)
	leave.pressed.connect(func() -> void:
		_play(_sfx_click)
		quit_requested.emit())
	stay.pressed.connect(func() -> void:
		_play(_sfx_back)
		panel.visible = false
		menu_box.visible = true
		btn_start.grab_focus.call_deferred())
	panel.set_meta("stay", stay)
	return panel
