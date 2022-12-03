extends Control


const SpriteOutline := preload("res://sprite_outline.tscn")
const Selection := preload("res://selection.tscn")
const ZOOM_INTERVALS := [0.1, 0.25, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0, 8.0]
const CAM_LIM := 1_000

var action := ""
var path := ""
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
var zoom := 4
var is_drawing := false

onready var sep := $Layout/HBoxContainer/Separate
onready var xport := $Layout/HBoxContainer/Export
onready var texture := $Layout/VC/Viewport/TextureRect
onready var cam := $Layout/VC/Viewport/Camera2D
onready var vc := $Layout/VC
onready var transparent := $Layout/VC/Viewport/Transparent


func _ready() -> void:
	$FileDialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	$Note.get_child(1).align = Label.ALIGN_CENTER
	if OS.get_processor_count() > 1:
		sub_region_count = 4
	else:
		sub_region_count = 2


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("delete"):
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected:
				button.queue_free()
	elif event.is_action_pressed("zoom_in") and texture.texture:
		zoom -= 1
		if zoom < 0:
			zoom = 0
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += cam.get_local_mouse_position() * cam.zoom
	elif event.is_action_pressed("zoom_out") and texture.texture:
		zoom += 1
		if zoom > ZOOM_INTERVALS.size() - 1:
			zoom = ZOOM_INTERVALS.size() - 1
			return
		cam.zoom = Vector2(ZOOM_INTERVALS[zoom], ZOOM_INTERVALS[zoom])
		cam.position += cam.get_local_mouse_position() * cam.zoom


func _on_Separate_pressed() -> void:
	action = "separate"
	$FileDialog.mode = FileDialog.MODE_OPEN_FILE
	$FileDialog.popup()


func _on_FileDialog_file_selected(file_path: String) -> void:
	path = file_path
	image = Image.new()
	if image.load(file_path) != OK:
		$Note.dialog_text = "Error loading image!"
		$Note.popup()
		return
	match action:
		"separate":
			separate()


func separate() -> void:
	transparent.hide()
	xport.disabled = true
	sep.disabled = true
	for child in texture.get_children():
		child.queue_free()
	texture.texture = null
	$Layout/ProgressBar.value = 0
	all_boxes = []
	y_size = ceil(float(image.get_height()) / sub_region_count)
	x_size = ceil(float(image.get_width()) / sub_region_count)
	regions = []
	region_threads = []
	threads_finished = 0
	size = image.get_size()
	data = image.get_data()
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
	var image_dict = {}
	for y in [regions[i].position.y - 1, regions[i].end.y]:
		for x in [regions[i].position.x - 1, regions[i].end.x]:
			image_dict[Vector2(x, y)] = 0
	for y in range(regions[i].position.y, regions[i].end.y):
		image_dict[Vector2(regions[i].position.x - 1, y)] = 0
		image_dict[Vector2(regions[i].end.x, y)] = 0
		for x in range(regions[i].position.x, regions[i].end.x):
			var a := data[x * 4 + y * size.x * 4 + 3]
			image_dict[Vector2(x, y)] = a
			image_dict[Vector2(x, regions[i].position.y - 1)] = 0
			image_dict[Vector2(x, regions[i].end.y)] = 0
			if a != 0:
				not_alpha[Vector2(x, y)] = a
	while not not_alpha.empty():
		var pixel: Vector2 = not_alpha.keys()[0]
		not_alpha.erase(pixel)
		var rect := Rect2(pixel, Vector2.ONE)
		var is_clear := false
		while not is_clear:
			rect = grow_rect(rect, image_dict)
			is_clear = clear(rect, not_alpha, image_dict)
		rect = Rect2(rect.position + Vector2.ONE, rect.size - Vector2.ONE)
		rects.append(rect)
	call_deferred("thread_done", i)
	return rects


func clear(rect: Rect2, not_alpha: Dictionary, image_dict: Dictionary) -> bool:
	var result := true
	for x in range(rect.position.x, rect.end.x):
		if image_dict[Vector2(x, rect.position.y)] != 0:
			not_alpha.erase(Vector2(x, rect.position.y))
			result = false
		if image_dict[Vector2(x, rect.end.y)] != 0:
			not_alpha.erase(Vector2(x, rect.end.y))
			result = false
	for y in range(rect.position.y, rect.end.y):
		if image_dict[Vector2(rect.position.x, y)] != 0:
			not_alpha.erase(Vector2(rect.position.x, y))
			result = false
		if image_dict[Vector2(rect.end.x, y)] != 0:
			not_alpha.erase(Vector2(rect.end.x, y))
			result = false
	return result


