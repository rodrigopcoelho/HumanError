extends Node
## CaseManager (autoload): loads and validates investigation cases from JSON,
## resolves line text (including story-driven mutations), scores classifications
## and applies their consequences.

signal case_submitted(case_id: String, result: Dictionary)

const CASE_DIR := "res://data/cases"
const CLASSIFICATIONS := ["VERIFIED_HUMAN", "SUSPICIOUS", "CORRUPTED_AI", "UNDETERMINED"]
const CLASS_LABELS := {
	"VERIFIED_HUMAN": "VERIFIED HUMAN",
	"SUSPICIOUS": "SUSPICIOUS",
	"CORRUPTED_AI": "CORRUPTED AI",
	"UNDETERMINED": "UNDETERMINED",
}
const CLASS_DESCRIPTIONS := {
	"VERIFIED_HUMAN": "The available evidence strongly suggests that the person is human.",
	"SUSPICIOUS": "There are inconsistencies, but insufficient evidence to establish that the person is a corrupted AI.",
	"CORRUPTED_AI": "The evidence strongly indicates that the individual is an artificial intelligence imitation.",
	"UNDETERMINED": "There is insufficient evidence to reach a reliable conclusion.",
}
const CATEGORIES := ["WRITING_STYLE", "MEMORY", "EMOTIONAL", "LOGICAL"]
const CATEGORY_LABELS := {
	"WRITING_STYLE": "Writing style", "MEMORY": "Memory consistency",
	"EMOTIONAL": "Emotional consistency", "LOGICAL": "Logical consistency",
}
const SEVERITIES := ["LOW", "MODERATE", "HIGH", "CRITICAL"]
const REQUIRED_KEYS := ["case_id", "character_id", "title", "difficulty", "day",
	"historical_messages", "questionnaire_answers", "evidence",
	"correct_classification", "result_explanation", "consequences", "truth"]
## How much each classification is worth, depending on what the subject really is.
const SCORE_TABLE := {
	"HUMAN": {"VERIFIED_HUMAN": 1.0, "SUSPICIOUS": 0.4, "UNDETERMINED": 0.3, "CORRUPTED_AI": 0.0},
	"AI": {"CORRUPTED_AI": 1.0, "SUSPICIOUS": 0.5, "UNDETERMINED": 0.3, "VERIFIED_HUMAN": 0.0},
}

var cases: Dictionary = {}          # case_id -> definition
var order: Array[String] = []
var results: Dictionary = {}        # case_id -> result dictionary
var load_errors: Array[String] = []
var _lines: Dictionary = {}         # case_id -> {line_id -> line info}


func _ready() -> void:
	load_all()


# ---------------------------------------------------------------- loading

func load_all() -> void:
	cases.clear()
	order.clear()
	_lines.clear()
	load_errors.clear()
	for path: String in SaveManager.list_data_files(CASE_DIR):
		var data: Variant = SaveManager.read_data_file(path)
		if not (data is Dictionary):
			load_errors.append("%s: not a JSON object" % path)
			continue
		var errs: Array[String] = validate_case(data)
		if not errs.is_empty():
			for e: String in errs:
				load_errors.append("%s: %s" % [path.get_file(), e])
			continue
		var id: String = str(data["case_id"])
		cases[id] = data
		order.append(id)
		_index_lines(id, data)
	order.sort_custom(func(a: String, b: String) -> bool:
		return int(cases[a]["day"]) * 100 + int(cases[a].get("order", 0)) < int(cases[b]["day"]) * 100 + int(cases[b].get("order", 0)))
	for e: String in load_errors:
		push_error("CaseManager: " + e)


