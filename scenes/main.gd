extends Control


const SpriteOutline := preload("res://scenes/sprite_outline.tscn")
const Selection := preload("res://scenes/selection.tscn")

const ZOOM_INTERVALS := [1.0/8, 1.0/4, 1.0/2, 1.0, 2.0, 4.0, 8.0]
const MAX_HISTORY := 100
const SCROLL_SPEED := 20
const MOVE_TIME_0 := 0.2
const MOVE_TIME_1 := 0.1


var image: Image
var image_size: Vector2
var image_data: PoolByteArray
var image_name: String
var save_path: String

var history := []
var history_index := -1

var tree_root: TreeItem

var action := "edit_sprites"
var file_action: String

var sprites := {}
var current_being_created_uid := -1

var zoom_counter := 3
var name_counter := 0
var is_drawing := false

var movement_temp: Array


onready var top_buttons := $Layout/TopBar/Buttons
onready var file_button := $"%FileButton"
onready var sprite_button := $"%SpriteButton"
onready var export_button := $"%ExportButton"

onready var tree := $Layout/Main/Tree

onready var scroll := $Layout/Main/Scroll
onready var background := $Layout/Main/Scroll/Images/Background
onready var images_node := $Layout/Main/Scroll/Images
onready var image_node := $Layout/Main/Scroll/Images/Image

onready var sidebar := $Layout/Main/Sidebar
onready var edit_sprites := $Layout/Main/Sidebar/EditSprites
onready var select_sprites := $Layout/Main/Sidebar/SelectSprites
onready var auto_sprite := $Layout/Main/Sidebar/AutoSprite

onready var zoom_label := $Layout/BottomBar/HBox/Zoom
onready var mouse_pos_label := $Layout/BottomBar/HBox/MousePos

onready var progress_bar := $Layout/ProgressBar

onready var file_dialog := $FileDialog
onready var note := $Note

onready var cut_rows := $Cut/VBox/Top/Rows
onready var cut_cols := $Cut/VBox/Top/Columns
onready var cut_y := $Cut/VBox/Bottom/YSize
onready var cut_x := $Cut/VBox/Bottom/XSize


func _ready() -> void:
	randomize()
	
	Detect.connect("region_thread_finished", self, "on_region_thread_finished")
	Detect.connect("detecting_finished", self, "display_sprites")
	
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	for child in file_dialog.get_children():
		if child is WindowDialog:
			child.get_child(1).align = Label.ALIGN_CENTER
	note.get_child(1).align = Label.ALIGN_CENTER
	
	for child in top_buttons.get_children():
		child.get_popup().connect("id_pressed", self, "on_menu_item_pressed", [child.name])
	tree_root = tree.create_item()
	for child in sidebar.get_children():
		child.connect("pressed", self, "on_sidebar_button_pressed", [child.get_index()])
	for node in [cut_rows, cut_cols, cut_y, cut_x]:
		node.connect("value_changed", self, "recalc_cut", [node.name])
	
	close_image()


func on_region_thread_finished(num_threads: int) -> void:
	progress_bar.value += progress_bar.max_value / num_threads


func get_uid_from_object(object) -> int:
	for uid in sprites:
		if object is Button and sprites[uid].outline == object:
			return uid
		elif object is TreeItem and sprites[uid].tree_item == object:
			return uid
	return -1 # Could not find uid


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save") and image_node.texture:
		if save_path:
			save_sheet(save_path)
		else:
			file_dialog.mode = FileDialog.MODE_SAVE_FILE
			file_dialog.filters = PoolStringArray(["*.spritter"])
			file_action = "save"
			file_dialog.popup()
	elif event.is_action_pressed("select_all"):
		for node in get_tree().get_nodes_in_group("sprite_outline"):
			node.select(true)
	elif event.is_action_pressed("delete"):
		delete_outlines()
	elif event.is_action_pressed("edit_sprites"):
		action = "edit_sprites"
		edit_sprites.pressed = true
	elif event.is_action_pressed("select_sprites"):
		action = "select_sprites"
		select_sprites.pressed = true
	elif event.is_action_pressed("auto_sprite"):
		action = "auto_sprite"
		$Layout/Main/Sidebar/AutoSprite.pressed = true
	elif event.is_action_pressed("zoom_in") and image_node.texture:
		zoom(1)
	elif event.is_action_pressed("zoom_out") and image_node.texture:
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
	history_index -= 1


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
	zoom_label.text = "%s%%" % (ZOOM_INTERVALS[zoom_counter] * 100)
	images_node.rect_min_size = image_node.rect_scale * image_size * 2
	var max_vector := get_max_vector2(image_size * ZOOM_INTERVALS[zoom_counter], scroll.rect_size)
	background.rect_position = max_vector / 2 - image_size * ZOOM_INTERVALS[zoom_counter] / 2
	image_node.rect_position = max_vector / 2 - image_size * ZOOM_INTERVALS[zoom_counter] / 2


