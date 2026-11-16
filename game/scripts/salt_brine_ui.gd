extends RefCounted
## 第 40 章「北門合作鹽田・儲滷槽」頁（規則在 salt_brine.gd，這裡只讀快照、送動作
## salt_brine_store / salt_brine_pour，cell＝SaltBrine.TANK，extra＝"a"／"b"）。
##
## 入口：北門合作社工寮東側的儲滷槽 TANK (48,14)。main._interact 把 POINT（"salt_brine"）加進北門的
##  互動點（不放進 SaltPanUI.interaction_points：那份清單與 salt_world_art.sites() 一一對應、有測試），
##  靠近按一般互動鍵就開這頁；沒有新按鍵。三道閘門修好前也能開，只顯示鎖定說明。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  天氣卡（第 n 日・北門天氣；下雨時多一行「收滷可以、放滷要等雨停」）→
##  儲滷槽卡（「槽裡 n／30 桶」＋ 30 格水位條、一句 BLURB）→
##  不能使用時：一張說明卡（common_block：LOCKED / NOT_READY / NO_UNIT / NO_WHEEL；NOT_READY 另有
##  「翻閱鹽田手帳」）；可以使用時：西側／東側鹽田兩張卡並排（鹽田名稱與編號、狀態文字
##  空的／滷水約 n 成／已結成鹽＋10 格進度條、「收滷 n 桶」「放滷 n 桶」、不能按的原因）→
##  原創聲明。伺服器回覆由 main._notice 寫進頁底（modal_feedback）。
##  原因：規則的 store_block / pour_block 優先；規則允許但人站得太遠時寫出要站到哪裡（AWAY）。
##  同一張卡兩個按鈕原因相同只寫一次，不同時分兩行「收滷：…」「放滷：…」。
##  不能按的按鈕仍可取得焦點（tooltip＝原因），所以鍵盤停在上面也讀得到。
##  結構只建一次，refresh() 依快照原地更新；指紋含水位、兩方鹽田（含依時間惰性推進的成數）、
##  天氣、遊戲分鐘、本人位置與地區，所以頁面開著跨過時間也會更新。
##  焦點：四個按鈕同一列（← → 循環），最上一列往上是「關閉」；NOT_READY 時是手帳按鈕。
##
## 純函式：near / away_text / store_reason / pour_reason / reason_text / state_text / weather_line /
##  level_text。
const Brine=preload("res://scripts/salt_brine.gd")
const Weather=preload("res://scripts/weather.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

const LAYOUT:="salt_brine"
const POINT:="salt_brine"
const PAGE_TITLE:=Brine.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const RAIN_INK:=Color("3f5f7a")
const BRINE_FILL:=Color("5f9fb0")
const SALT_FILL:=Color("f3f0e2")
const EMPTY_FILL:=Color("d8ccab")
const RAIN_LINE:="下雨了：收滷可以、放滷要等雨停。"
const AWAY:="請站到合作社工寮東側的儲滷槽旁（%d,%d）再收滷、放滷。"
const STORE_TEXT:="收滷"
const POUR_TEXT:="放滷"
const STORE_TIP:="請水車把這方鹽田的 %d 桶滷水抽進儲滷槽"
const POUR_TIP:="把槽裡 %d 桶滷水放回這方鹽田"
const STATE_EMPTY:="空的"
const STATE_BRINE:="滷水約 %d 成"
const STATE_SALT:="已結成鹽"
const NOTEBOOK_TEXT:="翻閱鹽田手帳"
const KEY_HINT:="← → 選擇・Enter 確認・Esc 回到島上"
const ACTION_IDS:=["Sb_store_a","Sb_pour_a","Sb_store_b","Sb_pour_b"]

# ------------------------------------------------------------ pure helpers --

static func region_of(s:Dictionary) -> String:
	return str(s.get("region_id","home"))

static func person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

## Standing within REACH of the tank in 北門 (the rule's TOO_FAR check).
static func near(s:Dictionary,person:Dictionary) -> bool:
	if person.is_empty() or region_of(s)!=Brine.REGION:return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(Brine.TANK)+Vector2(0.5,0.5))<=Brine.REACH

static func away_text() -> String:
	return AWAY%[Brine.TANK.x,Brine.TANK.y]

## Why the button cannot be pressed ("" = it can): the rules first, then where to stand.
static func store_reason(s:Dictionary,person:Dictionary,side:String) -> String:
	var block:=Brine.store_block(s,side)
	if not block.is_empty():return block
	return "" if near(s,person) else away_text()

static func pour_reason(s:Dictionary,person:Dictionary,side:String) -> String:
	var block:=Brine.pour_block(s,side)
	if not block.is_empty():return block
	return "" if near(s,person) else away_text()

