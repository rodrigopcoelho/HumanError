extends Node3D
## The analyst's office: a small first-person room built from primitives and
## photographs. You sit in the chair and look around; seven things can be used.
## What the room looks like each day comes from data/story_events/office.json.

const OFFICE_FILE := "res://data/story_events/office.json"
const SettingsPanel := preload("res://ui/components/settings_panel.gd")
const TURN_SPEED := 1.7
const HOTSPOT_LABELS := {
	"computer": "Your computer", "phone": "Desk phone", "cabinet": "Filing cabinet",
	"coffee": "Coffee machine", "door": "Office door", "board": "Notice board", "window": "Window",
}

var _cfg: Dictionary = {}
var _cam: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _turn_left: bool = false
var _turn_right: bool = false
var _dragging: bool = false
var _lights: Array[OmniLight3D] = []
var _tube_mats: Array[StandardMaterial3D] = []
var _base_energy: float = 1.0
var _flicker: float = 0.0
var _time: float = 0.0
var _hover_id: String = ""
var _hover_label: Label
var _reflection: MeshInstance3D
var _refl_yaw: float = 0.0
var _refl_delay: float = 0.0
var _ring_dialogue: String = ""
var _ring_config: String = ""
var _ring_timer: float = 1.5
var _phone_led: StandardMaterial3D
var _hud: CanvasLayer
var _pause: Control
var _leaving: bool = false


func _ready() -> void:
	_load_config()
	_build_room()
	_build_hud()
	ScreenFX.set_corruption(float(GameManager.day - 1) / 4.0 * 0.8)
	AudioManager.apply_preset(str(_cfg.get("ambience", "office")))
	if bool(_cfg.get("music", false)):
		AudioManager.play_music("drone", -20.0, 6.0)
	else:
		AudioManager.stop_music()
	DialogueManager.action_requested.connect(_on_action)
	var ring: String = str(_cfg.get("phone_ring", ""))
	_ring_config = ring
	if ring != "" and DialogueManager.has_dialogue(ring) and not DialogueManager.is_completed(ring):
		_ring_dialogue = ring
	GameManager.location = "office"
	StoryDirector.trigger("office_entered")


func _load_config() -> void:
	var data: Variant = SaveManager.read_data_file(OFFICE_FILE)
	var days: Variant = (data as Dictionary).get("days", {}) if data is Dictionary else {}
	var d: Variant = (days as Dictionary).get(str(GameManager.day), {}) if days is Dictionary else {}
	_cfg = (d as Dictionary).duplicate(true) if d is Dictionary else {}
	if GameManager.phase == "evening" and _cfg.get("evening") is Dictionary:
		for k: String in (_cfg["evening"] as Dictionary):
			_cfg[k] = _cfg["evening"][k]


# ---------------------------------------------------------------- construction

