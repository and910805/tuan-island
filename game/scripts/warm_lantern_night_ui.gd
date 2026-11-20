extends RefCounted
## 冬季暖燈夜面板（規則在 warm_lantern_night.gd；這裡只讀快照 warm_lantern_night /
## own_warm_lantern_night，動作一律走 app.session.perform(WL.ACTION,cell,extra)）：
##   佈告欄 WL.BOARD                 ： "start"、"join:<round>"、"finish:<round>"
##   燈站 WL.STATIONS[id].cell       ： "light:<round>:<station>:<wish>"
##
## open(app,"")      ＝ 佈告欄頁：共同進度、三張燈站卡（含路線提示）、自己的永久紀念、開始／加入／收燈。
## open(app,"grove") ＝ 燈站小窗（像對話框）：只在這裡選一個祝福並點燈；已點亮就只讀所選祝福。
## 加入只在佈告欄；燈站小窗不放加入。關閉只用面板標題列既有的「關閉  Esc」，不再另放。
## 結構只建一次，refresh(app) 原地更新。版面：life_modal_layout="warm_lantern_night"。
const WL=preload("res://scripts/warm_lantern_night.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")

const LAYOUT:="warm_lantern_night"
const TITLE:="冬季暖燈夜"
const LANTERN_ICON:="mine_lantern_kit"  # 既有 ItemArt 燈籠圖示
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const GOLD:=Color("c98a1c")

# ------------------------------------------------------------ pure helpers --

