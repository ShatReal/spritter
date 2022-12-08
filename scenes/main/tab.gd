extends HBoxContainer


signal show_file(mode, filters, action)
signal close_tab
signal zoom_changed(zoom)

const SpriteOutline := preload("res://scenes/main/sprite_outline.tscn")
const Selection := preload("res://scenes/main/selection.tscn")

const ZOOM_INTERVALS := [1.0/8, 1.0/4, 1.0/2, 1.0, 2.0, 4.0, 8.0]
const MAX_HISTORY := 100
const SCROLL_SPEED := 5
const MOVE_TIME_0 := 0.2
const MOVE_TIME_1 := 0.1

var image: Image
var image_size: Vector2
var image_data: PoolByteArray
var save_path: String

var sprites := {}
var current_being_created_uid := -1

var history := []
var history_index := -1

var action := ""

var tree_root: TreeItem

var zoom_counter := 3
var name_counter := 0
var is_drawing := false

var movement_temp: Array

onready var scroll := $Scroll
onready var tree := $Tree
onready var images := $Scroll/Images
onready var background := $Scroll/Images/Background
onready var image_node := $Scroll/Images/Image


func _ready() -> void:
	tree_root = tree.create_item()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not image_node.texture:
		return
	if event.is_action_pressed("save"):
		if save_path:
			SaveLoad.save_sheet(save_path, image, sprites)
		else:
			emit_signal("show_file", FileDialog.MODE_SAVE_FILE, PoolStringArray(["*.spritter"]), "save")
	elif event.is_action_pressed("select_all"):
		for outline in image_node.get_children():
			if outline.is_in_group("sprite_outline"):
				outline.select(true)
	elif event.is_action_pressed("delete"):
		delete_outlines()
	elif event.is_action_pressed("zoom_in"):
		zoom(1)
	elif event.is_action_pressed("zoom_out"):
		zoom(-1)
	elif (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) and $MoveTimer.is_stopped():
		start_movement()
		move_all_selected_outlines()
		$MoveTimer.wait_time = MOVE_TIME_0
		$MoveTimer.start()
	elif (event.is_action_released("ui_up") or event.is_action_released("ui_down") or event.is_action_released("ui_left") or event.is_action_released("ui_right")) and Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() == 0:
		end_movement()
		$MoveTimer.stop()
	elif event.is_action_pressed("redo"):
		redo()
	elif event.is_action_pressed("undo"):
		undo()
	elif event.is_action_pressed("move"):
		enable_sprites(false)
	elif event.is_action_released("move"):
		enable_sprites(true)


func get_mouse() -> Vector2:
	return image_node.get_local_mouse_position().snapped(Vector2.ONE)


func delete_outlines() -> void:
	if tree_root.is_selected(0):
		emit_signal("close_tab")
		return
	var dict := {
		"action": "delete",
		"outlines": [],
	}
	var tree_items_to_free := []
	for outline in image_node.get_children():
		if outline.is_in_group("sprite_outline") and outline.selected:
			var uid := Util.get_uid_from_object(outline, sprites)
			dict.outlines.append({
				"rect": outline.get_rect(),
				"name": sprites[uid].tree_item.get_text(0),
				"uid": uid,
				"index": sprites[uid].index,
			})
			tree_items_to_free.append(sprites[uid].tree_item)
			sprites.erase(uid)
			outline.queue_free()
	for tree_item in tree_items_to_free:
		tree_root.remove_child(tree_item)
		tree_item.free()
	dict.outlines.sort_custom(Util, "sort_by_index")
	add_history(dict)


func zoom(change: int) -> void:
	zoom_counter += change
	if zoom_counter > ZOOM_INTERVALS.size() - 1:
		zoom_counter = ZOOM_INTERVALS.size() - 1
		return
	if zoom_counter < 0:
		zoom_counter = 0
		return
	background.rect_scale = Vector2(ZOOM_INTERVALS[zoom_counter], ZOOM_INTERVALS[zoom_counter])
	image_node.rect_scale = Vector2(ZOOM_INTERVALS[zoom_counter], ZOOM_INTERVALS[zoom_counter])
	images.rect_min_size = image_node.rect_scale * image_size
	yield(get_tree(), "idle_frame")
	var max_vector := Util.get_max_vector2([scroll.rect_size, images.rect_min_size])
	background.rect_position = max_vector / 2 - image_size * ZOOM_INTERVALS[zoom_counter] / 2
	image_node.rect_position = max_vector / 2 - image_size * ZOOM_INTERVALS[zoom_counter] / 2
	emit_signal("zoom_changed", ZOOM_INTERVALS[zoom_counter])
 