func _mat(color: Color, emission_energy: float = 0.0, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m


func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _hotspot(id: String, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.set_meta("hotspot", id)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	add_child(body)


func _photo_quad(pos: Vector3, size: Vector2, rot_y_deg: float, path: String, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = UI.photo(path)
	m.albedo_color = Color(energy, energy, energy)
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees.y = rot_y_deg
	add_child(mi)
	return mi


func _text3d(text: String, pos: Vector3, rot_y_deg: float, color: Color, pixel: float = 0.0016, width: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = GameManager.format_text(text)
	l.font = UI.font_body
	l.font_size = 48
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.position = pos
	l.rotation_degrees.y = rot_y_deg
	if width > 0.0:
		l.width = width / pixel
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _build_room() -> void:
	var light: float = float(_cfg.get("light", 1.0))
	_base_energy = light
	_flicker = float(_cfg.get("flicker", 0.0))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.58)
	env.ambient_light_energy = 0.22 * light
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.09, 0.07)
	env.fog_density = 0.035 + 0.02 * float(GameManager.day)
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.25, 0.7)
	_cam.fov = 68.0
	_cam.current = true
	add_child(_cam)

	var wall := _mat(Color("8f8b78"))
	var trim := _mat(Color("3a4a40"))
	var carpet := _mat(Color("1b2c23"))
	var beige := _mat(Color("b5ae97"), 0.0, 0.6)
	var dark := _mat(Color("151a17"), 0.0, 0.5)
	var metal := _mat(Color("6f7a70"), 0.0, 0.4)
	var paper := _mat(Color("d9d5c8"))
	# Shell
	_box(Vector3(0, -0.05, 0), Vector3(6.2, 0.1, 6.2), carpet)
	_box(Vector3(0, 2.85, 0), Vector3(6.2, 0.1, 6.2), _mat(Color("a8a595")))
	_box(Vector3(0, 1.4, -3.05), Vector3(6.2, 2.9, 0.1), wall)
	_box(Vector3(0, 1.4, 3.05), Vector3(6.2, 2.9, 0.1), wall)
	_box(Vector3(-3.05, 1.4, 0), Vector3(0.1, 2.9, 6.2), wall)
	_box(Vector3(3.05, 1.4, 0), Vector3(0.1, 2.9, 6.2), wall)
	for z: float in [-2.98, 2.98]:
		_box(Vector3(0, 0.06, z), Vector3(6.0, 0.12, 0.04), trim)
	for x: float in [-2.98, 2.98]:
		_box(Vector3(x, 0.06, 0), Vector3(0.04, 0.12, 6.0), trim)
	# Ceiling lights
	for z: float in [-0.9, 1.7]:
		var tm := _mat(Color("e8f0e0"), 2.2 * light)
		_tube_mats.append(tm)
		_box(Vector3(0, 2.78, z), Vector3(1.3, 0.05, 0.22), tm)
		var ol := OmniLight3D.new()
		ol.position = Vector3(0, 2.5, z)
		ol.omni_range = 6.5
		ol.light_color = Color(0.86, 0.95, 0.84)
		ol.light_energy = 1.25 * light
		add_child(ol)
		_lights.append(ol)

	# Desk, monitor, keyboard (north)
	_box(Vector3(0, 0.74, -1.3), Vector3(1.9, 0.06, 0.85), _mat(Color("5b5444"), 0.0, 0.5))
	for x: float in [-0.88, 0.88]:
		_box(Vector3(x, 0.37, -1.3), Vector3(0.06, 0.74, 0.8), dark)
	_box(Vector3(0, 1.03, -1.45), Vector3(0.56, 0.48, 0.5), beige)
	_box(Vector3(0, 0.8, -1.4), Vector3(0.3, 0.06, 0.3), beige)
	var screen_color: Color = Color("3a0d0d") if bool(_cfg.get("monitor_red", false)) else Color("0d2416")
	_box(Vector3(0, 1.04, -1.195), Vector3(0.44, 0.34, 0.01), _mat(screen_color, 1.6))
	var text_color: Color = Color("e06a6a") if bool(_cfg.get("monitor_red", false)) else Color("9abf9a")
	_text3d(str(_cfg.get("monitor_text", "HVC TERMINAL\n> AWAITING LOGIN")), Vector3(0, 1.04, -1.185), 0.0, text_color, 0.00055, 0.4)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.05, -0.95)
	glow.omni_range = 2.2
	glow.light_energy = 0.5
	glow.light_color = text_color
	add_child(glow)
	_box(Vector3(0, 0.785, -1.02), Vector3(0.5, 0.03, 0.17), beige)
	_hotspot("computer", Vector3(0, 1.0, -1.3), Vector3(0.7, 0.6, 0.7))
	# Phone
	_box(Vector3(0.66, 0.8, -1.15), Vector3(0.24, 0.07, 0.22), dark)
	_box(Vector3(0.6, 0.85, -1.15), Vector3(0.07, 0.04, 0.24), dark)
	_phone_led = _mat(Color("9e2929"), 0.2)
	_box(Vector3(0.73, 0.84, -1.08), Vector3(0.03, 0.01, 0.03), _phone_led)
	_hotspot("phone", Vector3(0.66, 0.84, -1.15), Vector3(0.32, 0.2, 0.3))
	# Wall clock (north)
	_box(Vector3(1.6, 2.0, -2.98), Vector3(0.42, 0.24, 0.04), dark)
	_text3d(str(_cfg.get("clock", "09:02")), Vector3(1.6, 2.0, -2.955), 0.0, Color("c86060"), 0.0022)
	_text3d("HUMAN VERIFICATION CORPORATION\nIDENTITY SERVICES  -  ROOM 0417", Vector3(-1.2, 2.1, -2.99), 0.0, Color("2a3a30"), 0.0012)

	# Window (east)
	_box(Vector3(2.99, 1.5, -0.4), Vector3(0.05, 1.36, 2.0), trim)
	_photo_quad(Vector3(2.955, 1.5, -0.4), Vector2(1.86, 1.22), -90.0, "res://assets/environments/%s.jpg" % str(_cfg.get("window", "window_a")), float(_cfg.get("window_light", 0.8)))
	for i: int in 9:
		_box(Vector3(2.94, 0.95 + float(i) * 0.14, -0.4), Vector3(0.02, 0.025, 1.9), _mat(Color("9a9684")))
	_hotspot("window", Vector3(2.9, 1.5, -0.4), Vector3(0.2, 1.3, 2.0))
	_refl_delay = float(_cfg.get("reflection_delay", 0.0))
	if bool(_cfg.get("reflection", true)):
		_reflection = MeshInstance3D.new()
		var rq := QuadMesh.new()
		rq.size = Vector2(0.5, 0.75)
		_reflection.mesh = rq
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_texture = _silhouette_texture()
		rm.albedo_color = Color(0.02, 0.04, 0.03, float(_cfg.get("reflection_alpha", 0.35)))
		_reflection.material_override = rm
		_reflection.rotation_degrees.y = -90.0
		_reflection.position = Vector3(2.93, 1.4, -0.4)
		add_child(_reflection)

	# Door + notice board (south)
	_box(Vector3(-1.1, 1.05, 2.97), Vector3(1.0, 2.1, 0.07), _mat(Color("3d3a2c"), 0.0, 0.6))
	_box(Vector3(-1.1, 1.55, 2.925), Vector3(0.6, 0.7, 0.02), _mat(Color("7f9a86"), 0.5 * float(_cfg.get("corridor_light", 1.0))))
	if bool(_cfg.get("door_shadow", false)):
		_box(Vector3(-1.02, 1.5, 2.91), Vector3(0.22, 0.6, 0.01), _mat(Color(0.02, 0.03, 0.02)))
	_box(Vector3(-0.72, 1.05, 2.91), Vector3(0.05, 0.05, 0.06), metal)
	_text3d("0417", Vector3(-1.1, 2.02, 2.92), 180.0, Color("c6bfa8"), 0.0016)
	_hotspot("door", Vector3(-1.1, 1.05, 2.9), Vector3(1.0, 2.1, 0.25))
	_box(Vector3(1.3, 1.5, 2.98), Vector3(1.3, 0.9, 0.04), _mat(Color("7a6a4a")))
	var papers: Array = _cfg.get("board_papers", [[-0.35, 0.2, 0], [0.2, 0.15, 0], [-0.1, -0.2, 0], [0.4, -0.2, 0]])
	for p: Variant in papers:
		var red: bool = int(p[2]) == 1
		_box(Vector3(1.3 - float(p[0]), 1.5 + float(p[1]), 2.955), Vector3(0.26, 0.32, 0.01), _mat(Color("9e2929")) if red else paper)
	_hotspot("board", Vector3(1.3, 1.5, 2.93), Vector3(1.3, 0.9, 0.2))

	# Filing cabinet, coffee machine, corridor photograph (west)
	_box(Vector3(-2.68, 0.66, -1.7), Vector3(0.55, 1.32, 0.65), metal)
	for i: int in 4:
		_box(Vector3(-2.4, 0.2 + float(i) * 0.32, -1.7), Vector3(0.012, 0.012, 0.56), dark)
		_box(Vector3(-2.395, 0.32 + float(i) * 0.32, -1.7), Vector3(0.02, 0.03, 0.14), beige)
	if bool(_cfg.get("cabinet_open", false)):
		_box(Vector3(-2.25, 0.22, -1.7), Vector3(0.3, 0.26, 0.58), metal)
		_box(Vector3(-2.22, 0.3, -1.7), Vector3(0.2, 0.2, 0.02), paper)
	_hotspot("cabinet", Vector3(-2.6, 0.66, -1.7), Vector3(0.75, 1.32, 0.7))
	_box(Vector3(-2.65, 0.4, 1.0), Vector3(0.6, 0.8, 0.7), _mat(Color("4a4536")))
	_box(Vector3(-2.65, 1.0, 1.0), Vector3(0.32, 0.42, 0.3), dark)
	_box(Vector3(-2.48, 1.08, 1.0), Vector3(0.01, 0.03, 0.03), _mat(Color("9e2929") if bool(_cfg.get("coffee_red", false)) else Color("9abf9a"), 2.0))
	_box(Vector3(-2.5, 0.85, 1.0), Vector3(0.1, 0.1, 0.1), paper)
	_hotspot("coffee", Vector3(-2.6, 1.0, 1.0), Vector3(0.5, 0.5, 0.5))
	_box(Vector3(-2.985, 1.6, -0.3), Vector3(0.03, 0.78, 1.04), dark)
	_photo_quad(Vector3(-2.965, 1.6, -0.3), Vector2(0.94, 0.68), 90.0, "res://assets/environments/%s.jpg" % str(_cfg.get("corridor", "corridor_a")), 0.75 * light)

	# Spare chair: it is never quite where you left it.
	var ch: Array = _cfg.get("chair", [1.7, 1.3, 30])
	var chair := Node3D.new()
	chair.position = Vector3(float(ch[0]), 0, float(ch[1]))
	chair.rotation_degrees.y = float(ch[2])
	add_child(chair)
	var cm := _mat(Color("26332b"))
	_box(Vector3(0, 0.45, 0), Vector3(0.46, 0.07, 0.46), cm, chair)
	_box(Vector3(0, 0.82, 0.21), Vector3(0.46, 0.6, 0.06), cm, chair)
	_box(Vector3(0, 0.22, 0), Vector3(0.06, 0.44, 0.06), _mat(Color("151a17")), chair)
	_box(Vector3(0, 0.03, 0), Vector3(0.5, 0.04, 0.5), _mat(Color("151a17")), chair)


