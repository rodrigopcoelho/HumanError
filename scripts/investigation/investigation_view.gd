extends VBoxContainer
## VERIFICATION WORKBENCH: the comparison interface.
## Character profile above, historical information on the left, new questionnaire
## answers on the right, evidence notes below.

const LineItem := preload("res://ui/components/line_item.gd")

var desktop: Node
var case_id: String = ""
var _left_mode: String = "messages"
var _items: Dictionary = {}          # line id -> LineItem
var _left_list: VBoxContainer
var _right_list: VBoxContainer
var _tab_messages: Button
var _tab_files: Button
var _selection_label: Label
var _feedback: Label
var _requests_label: Label
var _category: OptionButton
var _note: LineEdit
var _flag_button: Button
var _evidence_list: VBoxContainer
var _evidence_header: Label
var _submit: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	EvidenceManager.selection_changed.connect(_on_selection_changed)
	EvidenceManager.evidence_added.connect(_on_evidence_added)


func open_args(args: Dictionary) -> void:
	var id: String = str(args.get("case_id", case_id))
	if id == "" or CaseManager.get_case(id).is_empty():
		return
	case_id = id
	GameManager.current_case = id
	_left_mode = "messages"
	_rebuild()
	StoryDirector.trigger("case_opened:" + id)
	if not GameManager.has_flag("workbench_help_seen"):
		GameManager.set_flag("workbench_help_seen")
		_show_help.call_deferred()


func _case() -> Dictionary:
	return CaseManager.get_case(case_id)


func _closed() -> bool:
	return CaseManager.is_done(case_id)


# ---------------------------------------------------------------- build

func _rebuild() -> void:
	UI.clear(self)
	_items.clear()
	var c: Dictionary = _case()
	var ch: Dictionary = CharacterManager.get_character(str(c["character_id"]))
	if desktop != null:
		desktop.call("set_window_title", "workbench", "VERIFICATION WORKBENCH  -  CASE %s" % str(c.get("number", "")))

	# --- profile strip
	var top := UI.hbox(10)
	add_child(top)
	var portrait := TextureRect.new()
	portrait.texture = CharacterManager.get_portrait(str(c["character_id"]))
	portrait.custom_minimum_size = Vector2(84, 105)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.material = UI.photo_material(0.12 + 0.07 * float(GameManager.day))
	var pframe := UI.panel("Sunken")
	pframe.add_child(portrait)
	top.add_child(pframe)
	var info := UI.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UI.label("%s   -   CASE %s: %s" % [str(ch.get("name", "?")).to_upper(), str(c.get("number", "")), str(c["title"]).to_upper()], "HeaderLabel"))
	info.add_child(UI.label("Age: %s    Occupation: %s    Difficulty: %s    Status: %s" % [UI.num(ch.get("age", "?")), str(ch.get("occupation", "?")), str(c["difficulty"]), CaseManager.status_label(case_id)], "SmallLabel", true))
	info.add_child(UI.label("LINGUISTIC BASELINE: " + str(ch.get("writing_style", "")), "SmallLabel", true))
	info.add_child(UI.label("HR PROFILE: " + str(ch.get("personality", "")), "SmallLabel", true))
	var side := UI.vbox(4)
	top.add_child(side)
	side.add_child(UI.button("HOW TO INVESTIGATE", _show_help))
	side.add_child(UI.button("OPEN MESSAGE ARCHIVE", func() -> void:
		if desktop != null:
			desktop.call("open_app", "archive", {"case_id": case_id})))
	_requests_label = UI.label("", "HeaderLabel")
	side.add_child(_requests_label)

	# --- comparison
	var split := HSplitContainer.new()
	UI.expand(split)
	add_child(split)
	var left := UI.panel("Sunken")
	UI.expand(left)
	split.add_child(left)
	var lv := UI.vbox(4)
	left.add_child(lv)
	var tabs := UI.hbox(4)
	lv.add_child(tabs)
	_tab_messages = UI.button("HISTORICAL MESSAGES", func() -> void: _set_left_mode("messages"))
	_tab_files = UI.button("SUPPORTING FILES", func() -> void: _set_left_mode("files"))
	_tab_messages.toggle_mode = true
	_tab_files.toggle_mode = true
	tabs.add_child(_tab_messages)
	tabs.add_child(_tab_files)
	tabs.add_child(UI.label("  ON FILE (before)", "SmallLabel"))
	var ls := UI.scroll()
	lv.add_child(ls)
	_left_list = UI.vbox(5)
	_left_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_left_list)

	var right := UI.panel("Sunken")
	UI.expand(right)
	split.add_child(right)
	var rv := UI.vbox(4)
	right.add_child(rv)
	rv.add_child(UI.label("NEW QUESTIONNAIRE  -  %s  (now)" % str(c.get("form", "FORM CV-1")), "HeaderLabel"))
	var rs := UI.scroll()
	rv.add_child(rs)
	_right_list = UI.vbox(5)
	_right_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_right_list)

	# --- evidence notes
	var bottom := UI.hbox(8)
	bottom.custom_minimum_size.y = 186
	add_child(bottom)
	var notes := UI.panel()
	notes.custom_minimum_size.x = 470
	bottom.add_child(notes)
	var nv := UI.vbox(4)
	notes.add_child(nv)
	nv.add_child(UI.label("EVIDENCE NOTES", "HeaderLabel"))
	_selection_label = UI.label("", "SmallLabel", true)
	_selection_label.custom_minimum_size.y = 34
	nv.add_child(_selection_label)
	var row := UI.hbox(6)
	nv.add_child(row)
	_category = OptionButton.new()
	for cat: String in CaseManager.CATEGORIES:
		_category.add_item(str(CaseManager.CATEGORY_LABELS[cat]))
	_category.tooltip_text = "What kind of inconsistency is this?"
	row.add_child(_category)
	_note = LineEdit.new()
	_note.placeholder_text = "Your note (optional)"
	_note.max_length = 140
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_note)
	var row2 := UI.hbox(6)
	nv.add_child(row2)
	_flag_button = UI.button("FLAG AS EVIDENCE", _on_flag_pressed)
	row2.add_child(_flag_button)
	row2.add_child(UI.button("CLEAR SELECTION", func() -> void: EvidenceManager.clear_selection(case_id)))
	_feedback = UI.label("", "RedLabel", true)
	nv.add_child(_feedback)

	var coll := UI.panel("Sunken")
	UI.expand(coll)
	bottom.add_child(coll)
	var cv := UI.vbox(4)
	coll.add_child(cv)
	_evidence_header = UI.label("", "HeaderLabel")
	cv.add_child(_evidence_header)
	var es := UI.scroll()
	cv.add_child(es)
	_evidence_list = UI.vbox(5)
	_evidence_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	es.add_child(_evidence_list)

	# --- footer
	var foot := UI.hbox(8)
	add_child(foot)
	var hint := UI.label("Select up to %d lines, choose a category, then flag them. Not every inconsistency means the subject is an imitation." % EvidenceManager.MAX_SELECTION, "SmallLabel", true)
	foot.add_child(hint)
	_submit = UI.button("SUBMIT DECISION", func() -> void:
		if desktop != null:
			desktop.call("open_classification", case_id), "DangerButton")
	foot.add_child(_submit)

	_fill_left()
	_fill_right()
	_refresh_evidence()
	_refresh_state()


