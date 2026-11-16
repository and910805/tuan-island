extends RefCounted

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
## Side cave direction per depth; matches MINE_SURVEY.POINTS (B6–B15 reuse B1–B5 caves).
const DIRECTIONS:=["北","東","南","北","東","北","東","北","南","東","南","北","東","北","東"]

## Shallow pages (B1–B5) count toward the 波波 reward; deep pages are tallied apart.
static func shallow_count(seen:Dictionary)->int:
	var count:=0
	for key in seen:
		if str(key) in World.MINE_SURVEY.REWARD_PAGES:count+=1
	return count

static func deep_count(seen:Dictionary)->int:
	return seen.size()-shallow_count(seen)

static func deep_total()->int:
	return World.MINE_SURVEY.POINTS.size()-World.MINE_SURVEY.REWARD_PAGES.size()

static func guidance(snapshot:Dictionary)->String:
	var region:=str(snapshot.get("region_id","home"))
	var depth:=World.MINES.IDS.find(region)+1
	if depth==0 and region!="jinguashi":return ""
	var record:Dictionary=snapshot.get("mine_survey",{}).get("own_record",World.MINE_SURVEY.FRESH)
	var seen:Dictionary=record.seen
	var shallow:=shallow_count(seen)
	if depth>World.MINES.SHALLOW_DEPTH:
		if not seen.get(str(depth),false):return "深層 %d／%d · 往%s找觀察點"%[deep_count(seen),deep_total(),DIRECTIONS[depth-1]]
		if record.claimed or not World.MINE_SURVEY.reward_ready(record):return "深層 %d／%d · {journal} 翻手帳"%[deep_count(seen),deep_total()]
	if record.claimed:return ""
	if World.MINE_SURVEY.reward_ready(record):return "側洞 5／5 · 回波波整理桌領獎"
	if depth==0:return ""
	if seen.get(str(depth),false):return "側洞 %d／5 · {journal} 翻手帳"%shallow
	return "側洞 %d／5 · 往%s找觀察點"%[shallow,DIRECTIONS[depth-1]]

