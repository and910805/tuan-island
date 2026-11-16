extends RefCounted
## 第 40 章「金瓜石回訪・礦料調度」頁與「礦燈」訪客卡片（規則在 jinguashi_revisit.gd，這裡只讀
## 快照、送動作 jg_revisit_sort / jg_revisit_ship / jg_revisit_claim）。
##
## 入口（都用一般互動鍵進既有頁面，再按頁內按鈕；沒有新按鍵，既有流程照舊）：
##  * 波波的礦樣整理桌（bobo_sort_ui）底部「金瓜石回訪・礦料調度」→ open(app,"table")；
##  * 山城接駁站的車票頁（travel_ui，人在金瓜石時）同名按鈕 → open(app,"ferry")；
##  * 下坑路牌（mine_ui 的 entry 卡片）探索手帳旁同名按鈕 → open(app,"depot")；
##  * 金瓜石左上追蹤卡（升降台修好、自己也整理過礦樣之後）顯示目前的訂單進度，
##    「打開礦料調度」按鈕 → open(app,"")（依站的位置決定）。
##  升降台修好之前三個按鈕寫「礦料調度・升降台修好後開放」，按下的頁面只顯示鎖定原因。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  波波的頭像＋「季的訂單・第 n 日・天氣」＋波波的理由 → 鎖定／補做說明（只在需要時）→
##  三個貨箱卡片（名稱與送出點座標、怎麼送、訂單要的礦料與數量＋背包持有、目前分揀、
##  三個分揀鈕（石材／銅礦／含金礦料，按下的是目前的分揀）、送出鈕＋已送出／你在這裡、
##  不能送出的原因）→ 分揀的原因（只寫一次）→ 礦燈列（狀態、領取鈕、原因）→ 原創聲明＋回到原頁。
##  每個按鈕不能按時寫出原因：規則的 sort_block / ship_block / claim_block 優先；規則允許但人不在
##  對的地方時，寫出要站到哪裡（含座標）——遠處貨箱的送出鈕不會默默失敗。
##  送出的位置就是規則要的格子：分揀／領取＝整理桌 sort_cell、送出＝dest_cell（整理桌／
##  山城接駁站 (11,20)／下坑路牌 (28,19)）。結構只建一次，refresh() 依快照原地更新（不重建），
##  按鈕按下後頁面不關、焦點留在原處；伺服器回覆由 main._notice 寫進頁底的 modal_feedback。
##  焦點：分揀鈕九個一列（左右循環），下＝同一箱的送出鈕；送出鈕一列；領取；回到原頁；
##  最上一列往上是「關閉」。
##
## 礦燈卡片（lantern_card）：任何訪客靠近擺好的礦燈按互動鍵（main._interact）：名稱、說明、
##  來源、對應工程、擺放者。
const World=preload("res://scripts/world.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Weather=preload("res://scripts/weather.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/jinguashi_revisit_art.gd")
const BoboArt=preload("res://scripts/bobo_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")

const LAYOUT:="jinguashi_revisit"
const CARD_LAYOUT:="mine_lantern"
const PAGE_TITLE:=JG.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const ENTRY_OPEN:="金瓜石回訪・礦料調度"
const ENTRY_LOCKED:="礦料調度・升降台修好後開放"
const ORIGIN_DEST:={"table":"bobo","ferry":"ferry","depot":"depot"}
const BACK_TEXT:={"table":"回到礦樣整理桌","ferry":"回到接駁站車票","depot":"回到下坑路牌"}
const PLACE_SHORT:={"bobo":"整理桌","ferry":"山城接駁站","depot":"下坑路牌"}
const ORE_SHORT:={"stone":"石材","copper_ore":"銅礦","gold_ore":"含金礦料"}
const SHIP_TEXT:="送出這一箱"
const CLAIM_TEXT:="領取礦燈"
const MARK_SENT:="✓ 已送出"
const MARK_OPEN:="○ 還沒送出"
const MARK_HERE:="・你在這裡"
const AWAY_SORT:="分揀要站在波波的整理桌旁（%d,%d）。"
const AWAY_SHIP:="走到%s旁（%d,%d）才能送出。"
const AWAY_CLAIM:="領礦燈要回到波波的整理桌旁（%d,%d）。"
const STATUS_OPEN:="礦燈・三箱都送出後，每人可在整理桌領一盞"
const STATUS_DONE:="✓ 礦料調度完成・到波波的整理桌領礦燈"
const STATUS_CLAIMED:="✓ 已領礦燈・在家園工坊「生活」頁擺放"
const DONE_LINE:="三個貨箱都送到了，謝謝大家！礦燈帶回家，看到它就記得今天。"

# ------------------------------------------------------------ pure helpers --

static func in_jinguashi(s:Dictionary) -> bool:
	return str(s.get("region_id","home"))==JG.REGION

static func entry_caption(s:Dictionary) -> String:
	return ENTRY_OPEN if JG.unlocked(s) else ENTRY_LOCKED

static func _person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

static func _bag(person:Dictionary) -> Dictionary:
	var bag:Variant=person.get("inventory",{})
	return bag if bag is Dictionary else {}

static func near(s:Dictionary,person:Dictionary,cell:Vector2i) -> bool:
	if person.is_empty() or not in_jinguashi(s):return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=JG.REACH

## The ship point the player stands at (closest within reach), "" when none.
static func standing_dest(s:Dictionary,person:Dictionary) -> String:
	var best:=""
	var best_distance:=JG.REACH+0.001
	if person.is_empty() or not in_jinguashi(s):return best
	var at:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	for dest:String in JG.DESTS:
		var d:=at.distance_to(Vector2(JG.dest_cell(s,dest))+Vector2(0.5,0.5))
		if d<best_distance:best=dest;best_distance=d
	return best

## Why the sort buttons cannot be pressed ("" = they can).
static func sort_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=JG.sort_block(s)
	if not block.is_empty():return block
	var table:=JG.sort_cell(s)
	return "" if near(s,person,table) else AWAY_SORT%[table.x,table.y]

## Why this crate's 送出 button cannot be pressed ("" = it can): the rules first, then where to stand.
static func ship_reason(s:Dictionary,person:Dictionary,dest:String) -> String:
	var block:=JG.ship_block(s,dest,_bag(person))
	if not block.is_empty():return block
	var cell:=JG.dest_cell(s,dest)
	return "" if near(s,person,cell) else AWAY_SHIP%[str(PLACE_SHORT.get(dest,"")),cell.x,cell.y]

static func claim_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=JG.claim_block(s,_bag(person))
	if not block.is_empty():return block
	var table:=JG.claim_cell(s)
	return "" if near(s,person,table) else AWAY_CLAIM%[table.x,table.y]

## Jinguashi tracker (two short lines). "" before the hoist repair and for players who have
## not done their own Bobo sort yet (the Bobo story tracker already leads there).
static func tracker_text(s:Dictionary) -> String:
	if not JG.unlocked(s) or not JG.player_ready(s):return ""
	if JG.completed(s):
		return "礦料調度完成\n礦燈可擺在家園了" if JG.claimed_own(s) else "礦料調度完成\n到整理桌找波波領礦燈"
	var done:=JG.sent(s)
	var season:=str(Weather.SEASON_LABELS.get(JG.order_season(s),""))
	if done.is_empty():
		var ok:=0
		for row:Dictionary in JG.rows(s):
			if bool(row.ok):ok+=1
		if ok<JG.DESTS.size():return "礦料調度・%s季訂單\n到整理桌分揀 %d／3 箱"%[season,ok]
	for dest:String in JG.DESTS:
		if dest not in done:return "礦料調度・已送出 %d／3\n下一箱：%s"%[done.size(),str(PLACE_SHORT[dest])]
	return ""

## The tracker card follows the revisit (and its button opens this page).
static func tracking(s:Dictionary) -> bool:
	return in_jinguashi(s) and not tracker_text(s).is_empty()

static func _person(app) -> Dictionary:
	return _person_of(app.session.snapshot,str(app.session.own_id))

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("jg_body")

static func card_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("jg_lantern_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

## origin: "table" / "ferry" / "depot" (the page it was opened from); "" = where I stand.
static func open(app,origin:String="") -> void:
	var s:Dictionary=app.session.snapshot
	if not in_jinguashi(s):return
	if not ORIGIN_DEST.has(origin):
		var here:=standing_dest(s,_person(app))
		origin="table"
		for key:String in ORIGIN_DEST:
			if ORIGIN_DEST[key]==here:origin=key
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	app.modal.name="JinguashiRevisitPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("jg_body",body)
	app.modal.set_meta("jg_origin",origin)
	body.add_theme_constant_override("separation",6)
	build(app,body,origin)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上"
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## Entry button for the bobo-sort page, the shuttle ticket page and the mine entry card.
static func entry_button(app,origin:String) -> Button:
	var s:Dictionary=app.session.snapshot
	var b:Button=app.button(entry_caption(s),func():open(app,origin))
	b.name="JgRevisitEntry"
	b.focus_mode=Control.FOCUS_ALL
	b.custom_minimum_size.y=34
	b.add_theme_font_size_override("font_size",14)
	b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	b.tooltip_text="" if JG.unlocked(s) else JG.LOCKED
	return b

## main._layout_preview: centred, as tall as its content (the lantern card sits at the top).
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var card:=card_open(app)
	var width:=minf(760.0 if card else 900.0,bounds.x-48)
	var cap:=bounds.y-32
	var height:=minf(cap,620)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))
	# The lantern card goes to the half of the screen away from the lantern, so the lantern
	# itself stays in view (at 1024×640 a card at the top covered it; screenshots, before/).
	if card:modal.position.y=bounds.y-height-16.0 if _lantern_on_top(app,bounds) else 16.0

