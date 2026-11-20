extends RefCounted
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const TITLES:={"entry":"下坑路牌","up":"回程路牌","down":"下階路牌","rest":"提燈休息站","service":"礦務工程","lift":"升降台"}
## Badge strip rows: B1–B8 on the first row, B9–B15 on the second.
const BADGE_ROW_SPLIT:=8
## Captions keep autowrap off, so long CJK sentences are split at punctuation
## to stay well inside the 480px station card at 15–16px.
const CAPTION_CHARS:=24

static func open(app,site:String)->void:
	var body:VBoxContainer=app._open_modal(TITLES[site])
	app.modal.set_meta("life_modal_layout","mine_station")
	app.modal.set_meta("mine_body",body)
	app.modal.set_meta("mine_site",site)
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("mine_body"):return
	var s:Dictionary=app.session.snapshot
	var region:=str(s.get("region_id","home"))
	var depth:=int(region.trim_prefix("mine_")) if region.begins_with("mine_") else 0
	var site:String=app.modal.get_meta("mine_site")
	var body:VBoxContainer=app.modal.get_meta("mine_body")
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	var station:Vector2i={"entry":World.MINES.ENTRY,"up":World.MINES.UP,"down":World.MINES.DOWN,"rest":World.MINES.REST,"service":World.MINES.SERVICE,"lift":World.MINES.LIFT}[site]
	var nearby:=not person.is_empty() and Vector2(person.x,person.y).distance_to(Vector2(station)+Vector2(0.5,0.5))<=3.2
	var progress:Dictionary=s.get("mine_depths",{})
	var unlocked:=int(progress.get("unlocked",1))
	# Q07: hoist repair flag + surface landings (empty until repaired); the whole
	# inventory is already part of the fingerprint (HOIST_COST have／need).
	var hoist_fixed:bool=World.MINES.hoist_ready(progress)
	var own_rest_kit:=int(s.get("own_bobo_rest_kit",0))
	var assigned:=int(s.get("resident_bonds",{}).get("bobo",{}).get("stage",0))>=3
	var fixtures:=int(s.get("bobo_rest_fixtures",0))
	var borrowed:bool=person.get("borrowed_mine_pick",false)
	var meal:=World.MEAL_BUFF.read(person,float(s.get("time",0.0)))
	var meal_stamp:=[meal.get("id",""),ceili(float(meal.get("left",0.0))/10.0)]
	var fingerprint:=JSON.stringify([site,region,nearby,World.MEAL_BUFF.whole_points(person),meal_stamp,person.get("inventory",{}),unlocked,progress.get("pumped",0),World.MINES.lift_targets(unlocked),hoist_fixed,World.MINES.surface_landings(progress),own_rest_kit,assigned,fixtures,borrowed])
	if app.modal.get_meta("mine_fingerprint","")==fingerprint:return
	app.modal.set_meta("mine_fingerprint",fingerprint)
	var focus:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",Pixel.texture_style("frame",8,8))
	body.add_child(card)
	var text:=VBoxContainer.new()
	text.add_theme_constant_override("separation",4)
	card.add_child(text)
	var heading:=HBoxContainer.new()
	text.add_child(heading)
	heading.add_child(Shell.picture(Shell.icon("pick"),24))
	var floor_title:="合作礦場" if depth==0 else "地下第 %d 層"%depth
	if depth>World.MINES.SHALLOW_DEPTH:floor_title+=" · "+str(Catalog.entry(depth).get("title",""))
	heading.add_child(caption(app,floor_title,16))
	var badges:=VBoxContainer.new()
	badges.name="MineBadges"
	badges.add_theme_constant_override("separation",3)
	text.add_child(badges)
	var badge_row:HFlowContainer
	for floor_index in range(1,World.MINES.MAX_DEPTH+1):
		if badge_row==null or floor_index==BADGE_ROW_SPLIT+1:
			badge_row=HFlowContainer.new()
			badge_row.add_theme_constant_override("h_separation",3)
			badge_row.add_theme_constant_override("v_separation",3)
			badges.add_child(badge_row)
		var badge:=PanelContainer.new()
		badge.name="MineBadge%d"%floor_index
		badge.add_theme_stylebox_override("panel",Pixel.texture_style("button_pressed" if floor_index==depth else ("button_normal" if floor_index<=unlocked else "paper"),3,5))
		badge.tooltip_text="第 %d 層 · %s"%[floor_index,"所在樓層" if floor_index==depth else ("已開通" if floor_index<=unlocked else "整備中")]
		badge_row.add_child(badge)
		var label:Label=caption(app,"B%d%s"%[floor_index,"" if floor_index<=unlocked else " ·"],15)
		if floor_index==depth:label.add_theme_color_override("font_color",Color("fff3cf"))
		badge.add_child(label)
	if depth>World.MINES.SHALLOW_DEPTH:
		var floor_info:Dictionary=Catalog.entry(depth)
		var zone:Dictionary=Catalog.ZONES.get(str(floor_info.get("zone","")),{})
		var hazard:Dictionary=Catalog.HAZARDS.get(str(floor_info.get("hazard","none")),Catalog.HAZARDS.none)
		var zone_note:=caption(app,"%s · %s"%[zone.get("name",""),hazard.name],15)
		zone_note.name="MineZone"
		text.add_child(zone_note)
		add_lines(app,text,str(hazard.note),15,"MineHazard")
	match site:
		"entry":
			text.add_child(caption(app,("第一層已開放。" if unlocked<=1 else "已開通到第 %d 層。"%unlocked)+"下坑前記得查看回程。",16))
			var notes:=HBoxContainer.new()
			text.add_child(notes)
			notes.add_child(caption(app,"合作礦場為架空場景。",15))
			var lore:=caption(app,"深層地質為遊戲設定。",15)
			lore.name="MineFictionNote"
			notes.add_child(lore)
			var entrance_actions:=HBoxContainer.new()
			text.add_child(entrance_actions)
			add_action(app,entrance_actions,"MineEnter","進入第一層",func():app.session.perform("mine_travel",World.MINES.ENTRY,"mine_1"),nearby and region=="jinguashi")
			if World.active_mining_pick(person.get("inventory",{})).is_empty():
				add_pick_loan(app,entrance_actions,World.MINES.ENTRY,nearby and region=="jinguashi" and s.get("picnic",false),borrowed)
			if unlocked>=6 and not hoist_fixed:
				add_hoist_repair(app,text,person,nearby and region=="jinguashi")
			elif hoist_fixed:
				var fixed:=caption(app,"升降台已修好，可直達已開通的停靠層。",15)
				fixed.name="MineHoistReady"
				text.add_child(fixed)
			# Surface rides only after the Q07 repair (cages below always go up).
			var landings:Array=World.MINES.surface_landings(progress)
			if not landings.is_empty():
				var hoist:=HFlowContainer.new()
				hoist.name="MineLiftLandings"
				hoist.add_theme_constant_override("h_separation",4)
				hoist.add_theme_constant_override("v_separation",4)
				text.add_child(hoist)
				for landing:int in landings:
					var target:="mine_%d"%landing
					add_action(app,hoist,"MineLift%d"%landing,"搭升降台到第 %d 層"%landing,func():app.session.perform("mine_travel",World.MINES.ENTRY,target),nearby and region=="jinguashi")
		"lift":
			text.add_child(caption(app,"升降台直通金瓜石山城，不收費也不耗體力。",16))
			if depth>World.MINES.SHALLOW_DEPTH:
				var lore:=caption(app,"深層地質為遊戲設定。",15)
				lore.name="MineFictionNote"
				text.add_child(lore)
			add_action(app,text,"MineLiftUp","搭升降台回山城",func():app.session.perform("mine_travel",World.MINES.LIFT,"jinguashi"),nearby and depth>World.MINES.SHALLOW_DEPTH)
		"up":
			var target:="jinguashi" if depth==1 else "mine_%d"%(depth-1)
			text.add_child(caption(app,"回程 → %s"%("金瓜石山城" if depth==1 else "地下第 %d 層"%(depth-1)),16))
			add_action(app,text,"MineUp","返回山城" if depth==1 else "回到上一層",func():app.session.perform("mine_travel",World.MINES.UP,target),nearby and depth>0)
		"down":
			if depth<World.MINES.MAX_DEPTH:
				var descend:Button=app.button("前往第 %d 層"%(depth+1),func():app.session.perform("mine_travel",World.MINES.DOWN,"mine_%d"%(depth+1)))
				descend.name="MineDown"
				descend.disabled=not nearby or depth>=unlocked
				text.add_child(descend)
				if descend.disabled:text.add_child(caption(app,"請先到礦務站完成整備。",15))
			else:
				text.add_child(caption(app,"這裡是最深的提燈大廳。",16))
		"rest":
			var energy:=World.MEAL_BUFF.whole_points(person)
			text.add_child(caption(app,"礦內體力  %d／100"%energy,17))
			text.add_child(meter(energy,100))
			if meal.get("id","")==World.MEAL_BUFF.SALAD:
				var effect:=caption(app,"沙拉效果 · 採礦耗體 −5%% · 剩 %s"%World.MEAL_BUFF.clock_text(ceili(float(meal.left))),15)
				effect.name="MineMealEffect"
				text.add_child(effect)
			# T067: what a strike on this floor adds besides the ore (B6–B15 catalog finds).
			var finds:=finds_text(depth)
			if not finds.is_empty():
				var found:=caption(app,finds,15)
				found.name="MineFinds"
				text.add_child(found)
			var rest_actions:=HBoxContainer.new()
			text.add_child(rest_actions)
			add_action(app,rest_actions,"MineRest","休息喝水",func():app.session.perform("mine_rest",World.MINES.REST),nearby and depth>0)
			if depth>0 and depth<=World.MINES.SHALLOW_DEPTH and World.active_mining_pick(person.get("inventory",{})).is_empty():
				add_pick_loan(app,rest_actions,World.MINES.REST,nearby and depth<=unlocked and s.get("picnic",false),borrowed)
			if depth==1 and assigned:
				text.add_child(caption(app,"波波的託付 · 不往深處也可以",16))
				add_rest_kit_tasks(app,text,person,nearby,own_rest_kit,fixtures)
		"service":
			var pending:=depth>0 and depth==unlocked and depth<World.MINES.MAX_DEPTH
			if not pending:
				text.add_child(caption(app,"這一層的工程已備妥。",16))
			elif depth==3:
				var pumped:=int(progress.get("pumped",0))
				var flow:=HBoxContainer.new()
				text.add_child(flow)
				for part in ["pump_kit","pipe_kit","tank_kit"]:
					if part!="pump_kit":flow.add_child(caption(app," → ",16))
					flow.add_child(Shell.picture(ItemArt.icon(part),24))
				flow.add_child(caption(app,"  已抽水 %d／24"%pumped,16))
				text.add_child(meter(pumped,24))
				text.add_child(caption(app,"用同一位島民的水泵、銅管與水桶接通。",15))
			else:
				if depth>=World.MINES.SHALLOW_DEPTH and Catalog.COMMISSIONS.has(depth):
					var project:=caption(app,"工程：%s → 開通第 %d 層"%[Catalog.COMMISSIONS[depth].title,depth+1],16)
					project.name="MineCommissionTitle"
					text.add_child(project)
				var requirements:=HFlowContainer.new()
				requirements.name="MineRequirements"
				requirements.add_theme_constant_override("h_separation",4)
				requirements.add_theme_constant_override("v_separation",4)
				text.add_child(requirements)
				for material in World.MINES.COSTS[depth-1]:
					var badge:=PanelContainer.new()
					badge.add_theme_stylebox_override("panel",Pixel.paper_style())
					requirements.add_child(badge)
					var row:=HBoxContainer.new()
					badge.add_child(row)
					row.add_child(Shell.picture(ItemArt.icon(material),32))
					row.add_child(caption(app,"%s  %d／%d"%[World.NAMES[material],int(person.get("inventory",{}).get(material,0)),World.MINES.COSTS[depth-1][material]],16))
			if pending:
				var ready:=nearby
				if depth==3:ready=ready and int(progress.get("pumped",0))>=24
				else:
					for item in World.MINES.COSTS[depth-1]:
						ready=ready and int(person.get("inventory",{}).get(item,0))>=World.MINES.COSTS[depth-1][item]
				add_action(app,text,"MineCommission","確認供水工程" if depth==3 else "交付工程材料",func():app.session.perform("mine_commission",World.MINES.SERVICE),ready)
			if depth>World.MINES.SHALLOW_DEPTH:
				var lore:=caption(app,"深層地質為遊戲設定。",15)
				lore.name="MineFictionNote"
				text.add_child(lore)
			if unlocked>=World.MINES.SHALLOW_DEPTH:
				var unlocked_note:=caption(app,"採掘機圖樣已解鎖；回工作台製作。",15)
				unlocked_note.name="DrillUnlockNote";text.add_child(unlocked_note)
			if depth in [4,5] and unlocked>=World.MINES.SHALLOW_DEPTH and app.has_method("_freight_menu"):
				add_action(app,text,"MineFreight","裝載礦車",app._freight_menu,nearby)
				if app.has_method("_auto_freight_menu"):add_action(app,text,"MineAutoFreight","安排定期寄運",app._auto_freight_menu,nearby)
	if not nearby:text.add_child(caption(app,"走近路牌或礦務設施後即可操作。",15))
	if site=="entry" and region=="jinguashi":
		# 第 40 章金瓜石回訪：坑內礦務站這一箱由下坑路牌旁的升降台送出（升降台修好前按鈕寫明鎖定）。
		var links:=HBoxContainer.new()
		links.name="MineEntryLinks"
		links.add_theme_constant_override("separation",8)
		text.add_child(links)
		add_action(app,links,"MineSurveyJournal","翻閱礦場探索手帳",func():app._mine_survey_menu(maxi(1,depth),site),true)
		var revisit:Button=preload("res://scripts/jinguashi_revisit_ui.gd").entry_button(app,"depot")
		revisit.custom_minimum_size.y=42  # same height and font as the journal button beside it
		revisit.remove_theme_font_size_override("font_size")
		links.add_child(revisit)
	else:
		add_action(app,text,"MineSurveyJournal","翻閱礦場探索手帳",func():app._mine_survey_menu(maxi(1,depth),site),true)
	if not focus_name.is_empty():
		var replacement:=body.find_child(focus_name,true,false) as Control
		if replacement is BaseButton and not replacement.disabled:replacement.grab_focus.call_deferred()

