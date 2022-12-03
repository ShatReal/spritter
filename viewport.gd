extends Viewport

func _input(event: InputEvent) -> void:
	get_tree().current_scene._input(event)