func get_max_vector2(vec1: Vector2, vec2: Vector2) -> Vector2:
	return Vector2(
		max(vec1.x, vec2.x),
		max(vec1.y, vec2.y)
	)


func delete_outline(uid) -> void:
	sprites[uid].outline.queue_free()
	tree_root.remove_child(sprites[uid].tree_item)
	sprites[uid].tree_item.free()
	sprites.erase(uid)


func delete_outlines() -> void:
	if tree_root.is_selected(0):
		close_image()
		return
	var dict := {
		"action": "delete",
		"outlines": [],
	}
	var tree_items_to_free := []
	for outline in get_tree().get_nodes_in_group("sprite_outline"):
		if outline.selected:
			var uid := get_uid_from_object(outline)
			dict.outlines.append({
				"rect": outline.get_rect(),
				"name": sprites[uid].tree_item.get_text(0),
				"uid": uid,
				"index": get_outline_index(sprites[uid].tree_item),
			})
			tree_items_to_free.append(sprites[uid].tree_item)
			sprites.erase(uid)
			outline.queue_free()
	for tree_item in tree_items_to_free:
		tree_root.remove_child(tree_item)
		tree_item.free()
	dict.outlines.sort_custom(self, "sort_by_index")
	add_history(dict)


func sort_by_index(a: Dictionary, b: Dictionary) -> bool:
	return a.index < b.index


func get_outline_index(tree_item: TreeItem) -> int:
	var index := 0
	var ti: TreeItem = tree_root.get_children()
	while ti:
		if ti == tree_item:
			break
		ti = ti.get_next()
		index += 1
	return index


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
	}
	if is_preview:
		outline.preview_start = pos
		outline.set_preview(true)
	outline.select(true)
	return uid


func on_outline_resized(original_rect: Rect2, new_rect: Rect2, outline: Button) -> void:
	add_history({
		"action": "resize",
		"original_rect": original_rect,
		"new_rect": new_rect,
		"uid": get_uid_from_object(outline),
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
				"index": get_outline_index(sprites[uid].tree_item),
			}
		)
	dict.outlines.sort_custom(self, "sort_by_index")
	add_history(dict)


