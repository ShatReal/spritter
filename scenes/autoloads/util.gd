extends Node



func sort_by_index(a: Dictionary, b: Dictionary) -> bool:
	return a.index < b.index


func get_outline_index(tree_item: TreeItem) -> int:
	var index := 0
	var ti: TreeItem = tree_item.get_parent().get_children()
	while ti:
		if ti == tree_item:
			break
		ti = ti.get_next()
		index += 1
	return index


func get_uid_from_object(object, sprites: Dictionary) -> int:
	for uid in sprites:
		if object is Button and sprites[uid].outline == object:
			return uid
		elif object is TreeItem and sprites[uid].tree_item == object:
			return uid
	return -1 # Could not find uid


func get_max_vector2(vectors: Array) -> Vector2:
	var max_vec := Vector2.ZERO
	for vector in vectors:
		if vector.x > max_vec.x:
			max_vec.x = vector.x
		if vector.y > max_vec.y:
			max_vec.y = vector.y
	return max_vec

func remove_file_extension(file: String) -> String:
	var arr := file.split(".")
	arr.remove(arr.size() - 1)
	return arr.join(".")
