extends RefCounted
## 夏季海風市集卡片（規則在 sea_breeze_fair.gd；這裡只讀快照 own_sea_breeze_fair）。
##
## 兩種模式（open(app,counter)）：
##  * 佈告欄模式（counter=false）：「開始 / 完成海風市集」（SeaFairStart / SeaFairFinish）
##    送 app.session.perform(ACTION,BOARD,"start"|"finish")；開始後顯示「去廣場西側市集」
##    的提示，並提供關閉鍵讓玩家直接走過去。
##  * 攤位模式（counter=true）：三顆真正的試吃按鈕 SeaFairServe_<id>（32px 圖示，取自
##    inventory_item_art.gd），送 app.session.perform(ACTION,Market.active_cell(snapshot),"serve:<id>")。
## 答對／答錯的回饋由 main 既有的 modal 回饋列顯示，卡片不重建，所以回饋留在卡上。
## 完成後卡片永遠展示一枚紀念牌（只是展示，不是背包物品）。任何季節都能從佈告欄回來看。
##
## 入口：add_board_link(app,body)（SeaFairBoardLink）、add_market_link(app,body)（SeaFairMarketLink）。
## 版面：open() 設 life_modal_layout=LAYOUT，root 對該值呼叫 layout(app,bounds)。
##
## 節點名稱：SeaFairPanel, SeaFairHead, SeaFairStatus, SeaFairNext, SeaFairClue, SeaFairMarks,
##   SeaFairMark_<0..2>, SeaFairDishes, SeaFairServe_<id>, SeaFairKeepsake, SeaFairReason,
##   SeaFairStart, SeaFairFinish, SeaFairWalk, SeaFairBoardLink, SeaFairMarketLink
const Rules=preload("res://scripts/sea_breeze_fair.gd")
const Market=preload("res://scripts/market_stall.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Portraits=preload("res://scripts/life_ui_theme.gd")

const LAYOUT:="sea_breeze_fair"
const TITLE:="夏季海風市集"
const GUESTS:=3
const INK:=Color("4a3522")
const MUTED:=Color("7d6a50")
const WARN:=Color("a4492f")
const TURQUOISE:=Color("1f9a96")
const TURQUOISE_DEEP:=Color("14706f")
const SAND:=Color("f0e1b8")
const SAND_DIM:=Color("ddd0aa")
const WOOD:=Color("8a5b35")
const WOOD_DIM:=Color("b09a78")
const GUEST_PORTRAITS:={"米露":"milu","阿榆":"aru","小栗":"xiaoli"}

# ------------------------------------------------------------ pure helpers --

static func _state(app) -> Dictionary:
	var v:Variant=app.session.snapshot.get("own_sea_breeze_fair",{})
	return v if v is Dictionary else {}

static func _phase(st:Dictionary) -> String:
	return str(st.get("phase","idle"))

static func _guest(st:Dictionary) -> Dictionary:
	var g:Variant=st.get("guest",{})
	return g if g is Dictionary else {}

static func dishes() -> Array:
	var out:Array=[]
	for id:String in Rules.DISHES:
		var sample:Dictionary=Rules.DISHES[id]
		out.append({"id":id,"title":sample.title,"hint":sample.hint,"item":id})
	return out

static func start_block(st:Dictionary) -> String:
	if not bool(st.get("unlocked",false)):return "海風市集還沒開放。"
	if bool(st.get("active",false)):return ""
	if not bool(st.get("completed",false)) and not bool(st.get("in_season",false)):return "第一次海風市集要等夏天；完成一次後，任何季節都能重玩。"
	return "現在還不能開始海風市集。"

## The next thing to do, one line. Pure: only reads the snapshot dictionary.
static func next_action(st:Dictionary,counter:=false) -> String:
	if bool(st.get("active",false)):
		if _phase(st)=="visit":
			return "客人在廣場西側的市集攤位等著。" if not counter else "照客人的線索，選一道料理端給他。"
		return "客人都招待完了。回到公告板按「完成海風市集」。"
	if bool(st.get("can_start",false)):
		return "回到公告板報名，再去廣場西側市集招待三位客人。" if counter else "聽三位客人的需求，為他們選一道夏日試吃品。"
	return start_block(st)

static func clue_text(st:Dictionary) -> String:
	if not bool(st.get("active",false)) or _phase(st)!="visit":return ""
	var g:=_guest(st)
	if g.is_empty():return ""
	return "%s說：「%s」"%[str(g.get("name","客人")),str(g.get("clue",""))]

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("sbf_body")

static func _counter(app) -> bool:
	return is_open(app) and bool(app.modal.get_meta("sbf_counter",false))

## 32px nearest-neighbour copy of an ItemArt icon so every serve button renders at a real 32px.
static func icon32(id:String) -> Texture2D:
	var tex:Texture2D=Items.icon(id)
	if tex==null:return null
	var img:=tex.get_image()
	if img==null or img.is_empty():return tex
	if img.is_compressed():img.decompress()
	if img.get_width()==32 and img.get_height()==32:return tex
	img=img.duplicate()
	img.resize(32,32,Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------- styles --

static func _box(fill:Color,border:Color,width:int,radius:int,margin:int) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=fill
	s.border_color=border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

static func _sand_card() -> StyleBoxFlat:
	return _box(SAND,WOOD,3,4,8)

static func _mark_style(done:bool) -> StyleBoxFlat:
	return _box(TURQUOISE if done else SAND_DIM,TURQUOISE_DEEP if done else WOOD_DIM,3,16,6)

static func _style_button(b:Button,primary:=false) -> void:
	var fill:=TURQUOISE if primary else SAND
	var hover:=TURQUOISE.lightened(0.15) if primary else SAND.lightened(0.25)
	b.add_theme_stylebox_override("normal",_box(fill,WOOD,3,4,6))
	b.add_theme_stylebox_override("hover",_box(hover,WOOD,3,4,6))
	b.add_theme_stylebox_override("pressed",_box(fill.darkened(0.12),WOOD,3,4,6))
	b.add_theme_stylebox_override("focus",_box(Color(0,0,0,0),TURQUOISE_DEEP,4,4,6))
	b.add_theme_stylebox_override("disabled",_box(SAND_DIM,WOOD_DIM,2,4,6))
	var ink:=Color.WHITE if primary else INK
	b.add_theme_color_override("font_color",ink)
	b.add_theme_color_override("font_hover_color",ink)
	b.add_theme_color_override("font_pressed_color",ink)
	b.add_theme_color_override("font_focus_color",ink)
	b.add_theme_color_override("font_disabled_color",MUTED)

# ---------------------------------------------------------------- structure --

static func _card(parent:Node,id:String,separation:=4) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",_sand_card())
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

static func _button(app,parent:Node,id:String,title:String,callback:Callable,primary:=false) -> Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.focus_mode=Control.FOCUS_ALL
	b.custom_minimum_size=Vector2(150,38)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size",15)
	_style_button(b,primary)
	parent.add_child(b)
	return b

static func open(app,counter:=false) -> void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.name="SeaFairPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("sbf_body",body)
	app.modal.set_meta("sbf_counter",counter)
	body.add_theme_constant_override("separation",8)
	_build(app,body,counter)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text=app.binding_text("Esc 關閉・在市集攤位選料理招待客人" if counter else "Esc 關閉・開始後走去廣場西側市集")
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _build(app,body:VBoxContainer,counter:bool) -> void:
	var head:=_card(body,"SeaFairHead")
	_wrapped(app,head,"SeaFairStatus",16)
	_wrapped(app,head,"SeaFairNext",15,TURQUOISE_DEEP)
	if counter:
		var dialogue:=HBoxContainer.new()
		dialogue.name="SeaFairDialogue"
		dialogue.add_theme_constant_override("separation",12)
		head.add_child(dialogue)
		var portrait:=TextureRect.new()
		portrait.name="SeaFairGuestPortrait"
		portrait.custom_minimum_size=Vector2(54,48)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
		dialogue.add_child(portrait)
		var clue:=_wrapped(app,dialogue,"SeaFairClue",17,INK)
		clue.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	# Three guest progress marks.
	var marks:=HBoxContainer.new()
	marks.name="SeaFairMarks"
	marks.add_theme_constant_override("separation",8)
	head.add_child(marks)
	for i in GUESTS:
		var m:=PanelContainer.new()
		m.name="SeaFairMark_%d"%i
		m.custom_minimum_size=Vector2(112,30)
		m.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var t:=Label.new()
		t.name="Text"
		t.text="客人 %d"%(i+1)
		t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size",14)
		m.add_child(t)
		marks.add_child(m)
	# Dishes: real buttons at the counter, plain sample cards on the board.
	var shelf:=_card(body,"SeaFairDishes",6)
	var cap:=_wrapped(app,shelf,"SeaFairDishesTitle",14,MUTED)
	cap.text="今天的海風料理" if not counter else "試吃品"
	var row:=HBoxContainer.new()
	row.name="SeaFairDishRow"
	row.add_theme_constant_override("separation",8)
	shelf.add_child(row)
	for d:Dictionary in dishes():
		var id:String=d.id
		var label_text:String="%s\n%s"%[d.title,d.hint] if not str(d.hint).is_empty() else str(d.title)
		if counter:
			var b:=_button(app,row,"SeaFairServe_"+id,label_text,func():_send_serve(app,id))
			b.icon=icon32(str(d.item))
			b.expand_icon=false
			b.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size=Vector2(150,58)
			b.add_theme_font_size_override("font_size",14)
			b.add_theme_constant_override("h_separation",8)
			b.tooltip_text=str(d.hint)
		else:
			var card:=PanelContainer.new()
			card.name="SeaFairDish_"+id
			card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel",_box(SAND_DIM,WOOD_DIM,2,4,6))
			row.add_child(card)
			var line:=HBoxContainer.new()
			line.add_theme_constant_override("separation",8)
			card.add_child(line)
			var pic:=TextureRect.new()
			pic.texture=icon32(str(d.item))
			pic.custom_minimum_size=Vector2(32,32)
			pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			pic.mouse_filter=Control.MOUSE_FILTER_IGNORE
			line.add_child(pic)
			var t:=_wrapped(app,line,"Text",14,INK)
			t.text=label_text
	# Keepsake, visible only after completion.
	var keep:=_card(body,"SeaFairKeepsake",4)
	var keep_row:=HBoxContainer.new()
	keep_row.add_theme_constant_override("separation",8)
	keep_row.alignment=BoxContainer.ALIGNMENT_CENTER
	keep.add_child(keep_row)
	for d:Dictionary in dishes():
		var pic:=TextureRect.new()
		pic.texture=Items.icon(str(d.item))
		pic.custom_minimum_size=Vector2(48,48)
		pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter=Control.MOUSE_FILTER_IGNORE
		keep_row.add_child(pic)
	var kt:=_wrapped(app,keep,"SeaFairKeepsakeText",14,TURQUOISE_DEEP)
	kt.text="夏季紀念卡 ・ 三位客人，三道夏日風味"
	kt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	keep.get_parent().visible=false
	_wrapped(app,body,"SeaFairReason",14,WARN)
	var buttons:=HBoxContainer.new()
	buttons.name="SeaFairButtons"
	buttons.add_theme_constant_override("separation",8)
	body.add_child(buttons)
	if not counter:
		_button(app,buttons,"SeaFairStart","開始海風市集",func():_send(app,"start"),true)
		_button(app,buttons,"SeaFairFinish","完成海風市集",func():_send(app,"finish"),true)
	_button(app,buttons,"SeaFairWalk","關閉",func():app._close_modal())

# ------------------------------------------------------------------ actions --

static func _send(app,extra:String) -> void:
	if not is_open(app):return
	app.session.perform(Rules.ACTION,Rules.BOARD,extra)

static func _send_serve(app,id:String) -> void:
	if not _counter(app):return
	var at:Vector2i=Market.active_cell(app.session.snapshot)
	if at==Market.NO_CELL:
		app._notice("市集攤位目前不在渡口廣場上。",false)
		return
	app.session.perform(Rules.ACTION,at,"serve:"+id)

# -------------------------------------------------------------------- links --

static func _link_label(st:Dictionary) -> String:
	var label:=TITLE
	if bool(st.get("active",false)):
		label+="・進行中 %d／%d"%[int(st.get("served",0)),GUESTS]
	elif bool(st.get("can_start",false)):
		label+="・可以開始" if not bool(st.get("completed",false)) else "・再玩一次"
	elif bool(st.get("completed",false)):
		label+="・已完成"
	return label

static func _update_link(app,meta:String,id:String,callback:Callable,at_top:bool) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta(meta):return
	var body:VBoxContainer=app.modal.get_meta(meta)
	if not is_instance_valid(body):return
	var st:=_state(app)
	var counter:=meta=="sbf_market_body"
	var available:bool=st.get("active",false) or (not counter and (st.get("completed",false) or st.get("in_season",false)))
	var allowed:bool=st.get("unlocked",false) and available
	var b:=body.get_node_or_null(id) as Button
	if b==null and not allowed:return
	var label:="海風試吃攤" if counter else _link_label(st)
	if b==null:
		b=app.button(label,callback)
		b.name=id
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size.y=34
		b.add_theme_font_size_override("font_size",14)
		b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		_style_button(b)
		body.add_child(b)
		if at_top:body.move_child(b,0)
	b.visible=allowed
	if b.text!=label:b.text=label
	b.tooltip_text=start_block(st)

## Board page: one link to the card, shown in every season once unlocked.
static func add_board_link(app,body:VBoxContainer) -> void:
	app.modal.set_meta("sbf_board_body",body)
	refresh_board_link(app)

static func refresh_board_link(app) -> void:
	_update_link(app,"sbf_board_body","SeaFairBoardLink",func():open(app,false),true)
	_update_link(app,"sbf_market_body","SeaFairMarketLink",func():open(app,true),true)

## Market stall panel (plaza): link that opens the card in counter mode.
static func add_market_link(app,body:VBoxContainer) -> void:
	app.modal.set_meta("sbf_market_body",body)
	refresh_board_link(app)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("sbf_body") as Node).find_child(id,true,false) as Control

## Updates the open card in place; no-op when it is not open. Also refreshes links.
static func refresh(app,force:=false) -> void:
	refresh_board_link(app)
	if not is_open(app):return
	var st:=_state(app)
	var counter:=_counter(app)
	var active:=bool(st.get("active",false))
	var phase:=_phase(st)
	var served:=clampi(int(st.get("served",0)),0,GUESTS)
	var at:Vector2i=Market.active_cell(app.session.snapshot) if counter else Market.NO_CELL
	var signature:=JSON.stringify([st.get("unlocked"),st.get("in_season"),active,st.get("completed"),st.get("can_start"),served,phase,st.get("guest"),at])
	if not force and str(app.modal.get_meta("sbf_signature",""))==signature:return
	app.modal.set_meta("sbf_signature",signature)
	var focus:=_focus_owner(app)
	var done:=bool(st.get("completed",false))
	var status:="尚未開放"
	if bool(st.get("unlocked",false)):
		if active:status="進行中・已招待 %d／%d 位客人"%[served,GUESTS]
		elif done:status="已完成過・%s"%("現在可以重玩" if bool(st.get("can_start",false)) else "暫時不能重玩")
		else:status="還沒開始・%s"%("夏天了，可以開始" if bool(st.get("in_season",false)) else "要等夏天")
	(_node(app,"SeaFairStatus") as Label).text=status
	(_node(app,"SeaFairNext") as Label).text=app.binding_text(next_action(st,counter))
	if counter:
		var dialogue:=_node(app,"SeaFairDialogue")
		var portrait:=_node(app,"SeaFairGuestPortrait") as TextureRect
		var clue_label:=_node(app,"SeaFairClue") as Label
		var guest:=_guest(st)
		clue_label.text=clue_text(st)
		portrait.texture=Portraits.icon(GUEST_PORTRAITS.get(str(guest.get("name","")),""))
		dialogue.visible=not clue_label.text.is_empty()
	for i in GUESTS:
		var m:=_node(app,"SeaFairMark_%d"%i) as PanelContainer
		var got:=(done and not active) or i<served
		m.add_theme_stylebox_override("panel",_mark_style(got))
		var t:=m.get_node("Text") as Label
		t.text="客人 %d ✓"%(i+1) if got else "客人 %d"%(i+1)
		t.add_theme_color_override("font_color",Color.WHITE if got else MUTED)
	var keep:=_node(app,"SeaFairKeepsake")
	if keep!=null:keep.visible=done and not active
	var reason:=""
	var can_serve:=active and phase=="visit" and not _guest(st).is_empty() and at!=Market.NO_CELL
	if counter:
		if not active:reason=start_block(st) if not bool(st.get("can_start",false)) else "先回公告板按「開始海風市集」。"
		elif phase!="visit":reason="客人都招待完了，回公告板完成。"
		elif at==Market.NO_CELL:reason="市集攤位目前不在渡口廣場上。"
	else:
		if active and phase!="return":reason="去廣場西側的市集攤位，選「海風試吃攤」。"
		elif not active and not bool(st.get("can_start",false)):reason=start_block(st)
	for d:Dictionary in dishes():
		var sb:=_node(app,"SeaFairServe_"+str(d.id)) as Button
		if sb!=null:
			sb.disabled=not can_serve
			sb.tooltip_text=str(d.hint) if can_serve else reason
	var start:=_node(app,"SeaFairStart") as Button
	var finish:=_node(app,"SeaFairFinish") as Button
	if start!=null:
		start.visible=not active
		start.text="再玩一次海風市集" if done else "開始海風市集"
		start.disabled=not bool(st.get("can_start",false))
		start.tooltip_text=start_block(st) if start.disabled else ""
	if finish!=null:
		finish.visible=active
		finish.disabled=phase!="return"
		finish.tooltip_text="先招待完三位客人。" if finish.disabled else ""
	var walk:=_node(app,"SeaFairWalk") as Button
	if walk!=null:
		walk.visible=phase=="return" if counter else active and phase=="visit"
		walk.text="離開攤位，回公告板" if counter else "出發去廣場西側市集"
	var line:=_node(app,"SeaFairReason") as Label
	line.text=reason
	line.visible=not reason.is_empty()
	_link_focus(app)
	_restore_focus(app,focus)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func _buttons(app) -> Array[Button]:
	var list:Array[Button]=[]
	var ids:Array=["SeaFairStart","SeaFairFinish","SeaFairWalk"]
	for d:Dictionary in dishes():ids.push_front("SeaFairServe_"+str(d.id))
	for id:String in ids:
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

static func _focus_first(app) -> void:
	if not is_open(app):return
	var list:=_buttons(app)
	if not list.is_empty() and list[0].is_visible_in_tree():list[0].grab_focus()

## Focus stays where it was; only a button that vanished or got disabled hands it on.
static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if is_instance_valid(before) and before.visible and not (before is Button and (before as Button).disabled):return
	_focus_first.call_deferred(app)

# ------------------------------------------------------------------- layout --

## Root's _layout_preview calls this when life_modal_layout==LAYOUT.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(720.0,bounds.x-48)
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