func _set_left_mode(mode: String) -> void:
	_left_mode = mode
	_fill_left()
	_refresh_state()


func _add_line(parent: Control, line_id: String, show_meta: bool = true) -> void:
	var item: PanelContainer = LineItem.new()
	parent.add_child(item)
	item.call("setup", case_id, line_id, not _closed(), show_meta)
	item.connect("toggled", _on_line_toggled)
	_items[line_id] = item


func _fill_left() -> void:
	for id: String in _items.keys():
		if (_items[id] as Node).get_parent() == _left_list:
			_items.erase(id)
	UI.clear(_left_list)
	var c: Dictionary = _case()
	_tab_messages.set_pressed_no_signal(_left_mode == "messages")
	_tab_files.set_pressed_no_signal(_left_mode == "files")
	if _left_mode == "messages":
		var threads: Dictionary = c.get("threads", {})
		var last_thread: String = "~none~"
		for m: Variant in c["historical_messages"]:
			var t: String = str(m.get("thread", ""))
			if t != last_thread:
				last_thread = t
				_left_list.add_child(UI.label(str(threads.get(t, "ARCHIVE")).to_upper(), "HeaderLabel", true))
			_add_line(_left_list, str(m["id"]))
	else:
		var docs: Array = CaseManager.get_documents(case_id)
		if docs.is_empty():
			_left_list.add_child(UI.label("No supporting files attached to this case.", "SmallLabel"))
		for doc: Variant in docs:
			_left_list.add_child(UI.label(GameManager.format_text(str(doc.get("title", "FILE"))).to_upper(), "HeaderLabel", true))
			if doc.has("note"):
				_left_list.add_child(UI.label(str(doc["note"]), "SmallLabel", true))
			for l: Variant in doc["lines"]:
				_add_line(_left_list, str(l["id"]), false)


func _fill_right() -> void:
	UI.clear(_right_list)
	for q: Variant in _case()["questionnaire_answers"]:
		_add_line(_right_list, str(q["id"]))


# ---------------------------------------------------------------- state

