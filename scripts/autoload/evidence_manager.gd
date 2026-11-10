extends Node
## EvidenceManager (autoload): the player's line selection, the limited pool of
## analysis requests, the collected evidence and which lines have been read.

signal evidence_added(item: Dictionary)
signal selection_changed(case_id: String)

const MAX_SELECTION := 3

var collected: Array = []           # evidence items (dictionaries)
var viewed: Dictionary = {}         # "CASE:line" -> times displayed
var selections: Dictionary = {}     # case_id -> Array of line ids
var requests_used: Dictionary = {}  # case_id -> int
var _next_id: int = 1


func reset_state() -> void:
	collected = []
	viewed = {}
	selections = {}
	requests_used = {}
	_next_id = 1


# ---------------------------------------------------------------- viewing

func mark_viewed(uid: String) -> void:
	viewed[uid] = int(viewed.get(uid, 0)) + 1


func view_count(uid: String) -> int:
	return int(viewed.get(uid, 0))


# ---------------------------------------------------------------- selection

func get_selection(case_id: String) -> Array:
	var s: Variant = selections.get(case_id, [])
	return s if s is Array else []


func is_selected(case_id: String, line_id: String) -> bool:
	return get_selection(case_id).has(line_id)


## Returns false when the selection is full.
func toggle_select(case_id: String, line_id: String) -> bool:
	var sel: Array = get_selection(case_id).duplicate()
	if sel.has(line_id):
		sel.erase(line_id)
	else:
		if sel.size() >= MAX_SELECTION:
			return false
		sel.append(line_id)
	selections[case_id] = sel
	selection_changed.emit(case_id)
	return true


func clear_selection(case_id: String) -> void:
	selections[case_id] = []
	selection_changed.emit(case_id)


# ---------------------------------------------------------------- evidence

func requests_left(case_id: String) -> int:
	return maxi(CaseManager.get_budget(case_id) - int(requests_used.get(case_id, 0)), 0)


func get_for_case(case_id: String) -> Array:
	var out: Array = []
	for item: Variant in collected:
		if str(item.get("case_id", "")) == case_id:
			out.append(item)
	return out


func found_clue_ids(case_id: String) -> Array:
	var out: Array = []
	for item: Variant in collected:
		if str(item.get("case_id", "")) == case_id and str(item.get("clue_id", "")) != "":
			out.append(str(item["clue_id"]))
	return out


func count_confirmed() -> int:
	var n: int = 0
	for item: Variant in collected:
		if str(item.get("clue_id", "")) != "":
			n += 1
	return n


func lines_in_evidence(case_id: String) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in get_for_case(case_id):
		for l: Variant in item.get("lines", []):
			out[str(l)] = true
	return out


func _set_matches(match_sets: Variant, sel: Array) -> bool:
	if not (match_sets is Array):
		return false
	for ms: Variant in match_sets:
		if not (ms is Array) or (ms as Array).is_empty():
			continue
		var all_in: bool = true
		for lid: Variant in ms:
			if not sel.has(str(lid)):
				all_in = false
				break
		if all_in:
			return true
	return false


func _set_touches(match_sets: Variant, sel: Array) -> bool:
	if not (match_sets is Array):
		return false
	for ms: Variant in match_sets:
		for lid: Variant in (ms if ms is Array else []):
			if sel.has(str(lid)):
				return true
	return false


