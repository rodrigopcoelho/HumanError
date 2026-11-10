extends Node
## Automated smoke test and scripted playthrough.
## Run:  godot --headless --path . res://tests/test_runner.tscn
## Uses separate save files, so it never touches a real saved game.

var _fails: int = 0
var _checks: int = 0


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  FAIL: ", what)


func _ready() -> void:
	SaveManager.save_path = "user://test_save.json"
	SaveManager.settings_path = "user://test_settings.json"
	SaveManager.delete_save()
	GameManager.scene_changes_enabled = false
	await get_tree().process_frame
	_test_scripts()
	_test_data()
	await _playthrough("A")
	await _playthrough("B")
	await _playthrough("C")
	await _test_wrong_calls()
	await _test_ui()
	SaveManager.delete_save()
	print("\n%d checks, %d failures" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _scripts_in(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub: String in d.get_directories():
		if not sub.begins_with("."):
			_scripts_in(dir.path_join(sub), out)


func _test_scripts() -> void:
	print("== scripts")
	var files: Array = []
	_scripts_in("res://scripts", files)
	_scripts_in("res://ui", files)
	for f: String in files:
		var s: GDScript = load(f) as GDScript
		check(s != null and s.can_instantiate(), "script compiles: " + f)
	print("  %d scripts loaded" % files.size())


func _test_data() -> void:
	print("== data")
	check(CaseManager.load_errors.is_empty(), "case data valid: " + str(CaseManager.load_errors))
	check(CharacterManager.load_errors.is_empty(), "character data valid: " + str(CharacterManager.load_errors))
	check(DialogueManager.load_errors.is_empty(), "dialogue data valid: " + str(DialogueManager.load_errors))
	check(StoryDirector.load_errors.is_empty(), "story data valid: " + str(StoryDirector.load_errors))
	check(CaseManager.cases.size() >= 6, "five cases + final case loaded")
	check(CharacterManager.characters.size() >= 6, "six characters loaded")
	for n: int in range(1, 6):
		check(not GameManager.get_day_info(n).is_empty(), "day %d defined" % n)
	for id: String in CaseManager.cases:
		var c: Dictionary = CaseManager.cases[id]
		check(CharacterManager.characters.has(str(c["character_id"])), id + " character exists")
		check(ResourceLoader.exists(str(CharacterManager.get_character(str(c["character_id"]))["portrait"])), id + " portrait exists")
	for snd: String in ["click", "select", "open", "confirm", "deny", "error", "notify", "stamp", "blip", "key1", "key2", "key3", "hdd", "boot",
			"phone_ring", "pickup", "door", "coffee", "fan", "crt_hum", "fluorescent", "murmur", "interference", "drone"]:
		check(ResourceLoader.exists("res://assets/audio/%s.wav" % snd), "sound exists: " + snd)
	for env: String in ["corridor_a", "corridor_b", "corridor_c", "corridor_d", "waiting_room", "window_a", "window_b", "server_room", "desktop_wallpaper"]:
		check(ResourceLoader.exists("res://assets/environments/%s.jpg" % env), "environment exists: " + env)
	# every office object has a dialogue on every day and phase
	for d: int in range(1, 6):
		for ph: String in ["morning", "evening"]:
			for obj: String in ["computer", "phone", "cabinet", "coffee", "door", "board", "window"]:
				var found: bool = false
				for id: String in ["office_%s_d%d_%s" % [obj, d, ph], "office_%s_d%d" % [obj, d], "office_%s_%s" % [obj, ph], "office_%s" % obj]:
					if DialogueManager.has_dialogue(id):
						found = true
				check(found, "office dialogue for %s day %d %s" % [obj, d, ph])


## Collects every clue in a case by flagging its first match set.
func _collect_all(case_id: String) -> int:
	var n: int = 0
	for ev: Variant in CaseManager.get_case(case_id)["evidence"]:
		if EvidenceManager.requests_left(case_id) <= 0:
			break
		if EvidenceManager.found_clue_ids(case_id).has(str(ev["id"])):
			continue
		EvidenceManager.clear_selection(case_id)
		for lid: Variant in ev["match_sets"][0]:
			EvidenceManager.toggle_select(case_id, str(lid))
		var res: Dictionary = EvidenceManager.flag_selection(case_id, str(ev["category"]), "test")
		if str(res["status"]) == "match":
			n += 1
	return n


func _run_dialogue(id: String, picks: Dictionary) -> void:
	check(DialogueManager.start(id, false), "dialogue starts: " + id)
	var guard: int = 0
	while DialogueManager.is_active() and guard < 200:
		guard += 1
		var choices: Array = DialogueManager.active_node.get("choices", [])
		if choices.is_empty():
			DialogueManager.advance()
		else:
			var idx: int = 0
			for i: int in choices.size():
				if picks.has(str(choices[i].get("id", ""))):
					idx = i
			DialogueManager.choose(idx)
	check(DialogueManager.is_completed(id), "dialogue completes: " + id)


func _close_result(case_id: String) -> void:
	GameManager.set_flag("result_ack:" + case_id)
	StoryDirector.trigger("result_closed:" + case_id)


func _playthrough(want: String) -> void:
	print("== playthrough, expecting ending ", want)
	GameManager.new_game("Tester")
	check(SaveManager.has_save(), "save created on new game")
	check(StoryDirector.delivered.has("m_welcome"), "day 1 mail delivered")
	var plan := {
		"A": ["VERIFIED_HUMAN", "CORRUPTED_AI", "VERIFIED_HUMAN", "CORRUPTED_AI", "CORRUPTED_AI"],
		"B": ["VERIFIED_HUMAN", "CORRUPTED_AI", "VERIFIED_HUMAN", "CORRUPTED_AI", "SUSPICIOUS"],
		"C": ["VERIFIED_HUMAN", "CORRUPTED_AI", "VERIFIED_HUMAN", "CORRUPTED_AI", "VERIFIED_HUMAN"],
	}
	var ids: Array = ["CASE_001", "CASE_002", "CASE_003", "CASE_004", "CASE_005"]
	for i: int in 5:
		var cid: String = ids[i]
		check(GameManager.day == i + 1, "day is %d" % (i + 1))
		GameManager.set_flag("booted_d%d" % GameManager.day)
		StoryDirector.trigger("desktop_ready")
		check(CaseManager.is_available(cid), cid + " available")
		check(not GameManager.can_end_shift(), "cannot end shift before the case")
		var found: int = _collect_all(cid)
		check(found >= 3, "%s: at least 3 clues collectable (got %d)" % [cid, found])
		var res: Dictionary = CaseManager.submit(cid, plan[want][i])
		check(not res.is_empty() and CaseManager.is_done(cid), cid + " submitted")
		print("   %s -> %s  accuracy %d  trust %d" % [cid, plan[want][i], int(res.get("accuracy", -1)), GameManager.trust])
		_close_result(cid)
		if i == 0:
			check(StoryDirector.delivered.has("m_u07_1"), "first unknown message delivered")
		if i == 1:
			check(GameManager.has_flag("pattern_seen"), "UNAUTHORIZED PATTERN event fired")
		if i == 2:
			_run_dialogue("u07_day3", {"yes": true})
		if i == 3:
			_run_dialogue("u07_day4", {"both": true, "hale": true})
		if i < 4:
			check(GameManager.can_end_shift(), "can end shift after the case")
			GameManager.phase = "evening"
			GameManager.day += 1
			GameManager.phase = "morning"
			StoryDirector.trigger("day_start")
	check(StoryDirector.fired.has("ev_u07_d5"), "day 5 contact queued")
	match want:
		"A": _run_dialogue("u07_day5", {"end_it": true, "lie": true, "report": true})
		"B": _run_dialogue("u07_day5", {"yes": true, "silent": true, "grant": true})
		"C": _run_dialogue("u07_day5", {"maybe": true, "who": true, "own_way": true})
	check(GameManager.has_flag("final_case_unlocked"), "final case unlocked")
	check(GameManager.has_flag("player_record_visible"), "player record visible")
	check(CaseManager.is_available("CASE_007"), "CASE_007 available")
	check(StoryDirector.delivered.has("m_voss_final"), "final directive delivered")
	var has_player: bool = false
	for e: Variant in CharacterManager.get_directory():
		if str(e.get("id", "")) == "PLAYER":
			has_player = true
			check(str(e["name"]) == "Tester", "player record carries the player's name")
	check(has_player, "player appears in directory")
	var hale: bool = false
	for e: Variant in CharacterManager.get_directory():
		if str(e.get("id", "")) == "THOMAS_HALE":
			hale = true
	check(not hale, "Thomas Hale has disappeared from the directory")
	if want == "C":
		StoryDirector.mark_email_read("m_sarah_key")
		StoryDirector.trigger("directory_viewed:PLAYER")
	# save / load round trip
	GameManager.notes = "The handwriting slopes like mine. I should check that."
	check(SaveManager.save_game(), "save written")
	var snapshot := [GameManager.day, GameManager.trust, CaseManager.results.size(), EvidenceManager.collected.size(), StoryDirector.delivered.size(), GameManager.flags.size()]
	GameManager.reset_state()
	CaseManager.reset_state()
	EvidenceManager.reset_state()
	DialogueManager.reset_state()
	StoryDirector.reset_state()
	check(SaveManager.load_game(), "save loaded")
	var after := [GameManager.day, GameManager.trust, CaseManager.results.size(), EvidenceManager.collected.size(), StoryDirector.delivered.size(), GameManager.flags.size()]
	check(snapshot == after, "save/load round trip preserves state: %s vs %s" % [str(snapshot), str(after)])
	check(GameManager.notes.begins_with("The handwriting"), "notes persist")
	check(GameManager.format_text("{note_quote}") == "The handwriting slopes like mine", "note quote extracted")
	var final_cls: String = {"A": "CORRUPTED_AI", "B": "VERIFIED_HUMAN", "C": "UNDETERMINED"}[want]
	var got: String = GameManager.determine_ending(final_cls)
	check(got == want, "ending %s reached (got %s; trust %d rapport %d truth %d)" % [want, got, GameManager.trust, GameManager.rapport, GameManager.truth_score()])
	var fres: Dictionary = CaseManager.submit("CASE_007", final_cls)
	check(not fres.is_empty() and not CaseManager.is_done("CASE_007"), "final case is not stored as a normal result")
	GameManager.game_active = false


func _test_wrong_calls() -> void:
	print("== consequences of wrong calls")
	GameManager.new_game("Wrong")
	CaseManager.submit("CASE_001", "CORRUPTED_AI")
	check(GameManager.has_flag("maria_condemned"), "condemning Maria sets a consequence flag")
	check(GameManager.trust < 50, "condemning Maria lowers trust")
	check(int(CaseManager.get_result("CASE_001")["accuracy"]) < 40, "wrong call scores low")
	_close_result("CASE_001")
	check(StoryDirector.delivered.has("m_voss_d1_bad"), "supervisor reacts to the wrong call")
	GameManager.day = 2
	StoryDirector.trigger("day_start")
	check(StoryDirector.delivered.has("m_maria_condemned"), "Maria writes after being condemned")
	var status: String = ""
	for e: Variant in CharacterManager.get_directory():
		if str(e.get("id", "")) == "MARIA_THOMPSON":
			status = str(e["status"])
	check(status == "ACCESS REVOKED", "directory reflects the decision (%s)" % status)
	# evidence system edge cases
	EvidenceManager.toggle_select("CASE_002", "h2")
	var r: Dictionary = EvidenceManager.flag_selection("CASE_002", "EMOTIONAL")
	check(str(r["status"]) == "partial", "half a comparison is reported as incomplete (%s)" % str(r["status"]))
	EvidenceManager.toggle_select("CASE_002", "h2")
	EvidenceManager.toggle_select("CASE_002", "q3")
	check(str(EvidenceManager.flag_selection("CASE_002", "EMOTIONAL")["status"]) == "match", "full comparison matches")
	EvidenceManager.toggle_select("CASE_002", "h2")
	EvidenceManager.toggle_select("CASE_002", "q3")
	check(str(EvidenceManager.flag_selection("CASE_002", "EMOTIONAL")["status"]) == "duplicate", "duplicate is not charged")
	check(EvidenceManager.requests_left("CASE_002") == 6, "two requests spent")
	for i: int in 4:
		EvidenceManager.toggle_select("CASE_002", ["h1", "h2", "h3", "h4"][i])
	check(EvidenceManager.get_selection("CASE_002").size() == 3, "selection is capped")
	# changed history
	GameManager.day = 4
	var before: String = CaseManager.line_text("CASE_001", "h1")
	EvidenceManager.mark_viewed("CASE_001:h1")
	var later: String = CaseManager.line_text("CASE_001", "h1")
	check(before != later or EvidenceManager.view_count("CASE_001:h1") > 1, "archived message changes after day 4")
	check(later.begins_with("Hello."), "changed history text shown")
	GameManager.game_active = false


func _press_all(root: Node, skip: Array) -> int:
	var n: int = 0
	for b: Node in root.find_children("*", "Button", true, false):
		var btn: Button = b
		if not is_instance_valid(btn) or btn.disabled or not btn.is_visible_in_tree():
			continue
		var blocked: bool = false
		for s: String in skip:
			if btn.text.to_upper().contains(s):
				blocked = true
		if blocked:
			continue
		btn.pressed.emit()
		n += 1
	return n


func _test_ui() -> void:
	print("== ui")
	GameManager.new_game("Interface")
	GameManager.set_flag("booted_d1")
	for scene: String in ["menu", "transition", "office", "ending"]:
		var inst: Node = (load(GameManager.SCENES[scene]) as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		check(is_instance_valid(inst), scene + " scene instantiates")
		if scene == "office":
			for obj: String in ["computer", "phone", "cabinet", "coffee", "door", "board", "window"]:
				check(str(inst.call("dialogue_for", obj)) != "", "office object usable: " + obj)
		inst.queue_free()
		await get_tree().process_frame
	DialogueManager.cancel()
	GameManager.game_active = true
	var desk: Control = (load(GameManager.SCENES["desktop"]) as PackedScene).instantiate()
	add_child(desk)
	await get_tree().process_frame
	for app: String in ["cases", "archive", "directory", "email", "monitor", "notes", "terminal", "shutdown"]:
		var c: Variant = desk.call("open_app", app, {})
		await get_tree().process_frame
		check(c != null and bool(desk.call("is_open", app)), "app opens: " + app)
	desk.call("open_app", "workbench", {"case_id": "CASE_001"})
	await get_tree().process_frame
	check(bool(desk.call("is_open", "workbench")), "workbench opens")
	desk.call("close_modal")
	var wb: Node = (desk.get("windows")["workbench"] as Node).get("content")
	wb.call("_on_line_toggled", "h4")
	wb.call("_on_line_toggled", "q2")
	check(EvidenceManager.get_selection("CASE_001").size() == 2, "lines selectable in the workbench")
	wb.call("_on_flag_pressed")
	check(EvidenceManager.found_clue_ids("CASE_001").has("e2"), "evidence collected through the workbench")
	wb.call("_set_left_mode", "files")
	await get_tree().process_frame
	desk.call("open_classification", "CASE_001")
	await get_tree().process_frame
	check(bool(desk.call("is_modal_open")), "classification dialog opens")
	desk.call("_confirm_classification", "CASE_001", "VERIFIED_HUMAN")
	await get_tree().process_frame
	check(bool(desk.call("is_modal_open")), "confirmation is required before submitting")
	desk.call("close_modal")
	desk.call("_submit_classification", "CASE_001", "VERIFIED_HUMAN")
	await get_tree().process_frame
	check(CaseManager.is_done("CASE_001"), "classification submitted through the desktop")
	check(bool(desk.call("is_open", "result")), "result window opens")
	desk.call("close_app", "result")
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.has_flag("result_ack:CASE_001"), "closing the result fires its story trigger")
	# press every remaining button except ones that leave the scene
	var pressed: int = _press_all(desk, ["END SHIFT", "STAND UP", "QUIT", "X", "SUBMIT"])
	await get_tree().process_frame
	await get_tree().process_frame
	print("  pressed %d desktop buttons" % pressed)
	desk.call("close_modal")
	desk.call("show_settings")
	await get_tree().process_frame
	check(bool(desk.call("is_modal_open")), "settings open from the desktop")
	SaveManager.set_setting("text_scale", 1.3)
	check(UI.theme.default_font_size == roundi(15 * 1.3), "text scaling applies")
	SaveManager.set_setting("text_scale", 1.0)
	SaveManager.set_setting("screen_distortion", false)
	SaveManager.set_setting("screen_distortion", true)
	SaveManager.set_setting("master_volume", 0.5)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.5) < 0.01, "master volume applies")
	SaveManager.set_setting("master_volume", 0.8)
	for i: int in 6:
		var a: Dictionary = StoryDirector.pop_desktop_action()
		if not a.is_empty():
			desk.call("_run_story_action", a)
	await get_tree().create_timer(0.5).timeout
	desk.queue_free()
	await get_tree().process_frame
	GameManager.game_active = false