static func _dict(v:Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _public(app) -> Dictionary:
	return _dict(app.session.snapshot.get("warm_lantern_night",{}))

static func _own(app) -> Dictionary:
	return _dict(app.session.snapshot.get("own_warm_lantern_night",{}))

static func _phase(pub:Dictionary) -> String:
	return str(pub.get("phase","idle"))

static func _round(pub:Dictionary) -> int:
	return int(pub.get("round",0))

static func _station_ids() -> Array:
	return WL.STATIONS.keys()

static func _wish_ids() -> Array:
	return WL.WISHES.keys()

static func _lit(pub:Dictionary,station:String) -> String:
	return str(_dict(pub.get("lamps",{})).get(station,""))

static func _lit_count(pub:Dictionary) -> int:
	var n:=0
	for id in _station_ids():
		if _lit(pub,str(id))!="":n+=1
	return n

static func _wish_text(wish:String) -> String:
	return str(WL.WISHES.get(wish,""))

static func _station_title(id:String) -> String:
	return str(_dict(WL.STATIONS.get(id,{})).get("title",id))

static func start_block(own:Dictionary) -> String:
	if not bool(own.get("unlocked",false)):return "暖燈夜還沒開放。"
	if not bool(own.get("completed",false)) and not bool(own.get("in_season",false)):return "第一次暖燈夜要等冬天；點過一次後，任何季節都能再辦。"
	if not bool(own.get("can_start",false)):return "現在還不能開始暖燈夜。"
	return ""

## One-line next step. Pure: reads only the two snapshot dictionaries.
static func next_action(pub:Dictionary,own:Dictionary) -> String:
	if not bool(own.get("unlocked",false)):return start_block(own)
	match _phase(pub):
		"celebrated":return "三盞紙燈都亮了，暖燈夜圓滿。"
		"lighting":
			if not bool(own.get("joined",false)):return "先在佈告欄按「加入暖燈夜」，才能到燈站點燈。"
			var left:=WL.STATIONS.size()-_lit_count(pub)
			if left<=0:return "三盞燈都亮了，回佈告欄按「收燈慶祝」。"
			return "還有 %d 盞燈沒亮：照路線提示走到燈站，各選一個祝福。"%left
		_:
			var block:=start_block(own)
			if block!="":return block
			return "在佈告欄開始暖燈夜，大家一起把三盞紙燈點亮。"

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("wl_body")

static func _station(app) -> String:
	return str(app.modal.get_meta("wl_station","")) if is_instance_valid(app.modal) else ""

# ---------------------------------------------------------------- structure --

static func _paper(parent:Node,id:String,separation:=4) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",separation)
	card.add_child(col)
	return col

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
	b.custom_minimum_size=Vector2(150,36)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size",15)
	parent.add_child(b)
	return b

static func _icon(size:int) -> TextureRect:
	var icon:=TextureRect.new()
	icon.name="Icon"
	icon.custom_minimum_size=Vector2(size,size)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	icon.texture=Items.icon(LANTERN_ICON)
	return icon

static func open(app,station:String="") -> void:
	if station!="" and not WL.STATIONS.has(station):station=""
	var body:VBoxContainer=app._open_modal(_station_title(station) if station!="" else TITLE)
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.name="WarmLanternNightPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("wl_body",body)
	app.modal.set_meta("wl_station",station)
	body.add_theme_constant_override("separation",8)
	if station=="":_build_board(app,body)
	else:_build_station(app,body,station)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text=app.binding_text("Esc 關閉・一盞燈只能許一個祝福" if station!="" else "Esc 關閉・到燈站點燈後回來收燈")
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _build_board(app,body:VBoxContainer) -> void:
	var head:=_paper(body,"WarmNightHead")
	_wrapped(app,head,"WarmNightStatus",16)
	_wrapped(app,head,"WarmNightNext",15,GOOD)
	var cards:=HBoxContainer.new()
	cards.name="WarmNightCards"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	for id in _station_ids():
		_build_card(app,cards,str(id))
	# Permanent own keepsake: shown once this player has completed a night.
	var keep:=PanelContainer.new()
	keep.name="WarmNightKeepsake"
	keep.add_theme_stylebox_override("panel",_card_style(true,true))
	body.add_child(keep)
	var krow:=HBoxContainer.new()
	krow.add_theme_constant_override("separation",10)
	keep.add_child(krow)
	krow.add_child(_icon(40))
	var kcol:=VBoxContainer.new()
	kcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	krow.add_child(kcol)
	_wrapped(app,kcol,"KeepTitle",16,GOLD).text="暖燈紀念・已收錄"
	_wrapped(app,kcol,"KeepLine",13,MUTED).text="你參加過暖燈夜，這盞小紙燈會一直留在你的紀錄裡。"
	_wrapped(app,body,"WarmNightReason",14,WARN)
	var row:=HBoxContainer.new()
	row.name="WarmNightButtons"
	row.add_theme_constant_override("separation",8)
	body.add_child(row)
	_button(app,row,"WarmNightStart","開始暖燈夜",func():_send_board(app,"start"))
	_button(app,row,"WarmNightJoin","加入暖燈夜",func():_send_board(app,"join:%d"%_round(_public(app))))
	_button(app,row,"WarmNightFinish","收燈慶祝",func():_send_board(app,"finish:%d"%_round(_public(app))))

static func _build_card(app,parent:Node,id:String) -> void:
	var def:Dictionary=WL.STATIONS[id]
	var card:=PanelContainer.new()
	card.name="WarmNightCard_"+id
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x=0
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",4)
	card.add_child(col)
	var top:=HBoxContainer.new()
	top.add_theme_constant_override("separation",8)
	col.add_child(top)
	top.add_child(_icon(44))
	var tcol:=VBoxContainer.new()
	tcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(tcol)
	_wrapped(app,tcol,"Title",16).text=str(def.get("title",id))
	_wrapped(app,tcol,"Mark",13,MUTED)
	_wrapped(app,col,"Hint",13,MUTED).text=str(def.get("hint",""))
	_wrapped(app,col,"Wish",13,GOOD)

static func _build_station(app,body:VBoxContainer,station:String) -> void:
	var pane:=_paper(body,"WarmNightStationPane",6)
	var top:=HBoxContainer.new()
	top.add_theme_constant_override("separation",10)
	pane.add_child(top)
	top.add_child(_icon(48))
	var tcol:=VBoxContainer.new()
	tcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(tcol)
	_wrapped(app,tcol,"WarmNightStationTitle",18).text="寫一張暖燈祝福"
	_wrapped(app,tcol,"WarmNightStationLine",14,MUTED)
	_wrapped(app,pane,"WarmNightChosen",15,GOOD)
	var list:=VBoxContainer.new()
	list.name="WarmNightWishes"
	list.add_theme_constant_override("separation",4)
	pane.add_child(list)
	for wish in _wish_ids():
		var w:=str(wish)
		var b:=_button(app,list,"WarmNightWish_"+w,_wish_text(w),func():_light(app,station,w))
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size=Vector2(0,40)
		b.add_theme_font_size_override("font_size",14)
	_wrapped(app,body,"WarmNightReason",14,WARN)

# ------------------------------------------------------------------ actions --

static func _send_board(app,extra:String) -> void:
	if not is_open(app):return
	app.session.perform(WL.ACTION,WL.BOARD,extra)

static func _light(app,station:String,wish:String) -> void:
	if not is_open(app) or not WL.STATIONS.has(station):return
	var cell:Vector2i=WL.STATIONS[station].cell
	app.session.perform(WL.ACTION,cell,"light:%d:%s:%s"%[_round(_public(app)),station,wish])

# ------------------------------------------------------------------- links --

static func _link_label(pub:Dictionary,own:Dictionary) -> String:
	var label:=TITLE
	match _phase(pub):
		"lighting":label+="・進行中 %d／%d"%[_lit_count(pub),WL.STATIONS.size()]
		"celebrated":label+="・已圓滿"
		_:
			if bool(own.get("can_start",false)):
				label+="・再辦一次" if bool(own.get("completed",false)) else "・可以開始"
	return label

static func _update_link(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("wl_board_body"):return
	var body:Node=app.modal.get_meta("wl_board_body")
	if not is_instance_valid(body):return
	var pub:=_public(app)
	var own:=_own(app)
	var active:=_phase(pub)!="idle"
	var allowed:bool=bool(own.get("unlocked",false)) and (active or bool(own.get("in_season",false)) or bool(own.get("completed",false)))
	var b:=body.get_node_or_null("WarmNightBoardLink") as Button
	if b==null and not allowed:return
	var label:=_link_label(pub,own)
	if b==null:
		b=app.button(label,func():open(app,""))
		b.name="WarmNightBoardLink"
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size.y=34
		b.add_theme_font_size_override("font_size",14)
		b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		body.add_child(b)
		body.move_child(b,0)
	b.visible=allowed
	if b.text!=label:b.text=label
	b.tooltip_text=next_action(pub,own)

static func add_board_link(app,body:VBoxContainer) -> void:
	app.modal.set_meta("wl_board_body",body)
	_update_link(app)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("wl_body") as Node).find_child(id,true,false) as Control

static func _card_style(lit:bool,keep:=false) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=Color("f7e3a8") if keep else (Color("f7ecc8") if lit else Color("e4dfcd"))
	s.border_color=GOLD if lit else Color("a9a28c")
	s.set_border_width_all(3 if lit else 2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	return s

static func _set_visible(c:Control,v:bool) -> void:
	if c!=null:c.visible=v

## Updates links (if present) and the open panel in place; never rebuilds anything.
static func refresh(app,force:=false) -> void:
	_update_link(app)
	if not is_open(app):return
	var pub:=_public(app)
	var own:=_own(app)
	var signature:=JSON.stringify([pub.get("round"),pub.get("phase"),pub.get("lamps"),pub.get("guests"),own.get("unlocked"),own.get("in_season"),own.get("completed"),own.get("joined"),own.get("can_start")])
	if not force and str(app.modal.get_meta("wl_signature",""))==signature:return
	app.modal.set_meta("wl_signature",signature)
	var focus:=_focus_owner(app)
	var station:=_station(app)
	if station=="":_refresh_board(app,pub,own)
	else:_refresh_station(app,pub,own,station)
	_link_focus(app)
	_restore_focus(app,focus)
	app._layout_preview.call_deferred()

static func _refresh_board(app,pub:Dictionary,own:Dictionary) -> void:
	var phase:=_phase(pub)
	var lighting:=phase=="lighting"
	var celebrated:=phase=="celebrated"
	var joined:=bool(own.get("joined",false))
	var unlocked:=bool(own.get("unlocked",false))
	var count:=_lit_count(pub)
	var total:=WL.STATIONS.size()
	var status:="尚未開放"
	if unlocked:
		match phase:
			"lighting":status="點燈 %d／%d ・ %d 位島民參加%s"%[count,total,int(pub.get("guests",0)),"（含你）" if joined else ""]
			"celebrated":status="第 %d 輪・暖燈夜圓滿 ・ %d 位島民參加"%[_round(pub),int(pub.get("guests",0))]
			_:status="還沒開始・%s"%("可以開始" if bool(own.get("can_start",false)) else "暫時不能開始")
	(_node(app,"WarmNightStatus") as Label).text=status
	(_node(app,"WarmNightNext") as Label).text=app.binding_text(next_action(pub,own))
	_set_visible(_node(app,"WarmNightKeepsake"),bool(own.get("completed",false)))
	for id in _station_ids():
		var sid:=str(id)
		var card:=_node(app,"WarmNightCard_"+sid) as PanelContainer
		var wish:=_lit(pub,sid)
		var on:=wish!=""
		card.add_theme_stylebox_override("panel",_card_style(on,celebrated and on))
		(card.find_child("Icon",true,false) as TextureRect).modulate=Color.WHITE if on else Color(0.5,0.5,0.5,0.6)
		var mark:=card.find_child("Mark",true,false) as Label
		mark.text="已點亮" if on else ("等你點燈" if lighting else "還沒開始")
		mark.add_theme_color_override("font_color",GOOD if on else MUTED)
		var line:=card.find_child("Wish",true,false) as Label
		line.text=_wish_text(wish)
		line.visible=on
	var start:=_node(app,"WarmNightStart") as Button
	var join:=_node(app,"WarmNightJoin") as Button
	var finish:=_node(app,"WarmNightFinish") as Button
	start.visible=not lighting
	start.text="再辦一次暖燈夜" if (celebrated or bool(own.get("completed",false))) else "開始暖燈夜"
	start.disabled=not bool(own.get("can_start",false))
	start.tooltip_text=start_block(own) if start.disabled else ""
	join.visible=lighting and not joined
	finish.visible=lighting and joined
	finish.disabled=count<total
	finish.tooltip_text="三盞燈都點亮才能收燈" if finish.disabled else ""
	var reason:=""
	if not unlocked or (phase=="idle" and start.disabled):reason=start_block(own)
	elif lighting and joined and count<total:reason="還差 %d 盞燈，點亮後才能收燈。"%(total-count)
	var rl:=_node(app,"WarmNightReason") as Label
	rl.text=reason
	rl.visible=reason!=""

static func _refresh_station(app,pub:Dictionary,own:Dictionary,station:String) -> void:
	var phase:=_phase(pub)
	var lighting:=phase=="lighting"
	var joined:=bool(own.get("joined",false))
	var wish:=_lit(pub,station)
	var lit:=wish!=""
	var line:=_node(app,"WarmNightStationLine") as Label
	line.text="這盞紙燈已經亮了。" if lit else "選一句話，點亮這盞紙燈。"
	var chosen:=_node(app,"WarmNightChosen") as Label
	chosen.text="已寫下的祝福：%s"%_wish_text(wish)
	chosen.visible=lit
	var reason:=""
	if not bool(own.get("unlocked",false)):reason="暖燈夜還沒開放。"
	elif not lighting:reason="暖燈夜還沒開始，先到佈告欄開始。" if phase!="celebrated" else "這一輪已經圓滿了。"
	elif not joined:reason="先到佈告欄加入暖燈夜，才能點燈。"
	var can:=lighting and joined and not lit
	for wid in _wish_ids():
		var b:=_node(app,"WarmNightWish_"+str(wid)) as Button
		if b==null:continue
		b.visible=not lit
		b.disabled=not can
		b.tooltip_text=reason if b.disabled else "把這句祝福寫在紙燈上"
	var rl:=_node(app,"WarmNightReason") as Label
	rl.text=reason if not lit else ""
	rl.visible=rl.text!=""

# -------------------------------------------------------------------- focus --

static func _buttons(app) -> Array[Button]:
	var list:Array[Button]=[]
	var root:=app.modal.get_meta("wl_body") as Node
	var ids:Array=["WarmNightStart","WarmNightJoin","WarmNightFinish"]
	for wid in _wish_ids():ids.append("WarmNightWish_"+str(wid))
	for id in ids:
		var b:=root.find_child(str(id),true,false) as Button
		if b!=null and b.is_visible_in_tree() and not b.disabled:list.append(b)
	return list

static func _link_focus(app) -> void:
	var list:=_buttons(app)
	for i in list.size():
		var b:=list[i]
		b.focus_next=b.get_path_to(list[(i+1)%list.size()])
		b.focus_previous=b.get_path_to(list[(i-1+list.size())%list.size()])

static func _focus_owner(app) -> Control:
	var f:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if f==null or not (app.modal as Node).is_ancestor_of(f):return null
	return f

static func _focus_first(app) -> void:
	if not is_open(app):return
	var list:=_buttons(app)
	if list.size()>0:list[0].grab_focus()

## Focus stays put; only a button that vanished or got disabled hands it on.
static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if is_instance_valid(before) and before.is_visible_in_tree() and not (before is Button and (before as Button).disabled):return
	_focus_first.call_deferred(app)

# ------------------------------------------------------------------- layout --

## root's _layout_preview calls this when life_modal_layout=="warm_lantern_night".
## Board: centred, ~720 wide. Station: narrow dialogue-like pane low on the screen.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var station:=bool(str(modal.get_meta("wl_station","")) != "")
	var width:=minf(520.0 if station else 720.0,bounds.x-48)
	var cap:=bounds.y-32
	var height:=minf(cap,420.0)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	var y:=floorf((bounds.y-height)/2)
	if station:y=maxf(16.0,bounds.y-height-24.0)
	modal.position=Vector2(floorf((bounds.x-width)/2),y)
