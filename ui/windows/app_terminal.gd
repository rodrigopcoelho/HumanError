extends VBoxContainer
## TERMINAL: a small command shell, and the channel UNKNOWN INSTANCE 07 uses
## to talk to the analyst. Presents DialogueManager conversations in-line.

var desktop: Node
var _log: RichTextLabel
var _choices: VBoxContainer
var _input: LineEdit
var _owns_dialogue: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var p := UI.panel("Term")
	UI.expand(p)
	add_child(p)
	var v := UI.vbox(6)
	p.add_child(v)
	_log = UI.rich("TermRich")
	_log.scroll_following = true
	v.add_child(_log)
	_choices = UI.vbox(4)
	v.add_child(_choices)
	var row := UI.hbox(6)
	v.add_child(row)
	row.add_child(UI.label("0417>", "TermLabel"))
	_input = LineEdit.new()
	_input.theme_type_variation = "TermEdit"
	_input.placeholder_text = "type 'help'"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_command)
	_input.text_changed.connect(func(_t: String) -> void: AudioManager.play_key())
	row.add_child(_input)
	DialogueManager.node_shown.connect(_on_node)
	DialogueManager.dialogue_finished.connect(_on_finished)
	if StoryDirector.terminal_log.is_empty():
		_print("HVC TERMINAL SHELL. Authorised use only. Type 'help'.")
	else:
		for line: Variant in StoryDirector.terminal_log:
			_log.append_text(str(line) + "\n")


func open_args(args: Dictionary) -> void:
	var did: String = str(args.get("dialogue", ""))
	if did != "" and not DialogueManager.is_active() and not DialogueManager.is_completed(did):
		_owns_dialogue = true
		_print("[color=#9e2929]-- INCOMING CONNECTION: SENDER NOT LISTED --[/color]")
		DialogueManager.start(did, false)
	elif _input != null:
		_input.grab_focus.call_deferred()


## The remote party does not let you hang up.
func can_close() -> bool:
	if _owns_dialogue and DialogueManager.is_active():
		_print("[color=#9e2929]CONNECTION HELD BY REMOTE PARTY.[/color]")
		AudioManager.play_sfx("deny", -6.0)
		return false
	return true


func _print(bbcode: String) -> void:
	StoryDirector.terminal_log.append(bbcode)
	if StoryDirector.terminal_log.size() > 300:
		StoryDirector.terminal_log.pop_front()
	_log.append_text(bbcode + "\n")


func _on_node(node: Dictionary) -> void:
	if not _owns_dialogue or not DialogueManager.terminal_mode:
		return
	var text: String = str(node.get("text", ""))
	var speaker: String = str(node.get("speaker", ""))
	var color: String = "#e6e2d6"
	if str(node.get("style", "")) == "red":
		color = "#d05a5a"
	elif str(node.get("style", "")) == "system":
		color = "#9abf9a"
	AudioManager.play_sfx("blip", -10.0)
	_print("[color=%s]%s%s[/color]" % [color, (speaker + ": ") if speaker != "" else "", text])
	UI.clear(_choices)
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		var b := UI.button("[ ... ]", func() -> void: DialogueManager.advance(), "TermButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_choices.add_child(b)
		b.grab_focus.call_deferred()
	for i: int in choices.size():
		var ch: Dictionary = choices[i]
		var b := UI.button("%d. %s" % [i + 1, str(ch.get("text", ""))], func() -> void:
			_print("[color=#9abf9a]0417> %s[/color]" % str(ch.get("text", "")))
			DialogueManager.choose(i), "TermButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choices.add_child(b)
		if i == 0:
			b.grab_focus.call_deferred()


func _on_finished(_id: String) -> void:
	if not _owns_dialogue:
		return
	_owns_dialogue = false
	UI.clear(_choices)
	_print("[color=#9e2929]-- CONNECTION CLOSED --[/color]")


func _on_command(text: String) -> void:
	_input.text = ""
	var cmd: String = text.strip_edges().to_lower()
	if cmd == "":
		return
	_print("[color=#9abf9a]0417> %s[/color]" % text.strip_edges().replace("[", "("))
	if _owns_dialogue and DialogueManager.is_active():
		_print("INPUT IGNORED. Use the listed responses.")
		return
	match cmd:
		"help":
			_print("Commands: help, whoami, status, cases, date, clear")
		"whoami":
			if GameManager.has_flag("player_record_visible"):
				_print("[color=#d05a5a]EMPLOYEE %s. RECORD CREATED 3 DAYS AGO. STATUS: PENDING VERIFICATION.[/color]" % GameManager.EMPLOYEE_ID)
			elif GameManager.day >= 3:
				_print("%s (employee %s). Profile inherited from: [NO SUCH EMPLOYEE]" % [GameManager.player_name, GameManager.EMPLOYEE_ID])
			else:
				_print("%s (employee %s). Verification Analyst." % [GameManager.player_name, GameManager.EMPLOYEE_ID])
		"status":
			_print("Clearance index: %d. Cases closed: %d. svc-continuity: RUNNING." % [GameManager.trust, CaseManager.results.size()])
		"cases":
			for id: String in CaseManager.get_available_cases():
				_print("  %s  %s" % [id, CaseManager.status_label(id)])
		"date":
			_print(str(GameManager.get_day_info().get("date", "?")) + ("" if GameManager.day < 4 else "  (clock unreliable)"))
		"clear":
			StoryDirector.terminal_log.clear()
			_log.clear()
		_:
			if GameManager.day >= 4:
				_print("Unknown command. We are still learning that one.")
			else:
				_print("Unknown command.")