## Returns a list of problems; empty means the case is usable.
func validate_case(c: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for k: String in REQUIRED_KEYS:
		if not c.has(k):
			errs.append("missing key '%s'" % k)
	if not errs.is_empty():
		return errs
	if not CLASSIFICATIONS.has(str(c["correct_classification"])):
		errs.append("invalid correct_classification")
	if not ["HUMAN", "AI", "UNKNOWN"].has(str(c["truth"])):
		errs.append("invalid truth value")
	if not (c["historical_messages"] is Array) or (c["historical_messages"] as Array).size() < 5:
		errs.append("needs at least 5 historical messages")
	if not (c["questionnaire_answers"] is Array) or (c["questionnaire_answers"] as Array).size() < 5:
		errs.append("needs at least 5 questionnaire answers")
	if not (c["evidence"] is Array) or (c["evidence"] as Array).size() < 3:
		errs.append("needs at least 3 evidence entries")
	if not errs.is_empty():
		return errs
	var ids: Dictionary = {}
	for m: Variant in c["historical_messages"]:
		if not (m is Dictionary) or not m.has("id") or not m.has("text"):
			errs.append("historical message without id/text")
		else:
			ids[str(m["id"])] = true
	for q: Variant in c["questionnaire_answers"]:
		if not (q is Dictionary) or not q.has("id") or not q.has("answer") or not q.has("question"):
			errs.append("questionnaire entry without id/question/answer")
		else:
			ids[str(q["id"])] = true
	for doc: Variant in c.get("documents", []):
		if not (doc is Dictionary) or not (doc.get("lines") is Array):
			errs.append("document without lines")
			continue
		for l: Variant in doc["lines"]:
			if l is Dictionary and l.has("id"):
				ids[str(l["id"])] = true
	var has_misleading: bool = false
	for ev: Variant in c["evidence"]:
		if not (ev is Dictionary):
			errs.append("evidence entry is not an object")
			continue
		for k: String in ["id", "title", "description", "category", "severity", "match_sets"]:
			if not ev.has(k):
				errs.append("evidence '%s' missing '%s'" % [str(ev.get("id", "?")), k])
		if ev.has("category") and not CATEGORIES.has(str(ev["category"])):
			errs.append("evidence '%s' has invalid category" % str(ev.get("id", "?")))
		if bool(ev.get("misleading", false)):
			has_misleading = true
		for ms: Variant in ev.get("match_sets", []):
			for lid: Variant in (ms if ms is Array else []):
				if not ids.has(str(lid)):
					errs.append("evidence '%s' references unknown line '%s'" % [str(ev.get("id", "?")), str(lid)])
	if not has_misleading:
		errs.append("needs at least one misleading clue")
	for cls: String in CLASSIFICATIONS:
		if not (c["consequences"] is Dictionary) or not (c["consequences"] as Dictionary).has(cls):
			errs.append("consequences missing '%s'" % cls)
	return errs


func _index_lines(id: String, c: Dictionary) -> void:
	var idx: Dictionary = {}
	var threads: Variant = c.get("threads", {})
	for m: Variant in c["historical_messages"]:
		var label: String = str((threads as Dictionary).get(str(m.get("thread", "")), "Archive")) if threads is Dictionary else "Archive"
		idx[str(m["id"])] = {"id": str(m["id"]), "kind": "message", "text": str(m["text"]),
			"meta": "%s  ·  %s" % [str(m.get("timestamp", "")), str(m.get("from", ""))],
			"source": "Archive · %s · %s" % [label, str(m.get("timestamp", ""))],
			"mutation": m.get("mutation"), "other": bool(m.get("other", false))}
	for q: Variant in c["questionnaire_answers"]:
		idx[str(q["id"])] = {"id": str(q["id"]), "kind": "answer", "text": str(q["answer"]),
			"meta": str(q["question"]), "source": "Questionnaire · \"%s\"" % str(q["question"]),
			"mutation": q.get("mutation"), "other": false}
	for doc: Variant in c.get("documents", []):
		for l: Variant in doc["lines"]:
			idx[str(l["id"])] = {"id": str(l["id"]), "kind": "document", "text": str(l["text"]),
				"meta": str(doc.get("title", "File")), "source": "File · %s" % str(doc.get("title", "File")),
				"mutation": l.get("mutation"), "other": false}
	_lines[id] = idx


# ---------------------------------------------------------------- queries

func get_case(id: String) -> Dictionary:
	var c: Variant = cases.get(id, {})
	return c if c is Dictionary else {}


func is_available(id: String) -> bool:
	var c: Dictionary = get_case(id)
	if c.is_empty():
		return false
	if int(c["day"]) > GameManager.day:
		return false
	return GameManager.check_requires(c.get("requires", {}))


func get_available_cases() -> Array[String]:
	var out: Array[String] = []
	for id: String in order:
		if is_available(id):
			out.append(id)
	return out


func is_done(id: String) -> bool:
	return results.has(id)


func get_result(id: String) -> Dictionary:
	var r: Variant = results.get(id, {})
	return r if r is Dictionary else {}


func get_classification(id: String) -> String:
	return str(get_result(id).get("classification", ""))


func get_line(case_id: String, line_id: String) -> Dictionary:
	var idx: Variant = _lines.get(case_id, {})
	var l: Variant = (idx as Dictionary).get(line_id, {})
	return l if l is Dictionary else {}


## Text of a line as it should be displayed right now. Some lines change after
## they have been read (EVENT 04: CHANGED HISTORY).
func line_text(case_id: String, line_id: String) -> String:
	var l: Dictionary = get_line(case_id, line_id)
	if l.is_empty():
		return ""
	var text: String = str(l["text"])
	var m: Variant = l.get("mutation")
	if m is Dictionary:
		var uid: String = case_id + ":" + line_id
		if GameManager.day >= int(m.get("min_day", 1)) \
				and EvidenceManager.view_count(uid) >= int(m.get("after_views", 1)) \
				and GameManager.check_requires(m.get("requires", {})):
			text = str(m.get("text", text))
			if not GameManager.has_flag("mutated:" + uid):
				GameManager.set_flag("mutated:" + uid)
				StoryDirector.trigger.call_deferred("line_mutated")
	return GameManager.format_text(text)


func get_documents(case_id: String) -> Array:
	var out: Array = []
	for doc: Variant in get_case(case_id).get("documents", []):
		if doc is Dictionary and GameManager.check_requires(doc.get("requires", {})):
			out.append(doc)
	return out


func get_budget(case_id: String) -> int:
	return int(get_case(case_id).get("analysis_requests", 8))


func get_clue(case_id: String, clue_id: String) -> Dictionary:
	for ev: Variant in get_case(case_id).get("evidence", []):
		if ev is Dictionary and str(ev["id"]) == clue_id:
			return ev
	return {}


func status_label(case_id: String) -> String:
	if is_done(case_id):
		return "CLOSED - " + str(CLASS_LABELS.get(get_classification(case_id), "?"))
	return "PENDING VERIFICATION"


## Mean accuracy over scored cases, or -1 when nothing has been scored.
func average_accuracy() -> int:
	var total: int = 0
	var n: int = 0
	for id: String in results:
		var acc: int = int(results[id].get("accuracy", -1))
		if acc >= 0:
			total += acc
			n += 1
	return -1 if n == 0 else roundi(float(total) / float(n))


# ---------------------------------------------------------------- submission

func submit(case_id: String, classification: String) -> Dictionary:
	var c: Dictionary = get_case(case_id)
	if c.is_empty() or not CLASSIFICATIONS.has(classification):
		push_error("CaseManager.submit: invalid case or classification (%s, %s)" % [case_id, classification])
		return {}
	if is_done(case_id):
		return get_result(case_id)
	var truth: String = str(c["truth"])
	var found: Array = EvidenceManager.found_clue_ids(case_id)
	var key_total: int = 0
	var key_found: int = 0
	for ev: Variant in c["evidence"]:
		if bool(ev.get("key", false)):
			key_total += 1
			if found.has(str(ev["id"])):
				key_found += 1
	var accuracy: int = -1
	if SCORE_TABLE.has(truth):
		var class_score: float = float(SCORE_TABLE[truth][classification])
		var ev_score: float = 1.0 if key_total == 0 else float(key_found) / float(key_total)
		accuracy = roundi((0.7 * class_score + 0.3 * ev_score) * 100.0)
	var cons: Dictionary = c["consequences"][classification]
	var trust_delta: int = int(cons.get("trust", 0))
	var result := {
		"classification": classification,
		"correct": classification == str(c["correct_classification"]),
		"accuracy": accuracy,
		"trust_delta": trust_delta,
		"evidence_found": found.size(),
		"key_found": key_found,
		"key_total": key_total,
		"summary": str(cons.get("summary", "")),
		"day": GameManager.day,
	}
	if bool(c.get("final", false)):
		return result
	results[case_id] = result
	GameManager.adjust_trust(trust_delta)
	GameManager.adjust_rapport(int(cons.get("rapport", 0)))
	var fl: Variant = cons.get("flags", {})
	if fl is Dictionary:
		for f: String in (fl as Dictionary):
			GameManager.set_flag(f, fl[f])
	case_submitted.emit(case_id, result)
	StoryDirector.trigger("case_submitted:" + case_id)
	SaveManager.save_game()
	return result


# ---------------------------------------------------------------- save

func reset_state() -> void:
	results = {}


func get_save_data() -> Dictionary:
	return {"results": results.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	results = {}
	var r: Variant = d.get("results", {})
	if r is Dictionary:
		for id: String in (r as Dictionary):
			if cases.has(id) and r[id] is Dictionary:
				var res: Dictionary = (r[id] as Dictionary).duplicate(true)
				for k: String in ["accuracy", "trust_delta", "evidence_found", "key_found", "key_total", "day"]:
					res[k] = int(res.get(k, 0))
				results[id] = res
