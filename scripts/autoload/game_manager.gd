extends Node
## GameManager (autoload): global game state, day progression, story flags,
## company trust, scene transitions and ending resolution.

signal day_changed(day: int)
signal flag_changed(flag: String, value: Variant)
signal trust_changed(value: int)

const SCENES := {
	"menu": "res://scenes/main_menu/main_menu.tscn",
	"transition": "res://scenes/transitions/day_transition.tscn",
	"office": "res://scenes/office/office.tscn",
	"desktop": "res://scenes/desktop/desktop.tscn",
	"ending": "res://scenes/endings/ending.tscn",
}
const LAST_DAY := 5
const EMPLOYEE_ID := "0417"
const DAYS_FILE := "res://data/story_events/days.json"

var game_active: bool = false
var player_name: String = "Analyst"
var day: int = 1
var phase: String = "morning"      # "morning" (shift running) or "evening" (shift ended)
var location: String = "transition" # where Continue should resume
var flags: Dictionary = {}
var trust: int = 50                 # company trust, shown as ANALYST CLEARANCE INDEX
var rapport: int = 0                # relationship with UNKNOWN INSTANCE 07
var notes: String = ""
var current_case: String = ""
var final_classification: String = ""
var ending: String = ""
var days: Dictionary = {}           # day number -> definition
var _changing_scene: bool = false
## Automated tests switch this off so managers can be exercised without leaving the test scene.
var scene_changes_enabled: bool = true


func _ready() -> void:
	_load_days()


func _load_days() -> void:
	var data: Variant = SaveManager.read_data_file(DAYS_FILE)
	if data is Dictionary and (data as Dictionary).get("days") is Array:
		for d: Variant in data["days"]:
			if d is Dictionary and (d as Dictionary).has("day"):
				days[int(d["day"])] = d
	for n: int in range(1, LAST_DAY + 1):
		if not days.has(n):
			push_error("GameManager: days.json has no entry for day %d" % n)


func get_day_info(n: int = -1) -> Dictionary:
	var d: Variant = days.get(day if n < 0 else n, {})
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- lifecycle

func reset_state() -> void:
	day = 1
	phase = "morning"
	location = "transition"
	flags = {}
	trust = 50
	rapport = 0
	notes = ""
	current_case = ""
	final_classification = ""
	ending = ""


func new_game(analyst_name: String) -> void:
	reset_state()
	var clean: String = analyst_name.strip_edges()
	player_name = clean if clean != "" else "Analyst"
	CaseManager.reset_state()
	EvidenceManager.reset_state()
	DialogueManager.reset_state()
	StoryDirector.reset_state()
	game_active = true
	StoryDirector.trigger("day_start")
	SaveManager.save_game()
	goto_scene("transition")


func continue_game() -> bool:
	if not SaveManager.load_game():
		return false
	game_active = true
	var target: String = location if SCENES.has(location) and location != "menu" and location != "ending" else "office"
	goto_scene(target)
	return true


func quit_to_menu() -> void:
	SaveManager.save_game()
	game_active = false
	goto_scene("menu")


# ---------------------------------------------------------------- flags / trust

func set_flag(flag: String, value: Variant = true) -> void:
	if flags.get(flag) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func has_flag(flag: String) -> bool:
	var v: Variant = flags.get(flag, false)
	return v is bool and v == true or (not (v is bool) and v != null)


func adjust_trust(delta: int) -> void:
	trust = clampi(trust + delta, 0, 100)
	trust_changed.emit(trust)


func adjust_rapport(delta: int) -> void:
	rapport += delta


## Central condition evaluator used by every data file.
## Supported keys: flag, not_flag (String or Array), flags {name: value}, day, min_day,
## max_day, phase, case_done, case_not_done, results {case: [classifications]},
## min_trust, max_trust, min_rapport, max_rapport.
func check_requires(req: Variant) -> bool:
	if not (req is Dictionary):
		return true
	var r: Dictionary = req
	for key: String in r:
		var v: Variant = r[key]
		match key:
			"flag":
				for f: Variant in (v if v is Array else [v]):
					if not has_flag(str(f)):
						return false
			"not_flag":
				for f: Variant in (v if v is Array else [v]):
					if has_flag(str(f)):
						return false
			"flags":
				for f: String in (v as Dictionary):
					if flags.get(f, false) != v[f]:
						return false
			"day":
				if day != int(v): return false
			"min_day":
				if day < int(v): return false
			"max_day":
				if day > int(v): return false
			"phase":
				if phase != str(v): return false
			"case_done":
				if not CaseManager.is_done(str(v)): return false
			"case_not_done":
				if CaseManager.is_done(str(v)): return false
			"results":
				for cid: String in (v as Dictionary):
					var got: String = CaseManager.get_classification(cid)
					if not (v[cid] as Array).has(got):
						return false
			"min_trust":
				if trust < int(v): return false
			"max_trust":
				if trust > int(v): return false
			"min_rapport":
				if rapport < int(v): return false
			"max_rapport":
				if rapport > int(v): return false
			_:
				push_warning("GameManager.check_requires: unknown key '%s'" % key)
	return true


