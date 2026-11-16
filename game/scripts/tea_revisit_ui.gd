extends RefCounted
## 第 40 章「貓空與鶯歌回訪・茶罐大單」頁與「茶陶組」訪客卡片（規則在 tea_revisit.gd，這裡只讀
## 快照、送動作 tea_revisit_jar / tea_revisit_fill / tea_revisit_send / tea_revisit_claim）。
##
## 入口（都用一般互動鍵進既有頁面，再按頁內按鈕；沒有新按鍵，既有茶陶流程照舊）：
##  * 鶯歌陶師的工作桌 (20,20)（tea_ceramics_ui 的 potter 頁）底部「貓空與鶯歌回訪・茶罐大單」
##    → open(app,"potter")；
##  * 貓空包裝台 (26,20)（tea_ceramics_ui 的 pack 頁）同名按鈕 → open(app,"pack")；
##    兩個按鈕在收下小栗的介紹信之後才出現（還沒開始茶陶故事的人看不到）。
##  * 貓空／鶯歌左上追蹤卡：完成包裝比較的島民，大單有「現在就能做」的一步時（交罐、裝茶、
##    寄出、領茶陶組）才改顯示大單；否則保留茶陶手帳的下一步（做罐、採茶、烘焙），
##    讓玩家先備齊空罐與茶。「打開茶罐大單」按鈕 → open(app,"")（依所在地區決定）。
##  * 茶陶合作手帳（tea_ceramics_ui 的 journal 頁）完成比較後多一行大單進度（TeaRevisitLine）。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  茶茶的頭像＋「季的訂單・第 n 日・貓空天氣」＋茶茶的理由 → 補做說明（NOT_READY，只在需要時，
##  附「翻閱茶陶手帳」）→ 進度一行（回收空罐 x／6・已裝 x／6）→ 左右兩張卡：
##  鶯歌卡（陶師工作桌座標、只收送貨回來的空罐且交出不退回的說明、回收陶罐／磨損陶罐兩列
##  （背包數量＋「交一只」）、背包裡新罐／待修罐為什麼不收、不能交的原因）；
##  貓空卡（包裝台座標、淺焙／深焙兩列（已裝／訂單・背包＋「裝一罐」）、「寄出大單」、原因）→
##  茶陶組列（狀態、領取鈕、原因）→ 原創聲明＋回到原頁。伺服器回覆由 main._notice 寫進頁底。
##  每個按鈕不能按時寫出原因：規則的 jar_block / fill_block / send_block / claim_block 優先；
##  規則允許但人在另一個地區或太遠時，寫出要去哪裡（地區名稱與座標）。
##  送出的位置就是規則要的格子：交罐／領取＝陶師工作桌 POTTER、裝茶／寄出＝包裝台 PACKER。
##  結構只建一次，refresh() 依快照原地更新（不重建），按鈕按下後頁面不關、焦點留在原處。
##  焦點：交罐鈕與裝茶鈕兩兩一列（左右循環：回收陶罐↔淺焙、磨損陶罐↔深焙）、寄出、領取、
##  回到原頁；最上一列往上是「關閉」。
##
## 茶陶組卡片（teaware_card）：任何訪客靠近擺好的茶陶組按互動鍵（main._interact）：名稱、說明、
##  來源、對應紀錄、擺放者；卡片放在畫面上離茶陶組較遠的那一半。
##
## 規則檔沒有、這裡自備的純函式：near / jar_reason / fill_reason / send_reason / claim_reason
##  （規則原因優先，再加上「要站到哪裡」）、tracker_text / tracking / journal_line。
const World=preload("res://scripts/world.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Weather=preload("res://scripts/weather.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/tea_revisit_art.gd")
const TeaArt=preload("res://scripts/tea_ceramics_art.gd")
const Residents=preload("res://scripts/tea_resident_art.gd")

const LAYOUT:="tea_revisit"
const CARD_LAYOUT:="tea_ware"
const PAGE_TITLE:=TR.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const ENTRY:="貓空與鶯歌回訪・茶罐大單"
const REGIONS:={"potter":TR.JAR_REGION,"pack":TR.FILL_REGION}
const BACK_TEXT:={"potter":"回到陶師的工作桌","pack":"回到包裝與寄運"}
const PLACE:={"yingge":"鶯歌合作陶坊","maokong":"貓空合作茶園"}
const JAR_TEXT:="交一只"
const FILL_TEXT:="裝一罐"
const SEND_TEXT:="寄出大單"
const CLAIM_TEXT:="領取茶陶組"
const JAR_NOTE:="只收送貨回來的空罐（回收陶罐、磨損陶罐）；交給陶師的空罐留給大單用，不會退回。"
const AWAY_JAR:="交罐要到鶯歌合作陶坊，站在陶師的工作桌旁（%d,%d）。"
const AWAY_FILL:="裝茶要到貓空合作茶園，站在包裝台旁（%d,%d）。"
const AWAY_SEND:="寄出要到貓空合作茶園，站在包裝台旁（%d,%d）。"
const AWAY_CLAIM:="領茶陶組要到鶯歌合作陶坊，站在陶師的工作桌旁（%d,%d）。"
const STATUS_OPEN:="茶陶組・大單寄出後，每人可在鶯歌陶師那裡領一組"
const STATUS_DONE:="✓ 茶罐大單寄出了・到鶯歌陶師那裡領茶陶組"
const STATUS_CLAIMED:="✓ 已領茶陶組・在家園工坊「生活」頁擺放"
const DONE_LINE:="6 罐茶都寄出了，謝謝你們一起跑兩地！陶師準備了茶陶組，帶一組回家吧。"
const JOURNAL_BUTTON:="翻閱茶陶手帳"

# ------------------------------------------------------------ pure helpers --

static func region_of(s:Dictionary) -> String:
	return str(s.get("region_id","home"))

static func in_tea_region(s:Dictionary) -> bool:
	return region_of(s) in [TR.JAR_REGION,TR.FILL_REGION]

static func _person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

static func _bag(person:Dictionary) -> Dictionary:
	var bag:Variant=person.get("inventory",{})
	return bag if bag is Dictionary else {}

## Standing within REACH of `cell` in `region`.
static func near(s:Dictionary,person:Dictionary,region:String,cell:Vector2i) -> bool:
	if person.is_empty() or region_of(s)!=region:return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=TR.REACH

## Why this jar button cannot be pressed ("" = it can): the rules first, then where to stand.
static func jar_reason(s:Dictionary,person:Dictionary,item:String) -> String:
	var block:=TR.jar_block(s,item,_bag(person))
	if not block.is_empty():return block
	var cell:=TR.jar_cell(s)
	return "" if near(s,person,TR.JAR_REGION,cell) else AWAY_JAR%[cell.x,cell.y]

static func fill_reason(s:Dictionary,person:Dictionary,style:String) -> String:
	var block:=TR.fill_block(s,style,_bag(person))
	if not block.is_empty():return block
	var cell:=TR.fill_cell(s)
	return "" if near(s,person,TR.FILL_REGION,cell) else AWAY_FILL%[cell.x,cell.y]

static func send_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=TR.send_block(s)
	if not block.is_empty():return block
	var cell:=TR.send_cell(s)
	return "" if near(s,person,TR.FILL_REGION,cell) else AWAY_SEND%[cell.x,cell.y]

static func claim_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=TR.claim_block(s,_bag(person))
	if not block.is_empty():return block
	var cell:=TR.claim_cell(s)
	return "" if near(s,person,TR.JAR_REGION,cell) else AWAY_CLAIM%[cell.x,cell.y]

## 貓空／鶯歌 tracker (two short lines). "" unless the player is ready and the order has a
## step they can do right now with what they carry (hand in a jar, fill, send or claim);
## otherwise the tea notebook keeps the tracker so it can lead to jars and tea first.
static func tracker_text(s:Dictionary,own_id:String) -> String:
	if not in_tea_region(s) or not TR.player_ready(s):return ""
	var person:=_person_of(s,own_id)
	if person.is_empty():return ""
	var bag:=_bag(person)
	if TR.completed(s):
		return "茶罐大單寄出了\n到鶯歌陶師那裡領茶陶組" if TR.claim_block(s,bag).is_empty() else ""
	if TR.send_block(s).is_empty():return "茶罐大單・6 罐都裝好了\n到貓空的包裝台寄出"
	var styles:=PackedStringArray()
	for style:String in TR.STYLES:
		if TR.fill_block(s,style,bag).is_empty():styles.append(str(TR.STYLE_NAMES[style]))
	if not styles.is_empty():return "茶罐大單・已裝 %d／6\n到貓空的包裝台裝%s"%[TR.filled_total(s),"、".join(styles)]
	for item:String in TR.JAR_ITEMS:
		if TR.jar_block(s,item,bag).is_empty():return "茶罐大單・空罐 %d／6\n帶回收空罐到鶯歌交給陶師"%TR.jars_total(s)
	return ""

## The tracker card follows the order (and its button opens this page).
static func tracking(s:Dictionary,own_id:String) -> bool:
	return not tracker_text(s,own_id).is_empty()

## One line for the 茶陶合作手帳 page ("" before the comparison).
static func journal_line(s:Dictionary) -> String:
	if not TR.player_ready(s):return ""
	if TR.completed(s):
		return "✓ 茶罐大單寄出了・茶陶組已領，可擺在家園" if TR.claimed_own(s) else "✓ 茶罐大單寄出了・到鶯歌陶師那裡領茶陶組"
	return "○ 茶罐大單：回收空罐 %d／6・已裝 %d／6（鶯歌交罐、貓空裝茶寄出）"%[TR.jars_total(s),TR.filled_total(s)]

static func _person(app) -> Dictionary:
	return _person_of(app.session.snapshot,str(app.session.own_id))

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("tr_body")

static func card_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("tr_teaware_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

## origin: "potter" / "pack" (the tea page it was opened from); "" = by region.
static func open(app,origin:String="") -> void:
	var s:Dictionary=app.session.snapshot
	if not in_tea_region(s):return
	if not REGIONS.has(origin):origin="potter" if region_of(s)==TR.JAR_REGION else "pack"
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	app.modal.name="TeaRevisitPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("tr_body",body)
	app.modal.set_meta("tr_origin",origin)
	body.add_theme_constant_override("separation",6)
	build(app,body,origin)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上"
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## Entry button for the tea potter page and the packing page.
static func entry_button(app,origin:String) -> Button:
	var b:Button=app.button(ENTRY,func():open(app,origin))
	b.name="TeaRevisitEntry"
	b.focus_mode=Control.FOCUS_ALL
	b.custom_minimum_size.y=34
	b.add_theme_font_size_override("font_size",14)
	b.tooltip_text="打開茶罐大單：鶯歌交回收空罐、貓空裝茶寄出"
	return b

## main._layout_preview: centred, as tall as its content (the tea ware card sits away from the object).
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var card:=card_open(app)
	var width:=minf(880.0 if card else 920.0,bounds.x-48)
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
	if card:modal.position.y=bounds.y-height-16.0 if _object_on_top(app,bounds) else 16.0

static func _object_on_top(app,bounds:Vector2) -> bool:
	var cell:Variant=app.modal.get_meta("tr_teaware_cell",null)
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

## One item row: icon, a label that fills the row and the action button on the right.
static func _row(app,parent:Node,id:String,texture:Texture2D,button_text:String,callback:Callable) -> void:
	var row:=HBoxContainer.new()
	row.name="TrRow_"+id
	row.add_theme_constant_override("separation",6)
	parent.add_child(row)
	row.add_child(picture(texture,24))
	var l:=_text(app,row,"TrLine_"+id,14)
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(app,row,"Tr_"+id,button_text,callback)

static func build(app,body:VBoxContainer,origin:String) -> void:
	# The order: season, day, weather and 茶茶's reason.
	var head:=_paper(body,"TrHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	head.add_child(row)
	var portrait:=picture(Residents.portrait("host"),48)
	portrait.name="TrPortrait"
	row.add_child(portrait)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",1)
	row.add_child(words)
	_text(app,words,"TrDay",16)
	_wrapped(app,words,"TrReason",14)
	# Not ready: finish the comparison with 茶茶 first.
	var hold:=_paper(body,"TrHold")
	_wrapped(app,hold,"TrHoldText",15,WARN)
	var notebook:=_button(app,hold,"TrNotebook",JOURNAL_BUTTON,func():app.TeaUI.open(app,"journal"))
	notebook.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	# Progress.
	_text(app,body,"TrProgress",15)
	# Two cards: 鶯歌 (jars) and 貓空 (fill and send).
	var cards:=HBoxContainer.new()
	cards.name="TrCards"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	var yingge:=_paper(cards,"TrYingge")
	_text(app,yingge,"TrYinggeName",15)
	_wrapped(app,yingge,"TrJarNote",13,MUTED).text=JAR_NOTE
	for item:String in TR.JAR_ITEMS:
		_row(app,yingge,item,TeaArt.icon(item),JAR_TEXT,func():_send_jar(app,item))
	_wrapped(app,yingge,"TrJarOther",13,MUTED)
	_wrapped(app,yingge,"TrJarReason",13,WARN)
	var maokong:=_paper(cards,"TrMaokong")
	_text(app,maokong,"TrMaokongName",15)
	_text(app,maokong,"TrOrder",13,MUTED)
	for style:String in TR.STYLES:
		_row(app,maokong,style,TeaArt.icon(str(TR.TEA_ITEMS[style])),FILL_TEXT,func():_send_fill(app,style))
	_wrapped(app,maokong,"TrFillReason",13,WARN)
	var send_row:=HBoxContainer.new()
	send_row.name="TrSendRow"
	send_row.add_theme_constant_override("separation",6)
	maokong.add_child(send_row)
	_button(app,send_row,"TrSend",SEND_TEXT,func():_send_send(app))
	var mark:=_text(app,send_row,"TrSendMark",13,MUTED)
	mark.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_wrapped(app,maokong,"TrSendReason",13,WARN)
	# The tea ware.
	var claim:=_paper(body,"TrClaimCard")
	var claim_row:=HBoxContainer.new()
	claim_row.add_theme_constant_override("separation",8)
	claim.add_child(claim_row)
	var icon:=picture(Art.teaware_texture(),32)
	icon.name="TrTeawareIcon"
	claim_row.add_child(icon)
	var status:=_wrapped(app,claim_row,"TrStatus",14)
	status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,claim_row,"TrClaim",CLAIM_TEXT,func():_send_claim(app))
	_wrapped(app,claim,"TrClaimReason",13,WARN)
	# Disclaimer and the way back to the page it was opened from.
	var foot:=HBoxContainer.new()
	foot.name="TrFooter"
	foot.add_theme_constant_override("separation",10)
	body.add_child(foot)
	var disclaimer:=_wrapped(app,foot,"TrDisclaimer",13,MUTED)
	disclaimer.text=TR.DISCLAIMER
	disclaimer.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,foot,"TrBack",str(BACK_TEXT.get(origin,BACK_TEXT.potter)),func():_back(app,origin))

# ------------------------------------------------------------------ actions --

static func _send_jar(app,item:String) -> void:
	if not is_open(app):return
	app.session.perform(TR.JAR_ACTION,TR.jar_cell(app.session.snapshot),item)
	refresh(app,true)

static func _send_fill(app,style:String) -> void:
	if not is_open(app):return
	app.session.perform(TR.FILL_ACTION,TR.fill_cell(app.session.snapshot),style)
	refresh(app,true)

static func _send_send(app) -> void:
	if not is_open(app):return
	app.session.perform(TR.SEND_ACTION,TR.send_cell(app.session.snapshot))
	refresh(app,true)

static func _send_claim(app) -> void:
	if not is_open(app):return
	app.session.perform(TR.CLAIM_ACTION,TR.claim_cell(app.session.snapshot))
	refresh(app,true)

static func _back(app,origin:String) -> void:
	# main.TeaUI (tea_ceramics_ui) — not preloaded here, because tea_ceramics_ui preloads this file.
	app.TeaUI.open(app,origin if REGIONS.has(origin) else "potter")

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("tr_body") as Node).find_child(id,true,false) as Control

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