func start_movement() -> void:
	movement_temp = []
	for outline in image_node.get_children():
		if outline.is_in_group("sprite_outline") and outline.selected:
			movement_temp.append({
				"uid": Util.get_uid_from_object(outline, sprites),
				"pos": outline.rect_position,
			})


func end_movement() -> void:
	if movement_temp.size() == 0:
		return
	var ends := []
	for dict in movement_temp:
		ends.append({
			"uid": dict.uid,
			"pos": sprites[dict.uid].outline.rect_position,
		})
	add_history({
		"action": "move",
		"starts": movement_temp,
		"ends": ends,
	})


func redo() -> void:
	history_index += 1
	if history.size() == history_index:
		history_index = history.size() - 1
		return
	var a: Dictionary = history[history_index]
	match a.action:
		"move":
			for dict in a.ends:
				sprites[dict.uid].outline.rect_position = dict.pos
		"delete":
			for outline in a.outlines:
				delete_outline(outline.uid)
		"resize":
			sprites[a.uid].outline.resize(a.new_rect.position, a.new_rect.size)
		"create":
			for outline in a.outlines:
				make_sprite_outline(outline.rect.position, outline.rect.size, outline.name, false, outline.uid, outline.index)
		"rename":
			sprites[a.uid].name = a.new
			sprites[a.uid].tree_item.set_text(0, a.new)
		"combine":
			for dict in a.deleted:
				delete_outline(dict.uid)
			make_sprite_outline(a.result.rect.position, a.result.rect.size, a.result.name, false, a.result.uid, a.result.index)


func undo() -> void:
	if history_index == -1:
		return
	var a: Dictionary = history[history_index]
	match a.action:
		"move":
			for dict in a.starts:
				sprites[dict.uid].outline.rect_position = dict.pos
		"delete":
			for outline in a.outlines:
				make_sprite_outline(outline.rect.position, outline.rect.size, outline.name, false, outline.uid, outline.index)
		"resize":
			sprites[a.uid].outline.resize(a.original_rect.position, a.original_rect.size)
		"create":
			for outline in a.outlines:
				delete_outline(outline.uid)
		"rename":
			sprites[a.uid].name = a.old
			sprites[a.uid].tree_item.set_text(0, a.old)
		"combine":
			delete_outline(a.result.uid)
			for dict in a.deleted:
				make_sprite_outline(dict.rect.position, dict.rect.size, dict.name, false, dict.uid, dict.index)
	history_index -= 1
	

func enable_sprites(on: bool) -> void:
	for outline in image_node.get_children():
		if outline.is_in_group("sprite_outline"):
			outline.enable(on)


func add_history(dict: Dictionary) -> void:
	while history.size() > history_index + 1:
		history.pop_back()
	history_index += 1
	history.append(dict)
	if history.size() == MAX_HISTORY:
		history.pop_front()
		history_index -= 1


func delete_outline(uid) -> void:
	sprites[uid].outline.queue_free()
	tree_root.remove_child(sprites[uid].tree_item)
	sprites[uid].tree_item.free()
	sprites.erase(uid)


