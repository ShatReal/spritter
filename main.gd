extends Control


const SpriteOutline := preload("res://sprite_outline.tscn")
const Selection := preload("res://selection.tscn")
const ZOOM_INTERVALS := [1.0/8, 1.0/4, 1.0/2, 1.0, 2.0, 4.0, 8.0]
const MAX_HISTORY := 100

var distance_between_tiles := 0
var regions: Array
var region_threads: Array
var image: Image
var sub_region_count: int
var threads_finished: int
var all_boxes: Array
var mutex := Mutex.new()
var x_size: int
var y_size: int
var size: Vector2
var data: PoolByteArray
var zoom := 3
var is_drawing := false
var action := "edit_sprites"
var cam_lim: int
var history := []
var movement_temp: Array
var history_index := -1
var image_name: String
var tree_root: TreeItem
var sprites := {}
var counter := 0
var file_action: String
var save_path: String
var current_being_created_uid: int

onready var file_button := $"%FileButton"
onready var sprite_button := $"%SpriteButton"
onready var export_button := $"%ExportButton"
onready var background := $Layout/Main/VC/Viewport/Background
onready var image_node := $Layout/Main/VC/Viewport/Image
onready var cam := $Layout/Main/VC/Viewport/Camera2D
onready var vc := $Layout/Main/VC
onready var cut_rows := $Cut/VBox/Top/Rows
onready var cut_cols := $Cut/VBox/Top/Columns
onready var cut_y := $Cut/VBox/Bottom/YSize
onready var cut_x := $Cut/VBox/Bottom/XSize
onready var viewport := $Layout/Main/VC/Viewport
onready var tree := $Layout/Main/Tree


func _ready() -> void:
	randomize()
	$FileDialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	$Note.get_child(1).align = Label.ALIGN_CENTER
	if OS.get_processor_count() > 1:
		sub_region_count = 4
	else:
		sub_region_count = 2
	for child in $Layout/TopBar/Buttons.get_children():
		child.get_popup().connect("id_pressed", self, "on_menu_item_pressed", [child.name])
	tree_root = tree.create_item()
	close_image()
	for child in $Layout/Main/Sidebar.get_children():
		child.connect("pressed", self, "on_sidebar_button_pressed", [child.get_index()])
	for node in [cut_rows, cut_cols, cut_y, cut_x]:
		node.connect("value_changed", self, "recalc_cut", [node.name])


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
			viewport.gui_disable_input = true
			$FileDialog.mode = FileDialog.MODE_SAVE_FILE
			$FileDialog.filters = PoolStringArray(["*.spritter"])
			file_action = "save"
			$FileDialog.popup()
	elif event.is_action_pressed("edit_sprites"):
		action = "edit_sprites"
		$Layout/Main/Sidebar/EditSprites.pressed = true
	elif event.is_action_pressed("select_sprites"):
		action = "select_sprites"
		$Layout/Main/Sidebar/SelectSprites.pressed = true
	elif event.is_action_pressed("delete"):
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
					"rect": outline.get_global_rect(),
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
	elif event.is_action_pressed("select_all"):
		for node in get_tree().get_nodes_in_group("sprite_outline"):
			node.select(true)
	elif event.is_action_pressed("zoom_in") and image_node.texture:
		zoom -= 1
		if zoom < 0:
			zoom = 0
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += (get_viewport().size / 2 - get_global_mouse_position()) * (ZOOM_INTERVALS[zoom] - ZOOM_INTERVALS[zoom + 1])
		$Layout/BottomBar/HBox/Zoom.text = "%s%%" % (1 / ZOOM_INTERVALS[zoom] * 100)
	elif event.is_action_pressed("zoom_out") and image_node.texture:
		zoom += 1
		if zoom > ZOOM_INTERVALS.size() - 1:
			zoom = ZOOM_INTERVALS.size() - 1
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += (get_viewport().size / 2 - get_global_mouse_position()) * (ZOOM_INTERVALS[zoom] - ZOOM_INTERVALS[zoom - 1])
		$Layout/BottomBar/HBox/Zoom.text = "%s%%" % (1 / ZOOM_INTERVALS[zoom] * 100)
	elif (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) and not Input.is_action_pressed("ui_down") and not Input.is_action_pressed("ui_left") and not Input.is_action_pressed("ui_right"):
		start_movement()
	elif (event.is_action_released("ui_up") or event.is_action_released("ui_down") or event.is_action_released("ui_left") or event.is_action_released("ui_right")) and not Input.is_action_pressed("ui_down") and not Input.is_action_pressed("ui_left") and not Input.is_action_pressed("ui_right"):
		end_movement()
	elif event.is_action_pressed("redo"):
		history_index += 1
		if history.size() == history_index:
			history_index = history.size() - 1
			return
		var a: Dictionary = history[history_index]
		match a.action:
			"move":
				for dict in a.ends:
					sprites[dict.uid].outline.rect_global_position = dict.pos
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
	elif event.is_action_pressed("undo"):
		if history_index == -1:
			return
		var a: Dictionary = history[history_index]
		match a.action:
			"move":
				for dict in a.starts:
					sprites[dict.uid].outline.rect_global_position = dict.pos
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
	elif event.is_action_pressed("auto_sprite"):
		action = "auto_sprite"
		$Layout/Main/Sidebar/AutoSprite.pressed = true


