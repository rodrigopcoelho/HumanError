extends VBoxContainer
## CASE DATABASE: file-explorer style list of verification cases, case details,
## the current questionnaire, the submit button and the evidence locker.

const Workbench := preload("res://scripts/investigation/investigation_view.gd")

var desktop: Node
var _list: ItemList
var _detail: VBoxContainer
var _ids: Array[String] = []
var _selected: String = ""
var _mode: String = "cases"
var _tab_cases: Button
var _tab_locker: Button
var _body: Control


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var tabs := UI.hbox(4)
	add_child(tabs)
	_tab_cases = UI.button("CASE FILES", func() -> void: _set_mode("cases"))
	_tab_locker = UI.button("EVIDENCE LOCKER", func() -> void: _set_mode("locker"))
	_tab_cases.toggle_mode = true
	_tab_locker.toggle_mode = true
	tabs.add_child(_tab_cases)
	tabs.add_child(_tab_locker)
	tabs.add_child(UI.spacer())
	tabs.add_child(UI.label("C:\\HVC\\IDENTITY\\CASES\\", "SmallLabel"))
	_body = HSplitContainer.new()
	UI.expand(_body)
	add_child(_body)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 290
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	_body.add_child(_list)
	var panel := UI.panel("Sunken")
	UI.expand(panel)
	_body.add_child(panel)
	var sc := UI.scroll()
	panel.add_child(sc)
	_detail = UI.vbox(6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_detail)
	CaseManager.case_submitted.connect(func(_id: String, _r: Dictionary) -> void: refresh())
	EvidenceManager.evidence_added.connect(func(_i: Dictionary) -> void:
		if _mode == "locker":
			refresh())
	refresh()


func open_args(args: Dictionary) -> void:
	if args.has("case_id"):
		_selected = str(args["case_id"])
		_mode = "cases"
	refresh()


func _set_mode(mode: String) -> void:
	_mode = mode
	refresh()


func refresh() -> void:
	if _list == null or not is_inside_tree():
		return
	_tab_cases.set_pressed_no_signal(_mode == "cases")
	_tab_locker.set_pressed_no_signal(_mode == "locker")
	_list.clear()
	_ids = CaseManager.get_available_cases()
	if _selected == "" or not _ids.has(_selected):
		_selected = ""
		for id: String in _ids:
			if not CaseManager.is_done(id):
				_selected = id
		if _selected == "" and not _ids.is_empty():
			_selected = _ids[_ids.size() - 1]
	for i: int in _ids.size():
		var c: Dictionary = CaseManager.get_case(_ids[i])
		var who: String = CharacterManager.get_name_of(str(c["character_id"]))
		_list.add_item("%s CASE_%s  %s" % ["[x]" if CaseManager.is_done(_ids[i]) else "[ ]", str(c.get("number", "")), who.to_upper()])
		if _ids[i] == _selected:
			_list.select(i)
	if _mode == "cases":
		_show_case()
	else:
		_show_locker()


func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _ids.size():
		_selected = _ids[index]
		AudioManager.play_sfx("click", -8.0)
		if _mode == "cases":
			_show_case()
		else:
			_show_locker()


func _kv(key: String, value: String) -> void:
	var h := UI.hbox(8)
	var k := UI.label(key, "SmallLabel")
	k.custom_minimum_size.x = 170
	h.add_child(k)
	h.add_child(UI.label(value, "", true))
	_detail.add_child(h)


func _show_case() -> void:
	UI.clear(_detail)
	if _selected == "":
		_detail.add_child(UI.label("No cases have been assigned to you yet.", "", true))
		return
	var c: Dictionary = CaseManager.get_case(_selected)
	var ch: Dictionary = CharacterManager.get_character(str(c["character_id"]))
	var done: bool = CaseManager.is_done(_selected)
	_detail.add_child(UI.label("CASE %s  -  %s" % [str(c.get("number", "")), str(c["title"]).to_upper()], "HeaderLabel", true))
	_kv("CASE NUMBER", "HVC-%s" % str(c.get("number", "")))
	_kv("SUBJECT", str(ch.get("name", "?")))
	_kv("AGE", UI.num(ch.get("age", "?")))
	_kv("OCCUPATION", str(ch.get("occupation", "?")))
	_kv("DIFFICULTY", str(c["difficulty"]))
	_kv("VERIFICATION STATUS", CaseManager.status_label(_selected))
	_kv("ASSIGNED", str(GameManager.get_day_info(int(c["day"])).get("date", "")))
	_detail.add_child(UI.label("BRIEFING", "HeaderLabel"))
	_detail.add_child(UI.label(GameManager.format_text(str(c.get("briefing", ""))), "", true))
	_detail.add_child(UI.label("PREVIOUS INVESTIGATION HISTORY", "HeaderLabel"))
	var history: Array = c.get("previous_history", [])
	if history.is_empty():
		_detail.add_child(UI.label("No previous verifications on file.", "SmallLabel", true))
	for h: Variant in history:
		_detail.add_child(UI.label("- " + GameManager.format_text(str(h)), "", true))
	var row := UI.hbox(8)
	_detail.add_child(row)
	row.add_child(UI.button("OPEN WORKBENCH" if not done else "REVIEW IN WORKBENCH", func() -> void:
		desktop.call("open_app", "workbench", {"case_id": _selected})))
	row.add_child(UI.button("MESSAGE ARCHIVE", func() -> void:
		desktop.call("open_app", "archive", {"case_id": _selected})))
	if done:
		row.add_child(UI.button("VIEW OFFICIAL RESULT", func() -> void:
			desktop.call("open_app", "result", {"case_id": _selected})))
	else:
		row.add_child(UI.button("SUBMIT DECISION", func() -> void:
			desktop.call("open_classification", _selected), "DangerButton"))
	_detail.add_child(UI.label("CURRENT QUESTIONNAIRE  (%s)" % str(c.get("form", "FORM CV-1")), "HeaderLabel"))
	for q: Variant in c["questionnaire_answers"]:
		_detail.add_child(UI.label("Q: " + str(q["question"]), "SmallLabel", true))
		_detail.add_child(UI.label("A: " + CaseManager.line_text(_selected, str(q["id"])), "", true))


func _show_locker() -> void:
	UI.clear(_detail)
	var all: Array = EvidenceManager.collected
	_detail.add_child(UI.label("EVIDENCE LOCKER  -  %d item(s) across all cases" % all.size(), "HeaderLabel", true))
	_detail.add_child(UI.label("Select a case on the left to filter. Everything you have flagged is kept here.", "SmallLabel", true))
	var shown: int = 0
	for item: Variant in all:
		if _selected != "" and str(item.get("case_id", "")) != _selected:
			continue
		shown += 1
		_detail.add_child(Workbench.make_evidence_card(item))
	if shown == 0:
		_detail.add_child(UI.label("No evidence collected for this case.", "", true))
