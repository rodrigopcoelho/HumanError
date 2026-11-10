extends PanelContainer
## A movable, resizable HVC TERMINAL window that hosts one application.

signal closed(window_id: String)

var window_id: String = ""
var content: Control
var _title: Label
var _dragging: bool = false
var _resizing: bool = false


func setup(id: String, title: String, content_node: Control, win_size: Vector2) -> void:
	window_id = id
	content = content_node
	theme_type_variation = "WindowFrame"
	custom_minimum_size = Vector2(340, 220)
	size = win_size
	var v := UI.vbox(0)
	add_child(v)
	var bar := UI.panel("TitleBar")
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	var h := UI.hbox(6)
	bar.add_child(h)
	_title = UI.label(title, "WhiteLabel")
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	var close := UI.button("X", request_close)
	close.custom_minimum_size = Vector2(30, 24)
	close.tooltip_text = "Close window"
	h.add_child(close)
	v.add_child(bar)
	var body := UI.margin(content, 6)
	UI.expand(body)
	UI.expand(content)
	v.add_child(body)
	var foot := UI.hbox(0)
	foot.add_child(UI.spacer())
	var grip := UI.label("//", "SmallLabel")
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Drag to resize"
	grip.gui_input.connect(_on_grip_input)
	foot.add_child(grip)
	v.add_child(foot)


func set_title(title: String) -> void:
	_title.text = title


func get_title() -> String:
	return _title.text


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_resizing = (event as InputEventMouseButton).pressed


func _input(event: InputEvent) -> void:
	if not (_dragging or _resizing):
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_dragging = false
		_resizing = false
	elif event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if _dragging:
			position += rel
			clamp_to_parent()
		else:
			var area: Vector2 = _parent_size()
			size = Vector2(clampf(size.x + rel.x, custom_minimum_size.x, area.x - position.x),
				clampf(size.y + rel.y, custom_minimum_size.y, area.y - position.y))


func _parent_size() -> Vector2:
	var p: Node = get_parent()
	return (p as Control).size if p is Control else get_viewport_rect().size


func clamp_to_parent() -> void:
	var area: Vector2 = _parent_size()
	size = Vector2(minf(size.x, area.x), minf(size.y, area.y))
	position = Vector2(clampf(position.x, 0.0, maxf(area.x - size.x, 0.0)), clampf(position.y, 0.0, maxf(area.y - size.y, 0.0)))


func request_close() -> void:
	if content != null and content.has_method("can_close") and not content.call("can_close"):
		return
	closed.emit(window_id)
	queue_free()