func delete_outline(uid) -> void:
	sprites[uid].outline.queue_free()
	tree_root.remove_child(sprites[uid].tree_item)
	sprites[uid].tree_item.free()
	sprites.erase(uid)


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


func make_sprite_outline(global_pos: Vector2, outline_size: Vector2, n: String, is_preview := false, uid := -1, index := -1) -> int:
	var outline := SpriteOutline.instance()
	image_node.add_child(outline)
	outline.parent_global_rect = Rect2(image_node.rect_global_position, size)
	outline.resize(global_pos, outline_size)
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
		outline.preview_start = global_pos
		outline.set_preview(true)
	outline.select(true)
	return uid


func on_outline_resized(original_rect: Rect2, new_rect: Rect2, outline: Button) -> void:
	add_history({
		"action": "resized",
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
				"rect": sprites[uid].outline.get_global_rect(),
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
				"pos": outline.rect_global_position,
			})


func end_movement() -> void:
	if movement_temp.size() == 0:
		return
	var ends := []
	for dict in movement_temp:
		ends.append({
			"uid": dict.uid,
			"pos": sprites[dict.uid].outline.rect_global_position,
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
	size = image.get_size()
	data = image.get_data()
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
	image_node.rect_position = -size / 2
	background.rect_position = -size / 2
	cut_y.max_value = size.y
	cut_x.max_value = size.x
	recalc_cut(cut_rows.value, "Rows")
	recalc_cut(cut_cols.value, "Columns")
	cam_lim = max(size.y, size.x)
	tree_root.set_text(0, image_name)


func set_image_name(path: String) -> void:
	var arr := path.get_file().split(".")
	arr.remove(arr.size() -1)
	image_name = arr.join(".")


func separate() -> void:
	$Layout/ProgressBar.value = 0
	all_boxes = []
	y_size = ceil(float(image.get_height()) / sub_region_count)
	x_size = ceil(float(image.get_width()) / sub_region_count)
	regions = []
	region_threads = []
	threads_finished = 0
	for y in range(0, image.get_height(), y_size):
		for x in range(0, image.get_width(), x_size):
			var region := Rect2(x, y, min(x_size + 1, image.get_width() - x), min(y_size + 1, image.get_height() - y))
			var thread := Thread.new()
			region_threads.append(thread)
			regions.append(region)
	for i in region_threads.size():
		region_threads[i].start(self, "flood_region", i)


func flood_region(i: int) -> Array:
	var not_alpha := {}
	var rects := []
	for y in range(regions[i].position.y, regions[i].end.y):
		for x in range(regions[i].position.x, regions[i].end.x):
			var a: int = data[x * 4 + y * size.x * 4 + 3]
			if a != 0:
				not_alpha[Vector2(x, y)] = a
	while not not_alpha.empty():
		rects.append(find_extents(not_alpha.keys()[0], not_alpha))
	call_deferred("thread_done", i)
	return rects


func find_extents(p: Vector2, not_alpha: Dictionary) -> Rect2:
	var r := Rect2(p - Vector2.ONE, Vector2.ONE * 2)
	while not is_rect_clear(r, not_alpha):
		r = grow_rect(r, not_alpha)
	r = Rect2(r.position + Vector2.ONE, r.size - Vector2.ONE)
	for key in not_alpha.keys():
		if r.has_point(key):
			not_alpha.erase(key)
	return r


func is_rect_clear(r: Rect2, not_alpha: Dictionary) -> bool:
	for x in r.size.x:
		if top_row(r, x, not_alpha) or bot_row(r, x, not_alpha):
			return false
	for y in r.size.y:
		if lef_col(r, y, not_alpha) or rig_col(r, y, not_alpha):
			return false
	return true


func grow_rect(r: Rect2, not_alpha: Dictionary) -> Rect2:
	for x in r.size.x:
		while top_row(r, x, not_alpha):
			r = Rect2(r.position + Vector2.UP, r.size + Vector2.DOWN)
		while bot_row(r, x, not_alpha):
			r = Rect2(r.position, r.size + Vector2.DOWN)
	for y in r.size.y:
		while lef_col(r, y, not_alpha):
			r = Rect2(r.position + Vector2.LEFT, r.size + Vector2.RIGHT)
		while rig_col(r, y, not_alpha):
			r = Rect2(r.position, r.size + Vector2.RIGHT)
	return r


func top_row(r: Rect2, x: int, not_alpha: Dictionary) -> bool:
	return not_alpha.has(Vector2(r.position.x + x, r.position.y))


func bot_row(r: Rect2, x: int, not_alpha: Dictionary) -> bool:
	return not_alpha.has(Vector2(r.position.x + x, r.end.y))


func lef_col(r: Rect2, y: int, not_alpha: Dictionary) -> bool:
	return not_alpha.has(Vector2(r.position.x, r.position.y + y))
	

func rig_col(r: Rect2, y: int, not_alpha: Dictionary) -> bool:
	return not_alpha.has(Vector2(r.end.x, r.position.y + y))
	
	
func thread_done(i: int) -> void:
	all_boxes.append_array(region_threads[i].wait_to_finish())
	threads_finished += 1
	$Layout/ProgressBar.value += $Layout/ProgressBar.max_value / region_threads.size()
	if threads_finished == region_threads.size():
		combine_boxes()
		display_sprites()


func combine_boxes() -> void:
	var i := all_boxes.size() - 1
	while i != -1:
		var has_merged := false
		for j in range(i - 1, -1, -1):
			if all_boxes[i].intersects(all_boxes[j], true):
				all_boxes[i] = all_boxes[i].merge(all_boxes[j])
				all_boxes.remove(j)
				has_merged = true
				i -= 1
		if not has_merged:
			i -= 1
		else:
			for j in range(i - 1, -1, -1):
				if all_boxes[i].intersects(all_boxes[j], true):
					all_boxes[i] = all_boxes[i].merge(all_boxes[j])
					all_boxes.remove(j)
					has_merged = true
					i -= 1
			if not has_merged:
				i -= 1


func display_sprites() -> void:
	var uids := []
	for rect in all_boxes:
		uids.append(make_sprite_outline(rect.position + image_node.rect_global_position, rect.size, str(counter)))
		counter += 1
	on_outlines_created(uids)


func on_outline_selected(on: bool, outline: Button) -> void:
	for uid in sprites:
		if sprites[uid].outline == outline:
			if on:
				sprites[uid].tree_item.select(0)
			else:
				sprites[uid].tree_item.deselect(0)
			return


func _exit_tree() -> void:
	for thread in region_threads:
		if thread.is_active():
			thread.wait_to_finish()


func _on_FileDialog_dir_selected(dir: String) -> void:
	var directory := Directory.new()
	if not directory.dir_exists(dir + "/%s" % image_name):
		directory.make_dir(dir + "/%s" % image_name)
	for child in image_node.get_children():
		image.get_rect(child.get_rect()).save_png(dir + "/%s/%s.png" % [image_name, child.get_index()])


func outside_sprite_gui_input(event: InputEvent) -> void:
	if not image_node.texture:
		return
	var mouse: Vector2 = image_node.get_global_mouse_position().snapped(Vector2.ONE)
	if not Input.is_action_pressed("move") and event.is_action_released("click"):
		is_drawing = false
		if Input.is_action_pressed("shift"):
			return
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected:
				if button.is_preview:
					button.set_preview(false)
					on_outlines_created([current_being_created_uid])
				else:
					button.select(false)
		if action == "auto_sprite":
			sprites[current_being_created_uid].outline.select(true)
	elif not Input.is_action_pressed("move") and event.is_action_pressed("click") and image_node.get_global_rect().has_point(mouse) and action == "auto_sprite":
		var coords: Vector2 = image_node.get_local_mouse_position().snapped(Vector2.ONE)
		if data[coords.x * 4 + coords.y * size.x * 4 + 3] == 0.0:
			return
		var rect := Rect2(coords - Vector2.ONE, Vector2.ONE * 2)
		while not auto_is_rect_clear(rect):
			rect = auto_grow_rect(rect)
		rect = Rect2(rect.position + Vector2.ONE, rect.size - Vector2.ONE)
		var uid := make_sprite_outline(rect.position + image_node.rect_global_position, rect.size, str(counter))
		on_outlines_created([uid])
		current_being_created_uid = uid
		counter += 1
	elif not Input.is_action_pressed("move") and not is_drawing and event is InputEventMouseMotion and Input.is_action_pressed("click") and image_node.get_global_rect().has_point(mouse):
		match action:
			"edit_sprites":
				is_drawing = true
				for button in get_tree().get_nodes_in_group("sprite_outline"):
					if button.selected:
						button.select(false)
				current_being_created_uid = make_sprite_outline(mouse, Vector2.ONE, str(counter), true)
				counter += 1
			"select_sprites":
				is_drawing = true
				var s := Selection.instance()
				image_node.add_child(s)
				s.parent_global_rect = Rect2(image_node.rect_global_position, size)
				s.resize(mouse, Vector2.ONE)
				s.preview_start = mouse
				if Input.is_action_pressed("shift"):
					return
				for button in get_tree().get_nodes_in_group("sprite_outline"):
					if button.selected:
						button.select(false)
	elif Input.is_action_pressed("move") and event is InputEventMouseMotion:
		cam.position -= event.relative
		cam.position = cam.position.limit_length(cam_lim)
	elif event.is_action_pressed("zoom_in"):
		zoom -= 1
		if zoom < 0:
			zoom = 0
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += (get_viewport().size / 2 - get_global_mouse_position()) * (ZOOM_INTERVALS[zoom] - ZOOM_INTERVALS[zoom + 1])
		$Layout/BottomBar/HBox/Zoom.text = "%s%%" % (1 / ZOOM_INTERVALS[zoom] * 100)
	elif event.is_action_pressed("zoom_out"):
		zoom += 1
		if zoom > ZOOM_INTERVALS.size() - 1:
			zoom = ZOOM_INTERVALS.size() - 1
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += (get_viewport().size / 2 - get_global_mouse_position()) * (ZOOM_INTERVALS[zoom] - ZOOM_INTERVALS[zoom - 1])
		$Layout/BottomBar/HBox/Zoom.text = "%s%%" % (1 / ZOOM_INTERVALS[zoom] * 100)


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


func on_menu_item_pressed(id: int, group: String) -> void:
	match group:
		"FileButton":
			match id:
				0:
					viewport.gui_disable_input = true
					$FileDialog.mode = FileDialog.MODE_OPEN_FILE
					file_action = "open"
					$FileDialog.filters = PoolStringArray(["*.png"])
					$FileDialog.popup()
				1:
					close_image()
				2:
					viewport.gui_disable_input = true
					$FileDialog.mode = FileDialog.MODE_SAVE_FILE
					$FileDialog.filters = PoolStringArray(["*.spritter"])
					file_action = "save"
					$FileDialog.popup()
				3:
					viewport.gui_disable_input = true
					$FileDialog.mode = FileDialog.MODE_OPEN_FILE
					$FileDialog.filters = PoolStringArray(["*.spritter"])
					file_action = "load"
					$FileDialog.popup()
		"SpriteButton":
			match id:
				0:
					viewport.gui_disable_input = true
					$Cut.popup()
				1:
					separate()
		"ExportButton":
			match id:
				0:
					viewport.gui_disable_input = true
					$FileDialog.mode = FileDialog.MODE_OPEN_DIR
					$FileDialog.popup()
		"HelpButton":
			match id:
				0:
					viewport.gui_disable_input = true
					$Help.popup()
				1:
					viewport.gui_disable_input = true
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
	all_boxes = []
	for y in range(0, size.y, cut_y.value):
		for x in range(0, size.x, cut_x.value):
			all_boxes.append(Rect2(x, y, cut_x.value, cut_y.value))
	display_sprites()


func recalc_cut(value: float, node: String) -> void:
	match node:
		"Rows":
			cut_y.value = int(size.y / value)
		"Columns":
			cut_x.value = int(size.x / value)
		"YSize":
			cut_rows.value = int(size.y / value)
		"XSize":
			cut_cols.value = int(size.x / value)


func on_popup_hide() -> void:
	viewport.gui_disable_input = false


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
			"rect": sprites[uid].outline.get_global_rect(),
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
	viewport.gui_disable_input = true
	$Note.dialog_text = message
	$Note.popup()


func auto_is_rect_clear(r: Rect2) -> bool:
	for x in r.size.x:
		if auto_top_row(r, x) or auto_bot_row(r, x):
			return false
	for y in r.size.y:
		if auto_lef_col(r, y) or auto_rig_col(r, y):
			return false
	return true


func auto_grow_rect(r: Rect2) -> Rect2:
	for x in r.size.x:
		while auto_top_row(r, x):
			r = Rect2(r.position + Vector2.UP, r.size + Vector2.DOWN)
		while auto_bot_row(r, x):
			r = Rect2(r.position, r.size + Vector2.DOWN)
	for y in r.size.y:
		while auto_lef_col(r, y):
			r = Rect2(r.position + Vector2.LEFT, r.size + Vector2.RIGHT)
		while auto_rig_col(r, y):
			r = Rect2(r.position, r.size + Vector2.RIGHT)
	return r


func auto_top_row(r: Rect2, x: int) -> bool:
	return data[(r.position.x + x + r.position.y * size.x) * 4 + 3] != 0.0


func auto_bot_row(r: Rect2, x: int) -> bool:
	return data[(r.position.x + x + r.end.y * size.x) * 4 + 3] != 0.0


func auto_lef_col(r: Rect2, y: int) -> bool:
	return data[(r.position.x + (r.position.y + y) * size.x) * 4 + 3] != 0.0
	

func auto_rig_col(r: Rect2, y: int) -> bool:
	return data[(r.end.x + (r.position.y + y) * size.x) * 4 + 3] != 0.0


func _on_Tree_item_edited() -> void:
	var uid := get_uid_from_object(tree.get_selected())
	add_history({
		"action": "rename",
		"uid": uid,
		"old": sprites[uid].name,
		"new": tree.get_selected().get_text(0),
	})
	sprites[uid].name = tree.get_selected().get_text(0)