## Q07 「卡住的升降台」: surface entry card section shown once B6 is open and the
## hoist is still stuck. Badges mirror MineRequirements (have／need, 32px icons).
static func add_hoist_repair(app,parent:Control,person:Dictionary,reachable:bool)->void:
	var section:=VBoxContainer.new()
	section.name="MineHoistRepair"
	section.add_theme_constant_override("separation",4)
	parent.add_child(section)
	add_lines(app,section,"升降台卡住了。波波需要材料修理。",15,"MineHoistCaption")
	var requirements:=HFlowContainer.new()
	requirements.name="MineHoistRequirements"
	requirements.add_theme_constant_override("h_separation",4)
	requirements.add_theme_constant_override("v_separation",4)
	section.add_child(requirements)
	var bag:Dictionary=person.get("inventory",{})
	var stocked:=true
	var cost:Dictionary=World.MINES.HOIST_COST
	for material in cost:
		var item:=str(material)
		var have:=int(bag.get(item,0))
		var need:=int(cost[material])
		stocked=stocked and have>=need
		var badge:=PanelContainer.new()
		badge.name="MineHoistNeed_"+item
		badge.add_theme_stylebox_override("panel",Pixel.paper_style())
		requirements.add_child(badge)
		var row:=HBoxContainer.new()
		badge.add_child(row)
		row.add_child(Shell.picture(ItemArt.icon(item),32))
		var count:=caption(app,"%s  %d／%d"%[World.NAMES.get(item,item),have,need],16)
		count.name="MineHoistCount_"+item
		row.add_child(count)
	add_action(app,section,"MineHoistRepairButton","交付修理材料",func():app.session.perform("mine_hoist_repair",World.MINES.ENTRY),reachable and stocked)

