extends Node
## UI (autoload): builds the HVC TERMINAL theme and offers small widget helpers.
## All font sizes flow through the Theme so text scaling updates live.

const C_DARK := Color("14251d")
const C_GREEN := Color("9abf9a")
const C_BEIGE := Color("c6bfa8")
const C_WHITE := Color("e6e2d6")
const C_BLACK := Color("090d0b")
const C_RED := Color("9e2929")
const C_SHADE := Color("9a947f")

const BASE_SIZES := {
	"TitleLabel": 54, "BigLabel": 26, "HeaderLabel": 17, "SmallLabel": 12,
	"TermLabel": 15, "TermSmall": 12, "RedLabel": 15, "WhiteLabel": 15,
	"WhiteSmall": 12, "RedHeader": 17, "TermHeader": 17, "TermBig": 26,
}
const BASE_SIZE := 15

var theme: Theme = Theme.new()
var font_body: Font
var font_bold: Font
var font_title: Font
var text_scale: float = 1.0


func _ready() -> void:
	_load_fonts()
	_build_theme()
	apply_scale(float(SaveManager.settings.get("text_scale", 1.0)))
	get_tree().root.theme = theme
	# Themes only propagate through Control/Window parents. Controls that hang off a
	# CanvasLayer or a Node3D (HUDs, the dialogue box) get the theme assigned directly.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Control and not (node.get_parent() is Control) and (node as Control).theme == null:
		(node as Control).theme = theme


func _load_font(path: String, fallback_names: PackedStringArray, bold: bool = false) -> Font:
	if ResourceLoader.exists(path):
		var f: Font = load(path) as Font
		if f != null:
			return f
	var sf := SystemFont.new()
	sf.font_names = fallback_names
	sf.font_weight = 700 if bold else 400
	return sf


func _load_fonts() -> void:
	var mono := PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	font_body = _load_font("res://assets/fonts/IBMPlexMono-Regular.ttf", mono)
	font_bold = _load_font("res://assets/fonts/IBMPlexMono-Bold.ttf", mono, true)
	font_title = _load_font("res://assets/fonts/VT323-Regular.ttf", mono, true)


