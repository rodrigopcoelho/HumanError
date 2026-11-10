extends Node
## Visual check: renders each screen and saves PNGs.
## Run: godot --path . res://tests/screenshot_tour.tscn -- <output_dir>

var _out: String = "user://shots"
var _n: int = 0


func _shot(label: String, wait: float = 0.8) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_n += 1
	img.save_png(_out.path_join("%02d_%s.png" % [_n, label]))
	print("shot ", label)


func _scene(key: String) -> Node:
	var inst: Node = (load(GameManager.SCENES[key]) as PackedScene).instantiate()
	add_child(inst)
	return inst


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	SaveManager.save_path = "user://test_save.json"
	SaveManager.settings_path = "user://test_settings.json"
	GameManager.scene_changes_enabled = false
	var s: Node = _scene("menu")
	await _shot("menu")
	s.queue_free()
	GameManager.new_game("R. Coelho")
	s = _scene("transition")
	await _shot("transition", 1.6)
	s.queue_free()
	s = _scene("office")
	await _shot("office_desk")
	for yaw: float in [-1.45, 3.14, 1.45]:
		s.set("_yaw", yaw)
		await _shot("office_%d" % int(yaw * 100), 0.4)
	s.call("_interact", "cabinet")
	await _shot("office_dialogue", 1.5)
	DialogueManager.cancel()
	s.queue_free()
	GameManager.set_flag("booted_d1")
	var desk: Node = _scene("desktop")
	StoryDirector.trigger("desktop_ready")
	await _shot("desktop", 2.5)
	desk.call("open_app", "email", {})
	await _shot("email", 0.6)
	desk.call("close_app", "email")
	desk.call("open_app", "cases", {})
	await _shot("cases", 0.6)
	desk.call("close_app", "cases")
	desk.call("open_app", "workbench", {"case_id": "CASE_001"})
	await get_tree().process_frame
	await _shot("workbench_help", 0.5)
	desk.call("close_modal")
	var wb: Node = (desk.get("windows")["workbench"] as Node).get("content")
	wb.call("_on_line_toggled", "h4")
	wb.call("_on_line_toggled", "q2")
	wb.call("_on_flag_pressed")
	wb.call("_on_line_toggled", "h1")
	await _shot("workbench", 0.6)
	desk.call("open_classification", "CASE_001")
	await _shot("classify", 0.5)
	desk.call("close_modal")
	desk.call("_submit_classification", "CASE_001", "VERIFIED_HUMAN")
	await _shot("result", 0.8)
	desk.call("close_app", "result")
	desk.call("open_app", "directory", {"employee_id": "MARIA_THOMPSON"})
	await _shot("directory", 0.6)
	desk.call("close_app", "directory")
	desk.queue_free()
	# Day 4: degraded system
	for cid: String in ["CASE_002", "CASE_003"]:
		CaseManager.submit(cid, "CORRUPTED_AI" if cid == "CASE_002" else "VERIFIED_HUMAN")
		GameManager.set_flag("result_ack:" + cid)
	GameManager.day = 4
	GameManager.set_flag("booted_d4")
	StoryDirector.desktop_queue.clear()
	desk = _scene("desktop")
	desk.call("open_app", "monitor", {})
	await _shot("monitor_day4", 3.5)
	desk.call("close_app", "monitor")
	desk.call("open_app", "terminal", {"dialogue": "u07_day4"})
	await _shot("terminal", 1.0)
	DialogueManager.cancel()
	desk.queue_free()
	s = _scene("office")
	await _shot("office_day4", 1.0)
	s.set("_yaw", -1.45)
	await _shot("office_day4_window", 0.5)
	s.queue_free()
	GameManager.day = 5
	GameManager.set_flag("player_record_visible")
	GameManager.set_flag("booted_d5")
	desk = _scene("desktop")
	desk.call("open_app", "directory", {"employee_id": "PLAYER"})
	await _shot("player_record", 1.0)
	desk.queue_free()
	GameManager.ending = "C"
	s = _scene("ending")
	for i: int in 11:
		s.call("_next")
	await _shot("ending", 2.5)
	SaveManager.delete_save()
	get_tree().quit()