func _silhouette_texture() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y: int in 96:
		for x: int in 64:
			var dx: float = (float(x) - 32.0) / 13.0
			var dy: float = (float(y) - 24.0) / 17.0
			var head: bool = dx * dx + dy * dy <= 1.0
			var sx: float = (float(x) - 32.0) / 30.0
			var sy: float = (float(y) - 96.0) / 52.0
			var body: bool = y > 44 and sx * sx + sy * sy <= 1.0
			if head or body:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- hud

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var info: Dictionary = GameManager.get_day_info()
	var top := UI.label("DAY %d  -  %s  -  %s" % [GameManager.day, str(info.get("date", "")), "END OF SHIFT" if GameManager.phase == "evening" else "MORNING"], "TermLabel")
	top.position = Vector2(20, 14)
	_hud.add_child(top)
	_hover_label = UI.label("", "TermBig")
	_hover_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hover_label.offset_top = -120
	_hover_label.offset_bottom = -80
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hover_label)
	var hint := UI.label("A / D or arrow keys: look around     Click or E: use     Esc: menu", "TermSmall")
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -36
	hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(hint)
	for side: int in 2:
		var b := Button.new()
		b.theme_type_variation = "TermButton"
		b.text = "<" if side == 0 else ">"
		b.tooltip_text = "Hold to look " + ("left" if side == 0 else "right")
		b.focus_mode = Control.FOCUS_NONE
		b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if side == 0 else Control.PRESET_CENTER_RIGHT)
		b.offset_left = 10.0 if side == 0 else -54.0
		b.offset_right = 54.0 if side == 0 else -10.0
		b.offset_top = -40
		b.offset_bottom = 40
		b.button_down.connect(func() -> void:
			if side == 0:
				_turn_left = true
			else:
				_turn_right = true)
		b.button_up.connect(func() -> void:
			_turn_left = false
			_turn_right = false)
		_hud.add_child(b)


