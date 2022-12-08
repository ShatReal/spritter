extends Control


const Tab := preload("res://scenes/main/tab.tscn")

var action := "edit_sprites"
var file_action := ""

onready var top_buttons := $Layout/TopBar/Buttons
onready var file_button := $"%FileButton"
onready var select_button := $"%SelectButton"
onready var sprite_button := $"%SpriteButton"
onready var export_button := $"%ExportButton"

onready var tabs := $Layout/Main/Tabs

onready var sidebar := $Layout/Main/Sidebar
onready var edit_sprites := $Layout/Main/Sidebar/EditSprites
onready var select_sprites := $Layout/Main/Sidebar/SelectSprites
onready var auto_sprite := $Layout/Main/Sidebar/AutoSprite

onready var zoom_label := $Layout/BottomBar/HBox/Zoom
onready var mouse_pos_label := $Layout/BottomBar/HBox/MousePos

onready var progress_bar := $Layout/ProgressBar

onready var file_dialog := $FileDialog
onready var note := $Note
onready var confirm := $Confirm

onready var cut_rows := $Cut/VBox/Top/Rows
onready var cut_cols := $Cut/VBox/Top/Columns
onready var cut_y := $Cut/VBox/Bottom/YSize
onready var cut_x := $Cut/VBox/Bottom/XSize


func _ready() -> void:
	randomize()
	
	Detect.connect("region_thread_finished", self, "on_region_thread_finished")
	Detect.connect("detecting_finished", self, "on_detecting_finished")
	SaveLoad.connect("show_note", self, "show_note")
	SaveLoad.connect("sheet_loaded", self, "on_sheet_loaded")
	
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	for child in file_dialog.get_children():
		if child is WindowDialog:
			child.get_child(1).align = Label.ALIGN_CENTER
	note.get_child(1).align = Label.ALIGN_CENTER
	confirm.get_child(1).align = Label.ALIGN_CENTER
	
	for child in top_buttons.get_children():
		child.get_popup().connect("id_pressed", self, "on_menu_item_pressed", [child.name])
	for child in sidebar.get_children():
		child.connect("pressed", self, "on_sidebar_button_pressed", [child.get_index()])
	for node in [cut_rows, cut_cols, cut_y, cut_x]:
		node.connect("value_changed", self, "recalc_cut", [node.name])
	

func _process(_delta: float) -> void:
	if tabs.get_child_count() != 0:
		var mouse: Vector2 = tabs.get_child(tabs.current_tab).get_mouse()
		$Layout/BottomBar/HBox/MousePos.text = "(%s, %s)" % [mouse.x, mouse.y]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("edit_sprites"):
		set_all_tabs_action("edit_sprites")
		edit_sprites.pressed = true
	elif event.is_action_pressed("select_sprites"):
		set_all_tabs_action("select_sprites")
		select_sprites.pressed = true
	elif event.is_action_pressed("auto_sprite"):
		set_all_tabs_action("auto_sprite")
		$Layout/Main/Sidebar/AutoSprite.pressed = true
	elif event.is_action_pressed("close_tab") and tabs.get_child_count() != 0:
		close_tab()


func on_detecting_finished(all_rects: Array) -> void:
	tabs.get_current_tab_control().display_sprites(all_rects)


func set_all_tabs_action(a: String) -> void:
	action = a
	for tab in tabs.get_children():
		tab.action = a


func _on_FileDialog_dir_selected(dir: String) -> void:
	tabs.get_child(tabs.current_tab).export_sprites(dir)


func _on_Label_meta_clicked(meta) -> void:
	OS.shell_open(meta)


func close_tab() -> void:
	if tabs.get_child_count() == 1:
		for i in select_button.get_popup().get_item_count():
			sprite_button.get_popup().set_item_disabled(i, true)
		for i in sprite_button.get_popup().get_item_count():
			sprite_button.get_popup().set_item_disabled(i, true)
		for i in export_button.get_popup().get_item_count():
			export_button.get_popup().set_item_disabled(i, true)
		file_button.get_popup().set_item_disabled(1, true)
		file_button.get_popup().set_item_disabled(2, true)
	tabs.get_child(tabs.current_tab).queue_free()



