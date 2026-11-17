extends RefCounted
const Layouts=preload("res://scripts/workshop_layouts.gd")
const GuideThumb=preload("res://scripts/workshop_layout_thumbnail.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const ThemeArt=preload("res://scripts/inventory_pixel_theme.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const DeviceArt=preload("res://scripts/logistics_ui.gd")
const World=preload("res://scripts/world.gd")

static func open(app,topic:int=-1)->void:
	if topic<0:topic=int(app.get_meta("workshop_guide_topic",0))
	topic=clampi(topic,0,Layouts.TITLES.size()-1)
	app.set_meta("workshop_guide_topic",topic)
	var lesson:=Layouts.lesson(topic)
	var body:VBoxContainer=app._open_modal("工坊圖解")
	var modal:Control=app.modal
	modal.set_meta("life_modal_layout","workshop_guide")
	modal.theme=ThemeArt.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel",ThemeArt.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var tabs:=HBoxContainer.new()
	body.add_child(tabs)
	for index in Layouts.TITLES.size():
		var tab:Button=app.button(Layouts.TITLES[index],func():open(app,index))
		tab.name="WorkshopLesson_%d"%index
		tab.toggle_mode=true
		tab.set_pressed_no_signal(index==topic)
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	body.add_child(columns)
	var drawing:=Tasks.card(columns)
	drawing.add_theme_constant_override("separation",4)
	drawing.get_parent().custom_minimum_size.x=360
	drawing.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var stage:=Control.new()
	stage.name="WorkshopDiagram"
	stage.custom_minimum_size=Vector2(320,192)
	drawing.add_child(stage)
	var thumbnail:=GuideThumb.new()
	thumbnail.design=lesson.design
	thumbnail.markers=lesson.markers
	stage.add_child(thumbnail)
	var resize:=func():thumbnail.box_size=stage.size
	stage.resized.connect(resize)
	resize.call()
	var steps:=Tasks.card(columns)
	steps.add_theme_constant_override("separation",4)
	steps.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var step_title:=Tasks.line(app,steps,"照著接，一步一步來",19)
	var step_text:=Tasks.line(app,steps,"",15)
	step_text.name="WorkshopStepText"
	step_text.custom_minimum_size.y=88
	var pages:=HBoxContainer.new()
	steps.add_child(pages)
	var page_buttons:Array[Button]=[]
	for page in 5:
		var turn:Button=app.button(str(page+1) if page<4 else "備註",func():
			step_title.text="第 %d 步／4"%(page+1) if page<4 else "搭建前的小提醒"
			step_text.text=lesson.steps[page] if page<4 else lesson.note
			for index in page_buttons.size():page_buttons[index].set_pressed_no_signal(index==page)
		)
		turn.name="WorkshopStep_%d"%page
		turn.custom_minimum_size.x=40
		turn.toggle_mode=true
		pages.add_child(turn)
		page_buttons.append(turn)
	page_buttons[0].pressed.emit()
	Tasks.line(app,drawing,"淡色圖示＝預留種植格，不是建築",14)
	var options:=HFlowContainer.new()
	options.add_theme_constant_override("h_separation",5)
	drawing.add_child(options)
	var kinds:Array[String]=[]
	for entry:Dictionary in lesson.design.pieces:
		if not kinds.has(str(entry.kind)):kinds.append(str(entry.kind))
	var selected:={"kind":kinds[0]}
	var chosen:Label=app.label("",15)
	chosen.name="WorkshopSelected"
	drawing.add_child(chosen)
	var buttons:Dictionary={}
	for kind:String in kinds:
		var choice:Button=app.button("",func():
			selected.kind=kind
			thumbnail.selected_kind=kind
			thumbnail.queue_redraw()
			chosen.text=World.BUILD[kind].name+" · 在下方查看建造配方"
			for id in buttons:buttons[id].set_pressed_no_signal(id==kind)
		)
		choice.name="WorkshopPiece_"+kind
		choice.icon=DeviceArt.device_icon(kind)
		if kind=="water_pump":choice.icon=ItemArt.icon("pump_kit")
		if kind=="water_tank":choice.icon=ItemArt.icon("tank_kit")
		if kind=="water_pipe":choice.icon=ItemArt.icon("pipe_kit")
		if kind=="sprinkler":choice.icon=ItemArt.icon("sprinkler_kit")
		choice.tooltip_text=World.BUILD[kind].name
		choice.custom_minimum_size=Vector2(44,40)
		choice.expand_icon=true
		choice.add_theme_constant_override("icon_max_width",32)
		choice.toggle_mode=true
		options.add_child(choice)
		buttons[kind]=choice
	buttons[kinds[0]].pressed.emit()
	Tasks.line(app,steps,"範例放置用料 · 背包／需要",14)
	var materials:=HFlowContainer.new()
	materials.name="WorkshopMaterials"
	materials.add_theme_constant_override("h_separation",12)
	steps.add_child(materials)
	var bag:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{}).get("inventory",{})
	var costs:=Layouts.cost(topic)
	var cost_labels:Dictionary={}
	for item:String in costs:
		var cost:int=costs[item]
		var row:=HBoxContainer.new()
		row.tooltip_text=World.NAMES[item]
		materials.add_child(row)
		Tasks.add_icon(row,ItemArt.icon(item),32)
		var count:Label=app.label("%d／%d"%[int(bag.get(item,0)),cost],15)
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
		count.name="WorkshopCost_"+item
		row.add_child(count)
		cost_labels[item]=count
	var refresh:Callable=func(snapshot:Dictionary,owner:String):
		if not is_instance_valid(modal) or app.modal!=modal:return
		var inventory:Dictionary=snapshot.get("players",{}).get(owner,{}).get("inventory",{})
		for item in cost_labels:cost_labels[item].text="%d／%d"%[int(inventory.get(item,0)),int(costs[item])]
	app.session.changed.connect(refresh)
	modal.tree_exiting.connect(func():
		if is_instance_valid(app.session) and app.session.changed.is_connected(refresh):app.session.changed.disconnect(refresh)
	)
	var starter:=PackedStringArray()
	for item:String in lesson.startup:starter.append("%s ×%d"%[World.NAMES[item],int(lesson.startup[item])])
	Tasks.line(app,steps,"另備起動用料："+"、".join(starter),14).name="WorkshopStartup"
	Tasks.line(app,steps,"套件先在工作台做；實際配方以建造目錄為準。",13)
	var actions:=HBoxContainer.new()
	body.add_child(actions)
	var build:Button=app.button("查看這件建材",func():app.life_panels.build_menu(app,str(selected.kind)))
	build.name="WorkshopBuild"
	actions.add_child(build)
	var back:Button=app.button("回口袋指南",app._help)
	back.name="WorkshopBack"
	actions.add_child(back)
	app._layout_preview()