## The reason line under one pan's two buttons.
static func reason_text(store_r:String,pour_r:String) -> String:
	if store_r==pour_r:return store_r
	var out:=PackedStringArray()
	if not store_r.is_empty():out.append(STORE_TEXT+"："+store_r)
	if not pour_r.is_empty():out.append(POUR_TEXT+"："+pour_r)
	return "\n".join(out)

static func state_text(row:Dictionary) -> String:
	match str(row.get("s","empty")):
		"brine":return STATE_BRINE%int(row.get("tenths",0))
		"salt":return STATE_SALT
	return STATE_EMPTY

static func _time(s:Dictionary) -> float:
	var t:Variant=s.get("time",0.0)
	return float(t) if (t is int or t is float) else 0.0

static func weather_line(s:Dictionary) -> String:
	var weather:Dictionary=Weather.at(_time(s),Brine.REGION)
	return "第 %d 日・北門%s"%[int(weather.get("day",1)),str(weather.get("label",""))]

static func level_text(s:Dictionary) -> String:
	return "槽裡 %d／%d 桶"%[Brine.level(s),Brine.CAP]

static func store_caption(n:int) -> String:
	return STORE_TEXT+(" %d 桶"%n if n>0 else "")

static func pour_caption(n:int) -> String:
	return POUR_TEXT+(" %d 桶"%n if n>0 else "")

static func _person(app) -> Dictionary:
	return person_of(app.session.snapshot,str(app.session.own_id))

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("sb_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

static func open(app) -> void:
	var s:Dictionary=app.session.snapshot
	if region_of(s)!=Brine.REGION:return
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	app.modal.name="SaltBrinePanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("sb_body",body)
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
	var width:=minf(780.0,bounds.x-40)
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

## A row of `count` small pixel cells (a gauge without percentages).
static func _gauge(parent:Node,id:String,count:int,cell:Vector2) -> HBoxContainer:
	var bar:=HBoxContainer.new()
	bar.name=id
	bar.add_theme_constant_override("separation",2)
	bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	for i in count:
		var c:=ColorRect.new()
		c.name="%s_%d"%[id,i]
		c.custom_minimum_size=cell
		c.color=EMPTY_FILL
		c.mouse_filter=Control.MOUSE_FILTER_IGNORE
		bar.add_child(c)
	return bar

static func build(app,body:VBoxContainer) -> void:
	# Today's Beimen weather.
	var head:=_paper(body,"SbHeader",1)
	_text(app,head,"SbWeather",16)
	_text(app,head,"SbRain",14,RAIN_INK)
	# The tank: level, gauge and what it is for.
	var tank:=_paper(body,"SbTank",4)
	var level_row:=HBoxContainer.new()
	level_row.name="SbLevelRow"
	level_row.add_theme_constant_override("separation",12)
	tank.add_child(level_row)
	_text(app,level_row,"SbLevel",16)
	_gauge(level_row,"SbBar",Brine.CAP,Vector2(11,14))
	_wrapped(app,tank,"SbBlurb",13,MUTED).text=Brine.BLURB
	# Cannot use the tank yet: one reason.
	var block:=_paper(body,"SbBlock")
	_wrapped(app,block,"SbBlockText",15,WARN)
	var notebook:=_button(app,block,"SbNotebook",NOTEBOOK_TEXT,func():app.SaltUI.open(app,"journal"))
	notebook.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	# The player's two pans.
	var cards:=HBoxContainer.new()
	cards.name="SbCards"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	for side:String in Brine.SIDES:
		var card:=_paper(cards,"SbCard_"+side,4)
		_text(app,card,"SbName_"+side,15)
		var state_row:=HBoxContainer.new()
		state_row.name="SbStateRow_"+side
		state_row.add_theme_constant_override("separation",10)
		card.add_child(state_row)
		_text(app,state_row,"SbState_"+side,14)
		_gauge(state_row,"SbPanBar_"+side,Brine.PAN_BUCKETS,Vector2(10,10))
		var buttons:=HBoxContainer.new()
		buttons.name="SbButtons_"+side
		buttons.add_theme_constant_override("separation",8)
		card.add_child(buttons)
		_button(app,buttons,"Sb_store_"+side,STORE_TEXT,func():_send(app,Brine.STORE_ACTION,side))
		_button(app,buttons,"Sb_pour_"+side,POUR_TEXT,func():_send(app,Brine.POUR_ACTION,side))
		_wrapped(app,card,"SbReason_"+side,13,WARN)
	var disclaimer:=_wrapped(app,body,"SbDisclaimer",13,MUTED)
	disclaimer.text=Brine.DISCLAIMER

# ------------------------------------------------------------------ actions --

static func _send(app,action:String,side:String) -> void:
	if not is_open(app):return
	app.session.perform(action,Brine.TANK,side)
	refresh(app,true)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("sb_body") as Node).find_child(id,true,false) as Control

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

