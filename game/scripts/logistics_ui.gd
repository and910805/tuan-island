extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const ARROWS := ["↑", "→", "↓", "←"]
const DEVICE_ICONS:={"forester":"forester_kit","conveyor":"conveyor_kit","sawmill":"sawmill_kit","charcoal_kiln":"kiln_kit","mill":"mill_kit","mine_drill":"mine_drill_kit","waterworks":"waterworks_kit"}
static var private_box_icon:AtlasTexture

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
	var preview:=HBoxContainer.new()
	preview.name="ConveyorRoutePreview"
	preview.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	preview.add_theme_constant_override("separation",10)
	route.add_child(preview)
	var previews:Array[TextureRect]=[]
	for index in 3:
		if index>0:plain_label(app,preview,"→",20)
		var picture:=TextureRect.new()
		picture.name=["ConveyorSourceIcon","ConveyorCargoIcon","ConveyorDestinationIcon"][index]
		picture.custom_minimum_size=Vector2(64,96)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		preview.add_child(picture)
		previews.append(picture)
	var compass := HBoxContainer.new()
	compass.add_theme_constant_override("separation",6)
	compass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	route.add_child(compass)
	var directions: Dictionary = {}
	for direction in 4:
		var arrow: Button = app.button(ARROWS[direction], func(): app.session.perform("configure_conveyor", cell, "dir:%d" % direction))
		arrow.toggle_mode = true
		arrow.custom_minimum_size = Vector2(52,42)
		arrow.tooltip_text=["朝北送出","朝東送出","朝南送出","朝西送出"][direction]
		compass.add_child(arrow)
		directions[direction] = arrow
	var endpoints := plain_label(app, route, "", 15)
	endpoints.name="ConveyorEndpoints"
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
	toggle.name="ConveyorToggle"
	unload.name="ConveyorUnload"
	unload.tooltip_text="手把 X 選取 · A 確認"
	controls.add_child(toggle)
	controls.add_child(unload)
	Tasks.line(app, body, "每 %d 秒移動一格。由後方接收，往前方送出。轉彎時，把下一段輸送帶轉向目的地。" % World.LOGISTICS.INTERVAL, 15)
	var advice:Label=app.label("",15)
	advice.name="ConveyorAdvice"
	advice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(advice)
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
		var destination := destination_status(objects, cell + offset, belt)
		endpoints.text = "來源　%s\n目的地　%s" % [source.text, destination.text]
		previews[0].texture=device_icon(str(source.get("kind","")))
		previews[1].texture=ItemArt.icon(item)
		previews[2].texture=device_icon(str(objects.get(World.key(cell+offset),{}).get("type","")))
		previews[0].tooltip_text="來源 · "+str(source.text)
		previews[1].tooltip_text=World.NAMES[item]
		previews[2].tooltip_text="目的地 · "+str(destination.text)
		previews[0].modulate=Color.WHITE if source.ready else Color(1,1,1,0.45)
		previews[2].modulate=Color.WHITE if destination.ready else Color(1,1,1,0.45)
		advice.text=operation_advice(objects,cell,belt,owner) if present else "設備已移除，請回到島上。"
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

func focus_primary(app) -> bool:
	if not is_instance_valid(modal) or app.modal!=modal:return false
	refresh(app)
	for id in ["ConveyorUnload","ConveyorToggle"]:
		var action:=modal.find_child(id,true,false) as Button
		if not is_instance_valid(action) or action.disabled or not action.is_visible_in_tree():continue
		action.grab_focus()
		var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
		if scroll!=null:scroll.ensure_control_visible(action)
		break
	return true

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
		if int(rear.items.get(item, 0)) > 0:return {"text": name, "ready": true,"kind":kind}
		if incoming == 0:return {"text": name + "沒有指定物品", "ready": false,"kind":kind}
	if incoming > 0:
		return {"text": "接入輸送帶 %d 段%s" % [incoming, "" if loaded else "（等待物品）"], "ready": loaded,"kind":"conveyor"}
	return {"text": "未接通來源", "ready": false}

static func destination_status(objects: Dictionary, cell: Vector2i, belt: Dictionary) -> Dictionary:
	var object: Dictionary = objects.get(World.key(cell), {})
	var reason:=World.LOGISTICS.delivery_block(belt,object,object)
	if not reason.is_empty():return {"text": reason, "ready": false}
	var kind: String = object.get("type", "")
	if kind in World.LOGISTICS.PROCESSORS and not object.get("auto_enabled",false):
		return {"text":World.BUILD[kind].name+"（只入料，自動加工未啟用）","ready":true}
	return {"text": World.BUILD[kind].name, "ready": true}

