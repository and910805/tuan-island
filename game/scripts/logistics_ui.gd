extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const ARROWS := ["↑", "→", "↓", "←"]

var modal: Control
var update_view: Callable

func device(app, cell: Vector2i) -> void:
	var body: VBoxContainer = app._open_modal("輸送帶")
	modal = app.modal
	modal.set_meta("life_modal_layout", "logistics_device")
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	body.add_child(layout)
	var route := Tasks.card(layout)
	route.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tasks.line(app, route, "輸送方向", 20)
	var compass := GridContainer.new()
	compass.columns = 3
	compass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	route.add_child(compass)
	var directions: Dictionary = {}
	var placements := {1: 0, 3: 3, 5: 1, 7: 2}
	for index in 9:
		if placements.has(index):
			var direction: int = placements[index]
			var arrow: Button = app.button(ARROWS[direction], func(): app.session.perform("configure_conveyor", cell, "dir:%d" % direction))
			arrow.toggle_mode = true
			arrow.custom_minimum_size = Vector2(52, 42)
			compass.add_child(arrow)
			directions[direction] = arrow
		elif index == 4:
			Tasks.add_icon(compass, ItemArt.icon("conveyor_kit"), 64)
		else:
			compass.add_child(Control.new())
	var endpoints := plain_label(app, route, "", 15)
	var cargo := Tasks.card(layout)
	cargo.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tasks.line(app, cargo, "輸送物品", 20)
	var filters := GridContainer.new()
	filters.columns = 6
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 6)
	cargo.add_child(filters)
	var filter_buttons: Dictionary = {}
	for item in World.LOGISTICS.FILTERS:
		var choice: Button = app.button("", func(): app.session.perform("configure_conveyor", cell, "filter:" + item))
		choice.icon = ItemArt.icon(item)
		choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice.tooltip_text = World.NAMES[item]
		choice.name = "Filter_" + item
		choice.toggle_mode = true
		choice.custom_minimum_size = Vector2(48, 48)
		filters.add_child(choice)
		filter_buttons[item] = choice
	var status := plain_label(app, cargo, "", 16)
	var transit := plain_label(app, cargo, "", 15)
	var controls := HBoxContainer.new()
	cargo.add_child(controls)
	var toggle: Button = app.button("啟用", func(): app.session.perform("toggle_conveyor", cell))
	var unload: Button = app.button("取回物品", func(): app.session.perform("unload_conveyor", cell))
	controls.add_child(toggle)
	controls.add_child(unload)
	Tasks.line(app, body, "每 %d 秒移動一格。由後方接收，往前方送出。轉彎時，把下一段輸送帶轉向目的地。" % World.LOGISTICS.INTERVAL, 15)
	Tasks.line(app, body, "木材送加工台，小麥送麵粉磨坊，銅礦送水力加工台；木炭供林務站與採掘機。礦料與成品可送入私人箱。", 15)
	var key := World.key(cell)
	update_view = func(snapshot: Dictionary):
		var objects: Dictionary = snapshot.get("objects", {})
		var belt: Dictionary = objects.get(key, {})
		var present: bool = belt.get("type") == "conveyor"
		var owner: bool = present and belt.get("owner") == app.session.own_id
		var enabled: bool = belt.get("enabled", false)
		var direction: int = belt.get("dir", 0)
		var item: String = belt.get("filter", "wood")
		var buffered: int = belt.get("items", {}).get(item, 0)
		var next_step := maxi(0, ceili(float(snapshot.get("next_logistics_check", 0)) - float(snapshot.get("time", 0))))
		for arrow in directions:
			directions[arrow].disabled = not owner or enabled or buffered > 0
			directions[arrow].set_pressed_no_signal(arrow == direction)
		for filter in filter_buttons:
			filter_buttons[filter].disabled = not owner or enabled or buffered > 0
			filter_buttons[filter].set_pressed_no_signal(filter == item)
		var offset: Vector2i = World.LOGISTICS.DIRECTIONS[direction]
		var source := source_status(objects, cell, offset, belt.get("owner", ""), item)
		var destination := destination_status(objects, cell + offset, belt.get("owner", ""), item)
		endpoints.text = "來源　%s\n目的地　%s" % [source.text, destination.text]
		transit.text = "%s　帶上 %d／1" % [World.NAMES[item], buffered]
		status.text = "輸送帶已移除" if not present else ("由擁有者操作" if not owner else
			("運作中 · 下次檢查 %d 秒" % next_step if enabled else ("已停止 · 先取回物品" if buffered > 0 else "已停止 · 可設定")))
		if owner and enabled:
			if buffered > 0 and not destination.ready:
				status.text = "阻塞 · " + destination.text
			elif buffered == 0 and not source.ready:
				status.text = "等待 · " + source.text
		toggle.disabled = not owner
		toggle.text = "停止" if enabled else "啟用"
		unload.disabled = not owner or buffered == 0
	refresh(app)

