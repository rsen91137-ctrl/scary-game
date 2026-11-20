class_name UIWidgets
extends RefCounted
## Shared look for the horror UI: fonts, colours and widget factories.

const COL_TEXT := Color(0.78, 0.75, 0.71)
const COL_DIM := Color(0.55, 0.52, 0.5, 0.85)
const COL_HOT := Color(1.0, 0.96, 0.92)
const COL_BLOOD := Color(0.62, 0.06, 0.05)

static var _font_cache := {}


## Cinzel for Latin text with a Noto Serif SC (subset) fallback for Chinese.
static func font(bold: bool = false) -> Font:
	var key := "b" if bold else "r"
	if _font_cache.has(key):
		return _font_cache[key]
	var latin := "res://assets/fonts/Cinzel-%s.ttf" % ("SemiBold" if bold else "Regular")
	var cjk := "res://assets/fonts/NotoSerifSC-%s.otf" % ("Bold" if bold else "Regular")
	var f: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(latin):
		var ff: FontFile = load(latin)
		if ResourceLoader.exists(cjk):
			var fb: Array[Font] = [load(cjk) as Font]
			ff.fallbacks = fb
		f = ff
	elif ResourceLoader.exists(cjk):
		f = load(cjk)
	_font_cache[key] = f
	return f


static func spaced(bold: bool, glyph_spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = font(bold)
	fv.spacing_glyph = glyph_spacing
	return fv


static func label(text: String, size: int, color := COL_TEXT, bold := false, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", spaced(bold, spacing) if spacing != 0 else font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func flat_box(bg: Color, border := Color(0, 0, 0, 0), bw := 0, margin := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func grabber_tex(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := absf(x - c) + absf(y - c)  # diamond
			var a := clampf((c - d) + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)


static func style_slider(s: HSlider) -> void:
	var track := flat_box(Color(1, 1, 1, 0.16))
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	var fill := flat_box(Color(0.55, 0.08, 0.06, 0.95))
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := flat_box(Color(0.8, 0.12, 0.08, 1.0))
	fill_hi.content_margin_top = 1
	fill_hi.content_margin_bottom = 1
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", grabber_tex(17, Color(0.85, 0.8, 0.76)))
	s.add_theme_icon_override("grabber_highlight", grabber_tex(19, Color(1, 0.95, 0.9)))
	s.add_theme_stylebox_override("focus", empty_box())
