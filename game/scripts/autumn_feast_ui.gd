extends RefCounted
## 秋收共享宴面板（規則在 autumn_feast.gd；這裡只讀快照 autumn_feast / own_autumn_feast，
## 動作一律走 app.session.perform(AF.ACTION,cell,extra)）：
##   佈告欄 AF.BOARD        ： "start"
##   共餐桌 table_cell(快照)： "join:<round>"、"give:<round>:<item>"、"serve:<round>"
##
## 入口：野餐之後，佈告欄頁底 add_board_link(app,body)、共餐桌頁 add_table_link(app,body)，
## 兩者都只開這一個面板（open(app,table)；table 只影響開啟時的提示與焦點）。
## 三個口袋卡（根莖／青葉／金穗）：圖示是已放入的那樣食材 PNG；沒放時淡色顯示第一個候選。
## 每個候選食材一顆 AutumnFeastGive_<id> 按鈕，按鈕文字直接寫「放入 X・扣 1 個（背包 n）」，
## 數量取自自己的背包（快照 players[own_id].inventory）。口袋滿了就收起按鈕，不留重複入口。
## 上桌之後換成完成畫面（宴席桌面＋三樣食材）。
## 結構只建一次，refresh(app) 原地更新；連結按鈕只更新自己，不動別的面板。
## 版面：life_modal_layout="autumn_feast"，root 呼叫 AutumnFeastUI.layout(app,bounds)。
const AF=preload("res://scripts/autumn_feast.gd")
const Community=preload("res://scripts/community.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")

const LAYOUT:="autumn_feast"
const TITLE:="秋季豐收宴"
const GIVE_COST:=1
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const GOLD:=Color("c98a1c")

# ------------------------------------------------------------ pure helpers --