## Distinct non-empty reasons, one per line (the same reason is shown once).
static func _reasons(values:Array) -> String:
	var out:=PackedStringArray()
	for v in values:
		if not str(v).is_empty() and not out.has(str(v)):out.append(str(v))
	return "\n".join(out)

static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var bag:=_bag(person)
	var ready:=TR.player_ready(s)
	var done:=TR.completed(s)
	var claimed:=TR.claimed_own(s)
	var progress:=TR.progress(s)
	var rows:=TR.rows(s,bag)
	var jars_r:={}
	for item:String in TR.JAR_ITEMS:jars_r[item]=jar_reason(s,person,item)
	var fills_r:={}
	for style:String in TR.STYLES:fills_r[style]=fill_reason(s,person,style)
	var send_r:=send_reason(s,person)
	var claim_r:=claim_reason(s,person)
	var season:=TR.order_season(s)
	var weather:Dictionary=Weather.at(float(s.get("time",0.0)),TR.FILL_REGION)
	var counts:={}
	for item:String in ["tea_returned_jar","tea_worn_jar","tea_jar","tea_spent_jar"]:counts[item]=int(bag.get(item,0))
	var signature:=JSON.stringify([ready,done,claimed,progress,rows,jars_r,fills_r,send_r,claim_r,season,str(weather.get("label","")),TR.today(s),TR.record(s).get("day",0),TR.record(s).get("done_day",0),counts,region_of(s)])
	if not force and str(app.modal.get_meta("tr_signature",""))==signature:return
	app.modal.set_meta("tr_signature",signature)
	var focus_before:=_focus_owner(app)
	var season_label:=str(Weather.SEASON_LABELS.get(season,""))
	var day_line:="%s季的訂單・第 %d 日・貓空%s"%[season_label,TR.today(s),str(weather.get("label",""))]
	if int(TR.record(s).get("day",0))>0 and not done:day_line="%s季的訂單（第 %d 日開始裝茶）・今天第 %d 日"%[season_label,int(TR.record(s).get("day",0)),TR.today(s)]
	if done:day_line="%s季的訂單・第 %d 日寄出了"%[season_label,int(TR.record(s).get("done_day",0))]
	_put(app,"TrDay",day_line)
	# The rule's reason is reported speech (「茶茶說，…」); shown as 茶茶's own words without the
	# doubled name.
	_put(app,"TrReason","茶茶　「"+(DONE_LINE if done else TR.reason(s).trim_prefix("茶茶說，"))+"」")
	_show(app,"TrHold",not ready)
	_put(app,"TrHoldText",TR.NOT_READY if not ready else "")
	for part in ["TrProgress","TrCards","TrClaimCard"]:_show(app,part,ready)
	# Progress.
	var jars:Dictionary=progress.jars
	_put(app,"TrProgress","回收空罐 %d／6（回收陶罐 %d、磨損陶罐 %d）・已裝 %d／6"%[int(progress.jars_total),int(jars.tea_returned_jar),int(jars.tea_worn_jar),int(progress.filled_total)] if ready else "",GOOD if done else INK)
	# 鶯歌: jars.
	_put(app,"TrYinggeName","鶯歌・陶師的工作桌（%d,%d）"%[TR.POTTER.x,TR.POTTER.y],INK)
	for item:String in TR.JAR_ITEMS:
		var reason:String=jars_r[item]
		_put(app,"TrLine_"+item,"%s・背包 %d"%[str(TR.JAR_NAMES[item]),int(bag.get(item,0))],INK if int(bag.get(item,0))>0 else MUTED)
		var b:=_enable(app,"Tr_"+item,reason.is_empty(),reason if not reason.is_empty() else "把一只%s交給陶師（交出不退回）"%str(TR.JAR_NAMES[item]))
		if b!=null:b.visible=not done
	var other:=PackedStringArray()
	if not done and ready:
		for item:String in ["tea_jar","tea_spent_jar"]:
			if int(bag.get(item,0))>0:other.append(TR.jar_block(s,item,bag))
	_put(app,"TrJarOther","\n".join(other))
	var jar_line:="" if done else _reasons(jars_r.values())
	_put(app,"TrJarReason",jar_line,MUTED if jar_line==TR.JARS_FULL else WARN)
	# 貓空: fill and send.
	_put(app,"TrMaokongName","貓空・包裝台（%d,%d）"%[TR.PACKER.x,TR.PACKER.y],INK)
	var order:Dictionary=progress.order
	_put(app,"TrOrder","%s季訂單：淺焙 %d 罐、深焙 %d 罐"%[season_label,int(order.light),int(order.deep)],MUTED)
	for row:Dictionary in rows:
		var style:String=row.id
		var reason:String=fills_r[style]
		var full:=bool(row.full)
		_put(app,"TrLine_"+style,"%s 已裝 %d／%d・背包 %d%s"%[str(row.name),int(row.filled),int(row.need),int(row.have)," ✓" if full else ""],GOOD if full else INK)
		var b:=_enable(app,"Tr_"+style,reason.is_empty(),reason if not reason.is_empty() else "在包裝台裝一罐%s"%str(row.tea_name))
		if b!=null:b.visible=not done
	var fill_line:="" if done else _reasons(fills_r.values())
	_put(app,"TrFillReason",fill_line,GOOD if fill_line==TR.ALL_FILLED else WARN)
	var send:=_enable(app,"TrSend",send_r.is_empty(),send_r if not send_r.is_empty() else "6 罐都裝好了，寄給渡口")
	if send!=null:send.visible=not done
	var mark:="✓ 第 %d 日寄出"%int(TR.record(s).get("done_day",0)) if done else ("○ 6 罐都裝好了" if bool(progress.ready_to_send) else "○ 還沒寄出")
	_put(app,"TrSendMark",mark,GOOD if done or bool(progress.ready_to_send) else MUTED)
	# The send reason is only worth a line once the six jars are filled (before that the fill
	# reasons already say what is missing).
	_put(app,"TrSendReason",send_r if bool(progress.ready_to_send) and not done else "",WARN)
	# The tea ware.
	_put(app,"TrStatus",STATUS_CLAIMED if claimed else (STATUS_DONE if done else STATUS_OPEN),GOOD if done else INK)
	_enable(app,"TrClaim",claim_r.is_empty(),claim_r if not claim_r.is_empty() else "向陶師領一組茶陶組")
	_put(app,"TrClaimReason",claim_r,MUTED if claim_r in [TR.CLAIMED,TR.NOT_DONE] else WARN)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("tr_body") if app.modal.has_meta("tr_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("tr_body"):break
		node=node.get_parent()
	return true

## Rows of focusable buttons (visual order): notebook; returned jar ↔ light; worn jar ↔ deep;
## send; claim; back.
static func focus_rows(app) -> Array:
	var rows:Array=[]
	for group:Array in [["TrNotebook"],["Tr_tea_returned_jar","Tr_light"],["Tr_tea_worn_jar","Tr_deep"],["TrSend"],["TrClaim"],["TrBack"]]:
		var row:Array[Button]=[]
		for id:String in group:
			var b:=_node(app,id) as Button
			if b!=null and _shown(b):row.append(b)
		if not row.is_empty():rows.append(row)
	return rows

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
			if r>0:b.focus_neighbor_top=b.get_path_to(rows[r-1][mini(i,rows[r-1].size()-1)])
			elif close!=null:b.focus_neighbor_top=b.get_path_to(close)
			b.focus_neighbor_bottom=b.get_path_to(rows[r+1][mini(i,rows[r+1].size()-1)] if r+1<rows.size() else b)
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

## Claim, then what can be done where I stand (send / fill in 貓空, jars in 鶯歌), then any
## usable button, then the notebook (not ready), then the first shown action, then back.
static func preferred(app) -> Button:
	var order:Array=["TrClaim"]
	if region_of(app.session.snapshot)==TR.FILL_REGION:order.append_array(["TrSend","Tr_light","Tr_deep","Tr_tea_returned_jar","Tr_tea_worn_jar"])
	else:order.append_array(["Tr_tea_returned_jar","Tr_tea_worn_jar","TrSend","Tr_light","Tr_deep"])
	for id:String in order:
		var b:=_node(app,id) as Button
		if _usable(b):return b
	var notebook:=_node(app,"TrNotebook") as Button
	if _usable(notebook):return notebook
	# Nothing can be pressed: rest on the first visible action of this region (or on 領取 once
	# the order is sent), so its tooltip and the reason line below it say what is missing.
	for id:String in (["TrClaim"] if TR.completed(app.session.snapshot) else order.slice(1)):
		var b:=_node(app,id) as Button
		if b!=null and _shown(b):return b
	return _node(app,"TrBack") as Button

static func focus_first(app) -> void:
	if not is_open(app):return
	var b:=preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if not is_instance_valid(before) or not _shown(before):_refocus_if_lost.call_deferred(app)

static func _refocus_if_lost(app) -> void:
	if not is_open(app):return
	var owner:=_focus_owner(app)
	if owner!=null and _shown(owner) and owner.is_visible_in_tree():return
	focus_first(app)

# --------------------------------------------------------- tea ware card --

static func _owner_name(s:Dictionary,owner:String) -> String:
	var found:=str(_person_of(s,owner).get("name",""))
	return found if not found.is_empty() else "另一位島民"

## Visitor card of a placed 茶陶組 (any visitor, read-only).
static func teaware_card(app,cell:Vector2i) -> void:
	var s:Dictionary=app.session.snapshot
	var obj:Variant=s.get("objects",{}).get(World.key(cell),{})
	var body:VBoxContainer=app._open_modal(TR.TEAWARE_NAME)
	_style(app)
	app.modal.set_meta("life_modal_layout",CARD_LAYOUT)
	app.modal.set_meta("tr_teaware_body",body)
	app.modal.set_meta("tr_teaware_cell",cell)
	var card:=_paper(body,"TeawareCard",4)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	var art:=picture(Art.teaware_texture(),80)
	art.name="TeawareIcon"
	row.add_child(art)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",3)
	row.add_child(words)
	_wrapped(app,words,"TeawareName",20).text=TR.TEAWARE_NAME
	_wrapped(app,words,"TeawareBlurb",15).text=TR.TEAWARE_BLURB
	# Source and project share one line so the card stays short enough to leave the tea ware
	# in view at 1024×640 (a taller card covered it; outputs/茶罐大單預覽/before/).
	var provenance:=HBoxContainer.new()
	provenance.add_theme_constant_override("separation",16)
	words.add_child(provenance)
	_text(app,provenance,"TeawareSource",15,MUTED).text=TR.TEAWARE_SOURCE
	_text(app,provenance,"TeawareProject",15,MUTED).text=TR.TEAWARE_PROJECT
	var owner:=_owner_name(s,str(obj.get("owner",""))) if obj is Dictionary else ""
	if not owner.is_empty():_wrapped(app,words,"TeawareOwner",14,MUTED).text="擺放者・"+owner
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="紀念物・只是裝飾・不能出售或交易・Esc 回到島上"
	app._layout_preview.call_deferred()
