extends Node
## StoryDirector (autoload): the controlled story-trigger system.
## Every email delivery and scripted horror event is declared in
## data/story_events/*.json and fired by a named trigger, never at random.
##
## Triggers used by the game:
##   day_start, shift_end, desktop_ready, app_opened:<app>, case_opened:<case>,
##   case_submitted:<case>, result_closed:<case>, evidence_collected:<case>:<clue>,
##   email_read:<id>, dialogue_finished:<id>, line_mutated

signal email_delivered(id: String)
signal emails_changed
signal desktop_action_queued
signal monitor_changed

const EMAILS_FILE := "res://data/story_events/emails.json"
const EVENTS_FILE := "res://data/story_events/events.json"
const MONITOR_FILE := "res://data/story_events/system_monitor.json"
## Actions that need the desktop on screen; they wait in a saved queue until it is.
const DESKTOP_ACTIONS := ["toast", "error_dialog", "open_app", "terminal_dialogue"]

var emails: Array = []
var events: Array = []
var monitor_data: Dictionary = {}
var load_errors: Array[String] = []

var delivered: Array = []           # email ids in delivery order
var delivered_day: Dictionary = {}  # email id -> day delivered
var read: Dictionary = {}           # email id -> true
var fired: Dictionary = {}          # event id -> true
var monitor_log: Array = []         # extra log lines appended by events
var terminal_log: Array = []        # persistent terminal transcript (bbcode)
var desktop_queue: Array = []       # pending desktop actions


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_errors.clear()
	var e: Variant = SaveManager.read_data_file(EMAILS_FILE)
	emails = e["emails"] if e is Dictionary and (e as Dictionary).get("emails") is Array else []
	if emails.is_empty():
		load_errors.append("emails.json: no emails loaded")
	var ev: Variant = SaveManager.read_data_file(EVENTS_FILE)
	events = ev["events"] if ev is Dictionary and (ev as Dictionary).get("events") is Array else []
	if events.is_empty():
		load_errors.append("events.json: no events loaded")
	var m: Variant = SaveManager.read_data_file(MONITOR_FILE)
	monitor_data = m if m is Dictionary else {}
	var seen: Dictionary = {}
	for mail: Variant in emails:
		if not (mail is Dictionary) or not mail.has("id") or not mail.has("trigger") or not mail.has("body"):
			load_errors.append("emails.json: entry without id/trigger/body")
		elif seen.has(mail["id"]):
			load_errors.append("emails.json: duplicate id '%s'" % str(mail["id"]))
		else:
			seen[mail["id"]] = true
	for event: Variant in events:
		if not (event is Dictionary) or not event.has("id") or not event.has("trigger") or not (event.get("actions") is Array):
			load_errors.append("events.json: entry without id/trigger/actions")
	for err: String in load_errors:
		push_error("StoryDirector: " + err)


# ---------------------------------------------------------------- triggers

func trigger(trigger_name: String) -> void:
	if not GameManager.game_active:
		return
	for mail: Variant in emails:
		if not (mail is Dictionary) or str(mail.get("trigger", "")) != trigger_name:
			continue
		if delivered.has(str(mail["id"])):
			continue
		if int(mail.get("day", 0)) != 0 and int(mail["day"]) != GameManager.day:
			continue
		if not GameManager.check_requires(mail.get("requires", {})):
			continue
		deliver_email(str(mail["id"]))
	for event: Variant in events:
		if not (event is Dictionary) or str(event.get("trigger", "")) != trigger_name:
			continue
		var id: String = str(event["id"])
		if bool(event.get("once", true)) and fired.has(id):
			continue
		if int(event.get("day", 0)) != 0 and int(event["day"]) != GameManager.day:
			continue
		if not GameManager.check_requires(event.get("requires", {})):
			continue
		fired[id] = true
		for action: Variant in event["actions"]:
			if action is Dictionary:
				_run_action(action)


func _run_action(action: Dictionary) -> void:
	var type: String = str(action.get("type", ""))
	if DESKTOP_ACTIONS.has(type):
		desktop_queue.append(action.duplicate(true))
		desktop_action_queued.emit()
		return
	match type:
		"flag":
			GameManager.set_flag(str(action.get("name", "")), action.get("value", true))
		"trust":
			GameManager.adjust_trust(int(action.get("delta", 0)))
		"rapport":
			GameManager.adjust_rapport(int(action.get("delta", 0)))
		"email":
			deliver_email(str(action.get("id", "")))
		"glitch":
			ScreenFX.pulse(float(action.get("strength", 0.6)), float(action.get("duration", 0.5)))
		"sfx":
			AudioManager.play_sfx(str(action.get("name", "")), float(action.get("db", -4.0)))
		"ambience":
			AudioManager.apply_preset(str(action.get("preset", "")), float(action.get("fade", 2.0)))
		"silence":
			AudioManager.silence(float(action.get("fade", 0.3)))
		"music":
			AudioManager.play_music(str(action.get("name", "drone")), float(action.get("db", -16.0)))
		"monitor_log":
			monitor_log.append(str(action.get("text", "")))
			monitor_changed.emit()
		"terminal_log":
			terminal_log.append(str(action.get("text", "")))
		"trigger":
			trigger.call_deferred(str(action.get("name", "")))
		_:
			push_warning("StoryDirector: unknown action type '%s'" % type)


func pop_desktop_action() -> Dictionary:
	if desktop_queue.is_empty():
		return {}
	var a: Variant = desktop_queue.pop_front()
	return a if a is Dictionary else {}


