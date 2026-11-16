extends RefCounted

const Life=preload("res://scripts/station_life.gd")
const Art=preload("res://scripts/station_life_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const NAMES={"toucheng":"頭城","ruifang":"瑞芳","jiufen":"九份"}

static func open(app,region:String)->void:
	if not Life.RESIDENTS.has(region):return
	var body:VBoxContainer=app._open_modal("在路上遇見的人")
	app.modal.set_meta("life_modal_layout","station_dialogue")
	app.modal.set_meta("station_body",body)
	app.modal.set_meta("station_region",region)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	# A conversation sits along the bottom; it does not need the generic
	# full-window heading above the resident's own portrait and name.
	if app.village_art_preview:
		var shell:VBoxContainer=body.get_parent().get_parent()
		shell.get_child(0).hide();shell.get_child(1).hide()
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.16
	refresh(app)

static func memory(app)->void:
	var body:VBoxContainer=app._open_modal("三站便箋 · 沿途的人")
	app.modal.set_meta("life_modal_layout","station_memory")
	app.modal.set_meta("station_body",body)
	app.modal.set_meta("station_region","memory")
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.20
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("station_body"):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var region:String=app.modal.get_meta("station_region")
	var stage:=int(Life.story(s,app.session.own_id).stage)
	var near:=false
	if Life.RESIDENTS.has(region):near=str(s.get("region_id","home"))==region and Vector2(person.x,person.y).distance_to(Vector2(Life.RESIDENTS[region].cell)+Vector2(0.5,0.5))<=3.2
	var signature:=JSON.stringify([stage,s.get("station_life",{}).get("repairs",{}),person.inventory,person.coins,person.get("travel_book",{}),near,s.get("picnic",false)])
	if app.modal.get_meta("station_signature","")==signature:return
	app.modal.set_meta("station_signature",signature)
	var body:VBoxContainer=app.modal.get_meta("station_body")
	var focus:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if region=="memory":
		memory_page(app,body,s,stage)
	else:
		dialogue(app,body,s,person,region,stage,near)
	if not focus_name.is_empty():
		var replacement=body.find_child(focus_name,true,false)
		if replacement is BaseButton and not replacement.disabled:replacement.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func dialogue(app,body:VBoxContainer,s:Dictionary,person:Dictionary,region:String,stage:int,near:bool)->void:
	var resident:Dictionary=Life.RESIDENTS[region]
	var entry:=Life.offer(s,app.session.own_id,region)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);body.add_child(row)
	var portrait:=VBoxContainer.new();portrait.custom_minimum_size.x=112;row.add_child(portrait)
	portrait.add_child(Shell.picture(Art.portrait(region),96))
	var name_label:=Helpers.text(app,portrait,resident.name,22);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var role:=Helpers.text(app,portrait,resident.role,14);role.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var words:=VBoxContainer.new();words.custom_minimum_size.x=300;words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;words.add_theme_constant_override("separation",12);row.add_child(words)
	var current_here:bool=stage<4 and Life.STAGES[stage].region==region
	var speech:String=str(entry.line) if current_here or stage==4 else str(resident.hello)
	var spoken:=Helpers.text(app,words,"「%s」"%speech,18);spoken.name="StationSpeech"
	Helpers.text(app,words,str(entry.title),16)
	if not current_here:
		var goal:=Helpers.text(app,words,str(entry.reason) if stage<4 else "這趟路線，已記在你的便箋裡。",14);goal.name="StationGoal"
		if stage==4:Helpers.text(app,words,"已收下謝禮：80 鈴幣 · 樹苗 ×1",14).name="StationRewardReceipt"
	if current_here:
		if stage==2:
			var bread:=HBoxContainer.new();words.add_child(bread);bread.add_child(Shell.picture(Items.icon("bread"),32))
			Helpers.text(app,bread,"小麥麵包 %d / 1"%int(person.inventory.get("bread",0)),15).name="StationBreadCount"
		if stage==3:Helpers.text(app,words,"謝禮：80 鈴幣 · 樹苗 ×1",14)
		var expected:=str(entry.extra)
		var advance:=Helpers.action(app,words,"StationStory",str(entry.action),func():app.session.perform("station_story",resident.cell,expected),near and entry.ready)
		advance.custom_minimum_size.y=40
		advance.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		advance.icon=Shell.icon("letter");advance.expand_icon=true;advance.add_theme_constant_override("icon_max_width",24)
		if not entry.ready:Helpers.text(app,words,str(entry.reason),14)
	var repair:=PanelContainer.new();repair.custom_minimum_size.x=210;repair.add_theme_stylebox_override("panel",Pixel.texture_style("life_paper",8,12));row.add_child(repair)
	var repair_body:=VBoxContainer.new();repair_body.add_theme_constant_override("separation",10);repair.add_child(repair_body)
	var repaired:bool=s.get("station_life",{}).get("repairs",{}).get(region,false)
	if repaired:
		repair_body.add_child(Shell.picture(Art.sprite(7),48))
		Helpers.text(app,repair_body,"%s的候車角落"%NAMES[region],16)
		Helpers.text(app,repair_body,"✓ 長椅修好了\n每個經過的人都能歇腳。",15).name="StationRepairDone"
	else:
		repair_body.add_child(Shell.picture(Art.sprite(6),48))
		Helpers.text(app,repair_body,"%s的候車角落"%NAMES[region],16)
		var materials:=HBoxContainer.new();materials.add_theme_constant_override("separation",8);repair_body.add_child(materials)
		var enough:bool=s.get("picnic",false)
		for item in Life.REPAIR_COST:
			materials.add_child(Shell.picture(Items.icon(item),32))
			var count:=int(person.inventory.get(item,0));var required:=int(Life.REPAIR_COST[item]);enough=enough and count>=required
			var amount:=Helpers.text(app,materials,"%d/%d"%[count,required],14);amount.name="StationMaterial_"+item
			amount.tooltip_text="木板" if item=="plank" else "石材"
		var button:=Helpers.action(app,repair_body,"StationRepair","動手修好長椅",func():app.session.perform("station_repair",resident.cell,region),near and enough);button.custom_minimum_size.y=40
	var footer:=HBoxContainer.new();footer.alignment=BoxContainer.ALIGNMENT_END;body.add_child(footer)
	Helpers.action(app,footer,"StationMemory","翻開三站便箋",func():memory(app))
	Helpers.action(app,footer,"StationLeave","先走囉 · Esc",app._close_modal)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="靠近%s再交談或修繕。"%resident.name if not near else "修繕由大家共用 · 故事與謝禮各自保存 · Esc 回到街上"