## Display-only uses of the deep-mine quest finds (rules: mine_expansion_catalog.RESOURCE_USES).
const FIND_USES:={"iron_ore":"可用小熔爐熔成鐵錠","ochre_earth":"可由出貨箱出售","vein_quartz":"熔晶砂用","warm_stone":"共餐桌保溫底座用"}

## 「敲礦另得：石材、暖岩片（共餐桌保溫底座用）」 for floors with catalog finds; "" otherwise.
static func finds_text(depth:int)->String:
	var names:=PackedStringArray()
	var uses:=PackedStringArray()
	for item:String in World.MINES.finds(depth):
		names.append(str(World.NAMES.get(item,item)))
		if FIND_USES.has(item):uses.append(FIND_USES[item])
	if names.is_empty():return ""
	return "敲礦另得：%s%s"%["、".join(names),"（%s）"%"、".join(uses) if not uses.is_empty() else ""]

static func caption(app,value:String,extent:int)->Label:
	var label:Label=app.label(value,extent)
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return label

## Adds one or more unwrapped captions, breaking after CJK punctuation so no line
## exceeds CAPTION_CHARS characters when a break point exists. The first line gets `id`.
static func add_lines(app,parent:Control,value:String,extent:int,id:String="")->void:
	var lines:=split_lines(value,CAPTION_CHARS)
	for index in range(lines.size()):
		var line:=caption(app,lines[index],extent)
		if index==0 and not id.is_empty():line.name=id
		parent.add_child(line)