## Spends one analysis request on the current selection.
## Result: {status, items, message}. status is one of
## "empty", "closed", "no_budget", "duplicate", "match", "partial", "none".
func flag_selection(case_id: String, category: String, note: String = "") -> Dictionary:
	var c: Dictionary = CaseManager.get_case(case_id)
	var sel: Array = get_selection(case_id).duplicate()
	if c.is_empty() or sel.is_empty():
		return {"status": "empty", "items": [], "message": "Select at least one line first."}
	if CaseManager.is_done(case_id):
		return {"status": "closed", "items": [], "message": "This case is closed."}
	var found: Array = found_clue_ids(case_id)
	var matches: Array = []
	var partial: bool = false
	var duplicate: bool = false
	for ev: Variant in c["evidence"]:
		var hit: bool = _set_matches(ev["match_sets"], sel)
		if found.has(str(ev["id"])):
			if hit:
				duplicate = true
			continue
		if hit:
			matches.append(ev)
		elif _set_touches(ev["match_sets"], sel):
			partial = true
	if matches.is_empty() and duplicate:
		return {"status": "duplicate", "items": [], "message": "That pattern is already in your evidence collection. Request not charged."}
	if requests_left(case_id) <= 0:
		return {"status": "no_budget", "items": [], "message": "No analysis requests remaining for this case."}
	requests_used[case_id] = int(requests_used.get(case_id, 0)) + 1
	var sources: Array[String] = []
	var quotes: Array[String] = []
	for lid: Variant in sel:
		var line: Dictionary = CaseManager.get_line(case_id, str(lid))
		sources.append(str(line.get("source", "?")))
		quotes.append(CaseManager.line_text(case_id, str(lid)))
	var items: Array = []
	var status: String = "none"
	var message: String = ""
	if not matches.is_empty():
		status = "match"
		for ev: Variant in matches:
			var item := _make_item(case_id, str(ev["id"]), str(ev["title"]), GameManager.format_text(str(ev["description"])),
				str(ev["category"]), category, str(ev["severity"]), note, sel, sources, quotes)
			collected.append(item)
			items.append(item)
		message = "PATTERN CONFIRMED: %d finding(s) added to evidence." % items.size()
	else:
		status = "partial" if partial else "none"
		var desc: String = "No corroborating pattern on file. Logged as analyst opinion only."
		message = "NO PATTERN FOUND. Logged as an unverified observation."
		if partial:
			desc = "A related pattern exists on file, but this selection does not establish it. A comparison line may be missing, or the wrong one was chosen."
			message = "INCOMPLETE: something here is on file, but this selection does not establish it."
		var item := _make_item(case_id, "", "Unverified observation", desc, category, category, "UNRATED", note, sel, sources, quotes)
		collected.append(item)
		items.append(item)
	selections[case_id] = []
	selection_changed.emit(case_id)
	for item: Variant in items:
		evidence_added.emit(item)
		if str(item["clue_id"]) != "":
			StoryDirector.trigger("evidence_collected:%s:%s" % [case_id, str(item["clue_id"])])
	SaveManager.save_game()
	return {"status": status, "items": items, "message": message}


func _make_item(case_id: String, clue_id: String, title: String, description: String, category: String,
		player_category: String, severity: String, note: String, lines: Array, sources: Array[String], quotes: Array[String]) -> Dictionary:
	var item := {
		"id": _next_id, "case_id": case_id, "clue_id": clue_id, "title": title,
		"description": description, "category": category, "player_category": player_category,
		"severity": severity, "note": note.strip_edges(), "lines": lines.duplicate(),
		"source": " + ".join(sources), "quotes": quotes, "day": GameManager.day,
	}
	_next_id += 1
	return item


# ---------------------------------------------------------------- save

func get_save_data() -> Dictionary:
	return {
		"collected": collected.duplicate(true), "viewed": viewed.duplicate(),
		"selections": selections.duplicate(true), "requests_used": requests_used.duplicate(),
		"next_id": _next_id,
	}


func load_save_data(d: Dictionary) -> void:
	reset_state()
	var c: Variant = d.get("collected", [])
	if c is Array:
		for item: Variant in c:
			if item is Dictionary and item.has("case_id") and item.has("title"):
				var it: Dictionary = (item as Dictionary).duplicate(true)
				it["id"] = int(it.get("id", 0))
				it["day"] = int(it.get("day", 1))
				collected.append(it)
	var v: Variant = d.get("viewed", {})
	if v is Dictionary:
		for k: String in (v as Dictionary):
			viewed[k] = int(v[k])
	var s: Variant = d.get("selections", {})
	if s is Dictionary:
		selections = (s as Dictionary).duplicate(true)
	var r: Variant = d.get("requests_used", {})
	if r is Dictionary:
		for k: String in (r as Dictionary):
			requests_used[k] = int(r[k])
	_next_id = int(d.get("next_id", collected.size() + 1))
