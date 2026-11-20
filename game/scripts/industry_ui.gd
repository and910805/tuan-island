extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const ProcessingQueueUI = preload("res://scripts/processing_queue_ui.gd")
const KITS := {
	"water_pipe": "pipe_kit", "water_tank": "tank_kit", "water_pump": "pump_kit",
	"sawmill": "sawmill_kit", "charcoal_kiln": "kiln_kit", "mill": "mill_kit",
}

var modal: Control
var update_view: Callable

func refresh(app) -> void:
	ProcessingQueueUI.refresh(app)
	if not is_instance_valid(modal) or app.modal != modal:
		update_view = Callable()
		modal = null
		return
	var snapshot: Dictionary = app.session.snapshot
	if update_view.is_valid():
		update_view.call(snapshot, snapshot.get("players", {}).get(app.session.own_id, {}))

func device(app, cell: Vector2i) -> void:
	var key := World.key(cell)
	var obj: Dictionary = app.session.snapshot.get("objects", {}).get(key, {})
	var kind: String = obj.get("type", "")
	if kind in World.LOGISTICS.PROCESSORS or kind in World.INDUSTRY.MANUAL_STATIONS:
		# T036: manual queue + automatic buffer workbench owns its own layout,
		# Session signals and refresh; this RefCounted keeps no reference to it.
		update_view = Callable()
		modal = null
		ProcessingQueueUI.open(app, cell)
		return
	if not KITS.has(kind):return
	var body: VBoxContainer = app._open_modal(World.BUILD[kind].name)
	modal = app.modal
	modal.set_meta("life_modal_layout", "industry_device")
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var paper := Tasks.card(body)
	if kind in World.LOGISTICS.PROCESSORS:
		modal.set_meta("life_modal_layout", "logistics_processor")
		processing(app, paper, cell, World.LOGISTICS.output_item(kind), kind)
	else:
		water_device(app, paper, cell, kind)
	refresh(app)