func make_sprite_outline(pos: Vector2, outline_size: Vector2, n: String, is_preview := false, uid := -1, index := -1) -> int:
	var outline := SpriteOutline.instance()
	image_node.add_child(outline)
	outline.resize(pos, outline_size)
	outline.name = n
	outline.connect("selected", self, "on_outline_selected", [outline])
	outline.connect("outline_resized", self, "on_outline_resized", [outline])
	outline.connect("move_started", self, "start_movement")
	outline.connect("move_ended", self, "end_movement")
	var tree_item: TreeItem
	if index == -1:
		tree_item = tree.create_item(tree_root)
		index = Util.get_outline_index(tree_item)
	else:
		tree_item = tree.create_item(tree_root, index)
	tree_item.set_editable(0, true)
	tree_item.set_text(0, n)
	if uid == -1:
		uid = randi()
		while uid in sprites:
			uid = randi()
	sprites[uid] = {
		"outline": outline,
		"tree_item": tree_item,
		"name": n,
		"index": index,
	}
	if is_preview:
		outline.preview_start = pos
		outline.set_preview(true)
	outline.select(true)
	return uid
	
	
func _on_Tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if item == tree.get_root() and selected:
		for outline in image_node.get_children():
			if outline.is_in_group("sprite_outline"):
				outline.select(false)
		return
	for uid in sprites:
		if sprites[uid].tree_item == item:
			sprites[uid].outline.select(selected)
			return


func on_outline_resized(original_rect: Rect2, new_rect: Rect2, outline: Button) -> void:
	add_history({
		"action": "resize",
		"original_rect": original_rect,
		"new_rect": new_rect,
		"uid": Util.get_uid_from_object(outline, sprites),
	})
	
	
func on_outlines_created(uids: Array) -> void:
	var dict := {
		"action": "create",
		"outlines": []
	}
	for uid in uids:
		dict.outlines.append(
			{
				"uid": uid,
				"rect": sprites[uid].outline.get_rect(),
				"name": sprites[uid].tree_item.get_text(0),
				"index": sprites[uid].index,
			}
		)
	dict.outlines.sort_custom(Util, "sort_by_index")
	add_history(dict)


func init(path := "", d = null, sprite_data = null) -> bool:
	if d:
		image = d
	else:
		image = Image.new()
		if image.load(path) != OK:
			return false
	image_size = image.get_size()
	image_data = image.get_data()
	name = Util.remove_file_extension(path.get_file())
	if path.ends_with(".spritter"):
		save_path = path
	var text := ImageTexture.new()
	text.create_from_image(image, 0)
	image_node.texture = text
	tree_root.set_text(0, name)
	zoom(0)
	if sprite_data:
		for dict in sprite_data:
			make_sprite_outline(dict.rect.position, dict.rect.size, dict.name, false, dict.uid, dict.index)
	return true


func display_sprites(all_rects: Array) -> void:
	var uids := []
	for rect in all_rects:
		uids.append(make_sprite_outline(rect.position, rect.size, str(name_counter)))
		name_counter += 1
	on_outlines_created(uids)


func on_outline_selected(on: bool, outline: Button) -> void:
	for uid in sprites:
		if sprites[uid].outline == outline:
			if on:
				sprites[uid].tree_item.select(0)
			else:
				sprites[uid].tree_item.deselect(0)
			return


func export_sprites(dir: String) -> void:
	var directory := Directory.new()
	if not directory.dir_exists(dir + "/%s" % name):
		directory.make_dir(dir + "/%s" % name)
	for uid in sprites:
		image.get_rect(sprites[uid].outline.get_rect()).save_png(dir + "/%s/%s.png" % [name, sprites[uid].name])


