extends VBoxContainer
## PERSONAL NOTES: free text that persists between sessions.

var desktop: Node
var _edit: TextEdit
var _status: Label
var _dirty: bool = false
var _timer: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UI.label("NOTES.TXT  -  private to employee %s" % GameManager.EMPLOYEE_ID, "SmallLabel"))
	_edit = TextEdit.new()
	_edit.text = GameManager.notes
	_edit.placeholder_text = "Write anything you want to remember.\nNobody else can read this file."
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	UI.expand(_edit)
	_edit.text_changed.connect(func() -> void:
		GameManager.notes = _edit.text
		_dirty = true
		_timer = 1.5
		_status.text = "editing..."
		AudioManager.play_key())
	add_child(_edit)
	_status = UI.label("saved", "SmallLabel")
	add_child(_status)
	tree_exiting.connect(_save)


func _process(delta: float) -> void:
	if _dirty:
		_timer -= delta
		if _timer <= 0.0:
			_save()


func _save() -> void:
	if _dirty:
		_dirty = false
		SaveManager.save_game()
		if _status != null:
			_status.text = "saved" if GameManager.day < 4 else "saved. read."
