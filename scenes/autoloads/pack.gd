extends Node


signal show_note(message)


func pack(paths: PoolStringArray, constrain: int, max_size: int, padding_x: int, padding_y: int, color: Color) -> Dictionary:
	var images := []
	for path in paths:
		var img := Image.new()
		if not img.load(path) == OK:
			emit_signal("show_note", "Error loading %s!" % path)
			return {}
		images.append(img)
	var all_rects := []
	var current_position := Vector2(padding_x, padding_y)
	var result := Image.new()
	if constrain == 0: # Width first
		images.sort_custom(self, "sort_by_width_descending")
		var height := 0
		var result_x := 0
		for i in images.size():
			var img: Image = images[i]
			if current_position.x + img.get_width() > max_size:
				if not current_position.y == padding_y:
					current_position.y += height + padding_y
				height = img.get_height()
				if current_position.x > result_x:
					result_x = current_position.x
				current_position.x = padding_x
			all_rects.append(Rect2(current_position, img.get_size()))
			current_position.x += img.get_width() + padding_x
			if i == images.size() - 1 and height == 0:
				height = images[0].get_height()
				if current_position.x > result_x:
					result_x = current_position.x
		result.create(result_x, current_position.y + height + padding_y, false, Image.FORMAT_RGBA8)
	else: # Height first
		images.sort_custom(self, "sort_by_height_descending")
		var width := 0
		var result_y := 0
		for i in images.size():
			var img: Image = images[i]
			if current_position.y + img.get_height() > max_size:
				if not current_position.x == padding_x:
					current_position.x += width + padding_x
				width = img.get_width()
				if current_position.y > result_y:
					result_y = current_position.y
				current_position.y = padding_y
			all_rects.append(Rect2(current_position, img.get_size()))
			current_position.y += img.get_height() + padding_y
			if i == images.size() - 1 and width == 0:
				width = images[0].get_width()
				if current_position.y > result_y:
					result_y = current_position.y
		result.create(current_position.x + width + padding_x, result_y, false, Image.FORMAT_RGBA8)
	result.fill(color)
	for i in images.size():
		result.blit_rect(images[i], Rect2(Vector2.ZERO, images[i].get_size()), all_rects[i].position)
	return {
		"data": result,
		"all_rects": all_rects,
	}


func sort_by_width_descending(a: Image, b: Image) -> bool:
	return a.get_width() > b.get_width()


func sort_by_height_descending(a: Image, b: Image) -> bool:
	return a.get_height() > b.get_height()
