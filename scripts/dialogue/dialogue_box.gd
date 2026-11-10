extends CanvasLayer
## Default dialogue presentation: a box at the bottom of the screen with
## typewriter text and choice buttons. Mouse and keyboard both work.

var _speaker: Label
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _tween: Tween
var _typing: bool = false
var _shown_frame: int = 0


func _ready() -> void:
	layer = 50
	var blocker := Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(_on_blocker_input)
	add_child(blocker)
	var panel := UI.panel("Term")
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = -250
	panel.offset_bottom = -30
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var v := UI.vbox(6)
	panel.add_child(v)
	_speaker = UI.label("", "TermHeader")
	v.add_child(_speaker)
	_text = UI.label("", "WhiteLabel", true)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text)
	_choices = UI.vbox(4)
	v.add_child(_choices)
	_hint = UI.label("[ click or press Enter ]", "TermSmall")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)
	DialogueManager.node_shown.connect(_on_node)


func _on_node(node: Dictionary) -> void:
	if DialogueManager.terminal_mode:
		return
	_shown_frame = Engine.get_process_frames()
	_speaker.text = str(node.get("speaker", ""))
	_speaker.visible = _speaker.text != ""
	_text.text = str(node.get("text", ""))
	_text.theme_type_variation = "RedLabel" if str(node.get("style", "")) == "red" else "WhiteLabel"
	UI.clear(_choices)
	var choices: Array = node.get("choices", [])
	_hint.visible = choices.is_empty()
	for i: int in choices.size():
		var b := UI.button(str(choices[i].get("text", "")), func() -> void: DialogueManager.choose(i), "TermButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.visible = false
		_choices.add_child(b)
	_text.visible_ratio = 0.0
	_typing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text, "visible_ratio", 1.0, clampf(float(_text.text.length()) * 0.018, 0.2, 3.0))
	_tween.tween_callback(_finish_typing)


func _finish_typing() -> void:
	_typing = false
	_text.visible_ratio = 1.0
	var first: bool = true
	for b: Node in _choices.get_children():
		(b as Control).visible = true
		if first:
			first = false
			(b as Control).grab_focus.call_deferred()


func _press() -> void:
	if Engine.get_process_frames() == _shown_frame:
		return
	if _typing:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_finish_typing()
	elif _choices.get_child_count() == 0:
		AudioManager.play_sfx("click", -10.0)
		DialogueManager.advance()


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_press()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_E):
		get_viewport().set_input_as_handled()
		_press()
