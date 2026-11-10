extends Control
## Main menu: New Game, Continue, Settings, Credits, Quit.

const SettingsPanel := preload("res://ui/components/settings_panel.gd")

var _menu: VBoxContainer
var _panel_holder: Control
var _continue: Button


func _ready() -> void:
	UI.full_rect(self)
	ScreenFX.set_corruption(0.3)
	AudioManager.apply_preset("menu")
	AudioManager.play_music("drone", -22.0, 5.0)
	var bg := ColorRect.new()
	bg.color = UI.C_BLACK
	UI.full_rect(bg)
	add_child(bg)
	var photo := TextureRect.new()
	photo.texture = UI.photo("res://assets/environments/corridor_a.jpg")
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.material = UI.photo_material(0.45, 0.0, 0.35)
	UI.full_rect(photo)
	add_child(photo)

	var left := UI.vbox(10)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 70
	left.offset_top = 60
	left.offset_right = 560
	left.offset_bottom = -40
	add_child(left)
	left.add_child(UI.label("HUMAN ERROR", "TitleLabel"))
	left.add_child(UI.label("HUMAN VERIFICATION CORPORATION\nANALYST TERMINAL  -  DEMO BUILD", "TermLabel"))
	left.add_child(UI.spacer(Vector2(0, 18)))
	_menu = UI.vbox(8)
	left.add_child(_menu)
	_add_item("NEW GAME", _on_new_game)
	_continue = _add_item("CONTINUE", _on_continue)
	_add_item("SETTINGS", _on_settings)
	_add_item("CREDITS", _on_credits)
	_add_item("QUIT", func() -> void: get_tree().quit())
	_continue.disabled = not SaveManager.has_save()
	var summary: String = SaveManager.get_save_summary()
	left.add_child(UI.label(summary if summary != "" else "No saved session.", "TermSmall", true))
	var seen: Array = SaveManager.settings.get("endings_seen", [])
	var marks: Array[String] = []
	for e: String in ["A", "B", "C"]:
		marks.append(e if seen.has(e) else "-")
	left.add_child(UI.label("ENDINGS RECORDED:  " + "  ".join(marks), "TermSmall"))

	_panel_holder = CenterContainer.new()
	_panel_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_holder.offset_left = 520
	_panel_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_holder)
	var foot := UI.label("Contains psychological horror themes. Screen effects can be reduced in SETTINGS.", "TermSmall")
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 70
	foot.offset_top = -34
	foot.offset_bottom = -12
	add_child(foot)
	(_menu.get_child(1 if not _continue.disabled else 0) as Control).grab_focus.call_deferred()


func _add_item(text: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, "TermButton")
	b.custom_minimum_size = Vector2(300, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_menu.add_child(b)
	return b


func _show_panel(content: Control) -> void:
	UI.clear(_panel_holder)
	var frame := UI.panel("WindowFrame")
	frame.add_child(UI.margin(content, 14))
	_panel_holder.add_child(frame)


func _close_panel() -> void:
	UI.clear(_panel_holder)


func _on_new_game() -> void:
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 440
	v.add_child(UI.label("NEW ANALYST REGISTRATION", "HeaderLabel"))
	v.add_child(UI.label("Enter the name you will work under. It will appear on your employee record.", "", true))
	var edit := LineEdit.new()
	edit.placeholder_text = "Analyst name"
	edit.max_length = 24
	v.add_child(edit)
	if SaveManager.has_save():
		v.add_child(UI.label("WARNING: starting a new game replaces the existing saved session.", "RedLabel", true))
	var row := UI.hbox(8)
	v.add_child(row)
	var begin := func() -> void: GameManager.new_game(edit.text)
	row.add_child(UI.button("BEGIN EMPLOYMENT", begin, "DangerButton"))
	row.add_child(UI.button("CANCEL", _close_panel))
	edit.text_submitted.connect(func(_t: String) -> void: begin.call())
	_show_panel(v)
	edit.grab_focus.call_deferred()


func _on_continue() -> void:
	if not GameManager.continue_game():
		var v := UI.vbox(10)
		v.custom_minimum_size.x = 420
		v.add_child(UI.label("COULD NOT LOAD SESSION", "RedHeader"))
		v.add_child(UI.label(SaveManager.last_error, "", true))
		v.add_child(UI.button("OK", _close_panel))
		_show_panel(v)


func _on_settings() -> void:
	var s: VBoxContainer = SettingsPanel.new()
	s.custom_minimum_size.x = 520
	s.connect("back_pressed", _close_panel)
	_show_panel(s)


func _on_credits() -> void:
	var v := UI.vbox(8)
	v.custom_minimum_size = Vector2(560, 420)
	v.add_child(UI.label("CREDITS AND LICENSES", "HeaderLabel"))
	var r := UI.rich()
	var text: String = "HUMAN ERROR - demo.\n\nPhotography: public-domain and CC0 photographs from Wikimedia Commons, heavily modified.\nFonts: IBM Plex Mono and VT323 (SIL Open Font License).\nAudio: original, generated for this project (CC0).\n\nFull attribution: documentation/ASSET_MANIFEST.md"
	var manifest: String = "res://documentation/ASSET_MANIFEST.md"
	if FileAccess.file_exists(manifest):
		text += "\n\n----\n\n" + FileAccess.get_file_as_string(manifest).replace("[", "(").replace("]", ")")
	r.text = text
	v.add_child(r)
	v.add_child(UI.button("BACK", _close_panel))
	_show_panel(v)
