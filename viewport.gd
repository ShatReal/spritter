extends Viewport

func _unhandled_input(event: InputEvent) -> void:
	get_tree().current_scene._unhandled_input(event)