static func device_icon(kind:String)->Texture2D:
	if DEVICE_ICONS.has(kind):return ItemArt.icon(DEVICE_ICONS[kind])
	if kind=="private_chest":
		if private_box_icon==null:
			private_box_icon=AtlasTexture.new()
			private_box_icon.atlas=preload("res://assets/ui-life/furniture.png")
			private_box_icon.region=Rect2(32,96,32,48)
			private_box_icon.filter_clip=true
		return private_box_icon
	return null

static func operation_advice(objects:Dictionary,cell:Vector2i,belt:Dictionary,owned:bool=true)->String:
	if not owned:return "這段輸送帶由擁有者設定；物品只會送入同一位主人的設備。"
	var item:String=belt.get("filter","wood")
	var amount:=int(belt.get("items",{}).get(item,0))
	if not belt.get("enabled",false):return "先取回帶上物品，清空後就能調整方向與篩選。" if amount>0 else "選好方向與物品後啟用；箭頭後方接來源，前方接收貨設備。"
	var offset:Vector2i=World.LOGISTICS.DIRECTIONS[int(belt.get("dir",0))]
	var front:Dictionary=objects.get(World.key(cell+offset),{})
	var reason:=World.LOGISTICS.delivery_block(belt,front,front)
	if amount>0 and reason==World.BOX_CAPACITY.BELT_FULL:return "前方私人箱 16 格都有東西；先取空一格，或改送箱內已有的物品，帶上的物品會保留。"
	if amount>0 and not reason.is_empty():
		match reason:
			"前方進料槽已滿":return "到前方加工台啟用自動加工，或取回進料騰出空間；帶上的物品會保留。"
			"前方燃料槽已滿":return "等前方設備消耗木炭後會繼續送；不需要拆除輸送帶。"
			"前方儲物箱已滿":return "先取走前方私人箱的物品，騰出空間後會繼續送。"
			"前方輸送帶已停用":return "啟用前方輸送帶，這格保留的物品就能繼續走。"
			"前方篩選不同":return "停用並清空前方輸送帶，將它的篩選改成%s。"%World.NAMES[item]
			"前方輸送帶有貨":return "沿路查看前方輸送帶，先處理最前端的堵塞；物品不會消失。"
			"前方是其他島民的設備":return "改接自己的設備；輸送帶不會把材料送進其他島民的庫存。"
			_:return "確認箭頭前方接上能收%s的設備，或停用後取回物品再改方向。"%World.NAMES[item]
	var source:=source_status(objects,cell,offset,str(belt.get("owner","")),item)
	if amount==0 and not source.ready:
		var rear:Dictionary=objects.get(World.key(cell-offset),{})
		var kind:String=rear.get("type","")
		if rear.get("owner","")==belt.get("owner","") and kind==str(source.get("kind","")):
			if kind=="forester":
				if not World.FORESTRY.OUTPUT.has(item):return "林務站只產木材、纖維及樹脂；先停用這段帶，再改篩選或改接來源。"
				return "到後方林務站檢查供料與作業格，啟用後等樹木成熟採伐。"
			if kind in World.LOGISTICS.PROCESSORS:
				var output:=World.LOGISTICS.output_item(kind)
				if item!=output:return "後方%s產出%s；先停用這段帶，再改篩選或改接來源。"%[World.BUILD[kind].name,World.NAMES[output]]
				if not rear.get("auto_enabled",false):return "後方加工台需使用自動模式才會把成品放入設備；手動加工成品由背包領取。"
				if rear.has("job"):return "後方正在加工，完成後會把成品送上這段帶。"
				return "後方自動加工尚未產出；檢查進料是否足夠，下一批完成就會送出。"
			if kind=="private_chest":return "把%s放進後方私人箱，輸送帶會自動取出。"%World.NAMES[item]
		if source.get("kind","")=="conveyor":return "沿後方接入的輸送帶查看來源，等待前一段送來%s。"%World.NAMES[item]
		return "在箭頭後方接自己的供貨設備，或讓另一段輸送帶朝這一格送貨。"
	if front.get("type","") in World.LOGISTICS.PROCESSORS and not front.get("auto_enabled",false) and reason.is_empty():return "前方加工台目前只收料；到設備頁啟用自動加工，才會繼續製作成品。"
	return "每%d秒檢查一次，物品逐段前進；前方滿了會保留在原處。"%World.LOGISTICS.INTERVAL
