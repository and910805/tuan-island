extends RefCounted
## 春季花園日面板（規則在 spring_garden_day.gd；這裡只讀快照 own_spring_garden，
## 按鈕只送 "start" 與 "finish" 兩個 extra：app.session.perform(ACTION,BOARD,extra)）。
##
## 入口：野餐之後的佈告欄頁底 add_board_link(app,body) → open(app)。連結在所有季節都在
## （第一次開始只限春天；完成過一次後任何季節都能重玩，由快照 can_start 決定）。
## 三個景點的 E 互動由 root 處理，這裡不碰；面板有「關閉去走走」，關閉後直接走路。
## 蓋章冊：三張卡（圖示取自 inventory_item_art.gd），蓋過的上色加紅章，沒蓋的變淡。
## 結構只建一次，refresh(app) 每個快照呼叫，原地更新，不丟焦點與位置。
##
## 版面：open() 設 life_modal_layout="spring_garden"，root 的 _layout_preview 對該值呼叫
## SpringGardenUI.layout(app,bounds)（見檔尾）。
const SG=preload("res://scripts/spring_garden_day.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")

const LAYOUT:="spring_garden"
const TITLE:="春季花園日"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const STAMP_RED:=Color("b8442f")

# ------------------------------------------------------------ pure helpers --

static func _state(app) -> Dictionary:
	var v:Variant=app.session.snapshot.get("own_spring_garden",{})
	return v if v is Dictionary else {}

## The next thing to do, one line. Pure: only reads the snapshot dictionary.
static func next_action(st:Dictionary) -> String:
	var mask:=int(st.get("mask",0))
	if bool(st.get("active",false)):
		if mask==SG.FULL_MASK:return "三個章都集滿了！回到公告板按「完成花園日」。"
		for id:String in SG.ORDER:
			if not SG.has_stamp(mask,id):
				var spot:Dictionary=SG.SPOTS[id]
				return "下一站・%s。走近花牌按 {interact} 蓋章。"%str(spot.hint)
		return ""
	if bool(st.get("can_start",false)):
		return "走訪三個景點，把花牌印章帶回公告板。" if not bool(st.get("completed",false)) else "這一頁收藏了你走過的三座花牌。"
	return start_block(st)

static func start_block(st:Dictionary) -> String:
	if not bool(st.get("unlocked",false)):return "先完成野餐，花園日才會開放。"
	if bool(st.get("active",false)):return ""
	if not bool(st.get("completed",false)) and not bool(st.get("in_season",false)):return "第一次花園日要等春天；完成一次後，任何季節都能重玩。"
	return "現在還不能開始花園日。"

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("sg_body")

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

static func open(app) -> void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.name="SpringGardenPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("sg_body",body)
	body.add_theme_constant_override("separation",8)
	_build(app,body)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text=app.binding_text("Esc 關閉・走近花牌按 {interact} 蓋章")
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _build(app,body:VBoxContainer) -> void:
	var head:=_paper(body,"SpringGardenHead")
	_wrapped(app,head,"SpringGardenStatus",16)
	_wrapped(app,head,"SpringGardenNext",15,GOOD)
	var album:=_paper(body,"SpringGardenAlbum",6)
	var cap:=_wrapped(app,album,"SpringGardenAlbumTitle",15,MUTED)
	cap.text="花園蓋章冊"
	var stamps:=HBoxContainer.new()
	stamps.name="SpringGardenStamps"
	stamps.add_theme_constant_override("separation",8)
	album.add_child(stamps)
	for i in SG.SPOTS.size():
		var spot:Dictionary=SG.SPOTS[SG.ORDER[i]]
		var card:=PanelContainer.new()
		card.name="SpringGardenStamp_%d"%i
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		stamps.add_child(card)
		var col:=VBoxContainer.new()
		col.add_theme_constant_override("separation",3)
		card.add_child(col)
		var icon:=TextureRect.new()
		icon.name="Icon"
		icon.texture=Items.icon(str(spot.item))
		icon.custom_minimum_size=Vector2(48,48)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		col.add_child(icon)
		var t:=_wrapped(app,col,"Title",15)
		t.text=str(spot.title)
		t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var h:=_wrapped(app,col,"Hint",12,MUTED)
		h.text=str(spot.hint)
		h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var mark:=_wrapped(app,col,"Mark",15,MUTED)
		mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_wrapped(app,body,"SpringGardenReason",14,WARN)
	var row:=HBoxContainer.new()
	row.name="SpringGardenButtons"
	row.add_theme_constant_override("separation",8)
	body.add_child(row)
	_button(app,row,"SpringGardenStart","開始花園日",func():_send(app,"start"))
	_button(app,row,"SpringGardenFinish","完成花園日",func():_send(app,"finish"))
	_button(app,row,"SpringGardenWalk","關閉去走走",func():app._close_modal())

# ------------------------------------------------------------------ actions --

static func _send(app,extra:String) -> void:
	if not is_open(app):return
	app.session.perform(SG.ACTION,SG.BOARD,extra)

## Board page (after the picnic): one link to this panel, shown in every season.
static func add_board_link(app,body:VBoxContainer) -> void:
	app.modal.set_meta("spring_garden_board_body",body)
	refresh_board_link(app)

