extends Button


signal selected(on)
signal outline_resized(original_rect, new_rect)
signal move_started()
signal move_ended()

const BORDER_WIDTH := 2

var selected_button: Button
var selected := false
var mouse_offset: Vector2
var is_preview := false
var preview_start: Vector2
var is_moving := false
var original_rect: Rect2


func _ready() -> void:
	set_process(false)
	for child in get_children():
		child.connect("button_down", self, "on_edge_button_down", [child])
		child.connect("gui_input", self, "on_edge_gui_input")


func _input(event: InputEvent) -> void:
	if event.is_action_released("click"):
		if not selected_button:
			return
		selected_button = null
		set_process(false)
		emit_signal("outline_resized", original_rect, get_rect())


func _process(_delta: float) -> void:
	var mouse: Vector2 = get_parent().get_local_mouse_position().snapped(Vector2.ONE)
	var parent_rect: Rect2 = get_parent().get_rect()
	if is_preview:
		mouse.x = clamp(mouse.x, 0, parent_rect.size.x)
		mouse.y = clamp(mouse.y, 0, parent_rect.size.y)
		if mouse.x < preview_start.x:
			if mouse.y < preview_start.y:
				resize(Vector2(mouse.x, mouse.y), Vector2(preview_start.x - mouse.x, preview_start.y - mouse.y))
			else:
				resize(Vector2(mouse.x, preview_start.y), Vector2(preview_start.x - mouse.x, mouse.y - preview_start.y))
		elif mouse.y < preview_start.y:
			resize(Vector2(preview_start.x, mouse.y), Vector2(mouse.x - preview_start.x, preview_start.y - mouse.y))
		else:
			resize(preview_start, mouse - rect_position)
	elif selected_button:
		var new_position := rect_position
		var new_size := rect_size
		var rect := get_rect()
		if "Top" in selected_button.name:
			mouse.y = clamp(mouse.y, 0, rect.end.y - 1)
			new_size.y = rect.end.y - mouse.y
			new_position.y = mouse.y
		elif "Bottom" in selected_button.name:
			mouse.y = clamp(mouse.y, rect.position.y + 1, parent_rect.size.y)
			new_size.y = mouse.y - rect.position.y
		if "Left" in selected_button.name:
			mouse.x = clamp(mouse.x, 0, rect.end.x - 1)
			new_size.x = rect.end.x - mouse.x
			new_position.x = mouse.x
		elif "Right" in selected_button.name:
			mouse.x = clamp(mouse.x, rect.position.x + 1, parent_rect.size.x)
			new_size.x = mouse.x - rect.position.x
		resize(new_position, new_size)
	else:
		var change := mouse - mouse_offset - rect_position
		rect_position = mouse - mouse_offset
		for other_button in get_tree().get_nodes_in_group("sprite_outline"):
			if not other_button == self and other_button.selected:
				other_button.rect_position += change


func resize(position: Vector2, size: Vector2) -> void:
	rect_position = position
	rect_size = size
	$Top.rect_size.x = size.x + BORDER_WIDTH * 2 - 2
	$Bottom.rect_size.x = size.x + BORDER_WIDTH * 2 - 2
	$Left.rect_size.y = size.y + BORDER_WIDTH * 2 - 2
	$Right.rect_size.y = size.y + BORDER_WIDTH * 2 - 2
	$Bottom.rect_position.y = size.y - 1 - BORDER_WIDTH
	$Right.rect_position.x = size.x - 1 - BORDER_WIDTH
	$TopRight.rect_position.x = size.x - 1 - BORDER_WIDTH
	$BottomLeft.rect_position.y = size.y - 1 - BORDER_WIDTH
	$BottomRight.rect_position.x = size.x - 1 - BORDER_WIDTH
	$BottomRight.rect_position.y = size.y - 1 - BORDER_WIDTH


func on_edge_button_down(edge: Button) -> void:
	if get_tree().current_scene.action != "edit_sprites":
		return
	if Input.is_action_pressed("move"):
		return
	original_rect = get_rect()
	set_process(true)
	selected_button = edge
	

func select(on: bool) -> void:
	selected = on
	emit_signal("selected", on)
	for child in get_children():
		child.disabled = not on
		if on:
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			mouse_default_cursor_shape = Control.CURSOR_MOVE
			match child.name:
				"Top", "Bottom":
					child.mouse_default_cursor_shape = Control.CURSOR_VSIZE
				"Left", "Right":
					child.mouse_default_cursor_shape = Control.CURSOR_HSIZE
				"TopLeft", "BottomRight":
					child.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
				"TopRight", "BottomLeft":
					child.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		else:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			child.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			child.mouse_filter = Control.MOUSE_FILTER_PASS


func _on_SpriteOutline_button_down() -> void:
	if Input.is_action_pressed("move"):
		return
	select(true)
	set_process(true)
	is_moving = true
	mouse_offset = get_local_mouse_position()
	emit_signal("move_started")


func _on_SpriteOutline_button_up() -> void:
	set_process(false)


func _on_SpriteOutline_pressed() -> void:
	if Input.is_action_pressed("move"):
		return
	if not is_moving:
		if not Input.is_action_pressed("shift"):
			for other_sprite in get_tree().get_nodes_in_group("sprite_outline"):
				if not other_sprite == self and other_sprite.selected:
					other_sprite.select(false)
	else:
		is_moving = false
		emit_signal("move_ended")


func set_preview(on: bool) -> void:
	is_preview = on
	set_process(on)


func on_edge_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not Input.is_action_pressed("click"):
		get_tree().current_scene.on_outside_sprite_gui_input(event)
