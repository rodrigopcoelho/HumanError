extends Node
## DialogueManager (autoload): loads branching dialogue from JSON and runs it.
## Presentation is decoupled: the default overlay (dialogue_box) or the TERMINAL
## application listen to the signals below.
##
## Node format:
##   {"speaker": "", "text": "", "style": "", "next": "id",
##    "effects": {flags, trust, rapport, sfx, glitch, action, trigger},
##    "branch": [{"requires": {...}, "next": "id"}],
##    "choices": [{"id": "", "text": "", "next": "id", "requires": {...}, "effects": {...}}]}

signal dialogue_started(id: String)
signal node_shown(node: Dictionary)
signal dialogue_finished(id: String)
signal action_requested(action: String)

const DIALOGUE_DIR := "res://data/dialogue"
const OVERLAY_SCENE := "res://scenes/dialogue/dialogue_box.tscn"

var dialogues: Dictionary = {}
var completed: Dictionary = {}      # dialogue id -> true
var choices_made: Dictionary = {}   # dialogue id -> Array of choice ids
var load_errors: Array[String] = []
var active_id: String = ""
var active_node: Dictionary = {}    # resolved node currently shown
var terminal_mode: bool = false
var _overlay: Node


func _ready() -> void:
	load_all()


func load_all() -> void:
	dialogues.clear()
	load_errors.clear()
	for path: String in SaveManager.list_data_files(DIALOGUE_DIR):
		var data: Variant = SaveManager.read_data_file(path)
		if not (data is Dictionary) or not ((data as Dictionary).get("dialogues") is Dictionary):
			load_errors.append("%s: expected {\"dialogues\": {...}}" % path)
			continue
		var set_: Dictionary = data["dialogues"]
		for id: String in set_:
			var d: Variant = set_[id]
			if not (d is Dictionary) or not ((d as Dictionary).get("nodes") is Dictionary) or not (d["nodes"] as Dictionary).has("start"):
				load_errors.append("%s: dialogue '%s' needs nodes.start" % [path.get_file(), id])
				continue
			_validate(id, d["nodes"], path.get_file())
			dialogues[id] = d
	for e: String in load_errors:
		push_error("DialogueManager: " + e)


func _validate(id: String, nodes: Dictionary, file: String) -> void:
	for nid: String in nodes:
		var n: Dictionary = nodes[nid]
		var targets: Array = [n.get("next", "")]
		for ch: Variant in n.get("choices", []):
			targets.append(ch.get("next", ""))
		for br: Variant in n.get("branch", []):
			targets.append(br.get("next", ""))
		for t: Variant in targets:
			if str(t) != "" and str(t) != "end" and not nodes.has(str(t)):
				load_errors.append("%s: dialogue '%s' node '%s' points to missing node '%s'" % [file, id, nid, str(t)])


func has_dialogue(id: String) -> bool:
	return dialogues.has(id)


func is_active() -> bool:
	return active_id != ""


func is_completed(id: String) -> bool:
	return completed.has(id)


func was_chosen(dialogue_id: String, choice_id: String) -> bool:
	var a: Variant = choices_made.get(dialogue_id, [])
	return a is Array and (a as Array).has(choice_id)


## Starts a dialogue. With use_overlay the standard dialogue box is shown;
## otherwise the caller (the TERMINAL app) presents it.
func start(id: String, use_overlay: bool = true) -> bool:
	if not dialogues.has(id):
		push_warning("DialogueManager: unknown dialogue '%s'" % id)
		return false
	if is_active():
		cancel()
	active_id = id
	terminal_mode = not use_overlay
	if use_overlay:
		var scene: PackedScene = load(OVERLAY_SCENE) as PackedScene
		if scene != null:
			_overlay = scene.instantiate()
			get_tree().root.add_child(_overlay)
	dialogue_started.emit(id)
	_goto("start")
	return true


func _nodes() -> Dictionary:
	return dialogues[active_id]["nodes"]