func dye_menu(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal("家具換色")
	modal=app.modal
	modal.theme=PixelTheme.make(app.hud.theme)
	modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var back:Button=app.button("回染料配方",func():device(app,cell))
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	body.add_child(back)
	Tasks.line(app,body,"替染色桌四格內自己的床、桌、椅或沙發上色，每次用一份染料。",16)
	var rows:=VBoxContainer.new()
	body.add_child(rows)
	var snapshot:Dictionary=app.session.snapshot
	var keys:=World.nearby_dye_furniture(snapshot.get("objects",{}),app.session.own_id,cell)
	if keys.is_empty():Tasks.line(app,body,"附近還沒有可以換色的家具。",16)
	var bindings:Array=[]
	for key in keys:
		var card:=Tasks.card(rows)
		var title:Label=app.label("",17)
		card.add_child(title)
		var buttons:=HBoxContainer.new()
		buttons.add_theme_constant_override("separation",8)
		card.add_child(buttons)
		var choices:Dictionary={}
		for pigment in ["blue_dye","orange_dye",""]:
			var caption:String=World.INDUSTRY.FURNITURE_DYES.get(pigment,"恢復原色")
			var button:Button=app.button(caption,func():app.session.perform("dye_furniture",cell,key+"|"+pigment))
			button.name="DyeFurniture_%s_%s"%[key.replace(",","_"),pigment if not pigment.is_empty() else "natural"]
			if not pigment.is_empty():
				button.icon=ItemArt.icon(pigment)
				button.expand_icon=true
				button.add_theme_constant_override("icon_max_width",24)
			buttons.add_child(button)
			choices[pigment]=button
		bindings.append({"key":key,"title":title,"choices":choices})
	update_view=func(current:Dictionary,person:Dictionary):
		var objects:Dictionary=current.get("objects",{})
		var available:=World.nearby_dye_furniture(objects,app.session.own_id,cell)
		var bag:Dictionary=person.get("inventory",{})
		var table:Dictionary=objects.get(World.key(cell),{})
		var owns_table:bool=table.get("type")==World.INDUSTRY.DYE_TABLE and table.get("owner")==app.session.own_id
		for row in bindings:
			var obj:Dictionary=objects.get(row.key,{})
			var dye:String=obj.get("dye","")
			var name:String=World.BUILD.get(obj.get("type",""),{}).get("name","家具已搬走")
			var offset:=World.cell(row.key)-cell
			var hint:=PackedStringArray()
			if offset.x!=0:hint.append("%s %d 格"%["東" if offset.x>0 else "西",absi(offset.x)])
			if offset.y!=0:hint.append("%s %d 格"%["南" if offset.y>0 else "北",absi(offset.y)])
			row.title.text="%s · %s · %s"%[name,"、".join(hint),World.INDUSTRY.FURNITURE_DYES.get(dye,"原色")]
			for pigment in row.choices:
				var button:Button=row.choices[pigment]
				var held:=int(bag.get(pigment,0))
				if not pigment.is_empty():button.text="%s · %d 份"%[World.INDUSTRY.FURNITURE_DYES[pigment],held]
				button.disabled=not owns_table or row.key not in available or pigment==dye or (not pigment.is_empty() and held<1)
	refresh(app)

func water_device(app, paper: VBoxContainer, cell: Vector2i, kind: String) -> void:
	var overview:=HBoxContainer.new()
	overview.add_theme_constant_override("separation",12)
	paper.add_child(overview)
	Tasks.add_icon(overview,ItemArt.icon(KITS[kind]),64)
	var heading: Label = app.label("", 20)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	overview.add_child(heading)
	var status: Label = app.label("", 16)
	status.name="WaterDeviceStatus"
	status.custom_minimum_size.x = 300
	paper.add_child(status)
	var gauge := ProgressBar.new()
	gauge.custom_minimum_size.y = 18
	gauge.show_percentage = false
	paper.add_child(gauge)
	gauge.visible = kind == "water_tank"
	var action := ""
	if kind == "water_tank":action = "refill_tank"
	if kind == "water_pump":action = "toggle_pump"
	var operation: Button = app.button("", func(): app.session.perform(action, cell))
	operation.name="WaterDeviceOperation"
	operation.size_flags_horizontal=Control.SIZE_SHRINK_END
	paper.add_child(operation)
	operation.visible = not action.is_empty()
	var key := World.key(cell)
	update_view = func(snapshot: Dictionary, _person: Dictionary):
		var obj: Dictionary = snapshot.get("objects", {}).get(key, {})
		var present: bool = obj.get("type") == kind
		var owner: bool = present and obj.get("owner") == app.session.own_id
		var network: Dictionary = World.INDUSTRY.network_info(snapshot, key)
		var tanks: int = network.get("connected_tanks", 0)
		var pumps: int = network.get("connected_pumps", 0)
		heading.text = "設備已移除" if not present else ("水桶 %d　·　水泵 %d" % [tanks, pumps])
		operation.disabled = not owner
		if kind == "water_tank":
			var water: int = obj.get("water", 0)
			gauge.max_value = World.INDUSTRY.TANK_CAPACITY
			gauge.value = water
			status.text = "水量 %d／%d%s" % [water, World.INDUSTRY.TANK_CAPACITY, " · 缺水" if water == 0 else ""]
			operation.text = "補滿儲水桶"
			operation.disabled = operation.disabled or water >= World.INDUSTRY.TANK_CAPACITY
			if pumps == 0:
				status.text += "\n沒有自動水源，可手動補水。"
			elif int(network.get("enabled_pumps", 0)) == 0:
				status.text += "\n連通的水泵尚未啟用，可手動補水。"
		elif kind == "water_pump":
			var enabled: bool = obj.get("enabled", false)
			status.text = "%s。需在河岸兩格內啟用，每 %d 秒可向連通水桶送 %d 格水。" % [
				"已啟用" if enabled else "已停止", World.INDUSTRY.INTERVAL,World.pump_rate_for(str(snapshot.get("region_id","home")),snapshot)]
			operation.text = "停止抽水" if enabled else "啟用河水泵"
			if tanks == 0:
				status.text += "\n未接通儲水桶，暫停供水。"
		else:
			status.text = "以四向相鄰水管連接同一位擁有者的設備。"
		if present and not owner:
			status.text += "\n由擁有者操作。"
		if present and int(network.get("capacity", 0)) > 0:
			status.text += "\n管網水量 %d／%d" % [network.water, network.capacity]

func processing(app, paper: VBoxContainer, cell: Vector2i, id: String, kind: String) -> void:
	var recipe: Dictionary = World.INDUSTRY.PROCESS[id]
	# Station buffer: wood/input_wood for sawmill & kiln, wheat/input_wheat for the mill.
	var input_item: String = World.LOGISTICS.input_item(kind)
	var input_field: String = World.LOGISTICS.input_field(kind)
	var input_name: String = World.NAMES[input_item]
	var header := HBoxContainer.new()
	paper.add_child(header)
	Tasks.add_icon(header, ItemArt.icon(KITS[kind]), 64)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(summary)
	var heading: Label = app.label("", 21)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	summary.add_child(heading)
	var requirement: Label = app.label("", 16)
	requirement.custom_minimum_size.x = 300
	summary.add_child(requirement)
	var ingredients := HBoxContainer.new()
	paper.add_child(ingredients)
	for item in recipe.ingredients:
		Tasks.add_icon(ingredients, ItemArt.icon(item), 32)
	var arrow:Label=app.label("→",18)
	arrow.autowrap_mode=TextServer.AUTOWRAP_OFF
	arrow.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	ingredients.add_child(arrow)
	Tasks.add_icon(ingredients, ItemArt.icon(id), 32)
	var gauge := ProgressBar.new()
	gauge.custom_minimum_size.y = 18
	gauge.show_percentage = false
	paper.add_child(gauge)
	var actions := HBoxContainer.new()
	paper.add_child(actions)
	var start: Button = app.button("開始加工", func(): app.session.perform("start_processing", cell, id))
	var claim: Button = app.button("領取成品", func(): app.session.perform("claim_processing", cell))
	var cancel: Button = app.button("取消並退回材料", func(): app.session.perform("cancel_processing", cell))
	for button in [start, claim, cancel]:
		actions.add_child(button)
	var automatic := HBoxContainer.new()
	automatic.add_theme_constant_override("separation", 10)
	paper.add_child(automatic)
	var auto_info := Tasks.card(automatic)
	auto_info.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tasks.line(app, auto_info, "自動加工", 17)
	var buffers := HBoxContainer.new()
	buffers.add_theme_constant_override("separation", 8)
	auto_info.add_child(buffers)
	Tasks.add_icon(buffers, ItemArt.icon(input_item), 32)
	var input_amount: Label = app.label("", 15)
	input_amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	buffers.add_child(input_amount)
	Tasks.add_icon(buffers, ItemArt.icon(id), 32)
	var output_amount: Label = app.label("", 15)
	output_amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	buffers.add_child(output_amount)
	var auto_status: Label = app.label("", 15)
	auto_status.custom_minimum_size.x = 280
	auto_info.add_child(auto_status)
	var supply := HBoxContainer.new()
	auto_info.add_child(supply)
	var feed: Button = app.button("補入" + input_name, func(): app.session.perform("feed_processing", cell))
	var unload: Button = app.button("取回" + input_name, func(): app.session.perform("unload_processing_input", cell))
	supply.add_child(feed)
	supply.add_child(unload)
	var auto_actions := HBoxContainer.new()
	auto_info.add_child(auto_actions)
	var toggle: Button = app.button("啟用自動加工", func(): app.session.perform("toggle_auto_processing", cell))
	var collect: Button = app.button("領取庫存", func(): app.session.perform("collect_processing_output", cell))
	auto_actions.add_child(toggle)
	auto_actions.add_child(collect)
	var key := World.key(cell)
	update_view = func(snapshot: Dictionary, person: Dictionary):
		var obj: Dictionary = snapshot.get("objects", {}).get(key, {})
		var job: Dictionary = obj.get("job", {})
		var busy := not job.is_empty()
		var owner: bool = obj.get("owner") == app.session.own_id
		var present: bool = obj.get("type") == kind
		var auto_enabled: bool = obj.get("auto_enabled", false)
		var auto_job: bool = job.get("auto", false)
		var input: int = obj.get(input_field, 0)
		var stored: int = obj.get("items", {}).get(id, 0)
		var wood: int = person.get("inventory", {}).get(input_item, 0)
		automatic.visible = present
		input_amount.text = "%s %d／%d" % [input_name, input, World.LOGISTICS.PROCESS_INPUT_CAP]
		output_amount.text = "%s %d／%d" % [World.NAMES[id], stored, World.LOGISTICS.PROCESS_OUTPUT_CAP]
		feed.disabled = not owner or input >= World.LOGISTICS.PROCESS_INPUT_CAP or wood == 0
		unload.disabled = not owner or input == 0
		collect.disabled = not owner or stored == 0
		toggle.disabled = not owner
		toggle.text = "停用自動加工" if auto_enabled else "啟用自動加工"
		if auto_job:
			auto_status.text = "本批完成後會存入產物庫。"
		elif not auto_enabled:
			auto_status.text = "自動加工已停用。"
		elif stored + int(recipe.yield) > World.LOGISTICS.PROCESS_OUTPUT_CAP:
			auto_status.text = "產物庫空間不足，請先領取。"
		else:
			auto_status.text = ("等待料槽%s。" % input_name) if input < int(recipe.ingredients.get(input_item, 0)) else "等待開始下一批。"
		actions.visible = (not busy and not auto_enabled) or (busy and not auto_job)
		start.visible = not busy and not auto_enabled
		claim.visible = busy and not auto_job
		cancel.visible = busy and not auto_job
		gauge.visible = busy
		ingredients.visible = not busy and not auto_enabled
		if not present:
			heading.text = "設備已移除"
			requirement.text = ""
			start.disabled = true
			return
		if busy:
			var seconds := maxf(0, float(job.ready) - float(snapshot.get("time", 0)))
			gauge.max_value = recipe.time
			gauge.value = maxf(0, float(recipe.time) - seconds)
			if auto_job:
				heading.text = "等待入庫" if seconds <= 0 else "自動加工 · 約剩 %d 秒" % ceili(seconds)
			else:
				heading.text = "完成，可以領取" if seconds <= 0 else "加工中 · 約剩 %d 秒" % ceili(seconds)
			requirement.text = "%s ×%d" % [World.NAMES[id], job.get("yield", recipe.yield)]
			claim.disabled = seconds > 0 or not owner
			cancel.disabled = not owner
			return
		var stock: Dictionary = person.get("inventory", {})
		var needs := PackedStringArray()
		var enough := true
		for item in recipe.ingredients:
			var held: int = stock.get(item, 0)
			var count: int = recipe.ingredients[item]
			needs.append("%s %d／%d" % [World.NAMES[item], held, count])
			enough = enough and held >= count
		heading.text = "%s ×%d · %d 秒" % [World.NAMES[id], recipe.yield, recipe.time]
		requirement.text = "持有／所需　" + "　".join(needs)
		if auto_enabled:
			heading.text = "自動加工 · 待開始"
			requirement.text = "%s %d → %s %d · %d 秒" % [input_name, recipe.ingredients.get(input_item, 0), World.NAMES[id], recipe.yield, recipe.time]
		start.disabled = not enough or not owner or auto_enabled
		if not owner:
			start.text = "由擁有者操作"
		elif auto_enabled:
			start.text = "先停用自動加工"
		else:
			start.text = "開始加工" if enough else "材料不足"
