extends RefCounted

const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
const Art=preload("res://scripts/tea_ceramics_art.gd")
const Residents=preload("res://scripts/tea_resident_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const Revisit=preload("res://scripts/tea_revisit_ui.gd")
const TITLES:={"home":"小栗的茶單與回收","journal":"第二章・茶陶合作手帳","host":"茶茶的合作茶園","potter":"陶師的工作桌","clay":"備土台","kiln":"製罐窯","pick":"茶叢","roast":"茶葉烘焙台","pack":"包裝與寄運"}
const JAR_NAMES:={"tea_jar":"新罐","tea_returned_jar":"回收罐","tea_worn_jar":"磨損罐","tea_spent_jar":"待修罐"}
const JAR_ORDER:=["tea_worn_jar","tea_returned_jar","tea_jar"]
const WORKSHOP_ART=preload("res://assets/tea-ceramics/buildings.png")
const CREAM:=Color("f9e8be")
const LINEN:=Color("e2cea9")
const GOLD:=Color("f0bb72")

static func unlocked(snapshot:Dictionary)->bool:
	return World.CHAPTER_ONE.phase(snapshot)=="complete"

static func interaction_points(region:String)->Dictionary:
	var points:Dictionary={}
	var sites:=View.tea_points(region)
	for cell:Vector2i in sites:points["tea:"+sites[cell]]=Vector2(cell)+Vector2(0.5,0.5)
	return points

static func open(app,site:String,cell:=Vector2i.ZERO)->void:
	var body:VBoxContainer=app._open_modal(TITLES[site])
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","tea_ceramics")
	app.modal.set_meta("tea_body",body)
	app.modal.set_meta("tea_site",site)
	app.modal.set_meta("tea_cell",cell)
	if site in ["host","potter","kiln"]:
		app.modal.set_meta("tea_width",584.0 if site=="kiln" else 640.0)
		app.modal.set_meta("tea_dialogue",site!="kiln")
		if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
		var shell:=app.modal.get_child(0) as VBoxContainer
		if shell:
			shell.add_theme_constant_override("separation",6)
			for child in shell.get_children():
				if child is HSeparator:child.hide()
			var title:=shell.get_child(0).get_child(0) as Label
			if title:title.add_theme_font_size_override("font_size",24)
	refresh(app)
	app._layout_preview.call_deferred()

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("tea_body"):return
	var snapshot:Dictionary=app.session.snapshot
	var actor:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var record:Dictionary=snapshot.get("tea_ceramics",{}).get("own_record",World.TEA_CERAMICS.FRESH)
	var now:=float(snapshot.get("time",0))
	var tea=World.TEA_CERAMICS
	var site:String=app.modal.get_meta("tea_site")
	var cell:Vector2i={"home":tea.RECEIVER,"host":tea.TEA_NPC,"potter":tea.POTTER,"clay":tea.CLAY,"kiln":tea.KILN,"roast":tea.ROASTER,"pack":tea.PACKER}.get(site,app.modal.get_meta("tea_cell"))
	var region:="home" if site=="home" else ("yingge" if site in ["potter","clay","kiln"] else "maokong")
	var nearby:bool=str(snapshot.get("region_id","home"))==region and not actor.is_empty() and Vector2(actor.x,actor.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2
	var bag:Dictionary=actor.get("inventory",{})
	var intro:bool=record.get("intro",false)
	var chapter_complete:=unlocked(snapshot)
	var remaining:Dictionary={}
	for job in ["kiln","roast","outbound","returning"]:
		remaining[job]=maxi(0,ceili(float(record.get(job,{}).get("ready",0))-now))
	remaining.clay=maxi(0,ceili(float(record.clay_ready)-now))
	remaining.pick=maxi(0,ceili(float(record.harvest_ready.get(str(tea.TEA_NODES.find(cell)),0))-now))
	var choice:String=app.modal.get_meta("tea_choice","")
	var fingerprint:=JSON.stringify([record,bag,remaining,nearby,chapter_complete,choice,snapshot.get("resident_memories",[]), snapshot.get("resident_participation",{}),snapshot.get("tea_revisit",{})])
	if app.modal.get_meta("tea_fingerprint","")==fingerprint:return
	app.modal.set_meta("tea_fingerprint",fingerprint)
	var height:=318.0
	if site=="journal":height=530.0 if record.get("comparison_complete",false) else 475.0  # 第 40 章：完成比較後多一行茶罐大單進度
	elif site=="home" and intro:height=430.0
	elif site=="kiln":height=418.0 if intro and record.kiln.is_empty() else 278.0
	elif site=="pack":height=520.0 if not record.returning.is_empty() else 410.0
	elif site=="host":height=(310.0 if record.get("comparison_complete",false) else 334.0) if intro else 294.0
	elif site=="potter":height=296.0
	elif site=="roast" and record.roast.is_empty():height=410.0
	app.modal.set_meta("tea_height",height)
	# 第 40 章：包裝台頁底部多了「茶罐大單」入口，加寬一點讓整列按鈕放得下。
	if site=="pack" and intro:app.modal.set_meta("tea_width",600.0)
	var body:VBoxContainer=app.modal.get_meta("tea_body")
	var focus:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var card:=PanelContainer.new()
	var workbench:=site in ["host","potter","kiln"]
	if workbench:
		var color:=Color("3a3028") if site=="kiln" else Color("394333")
		card.add_theme_stylebox_override("panel",surface(color,Color("9d7549"),12))
	else:card.add_theme_stylebox_override("panel",Pixel.paper_style())
	body.add_child(card)
	var page:=VBoxContainer.new()
	page.add_theme_constant_override("separation",8)
	card.add_child(page)
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	var perform:=func(id:String,title:String,action:String,ready:bool,extra:=""):
		Helpers.action(app,actions,id,title,func():app.session.perform(action,cell,extra),ready and nearby)
	var can_work:=intro and nearby
	if site=="host" or site=="potter":
		conversation(app,page,site,record,bag,nearby,perform)
		app._resident_story_dialogue(page,"chacha" if site=="host" else "yingge_potter")
	elif site=="kiln":
		kiln(app,page,actions,record,bag,remaining.kiln,nearby,cell)
	elif not intro:
		item_line(app,page,"wrapped_jar","小栗的介紹信","還記得我說想借陶罐帶湯嗎？先請鶯歌陶師教你製罐，再從貓空寄一批茶來。空罐回到茶園後，我們就知道下次怎麼用同一只罐帶湯了。")
		if site=="home":perform.call("TeaIntro","收下介紹信","tea_intro",chapter_complete)
		elif site=="journal":
			item_line(app,page,"tea_leaf","先到小栗的小店","第一章完成後，靠近小栗並從茶單收下介紹信。")
			Helpers.action(app,actions,"TeaHome","小栗的茶單",func():open(app,"home"),true)
	elif site=="journal":
		journal(app,page,record,remaining)
		Helpers.action(app,actions,"TeaMap","查看路線",app._map_menu,true)
	elif site=="home":
		var outbound:Dictionary=record.get("outbound",{})
		var empties:=int(record.get("empties",0))
		var returning:Dictionary=record.get("returning",{})
		var tea_ready:=not outbound.is_empty() and int(remaining.outbound)==0
		item_line(app,page,wrap_icon(outbound),"到貨", "等待茶園寄件" if outbound.is_empty() else (wrap_label(outbound)+" · 已到貨" if tea_ready else "運送中 · %d 秒"%remaining.outbound))
		if tea_ready:perform.call("TeaSell","交給小栗 · %d 鈴幣"%tea.price_for(outbound.style,outbound.wrap),"tea_sell",can_work)
		item_line(app,page,"tea_jar","回收空罐","待寄回 %d 個"%empties if returning.is_empty() else ("已送達茶園" if remaining.returning==0 else "回程 %d 秒"%remaining.returning))
		jar_counts(app,page,record.get("empty_items",{}) if returning.is_empty() else returning.get("items",{}))
		if empties>0:perform.call("TeaReturn","寄回空罐","tea_return",can_work and returning.is_empty())
		if record.get("reused",false):
			var active:bool=record.get("auto",false)
			perform.call("TeaAuto","關閉自動寄回空罐" if active else "開啟自動寄回空罐","tea_auto",can_work,"off" if active else "on")
		else:Helpers.text(app,page,"首輪由你寄回空罐，再到茶園領取，即可開啟自動寄回。")
	elif site=="clay":
		item_line(app,page,"clay","兩份石材換一份黏土","石材 %d · 黏土 %d"%[bag.get("stone",0),bag.get("clay",0)])
		perform.call("TeaClay","交換黏土" if remaining.clay==0 else "補貨中 · %d 秒"%remaining.clay,"tea_clay",can_work and record.potter and remaining.clay==0 and int(bag.get("stone",0))>=2)
	elif site=="pick":
		item_line(app,page,"tea_leaf","採下茶葉","目前有 %d 份茶葉。兩份可烘焙一份茶。"%bag.get("tea_leaf",0))
		perform.call("TeaPick","採茶" if remaining.pick==0 else "新葉生長中 · %d 秒"%remaining.pick,"tea_pick",can_work and remaining.pick==0)
	elif site=="roast":
		var roast:Dictionary=record.get("roast",{})
		if roast.is_empty():
			item_line(app,page,"tea_leaf","兩份茶葉烘焙一份茶","茶葉 %d · 淺焙 8 秒 · 深焙 12 秒"%bag.get("tea_leaf",0))
			var cards:=HBoxContainer.new()
			cards.add_theme_constant_override("separation",8)
			page.add_child(cards)
			for style in ["light","deep"]:
				var id:="TeaLight" if style=="light" else "TeaDeep"
				var title:="淺焙" if style=="light" else "深焙"
				option(app,cards,id,"tea_"+style,title,"%d 秒 · 纖維包 %d 鈴幣"%[tea.ROAST_SECONDS[style],tea.price_for(style,"fiber")],can_work and int(bag.get("tea_leaf",0))>=2,choice==style,func():app.session.perform("tea_roast",cell,style))
		else:
			item_line(app,page,"tea_"+str(roast.style),"淺焙茶" if roast.style=="light" else "深焙茶","可以起鍋" if remaining.roast==0 else "烘焙中 · %d 秒"%remaining.roast)
			perform.call("TeaTake","取茶","tea_take",can_work and remaining.roast==0)
	elif site=="pack":
		var packed:Dictionary=record.get("packed",{})
		var outbound:Dictionary=record.get("outbound",{})
		var returning:Dictionary=record.get("returning",{})
		var has_tea:=int(bag.get("tea_light",0))+int(bag.get("tea_deep",0))>0
		var jar_count:=0
		var next_jar:=""
		for id:String in JAR_ORDER:
			jar_count+=int(bag.get(id,0))
			if next_jar.is_empty() and int(bag.get(id,0))>0:next_jar=id
		item_line(app,page,wrap_icon(packed),"茶包裝","陶罐 %d · 纖維 %d"%[jar_count,bag.get("fiber",0)] if packed.is_empty() else wrap_label(packed)+" · 已包好")
		if packed.is_empty():
			var both:=int(bag.get("tea_light",0))>0 and int(bag.get("tea_deep",0))>0
			var style:String=app.modal.get_meta("tea_pack_style","light") if both else ("deep" if int(bag.get("tea_deep",0))>0 else "light")
			if both:
				var grades:=HBoxContainer.new()
				page.add_child(grades)
				for grade in ["light","deep"]:
					var grade_button:=Helpers.action(app,grades,"TeaPackStyle_"+grade,"淺焙" if grade=="light" else "深焙",func():
						app.modal.set_meta("tea_pack_style",grade)
						app.modal.remove_meta("tea_fingerprint")
						refresh(app)
					,true)
					grade_button.toggle_mode=true
					grade_button.set_pressed_no_signal(style==grade)
				app.modal.set_meta("tea_height",570.0 if not returning.is_empty() else 450.0)
			var cards:=HBoxContainer.new()
			cards.add_theme_constant_override("separation",8)
			page.add_child(cards)
			var can_jar:=can_work and has_tea and jar_count>0
			var can_fiber:=can_work and has_tea and int(bag.get("fiber",0))>0
			var base:int=tea.price_for(style,"fiber")
			var jar_detail:="沒有可用罐" if int(bag.get("tea_spent_jar",0))==0 else "待修罐需先修補"
			if not next_jar.is_empty():
				var uses:int=tea.JAR_USES[next_jar]
				jar_detail="%s ×1 · 送後剩 %d 次"%[JAR_NAMES[next_jar],uses-1] if uses>1 else "磨損罐 ×1 · 安全送達，送後 0 次"
			option(app,cards,"TeaPackJar","wrapped_jar","陶罐包裝","%d 基礎 + 12 包裝 = %d 鈴幣\n%s"%[base,tea.price_for(style,"jar"),jar_detail],can_jar,choice=="jar",func():choose(app,"jar"))
			option(app,cards,"TeaPackFiber","fiber_packet","纖維包裝","%d 基礎 + 0 包裝 = %d 鈴幣\n消耗 1 份纖維"%[base,base],can_fiber,choice=="fiber",func():choose(app,"fiber"))
			perform.call("TeaPackConfirm","確認包裝","tea_pack",(choice=="jar" and can_jar) or (choice=="fiber" and can_fiber),style+":"+choice)
		else:perform.call("TeaShip","寄給小栗","tea_ship",can_work and outbound.is_empty())
		if not outbound.is_empty():Helpers.text(app,page,"寄往渡口 · %d 秒"%remaining.outbound if remaining.outbound>0 else "已送達渡口，請小栗收貨。")
		if not returning.is_empty():
			item_line(app,page,"tea_jar","回程陶罐","可領取 %d 個"%returning.count if remaining.returning==0 else "回程中 · %d 秒"%remaining.returning)
			jar_counts(app,page,returning.get("items",{}))
			perform.call("TeaReclaim","領回陶罐","tea_reclaim",can_work and remaining.returning==0)
	if site=="host":
		Helpers.action(app,actions,"BondOpen","和茶茶聊聊",app._resident_bond_menu.bind("chacha"),true)
	if site!="journal":
		Helpers.action(app,actions,"TeaJournal","翻閱茶陶手帳",func():open(app,"journal"),true)
	# 第 40 章貓空與鶯歌回訪：陶師工作桌與包裝台多一顆「茶罐大單」入口（收下介紹信之後）。
	if site in ["potter","pack"] and intro:actions.add_child(Revisit.entry_button(app,site))
	if actions.get_child_count()>0:page.add_child(actions)
	else:actions.free()
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="請靠近工作點再操作。" if site!="journal" and not nearby else ("Esc 回到島上" if workbench else "茶陶合作 · 進度隨島民存檔保存")
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if workbench and (not next or next.disabled):
			for button:BaseButton in body.find_children("*","BaseButton",true,false):
				if not button.disabled:
					next=button
					break
		if next and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func surface(fill:Color,border:Color,inset:int)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(2)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_content_margin(side,inset)
	return style

static func workshop_text(app,parent:Control,value:String,font_size:int,tint:Color=CREAM)->Label:
	var label:=Helpers.text(app,parent,value,font_size)
	label.add_theme_color_override("font_color",tint)
	return label

static func workshop_picture(index:int,extent:int)->TextureRect:
	var texture:=AtlasTexture.new()
	texture.atlas=WORKSHOP_ART
	texture.region=Rect2(index*128,0,128,128)
	texture.filter_clip=true
	return Shell.picture(texture,extent)

static func conversation(app,page:VBoxContainer,site:String,record:Dictionary,bag:Dictionary,nearby:bool,perform:Callable)->void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	page.add_child(row)
	var host:=site=="host"
	var art:=Shell.picture(Residents.portrait(site),128)
	art.name="TeaResidentPortrait"
	art.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",5)
	row.add_child(words)
	workshop_text(app,words,"茶茶" if host else "陶師",18,GOLD)
	if not record.intro:
		workshop_text(app,words,"先向渡口的小栗收下介紹信。" if host else "帶著小栗的介紹信來，我會拿兩份試作黏土給你。",16)
		return
	if host:
		var line:="各寄一批陶罐茶和纖維茶，等小栗收貨，再把空罐領回來。"
		if record.comparison_complete:
			line="我會留幾個罐給常往返的茶單。只寄這一趟時，纖維包也方便。"
		elif World.TEA_CERAMICS.comparison_ready(record):
			line="兩批茶都送到了，空罐也回來了。你覺得這兩種包裝用起來怎麼樣？"
			perform.call("TeaDiscuss","比較兩種包裝","tea_discuss",nearby)
		elif not record.tea_discussed:
			line="想替小栗試寄一批茶嗎？南邊採兩份葉子就能烘一批。來聊聊怎麼裝。"
			perform.call("TeaDiscuss","聊聊怎麼包裝","tea_discuss",nearby)
		elif record.trials.jar and record.trials.fiber:
			line="兩批茶都送到了。等空罐回到茶園，領回來再和我聊聊。"
		workshop_text(app,words,line,16)
		var trials:=HBoxContainer.new()
		trials.add_theme_constant_override("separation",8)
		words.add_child(trials)
		for wrap:String in ["jar","fiber"]:
			trials.add_child(Shell.picture(Art.icon(wrap_icon({"wrap":wrap})),32))
			var kind:="陶罐" if wrap=="jar" else "纖維"
			var delivery:="已配送" if record.trials.get(wrap,false) else "待試寄"
			var status:=workshop_text(app,trials,"%s %s"%[kind,delivery],14,LINEN)
			status.name="TeaTrial_"+wrap
			status.autowrap_mode=TextServer.AUTOWRAP_OFF
	else:
		var line:="新罐能裝三趟。第三趟回來，把待修罐和一份黏土帶到窯邊，我們再補一補。"
		if not record.potter:
			var has_room:=int(bag.get("clay",0))<=World.TEA_CERAMICS.LIMIT-2
			line="先拿這兩份黏土，到窯邊就能燒第一只罐。"
			perform.call("TeaPotter","領取兩份黏土","tea_potter",has_room)
			if not has_room:line="黏土已達背包上限，騰出兩份黏土的空間再來領。"
		elif not record.potter_story:
			line="試作的黏土你已經領了。下回缺土，就帶兩份石材去備土台換一份。"
			perform.call("TeaPotterStory","請教如何修罐","tea_potter_story",true)
		workshop_text(app,words,line,16)

static func kiln(app,page:VBoxContainer,actions:HBoxContainer,record:Dictionary,bag:Dictionary,seconds:int,nearby:bool,cell:Vector2i)->void:
	var tea=World.TEA_CERAMICS
	var firing:Dictionary=record.kiln
	var idle:=firing.is_empty()
	var repair:bool=firing.get("repair",false)
	var ready:=not idle and seconds==0
	var headline:="窯火已熄，可以取罐" if ready else ("補罐中" if repair else "燒罐中")
	var detail:="修好的罐可再用三趟。" if repair else "新罐可用三趟。"
	if idle:
		headline="窯已空，可以備料"
		detail="燒製或修補需 %d 秒，每次入窯一只。"%tea.KILN_SECONDS
		if not record.intro:
			headline="先去找小栗"
			detail="收下介紹信後，再向鶯歌陶師領取試作黏土。"
	var flow:=HBoxContainer.new()
	flow.name="TeaKilnFlow"
	flow.add_theme_constant_override("separation",10)
	page.add_child(flow)
	flow.add_child(workshop_picture(2,96))
	var state:=VBoxContainer.new()
	state.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	state.alignment=BoxContainer.ALIGNMENT_CENTER
	state.add_theme_constant_override("separation",6)
	flow.add_child(state)
	workshop_text(app,state,headline,18,GOLD)
	if not idle:
		var inputs:="待修罐 ×1 ＋ 黏土 ×1" if repair else "黏土 ×2"
		workshop_text(app,state,"%s → 陶罐 ×1"%inputs,14,LINEN)
		var progress:=ProgressBar.new()
		progress.name="TeaKilnProgress"
		progress.show_percentage=false
		progress.max_value=tea.KILN_SECONDS
		progress.value=tea.KILN_SECONDS-seconds
		progress.custom_minimum_size.y=10
		progress.add_theme_stylebox_override("background",surface(Color("211d18"),Color("68503c"),0))
		progress.add_theme_stylebox_override("fill",surface(Color("d69251") if not ready else Color("88a765"),Color("dabc83"),0))
		state.add_child(progress)
		if seconds>0:detail="剩 %d 秒"%seconds
		elif int(bag.get("tea_jar",0))>=tea.LIMIT:detail="陶罐已達背包上限，騰出空間才能取罐。"
		var output:=Shell.picture(Art.icon("tea_jar"),64)
		output.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		if not ready:output.modulate=Color(1,1,1,0.50)
		flow.add_child(output)
	workshop_text(app,state,detail,14,LINEN).name="TeaKilnStatus"
	if not record.intro:return
	if not idle:
		var take:=Helpers.action(app,actions,"TeaFireTake","取出陶罐",func():app.session.perform("tea_fire_take",cell),nearby and ready and int(bag.get("tea_jar",0))<tea.LIMIT)
		take.tooltip_text="請靠近製罐窯。" if not nearby else detail
		return
	var recipes:=HBoxContainer.new()
	recipes.add_theme_constant_override("separation",8)
	page.add_child(recipes)
	var clay:=int(bag.get("clay",0))
	var spent:=int(bag.get("tea_spent_jar",0))
	var unlock:="先向陶師領黏土" if not record.potter else ""
	var fire_block:=unlock
	var repair_block:=unlock
	if unlock.is_empty():
		if clay<2:fire_block="還缺 %d 份黏土"%(2-clay)
		if spent==0 and clay==0:repair_block="缺待修罐與黏土"
		elif spent==0:repair_block="需要一只待修罐"
		elif clay==0:repair_block="還缺 1 份黏土"
	var fire:=kiln_recipe(app,recipes,"TeaFire","開始燒製",["clay"],"黏土 %d／2"%clay,fire_block,nearby,func():app.session.perform("tea_fire",cell))
	var mend:=kiln_recipe(app,recipes,"TeaRepair","修補陶罐",["tea_spent_jar","clay"],"待修罐 %d／1　黏土 %d／1"%[spent,clay],repair_block,nearby,func():app.session.perform("tea_repair",cell))
	fire.accessibility_name="開始燒製 · 兩份黏土製成一只可用三趟的陶罐"
	mend.accessibility_name="修補陶罐 · 一只待修罐加一份黏土，修好後可再用三趟"

static func kiln_recipe(app,parent:HBoxContainer,id:String,title:String,items:Array,stock:String,reason:String,nearby:bool,callback:Callable)->Button:
	var panel:=PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",surface(Color("4b3a30"),Color("876348"),7))
	parent.add_child(panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	panel.add_child(column)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",2)
	column.add_child(row)
	for item:String in items:row.add_child(Shell.picture(Art.icon(item),32))
	var outcome:=workshop_text(app,row,"→",14,LINEN)
	outcome.autowrap_mode=TextServer.AUTOWRAP_OFF
	outcome.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	row.add_child(Shell.picture(Art.icon("tea_jar"),32))
	workshop_text(app,column,stock,14)
	var status:=reason if not reason.is_empty() else ("出窯後可用三趟" if nearby else "請靠近製罐窯")
	workshop_text(app,column,status,13,GOLD if not reason.is_empty() or not nearby else LINEN).name=id+"Reason"
	var action:=Helpers.action(app,column,id,title,callback,nearby and reason.is_empty())
	action.tooltip_text=status
	return action

static func item_line(app,parent:Control,item:String,title:String,detail:String)->void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	parent.add_child(row)
	var texture:=Art.icon(item)
	if not texture:texture=Shell.icon("journal")
	row.add_child(Shell.picture(texture,32))
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(words)
	Helpers.text(app,words,title,18)
	Helpers.text(app,words,detail,15)

static func journal(app,parent:Control,record:Dictionary,remaining:Dictionary)->void:
	var roast:Dictionary=record.get("roast",{})
	var outbound:Dictionary=record.get("outbound",{})
	var returning:Dictionary=record.get("returning",{})
	item_line(app,parent,"tea_leaf","貓空茶園","採葉、烘焙與包裝。" if roast.is_empty() else ("烘焙可取茶" if remaining.roast==0 else "烘焙剩 %d 秒"%remaining.roast))
	item_line(app,parent,"tea_jar","鶯歌陶坊","陶師已提供黏土，可到窯邊製罐。" if record.get("potter",false) else "和陶師聊聊，領兩份黏土。")
	item_line(app,parent,wrap_icon(outbound),"渡口茶單","尚無寄件" if outbound.is_empty() else ("小栗可以收貨" if remaining.outbound==0 else "運送中 · %d 秒"%remaining.outbound))
	var reuse:="空罐待寄回 %d 個"%int(record.get("empties",0))
	if not returning.is_empty():reuse="茶園可領回空罐" if remaining.returning==0 else "回程中 · %d 秒"%remaining.returning
	if record.get("reused",false):reuse+=" · 已用回收罐送達 %d 次"%int(record.get("reuse_count",0))
	item_line(app,parent,"tea_jar","空罐回程",reuse)
	comparison(app,parent,record.get("trials",{}))
	if record.get("comparison_complete",false):
		Helpers.text(app,parent,"茶茶已記下兩種包裝的配送比較。")
		# 第 40 章貓空與鶯歌回訪：茶罐大單的進度（與波波頁的礦料調度行同一種寫法）。
		var revisit_line:=Revisit.journal_line(app.session.snapshot)
		if not revisit_line.is_empty():Helpers.text(app,parent,revisit_line,15).name="TeaRevisitLine"

static func comparison(app,parent:Control,trials:Dictionary)->void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	for wrap in ["jar","fiber"]:
		row.add_child(Shell.picture(Art.icon(wrap_icon({"wrap":wrap})),32))
		var status:=Helpers.text(app,row,("%s %s"%["陶罐" if wrap=="jar" else "纖維", "已配送" if trials.get(wrap,false) else "待試寄"]),14)
		status.name="TeaTrial_"+wrap
		status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		status.autowrap_mode=TextServer.AUTOWRAP_OFF

static func jar_counts(app,parent:Control,counts:Dictionary)->void:
	if counts.is_empty():return
	var row:=HBoxContainer.new()
	row.name="TeaJarCounts"
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	for id:String in JAR_NAMES:
		var amount:=int(counts.get(id,0))
		if amount<=0:continue
		var texture:=Art.icon(id)
		row.add_child(Shell.picture(texture if texture else Art.icon("tea_jar"),32))
		var label:=Helpers.text(app,row,"%s\n×%d"%[JAR_NAMES[id],amount],14)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL

static func wrap_icon(parcel:Dictionary)->String:
	return "fiber_packet" if parcel.get("wrap","jar")=="fiber" else "wrapped_jar"

static func wrap_label(parcel:Dictionary)->String:
	return ("淺焙茶" if parcel.style=="light" else "深焙茶")+("・纖維包" if parcel.wrap=="fiber" else "・陶罐")

static func choose(app,choice:String)->void:
	app.modal.set_meta("tea_choice",choice)
	refresh(app)

static func option(app,parent:Control,id:String,item:String,title:String,detail:String,enabled:bool,chosen:bool,callback:Callable)->void:
	var card:=Helpers.action(app,parent,id,title,callback,enabled)
	card.accessibility_name=title+" "+detail.replace("\n"," ")
	card.text=""
	card.custom_minimum_size.y=136
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.toggle_mode=true
	card.set_pressed_no_signal(chosen)
	var contents:=VBoxContainer.new()
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.mouse_filter=Control.MOUSE_FILTER_IGNORE
	contents.alignment=BoxContainer.ALIGNMENT_CENTER
	card.add_child(contents)
	var image:=Shell.picture(Art.icon(item),64)
	image.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	contents.add_child(image)
	for value in [title,detail]:
		var line:=Helpers.text(app,contents,value,15 if value==title else 13)
		line.mouse_filter=Control.MOUSE_FILTER_IGNORE
		line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if chosen:line.add_theme_color_override("font_color",Color("fff3cf"))