func on_outside_sprite_gui_input(event: InputEvent) -> void:
	if not image_node.texture or not visible:
		return
	if Input.is_action_pressed("move") and event is InputEventMouseMotion:
		scroll.scroll_horizontal -= event.relative.x / get_viewport().size.x * scroll.get_h_scrollbar().max_value * SCROLL_SPEED
		scroll.scroll_vertical -= event.relative.y / get_viewport().size.y * scroll.get_v_scrollbar().max_value * SCROLL_SPEED
	elif event.is_action_pressed("zoom_in"):
		zoom(1)
	elif event.is_action_pressed("zoom_out"):
		zoom(-1)
	elif event.is_action_pressed("move"):
		enable_sprites(false)
	elif event.is_action_released("move"):
		enable_sprites(true)
	if Input.is_action_pressed("move"):
		return
	var mouse: Vector2 = image_node.get_local_mouse_position().snapped(Vector2.ONE)
	if event.is_action_released("click"):
		is_drawing = false
		if action == "select_sprites":
			return
		if current_being_created_uid != -1:
			sprites[current_being_created_uid].outline.set_preview(false)
			on_outlines_created([current_being_created_uid])
			current_being_created_uid = -1
	elif event.is_action_pressed("click"):
		if not Input.is_action_pressed("shift"):
			for outline in image_node.get_children():
				if outline.is_in_group("sprite_outline") and outline.selected:
					outline.select(false)
		if not Rect2(Vector2.ZERO, image_size).has_point(mouse) or not action == "auto_sprite":
			return
		var rect := Auto.make_auto_sprite(mouse, image_size, image_data)
		if rect.get_area() == 0:
			return
		var uid := make_sprite_outline(rect.position, rect.size, str(name_counter))
		on_outlines_created([uid])
		current_being_created_uid = uid
		name_counter += 1
	elif not is_drawing and event is InputEventMouseMotion and Input.is_action_pressed("click") and Rect2(Vector2.ZERO, image_size).has_point(mouse):
		match action:
			"edit_sprites":
				is_drawing = true
				if not Input.is_action_pressed("shift"):
					for outline in image_node.get_children():
						if outline.is_in_group("sprite_outline") and outline.selected:
							outline.select(false)
				current_being_created_uid = make_sprite_outline(mouse, Vector2.ONE, str(name_counter), true)
				name_counter += 1
			"select_sprites":
				is_drawing = true
				var s := Selection.instance()
				image_node.add_child(s)
				s.resize(mouse, Vector2.ONE)
				s.preview_start = mouse
				if Input.is_action_pressed("shift"):
					return
				for outline in image_node.get_children():
					if outline.is_in_group("sprite_outline") and outline.selected:
						outline.select(false)


func combine_selected() -> void:
	var result: Rect2
	var to_delete := []
	for outline in image_node.get_children():
		if not outline.is_in_group("sprite_outline") or not outline.selected:
			continue
		var uid := Util.get_uid_from_object(outline, sprites)
		to_delete.append({
			"uid": uid,
			"rect": outline.get_rect(),
			"index": sprites[uid].index,
			"name": sprites[uid].name,
		})
		if result.get_area() == 0:
			result = outline.get_rect()
		else:
			result = result.merge(outline.get_rect())
	if to_delete.size() < 2:
		return
	to_delete.sort_custom(Util, "sort_by_index")
	for dict in to_delete:
		delete_outline(dict.uid)
	var result_uid := make_sprite_outline(result.position, result.size, str(name_counter))
	add_history({
		"action": "combine",
		"deleted": to_delete,
		"result": {
			"uid": result_uid,
			"rect": result,
			"index": sprites[result_uid].index,
			"name": str(name_counter)
		}
	})
	name_counter += 1


func cut(step: Vector2) -> void:
	var all_rects = []
	for y in range(0, image_size.y, step.y):
		for x in range(0, image_size.x, step.x):
			all_rects.append(Rect2(x, y, step.x, step.y))
	display_sprites(all_rects)


func move_all_selected_outlines() -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").snapped(Vector2.ONE)
	for outline in image_node.get_children():
		if outline.is_in_group("sprite_outline") and outline.selected:
			outline.rect_position += input
			
			
func _on_Tree_nothing_selected() -> void:
	var next: TreeItem = tree.get_next_selected(null)
	while next:
		next.deselect(0)
		next = tree.get_next_selected(null)


func _on_Tree_item_edited() -> void:
	var uid := Util.get_uid_from_object(tree.get_selected(), sprites)
	add_history({
		"action": "rename",
		"uid": uid,
		"old": sprites[uid].name,
		"new": tree.get_selected().get_text(0),
	})
	sprites[uid].name = tree.get_selected().get_text(0)


func _on_Image_resized() -> void:
	background.rect_size = image_node.rect_size


func _on_MoveTimer_timeout() -> void:
	if is_equal_approx($MoveTimer.wait_time, MOVE_TIME_0):
		$MoveTimer.wait_time = MOVE_TIME_1
	move_all_selected_outlines()
	$MoveTimer.start()
