extends Node
## SaveManager (autoload): settings + game progress persistence (JSON in user://).

signal settings_changed
signal game_saved

const SAVE_VERSION := 1
const DEFAULT_SETTINGS := {
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"fullscreen": false,
	"text_scale": 1.0,
	"screen_distortion": true,
	"flicker": true,
	"visual_noise": true,
	"endings_seen": [],
}

var save_path: String = "user://human_error_save.json"
var settings_path: String = "user://human_error_settings.json"
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var last_error: String = ""


func _ready() -> void:
	load_settings()
	apply_settings.call_deferred()


# ---------------------------------------------------------------- settings

func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	var data: Variant = _read_json(settings_path)
	if data is Dictionary:
		for k: String in DEFAULT_SETTINGS:
			if (data as Dictionary).has(k) and typeof(data[k]) == typeof(DEFAULT_SETTINGS[k]):
				settings[k] = data[k]


func save_settings() -> void:
	_write_json(settings_path, settings)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


func apply_settings() -> void:
	AudioManager.apply_volumes()
	UI.apply_scale(float(settings["text_scale"]))
	ScreenFX.apply_settings()
	if DisplayServer.get_name() != "headless":
		var want: int = DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
		var cur: int = DisplayServer.window_get_mode()
		var is_full: bool = cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_full != bool(settings["fullscreen"]):
			DisplayServer.window_set_mode(want)
	settings_changed.emit()


func record_ending(ending_id: String) -> void:
	var seen: Array = settings["endings_seen"]
	if not seen.has(ending_id):
		seen.append(ending_id)
		save_settings()


# ---------------------------------------------------------------- game

func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> bool:
	if not GameManager.game_active:
		return false
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": GameManager.get_save_data(),
		"cases": CaseManager.get_save_data(),
		"evidence": EvidenceManager.get_save_data(),
		"dialogue": DialogueManager.get_save_data(),
		"story": StoryDirector.get_save_data(),
	}
	var ok: bool = _write_json(save_path, data)
	if ok:
		game_saved.emit()
	return ok


func load_game() -> bool:
	var data: Variant = _read_json(save_path)
	if not (data is Dictionary):
		last_error = "Save file is missing or unreadable."
		return false
	var d: Dictionary = data
	if int(d.get("version", 0)) != SAVE_VERSION:
		last_error = "Save file version mismatch."
		return false
	for key: String in ["game", "cases", "evidence", "dialogue", "story"]:
		if not (d.get(key) is Dictionary):
			last_error = "Save file is corrupted (missing '%s')." % key
			return false
	GameManager.load_save_data(d["game"])
	CaseManager.load_save_data(d["cases"])
	EvidenceManager.load_save_data(d["evidence"])
	DialogueManager.load_save_data(d["dialogue"])
	StoryDirector.load_save_data(d["story"])
	return true


func get_save_summary() -> String:
	var data: Variant = _read_json(save_path)
	if data is Dictionary and (data as Dictionary).get("game") is Dictionary:
		var g: Dictionary = data["game"]
		return "%s  -  DAY %d  -  saved %s" % [str(g.get("player_name", "?")), int(g.get("day", 1)), str(data.get("saved_at", "")).replace("T", " ")]
	return ""


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# ---------------------------------------------------------------- io

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveManager: could not parse %s (%s)" % [path, json.get_error_message()])
		return null
	return json.data


func _write_json(path: String, data: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]
		push_warning("SaveManager: " + last_error)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Shared helper: reads a JSON data file from res://. Returns null and logs on failure.
func read_data_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Data file missing: " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Data file unreadable: " + path)
		return null
	var json := JSON.new()
	var err: int = json.parse(f.get_as_text())
	f.close()
	if err != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Lists the .json files in a res:// folder, sorted.
func list_data_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		push_error("Data folder missing: " + dir_path)
		return out
	for fn: String in d.get_files():
		if fn.ends_with(".json"):
			out.append(dir_path.path_join(fn))
	out.sort()
	return out
