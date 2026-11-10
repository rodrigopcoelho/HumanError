extends VBoxContainer
## EMPLOYEE DIRECTORY: company staff records. Entries change, and sometimes
## disappear, as the days pass.

var desktop: Node
var _search: LineEdit
var _list: ItemList
var _detail: VBoxContainer
var _entries: Array = []
var _shown: Array = []
var _selected_id: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var top := UI.hbox(8)
	add_child(top)
	top.add_child(UI.label("SEARCH:", "HeaderLabel"))
	_search = LineEdit.new()
	_search.placeholder_text = "name, department or employee number"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void:
		AudioManager.play_key()
		_fill_list())
	top.add_child(_search)
	var split := HSplitContainer.new()
	UI.expand(split)
	add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 280
	_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _shown.size():
			_selected_id = str(_shown[i].get("id", ""))
			AudioManager.play_sfx("click", -8.0)
			_show())
	split.add_child(_list)
	var panel := UI.panel("Sunken")
	UI.expand(panel)
	split.add_child(panel)
	var sc := UI.scroll()
	panel.add_child(sc)
	_detail = UI.vbox(6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_detail)
	GameManager.flag_changed.connect(func(_f: String, _v: Variant) -> void:
		if is_inside_tree():
			refresh.call_deferred())
	refresh()


func open_args(args: Dictionary) -> void:
	if args.has("employee_id"):
		_selected_id = str(args["employee_id"])
	refresh()


func refresh() -> void:
	_entries = CharacterManager.get_directory()
	_fill_list()


func _fill_list() -> void:
	_list.clear()
	_shown = []
	var q: String = _search.text.strip_edges().to_lower()
	for e: Variant in _entries:
		var hay: String = ("%s %s %s %s" % [str(e.get("name", "")), str(e.get("department", "")), str(e.get("employee_no", "")), str(e.get("title", ""))]).to_lower()
		if q != "" and not hay.contains(q):
			continue
		_shown.append(e)
		_list.add_item("%s  %s" % [str(e.get("employee_no", "----")), str(e.get("name", "?")).to_upper()])
		if str(e.get("id", "")) == _selected_id:
			_list.select(_shown.size() - 1)
	_show()


func _kv(key: String, value: String, red: bool = false) -> void:
	var h := UI.hbox(8)
	var k := UI.label(key, "SmallLabel")
	k.custom_minimum_size.x = 150
	h.add_child(k)
	h.add_child(UI.label(value, "RedLabel" if red else "", true))
	_detail.add_child(h)


func _show() -> void:
	UI.clear(_detail)
	var entry: Dictionary = {}
	for e: Variant in _shown:
		if str(e.get("id", "")) == _selected_id:
			entry = e
	if entry.is_empty():
		_detail.add_child(UI.label("%d record(s) listed. Select a record." % _shown.size(), "", true))
		if _shown.is_empty() and _search.text.strip_edges() != "":
			_detail.add_child(UI.label("NO SUCH EMPLOYEE.", "RedHeader"))
		return
	var top := UI.hbox(12)
	_detail.add_child(top)
	var frame := UI.panel("Term")
	var path: String = str(entry.get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = UI.photo(path)
		tr.custom_minimum_size = Vector2(130, 162)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.material = UI.photo_material(float(entry.get("photo_glitch", 0.12 + 0.07 * float(GameManager.day))), float(entry.get("photo_invert", 0.0)))
		frame.add_child(tr)
	else:
		var np := UI.label("NO PHOTO\nON FILE", "TermLabel")
		np.custom_minimum_size = Vector2(130, 162)
		np.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		np.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(np)
	top.add_child(frame)
	var v := UI.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(v)
	v.add_child(UI.label(str(entry.get("name", "?")).to_upper(), "HeaderLabel", true))
	v.add_child(UI.label(str(entry.get("title", "")), "", true))
	v.add_child(UI.label(str(entry.get("department", "")), "SmallLabel", true))
	var status: String = str(entry.get("status", "ACTIVE"))
	_kv("EMPLOYEE NO.", str(entry.get("employee_no", "----")))
	_kv("STATUS", status, status != "ACTIVE")
	_kv("WITH HVC SINCE", str(entry.get("since", "?")))
	_kv("EXTENSION", str(entry.get("ext", "-")))
	if entry.has("age"):
		_kv("AGE", UI.num(entry["age"]))
	if str(entry.get("record_created", "")) != "":
		_kv("RECORD CREATED", str(entry["record_created"]), bool(entry.get("record_alert", false)))
	if str(entry.get("note", "")) != "":
		_detail.add_child(UI.label("NOTES", "HeaderLabel"))
		_detail.add_child(UI.label(str(entry["note"]), "", true))
	if str(entry.get("alert", "")) != "":
		var p := UI.panel("ToastError")
		p.add_child(UI.label(str(entry["alert"]), "WhiteLabel", true))
		_detail.add_child(p)
	StoryDirector.trigger("directory_viewed:" + str(entry.get("id", "")))
