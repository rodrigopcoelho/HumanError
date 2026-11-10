extends VBoxContainer
## MESSAGE ARCHIVE: old conversations for every subject you have been assigned,
## with an optional side-by-side view of their new questionnaire answers.

const LineItem := preload("res://ui/components/line_item.gd")

var desktop: Node
var _list: ItemList
var _ids: Array[String] = []
var _selected: String = ""
var _left: VBoxContainer
var _right: VBoxContainer
var _right_panel: Control
var _compare: bool = true
var _compare_button: Button
var _header: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var top := UI.hbox(8)
	add_child(top)
	_header = UI.label("ARCHIVE", "HeaderLabel")
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_compare_button = UI.button("", func() -> void:
		_compare = not _compare
		_show())
	top.add_child(_compare_button)
	top.add_child(UI.button("OPEN IN WORKBENCH", func() -> void:
		if _selected != "":
			desktop.call("open_app", "workbench", {"case_id": _selected})))
	var split := HSplitContainer.new()
	UI.expand(split)
	add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 210
	_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _ids.size():
			_selected = _ids[i]
			AudioManager.play_sfx("click", -8.0)
			_show())
	split.add_child(_list)
	var panes := UI.hbox(6)
	UI.expand(panes)
	split.add_child(panes)
	var lp := UI.panel("Sunken")
	UI.expand(lp)
	panes.add_child(lp)
	var ls := UI.scroll()
	lp.add_child(ls)
	_left = UI.vbox(5)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_left)
	_right_panel = UI.panel("Sunken")
	UI.expand(_right_panel)
	panes.add_child(_right_panel)
	var rs := UI.scroll()
	_right_panel.add_child(rs)
	_right = UI.vbox(5)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_right)
	_refresh_list()


func open_args(args: Dictionary) -> void:
	if args.has("case_id"):
		_selected = str(args["case_id"])
	_refresh_list()


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	_ids = CaseManager.get_available_cases()
	if (_selected == "" or not _ids.has(_selected)) and not _ids.is_empty():
		_selected = _ids[_ids.size() - 1]
	for i: int in _ids.size():
		var c: Dictionary = CaseManager.get_case(_ids[i])
		_list.add_item(CharacterManager.get_name_of(str(c["character_id"])).to_upper())
		if _ids[i] == _selected:
			_list.select(i)
	_show()


func _line(parent: Control, line_id: String) -> void:
	var item: PanelContainer = LineItem.new()
	parent.add_child(item)
	item.call("setup", _selected, line_id, false, true)


func _show() -> void:
	UI.clear(_left)
	UI.clear(_right)
	_compare_button.text = "COMPARE WITH NEW ANSWERS: %s" % ("ON" if _compare else "OFF")
	_right_panel.visible = _compare
	if _selected == "":
		_header.text = "ARCHIVE  -  no subjects assigned"
		_left.add_child(UI.label("The archive is empty until a case is assigned to you.", "", true))
		return
	var c: Dictionary = CaseManager.get_case(_selected)
	var who: String = CharacterManager.get_name_of(str(c["character_id"]))
	_header.text = "ARCHIVE  -  %s  -  %d message(s) on file" % [who.to_upper(), (c["historical_messages"] as Array).size()]
	var threads: Dictionary = c.get("threads", {})
	var last: String = "~none~"
	for m: Variant in c["historical_messages"]:
		var t: String = str(m.get("thread", ""))
		if t != last:
			last = t
			_left.add_child(UI.label(str(threads.get(t, "ARCHIVE")).to_upper(), "HeaderLabel", true))
		_line(_left, str(m["id"]))
	if _compare:
		_right.add_child(UI.label("NEW QUESTIONNAIRE ANSWERS", "HeaderLabel", true))
		for q: Variant in c["questionnaire_answers"]:
			_line(_right, str(q["id"]))
