extends VBoxContainer
## INTERNAL EMAIL: inbox with a reading pane.

var desktop: Node
var _list: ItemList
var _ids: Array[String] = []
var _selected: String = ""
var _head: Label
var _meta: Label
var _body: RichTextLabel


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var split := HSplitContainer.new()
	UI.expand(split)
	add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 330
	_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _ids.size():
			_open(_ids[i]))
	split.add_child(_list)
	var panel := UI.panel("Sunken")
	UI.expand(panel)
	split.add_child(panel)
	var v := UI.vbox(6)
	panel.add_child(v)
	_head = UI.label("", "HeaderLabel", true)
	v.add_child(_head)
	_meta = UI.label("", "SmallLabel", true)
	v.add_child(_meta)
	_body = UI.rich()
	v.add_child(_body)
	StoryDirector.emails_changed.connect(_refresh_list)
	_refresh_list()
	if _selected == "":
		_head.text = "INBOX"
		_meta.text = "Select a message to read it."


func _refresh_list() -> void:
	if _list == null or not is_inside_tree():
		return
	_list.clear()
	_ids = []
	for i: int in range(StoryDirector.delivered.size() - 1, -1, -1):
		var id: String = str(StoryDirector.delivered[i])
		var mail: Dictionary = StoryDirector.get_email(id)
		_ids.append(id)
		var unread: bool = not StoryDirector.is_read(id)
		_list.add_item("%s %s\n   %s" % ["*" if unread else " ", str(mail.get("from", "?")), GameManager.format_text(str(mail.get("subject", "(no subject)")))])
		if unread:
			_list.set_item_custom_fg_color(_list.item_count - 1, UI.C_RED)
		if id == _selected:
			_list.select(_list.item_count - 1)


func _open(id: String) -> void:
	_selected = id
	var mail: Dictionary = StoryDirector.get_email(id)
	AudioManager.play_sfx("click", -8.0)
	_head.text = GameManager.format_text(str(mail.get("subject", "(no subject)")))
	_meta.text = "FROM: %s <%s>\nTO: %s\nDATE: %s" % [str(mail.get("from", "?")), str(mail.get("address", "unknown")), GameManager.format_text(str(mail.get("to", "{player} <analyst.0417@hvc.internal>"))), StoryDirector.email_date(id)]
	_body.text = GameManager.format_text(str(mail.get("body", "")))
	_body.scroll_to_line(0)
	StoryDirector.mark_email_read(id)