func on_menu_item_pressed(id: int, group: String) -> void:
	match group:
		"FileButton":
			match id:
				0:
					show_file(FileDialog.MODE_OPEN_FILE, PoolStringArray(["*.png"]), "open")
				1:
					close_tab()
				2:
					show_file(FileDialog.MODE_SAVE_FILE, PoolStringArray(["*.spritter"]), "save")
				3:
					show_file(FileDialog.MODE_OPEN_FILE, PoolStringArray(["*.spritter"]), "load")
		"SelectButton":
			match id:
				0:
					tabs.get_child(tabs.current_tab).combine_selected()
		"SpriteButton":
			match id:
				0:
					recalc_cut(cut_cols.value, "Columns")
					recalc_cut(cut_rows.value, "Rows")
					$Cut.popup()
				1:
					$Layout/ProgressBar.value = 0
					Detect.detect(tabs.get_child(tabs.current_tab).image_size, tabs.get_child(tabs.current_tab).image_data)
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
			set_all_tabs_action("edit_sprites")
		1:
			set_all_tabs_action("select_sprites")
		2:
			set_all_tabs_action("auto_sprite")


func recalc_cut(value: float, node: String) -> void:
	var image_size: Vector2 = tabs.get_child(tabs.current_tab).image_size
	match node:
		"Rows":
			cut_y.value = int(image_size.y / value)
		"Columns":
			cut_x.value = int(image_size.x / value)
		"YSize":
			cut_rows.value = int(image_size.y / value)
		"XSize":
			cut_cols.value = int(image_size.x / value)


func show_note(message: String) -> void:
	$Note.dialog_text = message
	$Note.popup()


func on_sheet_loaded(image_data: Image, sprite_data: Array, path: String) -> void:
	new_tab(path, image_data, sprite_data)



func on_region_thread_finished(num_threads: int) -> void:
	progress_bar.value += progress_bar.max_value / num_threads


func _on_FileDialog_file_selected(path: String) -> void:
	match file_action:
		"open":
			new_tab(path)
		"save":
			var tab := tabs.get_child(tabs.current_tab)
			tab.name = Util.remove_file_extension(path.get_file())
			tab.save_path = path
			SaveLoad.save_sheet(path, tab.image, tab.sprites)
		"load":
			SaveLoad.load_sheet(path)


func show_confirm(message: String) -> void:
	confirm.dialog_text = message
	confirm.popup()


func show_file(mode: int, filters: PoolStringArray, a: String) -> void:
	file_dialog.mode = mode
	file_dialog.filters = filters
	file_action = a
	file_dialog.current_file = Util.remove_file_extension(file_dialog.current_file)
	file_dialog.popup()


func change_zoom(zoom) -> void:
	zoom_label.text = "%s%%" % (zoom * 100)


func _on_Tabs_tab_changed(tab: int) -> void:
	change_zoom(tabs.get_child(tab).ZOOM_INTERVALS[tabs.get_child(tab).zoom_counter])


func new_tab(path := "", image_data = null, sprite_data = null) -> void:
	for i in select_button.get_popup().get_item_count():
		select_button.get_popup().set_item_disabled(i, false)
	for i in sprite_button.get_popup().get_item_count():
		sprite_button.get_popup().set_item_disabled(i, false)
	for i in export_button.get_popup().get_item_count():
		export_button.get_popup().set_item_disabled(i, false)
	file_button.get_popup().set_item_disabled(1, false)
	file_button.get_popup().set_item_disabled(2, false)
	var tab := Tab.instance()
	tabs.add_child(tab)
	var result: bool = tab.init(path, image_data, sprite_data)
	if not result:
		tab.queue_free()
		show_note("Error loading file!")
	tab.action = action
	tab.connect("show_file", self, "show_file")
	tab.connect("close_tab", self, "close_tab")
	tab.connect("zoom_changed", self, "change_zoom")


func _on_CutOk_pressed() -> void:
	$Cut.hide()
	tabs.get_current_tab_control().cut(Vector2(cut_x.value, cut_y.value))
