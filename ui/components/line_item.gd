extends PanelContainer
## One archived message, questionnaire answer or file line.
## Clicking (or Enter/Space with keyboard focus) toggles it as suspicious text.

signal toggled(line_id: String)

var case_id: String = ""
var line_id: String = ""
var selectable: bool = true
var _selected: bool = false
var _in_evidence: bool = false
var _other: bool = false
var _hover: bool = false
var _meta: Label
var _text: Label
var _tag: Label


func setup(p_case_id: String, p_line_id: String, p_selectable: bool = true, show_meta: bool = true) -> void:
	case_id = p_case_id
	line_id = p_line_id
	selectable = p_selectable
	var info: Dictionary = CaseManager.get_line(case_id, line_id)
	_other = bool(info.get("other", false))
	# Resolve the text before counting this view: some lines change once read.
	var text: String = CaseManager.line_text(case_id, line_id)
	EvidenceManager.mark_viewed(case_id + ":" + line_id)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(2)
	add_child(v)
	var top := UI.hbox(6)
	v.add_child(top)
	_meta = UI.label(str(info.get("meta", "")) if show_meta else "", "SmallLabel", true)
	_meta.visible = show_meta and str(info.get("meta", "")) != ""
	top.add_child(_meta)
	_tag = UI.label("", "SmallLabel")
	_tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(_tag)
	_text = UI.label(text, "", true)
	v.add_child(_text)
	if selectable:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; _refresh())
		mouse_exited.connect(func() -> void: _hover = false; _refresh())
		focus_entered.connect(_refresh)
		focus_exited.connect(_refresh)
		tooltip_text = "Click to select this text as suspicious"
	_refresh()


func set_state(selected: bool, in_evidence: bool) -> void:
	_selected = selected
	_in_evidence = in_evidence
	_refresh()


func _refresh() -> void:
	if _text == null:
		return
	if _selected:
		theme_type_variation = "Selected"
		_text.theme_type_variation = "WhiteLabel"
		_meta.theme_type_variation = "WhiteSmall"
		_tag.theme_type_variation = "WhiteSmall"
		_tag.text = ">> SELECTED"
	else:
		_text.theme_type_variation = ""
		_meta.theme_type_variation = "SmallLabel"
		_tag.theme_type_variation = "SmallLabel"
		_tag.text = "[IN EVIDENCE]" if _in_evidence else ""
		if _hover or has_focus():
			theme_type_variation = "LineHover"
		elif _in_evidence:
			theme_type_variation = "Evidence"
		else:
			theme_type_variation = "LineOther" if _other else "Line"


func _gui_input(event: InputEvent) -> void:
	if not selectable:
		return
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if click or event.is_action_pressed("ui_accept"):
		accept_event()
		toggled.emit(line_id)
