extends Control
## Placeholder for the game itself (this milestone only covers the main menu).
## Black screen, a slow heartbeat, chapter card, then back to the menu.

var _lines: Array[Control] = []
var _can_leave := false
var _hb: AudioStreamPlayer
var _t := 0.0
var _beat := 1.2


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_theme_constant_override("separation", 26)
	add_child(v)
	for spec: Array in [["PRO_CHAPTER", 30, UIWidgets.COL_DIM], ["LOGO", 0, Color.WHITE], ["PRO_WIP", 28, UIWidgets.COL_TEXT], ["PRO_PRESS", 20, Color(0.5, 0.48, 0.46)]]:
		var c: Control
		if spec[0] == "LOGO":
			var tr := TextureRect.new()
			tr.texture = load("res://assets/ui/logo_mask.png")
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			tr.custom_minimum_size = Vector2(820, 150)
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/logo.gdshader")
			m.set_shader_parameter("light", 0.6)
			tr.material = m
			c = tr
		else:
			c = UIWidgets.label(spec[0], spec[1], spec[2], false, 2)
		c.modulate.a = 0.0
		v.add_child(c)
		_lines.append(c)
	_hb = AudioStreamPlayer.new()
	_hb.bus = "Body"
	if ResourceLoader.exists("res://assets/audio/heart_lub.ogg"):
		_hb.stream = load("res://assets/audio/heart_lub.ogg")
	add_child(_hb)
	var tw := create_tween()
	tw.tween_interval(1.2)
	for i in _lines.size():
		tw.tween_property(_lines[i], "modulate:a", 1.0, 1.6)
		tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: _can_leave = true)


func _process(delta: float) -> void:
	_t += delta
	_beat -= delta
	if _beat <= 0.0:
		_beat = 1.35
		if _hb.stream:
			_hb.volume_db = -10.0
			_hb.play()


func _input(event: InputEvent) -> void:
	if not _can_leave:
		return
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		_can_leave = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.8)
		tw.tween_callback(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