static func memory_page(app,body:VBoxContainer,s:Dictionary,stage:int)->void:
	var faces:=HBoxContainer.new();faces.add_theme_constant_override("separation",16);body.add_child(faces)
	for region in Life.RESIDENTS:
		var card:=HBoxContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;faces.add_child(card)
		card.add_child(Shell.picture(Art.portrait(region),96))
		var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_child(words)
		Helpers.text(app,words,Life.RESIDENTS[region].name,18)
		Helpers.text(app,words,NAMES[region],14)
		Helpers.text(app,words,"長椅已修好" if s.get("station_life",{}).get("repairs",{}).get(region,false) else "等一張好長椅",13)
	Helpers.text(app,body,"風鈴渡口 →（交通船・轉乘）→ 頭城 → 瑞芳 → 九份 → 金瓜石",15)
	var chapters:=GridContainer.new();chapters.columns=2;chapters.add_theme_constant_override("h_separation",24);chapters.add_theme_constant_override("v_separation",18);body.add_child(chapters)
	for index in range(Life.STAGES.size()):
		var entry:Dictionary=Life.STAGES[index]
		var completed:=index<stage
		var line:=VBoxContainer.new();line.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.custom_minimum_size.x=300;line.add_theme_constant_override("separation",6);chapters.add_child(line)
		Helpers.text(app,line,("✓ " if completed else ("› " if index==stage else "○ "))+str(entry.title),17)
		if completed:Helpers.text(app,line,str(entry.line),14)
		elif index==stage:Helpers.text(app,line,str(entry.goal)+" · "+NAMES[entry.region]+"找"+str(Life.RESIDENTS[entry.region].name),14)
	var footer:=HBoxContainer.new();footer.alignment=BoxContainer.ALIGNMENT_END;body.add_child(footer)
	Helpers.action(app,footer,"StationRouteMap","查看轉乘路線",app._travel_menu)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="原創居民故事 · 已完成 %d / 4 段 · 謝禮只領一次"%stage