static func open(app,page:int=1,observe:bool=false,return_site:String="")->void:
	var body:VBoxContainer=app._open_modal("側洞觀察" if observe else "礦場探索手帳")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","mine_survey")
	app.modal.set_meta("survey_body",body)
	app.modal.set_meta("survey_page",page)
	app.modal.set_meta("survey_observe",observe)
	app.modal.set_meta("survey_return",return_site)
	refresh(app)
	app._layout_preview.call_deferred()

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("survey_body"):return
	var snapshot:Dictionary=app.session.snapshot
	var record:Dictionary=snapshot.get("mine_survey",{}).get("own_record",World.MINE_SURVEY.FRESH)
	var seen:Dictionary=record.seen
	var page:int=app.modal.get_meta("survey_page")
	var observe:bool=app.modal.get_meta("survey_observe")
	var return_site:String=app.modal.get_meta("survey_return")
	var region:=str(snapshot.get("region_id","home"))
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var point:Vector2i=World.MINE_SURVEY.POINTS[page]
	var table:Vector2i=World.BOBO_WORKSHOP.sites(snapshot).table if region=="jinguashi" else Vector2i.ZERO
	var near_point:=region=="mine_%d"%page and nearby(person,point)
	var near_table:=region=="jinguashi" and nearby(person,table)
	var sample_full:=int(person.get("inventory",{}).get("gold_sample",0))>=World.MINE_SURVEY.REWARD_LIMIT
	var fingerprint:=JSON.stringify([page,record,near_point,near_table,table,sample_full])
	if app.modal.get_meta("survey_fingerprint","")==fingerprint:return
	app.modal.set_meta("survey_fingerprint",fingerprint)
	var body:VBoxContainer=app.modal.get_meta("survey_body")
	var focus:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",5)
	body.add_child(spread)
	if not observe:make_index(app,spread,seen,page)
	var card:=paper(spread,14)
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var sheet:=VBoxContainer.new()
	sheet.add_theme_constant_override("separation",9)
	card.add_child(sheet)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	sheet.add_child(row)
	var found:bool=seen.get(str(page),false)
	var entry:Dictionary=World.MINE_SURVEY.entry(page)
	var specimen:=Shell.picture(Items.icon(entry.icon) if found else Shell.icon("journal"),64)
	specimen.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	row.add_child(specimen)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var title:=Helpers.text(app,words,str(entry.title) if found else "B%d · 尚未觀察"%page,20)
	title.name="SurveyTitle"
	var detail:=Helpers.text(app,words,str(entry.text) if found else ("查看這處側洞，將發現記入手帳。" if near_point else str(entry.hint)),16)
	detail.name="SurveyDetail"
	if not observe and not found and near_point:
		Helpers.action(app,words,"SurveyObserve","觀察並記入手帳",func():app.session.perform("survey_observe",point),true).size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var count:=shallow_count(seen)
	var deep:=deep_count(seen)
	if observe:
		var actions:=HBoxContainer.new()
		sheet.add_child(actions)
		if not found and near_point:
			Helpers.action(app,actions,"SurveyObserve","觀察並記入手帳",func():app.session.perform("survey_observe",point),true)
		Helpers.action(app,actions,"SurveyJournal","翻閱探索手帳",func():open(app,page),true)
	else:
		var rule:=HSeparator.new()
		var ink:=StyleBoxLine.new()
		ink.color=Color("b29b73")
		ink.thickness=1
		rule.add_theme_stylebox_override("separator",ink)
		sheet.add_child(rule)
		var reward:=HBoxContainer.new()
		reward.add_theme_constant_override("separation",10)
		sheet.add_child(reward)
		var stamp:=PanelContainer.new()
		stamp.add_theme_stylebox_override("panel",Pixel.texture_style("button_normal",3,5))
		stamp.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		reward.add_child(stamp)
		stamp.add_child(Shell.picture(Items.icon("gold_sample"),32))
		var reward_words:=VBoxContainer.new()
		reward_words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		reward.add_child(reward_words)
		var status:Label
		if record.claimed:
			status=Helpers.text(app,reward_words,"已領取金工收藏樣本 ×1",16)
		elif World.MINE_SURVEY.reward_ready(record):
			status=Helpers.text(app,reward_words,"金工收藏樣本 ×1 · 待領取" if near_table else "回金瓜石的波波整理桌領取收藏樣本。",16)
			Helpers.action(app,reward_words,"SurveyClaim","領取收藏樣本",func():app.session.perform("survey_claim",table),near_table and not sample_full).size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			if sample_full and near_table:Helpers.text(app,reward_words,"背包的收藏樣本已達上限。",15)
		else:
			status=Helpers.text(app,reward_words,"記下五層觀察後，到波波的整理桌領取金工收藏樣本。",16)
		status.name="SurveyReward"
		if deep>0 or page>World.MINES.SHALLOW_DEPTH:
			var deep_note:=Helpers.text(app,reward_words,"側洞 %d／5 · 深層 %d／%d"%[count,deep,deep_total()],15)
			deep_note.name="SurveyDeepProgress"
		var controls:=HBoxContainer.new()
		controls.alignment=BoxContainer.ALIGNMENT_END
		sheet.add_child(controls)
		if return_site=="bobo_sort":
			Helpers.action(app,controls,"SurveyBack","回礦樣整理桌",app._bobo_sort_menu,true)
		elif not return_site.is_empty():
			Helpers.action(app,controls,"SurveyBack","回礦場路牌",func():app._mine_site_menu(return_site),true)
		else:
			Helpers.action(app,controls,"SurveyResidents","島民手帳",func():app._journal("bobo"),true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="側洞觀察  %d／5 · 深層 %d／%d"%[count,deep,deep_total()]
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next and not next.disabled:next.grab_focus.call_deferred()

static func nearby(person:Dictionary,cell:Vector2i)->bool:
	return not person.is_empty() and Vector2(person.x,person.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2

static func select_page(app,page:int)->void:
	app.modal.set_meta("survey_page",page)
	refresh(app)

static func paper(parent:Control,inset:int)->PanelContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",Pixel.texture_style("paper",3,inset))
	parent.add_child(panel)
	return panel

static func make_index(app,parent:Control,seen:Dictionary,page:int)->void:
	var cover:=paper(parent,6)
	# Fifteen pages: one column per five floors (B1–B5, B6–B10, B11–B15).
	var pages:=HBoxContainer.new()
	pages.name="SurveyPages"
	pages.add_theme_constant_override("separation",2)
	cover.add_child(pages)
	var column:VBoxContainer
	for depth:int in range(1,World.MINE_SURVEY.POINTS.size()+1):
		if column==null or (depth-1)%5==0:
			column=VBoxContainer.new()
			column.add_theme_constant_override("separation",2)
			pages.add_child(column)
		var found:bool=seen.get(str(depth),false)
		var entry:Dictionary=World.MINE_SURVEY.entry(depth)
		var button:=Helpers.action(app,column,"SurveyPage%d"%depth,"B%d"%depth,func():select_page(app,depth),true)
		button.icon=Items.icon(entry.icon) if found else Shell.icon("journal")
		button.add_theme_constant_override("icon_max_width",16)
		button.custom_minimum_size.y=28
		button.accessibility_name="地下第 %d 層，%s"%[depth,entry.title if found else "尚未觀察"]
		button.tooltip_text=button.accessibility_name
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.x=50
		var blank:=StyleBoxEmpty.new()
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:blank.set_content_margin(side,3)
		button.add_theme_stylebox_override("normal",blank)
		button.add_theme_stylebox_override("hover",Pixel.texture_style("button_hover",3,3))
		button.add_theme_stylebox_override("pressed",Pixel.texture_style("button_pressed",3,3))
		button.add_theme_stylebox_override("hover_pressed",Pixel.texture_style("button_pressed",3,3))
		button.toggle_mode=true
		button.set_pressed_no_signal(depth==page)
