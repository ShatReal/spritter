extends Panel


var preview_start: Vector2


func _process(_delta: float) -> void:
	var mouse: Vector2 = get_parent().get_local_mouse_position().snapped(Vector2.ONE)
	var parent_rect: Rect2 = get_parent().get_rect()
	mouse.x = clamp(mouse.x, 0, parent_rect.size.x)
	mouse.y = clamp(mouse.y, 0, parent_rect.size.y)
	if mouse.x < preview_start.x:
		if mouse.y < preview_start.y:
			resize(Vector2(mouse.x, mouse.y), Vector2(preview_start.x - mouse.x, preview_start.y - mouse.y))
		else:
			resize(Vector2(mouse.x, preview_start.y), Vector2(preview_start.x - mouse.x, mouse.y - preview_start.y))
	elif mouse.y < preview_start.y:
		resize(Vector2(preview_start.x, mouse.y), Vector2(mouse.x - preview_start.x, preview_start.y - mouse.y))
	else:
		resize(preview_start, mouse - rect_position)


func _input(event: InputEvent) -> void:
	if event.is_action_released("click"):
		for o in get_parent().get_children():
			if o.is_in_group("sprite_outline") and o.get_rect().intersects(get_rect()):
				o.select(true)
		queue_free()


func resize(position: Vector2, size: Vector2) -> void:
	rect_position = position
	rect_size = size
