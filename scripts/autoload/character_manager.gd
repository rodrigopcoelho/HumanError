extends Node
## CharacterManager (autoload): loads character profiles and the employee directory,
## resolves day/flag dependent directory changes and validates relationships.

const CHARACTER_DIR := "res://data/characters"
const DIRECTORY_FILE := "res://data/characters/directory.json"
const REQUIRED_FIELDS := ["id", "name", "age", "occupation", "personality", "writing_style",
	"background", "memories", "emotional_traits", "narrative_role", "hidden_information",
	"truth", "relationships", "portrait"]

var characters: Dictionary = {}     # id -> profile
var directory: Array = []           # raw directory entries
var load_errors: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	characters.clear()
	directory.clear()
	load_errors.clear()
	for path: String in SaveManager.list_data_files(CHARACTER_DIR):
		if path == DIRECTORY_FILE:
			continue
		var data: Variant = SaveManager.read_data_file(path)
		if not (data is Dictionary):
			load_errors.append("%s: not a JSON object" % path)
			continue
		var c: Dictionary = data
		var missing: Array[String] = []
		for f: String in REQUIRED_FIELDS:
			if not c.has(f):
				missing.append(f)
		if not missing.is_empty():
			load_errors.append("%s: missing fields %s" % [path, str(missing)])
			continue
		characters[str(c["id"])] = c
	var dir_data: Variant = SaveManager.read_data_file(DIRECTORY_FILE)
	if dir_data is Dictionary and (dir_data as Dictionary).get("employees") is Array:
		directory = dir_data["employees"]
	else:
		load_errors.append("directory.json: missing 'employees' array")
	_validate_relationships()
	for e: String in load_errors:
		push_error("CharacterManager: " + e)


func _validate_relationships() -> void:
	for id: String in characters:
		for rel: Variant in characters[id]["relationships"]:
			if rel is Dictionary and not characters.has(str(rel.get("id", ""))) and not _directory_has(str(rel.get("id", ""))):
				load_errors.append("%s: relationship to unknown id '%s'" % [id, str(rel.get("id", ""))])


func _directory_has(id: String) -> bool:
	for e: Variant in directory:
		if e is Dictionary and str(e.get("id", "")) == id:
			return true
	return false


func get_character(id: String) -> Dictionary:
	var c: Variant = characters.get(id, {})
	return c if c is Dictionary else {}


func get_name_of(id: String) -> String:
	if characters.has(id):
		return str(characters[id]["name"])
	for e: Variant in directory:
		if e is Dictionary and str(e.get("id", "")) == id:
			return str(e.get("name", id))
	return id


func get_relationships(id: String) -> Array:
	var c: Dictionary = get_character(id)
	var r: Variant = c.get("relationships", [])
	return r if r is Array else []


func get_portrait(id: String) -> Texture2D:
	var c: Dictionary = get_character(id)
	return UI.photo(str(c.get("portrait", "")))


## The employee directory as it currently appears: entries can be hidden, and
## fields can be overridden, depending on the day and story flags.
func get_directory() -> Array:
	var out: Array = []
	for raw: Variant in directory:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = (raw as Dictionary).duplicate(true)
		if e.has("requires") and not GameManager.check_requires(e["requires"]):
			continue
		var cid: String = str(e.get("character_id", ""))
		if cid != "" and characters.has(cid):
			var c: Dictionary = characters[cid]
			for k: String in ["name", "age", "portrait"]:
				if not e.has(k):
					e[k] = c[k]
			if not e.has("title"):
				e["title"] = c["occupation"]
		for variant: Variant in e.get("variants", []):
			if variant is Dictionary and GameManager.check_requires(variant.get("requires", {})):
				var fields: Variant = variant.get("fields", {})
				if fields is Dictionary:
					for k: String in (fields as Dictionary):
						e[k] = fields[k]
		for k: String in e:
			if e[k] is String:
				e[k] = GameManager.format_text(e[k])
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return out