func start_movement() -> void:
	movement_temp = []
	for outline in get_tree().get_nodes_in_group("sprite_outline"):
		if outline.selected:
			movement_temp.append({
				"uid": get_uid_from_object(outline),
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


func add_history(dict: Dictionary) -> void:
	while history.size() > history_index + 1:
		history.pop_back()
	history_index += 1
	history.append(dict)
	if history.size() == MAX_HISTORY:
		history.pop_front()
		history_index -= 1


func _on_FileDialog_file_selected(path: String) -> void:
	match file_action:
		"open":
			load_image(path)
		"save":
			save_path = path
			save_sheet(path)
		"load":
			load_sheet(path)


func load_image(path, d = null) -> void:
	if not d:
		image = Image.new()
		if image.load(path) != OK:
			$Note.dialog_text = "Error loading image!"
			$Note.popup()
			return
	else:
		image = d
	close_image()
	set_image_name(path)
	image_size = image.get_size()
	image_data = image.get_data()
	for i in sprite_button.get_popup().get_item_count():
		sprite_button.get_popup().set_item_disabled(i, false)
	for i in export_button.get_popup().get_item_count():
		export_button.get_popup().set_item_disabled(i, false)
	file_button.get_popup().set_item_disabled(1, false)
	file_button.get_popup().set_item_disabled(2, false)
	var text := ImageTexture.new()
	text.create_from_image(image, 0)
	image_node.texture = text
	background.show()
	cut_y.max_value = image_size.y
	cut_x.max_value = image_size.x
	recalc_cut(cut_rows.value, "Rows")
	recalc_cut(cut_cols.value, "Columns")
	tree_root.set_text(0, image_name)
	zoom(0)
	tree.hide_root = false


func set_image_name(path: String) -> void:
	var arr := path.get_file().split(".")
	arr.remove(arr.size() -1)
	image_name = arr.join(".")


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


func _on_FileDialog_dir_selected(dir: String) -> void:
	var directory := Directory.new()
	if not directory.dir_exists(dir + "/%s" % image_name):
		directory.make_dir(dir + "/%s" % image_name)
	for child in image_node.get_children():
		image.get_rect(child.get_rect()).save_png(dir + "/%s/%s.png" % [image_name, child.get_index()])


func outside_sprite_gui_input(event: InputEvent) -> void:
	if not image_node.texture:
		return
	var mouse: Vector2 = image_node.get_local_mouse_position().snapped(Vector2.ONE)
	if not Input.is_action_pressed("move") and event.is_action_released("click"):
		is_drawing = false
		if Input.is_action_pressed("shift"):
			return
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected:
				if button.is_preview:
					button.set_preview(false)
					on_outlines_created([current_being_created_uid])
					current_being_created_uid = -1
				else:
					button.select(false)
		if action == "auto_sprite" and current_being_created_uid != -1:
			sprites[current_being_created_uid].outline.select(true)
			current_being_created_uid = -1
	elif not Input.is_action_pressed("move") and event.is_action_pressed("click") and is_mouse_inside_image() and action == "auto_sprite":
		var rect := Auto.make_auto_sprite(mouse, image_size, image_data)
		if rect.get_area() == 0:
			return
		var uid := make_sprite_outline(rect.position, rect.size, str(name_counter))
		on_outlines_created([uid])
		current_being_created_uid = uid
		name_counter += 1
	elif not Input.is_action_pressed("move") and not is_drawing and event is InputEventMouseMotion and Input.is_action_pressed("click") and is_mouse_inside_image():
		match action:
			"edit_sprites":
				is_drawing = true
				for button in get_tree().get_nodes_in_group("sprite_outline"):
					if button.selected:
						button.select(false)
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
				for button in get_tree().get_nodes_in_group("sprite_outline"):
					if button.selected:
						button.select(false)
	elif Input.is_action_pressed("move") and event is InputEventMouseMotion:
		scroll.scroll_horizontal -= event.relative.x / get_viewport().size.x * scroll.get_h_scrollbar().max_value * SCROLL_SPEED / ZOOM_INTERVALS[zoom_counter]
		scroll.scroll_vertical -= event.relative.y / get_viewport().size.y * scroll.get_v_scrollbar().max_value * SCROLL_SPEED / ZOOM_INTERVALS[zoom_counter]
	elif event.is_action_pressed("zoom_in"):
		zoom(1)
	elif event.is_action_pressed("zoom_out"):
		zoom(-1)


func is_mouse_inside_image() -> bool:
	return image_node.rect_size.x > image_node.get_local_mouse_position().x and image_node.rect_size.y > image_node.get_local_mouse_position().y


func _on_TextureRect_resized() -> void:
	background.rect_size = image_node.rect_size


func _on_Label_meta_clicked(meta) -> void:
	OS.shell_open(meta)


func close_image() -> void:
	background.hide()
	for i in sprite_button.get_popup().get_item_count():
		sprite_button.get_popup().set_item_disabled(i, true)
	for i in export_button.get_popup().get_item_count():
		export_button.get_popup().set_item_disabled(i, true)
	file_button.get_popup().set_item_disabled(1, true)
	file_button.get_popup().set_item_disabled(2, true)
	for child in image_node.get_children():
		child.queue_free()
	image_node.texture = null
	tree_root.set_text(0, "")
	var child := tree_root.get_children()
	while child:
		tree_root.remove_child(child)
		child.free()
		child = tree_root.get_children()
	sprites = {}
	history = []
	history_index = -1
	save_path = ""
	tree.hide_root = true


func on_menu_item_pressed(id: int, group: String) -> void:
	match group:
		"FileButton":
			match id:
				0:
					file_dialog.mode = FileDialog.MODE_OPEN_FILE
					file_action = "open"
					file_dialog.filters = PoolStringArray(["*.png"])
					file_dialog.popup()
				1:
					close_image()
				2:
					file_dialog.mode = FileDialog.MODE_SAVE_FILE
					file_dialog.filters = PoolStringArray(["*.spritter"])
					file_action = "save"
					file_dialog.popup()
				3:
					file_dialog.mode = FileDialog.MODE_OPEN_FILE
					file_dialog.filters = PoolStringArray(["*.spritter"])
					file_action = "load"
					file_dialog.popup()
		"SpriteButton":
			match id:
				0:
					$Cut.popup()
				1:
					$Layout/ProgressBar.value = 0
					Detect.detect(image_size, image_data)
		"ExportButton":
			match id:
				0:
					file_dialog.mode = FileDialog.MODE_OPEN_DIR
					file_dialog.popup()
		"HelpButton":
			match id:
				0:
					$Help.popup()
				1:
					$Credits.popup()


func on_sidebar_button_pressed(i: int) -> void:
	match i:
		0:
			action = "edit_sprites"
		1:
			action = "select_sprites"
		2:
			action = "auto_sprite"


func _on_CutOk_pressed() -> void:
	$Cut.hide()
	var all_rects = []
	for y in range(0, image_size.y, cut_y.value):
		for x in range(0, image_size.x, cut_x.value):
			all_rects.append(Rect2(x, y, cut_x.value, cut_y.value))
	display_sprites(all_rects)


func recalc_cut(value: float, node: String) -> void:
	match node:
		"Rows":
			cut_y.value = int(image_size.y / value)
		"Columns":
			cut_x.value = int(image_size.x / value)
		"YSize":
			cut_rows.value = int(image_size.y / value)
		"XSize":
			cut_cols.value = int(image_size.x / value)


func _on_Tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if item == tree_root and selected:
		for outline in get_tree().get_nodes_in_group("sprite_outline"):
			outline.select(false)
		return
	for uid in sprites:
		if sprites[uid].tree_item == item:
			sprites[uid].outline.select(selected)
			return


func _on_Tree_nothing_selected() -> void:
	var next: TreeItem = tree.get_next_selected(null)
	while next:
		next.deselect(0)
		next = tree.get_next_selected(null)
		
		
func _process(_delta: float) -> void:
	var mouse: Vector2 = image_node.get_local_mouse_position().snapped(Vector2.ONE)
	$Layout/BottomBar/HBox/MousePos.text = "(%s, %s)" % [mouse.x, mouse.y]


func save_sheet(path: String) -> void:
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
			"index": get_outline_index(sprites[uid].tree_item),
		})
	array.sort_custom(self, "sort_by_index")
	f.store_var(array)
	f.close()


