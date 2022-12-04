extends Panel


var parent_global_rect: Rect2
var preview_start: Vector2


func _process(_delta: float) -> void:
	var mouse: Vector2 = (get_global_mouse_position()).snapped(Vector2.ONE)
	mouse.x = clamp(mouse.x, parent_global_rect.position.x, parent_global_rect.end.x)
	mouse.y = clamp(mouse.y, parent_global_rect.position.y, parent_global_rect.end.y)
	if mouse.x < preview_start.x:
		if mouse.y < preview_start.y:
			resize(Vector2(mouse.x, mouse.y), Vector2(preview_start.x - mouse.x, preview_start.y - mouse.y))
		else:
			resize(Vector2(mouse.x, preview_start.y), Vector2(preview_start.x - mouse.x, mouse.y - preview_start.y))
	elif mouse.y < preview_start.y:
		resize(Vector2(preview_start.x, mouse.y), Vector2(mouse.x - preview_start.x, preview_start.y - mouse.y))
	else:
		resize(preview_start, mouse - rect_global_position)


func _input(event: InputEvent) -> void:
	if event.is_action_released("click"):
		for o in get_tree().get_nodes_in_group("sprite_outline"):
			if o.get_rect().intersects(get_rect()):
				o.select(true)
		queue_free()


func resize(global_position: Vector2, size: Vector2) -> void:
	rect_global_position = global_position
	rect_size = size
