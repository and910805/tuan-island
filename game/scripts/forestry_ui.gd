extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const ThemeArt = preload("res://scripts/inventory_pixel_theme.gd")
const DIRECTIONS := ["上方", "右方", "下方", "左方"]
const INPUTS := {"charcoal": "fuel", "sapling": "saplings"}
const PRODUCTS := ["wood", "fiber", "resin"]

var modal: Control
var update_view: Callable

func device(app, cell: Vector2i) -> void:
	var body: VBoxContainer = app._open_modal("林務工作站")
	modal = app.modal
	modal.set_meta("life_modal_layout", "forestry_device")
	modal.theme = ThemeArt.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel", ThemeArt.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	body.add_child(layout)
	var plots := Tasks.card(layout)
	plots.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tasks.line(app, plots, "作業地塊", 20)
	Tasks.line(app, plots, "距工作站兩格，每 %d 秒依序檢查一格。" % World.FORESTRY.INTERVAL, 15)
	var summary: Label = single_line(app, "", 16)
	plots.add_child(summary)
	var plots_grid := GridContainer.new()
	plots_grid.columns = 2
	plots_grid.add_theme_constant_override("h_separation", 6)
	plots_grid.add_theme_constant_override("v_separation", 6)
	plots.add_child(plots_grid)
	var plot_labels: Array[Label] = []
	for direction in DIRECTIONS:
		var plot_card := Tasks.card(plots_grid)
		plot_card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := HBoxContainer.new()
		plot_card.add_child(line)
		Tasks.add_icon(line, ItemArt.icon("sapling"), 32)
		line.add_child(single_line(app, direction, 15))
		var plot: Label = app.label("", 14)
		plot.custom_minimum_size = Vector2(124, 24)
		plot_card.add_child(plot)
		plot_labels.append(plot)
	var controls := Tasks.card(layout)
	controls.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := HBoxContainer.new()
	controls.add_child(heading)
	Tasks.add_icon(heading, ItemArt.icon("forester_kit"), 32)
	heading.add_child(single_line(app, "供料與產物", 20))
	var stocks: Dictionary = {}
	for item in INPUTS:
		var row := HBoxContainer.new()
		controls.add_child(row)
		Tasks.add_icon(row, ItemArt.icon(item), 32)
		var amount := single_line(app, "", 15)
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(amount)
		var load_button: Button = app.button("補入", func(): app.session.perform("load_forester", cell, item))
		load_button.tooltip_text = "每次最多補入 4 件"
		row.add_child(load_button)
		stocks[item] = [amount, load_button]
	var output := HBoxContainer.new()
	output.add_theme_constant_override("separation", 8)
	controls.add_child(output)
	var product_labels: Dictionary = {}
	for item in PRODUCTS:
		var row := HBoxContainer.new()
		output.add_child(row)
		Tasks.add_icon(row, ItemArt.icon(item), 32)
		var label := single_line(app, "", 15)
		row.add_child(label)
		product_labels[item] = label
	var toggle: Button = app.button("啟用", func(): app.session.perform("toggle_forester", cell))
	var collect: Button = app.button("領取產物", func(): app.session.perform("collect_forester", cell))
	var unload: Button = app.button("退回供料", func(): app.session.perform("unload_forester", cell))
	var actions := HBoxContainer.new()
	controls.add_child(actions)
	for button in [toggle, collect, unload]:
		actions.add_child(button)
	var key := World.key(cell)
	var map := World.new()
	update_view = func(snapshot: Dictionary, person: Dictionary):
		var station: Dictionary = snapshot.get("objects", {}).get(key, {})
		var present: bool = station.get("type") == "forester"
		var owned: bool = present and station.get("owner") == app.session.own_id
		var enabled: bool = station.get("enabled", false)
		var bag: Dictionary = person.get("inventory", {})
		map.state = snapshot
		var has_supply := false
		for item in INPUTS:
			var stored: int = station.get(INPUTS[item], 0)
			var held: int = bag.get(item, 0)
			stocks[item][0].text = "%s %d／%d · 背包 %d" % [World.NAMES[item], stored, World.FORESTRY.CAPACITY, held]
			stocks[item][1].disabled = not owned or stored >= World.FORESTRY.CAPACITY or held == 0
			has_supply = has_supply or stored > 0
		var total := 0
		for item in PRODUCTS:
			var amount: int = station.get("items", {}).get(item, 0)
			product_labels[item].text = "%d／%d" % [amount, World.FORESTRY.OUTPUT_CAPS[item]]
			product_labels[item].tooltip_text = World.NAMES[item]
			total += amount
		toggle.disabled = not owned
		toggle.text = "停止" if enabled else "啟用"
		collect.disabled = not owned or total == 0
		unload.disabled = not owned or not has_supply
		summary.text = station_summary(snapshot, station, present, owned)
		for index in plot_labels.size():
			var tile: Vector2i = cell + World.FORESTRY.OFFSETS[index]
			plot_labels[index].text = plot_summary(map, tile, station) if present else "—"
	refresh(app)

func refresh(app) -> void:
	if not is_instance_valid(modal) or app.modal != modal:
		modal = null
		update_view = Callable()
		return
	var snapshot: Dictionary = app.session.snapshot
	update_view.call(snapshot, snapshot.get("players", {}).get(app.session.own_id, {}))

static func single_line(app, text: String, pixels: int) -> Label:
	var label: Label = app.label(text, pixels)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

static func station_summary(snapshot: Dictionary, station: Dictionary, present: bool, owned: bool) -> String:
	if not present:return "工作站已移除"
	if not owned:return "由擁有者操作"
	if not station.enabled:return "已停止"
	var remaining := maxi(0, ceili(float(station.next_cycle) - float(snapshot.get("time", 0))))
	return "下次檢查%s · %d 秒" % [DIRECTIONS[int(station.cursor)], remaining]

static func plot_summary(map, tile: Vector2i, station: Dictionary) -> String:
	var status: String = World.FORESTRY.plot_status(map, tile, station.owner)
	match status:
		"empty":
			var center := Vector2(tile) + Vector2(0.5, 0.5)
			for person in map.state.get("players", {}).values():
				if Vector2(person.x, person.y).distance_to(center) < 0.8:
					return "有人站立 · 稍候"
			return "空地 · 可種植" if station.saplings > 0 else "空地 · 缺樹苗"
		"growing":
			var tree: Dictionary = map.state.forest[World.key(tile)]
			var seconds := ceili(World.TREE_TIME - float(tree.growth))
			return "等待讓出空間" if seconds <= 0 else "成長中 · 約 %d 秒" % seconds
		"mature":
			if station.fuel == 0:return "成熟 · 缺木炭"
			for item in PRODUCTS:
				if int(station.items.get(item, 0)) + World.FORESTRY.OUTPUT[item] > World.FORESTRY.OUTPUT_CAPS[item]:
					return "成熟 · 請先領取產物"
			return "成熟 · 可採收"
		_:
			return "不可作業"
