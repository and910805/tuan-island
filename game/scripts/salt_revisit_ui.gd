extends RefCounted
## 第 40 章「臺南北門回訪・鹽籃批次」頁與「鹽籃」訪客卡片（規則在 salt_revisit.gd，這裡只讀快照、
## 送動作 salt_revisit_stock / salt_revisit_pack / salt_revisit_send / salt_revisit_claim）。
##
## 入口（都用一般互動鍵進既有頁面，再按頁內按鈕；沒有新按鍵，既有鹽田流程照舊）：
##  * 阿曬 (44,17)（salt_pan_ui 的 worker 頁，認識阿曬之後）動作列「臺南北門回訪・鹽籃批次」
##    → open(app,"worker")；
##  * 合作社收鹽箱 (47,23)（salt_pan_ui 的 coop_chest 頁）同名按鈕 → open(app,"chest")；
##  * 海邊公車站／鹽田站牌 (48,25)（travel_ui 的車票頁，北門的 bus 站）同名按鈕 → open(app,"stop")；
##    三道閘門修好之前按鈕寫「鹽籃批次・三道閘門修好後開放」（提示＝規則的 LOCKED），按下去
##    頁面只顯示鎖定說明（同金瓜石回訪的做法）。
##  * 北門左上追蹤卡：鹽田章節已完成（phase complete，不蓋過還在進行的章節步驟）、本人收過鹽，
##    而且批次有「現在就能做」的一步（入倉、裝籃、送出、領鹽籃）時才改顯示批次進度；
##    「打開鹽籃批次」按鈕 → open(app,"")（依站的位置決定）。
##  * 北門鹽田手帳（salt_pan_ui 的 journal 左頁「下一步」下方）多一行批次進度 SaltRevisitLine。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  阿曬的頭像＋「季的訂單・第 n 日・北門天氣」＋阿曬的理由 → 鎖定說明（LOCKED，只在閘門沒修好時）→
##  補做說明（NOT_READY＋「翻閱鹽田手帳」，只在還沒親手收過鹽時）→ 進度一行（入倉 x／6 批（晴天、
##  多雲）・已裝 y／6 籃・雨天裝籃 z 籃）→ 左右兩張卡：
##  阿曬卡（工寮前座標、一批＝海鹽 3 份、海鹽列（背包數量＋「入倉一批」）、不能入倉的原因；雨天
##  寫出 RAIN_STOCK，並說明今天改去收鹽箱裝籃；閘門修好後最後一行 SaltBrineLine 寫儲滷槽水位）；
##  收鹽箱卡（座標、季節訂單、料理用／醃漬用兩列（已裝／訂單＋「裝一籃」）、背包纖維、原因；
##  雨天綠字「今天下雨，正好在倉棚下裝籃」；海邊公車站座標＋「送出鹽籃」）→
##  鹽籃列（狀態、領取鈕、原因）→ 原創聲明＋回到原頁。伺服器回覆由 main._notice 寫進頁底。
##  每個按鈕不能按時寫出原因：規則的 stock_block / pack_block / send_block / claim_block 優先；
##  規則允許但人站得不對時，寫出要站到哪裡（地點名稱與座標）。
##  送出的位置就是規則要的格子：入倉／領取＝阿曬 WORKER、裝籃＝收鹽箱 CHEST、送出＝公車站 STOP。
##  結構只建一次，refresh() 依快照原地更新（不重建），按鈕按下後頁面不關、焦點留在原處。
##  焦點：入倉鈕與料理用並排（左右循環），下一列醃漬用，再來送出、領取、回到原頁；
##  最上一列往上是「關閉」。
##
## 鹽籃卡片（basket_card）：任何訪客靠近擺好的鹽籃按互動鍵（main._interact）：名稱、說明、
##  來源、對應工程、擺放者；卡片放在畫面上離鹽籃較遠的那一半。
##
## 規則檔沒有、這裡自備的純函式：near / stock_reason / pack_reason / send_reason / claim_reason
##  （規則原因優先，再加上「要站到哪裡」）、tracker_text / tracking / journal_line。
const World=preload("res://scripts/world.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Weather=preload("res://scripts/weather.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/salt_revisit_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Brine=preload("res://scripts/salt_brine.gd")

const LAYOUT:="salt_revisit"
const CARD_LAYOUT:="salt_basket"
const PAGE_TITLE:=SR.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const RAIN_INK:=Color("3f5f7a")
const ENTRY:="臺南北門回訪・鹽籃批次"
const ENTRY_LOCKED:="鹽籃批次・三道閘門修好後開放"
const ORIGINS:=["worker","chest","stop"]
const BACK_TEXT:={"worker":"回到阿曬","chest":"回到合作社收鹽箱","stop":"回到鹽田站牌"}
const STOCK_TEXT:="入倉一批"
const PACK_TEXT:="裝一籃"
const SEND_TEXT:="送出鹽籃"
const CLAIM_TEXT:="領取鹽籃"
const STOCK_NOTE:="一批＝海鹽 3 份，阿曬會記下入倉那天的天氣。"
## Under RAIN_STOCK on a rainy day: where the work goes instead (the rule text already says why;
## an earlier longer note repeated it: outputs/鹽籃批次預覽/before/).
const RAIN_PACK_NOTE:="→ 雨天改做包裝：到合作社收鹽箱旁裝籃（47,23）。"
const RAIN_PACK_GOOD:="今天下雨，正好在倉棚下裝籃。"
const AWAY_STOCK:="入倉要到合作社工寮前，站在阿曬旁（%d,%d）。"
const AWAY_PACK:="裝籃要站在合作社收鹽箱旁（%d,%d）。"
const AWAY_SEND:="送出要到海邊公車站，站在鹽田站牌旁（%d,%d）。"
const AWAY_CLAIM:="領鹽籃要到合作社工寮前，站在阿曬旁（%d,%d）。"
const STATUS_OPEN:="鹽籃・批次送出後，每位親手收過鹽的島民可在阿曬那裡領一只"
const STATUS_DONE:="✓ 鹽籃批次送出了・到阿曬那裡領鹽籃"
const STATUS_CLAIMED:="✓ 已領鹽籃・在家園工坊「生活」頁擺放"
const DONE_LINE:="6 籃鹽都送上沿海公車了，辛苦大家！合作社留了幾只鹽籃，帶一只回家吧。"
const JOURNAL_BUTTON:="翻閱鹽田手帳"
## 儲滷槽 (salt_brine.gd) info line in 阿曬's card, under the rain note (SaltBrineLine): the left
## card is shorter than the chest card, so the line does not make the page taller.
const BRINE_LINE:="儲滷槽 %d／%d 桶"

# ------------------------------------------------------------ pure helpers --

static func region_of(s:Dictionary) -> String:
	return str(s.get("region_id","home"))

static func in_beimen(s:Dictionary) -> bool:
	return region_of(s)==SR.REGION

static func _person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

static func _bag(person:Dictionary) -> Dictionary:
	var bag:Variant=person.get("inventory",{})
	return bag if bag is Dictionary else {}

## The entry caption: open, or locked until the Beimen gates are repaired.
static func entry_caption(s:Dictionary) -> String:
	return ENTRY if SR.unlocked(s) else ENTRY_LOCKED

## Standing within REACH of `cell` in 北門.
static func near(s:Dictionary,person:Dictionary,cell:Vector2i) -> bool:
	if person.is_empty() or not in_beimen(s):return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=SR.REACH

## Why this button cannot be pressed ("" = it can): the rules first, then where to stand.
static func stock_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=SR.stock_block(s,_bag(person))
	if not block.is_empty():return block
	var cell:=SR.stock_cell(s)
	return "" if near(s,person,cell) else AWAY_STOCK%[cell.x,cell.y]

static func pack_reason(s:Dictionary,person:Dictionary,kind:String) -> String:
	var block:=SR.pack_block(s,kind,_bag(person))
	if not block.is_empty():return block
	var cell:=SR.pack_cell(s)
	return "" if near(s,person,cell) else AWAY_PACK%[cell.x,cell.y]

static func send_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=SR.send_block(s)
	if not block.is_empty():return block
	var cell:=SR.send_cell(s)
	return "" if near(s,person,cell) else AWAY_SEND%[cell.x,cell.y]

static func claim_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=SR.claim_block(s,_bag(person))
	if not block.is_empty():return block
	var cell:=SR.claim_cell(s)
	return "" if near(s,person,cell) else AWAY_CLAIM%[cell.x,cell.y]

## The Beimen chapter (salt_pan.own.phase) is finished: its own next step no longer needs the card.
static func chapter_done(s:Dictionary) -> bool:
	var salt:Variant=s.get("salt_pan",{})
	if not salt is Dictionary or not salt.get("own") is Dictionary:return false
	return str(salt.own.get("phase",""))=="complete"

## 北門 tracker (two short lines). "" unless the chapter is finished (a running chapter step is
## more urgent and keeps the card), the player has raked by hand, and the batch has a step they
## can do right now with what they carry (claim, send, pack or stock).
static func tracker_text(s:Dictionary,own_id:String) -> String:
	if not in_beimen(s) or not chapter_done(s) or not SR.unlocked(s) or not SR.player_ready(s):return ""
	var person:=_person_of(s,own_id)
	if person.is_empty():return ""
	var bag:=_bag(person)
	if SR.completed(s):
		return "鹽籃批次送出了\n到阿曬那裡領鹽籃" if SR.claim_block(s,bag).is_empty() else ""
	if SR.send_block(s).is_empty():return "鹽籃批次・6 籃都裝好了\n到海邊公車站送出"
	var kinds:=PackedStringArray()
	for kind:String in SR.KINDS:
		if SR.pack_block(s,kind,bag).is_empty():kinds.append(str(SR.KIND_NAMES[kind]))
	if not kinds.is_empty():
		return "鹽籃批次・已裝 %d／6 籃%s\n到收鹽箱旁裝%s"%[SR.packed_total(s),"・雨天" if SR.rainy_today(s) else "","、".join(kinds)]
	if SR.stock_block(s,bag).is_empty():return "鹽籃批次・入倉 %d／6 批\n帶海鹽找阿曬入倉"%SR.stocked_total(s)
	return ""

## The tracker card follows the batch (and its button opens this page).
static func tracking(s:Dictionary,own_id:String) -> bool:
	return not tracker_text(s,own_id).is_empty()

## One line for the 北門鹽田手帳 ("" before the gates are repaired).
static func journal_line(s:Dictionary) -> String:
	if not SR.unlocked(s):return ""
	if SR.completed(s):
		if not SR.player_ready(s):return "✓ 鹽籃批次送出了・親手收一次鹽後可以領鹽籃"
		return "✓ 鹽籃批次送出了・鹽籃已領，可擺在家園" if SR.claimed_own(s) else "✓ 鹽籃批次送出了・到阿曬那裡領鹽籃"
	if not SR.player_ready(s):return "○ 鹽籃批次：先在保留手作池親手收一次鹽，再來幫忙"
	return "○ 鹽籃批次：入倉 %d／6 批・已裝 %d／6 籃（阿曬入倉、收鹽箱裝籃、公車站送出）"%[SR.stocked_total(s),SR.packed_total(s)]

## The 儲滷槽 line on this page ("" before the Beimen gates are repaired).
static func brine_line(s:Dictionary) -> String:
	if not Brine.unlocked(s):return ""
	var level_text:=BRINE_LINE%[Brine.level(s),Brine.CAP]
	if SR.rainy_today(s):return level_text+"・雨停再放滷"
	if Weather.rains(Weather.day_index(s.get("time",0.0))+1.0,SR.REGION):return level_text+"・明日有雨"
	return level_text

static func _person(app) -> Dictionary:
	return _person_of(app.session.snapshot,str(app.session.own_id))

## Where the page was opened from by standing spot: 阿曬, else the chest/stop corner.
static func standing_origin(s:Dictionary,person:Dictionary) -> String:
	if near(s,person,SR.WORKER):return "worker"
	if near(s,person,SR.STOP) and not near(s,person,SR.CHEST):return "stop"
	return "chest"

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("sr_body")

static func card_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("sr_basket_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

## origin: "worker" / "chest" / "stop" (the Beimen page it was opened from); "" = by standing spot.
static func open(app,origin:String="") -> void:
	var s:Dictionary=app.session.snapshot
	if not in_beimen(s):return
	if not origin in ORIGINS:origin=standing_origin(s,_person(app))
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	app.modal.name="SaltRevisitPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("sr_body",body)
	app.modal.set_meta("sr_origin",origin)
	app.modal.set_meta("suppress_world_prompts",true)
	body.add_theme_constant_override("separation",5)
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:
		# Use the shared modal's gaps for content space on this denser page.
		var shell:=scroll.get_parent() as VBoxContainer
		shell.add_theme_constant_override("separation",6)
		body.minimum_size_changed.connect(app._layout_preview.call_deferred)
	build(app,body,origin)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上"
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## Entry button for 阿曬's page, the co-op chest page and the 鹽田站牌 ticket page.
static func entry_button(app,origin:String) -> Button:
	var s:Dictionary=app.session.snapshot
	var b:Button=app.button(entry_caption(s),func():open(app,origin))
	b.name="SaltRevisitEntry"
	b.focus_mode=Control.FOCUS_ALL
	b.custom_minimum_size.y=34
	b.add_theme_font_size_override("font_size",14)
	b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	b.tooltip_text="打開鹽籃批次：阿曬入倉、收鹽箱裝籃、公車站送出" if SR.unlocked(s) else SR.LOCKED
	return b

## main._layout_preview: centred, as tall as its content (the basket card sits away from the object).
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var card:=card_open(app)
	var width:=minf(880.0 if card else 940.0,bounds.x-40)
	var cap:=bounds.y-24
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
	var cell:Variant=app.modal.get_meta("sr_basket_cell",null)
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

## One row: icon, a label that fills the row and the action button on the right.
static func _row(app,parent:Node,id:String,texture:Texture2D,button_text:String,callback:Callable) -> void:
	var row:=HBoxContainer.new()
	row.name="SrRow_"+id
	row.add_theme_constant_override("separation",6)
	parent.add_child(row)
	row.add_child(picture(texture,24))
	var l:=_text(app,row,"SrLine_"+id,14)
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(app,row,"Sr_"+id,button_text,callback)

static func build(app,body:VBoxContainer,origin:String) -> void:
	# The order: season, day, Beimen weather and 阿曬's reason.
	var head:=_paper(body,"SrHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	head.add_child(row)
	var face:Texture2D=app.SaltUI.portrait("salt_worker")
	if face!=null:
		var portrait:=picture(face,48)
		portrait.name="SrPortrait"
		row.add_child(portrait)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",1)
	row.add_child(words)
	_text(app,words,"SrDay",16)
	_wrapped(app,words,"SrReason",14)
	# Locked: the three gates first.
	var locked:=_paper(body,"SrLocked")
	_wrapped(app,locked,"SrLockedText",15,WARN)
	# Not ready: rake salt by hand once first.
	var hold:=_paper(body,"SrHold")
	_wrapped(app,hold,"SrHoldText",15,WARN)
	var notebook:=_button(app,hold,"SrNotebook",JOURNAL_BUTTON,func():app.SaltUI.open(app,"journal"))
	notebook.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	# Progress.
	_text(app,body,"SrProgress",15)
	# Two cards: 阿曬 (stock) and the co-op chest (pack) with the bus stop (send).
	var cards:=HBoxContainer.new()
	cards.name="SrCards"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	var worker:=_paper(cards,"SrStockCard")
	_text(app,worker,"SrStockName",15)
	_wrapped(app,worker,"SrStockNote",13,MUTED).text=STOCK_NOTE
	_row(app,worker,"stock",Items.icon(SR.SALT_ITEM),STOCK_TEXT,func():_send_stock(app))
	_wrapped(app,worker,"SrStockReason",13,WARN)
	_wrapped(app,worker,"SrRainNote",13,RAIN_INK)
	var brine_row:=HBoxContainer.new()
	brine_row.name="SrBrineRow"
	brine_row.add_theme_constant_override("separation",6)
	worker.add_child(brine_row)
	_wrapped(app,brine_row,"SaltBrineLine",13,MUTED).vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var brine_button:=_button(app,brine_row,"SrBrine","查看儲滷槽",func():
		app.SaltBrineUI.open(app,func():open(app,origin)))
	brine_button.tooltip_text="工寮東側：雨前收滷，雨停後可放回鹽田，讓下一批海鹽更快曬好。"
	var chest:=_paper(cards,"SrPackCard")
	(chest.get_parent() as Control).size_flags_stretch_ratio=1.25
	_text(app,chest,"SrPackName",15)
	_text(app,chest,"SrOrder",13,MUTED)
	for kind:String in SR.KINDS:
		_row(app,chest,kind,Art.basket_texture(),PACK_TEXT,func():_send_pack(app,kind))
	_text(app,chest,"SrFiber",13,MUTED)
	_wrapped(app,chest,"SrRainPack",13,GOOD)
	_wrapped(app,chest,"SrPackReason",13,WARN)
	var send_row:=HBoxContainer.new()
	send_row.name="SrSendRow"
	send_row.add_theme_constant_override("separation",6)
	chest.add_child(send_row)
	_text(app,send_row,"SrStopName",14)
	_button(app,send_row,"SrSend",SEND_TEXT,func():_send_send(app))
	var mark:=_text(app,send_row,"SrSendMark",13,MUTED)
	mark.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_wrapped(app,chest,"SrSendReason",13,WARN)
	# The salt basket.
	var claim:=_paper(body,"SrClaimCard")
	var claim_row:=HBoxContainer.new()
	claim_row.add_theme_constant_override("separation",8)
	claim.add_child(claim_row)
	var icon:=picture(Art.basket_texture(),32)
	icon.name="SrBasketIcon"
	claim_row.add_child(icon)
	var status:=_wrapped(app,claim_row,"SrStatus",14)
	status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,claim_row,"SrClaim",CLAIM_TEXT,func():_send_claim(app))
	_wrapped(app,claim,"SrClaimReason",13,WARN)
	# Disclaimer and the way back to the page it was opened from.
	var foot:=HBoxContainer.new()
	foot.name="SrFooter"
	foot.add_theme_constant_override("separation",10)
	body.add_child(foot)
	var disclaimer:=_wrapped(app,foot,"SrDisclaimer",13,MUTED)
	disclaimer.text=SR.DISCLAIMER
	disclaimer.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(app,foot,"SrBack",str(BACK_TEXT.get(origin,BACK_TEXT.worker)),func():_back(app,origin))

# ------------------------------------------------------------------ actions --

static func _send_stock(app) -> void:
	if not is_open(app):return
	app.session.perform(SR.STOCK_ACTION,SR.stock_cell(app.session.snapshot))
	refresh(app,true)

static func _send_pack(app,kind:String) -> void:
	if not is_open(app):return
	app.session.perform(SR.PACK_ACTION,SR.pack_cell(app.session.snapshot),kind)
	refresh(app,true)

static func _send_send(app) -> void:
	if not is_open(app):return
	app.session.perform(SR.SEND_ACTION,SR.send_cell(app.session.snapshot))
	refresh(app,true)

static func _send_claim(app) -> void:
	if not is_open(app):return
	app.session.perform(SR.CLAIM_ACTION,SR.claim_cell(app.session.snapshot))
	refresh(app,true)

static func _back(app,origin:String) -> void:
	# main.SaltUI / main.TravelUI — not preloaded here, because salt_pan_ui and travel_ui preload this file.
	match origin:
		"chest":app.SaltUI.open(app,"coop_chest")
		"stop":app.TravelUI.open(app,"bus")
		_:app.SaltUI.open(app,"worker")

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("sr_body") as Node).find_child(id,true,false) as Control

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
	var unlocked:=SR.unlocked(s)
	var ready:=unlocked and SR.player_ready(s)
	var done:=SR.completed(s)
	var claimed:=SR.claimed_own(s)
	var progress:=SR.progress(s)
	var rows:=SR.rows(s,bag)
	var stock_r:=stock_reason(s,person)
	var packs_r:={}
	for kind:String in SR.KINDS:packs_r[kind]=pack_reason(s,person,kind)
	var send_r:=send_reason(s,person)
	var claim_r:=claim_reason(s,person)
	var season:=SR.order_season(s)
	var weather:Dictionary=Weather.at(float(s.get("time",0.0)),SR.REGION)
	var rainy:=SR.rainy_today(s)
	var counts:={"sea_salt":int(bag.get(SR.SALT_ITEM,0)),"fiber":int(bag.get(SR.FIBER_ITEM,0))}
	var signature:=JSON.stringify([unlocked,ready,done,claimed,progress,rows,stock_r,packs_r,send_r,claim_r,season,str(weather.get("label","")),SR.today(s),SR.record(s).get("day",0),SR.record(s).get("done_day",0),counts,region_of(s),brine_line(s)])
	if not force and str(app.modal.get_meta("sr_signature",""))==signature:return
	app.modal.set_meta("sr_signature",signature)
	var focus_before:=_focus_owner(app)
	var season_label:=str(Weather.SEASON_LABELS.get(season,""))
	var weather_label:=str(weather.get("label",""))
	var day_line:="%s季的訂單・第 %d 日・北門%s"%[season_label,SR.today(s),weather_label]
	if int(SR.record(s).get("day",0))>0 and not done:day_line="%s季的訂單（第 %d 日開始裝籃）・今天第 %d 日・北門%s"%[season_label,int(SR.record(s).get("day",0)),SR.today(s),weather_label]
	if done:day_line="%s季的訂單・第 %d 日送出了"%[season_label,int(SR.record(s).get("done_day",0))]
	_put(app,"SrDay",day_line)
	# The rule's reason is reported speech (「阿曬說，…」); shown as 阿曬's own words without the
	# doubled name.
	_put(app,"SrReason","阿曬　「"+(DONE_LINE if done else SR.reason(s).trim_prefix("阿曬說，"))+"」")
	_show(app,"SrLocked",not unlocked)
	_put(app,"SrLockedText",SR.LOCKED if not unlocked else "")
	_show(app,"SrHold",unlocked and not ready)
	_put(app,"SrHoldText",SR.NOT_READY if unlocked and not ready else "")
	for part in ["SrProgress","SrCards","SrClaimCard"]:_show(app,part,ready)
	# Progress.
	var lots:Dictionary=progress.stocked
	var progress_line:="入倉 %d／6 批（晴天 %d、多雲 %d）・已裝 %d／6 籃"%[int(progress.stocked_total),int(lots.sunny),int(lots.cloudy),int(progress.packed_total)]
	if int(progress.rain_packs)>0:progress_line+="（雨天裝 %d 籃）"%int(progress.rain_packs)
	_put(app,"SrProgress",progress_line if ready else "",GOOD if done else INK)
	# 阿曬: stock.
	_put(app,"SrStockName","阿曬・合作社工寮前（%d,%d）"%[SR.WORKER.x,SR.WORKER.y],INK)
	var salt_have:=int(counts.sea_salt)
	_put(app,"SrLine_stock","海鹽・背包 %d"%salt_have,INK if salt_have>=SR.LOT_SALT else MUTED)
	var stock:=_enable(app,"Sr_stock",stock_r.is_empty(),stock_r if not stock_r.is_empty() else "把海鹽 3 份交給阿曬入倉")
	if stock!=null:stock.visible=not done
	_show(app,"SrStockNote",not done)
	var stock_line:="" if done else stock_r
	_put(app,"SrStockReason",stock_line,MUTED if stock_line==SR.STOCK_FULL else (RAIN_INK if stock_line==SR.RAIN_STOCK else WARN))
	# A rainy day: say plainly that packing goes on (「雨天轉做包裝」).
	_put(app,"SrRainNote",RAIN_PACK_NOTE if rainy and not done and stock_line==SR.RAIN_STOCK else "")
	_put(app,"SaltBrineLine",brine_line(s),MUTED)
	_show(app,"SrBrineRow",Brine.unlocked(s) and not done)
	# Co-op chest: pack.
	_put(app,"SrPackName","合作社收鹽箱（%d,%d）"%[SR.CHEST.x,SR.CHEST.y],INK)
	var order:Dictionary=progress.order
	_put(app,"SrOrder","%s季訂單：料理用 %d 籃、醃漬用 %d 籃"%[season_label,int(order.kitchen),int(order.pickle)],MUTED)
	for row:Dictionary in rows:
		var kind:String=row.id
		var reason:String=packs_r[kind]
		var full:=bool(row.full)
		_put(app,"SrLine_"+kind,"%s 已裝 %d／%d%s"%[str(row.name),int(row.packed),int(row.need)," ✓" if full else ""],GOOD if full else INK)
		var b:=_enable(app,"Sr_"+kind,reason.is_empty(),reason if not reason.is_empty() else "在收鹽箱旁裝一籃%s的鹽（纖維 2 份）"%str(row.name))
		if b!=null:b.visible=not done
	var fiber_have:=int(counts.fiber)
	_put(app,"SrFiber","" if done else "纖維・背包 %d（一籃用 %d 份，編籃、綁口）"%[fiber_have,SR.FIBER_PER_BASKET],INK if fiber_have>=SR.FIBER_PER_BASKET else MUTED)
	var can_pack:=false
	for kind:String in SR.KINDS:
		if str(packs_r[kind]).is_empty():can_pack=true
	_put(app,"SrRainPack",RAIN_PACK_GOOD if rainy and can_pack and not done else "")
	var pack_line:="" if done else _reasons(packs_r.values())
	_put(app,"SrPackReason",pack_line,GOOD if pack_line==SR.ALL_PACKED else WARN)
	_put(app,"SrStopName","海邊公車站（%d,%d）"%[SR.STOP.x,SR.STOP.y],INK)
	var send:=_enable(app,"SrSend",send_r.is_empty(),send_r if not send_r.is_empty() else "6 籃都裝好了，送上沿海公車")
	if send!=null:send.visible=not done
	var mark:="✓ 第 %d 日送出"%int(SR.record(s).get("done_day",0)) if done else ("○ 6 籃都裝好了" if bool(progress.ready_to_send) else "○ 還沒送出")
	_put(app,"SrSendMark",mark,GOOD if done or bool(progress.ready_to_send) else MUTED)
	# The send reason is only worth a line once the six baskets are packed (before that the pack
	# reasons already say what is missing).
	_put(app,"SrSendReason",send_r if bool(progress.ready_to_send) and not done else "",WARN)
	# The salt basket.
	_put(app,"SrStatus",STATUS_CLAIMED if claimed else (STATUS_DONE if done else STATUS_OPEN),GOOD if done else INK)
	_enable(app,"SrClaim",claim_r.is_empty(),claim_r if not claim_r.is_empty() else "向阿曬領一只鹽籃")
	_put(app,"SrClaimReason",claim_r,MUTED if claim_r in [SR.CLAIMED,SR.NOT_DONE] else WARN)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("sr_body") if app.modal.has_meta("sr_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("sr_body"):break
		node=node.get_parent()
	return true

## Rows of focusable buttons (visual order): notebook; stock ↔ kitchen; pickle; send; claim; back.
static func focus_rows(app) -> Array:
	var rows:Array=[]
	for group:Array in [["SrNotebook"],["Sr_stock","Sr_kitchen"],["Sr_pickle"],["SrSend"],["SrBrine"],["SrClaim"],["SrBack"]]:
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
			# 醃漬用 sits under 料理用 in the right-hand card: up goes back to 料理用.
			if b.name=="Sr_pickle" and r>0 and (rows[r-1] as Array).size()>1 and str((rows[r-1][1] as Button).name)=="Sr_kitchen":
				b.focus_neighbor_top=b.get_path_to(rows[r-1][1])
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

## Claim, then what can be done where I stand (stock at 阿曬; send / pack at the chest corner),
## then any usable button, then the notebook (not ready), then the first shown action, then back.
static func preferred(app) -> Button:
	var order:Array=["SrClaim"]
	if standing_origin(app.session.snapshot,_person(app))=="worker":order.append_array(["Sr_stock","Sr_kitchen","Sr_pickle","SrSend"])
	else:order.append_array(["SrSend","Sr_kitchen","Sr_pickle","Sr_stock"])
	for id:String in order:
		var b:=_node(app,id) as Button
		if _usable(b):return b
	var notebook:=_node(app,"SrNotebook") as Button
	if _usable(notebook):return notebook
	# Nothing can be pressed: rest on the first visible action here (or on 領取 once the batch is
	# sent), so its tooltip and the reason line below it say what is missing.
	for id:String in (["SrClaim"] if SR.completed(app.session.snapshot) else order.slice(1)):
		var b:=_node(app,id) as Button
		if b!=null and _shown(b):return b
	return _node(app,"SrBack") as Button

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

# ------------------------------------------------------------ basket card --

static func _owner_name(s:Dictionary,owner:String) -> String:
	var found:=str(_person_of(s,owner).get("name",""))
	return found if not found.is_empty() else "另一位島民"

## Visitor card of a placed 鹽籃 (any visitor, read-only).
static func basket_card(app,cell:Vector2i) -> void:
	var s:Dictionary=app.session.snapshot
	var obj:Variant=s.get("objects",{}).get(World.key(cell),{})
	var body:VBoxContainer=app._open_modal(SR.BASKET_NAME)
	_style(app)
	app.modal.set_meta("life_modal_layout",CARD_LAYOUT)
	app.modal.set_meta("sr_basket_body",body)
	app.modal.set_meta("sr_basket_cell",cell)
	var card:=_paper(body,"BasketCard",4)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	var art:=picture(Art.basket_texture(),80)
	art.name="BasketIcon"
	row.add_child(art)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",3)
	row.add_child(words)
	_wrapped(app,words,"BasketName",20).text=SR.BASKET_NAME
	_wrapped(app,words,"BasketBlurb",15).text=SR.BASKET_BLURB
	# Source and project share one line so the card stays short and leaves the basket in view.
	var provenance:=HBoxContainer.new()
	provenance.add_theme_constant_override("separation",16)
	words.add_child(provenance)
	_text(app,provenance,"BasketSource",15,MUTED).text=SR.BASKET_SOURCE
	_text(app,provenance,"BasketProject",15,MUTED).text=SR.BASKET_PROJECT
	var owner:=_owner_name(s,str(obj.get("owner",""))) if obj is Dictionary else ""
	if not owner.is_empty():_wrapped(app,words,"BasketOwner",14,MUTED).text="擺放者・"+owner
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="紀念物・只是裝飾・不能出售或交易・Esc 回到島上"
	app._layout_preview.call_deferred()