static func _fill(app,id:String,count:int,filled:int,color:Color) -> void:
	var bar:=_node(app,id)
	if bar==null:return
	for i in count:
		var c:=bar.get_node_or_null("%s_%d"%[id,i]) as ColorRect
		if c!=null:c.color=color if i<filled else EMPTY_FILL

static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var common:=Brine.common_block(s)
	var rows:Array=Brine.rows(s)
	var held:=Brine.level(s)
	var rainy:=Brine.rainy_now(s)
	var close_by:=near(s,person)
	var reasons:={}
	for side:String in Brine.SIDES:
		reasons[side]=[store_reason(s,person,side),pour_reason(s,person,side)]
	# Brine progress is lazy (integrated from pan.p/pan.t to snapshot.time), so the rows change
	# with time alone; the game minute and the weather are in the signature as well.
	var signature:=JSON.stringify([common,rows,held,rainy,close_by,reasons,weather_line(s),int(floorf(_time(s)/60.0)),
		snappedf(float(person.get("x",0.0)),0.1),snappedf(float(person.get("y",0.0)),0.1),region_of(s)])
	if not force and str(app.modal.get_meta("sb_signature",""))==signature:return
	app.modal.set_meta("sb_signature",signature)
	var focus_before:=_focus_owner(app)
	# Weather.
	_put(app,"SbWeather",weather_line(s))
	_put(app,"SbRain",RAIN_LINE if rainy else "")
	# Tank.
	_put(app,"SbLevel",level_text(s),GOOD if held>=Brine.CAP else INK)
	_fill(app,"SbBar",Brine.CAP,held,BRINE_FILL)
	# Locked / not ready / no unit / no wheel: one reason instead of the pans.
	var usable:=common.is_empty() and rows.size()==Brine.SIDES.size()
	_show(app,"SbBlock",not usable)
	_put(app,"SbBlockText",common if not common.is_empty() else ("" if usable else Brine.NO_UNIT))
	_show(app,"SbNotebook",common==Brine.NOT_READY)
	_show(app,"SbCards",usable)
	for at in Brine.SIDES.size():
		var side:String=Brine.SIDES[at]
		var row:Dictionary=rows[at] if usable else {}
		var store_r:String=reasons[side][0]
		var pour_r:String=reasons[side][1]
		_put(app,"SbName_"+side,"%s（鹽田 %d）"%[str(Brine.SIDE_NAMES[side]),int(row.get("pan",-1))+1] if usable else str(Brine.SIDE_NAMES[side]))
		var state:=str(row.get("s","empty"))
		_put(app,"SbState_"+side,state_text(row),INK if state=="brine" else (GOOD if state=="salt" else MUTED))
		_fill(app,"SbPanBar_"+side,Brine.PAN_BUCKETS,Brine.PAN_BUCKETS if state=="salt" else int(row.get("tenths",0)),SALT_FILL if state=="salt" else BRINE_FILL)
		var store_n:=int(row.get("store",0))
		var pour_n:=int(row.get("pour",0))
		var store:=_enable(app,"Sb_store_"+side,usable and store_r.is_empty(),store_r if not store_r.is_empty() else STORE_TIP%store_n)
		if store!=null:store.text=store_caption(store_n)
		var pour:=_enable(app,"Sb_pour_"+side,usable and pour_r.is_empty(),pour_r if not pour_r.is_empty() else POUR_TIP%pour_n)
		if pour!=null:pour.text=pour_caption(pour_n)
		_put(app,"SbReason_"+side,reason_text(store_r,pour_r) if usable else "",WARN)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("sb_body") if app.modal.has_meta("sb_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("sb_body"):break
		node=node.get_parent()
	return true

## Rows of focusable buttons: the journal link (not ready); the four pan buttons in one row.
static func focus_rows(app) -> Array:
	var rows:Array=[]
	for group:Array in [["SbNotebook"],ACTION_IDS]:
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

## The first button that can be pressed, then the journal link, then the first shown pan button
## (its tooltip and the reason under it say what is missing), then 關閉.
static func preferred(app) -> Control:
	for id:String in ACTION_IDS:
		var b:=_node(app,id) as Button
		if _usable(b):return b
	var notebook:=_node(app,"SbNotebook") as Button
	if _usable(notebook):return notebook
	for id:String in ACTION_IDS:
		var b:=_node(app,id) as Button
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
