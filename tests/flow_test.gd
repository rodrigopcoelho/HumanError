extends Node
## Drives the real game through its scene changes (menu -> day card -> office ->
## desktop -> end of shift -> next day -> ending -> menu).
## Run: godot --path . res://tests/flow_test.tscn

var _fails: int = 0


func check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1


func _scene_name() -> String:
	var s: Node = get_tree().current_scene
	return str(s.name) if s != null else ""


func _wait_scene(expected: String) -> void:
	for i: int in 200:
		await get_tree().process_frame
		if _scene_name() == expected and not GameManager._changing_scene:
			break
	check(_scene_name() == expected, "scene is " + expected + " (got " + _scene_name() + ")")


func _ready() -> void:
	SaveManager.save_path = "user://test_save.json"
	SaveManager.settings_path = "user://test_settings.json"
	SaveManager.delete_save()
	_run.call_deferred()


func _run() -> void:
	var root: Window = get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	GameManager.goto_scene("menu")
	await _wait_scene("MainMenu")
	GameManager.new_game("Flow")
	await _wait_scene("DayTransition")
	for i: int in 3:
		get_tree().current_scene.call("_next")
		await get_tree().create_timer(0.1).timeout
	await _wait_scene("Office")
	check(str(get_tree().current_scene.call("dialogue_for", "phone")) == "office_phone_d1_morning", "phone is ringing on day 1")
	get_tree().current_scene.call("_interact", "computer")
	await get_tree().process_frame
	check(DialogueManager.is_active(), "computer dialogue opens")
	DialogueManager.choose(0)
	await _wait_scene("Desktop")
	await get_tree().create_timer(4.5).timeout
	check(GameManager.has_flag("booted_d1"), "boot sequence completes")
	var desk: Node = get_tree().current_scene
	desk.call("open_app", "workbench", {"case_id": "CASE_001"})
	await get_tree().process_frame
	desk.call("close_modal")
	desk.call("_submit_classification", "CASE_001", "VERIFIED_HUMAN")
	await get_tree().create_timer(0.3).timeout
	desk.call("close_app", "result")
	await get_tree().create_timer(0.3).timeout
	check(GameManager.can_end_shift(), "shift can end after the case")
	GameManager.end_shift()
	await _wait_scene("Office")
	check(GameManager.phase == "evening", "it is evening")
	get_tree().current_scene.call("_interact", "door")
	await get_tree().process_frame
	DialogueManager.choose(0)
	await _wait_scene("DayTransition")
	check(GameManager.day == 2, "day advanced to 2")
	# Continue from the save
	GameManager.quit_to_menu()
	await _wait_scene("MainMenu")
	check(GameManager.continue_game(), "continue loads the save")
	await _wait_scene("DayTransition")
	check(GameManager.day == 2 and CaseManager.is_done("CASE_001"), "progress restored after continue")
	GameManager.finish_game("UNDETERMINED")
	await _wait_scene("Ending")
	for i: int in 30:
		if _scene_name() != "Ending":
			break
		get_tree().current_scene.call("_next")
		await get_tree().create_timer(0.05).timeout
	await _wait_scene("MainMenu")
	SaveManager.delete_save()
	print("flow test failures: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
