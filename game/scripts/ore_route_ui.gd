extends RefCounted
## 第 40 章金瓜石初訪「沿運礦路線送一批礦料」頁（規則在 ore_route.gd，這裡只讀快照、送動作
## ore_cart，cell＝台車現在的格 Route.cart_cell(stage)，extra＝下一步 load／push／unload）。
##
## 入口：金瓜石山城的運礦台車（會隨階段沿軌道移動）。main._interact 把 POINT（"ore_cart"）加進
##  金瓜石的互動點，位置是台車現在的格；靠近按一般互動鍵時 interact()：空車（階段 0）開這頁，
##  台車已裝好（階段 ≥1）時不開頁、直接送下一步（伺服器的訊息走一般提示）。沒有新按鍵。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  標頭卡（今天 n／2 車・累計 n 車）→ 台車卡（64×64 台車圖放大成 128×128、台車現在的狀況、
##  七個停靠點小標「✓ 已過／▶ 台車在這／○ 還沒到」）→ 一個動作按鈕（文字跟著下一步變）→
##  不能按的原因 → 鈴幣 → 運礦工資 → 說明 BLURB → 操作提示 HOW → 原創聲明。
##  伺服器回覆由 main._notice 寫進頁底（modal_feedback）。
##  原因：規則的 step_block 優先；規則允許但人離台車太遠時寫出台車在哪一格（away_text）。
##  不能按的按鈕仍可取得焦點（tooltip＝原因）。結構只建一次，refresh() 依快照原地更新。
##
## 純函式：region_of / person_of / near / away_text / action_reason / action_caption / count_text /
##  chip_text。
const Route=preload("res://scripts/ore_route.gd")
const Art=preload("res://scripts/ore_route_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

const LAYOUT:="ore_route"
const POINT:="ore_cart"
const PAGE_TITLE:=Route.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const AWAY:="請走到台車旁（%d,%d）再操作。"
const KEY_HINT:="Enter 確認・Esc 回到島上"
const COUNT_TEXT:="今天 %d／%d 車・累計 %d 車"
const CAPTION_LOAD:="裝一車礦料"
const CAPTION_PUSH:="往前推一段（還剩 %d 段）"
const CAPTION_UNLOAD:="卸下礦料"
const STOP_COUNT:=7
const STOP_FIRST:="裝礦台"
const STOP_LAST:="卸礦台"
const PURSE_TEXT:="鈴幣：%d"
const PAY_TEXT:="運礦工資：每車 %d 鈴幣"

# ------------------------------------------------------------ pure helpers --

static func region_of(s:Dictionary) -> String:
	return str(s.get("region_id","home"))

static func person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

## Standing within REACH of the cart's current cell in 金瓜石 (the rule's TOO_FAR check).
static func near(s:Dictionary,person:Dictionary) -> bool:
	if person.is_empty() or region_of(s)!=Route.REGION:return false
	var cell:Vector2i=Route.cart_cell(Route.stage(s))
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Route.REACH

static func away_text(stage:int) -> String:
	var cell:Vector2i=Route.cart_cell(stage)
	return AWAY%[cell.x,cell.y]

## Why the action cannot be done ("" = it can): the rules first, then where to stand.
static func action_reason(s:Dictionary,person:Dictionary) -> String:
	var block:String=Route.step_block(s,Route.next_step(s),person)
	if not block.is_empty():return block
	return "" if near(s,person) else away_text(Route.stage(s))

static func action_caption(stage:int) -> String:
	var at:=clampi(stage,0,Route.LAST)
	if at==0:return CAPTION_LOAD
	if at==Route.LAST:return CAPTION_UNLOAD
	return CAPTION_PUSH%Route.pushes_left(at)

static func count_text(s:Dictionary) -> String:
	return COUNT_TEXT%[Route.count_today(s),Route.DAILY,Route.total(s)]

## Index (0..6) of the stop the cart stands at.
static func _cart_index(stage:int) -> int:
	return clampi(stage,1,STOP_COUNT)-1

static func _stop_name(index:int) -> String:
	if index<=0:return STOP_FIRST
	if index>=STOP_COUNT-1:return STOP_LAST
	return str(index)

## One stop chip: "✓ 名稱" passed, "▶ 名稱" cart here, "○ 名稱" not reached yet.
static func chip_text(stage:int,index:int) -> String:
	var here:=_cart_index(stage)
	var title:=_stop_name(index)
	if index<here:return "✓ "+title
	if index==here:return "▶ "+title
	return "○ "+title

static func _chip_color(stage:int,index:int) -> Color:
	var here:=_cart_index(stage)
	if index==here:return GOOD
	if index<here:return MUTED
	return INK

static func _person(app) -> Dictionary:
	return person_of(app.session.snapshot,str(app.session.own_id))

static func _coins(person:Dictionary) -> int:
	var value:Variant=person.get("coins",0)
	if (value is int or value is float) and is_finite(float(value)):return int(value)
	return 0

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("or_body")

## The interact key at the cart: an empty cart opens this page; a loaded cart takes the next
## step right away (the server's message shows as an ordinary notice).
static func interact(app) -> void:
	var s:Dictionary=app.session.snapshot
	var stage:=Route.stage(s)
	if stage<=0:
		open(app)
		return
	app.session.perform(Route.ACTION,Route.cart_cell(stage),Route.next_step(s))

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

static func open(app) -> void:
	var s:Dictionary=app.session.snapshot
	if region_of(s)!=Route.REGION:return
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	app.modal.name="OreRoutePanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("or_body",body)
	app.modal.set_meta("suppress_world_prompts",true)
	body.add_theme_constant_override("separation",6)
	build(app,body)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text=KEY_HINT
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: centred, as tall as its content.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(560.0,bounds.x-40)
	var cap:=bounds.y-24
	var height:=minf(cap,560.0)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	else:
		height=minf(cap,maxf(modal.get_combined_minimum_size().y,240.0))
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))

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

