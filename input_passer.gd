extends Node


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("edit_sprites") or event.is_action_pressed("select_sprites") or event.is_action_pressed("delete") or event.is_action_pressed("select_all") or event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_released("ui_up") or event.is_action_released("ui_down") or event.is_action_released("ui_left") or event.is_action_released("ui_right") or event.is_action_pressed("undo") or event.is_action_pressed("redo") or event.is_action_pressed("save"):
		get_tree().set_input_as_handled()
		get_tree().current_scene._unhandled_input(event)