static func _lantern_on_top(app,bounds:Vector2) -> bool:
	var cell:Variant=app.modal.get_meta("jg_lantern_cell",null)
	if not cell is Vector2i or app.view==null:return false
	var view:CanvasItem=app.view
	var at:Vector2=view.get_global_transform_with_canvas()*(app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*float(app.view.view_zoom()))
	return at.y<bounds.y*0.5

static func _text(app,parent:Node,id:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label("",size)
	l.name=id
	l.autowrap_mode=TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal=Control.SIZE_FILL
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func _wrapped(app,parent:Node,id:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label("",size)
	l.name=id
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func _button(app,parent:Node,id:String,title:String,callback:Callable) -> Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.focus_mode=Control.FOCUS_ALL
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size=Vector2(0,30)
	b.add_theme_font_size_override("font_size",14)
	parent.add_child(b)
	return b

static func picture(texture:Texture2D,extent:int) -> TextureRect:
	var result:=TextureRect.new()
	result.texture=texture
	result.custom_minimum_size=Vector2(extent,extent)
	result.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return result

static func _paper(parent:Node,id:String,separation:=3) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",separation)
	card.add_child(col)
	return col

static func build(app,body:VBoxContainer,origin:String) -> void:
	# The order: season, day, weather and Bobo's reason.
	var head:=_paper(body,"JgHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	head.add_child(row)
	var portrait:=picture(BoboArt.icon("portrait"),48)
	portrait.name="JgPortrait"
	row.add_child(portrait)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",1)
	row.add_child(words)
	_text(app,words,"JgDay",16)
	_wrapped(app,words,"JgReason",14)
	# Locked / not ready.
	var hold:=_paper(body,"JgHold")
	_wrapped(app,hold,"JgHoldText",15,WARN)
	var practice:=_button(app,hold,"JgSortPractice","到波波的礦樣整理桌",app._bobo_sort_menu)
	practice.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	# Three crates.
	var crates:=HBoxContainer.new()
	crates.name="JgCrates"
	crates.add_theme_constant_override("separation",8)
	body.add_child(crates)
	for c in JG.DESTS.size():
		var dest:String=JG.DESTS[c]
		var card:=_paper(crates,"JgCrate_"+dest)
		_text(app,card,"JgCrateName_"+dest,15)
		_text(app,card,"JgCrateHow_"+dest,13,MUTED)
		_text(app,card,"JgCrateNeed_"+dest,13)
		_text(app,card,"JgCrateNow_"+dest,13)
		var sorts:=HBoxContainer.new()
		sorts.name="JgSortRow_"+dest
		sorts.add_theme_constant_override("separation",4)
		card.add_child(sorts)
		for ore:String in JG.ORES:
			var b:=_button(app,sorts,"JgSort_%s_%s"%[dest,ore],str(ORE_SHORT[ore]),func():_send_sort(app,dest,ore))
			b.toggle_mode=true
			b.set_meta("jg_col",c)
			b.icon=Items.icon(ore)
			b.add_theme_constant_override("icon_max_width",18)
			b.add_theme_constant_override("h_separation",3)
		var ship_row:=HBoxContainer.new()
		ship_row.add_theme_constant_override("separation",6)
		card.add_child(ship_row)
		var ship:=_button(app,ship_row,"JgShip_"+dest,SHIP_TEXT,func():_send_ship(app,dest))
		ship.set_meta("jg_col",c)
		var mark:=_text(app,ship_row,"JgCrateMark_"+dest,13,MUTED)
		mark.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_wrapped(app,card,"JgShipReason_"+dest,13,WARN)
	_wrapped(app,body,"JgSortReason",14,WARN)
	# The lantern.
	var claim:=_paper(body,"JgClaimCard")
	var claim_row:=HBoxContainer.new()
	claim_row.add_theme_constant_override("separation",8)
	claim.add_child(claim_row)
	var icon:=picture(Art.lantern_texture(),32)
	icon.name="JgLanternIcon"
	claim_row.add_child(icon)
	var status:=_wrapped(app,claim_row,"JgStatus",14)
	status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,claim_row,"JgClaim",CLAIM_TEXT,func():_send_claim(app))
	_wrapped(app,claim,"JgClaimReason",13,WARN)
	# Disclaimer and the way back to the page it was opened from.
	var foot:=HBoxContainer.new()
	foot.name="JgFooter"
	foot.add_theme_constant_override("separation",10)
	body.add_child(foot)
	var disclaimer:=_wrapped(app,foot,"JgDisclaimer",13,MUTED)
	disclaimer.text=JG.DISCLAIMER
	disclaimer.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,foot,"JgBack",str(BACK_TEXT.get(origin,BACK_TEXT.table)),func():_back(app,origin))

# ------------------------------------------------------------------ actions --

static func _send_sort(app,dest:String,ore:String) -> void:
	if not is_open(app):return
	app.session.perform(JG.SORT_ACTION,JG.sort_cell(app.session.snapshot),JG.sort_extra(dest,ore))
	refresh(app,true)

static func _send_ship(app,dest:String) -> void:
	if not is_open(app):return
	app.session.perform(JG.SHIP_ACTION,JG.dest_cell(app.session.snapshot,dest))
	refresh(app,true)

static func _send_claim(app) -> void:
	if not is_open(app):return
	app.session.perform(JG.CLAIM_ACTION,JG.claim_cell(app.session.snapshot))
	refresh(app,true)

static func _back(app,origin:String) -> void:
	match origin:
		"ferry":app._travel_menu("shuttle")
		"depot":app._mine_site_menu("entry")
		_:app._bobo_sort_menu()

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("jg_body") as Node).find_child(id,true,false) as Control