static func _dict(v:Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _public(app) -> Dictionary:
	return _dict(app.session.snapshot.get("autumn_feast",{}))

static func _own(app) -> Dictionary:
	return _dict(app.session.snapshot.get("own_autumn_feast",{}))

static func _inventory(app) -> Dictionary:
	var person:=_dict(_dict(app.session.snapshot.get("players",{})).get(app.session.own_id,{}))
	return _dict(person.get("inventory",{}))

static func _item_name(id:String) -> String:
	return AF.item_name(id)

static func _slot_ids() -> Array:
	return AF.SLOTS.keys()

static func _filled(pub:Dictionary,slot:String) -> String:
	return str(_dict(pub.get("entries",{})).get(slot,""))

static func _filled_count(pub:Dictionary) -> int:
	var n:=0
	for slot in _slot_ids():
		if _filled(pub,slot)!="":n+=1
	return n

static func _phase(pub:Dictionary) -> String:
	return str(pub.get("phase","idle"))

static func _round(pub:Dictionary) -> int:
	return int(pub.get("round",0))

static func start_block(own:Dictionary) -> String:
	if not bool(own.get("unlocked",false)):return "先完成野餐，秋收宴才會開放。"
	if not bool(own.get("completed",false)) and not bool(own.get("in_season",false)):return "第一次秋收宴要等秋天；辦過一次後，任何季節都能再辦。"
	if not bool(own.get("can_start",false)):return "現在還不能開宴。"
	return ""

## One-line next step. Pure: reads only the two snapshot dictionaries.
static func next_action(pub:Dictionary,own:Dictionary) -> String:
	if not bool(own.get("unlocked",false)):return start_block(own)
	match _phase(pub):
		"served":return "三類食材已經一起上桌。"
		"collect":
			if not bool(own.get("joined",false)):return "到共餐桌按「加入秋收宴」，才能放入食材。"
			var left:=AF.SLOTS.size()-_filled_count(pub)
			if left<=0:return "三個口袋都滿了，到共餐桌按「上桌開宴」。"
			return "還有 %d 個口袋是空的：每個口袋放入一樣自己背包裡的食材。"%left
		_:
			var block:=start_block(own)
			if block!="":return block
			return "在公告板發起聚餐，再到共餐桌準備三類食材。"

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("af_body")

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
	return icon

static func open(app,table:=false) -> void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.name="AutumnFeastPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("af_body",body)
	app.modal.set_meta("af_table",table)
	body.add_theme_constant_override("separation",8)
	_build(app,body)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text=app.binding_text("Esc 關閉・食材取自你自己的背包" if table else "Esc 關閉・開宴後到共餐桌放入食材")
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _build(app,body:VBoxContainer) -> void:
	var head:=_paper(body,"AutumnFeastHead")
	_wrapped(app,head,"AutumnFeastStatus",16)
	_wrapped(app,head,"AutumnFeastNext",15,GOOD)
	_wrapped(app,head,"AutumnFeastKeepsake",14,GOLD).text="秋收紀念・已收錄"
	var pockets:=HBoxContainer.new()
	pockets.name="AutumnFeastPockets"
	pockets.add_theme_constant_override("separation",8)
	body.add_child(pockets)
	for slot:String in _slot_ids():
		_build_pocket(app,pockets,slot)
	# Completion view (shown instead of the give lists once served).
	var finale:=_paper(body,"AutumnFeastFinale",6)
	var ft:=_wrapped(app,finale,"FinaleTitle",20,GOLD)
	ft.text="豐收宴開席！"
	ft.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var spread:=HBoxContainer.new()
	spread.name="FinaleSpread"
	spread.alignment=BoxContainer.ALIGNMENT_CENTER
	spread.add_theme_constant_override("separation",18)
	finale.add_child(spread)
	for slot:String in _slot_ids():
		var col:=VBoxContainer.new()
		col.name="Finale_"+slot
		col.custom_minimum_size.x=112
		col.add_theme_constant_override("separation",2)
		spread.add_child(col)
		var icon:=_icon(56)
		col.add_child(icon)
		var nm:=_wrapped(app,col,"Name",14)
		nm.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var fl:=_wrapped(app,finale,"FinaleLine",15,MUTED)
	fl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	fl.text="在渡口一起留住這一季的收成。"
	_wrapped(app,body,"AutumnFeastReason",14,WARN)
	var row:=HBoxContainer.new()
	row.name="AutumnFeastButtons"
	row.add_theme_constant_override("separation",8)
	body.add_child(row)
	_button(app,row,"AutumnFeastStart","開始秋收宴",func():_send_board(app,"start"))
	_button(app,row,"AutumnFeastJoin","加入秋收宴",func():_send_table(app,"join:%d"%_round(_public(app))))
	_button(app,row,"AutumnFeastServe","上桌開宴",func():_send_table(app,"serve:%d"%_round(_public(app))))
	_button(app,row,"AutumnFeastClose","關閉",func():app._close_modal())

static func _build_pocket(app,parent:Node,slot:String) -> void:
	var def:Dictionary=AF.SLOTS[slot]
	var card:=PanelContainer.new()
	card.name="AutumnFeastPocket_"+slot
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio=1.0
	card.custom_minimum_size.x=0
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",4)
	card.add_child(col)
	var top:=HBoxContainer.new()
	top.add_theme_constant_override("separation",8)
	col.add_child(top)
	top.add_child(_icon(48))
	var tcol:=VBoxContainer.new()
	tcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(tcol)
	_wrapped(app,tcol,"Title",16).text=str(def.get("title",slot))
	_wrapped(app,tcol,"Mark",13,MUTED)
	var cost:=_wrapped(app,col,"Cost",12,MUTED)
	cost.text="擇一捐出 1 份"
	var list:=VBoxContainer.new()
	list.name="Gives"
	list.add_theme_constant_override("separation",4)
	col.add_child(list)
	var seen:=[]
	for item:String in def.get("items",[]):
		if item in seen:continue
		seen.append(item)
		var b:=_button(app,list,"AutumnFeastGive_"+item,"",func():_give(app,item))
		b.icon=Items.icon(item)
		b.expand_icon=true
		b.add_theme_constant_override("icon_max_width",26)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size=Vector2(0,36)
		b.add_theme_font_size_override("font_size",13)

# ------------------------------------------------------------------ actions --

static func _send_board(app,extra:String) -> void:
	if not is_open(app):return
	app.session.perform(AF.ACTION,AF.BOARD,extra)

static func _send_table(app,extra:String) -> void:
	if not is_open(app):return
	var cell:Vector2i=Community.table_cell(app.session.snapshot)
	if cell==Community.NO_CELL:return
	app.session.perform(AF.ACTION,cell,extra)

static func _give(app,item:String) -> void:
	_send_table(app,"give:%d:%s"%[_round(_public(app)),item])

# ------------------------------------------------------------------- links --

static func _link_label(pub:Dictionary,own:Dictionary) -> String:
	var label:=TITLE
	match _phase(pub):
		"collect":
			label+="・進行中 %d／%d"%[_filled_count(pub),AF.SLOTS.size()]
		"served":label+="・已開席"
		_:
			if bool(own.get("can_start",false)):
				label+="・再辦一次" if bool(own.get("completed",false)) else "・可以開始"
	return label

static func _update_link(app,meta:String,id:String,table:bool) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta(meta):return
	var body:Node=app.modal.get_meta(meta)
	if not is_instance_valid(body):return
	var pub:=_public(app)
	var own:=_own(app)
	var active:=_phase(pub)!="idle"
	var allowed:bool=own.get("unlocked",false) and (active or own.get("in_season",false) or own.get("completed",false))
	var b:=body.get_node_or_null(id) as Button
	if b==null and not allowed:return
	var label:=_link_label(pub,own)
	if b==null:
		b=app.button(label,func():open(app,table))
		b.name=id
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
	app.modal.set_meta("af_board_body",body)
	_update_link(app,"af_board_body","AutumnFeastBoardLink",false)

static func add_table_link(app,body:VBoxContainer) -> void:
	app.modal.set_meta("af_table_body",body)
	_update_link(app,"af_table_body","AutumnFeastTableLink",true)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("af_body") as Node).find_child(id,true,false) as Control