static func build(app,body:VBoxContainer) -> void:
	# Today's and total carts.
	var head:=_paper(body,"OrHeader",1)
	_text(app,head,"OrCount",16)
	# The cart: picture, where it is, and the seven stops.
	var card:=_paper(body,"OrCartCard",4)
	var row:=HBoxContainer.new()
	row.name="OrCartRow"
	row.add_theme_constant_override("separation",12)
	card.add_child(row)
	var cart:=TextureRect.new()
	cart.name="OrCart"
	cart.texture=Art.cart_texture(false)
	cart.custom_minimum_size=Vector2(128,128)
	cart.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	cart.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cart.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	cart.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	cart.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(cart)
	var col:=VBoxContainer.new()
	col.name="OrCartInfo"
	col.add_theme_constant_override("separation",6)
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	col.alignment=BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_wrapped(app,col,"OrStage",15)
	var stops:=HBoxContainer.new()
	stops.name="OrStops"
	stops.add_theme_constant_override("separation",6)
	col.add_child(stops)
	for index in STOP_COUNT:
		_text(app,stops,"OrStop_%d"%index,12)
	var action:=_button(app,col,"OrAction",CAPTION_LOAD,func():_send(app))
	action.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_wrapped(app,col,"OrReason",13,WARN)
	_text(app,col,"OrPurse",13)
	_text(app,col,"OrPay",13,MUTED)
	_wrapped(app,body,"OrBlurb",13,MUTED).text=Route.BLURB
	_wrapped(app,body,"OrHow",13,MUTED).text=Route.HOW
	_wrapped(app,body,"OrDisclaimer",13,MUTED).text=Route.DISCLAIMER

# ------------------------------------------------------------------ actions --

static func _send(app) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var stage:=Route.stage(s)
	app.session.perform(Route.ACTION,Route.cart_cell(stage),Route.next_step(s))
	refresh(app,true)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("or_body") as Node).find_child(id,true,false) as Control

static func _put(app,id:String,value:String,color=null) -> Label:
	var l:=_node(app,id) as Label
	if l==null:return null
	l.text=value
	if color is Color:l.add_theme_color_override("font_color",color)
	l.visible=not value.is_empty()
	return l

static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var now:Dictionary=Route.view(s)
	var close_by:=near(s,person)
	var reason:=action_reason(s,person)
	var coins:=_coins(person)
	var signature:=JSON.stringify([now,close_by,reason,region_of(s),
		snappedf(float(person.get("x",0.0)),0.1),snappedf(float(person.get("y",0.0)),0.1),coins])
	if not force and str(app.modal.get_meta("or_signature",""))==signature:return
	app.modal.set_meta("or_signature",signature)
	var focus_before:=_focus_owner(app)
	var stage:=int(now.get("stage",0))
	_put(app,"OrCount",count_text(s))
	var cart:=_node(app,"OrCart") as TextureRect
	if cart!=null:cart.texture=Art.cart_texture(stage>0)
	_put(app,"OrStage",Route.stage_text(stage))
	for index in STOP_COUNT:
		_put(app,"OrStop_%d"%index,chip_text(stage,index),_chip_color(stage,index))
	var action:=_node(app,"OrAction") as Button
	if action!=null:
		action.text=action_caption(stage)
		action.disabled=not reason.is_empty()
		action.tooltip_text=reason if not reason.is_empty() else Route.BLURB
		action.focus_mode=Control.FOCUS_ALL
	_put(app,"OrReason",reason,WARN)
	_put(app,"OrPurse",PURSE_TEXT%coins)
	_put(app,"OrPay",PAY_TEXT%Route.PAY)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("or_body") if app.modal.has_meta("or_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("or_body"):break
		node=node.get_parent()
	return true

## The single action button: ↑ / ↓ / Tab go to 關閉 and back.
static func link_focus(app) -> void:
	var b:=_node(app,"OrAction") as Button
	if b==null:return
	var close:=close_button(app)
	b.focus_neighbor_left=b.get_path_to(b)
	b.focus_neighbor_right=b.get_path_to(b)
	b.focus_neighbor_bottom=b.get_path_to(b)
	if close!=null:
		b.focus_neighbor_top=b.get_path_to(close)
		b.focus_next=b.get_path_to(close)
		b.focus_previous=b.get_path_to(close)
		close.focus_neighbor_bottom=close.get_path_to(b)
		close.focus_neighbor_top=close.get_path_to(b)
		close.focus_next=close.get_path_to(b)
		close.focus_previous=close.get_path_to(b)
	else:
		b.focus_neighbor_top=b.get_path_to(b)
		b.focus_next=b.get_path_to(b)
		b.focus_previous=b.get_path_to(b)

static func _focus_owner(app) -> Control:
	if not is_open(app):return null
	var owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if owner==null or not (app.modal as Node).is_ancestor_of(owner):return null
	return owner

## The action button (even when disabled: its tooltip and the reason under it say what is
## missing); 關閉 only when the button is missing.
static func preferred(app) -> Control:
	var b:=_node(app,"OrAction") as Button
	if b!=null and _shown(b):return b
	return close_button(app)

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
