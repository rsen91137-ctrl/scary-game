class_name CycleButton
extends Button
## "‹  value  ›" selector. Click / Enter / Right = next, Left = previous.

signal value_changed(index: int)

var options: Array[String] = []
var index := 0


func _init(opts: Array[String] = [], start := 0) -> void:
	options = opts
	index = start
	flat = true
	focus_mode = Control.FOCUS_ALL
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_font_override("font", UIWidgets.font(false))
	add_theme_font_size_override("font_size", 26)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, UIWidgets.empty_box())
	var focus := UIWidgets.flat_box(Color(0.5, 0.05, 0.04, 0.18), Color(0.7, 0.1, 0.07, 0.6), 1)
	add_theme_stylebox_override("focus", focus)
	add_theme_color_override("font_color", UIWidgets.COL_TEXT)
	add_theme_color_override("font_hover_color", UIWidgets.COL_HOT)
	add_theme_color_override("font_focus_color", UIWidgets.COL_HOT)
	custom_minimum_size = Vector2(260, 44)
	pressed.connect(func() -> void: step(1))
	mouse_entered.connect(func() -> void: grab_focus())
	_refresh()


func step(d: int) -> void:
	if options.is_empty():
		return
	index = wrapi(index + d, 0, options.size())
	_refresh()
	value_changed.emit(index)


func set_index(i: int) -> void:
	index = clampi(i, 0, maxi(options.size() - 1, 0))
	_refresh()


func _refresh() -> void:
	if options.is_empty():
		text = ""
		return
	text = "‹    %s    ›" % tr(options[index])


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()