func _goto(node_id: String) -> void:
	var guard: int = 0
	var target: String = node_id
	while guard < 50:
		guard += 1
		if target == "" or target == "end" or not _nodes().has(target):
			_finish()
			return
		var n: Dictionary = _nodes()[target]
		_apply_effects(n.get("effects", {}))
		if not is_active():
			return
		# Pure routing node: no text, just a branch.
		if str(n.get("text", "")) == "":
			target = _resolve_next(n)
			continue
		var visible: Array = []
		for ch: Variant in n.get("choices", []):
			if ch is Dictionary and GameManager.check_requires(ch.get("requires", {})):
				var copy: Dictionary = (ch as Dictionary).duplicate(true)
				copy["text"] = GameManager.format_text(str(ch.get("text", "")))
				visible.append(copy)
		active_node = {
			"id": target,
			"speaker": GameManager.format_text(str(n.get("speaker", ""))),
			"text": GameManager.format_text(str(n.get("text", ""))),
			"style": str(n.get("style", "")),
			"choices": visible,
			"next": _resolve_next(n),
		}
		node_shown.emit(active_node)
		return
	push_error("DialogueManager: routing loop in dialogue '%s'" % active_id)
	_finish()


func _resolve_next(n: Dictionary) -> String:
	for br: Variant in n.get("branch", []):
		if br is Dictionary and GameManager.check_requires(br.get("requires", {})):
			return str(br.get("next", ""))
	return str(n.get("next", ""))


func _apply_effects(e: Variant) -> void:
	if not (e is Dictionary):
		return
	var fx: Dictionary = e
	var fl: Variant = fx.get("flags", {})
	if fl is Dictionary:
		for f: String in (fl as Dictionary):
			GameManager.set_flag(f, fl[f])
	if fx.has("trust"):
		GameManager.adjust_trust(int(fx["trust"]))
	if fx.has("rapport"):
		GameManager.adjust_rapport(int(fx["rapport"]))
	if fx.has("sfx"):
		AudioManager.play_sfx(str(fx["sfx"]), float(fx.get("sfx_db", -4.0)))
	if fx.has("glitch"):
		ScreenFX.pulse(float(fx["glitch"]), 0.6)
	if fx.has("trigger"):
		StoryDirector.trigger(str(fx["trigger"]))
	if fx.has("action"):
		action_requested.emit(str(fx["action"]))


## Continue past a node that has no choices.
func advance() -> void:
	if not is_active() or not (active_node.get("choices", []) as Array).is_empty():
		return
	_goto(str(active_node.get("next", "")))


func choose(index: int) -> void:
	if not is_active():
		return
	var choices: Array = active_node.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var ch: Dictionary = choices[index]
	var made: Array = choices_made.get(active_id, [])
	made.append(str(ch.get("id", str(index))))
	choices_made[active_id] = made
	_apply_effects(ch.get("effects", {}))
	if is_active():
		_goto(str(ch.get("next", "")))


func _finish() -> void:
	var id: String = active_id
	if id == "":
		return
	completed[id] = true
	active_id = ""
	active_node = {}
	_free_overlay()
	dialogue_finished.emit(id)
	StoryDirector.trigger("dialogue_finished:" + id)
	if GameManager.game_active:
		SaveManager.save_game()


## Abandons the running dialogue without marking it complete.
func cancel() -> void:
	if active_id == "":
		return
	active_id = ""
	active_node = {}
	_free_overlay()


func _free_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


# ---------------------------------------------------------------- save

func reset_state() -> void:
	cancel()
	completed = {}
	choices_made = {}


func get_save_data() -> Dictionary:
	return {"completed": completed.duplicate(), "choices_made": choices_made.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	var c: Variant = d.get("completed", {})
	if c is Dictionary:
		completed = (c as Dictionary).duplicate()
	var m: Variant = d.get("choices_made", {})
	if m is Dictionary:
		choices_made = (m as Dictionary).duplicate(true)