## Called when the desktop appears. Re-queues anything that must not be skipped:
## unacknowledged case results and interrupted terminal conversations.
func on_desktop_ready() -> void:
	for cid: String in CaseManager.results:
		if not GameManager.has_flag("result_ack:" + cid) and not _queued("open_app", "case_id", cid):
			desktop_queue.push_front({"type": "open_app", "app": "result", "args": {"case_id": cid}})
	for event: Variant in events:
		if not (event is Dictionary) or not fired.has(str(event["id"])):
			continue
		for action: Variant in event["actions"]:
			if action is Dictionary and str(action.get("type", "")) == "terminal_dialogue":
				var did: String = str(action.get("id", ""))
				if not DialogueManager.is_completed(did) and not _queued("terminal_dialogue", "id", did):
					desktop_queue.append(action.duplicate(true))


func _queued(type: String, key: String, value: String) -> bool:
	for a: Variant in desktop_queue:
		if a is Dictionary and str(a.get("type", "")) == type:
			if str(a.get(key, "")) == value:
				return true
			var args: Variant = a.get("args", {})
			if args is Dictionary and str((args as Dictionary).get(key, "")) == value:
				return true
	return false


# ---------------------------------------------------------------- email

func get_email(id: String) -> Dictionary:
	for mail: Variant in emails:
		if mail is Dictionary and str(mail.get("id", "")) == id:
			return mail
	return {}


func deliver_email(id: String) -> void:
	var mail: Dictionary = get_email(id)
	if mail.is_empty() or delivered.has(id):
		return
	delivered.append(id)
	delivered_day[id] = GameManager.day
	email_delivered.emit(id)
	emails_changed.emit()
	if not bool(mail.get("silent", false)):
		desktop_queue.append({"type": "toast", "text": "NEW MAIL: %s" % str(mail.get("from", "unknown")), "style": "mail", "sfx": "notify"})
		desktop_action_queued.emit()


func is_read(id: String) -> bool:
	return read.has(id)


func unread_count() -> int:
	var n: int = 0
	for id: Variant in delivered:
		if not read.has(str(id)):
			n += 1
	return n


func mark_email_read(id: String) -> void:
	if read.has(id) or not delivered.has(id):
		return
	read[id] = true
	var mail: Dictionary = get_email(id)
	var on_read: Variant = mail.get("on_read", {})
	if on_read is Dictionary:
		var fl: Variant = (on_read as Dictionary).get("flags", {})
		if fl is Dictionary:
			for f: String in (fl as Dictionary):
				GameManager.set_flag(f, fl[f])
		if (on_read as Dictionary).has("glitch"):
			ScreenFX.pulse(float(on_read["glitch"]), 0.5)
	emails_changed.emit()
	trigger("email_read:" + id)
	SaveManager.save_game()


func email_date(id: String) -> String:
	var d: int = int(delivered_day.get(id, GameManager.day))
	return str(GameManager.get_day_info(d).get("date", "DAY %d" % d))


# ---------------------------------------------------------------- system monitor

## Monitor content for the current day, with flag-dependent rows filtered.
func get_monitor() -> Dictionary:
	var days: Variant = monitor_data.get("days", {})
	var d: Variant = (days as Dictionary).get(str(GameManager.day), {}) if days is Dictionary else {}
	var src: Dictionary = d if d is Dictionary else {}
	var out := {"glitch_level": int(src.get("glitch_level", 0)), "header": GameManager.format_text(str(src.get("header", "")))}
	for section: String in ["servers", "processes", "warnings", "log"]:
		var rows: Array = []
		for row: Variant in src.get(section, []):
			if row is Dictionary:
				if GameManager.check_requires(row.get("requires", {})):
					var copy: Dictionary = (row as Dictionary).duplicate()
					for k: String in copy:
						if copy[k] is String:
							copy[k] = GameManager.format_text(copy[k])
					rows.append(copy)
			else:
				rows.append(GameManager.format_text(str(row)))
		out[section] = rows
	for line: Variant in monitor_log:
		(out["log"] as Array).append(GameManager.format_text(str(line)))
	return out


# ---------------------------------------------------------------- save

func reset_state() -> void:
	delivered = []
	delivered_day = {}
	read = {}
	fired = {}
	monitor_log = []
	terminal_log = []
	desktop_queue = []


func get_save_data() -> Dictionary:
	return {
		"delivered": delivered.duplicate(), "delivered_day": delivered_day.duplicate(),
		"read": read.duplicate(), "fired": fired.duplicate(),
		"monitor_log": monitor_log.duplicate(), "terminal_log": terminal_log.duplicate(),
		"desktop_queue": desktop_queue.duplicate(true),
	}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	for id: Variant in d.get("delivered", []):
		if not get_email(str(id)).is_empty():
			delivered.append(str(id))
	var dd: Variant = d.get("delivered_day", {})
	if dd is Dictionary:
		for k: String in (dd as Dictionary):
			delivered_day[k] = int(dd[k])
	for key: String in ["read", "fired"]:
		var v: Variant = d.get(key, {})
		if v is Dictionary:
			set(key, (v as Dictionary).duplicate())
	for key: String in ["monitor_log", "terminal_log"]:
		var v: Variant = d.get(key, [])
		if v is Array:
			set(key, (v as Array).duplicate())
	var q: Variant = d.get("desktop_queue", [])
	if q is Array:
		for a: Variant in q:
			if a is Dictionary:
				desktop_queue.append((a as Dictionary).duplicate(true))