func refresh(app) -> void:
	if not is_instance_valid(modal) or app.modal != modal:
		modal = null
		update_view = Callable()
		return
	update_view.call(app.session.snapshot)

static func plain_label(app, parent: Container, text: String, font_size: int) -> Label:
	var result: Label = app.label(text, font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(result)
	return result

static func source_status(objects: Dictionary, cell: Vector2i, offset: Vector2i, owner: String, item: String) -> Dictionary:
	var incoming := 0
	var loaded := false
	for neighbor_offset in World.LOGISTICS.DIRECTIONS:
		var neighbor: Dictionary = objects.get(World.key(cell + neighbor_offset), {})
		if neighbor.get("type") != "conveyor" or neighbor.get("owner") != owner:continue
		if not neighbor.get("enabled", false) or neighbor.get("filter") != item:continue
		if World.LOGISTICS.DIRECTIONS[int(neighbor.dir)] != -neighbor_offset:continue
		incoming += 1
		loaded = loaded or int(neighbor.items.get(item, 0)) > 0
	var rear: Dictionary = objects.get(World.key(cell - offset), {})
	var kind: String = rear.get("type", "")
	if rear.get("owner") == owner and kind in World.LOGISTICS.SOURCES:
		var name: String = World.BUILD[kind].name
		if int(rear.items.get(item, 0)) > 0:return {"text": name, "ready": true}
		if incoming == 0:return {"text": name + "沒有指定物品", "ready": false}
	if incoming > 0:
		return {"text": "接入輸送帶 %d 段%s" % [incoming, "" if loaded else "（等待物品）"], "ready": loaded}
	return {"text": "未接通來源", "ready": false}

static func destination_status(objects: Dictionary, cell: Vector2i, owner: String, item: String) -> Dictionary:
	var object: Dictionary = objects.get(World.key(cell), {})
	if object.is_empty():return {"text": "未接通目的地", "ready": false}
	if object.get("owner") != owner:return {"text": "其他玩家的設備", "ready": false}
	var kind: String = object.get("type", "")
	match kind:
		"conveyor":
			if not object.get("enabled", false):return {"text": "下一段輸送帶已停止", "ready": false}
			if object.get("filter") != item:return {"text": "下一段物品設定不同", "ready": false}
			if not object.items.is_empty():return {"text": "下一段輸送帶已有物品", "ready": false}
		"private_chest":
			if int(object.items.get(item, 0)) >= 1000000000:return {"text": "私人箱已滿", "ready": false}
		"forester":
			if item != "charcoal":return {"text": "林務站只接收木炭", "ready": false}
			if int(object.fuel) >= World.FORESTRY.CAPACITY:return {"text": "林務站燃料已滿", "ready": false}
		"sawmill", "charcoal_kiln", "mill":
			var accepted: String = World.LOGISTICS.input_item(kind)
			if item != accepted:return {"text": "%s只接收%s" % [World.BUILD[kind].name if kind == "mill" else "加工設備", World.NAMES[accepted]], "ready": false}
			if int(object.get(World.LOGISTICS.input_field(kind), 0)) >= World.LOGISTICS.PROCESS_INPUT_CAP:return {"text": "加工料槽已滿", "ready": false}
		"waterworks":
			if not World.WATERWORKS.INPUTS.has(item):return {"text": "水力加工台只接收銅礦與木材", "ready": false}
			if int(object.get("input",{}).get(item,0)) >= World.WATERWORKS.INPUT_CAP:return {"text": "水力加工台的%s料槽已滿" % World.NAMES[item], "ready": false}
		"mine_drill":
			if item != "charcoal":return {"text": "採掘機只接收木炭", "ready": false}
			if int(object.get("fuel",0)) >= World.MINE_DRILL.FUEL_CAP:return {"text": "採掘機燃料已滿", "ready": false}
		_:
			return {"text": "無相容目的地", "ready": false}
	return {"text": World.BUILD[kind].name, "ready": true}