static func _put(app,id:String,value:String,color=null) -> Label:
	var l:=_node(app,id) as Label
	if l==null:return null
	l.text=value
	if color is Color:l.add_theme_color_override("font_color",color)
	l.visible=not value.is_empty()
	return l

static func _enable(app,id:String,enabled:bool,tip:String) -> Button:
	var b:=_node(app,id) as Button
	if b==null:return null
	b.disabled=not enabled
	b.tooltip_text=tip
	return b

static func _show(app,id:String,on:bool) -> void:
	var c:=_node(app,id)
	if c!=null:c.visible=on

static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var bag:=_bag(person)
	var unlocked:=JG.unlocked(s)
	var ready:=unlocked and JG.player_ready(s)
	var done:=JG.completed(s)
	var claimed:=JG.claimed_own(s)
	var here:=standing_dest(s,person)
	var rows:=JG.rows(s,bag)
	var sort_block:=sort_reason(s,person)
	var ships:={}
	for dest:String in JG.DESTS:ships[dest]=ship_reason(s,person,dest)
	var claim_block:=claim_reason(s,person)
	var season:=JG.order_season(s)
	var weather:Dictionary=Weather.at(float(s.get("time",0.0)),JG.REGION)
	var signature:=JSON.stringify([unlocked,ready,done,claimed,here,rows,sort_block,ships,claim_block,season,str(weather.get("label","")),JG.today(s),JG.record(s).get("day",0)])
	if not force and str(app.modal.get_meta("jg_signature",""))==signature:return
	app.modal.set_meta("jg_signature",signature)
	var focus_before:=_focus_owner(app)
	var locked_day:=not JG.sent(s).is_empty()
	var day_line:="%s季的訂單・第 %d 日・金瓜石%s"%[str(Weather.SEASON_LABELS.get(season,"")),JG.today(s),str(weather.get("label",""))]
	if locked_day and not done:day_line="%s季的訂單（第 %d 日開始送出）・今天第 %d 日"%[str(Weather.SEASON_LABELS.get(season,"")),int(JG.record(s).get("day",0)),JG.today(s)]
	if done:day_line="%s季的訂單・第 %d 日・三箱都送到了"%[str(Weather.SEASON_LABELS.get(season,"")),int(JG.record(s).get("done_day",0))]
	_put(app,"JgDay",day_line)
	_put(app,"JgReason","波波　「"+(DONE_LINE if done else JG.reason(s))+"」")
	var hold_text:=""
	if not unlocked:hold_text=JG.LOCKED
	elif not JG.player_ready(s):hold_text=JG.NOT_READY
	_show(app,"JgHold",not hold_text.is_empty())
	_put(app,"JgHoldText",hold_text)
	_show(app,"JgSortPractice",hold_text==JG.NOT_READY)
	for part in ["JgCrates","JgClaimCard"]:_show(app,part,ready)
	# Crates.
	for row:Dictionary in rows:
		var dest:String=row.id
		var cell:Vector2i=row.cell
		_put(app,"JgCrateName_"+dest,"%s（%d,%d）"%[str(row.name),cell.x,cell.y],INK)
		_put(app,"JgCrateHow_"+dest,str(row.how),MUTED)
		_put(app,"JgCrateNeed_"+dest,"訂單：%s ×%d・背包 %d"%[str(row.needed_name),int(row.amount),int(row.have)],GOOD if int(row.have)>=int(row.amount) or bool(row.sent) else INK)
		var now:="分揀：還沒分揀"
		if not str(row.ore).is_empty():now="分揀：%s %s"%[str(row.ore_name),"✓" if bool(row.ok) else "✗ 不符訂單"]
		_put(app,"JgCrateNow_"+dest,now,GOOD if bool(row.ok) else (MUTED if str(row.ore).is_empty() else WARN))
		for ore:String in JG.ORES:
			var b:=_enable(app,"JgSort_%s_%s"%[dest,ore],sort_block.is_empty(),sort_block if not sort_block.is_empty() else ("已分揀成%s"%str(JG.ORE_NAMES[ore]) if ore==str(row.ore) else "把%s的貨箱分揀成%s"%[str(row.name),str(JG.ORE_NAMES[ore])]))
			if b!=null:b.set_pressed_no_signal(ore==str(row.ore))
		_show(app,"JgSortRow_"+dest,not done)
		var reason:String=ships[dest]
		var ship:=_enable(app,"JgShip_"+dest,reason.is_empty(),reason if not reason.is_empty() else str(row.how))
		if ship!=null:ship.visible=not bool(row.sent)
		var mark:=MARK_SENT if bool(row.sent) else MARK_OPEN
		if dest==here and not done and not bool(row.sent):mark+=MARK_HERE
		_put(app,"JgCrateMark_"+dest,mark,GOOD if bool(row.sent) else MUTED)
		# Reasons already shown elsewhere (sent / completed) are not repeated under each crate.
		var line:=reason
		if bool(row.sent) or done:line=""
		_put(app,"JgShipReason_"+dest,line,WARN)
	# Sorting: one reason for all nine buttons (the rules' block or where to stand).
	var sort_line:=sort_block if ready and not done else ""
	_put(app,"JgSortReason",sort_line,MUTED if sort_block==JG.SENT_LOCKED else WARN)
	# The lantern.
	_put(app,"JgStatus",STATUS_CLAIMED if claimed else (STATUS_DONE if done else STATUS_OPEN),GOOD if done else INK)
	_enable(app,"JgClaim",claim_block.is_empty(),claim_block if not claim_block.is_empty() else "向波波領一盞礦燈")
	_put(app,"JgClaimReason",claim_block,MUTED if claim_block in [JG.CLAIMED,JG.NOT_DONE] else WARN)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("jg_body") if app.modal.has_meta("jg_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("jg_body"):break
		node=node.get_parent()
	return true

static func focus_rows(app) -> Array:
	var rows:Array=[]
	var sort_ids:=[]
	var ship_ids:=[]
	for dest:String in JG.DESTS:
		for ore:String in JG.ORES:sort_ids.append("JgSort_%s_%s"%[dest,ore])
		ship_ids.append("JgShip_"+dest)
	for group:Array in [["JgSortPractice"],sort_ids,ship_ids,["JgClaim"],["JgBack"]]:
		var row:Array[Button]=[]
		for id:String in group:
			var b:=_node(app,id) as Button
			if b!=null and _shown(b):row.append(b)
		if not row.is_empty():rows.append(row)
	return rows

## Vertical neighbour in `row` for `b`: the same crate column when both have one (the
## pressed sort button of that crate first), else the nearest index.
static func _vertical(row:Array,b:Button,index:int) -> Button:
	if b.has_meta("jg_col"):
		var same:Array[Button]=[]
		for other:Button in row:
			if other.has_meta("jg_col") and int(other.get_meta("jg_col"))==int(b.get_meta("jg_col")):same.append(other)
		for other:Button in same:
			if other.button_pressed:return other
		if not same.is_empty():return same[0]
	return row[mini(index,row.size()-1)]

static func link_focus(app) -> void:
	var rows:=focus_rows(app)
	var close:=close_button(app)
	var flat:Array[Button]=[]
	for row:Array in rows:
		for b:Button in row:flat.append(b)
	for r in rows.size():
		var row:Array=rows[r]
		for i in row.size():
			var b:Button=row[i]
			b.focus_neighbor_left=b.get_path_to(row[(i-1+row.size())%row.size()])
			b.focus_neighbor_right=b.get_path_to(row[(i+1)%row.size()])
			if r>0:b.focus_neighbor_top=b.get_path_to(_vertical(rows[r-1],b,i))
			elif close!=null:b.focus_neighbor_top=b.get_path_to(close)
			b.focus_neighbor_bottom=b.get_path_to(_vertical(rows[r+1],b,i) if r+1<rows.size() else b)
			var at:=flat.find(b)
			b.focus_next=b.get_path_to(flat[(at+1)%flat.size()])
			b.focus_previous=b.get_path_to(flat[(at-1+flat.size())%flat.size()])
	if close!=null and not flat.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(flat[0])
		close.focus_neighbor_top=close.get_path_to(flat[flat.size()-1])
		close.focus_next=close.get_path_to(flat[0])

static func _focus_owner(app) -> Control:
	if not is_open(app):return null
	var owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if owner==null or not (app.modal as Node).is_ancestor_of(owner):return null
	return owner

static func _usable(b:Button) -> bool:
	return b!=null and _shown(b) and not b.disabled

## Claim, then the crate I stand at (or the page's crate), then the first crate that still
## needs sorting, then any crate that can be sent, then the way back.
static func preferred(app) -> Button:
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var claim:=_node(app,"JgClaim") as Button
	if _usable(claim):return claim
	var here:=standing_dest(s,person)
	if here.is_empty():here=str(ORIGIN_DEST.get(str(app.modal.get_meta("jg_origin","table")),"bobo"))
	var ship:=_node(app,"JgShip_"+here) as Button
	if _usable(ship):return ship
	for row:Dictionary in JG.rows(s):
		if bool(row.ok):continue
		var wanted:=_node(app,"JgSort_%s_%s"%[str(row.id),str(row.ore) if not str(row.ore).is_empty() else str(JG.ORES[0])]) as Button
		if _usable(wanted):return wanted
	for dest:String in JG.DESTS:
		var other:=_node(app,"JgShip_"+dest) as Button
		if _usable(other):return other
	var practice:=_node(app,"JgSortPractice") as Button
	if _usable(practice):return practice
	return _node(app,"JgBack") as Button

static func focus_first(app) -> void:
	if not is_open(app):return
	var b:=preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

## A sent crate's 送出 button disappears: focus moves to the next crate's 送出 button (its
## tooltip / reason line says where to go next), otherwise to the preferred button.
static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if not is_instance_valid(before) or not _shown(before):
		if is_instance_valid(before) and str(before.name).begins_with("JgShip_"):
			var at:=JG.DESTS.find(str(before.name).trim_prefix("JgShip_"))
			for step in range(1,JG.DESTS.size()):
				var next:=_node(app,"JgShip_"+str(JG.DESTS[(at+step)%JG.DESTS.size()])) as Button
				if next!=null and _shown(next):
					next.grab_focus.call_deferred()
					return
		_refocus_if_lost.call_deferred(app)

static func _refocus_if_lost(app) -> void:
	if not is_open(app):return
	var owner:=_focus_owner(app)
	if owner!=null and _shown(owner) and owner.is_visible_in_tree():return
	focus_first(app)

# ----------------------------------------------------------- lantern card --

static func _owner_name(s:Dictionary,owner:String) -> String:
	var found:=str(_person_of(s,owner).get("name",""))
	return found if not found.is_empty() else "另一位島民"

## Visitor card of a placed 礦燈 (any visitor, read-only).
static func lantern_card(app,cell:Vector2i) -> void:
	var s:Dictionary=app.session.snapshot
	var obj:Variant=s.get("objects",{}).get(World.key(cell),{})
	var body:VBoxContainer=app._open_modal(JG.LANTERN_NAME)
	_style(app)
	app.modal.set_meta("life_modal_layout",CARD_LAYOUT)
	app.modal.set_meta("jg_lantern_body",body)
	app.modal.set_meta("jg_lantern_cell",cell)
	var card:=_paper(body,"LanternCard",4)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	var art:=picture(Art.lantern_texture(),96)
	art.name="LanternIcon"
	row.add_child(art)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",3)
	row.add_child(words)
	_wrapped(app,words,"LanternName",20).text=JG.LANTERN_NAME
	_wrapped(app,words,"LanternBlurb",15).text=JG.LANTERN_BLURB
	_wrapped(app,words,"LanternSource",15,MUTED).text=JG.LANTERN_SOURCE
	_wrapped(app,words,"LanternProject",15,MUTED).text=JG.LANTERN_PROJECT
	var owner:=_owner_name(s,str(obj.get("owner",""))) if obj is Dictionary else ""
	if not owner.is_empty():_wrapped(app,words,"LanternOwner",14,MUTED).text="擺放者・"+owner
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="紀念物・只是裝飾，不會照明・不能出售或交易・Esc 回到島上"
	app._layout_preview.call_deferred()
