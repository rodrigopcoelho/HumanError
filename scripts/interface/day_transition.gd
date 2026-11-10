extends Control
## Day title card with a short introduction, shown at the start of each day.

var _lines: Array = []
var _body: Label
var _button: Button
var _index: int = 0


func _ready() -> void:
	UI.full_rect(self)
	var info: Dictionary = GameManager.get_day_info()
	ScreenFX.set_corruption(float(GameManager.day - 1) / 4.0 * 0.8)
	if GameManager.day >= 4:
		AudioManager.silence(1.0)
	else:
		AudioManager.apply_preset("office_empty", 2.0)
		AudioManager.stop_music(2.0)
	var bg := ColorRect.new()
	bg.color = UI.C_BLACK
	UI.full_rect(bg)
	add_child(bg)
	var photo := TextureRect.new()
	photo.texture = UI.photo("res://assets/environments/%s.jpg" % str(info.get("photo", "waiting_room")))
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.material = UI.photo_material(0.15 + 0.15 * float(GameManager.day), 1.0 if bool(info.get("invert", false)) else 0.0, 0.55)
	UI.full_rect(photo)
	add_child(photo)
	var center := CenterContainer.new()
	UI.full_rect(center)
	add_child(center)
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 760
	center.add_child(v)
	v.add_child(UI.label("DAY %d" % GameManager.day, "TitleLabel"))
	v.add_child(UI.label(str(info.get("title", "")).to_upper(), "TermBig"))
	v.add_child(UI.label(str(info.get("date", "")), "TermLabel"))
	v.add_child(UI.spacer(Vector2(0, 12)))
	_body = UI.label("", "WhiteLabel", true)
	_body.custom_minimum_size = Vector2(760, 200)
	v.add_child(_body)
	_button = UI.button("CONTINUE", _next, "TermButton")
	_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(_button)
	_button.grab_focus.call_deferred()
	_lines = info.get("intro", [])
	_show_line()


func _show_line() -> void:
	if _index < _lines.size():
		_body.text = GameManager.format_text(str(_lines[_index]))
		_body.visible_ratio = 0.0
		var tw: Tween = create_tween()
		tw.tween_property(_body, "visible_ratio", 1.0, clampf(float(_body.text.length()) * 0.015, 0.3, 2.5))
	_button.text = "BEGIN SHIFT" if _index >= _lines.size() - 1 else "CONTINUE"


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_button.disabled = true
		GameManager.goto_scene("office")
	else:
		_show_line()