# ---------------------------------------------------------------- text variables

## A sentence the player wrote in PERSONAL NOTES, so the unknown instance can quote it.
func note_quote() -> String:
	var cleaned: String = notes.replace("\r", "\n")
	for chunk: String in cleaned.split("\n", false):
		for sentence: String in chunk.split(".", false):
			var s: String = sentence.strip_edges()
			if s.length() >= 12:
				return s.substr(0, 90)
	return "I'm not sure what I'm looking for"


func format_text(text: String) -> String:
	if not text.contains("{"):
		return text
	var out: String = text
	out = out.replace("{player}", player_name)
	out = out.replace("{PLAYER}", player_name.to_upper())
	out = out.replace("{employee_id}", EMPLOYEE_ID)
	out = out.replace("{note_quote}", note_quote())
	out = out.replace("{day}", str(day))
	out = out.replace("{trust}", str(trust))
	out = out.replace("{case_count}", str(CaseManager.results.size()))
	var guard: int = 0
	while out.contains("{decision:") and guard < 20:
		guard += 1
		var a: int = out.find("{decision:")
		var b: int = out.find("}", a)
		if b == -1:
			break
		var cid: String = out.substr(a + 10, b - a - 10)
		var cls: String = CaseManager.get_classification(cid)
		var word: String = str(CaseManager.CLASS_LABELS.get(cls, "nothing yet")).to_lower()
		out = out.substr(0, a) + word + out.substr(b + 1)
	return out


# ---------------------------------------------------------------- scenes / days

func goto_scene(key: String) -> void:
	if not SCENES.has(key) or _changing_scene:
		return
	if not scene_changes_enabled:
		if key != "menu" and key != "ending":
			location = key
		return
	_changing_scene = true
	if key != "menu" and key != "ending":
		location = key
	await ScreenFX.fade_out(0.35)
	DialogueManager.cancel()
	get_tree().change_scene_to_file(SCENES[key])
	await get_tree().process_frame
	await ScreenFX.fade_in(0.5)
	_changing_scene = false


func day_case_id() -> String:
	return str(get_day_info().get("case_id", ""))


func is_day_case_done() -> bool:
	var cid: String = day_case_id()
	return cid == "" or CaseManager.is_done(cid)


func can_end_shift() -> bool:
	return day < LAST_DAY and phase == "morning" and is_day_case_done()


func end_shift() -> void:
	if not can_end_shift():
		return
	phase = "evening"
	StoryDirector.trigger("shift_end")
	SaveManager.save_game()
	goto_scene("office")


func advance_day() -> void:
	if day >= LAST_DAY:
		return
	day += 1
	phase = "morning"
	location = "transition"
	day_changed.emit(day)
	StoryDirector.trigger("day_start")
	SaveManager.save_game()
	goto_scene("transition")


# ---------------------------------------------------------------- endings

## Called when the final case (UNKNOWN INSTANCE 07) is classified.
func finish_game(classification: String) -> void:
	final_classification = classification
	ending = determine_ending(classification)
	SaveManager.record_ending(ending)
	goto_scene("ending")


## How much of the truth about employee 0417 the player uncovered.
func truth_score() -> int:
	var score: int = 0
	for f: String in ["viewed_own_record", "has_manifest", "read_own_file", "asked_who_am_i", "found_0314"]:
		if has_flag(f):
			score += 1
	if EvidenceManager.count_confirmed() >= 14:
		score += 1
	return score


## Ending A: COMPLIANCE, B: CONTAMINATION, C: HUMAN ERROR.
func determine_ending(classification: String) -> String:
	if classification == "CORRUPTED_AI":
		return "A"
	if has_flag("granted_access"):
		return "B"
	var truth: int = truth_score()
	if classification == "VERIFIED_HUMAN" and rapport >= 2 and truth < 3:
		return "B"
	if truth >= 2:
		return "C"
	return "A" if trust >= 55 else "B"


# ---------------------------------------------------------------- save

func get_save_data() -> Dictionary:
	return {
		"player_name": player_name, "day": day, "phase": phase, "location": location,
		"flags": flags.duplicate(true), "trust": trust, "rapport": rapport,
		"notes": notes, "current_case": current_case,
	}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	player_name = str(d.get("player_name", "Analyst"))
	day = clampi(int(d.get("day", 1)), 1, LAST_DAY)
	phase = str(d.get("phase", "morning"))
	location = str(d.get("location", "office"))
	var f: Variant = d.get("flags", {})
	flags = (f as Dictionary).duplicate(true) if f is Dictionary else {}
	trust = clampi(int(d.get("trust", 50)), 0, 100)
	rapport = int(d.get("rapport", 0))
	notes = str(d.get("notes", ""))
	current_case = str(d.get("current_case", ""))
