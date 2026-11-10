extends Control
## HVC TERMINAL: the fictional operating system. Owns the window manager, the
## taskbar, toasts, modal dialogs, the boot screen and the story action queue.

const WindowScript := preload("res://ui/windows/desktop_window.gd")
const SettingsPanel := preload("res://ui/components/settings_panel.gd")

const APPS := {
	"cases": {"title": "CASE DATABASE", "glyph": "DB", "script": "res://ui/windows/app_case_database.gd", "size": Vector2(900, 580)},
	"archive": {"title": "MESSAGE ARCHIVE", "glyph": "MSG", "script": "res://ui/windows/app_message_archive.gd", "size": Vector2(960, 580)},
	"directory": {"title": "EMPLOYEE DIRECTORY", "glyph": "DIR", "script": "res://ui/windows/app_employee_directory.gd", "size": Vector2(820, 540)},
	"email": {"title": "INTERNAL EMAIL", "glyph": "@", "script": "res://ui/windows/app_email.gd", "size": Vector2(880, 540)},
	"monitor": {"title": "SYSTEM MONITOR", "glyph": "SYS", "script": "res://ui/windows/app_system_monitor.gd", "size": Vector2(760, 560)},
	"notes": {"title": "PERSONAL NOTES", "glyph": "TXT", "script": "res://ui/windows/app_notes.gd", "size": Vector2(520, 460)},
	"terminal": {"title": "TERMINAL", "glyph": ">_", "script": "res://ui/windows/app_terminal.gd", "size": Vector2(700, 480)},
	"shutdown": {"title": "EXIT / SHUTDOWN", "glyph": "I/O", "script": "res://ui/windows/app_shutdown.gd", "size": Vector2(460, 430)},
	"workbench": {"title": "VERIFICATION WORKBENCH", "scene": "res://scenes/investigation/investigation_view.tscn", "size": Vector2(1220, 668), "hidden": true},
	"result": {"title": "OFFICIAL RESULT", "script": "res://ui/windows/app_case_result.gd", "size": Vector2(700, 600), "hidden": true},
}
## Icon labels decay from day 4 onward (corrupted desktop icons).
const CORRUPT_LABELS := {
	4: {"archive": "MESSAGE ARCH1VE", "directory": "EMPLOYEE DIRECT0RY", "monitor": "SYSTEM M0NITOR"},
	5: {"cases": "CASE DATA8ASE", "archive": "M3SSAGE ARCH1VE", "directory": "EMPLOYEE D1RECT0RY",
		"email": "INTERNAL EMA1L", "monitor": "SYST3M M0N1TOR", "notes": "PERSONAL N0TES?", "terminal": "T3RMINAL", "shutdown": "EX1T / SHUTD0WN"},
}

var windows: Dictionary = {}        # window id -> window node
var _window_layer: Control
var _task_buttons: HBoxContainer
var _clock: Label
var _mail_label: Label
var _toasts: VBoxContainer
var _modal_layer: Control
var _modal_dismissable: bool = false
var _boot: Control
var _booting: bool = false
var _queue_timer: float = 0.0
var _clock_seconds: float = 0.0
var _spawn_count: int = 0
var _hdd_timer: float = 6.0


func _ready() -> void:
	UI.full_rect(self)
	_build()
	StoryDirector.emails_changed.connect(_refresh_taskbar)
	ScreenFX.set_corruption(float(GameManager.day - 1) / 4.0 * 0.8)
	var boot_flag: String = "booted_d%d" % GameManager.day
	if GameManager.has_flag(boot_flag):
		_on_boot_finished(false)
	else:
		_start_boot(boot_flag)


func _exit_tree() -> void:
	DialogueManager.cancel()