func grow_rect(rect: Rect2, image_dict: Dictionary) -> Rect2:
	for x in range(rect.position.x, rect.end.x):
		if image_dict[Vector2(x, rect.position.y)] != 0:
			return Rect2(rect.position + Vector2.UP, rect.size + Vector2.DOWN)
		if image_dict[Vector2(x, rect.end.y)] != 0:
			return Rect2(rect.position, rect.size + Vector2.DOWN)
	for y in range(rect.position.y, rect.end.y):
		if image_dict[Vector2(rect.position.x, y)] != 0:
			return Rect2(rect.position + Vector2.LEFT, rect.size + Vector2.RIGHT)
		if image_dict[Vector2(rect.end.x, y)] != 0:
			return Rect2(rect.position, rect.size + Vector2.RIGHT)
	return rect
		

func thread_done(i: int) -> void:
	all_boxes.append_array(region_threads[i].wait_to_finish())
	threads_finished += 1
	$Layout/ProgressBar.value += $Layout/ProgressBar.max_value / region_threads.size()
	if threads_finished == region_threads.size():
		combine_boxes()
		display_sprites()
		sep.disabled = false
		xport.disabled = false


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
	var text := ImageTexture.new()
	text.create_from_image(image, 0)
	texture.texture = text
	transparent.show()
	texture.rect_position = -size / 2
	transparent.rect_position = -size / 2
	for rect in all_boxes: 
		var outline := SpriteOutline.instance()
		texture.add_child(outline)
		outline.parent_global_rect = Rect2(texture.rect_global_position, size)
		outline.resize(rect.position + texture.rect_global_position, rect.size)


func _exit_tree() -> void:
	for thread in region_threads:
		if thread.is_active():
			thread.wait_to_finish()


func _on_Export_pressed() -> void:
	$FileDialog.mode = FileDialog.MODE_OPEN_DIR
	$FileDialog.popup()


func _on_FileDialog_dir_selected(dir: String) -> void:
	var arr := path.get_file().split(".")
	arr.remove(arr.size() -1)
	var image_name := arr.join(".")
	var directory := Directory.new()
	if not directory.dir_exists(dir + "/%s" % image_name):
		directory.make_dir(dir + "/%s" % image_name)
	for child in texture.get_children():
		image.get_rect(child.get_rect()).save_png(dir + "/%s/%s.png" % [image_name, child.get_index()])


func outside_sprite_gui_input(event: InputEvent) -> void:
	var mouse: Vector2 = (((get_global_mouse_position() - get_viewport().size / 2) * cam.zoom) + cam.position).snapped(Vector2.ONE)
	if not Input.is_action_pressed("ui_select") and event.is_action_released("click"):
		is_drawing = false
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected and not button.is_preview:
				button.select(false)
	elif not Input.is_action_pressed("ui_select") and not is_drawing and event is InputEventMouseMotion and Input.is_action_pressed("click") and texture.texture and texture.get_global_rect().has_point(mouse):
		is_drawing = true
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected:
				button.select(false)
		var outline := SpriteOutline.instance()
		texture.add_child(outline)
		outline.parent_global_rect = Rect2(texture.rect_global_position, size)
		outline.resize(mouse - (vc.rect_global_position) * cam.zoom, Vector2.ONE)
		outline.preview_start = mouse - (vc.rect_global_position) * cam.zoom
		outline.set_preview(true)
		outline.select(true)
	elif not Input.is_action_pressed("ui_select") and not is_drawing and event is InputEventMouseMotion and Input.is_action_pressed("right_click") and texture.texture and texture.get_global_rect().has_point(mouse):
		is_drawing = true
		for button in get_tree().get_nodes_in_group("sprite_outline"):
			if button.selected:
				button.select(false)
		var s := Selection.instance()
		texture.add_child(s)
		s.parent_global_rect = Rect2(texture.rect_global_position, size)
		s.resize(mouse, Vector2.ONE)
		s.preview_start = mouse - vc.rect_global_position * cam.zoom
	elif Input.is_action_pressed("ui_select") and Input.is_action_pressed("click") and event is InputEventMouseMotion:
		cam.position -= event.relative
		cam.position = cam.position.limit_length(CAM_LIM)


func _on_Help_pressed() -> void: 
	$Help.popup_centered()


func _on_TextureRect_resized() -> void:
	transparent.rect_size = texture.rect_size


func _on_Credits_pressed() -> void:
	$Credits.popup()


func _on_Label_meta_clicked(meta) -> void:
	OS.shell_open(meta)
