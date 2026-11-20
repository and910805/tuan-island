extends RefCounted
const Layouts=preload("res://scripts/workshop_layouts.gd")
const GuideThumb=preload("res://scripts/workshop_layout_thumbnail.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const ThemeArt=preload("res://scripts/inventory_pixel_theme.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const DeviceArt=preload("res://scripts/logistics_ui.gd")
const World=preload("res://scripts/world.gd")
const HouseUI=preload("res://scripts/house_ui.gd")

## Motion plays unless the player asked for reduced motion or there is no display.
## QA meta `workshop_guide_motion` ("on"/"off") can force either way, except that
## a reduced-motion preference always wins over "on".
static func motion_enabled(app)->bool:
	var mode:String=str(app.get_meta("workshop_guide_motion","auto"))
	if mode=="off":return false
	if app.sound!=null and bool(app.sound.reduced_motion):return false
	if mode=="on":return true
	return DisplayServer.get_name()!="headless"

static func open(app,topic:int=-1,resume:Dictionary={})->void:
	if topic<0:topic=int(app.get_meta("workshop_guide_topic",0))
	topic=clampi(topic,0,Layouts.TITLES.size()-1)
	app.set_meta("workshop_guide_topic",topic)
	var lesson:=Layouts.lesson(topic)
	var steps:Array=lesson.guide
	var motion:bool=motion_enabled(app)
	var body:VBoxContainer=app._open_modal("工坊圖解")
	var modal:Control=app.modal
	if app.modal_feedback:app.modal_feedback.text="Esc 或手把 B 回到島上"
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
	# Left: the demonstration, playing from the first moment.
	var drawing:=Tasks.card(columns)
	drawing.add_theme_constant_override("separation",4)
	drawing.get_parent().custom_minimum_size.x=380
	drawing.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var viewport_height:int=int(app.get_viewport().get_visible_rect().size.y)
	var stage:=Control.new()
	stage.name="WorkshopDiagram"
	stage.custom_minimum_size=Vector2(356,clampi(viewport_height-360,180,276))
	drawing.add_child(stage)
	var thumbnail:=GuideThumb.new()
	thumbnail.name="WorkshopPreview"
	thumbnail.design=lesson.design
	thumbnail.markers=lesson.markers
	stage.add_child(thumbnail)
	var resize:=func():thumbnail.box_size=stage.size
	stage.resized.connect(resize)
	resize.call()
	var replay:Button=app.button("重播示範",func():thumbnail.replay())
	replay.name="WorkshopReplay"
	replay.tooltip_text="從頭再看一次" if motion else "已設定減少動態，改用靜態箭頭呈現"
	replay.disabled=not motion
	# Right: one action at a time.
	var current:=Tasks.card(columns)
	current.add_theme_constant_override("separation",4)
	current.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var progress:=Tasks.line(app,current,"",14)
	progress.name="WorkshopProgress"
	var heading:=Tasks.line(app,current,"",22)
	heading.name="WorkshopStepHeading"
	var text:=Tasks.line(app,current,"",16)
	text.name="WorkshopStepText"
	text.custom_minimum_size.y=64
	var nav:=HBoxContainer.new()
	current.add_child(nav)
	var prev:Button=app.button("上一步",func():pass)
	prev.name="WorkshopPrev"
	prev.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nav.add_child(prev)
	var next:Button=app.button("下一步",func():pass)
	next.name="WorkshopNext"
	next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nav.add_child(next)
	var next_style:=ThemeArt.texture_style("button_pressed",3,8)
	next.add_theme_stylebox_override("normal",next_style)
	next.add_theme_stylebox_override("hover",next_style)
	for state_name in ["font_color","font_hover_color","font_focus_color"]:
		next.add_theme_color_override(state_name,Color("fff3cf"))
	var pages:=HBoxContainer.new()
	current.add_child(pages)
	var page_buttons:Array[Button]=[]
	for page in steps.size():
		var turn:Button=app.button(str(page+1),func():pass)
		turn.name="WorkshopStep_%d"%page
		turn.tooltip_text="第 %d 步"%(page+1)
		turn.custom_minimum_size.x=44
		turn.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		turn.toggle_mode=true
		pages.add_child(turn)
		page_buttons.append(turn)
	var toggle:Button=app.button("備註與用料",func():pass)
	toggle.name="WorkshopDetailsToggle"
	toggle.toggle_mode=true
	# Always-visible recipe link and back.
	var actions:=HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(replay)
	var state:={"step":0,"kind":""}
	var build:Button=app.button("查看建造配方",func():
		app.life_panels.build_menu(app,str(state.kind),{"topic":topic,"step":state.step,"kind":state.kind,"details":toggle.button_pressed})
	)
	build.name="WorkshopBuild"
	actions.add_child(build)
	actions.add_child(toggle)
	var back:Button=app.button("回口袋指南",app._help)
	back.name="WorkshopBack"
	actions.add_child(back)
	var house_check:Button
	if topic==Layouts.FIRST_HOUSE:
		house_check=app.button("小屋結構檢查",func():HouseUI.open(app))
		house_check.name="WorkshopHouseCheck"
		actions.add_child(house_check)
	# Optional details: notes, piece picker, live materials.
	var details:=Tasks.card(body)
	details.get_parent().name="WorkshopDetails"
	details.get_parent().visible=false
	details.add_theme_constant_override("separation",4)
	var note:=Tasks.line(app,details,str(lesson.note),15)
	note.name="WorkshopNote"
	if not lesson.markers.is_empty():Tasks.line(app,details,"淡色圖示＝預留種植格，不是建築",14)
	var options:=HFlowContainer.new()
	options.add_theme_constant_override("h_separation",5)
	details.add_child(options)
	var kinds:Array[String]=[]
	for entry:Dictionary in lesson.design.pieces:
		if not kinds.has(str(entry.kind)):kinds.append(str(entry.kind))
	state.kind=kinds[0]
	var chosen:Label=app.label("",15)
	chosen.name="WorkshopSelected"
	details.add_child(chosen)
	var buttons:Dictionary={}
	var choose:=func(kind:String)->void:
		state.kind=kind
		thumbnail.selected_kind=kind
		thumbnail.queue_redraw()
		chosen.text="已選建材 · "+World.BUILD[kind].name
		build.text="查看建造配方：%s"%World.BUILD[kind].name
		for id in buttons:buttons[id].set_pressed_no_signal(id==kind)
	for kind:String in kinds:
		var choice:Button=app.button("",func():choose.call(kind))
		choice.name="WorkshopPiece_"+kind
		choice.icon=DeviceArt.device_icon(kind)
		if kind=="water_pump":choice.icon=ItemArt.icon("pump_kit")
		if kind=="water_tank":choice.icon=ItemArt.icon("tank_kit")
		if kind=="water_pipe":choice.icon=ItemArt.icon("pipe_kit")
		if kind=="sprinkler":choice.icon=ItemArt.icon("sprinkler_kit")
		if choice.icon==null:choice.text=World.BUILD[kind].name
		choice.tooltip_text=World.BUILD[kind].name
		choice.custom_minimum_size=Vector2(44,40)
		choice.expand_icon=true
		choice.add_theme_constant_override("icon_max_width",32)
		choice.toggle_mode=true
		options.add_child(choice)
		buttons[kind]=choice
	Tasks.line(app,details,"範例放置用料 · 背包／需要",14)
	var materials:=HFlowContainer.new()
	materials.name="WorkshopMaterials"
	materials.add_theme_constant_override("h_separation",12)
	details.add_child(materials)
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
	if not starter.is_empty():Tasks.line(app,details,"另備起動用料："+"、".join(starter),14).name="WorkshopStartup"
	if topic!=Layouts.FIRST_HOUSE:
		Tasks.line(app,details,"入門套件可向阿榆換取。" if topic==Layouts.STARTER_IRRIGATION else "套件先在工作台做，實際配方以建造目錄為準。",13)
	# Step navigation.
	var go:=func(index:int)->void:
		var at:int=clampi(index,0,steps.size()-1)
		state.step=at
		var data:Dictionary=steps[at]
		progress.text="第 %d／%d 步"%[at+1,steps.size()]
		heading.text=str(data.heading)
		var lines:=PackedStringArray()
		for line in data.lines:lines.append(str(line))
		text.text="\n".join(lines)
		thumbnail.show_step(lesson.design,data,motion)
		for position in page_buttons.size():page_buttons[position].set_pressed_no_signal(position==at)
		prev.disabled=at==0
		next.disabled=at==steps.size()-1
		if house_check:house_check.visible=at==steps.size()-1
		var focus:Array=data.get("focus",[])
		if not focus.is_empty():choose.call(str(focus[0]))
		var holder:Control=app.get_viewport().gui_get_focus_owner()
		if holder is Button and (holder as Button).disabled:
			if prev.disabled:next.grab_focus()
			else:prev.grab_focus()
	for page in page_buttons.size():page_buttons[page].pressed.connect(func():go.call(page))
	prev.pressed.connect(func():go.call(int(state.step)-1))
	next.pressed.connect(func():go.call(int(state.step)+1))
	toggle.toggled.connect(func(open_now:bool):
		details.get_parent().visible=open_now
		columns.visible=not open_now
		replay.visible=not open_now
		toggle.text="回到步驟" if open_now else "備註與用料"
		app._layout_preview()
	)
	go.call(int(resume.get("step",0)))
	var resumed_kind:=str(resume.get("kind",""))
	if buttons.has(resumed_kind):choose.call(resumed_kind)
	toggle.button_pressed=bool(resume.get("details",false))
	(func():
		if not is_instance_valid(modal) or app.modal!=modal:return
		var target:=toggle if toggle.button_pressed else (prev if next.disabled else next)
		target.grab_focus()
	).call_deferred()
	app._layout_preview()
