extends Node


signal region_thread_finished(num_threads)
signal detecting_finished(all_rects)

var distance_between_tiles := 0
var regions: Array
var region_threads: Array
var sub_region_count: int
var threads_finished: int
var all_rects: Array
var bitmap_threshold := 0.1


func _ready() -> void:
	if OS.get_processor_count() > 1:
		sub_region_count = 4
	else:
		sub_region_count = 2


func _exit_tree() -> void:
	for thread in region_threads:
		if thread.is_active():
			thread.wait_to_finish()


func detect(image_size: Vector2, image_data: PoolByteArray) -> void:
	all_rects = []
#	var bitmap := BitMap.new()
#	bitmap.create_from_image_alpha(image, bitmap_threshold)
#	for i in bitmap.opaque_to_polygons(Rect2(Vector2(), bitmap.get_size())):
#		var arrx := []
#		var arry := []
#		for j in i:
#			arrx.append(j.x)
#			arry.append(j.y)
#		all_rects.append(Rect2(arrx.min(), arry.min(), arrx.max() - arrx.min(), arry.max() - arry.min()))
#	display_sprites()
	var y_size: int = ceil(image_size.y / sub_region_count)
	var x_size: int = ceil(image_size.x / sub_region_count)
	regions = []
	region_threads = []
	threads_finished = 0
	for y in range(0, image_size.y, y_size):
		for x in range(0, image_size.x, x_size):
			var region := Rect2(x, y, min(x_size + 1, image_size.x - x), min(y_size + 1, image_size.y - y))
			var thread := Thread.new()
			region_threads.append(thread)
			regions.append(region)
	for i in region_threads.size():
		region_threads[i].start(self, "flood_region", {"i": i, "image_size": image_size, "image_data": image_data})


func flood_region(data: Dictionary) -> Array:
	var not_alpha := {}
	var rects := []
	for y in range(regions[data.i].position.y, regions[data.i].end.y):
		for x in range(regions[data.i].position.x, regions[data.i].end.x):
			var a: int = data.image_data[x * 4 + y * data.image_size.x * 4 + 3]
			if a != 0:
				not_alpha[Vector2(x, y)] = a
	while not not_alpha.empty():
		rects.append(find_extents(not_alpha.keys()[0], not_alpha))
	call_deferred("thread_finished", data.i)
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
	
	
func thread_finished(i: int) -> void:
	all_rects.append_array(region_threads[i].wait_to_finish())
	threads_finished += 1
	emit_signal("region_thread_finished", region_threads.size())
	if threads_finished == region_threads.size():
		combine_boxes()
		emit_signal("detecting_finished", all_rects)


func combine_boxes() -> void:
	var i := all_rects.size() - 1
	while i != -1:
		var has_merged := false
		for j in range(i - 1, -1, -1):
			if all_rects[i].intersects(all_rects[j], true):
				all_rects[i] = all_rects[i].merge(all_rects[j])
				all_rects.remove(j)
				has_merged = true
				i -= 1
		if not has_merged:
			i -= 1
		else:
			for j in range(i - 1, -1, -1):
				if all_rects[i].intersects(all_rects[j], true):
					all_rects[i] = all_rects[i].merge(all_rects[j])
					all_rects.remove(j)
					has_merged = true
					i -= 1
			if not has_merged:
				i -= 1
