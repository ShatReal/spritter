extends Node


var tree: Tree


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


func get_max_vector2(vec1: Vector2, vec2: Vector2) -> Vector2:
	return Vector2(
		max(vec1.x, vec2.x),
		max(vec1.y, vec2.y)
	)