func _toggle_pause() -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
		return
	_pause = UI.panel("Dim")
	UI.full_rect(_pause)
	_hud.add_child(_pause)
	var center := CenterContainer.new()
	_pause.add_child(center)
	var frame := UI.panel("WindowFrame")
	center.add_child(frame)
	var v := UI.vbox(8)
	v.custom_minimum_size.x = 520
	frame.add_child(UI.margin(v, 12))
	v.add_child(UI.label("PAUSED", "HeaderLabel"))
	var resume := UI.button("RESUME", _toggle_pause)
	v.add_child(resume)
	var s: VBoxContainer = SettingsPanel.new()
	s.set("show_back", false)
	v.add_child(s)
	v.add_child(UI.button("SAVE AND QUIT TO MAIN MENU", func() -> void: GameManager.quit_to_menu()))
	resume.grab_focus.call_deferred()


func _busy() -> bool:
	return _leaving or DialogueManager.is_active() or (_pause != null and is_instance_valid(_pause))


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_time += delta
	if not _busy():
		var turn: float = 0.0
		if _turn_left or Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
			turn += 1.0
		if _turn_right or Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
			turn -= 1.0
		_yaw += turn * TURN_SPEED * delta
	_cam.rotation = Vector3(_pitch, _yaw, 0)
	# Fluorescent flicker: slow dips only, and off entirely if the player disabled it.
	var energy: float = _base_energy
	if _flicker > 0.0 and bool(SaveManager.settings.get("flicker", true)):
		var n: float = sin(_time * 1.3) * sin(_time * 0.7 + 1.3)
		if n > 0.55:
			energy *= 1.0 - _flicker * 0.45 * smoothstep(0.55, 0.8, n)
	for l: OmniLight3D in _lights:
		l.light_energy = 1.25 * energy
	for m: StandardMaterial3D in _tube_mats:
		m.emission_energy_multiplier = 2.2 * energy
	# The reflection in the window follows you. Later, it follows late.
	if _reflection != null:
		var k: float = 1.0 if _refl_delay <= 0.0 else clampf(delta / _refl_delay, 0.0, 1.0)
		_refl_yaw = lerpf(_refl_yaw, _yaw, k)
		_reflection.position.z = -0.4 + clampf(sin(_refl_yaw + PI * 0.5), -1.0, 1.0) * 0.35
	# Phone
	if _ring_dialogue != "" and not _busy():
		_ring_timer -= delta
		_phone_led.emission_energy_multiplier = 3.0 if fmod(_time, 1.0) < 0.5 else 0.2
		if _ring_timer <= 0.0:
			_ring_timer = 3.2
			AudioManager.play_sfx("phone_ring", -6.0)
	_update_hover()


