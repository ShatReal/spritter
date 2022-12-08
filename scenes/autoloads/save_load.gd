extends Node


signal show_note(message)
signal sheet_loaded(image_data, sprite_data, path)

const START := "Spritter"


func save_sheet(path: String, image: Image, sprites: Dictionary) -> void:
	var f := File.new()
	f.open(path, File.WRITE)
	f.store_var("Spritter")
	f.store_var(image, true)
	var array := []
	for uid in sprites:
		array.append({
			"uid": uid,
			"rect": sprites[uid].outline.get_rect(),
			"name": sprites[uid].tree_item.get_text(0),
			"index": Util.get_outline_index(sprites[uid].tree_item),
		})
	array.sort_custom(Util, "sort_by_index")
	f.store_var(array)
	f.close()


func load_sheet(path: String) -> void:
	var f := File.new()
	f.open(path, File.READ)
	if f.get_len() == 0 and not f.get_var() == START:
		emit_signal("show_note", "Error opening file!")
		f.close()
		return
	var spritter = f.get_var()
	var image_data = f.get_var(true)
	var sprite_data = f.get_var()
	f.close()
	if not spritter == "Spritter" or not image_data is Image or not sprite_data is Array:
		emit_signal("show_note", "Error opening file!")
		return
	for sprite in sprite_data:
		if not sprite is Dictionary or not sprite.has_all(["uid", "rect", "name", "index"]) or not sprite.uid is int or not sprite.rect is Rect2 or not sprite.name is String or not sprite.index is int:
			emit_signal("show_note", "Error opening file!")
			return
	emit_signal("sheet_loaded", image_data, sprite_data, path)
