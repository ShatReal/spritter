extends Node


func make_auto_sprite(mouse: Vector2, image_size: Vector2, image_data: PoolByteArray) -> Rect2:
	if image_data[mouse.x * 4 + mouse.y * image_size.x * 4 + 3] == 0.0:
		return Rect2(0, 0, 0, 0)
	var rect := Rect2(mouse - Vector2.ONE, Vector2.ONE * 2)
	while not is_rect_clear(rect, image_size, image_data):
		rect = grow_rect(rect, image_size, image_data)
	return Rect2(rect.position + Vector2.ONE, rect.size - Vector2.ONE)
	

func is_rect_clear(r: Rect2, image_size: Vector2, image_data: PoolByteArray) -> bool:
	for x in r.size.x:
		if top_row(r, x, image_size, image_data) or bot_row(r, x, image_size, image_data):
			return false
	for y in r.size.y:
		if lef_col(r, y, image_size, image_data) or rig_col(r, y, image_size, image_data):
			return false
	return true


func grow_rect(r: Rect2, image_size: Vector2, image_data: PoolByteArray) -> Rect2:
	for x in r.size.x:
		while top_row(r, x, image_size, image_data):
			r = Rect2(r.position + Vector2.UP, r.size + Vector2.DOWN)
		while bot_row(r, x, image_size, image_data):
			r = Rect2(r.position, r.size + Vector2.DOWN)
	for y in r.size.y:
		while lef_col(r, y, image_size, image_data):
			r = Rect2(r.position + Vector2.LEFT, r.size + Vector2.RIGHT)
		while rig_col(r, y, image_size, image_data):
			r = Rect2(r.position, r.size + Vector2.RIGHT)
	return r


func top_row(r: Rect2, x: int, image_size: Vector2, image_data: PoolByteArray) -> bool:
	return image_data[(r.position.x + x + r.position.y * image_size.x) * 4 + 3] != 0.0


func bot_row(r: Rect2, x: int, image_size: Vector2, image_data: PoolByteArray) -> bool:
	return image_data[(r.position.x + x + r.end.y * image_size.x) * 4 + 3] != 0.0


func lef_col(r: Rect2, y: int, image_size: Vector2, image_data: PoolByteArray) -> bool:
	return image_data[(r.position.x + (r.position.y + y) * image_size.x) * 4 + 3] != 0.0
	

func rig_col(r: Rect2, y: int, image_size: Vector2, image_data: PoolByteArray) -> bool:
	return image_data[(r.end.x + (r.position.y + y) * image_size.x) * 4 + 3] != 0.0
