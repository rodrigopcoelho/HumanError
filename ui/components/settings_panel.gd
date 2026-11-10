extends VBoxContainer
## Settings: text size, audio volumes, display mode and accessibility options.
## Used by the main menu, the SHUTDOWN application and the office pause menu.

signal back_pressed

var show_back: bool = true
var _toggles: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UI.label("SETTINGS", "HeaderLabel"))
	_slider("TEXT SIZE", "text_scale", 0.8, 1.5, 0.05, true)
	_slider("MASTER VOLUME", "master_volume", 0.0, 1.0, 0.05, false)
	_slider("MUSIC VOLUME", "music_volume", 0.0, 1.0, 0.05, false)
	_slider("EFFECTS VOLUME", "sfx_volume", 0.0, 1.0, 0.05, false)
	_toggle("FULLSCREEN", "fullscreen")
	add_child(UI.label("ACCESSIBILITY", "HeaderLabel"))
	_toggle("SCREEN DISTORTION (glitches, colour fringing)", "screen_distortion")
	_toggle("LIGHT FLICKER", "flicker")
	_toggle("VISUAL NOISE (grain, scanlines)", "visual_noise")
	add_child(UI.label("Turning these off never hides gameplay information.", "SmallLabel", true))
	if show_back:
		var b := UI.button("BACK", func() -> void: back_pressed.emit())
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_child(b)


func _slider(title: String, key: String, lo: float, hi: float, step: float, is_scale: bool) -> void:
	var row := UI.hbox(10)
	var l := UI.label(title)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(SaveManager.settings.get(key, hi))
	s.custom_minimum_size = Vector2(220, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := UI.label("")
	val.custom_minimum_size.x = 60
	row.add_child(val)
	var fmt := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		SaveManager.set_setting(key, v)
		if not is_scale:
			AudioManager.play_sfx("click", -6.0))
	add_child(row)


func _toggle(title: String, key: String) -> void:
	var b := UI.button("", func() -> void:
		SaveManager.set_setting(key, not bool(SaveManager.settings.get(key, false)))
		_refresh_toggles())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("title", title)
	_toggles[key] = b
	add_child(b)
	_refresh_toggles()


func _refresh_toggles() -> void:
	for key: String in _toggles:
		var b: Button = _toggles[key]
		b.text = "[%s] %s" % ["X" if bool(SaveManager.settings.get(key, false)) else " ", str(b.get_meta("title"))]