static func _pocket_style(filled:bool,served:bool) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=Color("f7e3a8") if served else (Color("f7ecc8") if filled else Color("e4dfcd"))
	s.border_color=GOLD if filled else Color("a9a28c")
	s.set_border_width_all(3 if filled else 2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	return s

## Updates links (if present) and the open panel in place; never rebuilds anything.
static func refresh(app,force:=false) -> void:
	_update_link(app,"af_board_body","AutumnFeastBoardLink",false)
	_update_link(app,"af_table_body","AutumnFeastTableLink",true)
	if not is_open(app):return
	var pub:=_public(app)
	var own:=_own(app)
	var inv:=_inventory(app)
	var table:bool=app.modal.get_meta("af_table",false)
	var phase:=_phase(pub)
	var served:=phase=="served"
	var collect:=phase=="collect"
	var joined:=bool(own.get("joined",false))
	var held:Array=[]
	for slot:String in _slot_ids():
		for item in AF.SLOTS[slot].get("items",[]):held.append(int(inv.get(item,0)))
	var signature:=JSON.stringify([pub.get("round"),phase,pub.get("entries"),pub.get("guests"),own.get("unlocked"),own.get("in_season"),own.get("completed"),joined,own.get("can_start"),held])
	if not force and str(app.modal.get_meta("af_signature",""))==signature:return
	app.modal.set_meta("af_signature",signature)
	var focus:=_focus_owner(app)
	var count:=_filled_count(pub)
	var full:=count>=AF.SLOTS.size()
	var status:="尚未開放"
	if bool(own.get("unlocked",false)):
		match phase:
			"collect":status="備料 %d／%d ・ %d 位島民%s"%[count,AF.SLOTS.size(),int(pub.get("guests",0)),"（含你）" if joined else ""]
			"served":status="第 %d 輪・宴席已開"%_round(pub)
			_:status="還沒開宴・%s"%("可以開始" if bool(own.get("can_start",false)) else "暫時不能開始")
	(_node(app,"AutumnFeastStatus") as Label).text=status
	(_node(app,"AutumnFeastNext") as Label).text=app.binding_text(next_action(pub,own))
	_node(app,"AutumnFeastKeepsake").visible=bool(own.get("completed",false))
	var reason:=""
	var can_give:=collect and joined
	for slot:String in _slot_ids():
		var def:Dictionary=AF.SLOTS[slot]
		var item:=_filled(pub,slot)
		var card:=_node(app,"AutumnFeastPocket_"+slot) as PanelContainer
		var is_full:=item!=""
		card.add_theme_stylebox_override("panel",_pocket_style(is_full,served))
		card.visible=not served
		var icon:=card.find_child("Icon",true,false) as TextureRect
		var first:String=str((def.get("items",[""]) as Array)[0]) if (def.get("items",[]) as Array).size()>0 else ""
		icon.texture=Items.icon(item if is_full else first) if (is_full or first!="") else null
		icon.modulate=Color.WHITE if is_full else Color(0.5,0.5,0.5,0.6)
		var mark:=card.find_child("Mark",true,false) as Label
		mark.text="已放入 %s"%_item_name(item) if is_full else "還是空的"
		mark.add_theme_color_override("font_color",GOOD if is_full else MUTED)
		(card.find_child("Cost",true,false) as Control).visible=table and not is_full
		(card.find_child("Gives",true,false) as Control).visible=table and not is_full
		var seen:=[]
		for it:String in def.get("items",[]):
			if it in seen:continue
			seen.append(it)
			var b:=card.find_child("AutumnFeastGive_"+it,true,false) as Button
			if b==null:continue
			var n:=int(inv.get(it,0))
			b.text="%s（有 %d）"%[_item_name(it),n]
			b.disabled=not can_give or is_full or n<GIVE_COST
			b.tooltip_text=_give_reason(collect,joined,n,it) if b.disabled else "從背包拿 %d 個%s放進「%s」"%[GIVE_COST,_item_name(it),str(def.get("title",slot))]
	# Finale.
	var finale:=_node(app,"AutumnFeastFinale") as Control
	finale.visible=served
	for slot:String in _slot_ids():
		var col:=_node(app,"Finale_"+slot)
		var item:=_filled(pub,slot)
		(col.find_child("Icon",true,false) as TextureRect).texture=Items.icon(item) if item!="" else null
		(col.find_child("Name",true,false) as Label).text="%s\n%s"%[str(AF.SLOTS[slot].get("title",slot)),_item_name(item) if item!="" else ""]
	# Buttons: each action appears in exactly one phase.
	var start:=_node(app,"AutumnFeastStart") as Button
	var join:=_node(app,"AutumnFeastJoin") as Button
	var serve:=_node(app,"AutumnFeastServe") as Button
	start.visible=not table and not collect
	start.text="再辦一次秋收宴" if (served or bool(own.get("completed",false))) else "開始秋收宴"
	start.disabled=not bool(own.get("can_start",false))
	start.tooltip_text=start_block(own) if start.disabled else ""
	join.visible=table and collect and not joined
	serve.visible=table and collect and joined
	serve.disabled=not full
	serve.tooltip_text="三個口袋都要放滿才能上桌" if serve.disabled else ""
	var close:=_node(app,"AutumnFeastClose") as Button
	close.visible=not table and collect
	close.text="前往共餐桌"
	if not bool(own.get("unlocked",false)) or (phase=="idle" and start.disabled):reason=start_block(own)
	elif collect and joined and not full:reason="還差 %d 個口袋，放滿後才能上桌。"%(AF.SLOTS.size()-count)
	var line:=_node(app,"AutumnFeastReason") as Label
	line.text=reason
	line.visible=reason!=""
	_link_focus(app)
	_restore_focus(app,focus)
	app._layout_preview.call_deferred()

static func _give_reason(collect:bool,joined:bool,held:int,item:String) -> String:
	if not collect:return "還沒開宴"
	if not joined:return "先加入秋收宴"
	if held<GIVE_COST:return "背包裡沒有%s"%_item_name(item)
	return "這個口袋已經放好了"

# -------------------------------------------------------------------- focus --

static func _buttons(app) -> Array[Button]:
	var list:Array[Button]=[]
	var root:=app.modal.get_meta("af_body") as Node
	for slot:String in _slot_ids():
		for item in AF.SLOTS[slot].get("items",[]):
			var g:=root.find_child("AutumnFeastGive_"+str(item),true,false) as Button
			if g!=null and g.is_visible_in_tree() and not g.disabled and not list.has(g):list.append(g)
	for id in ["AutumnFeastStart","AutumnFeastJoin","AutumnFeastServe","AutumnFeastClose"]:
		var b:=_node(app,id) as Button
		if b!=null and b.is_visible_in_tree() and not b.disabled:list.append(b)
	return list

static func _link_focus(app) -> void:
	var list:=_buttons(app)
	for i in list.size():
		var b:=list[i]
		var prev:=list[(i-1+list.size())%list.size()]
		var next:=list[(i+1)%list.size()]
		b.focus_next=b.get_path_to(next)
		b.focus_previous=b.get_path_to(prev)

static func _focus_owner(app) -> Control:
	var f:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if f==null or not (app.modal as Node).is_ancestor_of(f):return null
	return f

static func _preferred(app) -> Button:
	for id in ["AutumnFeastServe","AutumnFeastJoin","AutumnFeastStart"]:
		var b:=_node(app,id) as Button
		if b!=null and b.is_visible_in_tree() and not b.disabled:return b
	var list:=_buttons(app)
	return list[0] if list.size()>0 else _node(app,"AutumnFeastClose") as Button

static func _focus_first(app) -> void:
	if not is_open(app):return
	var b:=_preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

## Focus stays put; only a button that vanished or got disabled hands it on.
static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if is_instance_valid(before) and before.is_visible_in_tree() and not (before is Button and (before as Button).disabled):return
	_focus_first.call_deferred(app)

# ------------------------------------------------------------------- layout --

## root's _layout_preview calls this when life_modal_layout=="autumn_feast".
## Width 960 at 1024 (bounds-48 caps it), up to 1040 at 1280; height follows content.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var preparing:=_phase(_public(app))=="collect" and bool(modal.get_meta("af_table",false))
	var width:=minf(820.0 if preparing else 700.0,bounds.x-48)
	var cap:=bounds.y-32
	var height:=minf(cap,520.0)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))
