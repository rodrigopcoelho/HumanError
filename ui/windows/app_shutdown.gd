extends VBoxContainer
## EXIT / SHUTDOWN: leave the desk, end the shift, settings, save and quit.

var desktop: Node


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UI.label("HVC TERMINAL  -  SESSION CONTROL", "HeaderLabel"))
	add_child(UI.label("Analyst: %s   Employee no.: %s" % [GameManager.player_name, GameManager.EMPLOYEE_ID], "SmallLabel", true))
	var end := UI.button("END SHIFT", func() -> void:
		desktop.call("show_confirm", "END SHIFT", "Log out and end today's shift? You can look around the office before you go home.", "END SHIFT", GameManager.end_shift))
	end.disabled = not GameManager.can_end_shift()
	add_child(end)
	var why: String = "Today's case is closed. You may end your shift."
	if GameManager.day >= GameManager.LAST_DAY:
		why = "SHIFT CANNOT BE ENDED. Employee verification sweep pending. Remain at your terminal."
	elif not GameManager.is_day_case_done():
		why = "You cannot end the shift until today's case has been submitted."
	add_child(UI.label(why, "RedLabel" if end.disabled else "SmallLabel", true))
	add_child(UI.button("STAND UP FROM DESK", func() -> void:
		SaveManager.save_game()
		GameManager.goto_scene("office")))
	add_child(UI.label("Your windows and investigation progress are kept.", "SmallLabel", true))
	add_child(UI.button("SETTINGS", func() -> void: desktop.call("show_settings")))
	add_child(UI.button("SAVE AND QUIT TO MAIN MENU", func() -> void: GameManager.quit_to_menu()))
	add_child(UI.button("CANCEL", func() -> void: desktop.call("close_app", "shutdown")))
	add_child(UI.label("Progress is saved automatically.", "SmallLabel", true))