func _refresh_state() -> void:
	if _selection_label == null:
		return
	var sel: Array = EvidenceManager.get_selection(case_id)
	var used: Dictionary = EvidenceManager.lines_in_evidence(case_id)
	for id: String in _items:
		if is_instance_valid(_items[id]):
			(_items[id] as Node).call("set_state", sel.has(id), used.has(id))
	if sel.is_empty():
		_selection_label.text = "Nothing selected. Click a message, an answer or a file line that seems wrong - or pair an old line with a new one that contradicts it."
	else:
		var parts: Array[String] = []
		for id: Variant in sel:
			var t: String = CaseManager.line_text(case_id, str(id))
			parts.append("\"%s\"" % (t.substr(0, 46) + ("..." if t.length() > 46 else "")))
		_selection_label.text = "SELECTED (%d/%d): %s" % [sel.size(), EvidenceManager.MAX_SELECTION, "  +  ".join(parts)]
	var left: int = EvidenceManager.requests_left(case_id)
	_requests_label.text = "ANALYSIS REQUESTS: %d / %d" % [left, CaseManager.get_budget(case_id)]
	var closed: bool = _closed()
	_flag_button.disabled = closed or sel.is_empty()
	_submit.disabled = closed
	_submit.text = "CASE CLOSED" if closed else "SUBMIT DECISION"
	if closed:
		_feedback.text = "This case is closed. The record is read-only."


func _refresh_evidence() -> void:
	UI.clear(_evidence_list)
	var items: Array = EvidenceManager.get_for_case(case_id)
	_evidence_header.text = "EVIDENCE COLLECTION (%d)" % items.size()
	if items.is_empty():
		_evidence_list.add_child(UI.label("No evidence collected yet.", "SmallLabel"))
	for i: int in range(items.size() - 1, -1, -1):
		_evidence_list.add_child(make_evidence_card(items[i]))


## Shared with the CASE DATABASE evidence locker.
static func make_evidence_card(item: Dictionary) -> Control:
	var confirmed: bool = str(item.get("clue_id", "")) != ""
	var p := UI.panel("Evidence" if confirmed else "Line")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(2)
	p.add_child(v)
	v.add_child(UI.label(str(item.get("title", "")), "HeaderLabel", true))
	var cat: String = str(CaseManager.CATEGORY_LABELS.get(str(item.get("category", "")), "?"))
	var meta: String = "%s   |   SEVERITY: %s" % [cat.to_upper(), str(item.get("severity", "?"))]
	var pc: String = str(item.get("player_category", ""))
	if confirmed and pc != "" and pc != str(item.get("category", "")):
		meta += "   |   you filed it as: %s" % str(CaseManager.CATEGORY_LABELS.get(pc, pc))
	v.add_child(UI.label(meta, "RedLabel" if str(item.get("severity", "")) == "CRITICAL" else "SmallLabel", true))
	v.add_child(UI.label(str(item.get("description", "")), "", true))
	for q: Variant in item.get("quotes", []):
		v.add_child(UI.label("  > " + str(q), "SmallLabel", true))
	v.add_child(UI.label("SOURCE: " + str(item.get("source", "")), "SmallLabel", true))
	if str(item.get("note", "")) != "":
		v.add_child(UI.label("YOUR NOTE: " + str(item["note"]), "SmallLabel", true))
	return p


# ---------------------------------------------------------------- input

func _on_line_toggled(line_id: String) -> void:
	if _closed():
		return
	if EvidenceManager.toggle_select(case_id, line_id):
		AudioManager.play_sfx("select", -8.0)
	else:
		_feedback.text = "Selection full (%d lines). Clear it or flag it first." % EvidenceManager.MAX_SELECTION
		AudioManager.play_sfx("error", -10.0)


func _on_selection_changed(changed_case: String) -> void:
	if changed_case == case_id and is_inside_tree():
		_refresh_state()


func _on_evidence_added(item: Dictionary) -> void:
	if str(item.get("case_id", "")) == case_id and is_inside_tree() and _evidence_list != null:
		_refresh_evidence()
		_refresh_state()


func _on_flag_pressed() -> void:
	var cat: String = CaseManager.CATEGORIES[maxi(_category.selected, 0)]
	var res: Dictionary = EvidenceManager.flag_selection(case_id, cat, _note.text)
	_feedback.text = str(res.get("message", ""))
	match str(res.get("status", "")):
		"match":
			AudioManager.play_sfx("confirm", -4.0)
			_note.text = ""
		"partial", "none":
			AudioManager.play_sfx("deny", -6.0)
			_note.text = ""
		_:
			AudioManager.play_sfx("error", -10.0)
	_refresh_state()


func _show_help() -> void:
	if desktop == null:
		return
	desktop.call("show_message", "HOW TO INVESTIGATE",
		"1. LEFT is what we have on file: archived messages and supporting files.\n   RIGHT is what the subject wrote today.\n\n"
		+ "2. Click a line that seems wrong. To show a contradiction, select the OLD line and the NEW line together (up to %d lines).\n\n" % EvidenceManager.MAX_SELECTION
		+ "3. Choose a category and press FLAG AS EVIDENCE. Each flag spends one ANALYSIS REQUEST, whether or not the system confirms a pattern. You cannot flag everything.\n\n"
		+ "4. A confirmed pattern is not a verdict. People forget, lie, get tired and change. Read what the finding says - and what it does not say.\n\n"
		+ "5. When you are ready, SUBMIT DECISION. It is final.", "UNDERSTOOD")
