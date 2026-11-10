extends VBoxContainer
## OFFICIAL RESULT: feedback after a classification. Shows the official result,
## which clues mattered, the analyst's accuracy, the trust change and consequences.
## Some results are deliberately partial or sealed.

var desktop: Node
var case_id: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	tree_exiting.connect(_on_closing)


func open_args(args: Dictionary) -> void:
	case_id = str(args.get("case_id", case_id))
	_rebuild()


func _on_closing() -> void:
	if case_id != "" and CaseManager.is_done(case_id) and not GameManager.has_flag("result_ack:" + case_id):
		GameManager.set_flag("result_ack:" + case_id)
		StoryDirector.trigger("result_closed:" + case_id)
		SaveManager.save_game()


func _rebuild() -> void:
	UI.clear(self)
	var c: Dictionary = CaseManager.get_case(case_id)
	var r: Dictionary = CaseManager.get_result(case_id)
	if c.is_empty() or r.is_empty():
		add_child(UI.label("No result on file.", ""))
		return
	var who: String = CharacterManager.get_name_of(str(c["character_id"]))
	var reveal: String = str(c.get("reveal", "full"))
	if desktop != null:
		desktop.call("set_window_title", "result", "OFFICIAL RESULT  -  CASE %s" % str(c.get("number", "")))
	var sc := UI.scroll()
	add_child(sc)
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UI.label("CASE %s  -  %s" % [str(c.get("number", "")), who.to_upper()], "HeaderLabel"))
	var official := UI.panel("Term")
	var ov := UI.vbox(2)
	official.add_child(ov)
	ov.add_child(UI.label("OFFICIAL RESULT", "TermSmall"))
	ov.add_child(UI.label(GameManager.format_text(str(c.get("official_result", "RESULT WITHHELD"))), "TermBig", true))
	v.add_child(official)
	v.add_child(UI.label("YOUR CLASSIFICATION:  " + str(CaseManager.CLASS_LABELS.get(str(r["classification"]), "?")), "HeaderLabel"))
	var acc: int = int(r.get("accuracy", -1))
	if reveal == "sealed":
		v.add_child(UI.label("ANALYST ACCURACY:  PENDING REVIEW  (result sealed by management)", "RedHeader", true))
	elif acc < 0:
		v.add_child(UI.label("ANALYST ACCURACY:  CANNOT BE COMPUTED", "RedHeader", true))
	else:
		v.add_child(UI.label("ANALYST ACCURACY:  %d%%   (classification 70%% / key findings 30%%: %d of %d)" % [acc, int(r["key_found"]), int(r["key_total"])], "HeaderLabel", true))
	var delta: int = int(r.get("trust_delta", 0))
	v.add_child(UI.label("ANALYST CLEARANCE INDEX:  %d   (%s%d)" % [GameManager.trust, "+" if delta >= 0 else "", delta], "RedHeader" if delta < 0 else "HeaderLabel", true))
	v.add_child(UI.label("EXPLANATION", "HeaderLabel"))
	v.add_child(UI.label(GameManager.format_text(str(c["result_explanation"])), "", true))
	v.add_child(UI.label("FINDINGS THAT MATTERED", "HeaderLabel"))
	var found: Array = EvidenceManager.found_clue_ids(case_id)
	var misleading: Array = []
	for ev: Variant in c["evidence"]:
		if bool(ev.get("misleading", false)):
			misleading.append(ev)
		if not bool(ev.get("key", false)):
			continue
		var got: bool = found.has(str(ev["id"]))
		v.add_child(UI.label("%s  %s" % ["[FOUND] " if got else "[MISSED]", str(ev["title"])], "" if got else "RedLabel", true))
		var why: String = str(ev.get("explanation", ""))
		if reveal == "sealed" and not got:
			why = "[withheld]"
		if why != "":
			v.add_child(UI.label("          " + GameManager.format_text(why), "SmallLabel", true))
	if not misleading.is_empty() and reveal != "sealed":
		v.add_child(UI.label("MISLEADING INDICATORS", "HeaderLabel"))
		for ev: Variant in misleading:
			v.add_child(UI.label("%s  %s" % ["[FLAGGED]" if found.has(str(ev["id"])) else "[  --   ]", str(ev["title"])], "", true))
			if str(ev.get("explanation", "")) != "":
				v.add_child(UI.label("          " + GameManager.format_text(str(ev["explanation"])), "SmallLabel", true))
	v.add_child(UI.label("CONSEQUENCE", "HeaderLabel"))
	v.add_child(UI.label(GameManager.format_text(str(r.get("summary", ""))), "", true))
	if str(c.get("unresolved", "")) != "":
		v.add_child(UI.label("UNRESOLVED", "RedHeader"))
		v.add_child(UI.label(GameManager.format_text(str(c["unresolved"])), "", true))
	var b := UI.button("CLOSE FILE", func() -> void:
		if desktop != null:
			desktop.call("close_app", "result"))
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(b)
