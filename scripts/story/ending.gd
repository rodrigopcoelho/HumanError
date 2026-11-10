extends Control
## Ending sequence. Which ending plays is decided by GameManager.determine_ending().

const ENDINGS_FILE := "res://data/story_events/endings.json"

var _lines: Array = []
var _index: int = -1
var _box: VBoxContainer
var _button: Button
var _def: Dictionary = {}


func _ready() -> void:
	UI.full_rect(self)
	var data: Variant = SaveManager.read_data_file(ENDINGS_FILE)
	var id: String = GameManager.ending if GameManager.ending != "" else "C"
	if data is Dictionary and (data as Dictionary).get(id) is Dictionary:
		_def = data[id]
	ScreenFX.set_corruption(float(_def.get("corruption", 0.8)))
	AudioManager.silence(0.5)
	if str(_def.get("music", "")) != "":
		AudioManager.play_music(str(_def["music"]), -14.0, 6.0)
	var bg := ColorRect.new()
	bg.color = UI.C_BLACK
	UI.full_rect(bg)
	add_child(bg)
	var photo := TextureRect.new()
	photo.texture = UI.photo("res://assets/environments/%s.jpg" % str(_def.get("photo", "corridor_c")))
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.material = UI.photo_material(float(_def.get("glitch", 0.6)), float(_def.get("invert", 0.0)), 0.6)
	UI.full_rect(photo)
	add_child(photo)
	var sc := UI.scroll()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 140
	sc.offset_right = -140
	sc.offset_top = 50
	sc.offset_bottom = -90
	sc.follow_focus = true
	add_child(sc)
	_box = UI.vbox(12)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_box)
	_button = UI.button("CONTINUE", _next, "TermButton")
	_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_button.offset_left = 140
	_button.offset_top = -74
	_button.offset_bottom = -34
	_button.offset_right = 360
	add_child(_button)
	_button.grab_focus.call_deferred()
	for l: Variant in _def.get("lines", []):
		if l is Dictionary:
			if GameManager.check_requires(l.get("requires", {})):
				_lines.append(l)
		else:
			_lines.append({"text": str(l)})
	for f: Variant in _def.get("final", []):
		_lines.append({"text": str(f), "style": "final"})
	_lines.append({"text": _summary(), "style": "summary"})
	_next()


func _summary() -> String:
	var out: String = "%s\n\n" % str(_def.get("title", "END OF DEMO"))
	for id: String in CaseManager.order:
		if CaseManager.is_done(id):
			var c: Dictionary = CaseManager.get_case(id)
			out += "CASE %s  %s: %s\n" % [str(c.get("number", "")), CharacterManager.get_name_of(str(c["character_id"])), str(CaseManager.CLASS_LABELS.get(CaseManager.get_classification(id), "?"))]
	out += "INSTANCE 07: %s\n" % str(CaseManager.CLASS_LABELS.get(GameManager.final_classification, "?"))
	var acc: int = CaseManager.average_accuracy()
	out += "\nANALYST ACCURACY: %s\nCLEARANCE INDEX: %d\nFINDINGS CONFIRMED: %d\n\nThank you for playing the HUMAN ERROR demo." % ["%d%% (one result remains sealed)" % acc if acc >= 0 else "n/a", GameManager.trust, EvidenceManager.count_confirmed()]
	return out


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_button.disabled = true
		GameManager.quit_to_menu()
		return
	var l: Dictionary = _lines[_index]
	var style: String = str(l.get("style", ""))
	var variation: String = "WhiteLabel"
	if style == "final":
		variation = "TitleLabel"
		ScreenFX.pulse(0.8, 0.9)
		AudioManager.play_sfx("interference", -6.0)
	elif style == "red":
		variation = "RedHeader"
	elif style == "system" or style == "summary":
		variation = "TermLabel"
	var label := UI.label(GameManager.format_text(str(l.get("text", ""))), variation, true)
	label.focus_mode = Control.FOCUS_ALL
	_box.add_child(label)
	label.visible_ratio = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(label, "visible_ratio", 1.0, clampf(float(label.text.length()) * 0.012, 0.3, 2.0))
	label.grab_focus.call_deferred()
	_button.grab_focus.call_deferred()
	_button.text = "RETURN TO MAIN MENU" if _index == _lines.size() - 1 else "CONTINUE"