func sb(bg: Color, border: Color = C_BLACK, bw: int = 1, pad: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s


func _bevel(bg: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := sb(bg, C_BLACK, 1, 6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	if pressed:
		s.border_width_left = 2
		s.border_width_top = 2
	else:
		s.border_width_right = 2
		s.border_width_bottom = 2
	return s


func _button_styles(type: String, normal: Color, hover: Color, pressed: Color, font: Color, font_pressed: Color) -> void:
	theme.set_stylebox("normal", type, _bevel(normal))
	theme.set_stylebox("hover", type, _bevel(hover))
	theme.set_stylebox("pressed", type, _bevel(pressed, true))
	theme.set_stylebox("hover_pressed", type, _bevel(pressed, true))
	theme.set_stylebox("disabled", type, _bevel(normal.darkened(0.12)))
	var focus := sb(Color(0, 0, 0, 0), C_RED, 2, 6)
	focus.draw_center = false
	theme.set_stylebox("focus", type, focus)
	for c: String in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(c, type, font)
	for c: String in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(c, type, font_pressed)
	theme.set_color("font_disabled_color", type, font.lerp(normal, 0.6))


func _build_theme() -> void:
	theme.default_font = font_body
	# Panels
	theme.set_stylebox("panel", "PanelContainer", sb(C_BEIGE, C_BLACK, 1, 6))
	theme.set_stylebox("panel", "Panel", sb(C_BEIGE, C_BLACK, 1, 6))
	var variations := {
		"Sunken": sb(C_WHITE, C_SHADE, 2, 6),
		"Term": sb(C_BLACK, C_GREEN, 1, 10),
		"TitleBar": sb(C_DARK, C_DARK, 0, 4),
		"TaskBar": sb(C_BEIGE, C_BLACK, 1, 3),
		"WindowFrame": sb(C_BEIGE, C_BLACK, 2, 3),
		"Selected": sb(C_DARK, C_RED, 2, 6),
		"Line": sb(C_WHITE, C_SHADE, 1, 6),
		"LineOther": sb(C_BEIGE.lightened(0.15), C_SHADE, 1, 6),
		"LineHover": sb(Color("f3f0e6"), C_DARK, 1, 6),
		"Evidence": sb(Color("d8d2bc"), C_DARK, 1, 6),
		"Dim": sb(Color(0.03, 0.05, 0.04, 0.78), C_BLACK, 0, 0),
		"Toast": sb(C_BEIGE, C_BLACK, 2, 8),
		"ToastError": sb(C_RED, C_BLACK, 2, 8),
		"ToastTerm": sb(C_BLACK, C_GREEN, 2, 8),
		"Clear": sb(Color(0, 0, 0, 0), C_BLACK, 0, 0),
	}
	for v: String in variations:
		theme.set_type_variation(v, "PanelContainer")
		theme.set_stylebox("panel", v, variations[v])
	# Buttons
	_button_styles("Button", C_BEIGE.lightened(0.12), C_WHITE, C_DARK, C_BLACK, C_WHITE)
	_button_styles("OptionButton", C_BEIGE.lightened(0.12), C_WHITE, C_DARK, C_BLACK, C_WHITE)
	theme.set_type_variation("TermButton", "Button")
	_button_styles("TermButton", C_BLACK, C_DARK, C_GREEN, C_GREEN, C_BLACK)
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var tb: StyleBoxFlat = theme.get_stylebox(st, "TermButton") as StyleBoxFlat
		tb.border_color = C_GREEN
	theme.set_type_variation("DangerButton", "Button")
	_button_styles("DangerButton", C_RED, C_RED.lightened(0.15), C_BLACK, C_WHITE, C_WHITE)
	theme.set_type_variation("FlatButton", "Button")
	_button_styles("FlatButton", C_DARK, C_DARK.lightened(0.12), C_GREEN, C_WHITE, C_BLACK)
	# Labels
	theme.set_color("font_color", "Label", C_BLACK)
	var label_vars := {
		"TitleLabel": [C_WHITE, font_title], "BigLabel": [C_BLACK, font_title],
		"HeaderLabel": [C_BLACK, font_bold], "SmallLabel": [Color("3c3f37"), font_body],
		"TermLabel": [C_GREEN, font_body], "TermSmall": [C_GREEN.darkened(0.2), font_body],
		"RedLabel": [C_RED, font_bold], "WhiteLabel": [C_WHITE, font_body],
		"WhiteSmall": [C_WHITE.darkened(0.15), font_body], "RedHeader": [C_RED, font_bold],
		"TermHeader": [C_GREEN, font_bold], "TermBig": [C_GREEN, font_title],
	}
	for v: String in label_vars:
		theme.set_type_variation(v, "Label")
		theme.set_color("font_color", v, label_vars[v][0])
		theme.set_font("font", v, label_vars[v][1])
	# Rich text
	for t: String in ["RichTextLabel", "TermRich"]:
		if t != "RichTextLabel":
			theme.set_type_variation(t, "RichTextLabel")
		theme.set_font("normal_font", t, font_body)
		theme.set_font("bold_font", t, font_bold)
		theme.set_font("mono_font", t, font_body)
		theme.set_font("italics_font", t, font_body)
		theme.set_font("bold_italics_font", t, font_bold)
	theme.set_color("default_color", "RichTextLabel", C_BLACK)
	theme.set_color("default_color", "TermRich", C_GREEN)
	# Text inputs
	for t: String in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", t, sb(C_WHITE, C_SHADE, 2, 6))
		theme.set_stylebox("focus", t, sb(C_WHITE, C_DARK, 2, 6))
		theme.set_stylebox("read_only", t, sb(C_BEIGE, C_SHADE, 2, 6))
		theme.set_color("font_color", t, C_BLACK)
		theme.set_color("font_placeholder_color", t, Color("7d7a6c"))
		theme.set_color("caret_color", t, C_BLACK)
		theme.set_color("selection_color", t, C_GREEN)
		theme.set_color("font_selected_color", t, C_BLACK)
	theme.set_type_variation("TermEdit", "LineEdit")
	theme.set_stylebox("normal", "TermEdit", sb(C_BLACK, C_GREEN, 1, 6))
	theme.set_stylebox("focus", "TermEdit", sb(C_BLACK, C_GREEN, 2, 6))
	theme.set_color("font_color", "TermEdit", C_GREEN)
	theme.set_color("caret_color", "TermEdit", C_GREEN)
	theme.set_color("font_placeholder_color", "TermEdit", C_GREEN.darkened(0.5))
	# Lists
	theme.set_stylebox("panel", "ItemList", sb(C_WHITE, C_SHADE, 2, 4))
	theme.set_stylebox("focus", "ItemList", sb(Color(0, 0, 0, 0), C_DARK, 0, 4))
	for st: String in ["selected", "selected_focus", "cursor", "cursor_unfocused"]:
		theme.set_stylebox(st, "ItemList", sb(C_DARK, C_DARK, 0, 2))
	theme.set_stylebox("hovered", "ItemList", sb(C_BEIGE, C_BEIGE, 0, 2))
	theme.set_color("font_color", "ItemList", C_BLACK)
	theme.set_color("font_hovered_color", "ItemList", C_BLACK)
	theme.set_color("font_selected_color", "ItemList", C_WHITE)
	theme.set_color("font_hovered_selected_color", "ItemList", C_WHITE)
	theme.set_constant("v_separation", "ItemList", 6)
	# Popup menus (OptionButton)
	theme.set_stylebox("panel", "PopupMenu", sb(C_WHITE, C_BLACK, 2, 4))
	theme.set_stylebox("hover", "PopupMenu", sb(C_DARK, C_DARK, 0, 2))
	theme.set_color("font_color", "PopupMenu", C_BLACK)
	theme.set_color("font_hover_color", "PopupMenu", C_WHITE)
	# Scrollbars
	for t: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", t, sb(C_SHADE, C_SHADE, 0, 5))
		theme.set_stylebox("grabber", t, sb(C_DARK, C_BLACK, 1, 5))
		theme.set_stylebox("grabber_highlight", t, sb(C_DARK.lightened(0.15), C_BLACK, 1, 5))
		theme.set_stylebox("grabber_pressed", t, sb(C_BLACK, C_BLACK, 1, 5))
	# Slider / progress
	theme.set_stylebox("slider", "HSlider", sb(C_SHADE, C_BLACK, 1, 3))
	theme.set_stylebox("grabber_area", "HSlider", sb(C_DARK, C_BLACK, 1, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", sb(C_DARK, C_BLACK, 1, 3))
	var grab := _solid_texture(12, 20, C_DARK)
	theme.set_icon("grabber", "HSlider", grab)
	theme.set_icon("grabber_highlight", "HSlider", _solid_texture(12, 20, C_RED))
	theme.set_icon("grabber_disabled", "HSlider", grab)
	theme.set_stylebox("background", "ProgressBar", sb(C_WHITE, C_SHADE, 2, 2))
	theme.set_stylebox("fill", "ProgressBar", sb(C_DARK, C_DARK, 0, 2))
	theme.set_color("font_color", "ProgressBar", C_RED)
	theme.set_stylebox("panel", "TooltipPanel", sb(C_WHITE, C_BLACK, 1, 4))
	theme.set_color("font_color", "TooltipLabel", C_BLACK)
	theme.set_constant("separation", "HSplitContainer", 8)


func _solid_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Applies a global text scale (0.8 - 1.6). Everything using the theme updates at once.
func apply_scale(s: float) -> void:
	text_scale = clampf(s, 0.8, 1.6)
	theme.default_font_size = roundi(BASE_SIZE * text_scale)
	for v: String in BASE_SIZES:
		theme.set_font_size("font_size", v, roundi(int(BASE_SIZES[v]) * text_scale))
	for t: String in ["RichTextLabel", "TermRich"]:
		for k: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
			theme.set_font_size(k, t, roundi(BASE_SIZE * text_scale))


# ---------------------------------------------------------------- helpers

func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func button(text: String, callback: Callable = Callable(), variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: AudioManager.play_sfx("click"))
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


func rich(variation: String = "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.selection_enabled = true
	if variation != "":
		r.theme_type_variation = variation
	return r


func expand(c: Control, h: bool = true, v: bool = true) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func margin(child: Control, m: int = 8) -> MarginContainer:
	var mc := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, m)
	mc.add_child(child)
	return mc


func spacer(min_size: Vector2 = Vector2.ZERO) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func clear(node: Node) -> void:
	for ch: Node in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Loads a photograph if it exists, otherwise returns a generated placeholder so the
## game never silently depends on a missing (or unlicensed) image.
func photo(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			return t
	return placeholder_texture()


var _placeholder: ImageTexture

func placeholder_texture() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(64, 80, false, Image.FORMAT_RGB8)
		for y: int in 80:
			for x: int in 64:
				var v: float = 0.10 + 0.08 * float((x / 8 + y / 8) % 2) + randf() * 0.05
				img.set_pixel(x, y, Color(v * 0.8, v * 1.1, v * 0.85))
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


func photo_material(intensity: float = 0.25, invert: float = 0.0, darken: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/photo_glitch.gdshader") as Shader
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("invert", invert)
	m.set_shader_parameter("darken", darken)
	m.set_shader_parameter("motion", 1.0 if bool(SaveManager.settings.get("screen_distortion", true)) else 0.0)
	return m


## JSON numbers arrive as floats; show whole numbers without a trailing ".0".
func num(v: Variant) -> String:
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return str(v)
