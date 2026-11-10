extends VBoxContainer
## SYSTEM MONITOR: server status, processes, network activity, warnings.
## It becomes less reliable as the days pass (glitch_level in the data).

var desktop: Node
var _data: Dictionary = {}
var _proc_labels: Array = []
var _graph: Control
var _samples: Array[float] = []
var _tick: float = 0.0
var _ticks: int = 0
var _log_box: VBoxContainer
var _log_shown: int = 0
var _trust: ProgressBar
var _trust_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	for i: int in 48:
		_samples.append(randf_range(0.1, 0.4))
	StoryDirector.monitor_changed.connect(_rebuild)
	GameManager.trust_changed.connect(func(_v: int) -> void: _update_trust())
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	UI.clear(self)
	_proc_labels.clear()
	_data = StoryDirector.get_monitor()
	add_child(UI.label(str(_data.get("header", "SYSTEM STATUS")), "HeaderLabel", true))
	var trow := UI.hbox(8)
	add_child(trow)
	_trust_label = UI.label("", "SmallLabel")
	trow.add_child(_trust_label)
	_trust = ProgressBar.new()
	_trust.custom_minimum_size = Vector2(200, 18)
	_trust.show_percentage = false
	_trust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_trust)
	_update_trust()
	var cols := UI.hbox(8)
	UI.expand(cols)
	add_child(cols)
	var left := UI.panel("Term")
	UI.expand(left)
	cols.add_child(left)
	var ls := UI.scroll()
	left.add_child(ls)
	var lv := UI.vbox(3)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(lv)
	lv.add_child(UI.label("SERVER STATUS", "TermHeader"))
	for s: Variant in _data.get("servers", []):
		var bad: bool = str(s.get("status", "OK")) != "OK"
		var l := UI.label("%-14s %s" % [str(s.get("name", "?")), str(s.get("status", "OK"))], "TermLabel", true)
		if bad:
			l.add_theme_color_override("font_color", UI.C_RED.lightened(0.25))
		lv.add_child(l)
	lv.add_child(UI.label(" ", "TermSmall"))
	lv.add_child(UI.label("ACTIVE PROCESSES", "TermHeader"))
	for p: Variant in _data.get("processes", []):
		var l := UI.label("", "TermLabel", true)
		l.set_meta("proc", p)
		lv.add_child(l)
		_proc_labels.append(l)
	var right := UI.vbox(6)
	UI.expand(right)
	cols.add_child(right)
	var gp := UI.panel("Term")
	gp.custom_minimum_size.y = 120
	right.add_child(gp)
	var gv := UI.vbox(2)
	gp.add_child(gv)
	gv.add_child(UI.label("NETWORK ACTIVITY", "TermHeader"))
	_graph = Control.new()
	UI.expand(_graph)
	_graph.draw.connect(_draw_graph)
	gv.add_child(_graph)
	var wp := UI.panel("Term")
	UI.expand(wp)
	right.add_child(wp)
	var ws := UI.scroll()
	wp.add_child(ws)
	_log_box = UI.vbox(3)
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ws.add_child(_log_box)
	_log_box.add_child(UI.label("CORRUPTION WARNINGS", "TermHeader"))
	var warnings: Array = _data.get("warnings", [])
	if warnings.is_empty():
		_log_box.add_child(UI.label("none", "TermSmall"))
	for w: Variant in warnings:
		var wl := UI.label("! " + str(w), "TermLabel", true)
		wl.add_theme_color_override("font_color", UI.C_RED.lightened(0.25))
		_log_box.add_child(wl)
	_log_box.add_child(UI.label(" ", "TermSmall"))
	_log_box.add_child(UI.label("SYSTEM MESSAGES", "TermHeader"))
	_log_shown = 0
	_update_processes()
	_reveal_log()


func _update_trust() -> void:
	if _trust == null or not is_instance_valid(_trust):
		return
	_trust.value = GameManager.trust
	_trust_label.text = "ANALYST CLEARANCE INDEX: %d / 100" % GameManager.trust


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	_ticks += 1
	var level: int = int(_data.get("glitch_level", 0))
	var v: float = clampf(_samples[_samples.size() - 1] + randf_range(-0.15, 0.15), 0.05, 0.95)
	if level >= 2 and _ticks % 9 == 0:
		v = 1.0
	_samples.append(v)
	_samples.pop_front()
	if _graph != null and is_instance_valid(_graph):
		_graph.queue_redraw()
	_update_processes()
	if _ticks % 2 == 0:
		_reveal_log()


func _update_processes() -> void:
	var level: int = int(_data.get("glitch_level", 0))
	for i: int in _proc_labels.size():
		var l: Label = _proc_labels[i]
		if not is_instance_valid(l):
			continue
		var p: Dictionary = l.get_meta("proc")
		var cpu: String = "%2d%%" % clampi(int(p.get("cpu", 1)) + randi_range(-1, 2), 0, 99)
		# An unreliable monitor reports numbers that cannot be true.
		if level >= 2 and (_ticks + i * 3) % 7 == 0:
			cpu = ["-4%", "103%", "NaN", "??%", "03:14"][(_ticks + i) % 5]
		var pname: String = str(p.get("name", "?"))
		if level >= 3 and (_ticks + i) % 11 == 0 and p.has("alias"):
			pname = str(p["alias"])
		l.text = "%-22s %-8s %s" % [pname, str(p.get("user", "sys")), cpu]


func _reveal_log() -> void:
	var lines: Array = _data.get("log", [])
	if _log_shown < lines.size() and _log_box != null and is_instance_valid(_log_box):
		_log_box.add_child(UI.label("> " + str(lines[_log_shown]), "TermLabel", true))
		_log_shown += 1


func _draw_graph() -> void:
	var sz: Vector2 = _graph.size
	var w: float = sz.x / float(_samples.size())
	for i: int in _samples.size():
		var h: float = _samples[i] * sz.y
		var col: Color = UI.C_GREEN if _samples[i] < 0.99 else UI.C_RED.lightened(0.2)
		_graph.draw_rect(Rect2(float(i) * w, sz.y - h, maxf(w - 2.0, 1.0), h), col)