func _raycast(screen_pos: Vector2) -> String:
	var from: Vector3 = _cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + _cam.project_ray_normal(screen_pos) * 12.0
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return ""
	var col: Object = hit.get("collider")
	return str(col.get_meta("hotspot", "")) if col != null else ""


func _update_hover() -> void:
	if _busy():
		_hover_id = ""
		_hover_label.text = ""
		return
	var vp: Viewport = get_viewport()
	var id: String = _raycast(vp.get_mouse_position())
	if id == "":
		id = _raycast(vp.get_visible_rect().size * 0.5)
	_hover_id = id
	var text: String = str(HOTSPOT_LABELS.get(id, ""))
	if id == "phone" and _ring_dialogue != "":
		text += "  (ringing)"
	_hover_label.text = "[ %s ]" % text if text != "" else ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not DialogueManager.is_active() and not _leaving:
			_toggle_pause()
		return
	if _busy():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var id: String = _raycast(mb.position)
			if id != "":
				_interact(id)
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.003, -0.45, 0.35)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key: int = (event as InputEventKey).keycode
		if (key == KEY_E or key == KEY_ENTER or key == KEY_SPACE) and _hover_id != "":
			_interact(_hover_id)


# ---------------------------------------------------------------- interaction

## Picks the most specific dialogue available for an object:
## office_<obj>_d<day>_<phase>, office_<obj>_d<day>, office_<obj>_<phase>, office_<obj>.
func dialogue_for(obj: String) -> String:
	if obj == "phone" and _ring_dialogue != "":
		return _ring_dialogue
	var d: int = GameManager.day
	for id: String in ["office_%s_d%d_%s" % [obj, d, GameManager.phase], "office_%s_d%d" % [obj, d],
			"office_%s_%s" % [obj, GameManager.phase], "office_%s" % obj]:
		if not DialogueManager.has_dialogue(id):
			continue
		# A call that has already been answered does not play again.
		if id == _ring_config and DialogueManager.is_completed(id):
			continue
		return id
	return ""


func _interact(obj: String) -> void:
	var id: String = dialogue_for(obj)
	if id == "":
		return
	AudioManager.play_sfx("click", -8.0)
	if obj == "phone" and _ring_dialogue != "":
		_ring_dialogue = ""
		_phone_led.emission_energy_multiplier = 0.2
		AudioManager.play_sfx("pickup", -6.0)
	GameManager.set_flag("used:%s:d%d" % [obj, GameManager.day])
	DialogueManager.start(id)
	StoryDirector.trigger("office_used:" + obj)


func _on_action(action: String) -> void:
	match action:
		"use_computer":
			_leaving = true
			AudioManager.play_sfx("boot", -10.0)
			GameManager.goto_scene("desktop")
		"next_day":
			_leaving = true
			AudioManager.play_sfx("door", -4.0)
			GameManager.advance_day()
		"coffee":
			AudioManager.play_sfx("coffee", -6.0)
		"door_rattle":
			AudioManager.play_sfx("door", -8.0)