func load_sheet(path: String) -> void:
	var f := File.new()
	f.open(path, File.READ)
	if f.get_len() == 0 and not f.get_var() == "Spritter":
		show_note("Error opening file!")
		f.close()
		return
	var spritter = f.get_var()
	var d = f.get_var(true)
	var sprite_data = f.get_var()
	f.close()
	if not spritter == "Spritter":
		show_note("Error opening file!")
		return
	if not d is Image:
		show_note("Error opening file!")
		return
	if not sprite_data is Array:
		show_note("Error opening file!")
		return
	for sprite in sprite_data:
		if not sprite is Dictionary or not sprite.has_all(["uid", "rect", "name", "index"]) or not sprite.uid is int or not sprite.rect is Rect2 or not sprite.name is String or not sprite.index is int:
			show_note("Error opening file!")
			return
	load_image(path, d)
	var uids := []
	for sprite in sprite_data:
		uids.append(make_sprite_outline(sprite.rect.position, sprite.rect.size, sprite.name, false, sprite.uid, sprite.index))
	on_outlines_created(uids)
	save_path = path

func show_note(message: String) -> void:
	$Note.dialog_text = message
	$Note.popup()


func _on_Tree_item_edited() -> void:
	var uid := get_uid_from_object(tree.get_selected())
	add_history({
		"action": "rename",
		"uid": uid,
		"old": sprites[uid].name,
		"new": tree.get_selected().get_text(0),
	})
	sprites[uid].name = tree.get_selected().get_text(0)


func move_all_selected_outlines() -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").snapped(Vector2.ONE)
	for outline in get_tree().get_nodes_in_group("sprite_outline"):
		if outline.selected:
			outline.rect_position += input


func _on_MoveTimer_timeout() -> void:
	if is_equal_approx($MoveTimer.wait_time, MOVE_TIME_0):
		$MoveTimer.wait_time = MOVE_TIME_1
	move_all_selected_outlines()
	$MoveTimer.start()