static func refresh_board_link(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("spring_garden_board_body"):return
	var body:VBoxContainer=app.modal.get_meta("spring_garden_board_body")
	var st:=_state(app)
	var allowed:=bool(st.get("unlocked",false))
	var b:=body.get_node_or_null("SpringGardenLink") as Button
	if b==null and not allowed:return
	var label:=TITLE
	if bool(st.get("active",false)):label+="・進行中 %d／%d"%[SG.stamp_count(int(st.get("mask",0))),SG.SPOTS.size()]
	elif bool(st.get("can_start",false)):label+="・可以開始" if not bool(st.get("completed",false)) else "・再玩一次"
	if b==null:
		b=app.button(label,func():open(app))
		b.name="SpringGardenLink"
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size.y=34
		b.add_theme_font_size_override("font_size",14)
		b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		body.add_child(b)
		body.move_child(b,0)
	b.visible=allowed
	if b.text!=label:b.text=label
	b.tooltip_text=start_block(st)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("sg_body") as Node).find_child(id,true,false) as Control

static func _stamp_style(stamped:bool) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=Color("f7ecc8") if stamped else Color("d9d4c4")
	s.border_color=STAMP_RED if stamped else Color("a9a28c")
	s.set_border_width_all(3 if stamped else 2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	return s

## Rebuilds nothing: updates the open panel in place; no-op when it is not open.
static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var st:=_state(app)
	var mask:=int(st.get("mask",0))
	var active:=bool(st.get("active",false))
	var signature:=JSON.stringify([st.get("unlocked"),st.get("in_season"),active,mask,st.get("completed"),st.get("can_start")])
	if not force and str(app.modal.get_meta("sg_signature",""))==signature:return
	app.modal.set_meta("sg_signature",signature)
	var focus:=_focus_owner(app)
	var done:=bool(st.get("completed",false))
	var status:="尚未開放"
	if bool(st.get("unlocked",false)):
		if active:status="進行中・已蓋章 %d／%d"%[SG.stamp_count(mask),SG.SPOTS.size()]
		elif done:status="已完成過・%s"%("現在可以重玩" if bool(st.get("can_start",false)) else "暫時不能重玩")
		else:status="還沒開始・%s"%("春天了，可以開始" if bool(st.get("in_season",false)) else "要等春天")
	(_node(app,"SpringGardenStatus") as Label).text=status
	(_node(app,"SpringGardenNext") as Label).text=app.binding_text(next_action(st))
	for i in SG.SPOTS.size():
		var stamped:bool=(done and not active) or SG.has_stamp(mask,SG.ORDER[i])
		var card:=_node(app,"SpringGardenStamp_%d"%i) as PanelContainer
		card.add_theme_stylebox_override("panel",_stamp_style(stamped))
		(card.find_child("Icon",true,false) as CanvasItem).modulate=Color.WHITE if stamped else Color(0.45,0.45,0.45,0.55)
		var mark:=card.find_child("Mark",true,false) as Label
		mark.text="已蓋章" if stamped else "還沒蓋章"
		mark.add_theme_color_override("font_color",STAMP_RED if stamped else MUTED)
		(card.find_child("Title",true,false) as Label).add_theme_color_override("font_color",INK if stamped else MUTED)
	var reason:=""
	if active and mask!=SG.FULL_MASK:reason="還差 %d 個章，集滿後才能完成。"%(SG.SPOTS.size()-SG.stamp_count(mask))
	elif not active and not bool(st.get("can_start",false)):reason=start_block(st)
	var start:=_node(app,"SpringGardenStart") as Button
	var finish:=_node(app,"SpringGardenFinish") as Button
	start.visible=not active
	start.text="再玩一次花園日" if done else "開始花園日"
	start.disabled=not bool(st.get("can_start",false))
	start.tooltip_text=start_block(st) if start.disabled else ""
	finish.visible=active
	finish.disabled=mask!=SG.FULL_MASK
	finish.tooltip_text=reason if finish.disabled else ""
	var line:=_node(app,"SpringGardenReason") as Label
	line.text=reason
	line.visible=not line.text.is_empty()
	_link_focus(app)
	_restore_focus(app,focus)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func _buttons(app) -> Array[Button]:
	var list:Array[Button]=[]
	for id in ["SpringGardenStart","SpringGardenFinish","SpringGardenWalk"]:
		var b:=_node(app,id) as Button
		if b!=null and b.visible and not b.disabled:list.append(b)
	return list

static func _link_focus(app) -> void:
	var list:=_buttons(app)
	for i in list.size():
		var b:=list[i]
		var prev:=list[(i-1+list.size())%list.size()]
		var next:=list[(i+1)%list.size()]
		b.focus_neighbor_left=b.get_path_to(prev)
		b.focus_neighbor_right=b.get_path_to(next)
		b.focus_next=b.get_path_to(next)
		b.focus_previous=b.get_path_to(prev)

static func _focus_owner(app) -> Control:
	var f:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if f==null or not (app.modal as Node).is_ancestor_of(f):return null
	return f

## The primary action when enabled, else the walk-away button.
static func _preferred(app) -> Button:
	for id in ["SpringGardenFinish","SpringGardenStart"]:
		var b:=_node(app,id) as Button
		if b!=null and b.visible and not b.disabled:return b
	return _node(app,"SpringGardenWalk") as Button

static func _focus_first(app) -> void:
	if not is_open(app):return
	var b:=_preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

## Focus stays where it was; only a button that vanished or got disabled hands it on.
static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if is_instance_valid(before) and before.visible and not (before is Button and (before as Button).disabled):return
	_focus_first.call_deferred(app)

# ------------------------------------------------------------------- layout --

## Optional custom layout: root's _layout_preview calls this when life_modal_layout=="spring_garden".
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(720.0,bounds.x-48)
	var cap:=bounds.y-32
	var height:=minf(cap,460.0)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))