# ---------------------------------------------------------------- layout

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UI.C_DARK
	UI.full_rect(bg)
	add_child(bg)
	var wall := TextureRect.new()
	wall.texture = UI.photo("res://assets/environments/desktop_wallpaper.jpg")
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wall.material = UI.photo_material(0.10 + 0.12 * float(GameManager.day), 0.0, 0.45)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(wall)
	add_child(wall)

	var brand := UI.label("HUMAN VERIFICATION CORPORATION", "TermBig")
	brand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_offsets(brand, -520, -124, -14, -92)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brand.modulate.a = 0.55
	add_child(brand)
	var motto := UI.label("\"Certainty is a service.\"" if GameManager.day < 4 else "\"Certainty is a serv", "TermLabel")
	motto.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_offsets(motto, -520, -86, -14, -60)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	motto.modulate.a = 0.55
	add_child(motto)

	_window_layer = Control.new()
	_window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window_layer.offset_bottom = -40
	add_child(_window_layer)

	var icons := GridContainer.new()
	icons.columns = 2
	icons.position = Vector2(18, 16)
	icons.add_theme_constant_override("h_separation", 14)
	icons.add_theme_constant_override("v_separation", 12)
	_window_layer.add_child(icons)
	var corrupt: Dictionary = CORRUPT_LABELS.get(mini(GameManager.day, 5), {})
	for id: String in APPS:
		if bool(APPS[id].get("hidden", false)):
			continue
		icons.add_child(_make_icon(id, str(corrupt.get(id, APPS[id]["title"])), corrupt.has(id)))

	var bar := UI.panel("TaskBar")
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -40
	add_child(bar)
	var h := UI.hbox(8)
	bar.add_child(h)
	var start := UI.button("HVC", func() -> void: open_app("shutdown"), "TermButton")
	start.tooltip_text = "Exit / Shutdown"
	h.add_child(start)
	_task_buttons = UI.hbox(4)
	_task_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_buttons.clip_contents = true
	h.add_child(_task_buttons)
	_mail_label = UI.label("", "RedLabel")
	h.add_child(_mail_label)
	_clock = UI.label("", "HeaderLabel")
	h.add_child(_clock)

	_toasts = UI.vbox(6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_offsets(_toasts, -384, -360, -14, -52)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_modal_layer = Control.new()
	UI.full_rect(_modal_layer)
	_modal_layer.visible = false
	add_child(_modal_layer)
	_update_clock()
	_refresh_taskbar()


func _offsets(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _make_icon(id: String, title: String, corrupted: bool) -> Control:
	var b := Button.new()
	b.theme_type_variation = "TermButton"
	b.custom_minimum_size = Vector2(150, 84)
	b.tooltip_text = "Open " + str(APPS[id]["title"])
	b.pressed.connect(func() -> void: open_app(id))
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(v)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	var glyph := UI.label(str(APPS[id]["glyph"]), "TermBig")
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if corrupted:
		glyph.theme_type_variation = "BigLabel"
		glyph.add_theme_color_override("font_color", UI.C_RED)
	v.add_child(glyph)
	var l := UI.label(title, "TermSmall")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return b


# ---------------------------------------------------------------- boot screen

func _start_boot(boot_flag: String) -> void:
	_booting = true
	_boot = UI.panel("Term")
	UI.full_rect(_boot)
	add_child(_boot)
	var v := UI.vbox(4)
	_boot.add_child(UI.margin(v, 40))
	v.add_child(UI.label("HVC TERMINAL", "TermBig"))
	var log_label := UI.rich("TermRich")
	v.add_child(log_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	v.add_child(bar)
	v.add_child(UI.label("Press any key to skip", "TermSmall"))
	var lines: Array = [
		"HVC TERMINAL v4.1  (c) Human Verification Corporation",
		"MEMORY CHECK .............. 640K OK",
		"MOUNTING /identity ........ OK",
		"MOUNTING /archive ......... OK",
		"STARTING svc-continuity ... OK",
	]
	for extra: Variant in GameManager.get_day_info().get("boot_lines", []):
		lines.append(GameManager.format_text(str(extra)))
	lines.append("LOADING PROFILE %s ....... OK" % GameManager.EMPLOYEE_ID)
	lines.append("WELCOME, %s." % GameManager.player_name.to_upper())
	AudioManager.play_sfx("boot", -6.0)
	AudioManager.play_sfx("hdd", -8.0)
	for i: int in lines.size():
		if not _booting:
			break
		log_label.append_text(str(lines[i]) + "\n")
		bar.value = 100.0 * float(i + 1) / float(lines.size())
		await get_tree().create_timer(0.32).timeout
	if _booting:
		await get_tree().create_timer(0.5).timeout
	GameManager.set_flag(boot_flag)
	_on_boot_finished(true)


func _on_boot_finished(first_time: bool) -> void:
	_booting = false
	if _boot != null and is_instance_valid(_boot):
		_boot.queue_free()
	_boot = null
	_apply_ambience()
	StoryDirector.on_desktop_ready()
	if first_time:
		StoryDirector.trigger("desktop_ready")
		SaveManager.save_game()
	_queue_timer = 1.2


func _apply_ambience() -> void:
	if GameManager.has_flag("ambience_dead"):
		AudioManager.apply_preset("desktop_dead")
	elif GameManager.day >= 4:
		AudioManager.apply_preset("desktop_wrong")
		AudioManager.play_music("drone", -20.0, 6.0)
	else:
		AudioManager.apply_preset("desktop")
		AudioManager.stop_music()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_clock_seconds += delta
	if _clock_seconds >= 1.0:
		_clock_seconds = 0.0
		_update_clock()
	if _booting:
		return
	_hdd_timer -= delta
	if _hdd_timer <= 0.0:
		_hdd_timer = randf_range(9.0, 22.0)
		if not GameManager.has_flag("ambience_dead"):
			AudioManager.play_sfx("hdd", -16.0, randf_range(0.9, 1.1))
	_queue_timer -= delta
	if _queue_timer <= 0.0:
		_queue_timer = 1.3
		if not _modal_layer.visible and not DialogueManager.is_active():
			_run_story_action(StoryDirector.pop_desktop_action())


var _clock_minutes: int = 0

func _update_clock() -> void:
	_clock_minutes += 1
	var total: int = 9 * 60 + int(float(_clock_minutes) / 2.0)
	var time_text: String = "%02d:%02d" % [(total / 60) % 24, total % 60]
	# From day 3 the clock occasionally insists on a different time.
	if GameManager.day >= 3 and _clock_minutes % 47 >= 44:
		time_text = "03:14"
	var info: Dictionary = GameManager.get_day_info()
	_clock.text = "DAY %d  %s  %s " % [GameManager.day, str(info.get("date", "")), time_text]


func _run_story_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	match str(action.get("type", "")):
		"toast":
			toast(str(action.get("text", "")), str(action.get("style", "")), float(action.get("duration", 4.5)))
			if action.has("sfx"):
				AudioManager.play_sfx(str(action["sfx"]), -6.0)
			if action.has("glitch"):
				ScreenFX.pulse(float(action["glitch"]), 0.5)
		"error_dialog":
			AudioManager.play_sfx("error", -4.0)
			if action.has("glitch"):
				ScreenFX.pulse(float(action["glitch"]), 0.5)
			show_message(str(action.get("title", "SYSTEM")), str(action.get("text", "")), str(action.get("button", "OK")))
		"open_app":
			var args: Variant = action.get("args", {})
			open_app(str(action.get("app", "")), args if args is Dictionary else {})
		"terminal_dialogue":
			var did: String = str(action.get("id", ""))
			if not DialogueManager.is_completed(did):
				AudioManager.play_sfx("interference", -8.0)
				ScreenFX.pulse(0.5, 0.6)
				open_app("terminal", {"dialogue": did})


# ---------------------------------------------------------------- window manager

func open_app(id: String, args: Dictionary = {}) -> Control:
	if not APPS.has(id):
		push_warning("Desktop: unknown app '%s'" % id)
		return null
	if windows.has(id) and is_instance_valid(windows[id]):
		var existing: Control = windows[id]
		existing.move_to_front()
		var c: Control = existing.get("content")
		if c != null and c.has_method("open_args"):
			c.call("open_args", args)
		_refresh_taskbar()
		return c
	var def: Dictionary = APPS[id]
	var content: Control
	if def.has("scene"):
		content = (load(str(def["scene"])) as PackedScene).instantiate() as Control
	else:
		content = (load(str(def["script"])) as GDScript).new() as Control
	if content == null:
		push_error("Desktop: could not create app '%s'" % id)
		return null
	content.set("desktop", self)
	var w: PanelContainer = WindowScript.new()
	var area: Vector2 = _window_layer.size
	var win_size: Vector2 = Vector2(minf((def["size"] as Vector2).x, area.x - 8.0), minf((def["size"] as Vector2).y, area.y - 4.0))
	w.call("setup", id, str(def["title"]), content, win_size)
	_window_layer.add_child(w)
	var offset: float = float(_spawn_count % 5) * 22.0
	_spawn_count += 1
	w.position = Vector2(maxf((area.x - win_size.x) * 0.5 + offset + 60.0, 0.0), maxf((area.y - win_size.y) * 0.4 + offset, 0.0))
	w.call("clamp_to_parent")
	w.connect("closed", _on_window_closed)
	windows[id] = w
	if content.has_method("open_args"):
		content.call("open_args", args)
	AudioManager.play_sfx("open", -8.0)
	_refresh_taskbar()
	StoryDirector.trigger("app_opened:" + id)
	return content


func close_app(id: String) -> void:
	if windows.has(id) and is_instance_valid(windows[id]):
		(windows[id] as Node).call("request_close")


func is_open(id: String) -> bool:
	return windows.has(id) and is_instance_valid(windows[id])


func set_window_title(id: String, title: String) -> void:
	if is_open(id):
		(windows[id] as Node).call("set_title", title)
		_refresh_taskbar()


func _on_window_closed(id: String) -> void:
	windows.erase(id)
	_refresh_taskbar.call_deferred()


func _refresh_taskbar() -> void:
	if _task_buttons == null:
		return
	UI.clear(_task_buttons)
	for id: String in windows:
		if not is_instance_valid(windows[id]):
			continue
		var title: String = str((windows[id] as Node).call("get_title"))
		var b := UI.button(title.substr(0, 22), func() -> void:
			if is_open(id):
				(windows[id] as Control).move_to_front())
		_task_buttons.add_child(b)
	var unread: int = StoryDirector.unread_count()
	_mail_label.text = "MAIL: %d UNREAD" % unread if unread > 0 else ""


func _input(event: InputEvent) -> void:
	if _booting:
		if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
			_booting = false
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _modal_layer.visible:
		# Bring the clicked window to the front.
		var pos: Vector2 = (event as InputEventMouseButton).position
		var kids: Array[Node] = _window_layer.get_children()
		for i: int in range(kids.size() - 1, -1, -1):
			var w: Node = kids[i]
			if w is PanelContainer and w.has_method("request_close") and (w as Control).get_global_rect().has_point(pos):
				(w as Control).move_to_front()
				break


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _booting:
		return
	get_viewport().set_input_as_handled()
	if _modal_layer.visible:
		if _modal_dismissable:
			close_modal()
		return
	var kids: Array[Node] = _window_layer.get_children()
	for i: int in range(kids.size() - 1, -1, -1):
		if kids[i].has_method("request_close"):
			kids[i].call("request_close")
			return
	open_app("shutdown")


# ---------------------------------------------------------------- toasts / modals

func toast(text: String, style: String = "", duration: float = 4.5) -> void:
	if text == "":
		return
	var variation: String = "Toast"
	var label_var: String = ""
	if style == "error":
		variation = "ToastError"
		label_var = "WhiteLabel"
	elif style == "term":
		variation = "ToastTerm"
		label_var = "TermLabel"
	var p := UI.panel(variation)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(GameManager.format_text(text), label_var, true)
	l.custom_minimum_size.x = 330
	p.add_child(l)
	_toasts.add_child(p)
	var tw: Tween = p.create_tween()
	tw.tween_interval(maxf(duration, 0.5))
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func show_modal(content: Control, dismissable: bool = false) -> void:
	UI.clear(_modal_layer)
	_modal_dismissable = dismissable
	var dim := UI.panel("Dim")
	UI.full_rect(dim)
	_modal_layer.add_child(dim)
	var center := CenterContainer.new()
	UI.full_rect(center)
	_modal_layer.add_child(center)
	var frame := UI.panel("WindowFrame")
	frame.add_child(UI.margin(content, 12))
	center.add_child(frame)
	_modal_layer.visible = true
	var first: Control = content.find_next_valid_focus()
	if first != null:
		first.grab_focus.call_deferred()


func close_modal() -> void:
	UI.clear(_modal_layer)
	_modal_layer.visible = false


func is_modal_open() -> bool:
	return _modal_layer.visible


func show_message(title: String, text: String, button_text: String = "OK", on_close: Callable = Callable()) -> void:
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 440
	var bar := UI.panel("TitleBar")
	bar.add_child(UI.label(title, "WhiteLabel"))
	v.add_child(bar)
	var l := UI.label(GameManager.format_text(text), "", true)
	l.custom_minimum_size.x = 420
	v.add_child(l)
	var b := UI.button(button_text, func() -> void:
		close_modal()
		if on_close.is_valid():
			on_close.call())
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	show_modal(v, not on_close.is_valid())


func show_confirm(title: String, text: String, yes_text: String, on_yes: Callable, no_text: String = "CANCEL") -> void:
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 460
	var bar := UI.panel("TitleBar")
	bar.add_child(UI.label(title, "WhiteLabel"))
	v.add_child(bar)
	var l := UI.label(text, "", true)
	l.custom_minimum_size.x = 440
	v.add_child(l)
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UI.button(no_text, close_modal))
	h.add_child(UI.button(yes_text, func() -> void:
		close_modal()
		on_yes.call(), "DangerButton"))
	v.add_child(h)
	show_modal(v, true)


func show_settings() -> void:
	var s: VBoxContainer = SettingsPanel.new()
	s.custom_minimum_size.x = 520
	s.connect("back_pressed", close_modal)
	show_modal(s, true)


# ---------------------------------------------------------------- classification flow

## Opens the four-way classification dialog for a case, with confirmation.
func open_classification(case_id: String) -> void:
	var c: Dictionary = CaseManager.get_case(case_id)
	if c.is_empty() or CaseManager.is_done(case_id):
		return
	var who: String = CharacterManager.get_name_of(str(c["character_id"]))
	var v := UI.vbox(8)
	v.custom_minimum_size.x = 620
	var bar := UI.panel("TitleBar")
	bar.add_child(UI.label("SUBMIT DECISION  -  CASE %s  -  %s" % [str(c.get("number", "")), who.to_upper()], "WhiteLabel"))
	v.add_child(bar)
	var found: int = EvidenceManager.found_clue_ids(case_id).size()
	v.add_child(UI.label("Confirmed findings on file: %d.   Unverified observations: %d." % [found, EvidenceManager.get_for_case(case_id).size() - found], "SmallLabel", true))
	v.add_child(UI.label("Select one classification. You will be asked to confirm.", "", true))
	for cls: String in CaseManager.CLASSIFICATIONS:
		var b := UI.button(str(CaseManager.CLASS_LABELS[cls]), func() -> void: _confirm_classification(case_id, cls))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
		var d := UI.label(str(CaseManager.CLASS_DESCRIPTIONS[cls]), "SmallLabel", true)
		d.custom_minimum_size.x = 600
		v.add_child(d)
	var cancel := UI.button("CANCEL", close_modal)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(cancel)
	show_modal(v, true)


func _confirm_classification(case_id: String, cls: String) -> void:
	var c: Dictionary = CaseManager.get_case(case_id)
	var who: String = CharacterManager.get_name_of(str(c["character_id"]))
	show_confirm("CONFIRM SUBMISSION",
		"Classify %s as %s?\n\nThis decision is final. It will be entered into the subject's permanent record and acted upon." % [who, str(CaseManager.CLASS_LABELS[cls])],
		"SUBMIT: " + str(CaseManager.CLASS_LABELS[cls]),
		func() -> void: _submit_classification(case_id, cls), "GO BACK")


func _submit_classification(case_id: String, cls: String) -> void:
	var c: Dictionary = CaseManager.get_case(case_id)
	AudioManager.play_sfx("stamp", -2.0)
	var result: Dictionary = CaseManager.submit(case_id, cls)
	if result.is_empty():
		show_message("SUBMISSION FAILED", "The classification could not be recorded. Please try again.")
		return
	close_app("workbench")
	if bool(c.get("final", false)):
		ScreenFX.pulse(1.0, 1.2)
		AudioManager.silence(0.2)
		GameManager.finish_game(cls)
		return
	if is_open("cases"):
		(windows["cases"].get("content") as Node).call("refresh")
	open_app("result", {"case_id": case_id})