static func split_lines(value:String,limit:int)->PackedStringArray:
	var lines:=PackedStringArray()
	var line:=""
	var piece:=""
	for index in range(value.length()):
		piece+=value[index]
		if value[index] in ["，","；","。","、","：","！","？"] or index==value.length()-1:
			if not line.is_empty() and line.length()+piece.length()>limit:
				lines.append(line)
				line=""
			line+=piece
			piece=""
	if not line.is_empty():lines.append(line)
	return lines

static func meter(value:int,capacity:int)->ProgressBar:
	var bar:=ProgressBar.new()
	bar.show_percentage=false
	bar.max_value=capacity
	bar.value=value
	bar.custom_minimum_size.y=9
	bar.add_theme_stylebox_override("background",Pixel.texture_style("button_normal",3,0))
	bar.add_theme_stylebox_override("fill",Pixel.texture_style("button_pressed",3,0))
	return bar

static func add_rest_kit_tasks(app,parent:VBoxContainer,person:Dictionary,nearby:bool,installed:int,fixtures:int) -> void:
	var goals:=World.RESIDENT_GOALS
	var inv:Dictionary=person.get("inventory",{})
	for id:String in goals.REST_KIT_PARTS:
		var part:Dictionary=goals.REST_KIT_PARTS[id]
		var bit:=int(part.bit)
		if (installed&bit)!=0:
			parent.add_child(caption(app,"✓ 已備好%s"%part.label,15))
			continue
		var costs:=PackedStringArray()
		var enough:=true
		for item:String in part.cost:
			costs.append("%s %d"%[World.NAMES[item],part.cost[item]])
			enough=enough and int(inv.get(item,0))>=int(part.cost[item])
		var verb:="補整" if (fixtures&bit)!=0 else "製作"
		add_action(app,parent,"BoboRest_"+id,"%s%s · %s"%[verb,part.label,"、".join(costs)],
			func():app.session.perform(goals.REST_KIT_ACTION,World.MINES.REST,id),nearby and enough)
	if installed==goals.REST_KIT_MASK:
		parent.add_child(caption(app,"備好了，回金瓜石山城找波波。",15))

static func add_pick_loan(app,parent:Control,site:Vector2i,nearby:bool,borrowed:bool)->void:
	if borrowed:
		parent.add_child(caption(app,"公用鎬可在 B1–B5 使用。",15))
		return
	add_action(app,parent,"MineBorrowPick","借用公用鎬",func():app.session.perform("borrow_mine_pick",site),nearby)

static func add_action(app,parent:Control,id:String,title:String,callback:Callable,enabled:bool)->void:
	var button:Button=app.button(title,callback)
	button.name=id
	button.disabled=not enabled
	button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	parent.add_child(button)
