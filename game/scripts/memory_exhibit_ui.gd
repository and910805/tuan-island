extends RefCounted
## 第 40 章「風鈴節廣場・地方記憶展」用戶端：世界裡的展台（圖、名牌、互動點）與「地方記憶展」頁。
## 規則全在 memory_exhibit.gd；這裡只讀快照（公開 memory_exhibit、本人 own_memory_exhibit、
## lanyang_revisit 公開欄位）並送唯一的動作 exhibit_view。
##
## 世界：風鈴節開幕後在使用中的展台格（(39,26) → (41,23) → (37,22)）畫 56×56 展台
##  （memory_exhibit_art.stand，格子左上 + (-12,-24)）；開幕前與暫停（三格都被佔）時不畫。
##  名牌「地方記憶展」，自己有未看的展品時加「・新」並在匾額右側畫紅色小圓點；
##  聚焦時「看地方記憶展」＋互動鍵（名牌錨點往東 8px，避開西邊兩格的紀念品交換攤）。
##  展台在該列所有格子畫完後才畫（(40,26) 的石頭留在展台右柱後面）；其他互動提示避開展台的
##  牆面與展台（world_view.label_obstacles）。玩家站在展台後方（上一列）且身體與展台重疊時，
##  展台半透明，人不會被蓋住。各動態模式都是靜態圖，預覽與一般繪製走同一條 world_view 路徑。
##  互動點順序（main._interact / world_view.interaction_focus）：…紀念品交換攤 → 本展台 → 物件。
##
## 頁面（版面由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  說明一行；整頁狀態一行（鎖定、暫停＋要清的格子、四座都空、離展台太遠時的提醒）；
##  四張展品卡（MemoryCard_<id>，可聚焦的按鈕：圖示、名稱、地區、展出中／展台空著、
##  「新」或「已看過」）；下方左邊是選中展品的說明（來源、對應工程、完成那天、需求、閘、
##  原創聲明）或「翻閱回顧」的分頁（4 頁，上一頁／下一頁／回到展品），右邊是「你的進度」
##  （依選中的展品 personal_hint_for：分水木牌＝第一次分水／木牌，礦燈＝礦樣整理／礦燈，
##  陶器＝跟茶茶的包裝比較／茶陶組，鹽籃＝在北門親手收過鹽／鹽籃）。
##  送出時機（本實作的選擇）：翻到回顧最後一頁的那一刻，若這件展品自己還沒看過、
##  view_block 為空、且人在展台 REACH 內，就送一次 exhibit_view（同一頁開著時每件只送一次；
##  ALREADY_SEEN 是失敗回覆，所以看過的不送）。最後一頁的「下一頁」改成「看完了」，按下回到
##  展品說明，不再送動作。離展台太遠時不送，頁面提醒走到展台前再看一次。伺服器回覆由
##  main._notice 寫在頁底。頁面只建一次，refresh() 依快照就地更新，焦點留在原處。
##  焦點：卡片列左右循環、上到「關閉」、下到動作列；動作列左右循環、上回選中的卡片。
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Art=preload("res://scripts/memory_exhibit_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

const LAYOUT:="memory_exhibit"
const POINT:="memory_exhibit:stand"
const TITLE:=Exhibit.TITLE
const NO_CELL:=Exhibit.NO_CELL
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const NEW_RED:=Color("c8453a")
## Stand sprite offset from its cell's top-left and size (world px, unzoomed).
const STAND_OFFSET:=Vector2(-12,-24)
const STAND_SIZE:=Vector2(56,56)
## World label anchor from the cell's top-left: above the roof, nudged 8 px east so the
## focused prompt stays off the 紀念品交換攤 awning two tiles west (screenshots, before/).
const LABEL_ANCHOR:=Vector2(24,-27)
const INTRO:="風鈴節之後，各地回訪帶回的紀念物擺在這座展台。錯過的島民也能在這裡翻閱回顧。"
const NONE_ON_DISPLAY:="四座展台目前都空著：回訪故事完成之後，對應的紀念物才會擺上來。"
const WALK:="翻閱回顧哪裡都能看；站在展台前看完最後一頁，展台才會記下你看過了。"
const NOT_NEAR_DONE:="回顧看完了。走到展台前再翻到最後一頁，展台才會記下你看過了。"
const ENTRY_OPEN:="地方記憶展（廣場北緣）"
const ENTRY_LOCKED:="地方記憶展・風鈴節後開放"
const STATUS_ON:="展出中・回顧 4 頁"
const STATUS_EMPTY:="展台空著"
const BADGE_NEW:="新"
const BADGE_SEEN:="已看過"
const RECAP:="翻閱回顧"
const PREV:="上一頁"
const NEXT:="下一頁"
const DONE:="看完了"
const BACK:="回到展品"
const TRACKER:="地方記憶展・%d 件新展品\n到廣場北緣的展台補看回顧"

# ------------------------------------------------------------ pure helpers --

static func at_home(s:Dictionary) -> bool:
	return str(s.get("region_id","home"))=="home"

## Active stand cell in this (home) snapshot; NO_CELL before the festival, while
## paused and outside home.
static func stand_cell(s:Dictionary) -> Vector2i:
	return Exhibit.stand_cell(s) if at_home(s) else NO_CELL

static func stand_shown(s:Dictionary) -> bool:
	return stand_cell(s)!=NO_CELL

static func _person(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

static func near_stand(s:Dictionary,own_id:String) -> bool:
	var cell:=stand_cell(s)
	if cell==NO_CELL:return false
	var person:=_person(s,own_id)
	if person.is_empty():return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Exhibit.REACH

## World label: short name, "・新" with unread exhibits, what the interact key does when focused.
static func stand_title(s:Dictionary,focused:bool) -> String:
	if focused:return "看"+TITLE  # short: the prompt + key badge stays off the 紀念品交換攤 awning
	return TITLE+"・新" if Exhibit.unread_count(s)>0 else TITLE

static func entry_caption(s:Dictionary) -> String:
	return ENTRY_OPEN if Exhibit.unlocked(s) else ENTRY_LOCKED

## Journal (島嶼近況) line; "" before the festival.
static func news_line(s:Dictionary) -> String:
	if not Exhibit.unlocked(s):return ""
	return "地方記憶展：%d 件展出・%d 件還沒看"%[Exhibit.on_display_ids(s).size(),Exhibit.unread_count(s)]

## Home tracker (lowest priority): "" when nothing is unread.
static func tracker_text(s:Dictionary) -> String:
	if not at_home(s) or not Exhibit.unlocked(s):return ""
	var n:=Exhibit.unread_count(s)
	return TRACKER%n if n>0 else ""

static func cells_text() -> String:
	var parts:=PackedStringArray()
	for cell:Vector2i in Exhibit.CANDIDATES:parts.append("(%d,%d)"%[cell.x,cell.y])
	return "、".join(parts)

## The page-wide state line ("" = hidden).
static func page_line(s:Dictionary,own_id:String) -> String:
	if not Exhibit.unlocked(s):return Exhibit.LOCKED
	if Exhibit.paused(s):return Exhibit.NO_POINT%cells_text()+"拿走上面的物件、地板、屋頂、作物或樹即可。"
	if Exhibit.on_display_ids(s).is_empty():return NONE_ON_DISPLAY
	if Exhibit.unread_count(s)>0 and not near_stand(s,own_id):return WALK
	return ""

# -------------------------------------------------------------------- art --

static func stand_rect(view,cell:Vector2i) -> Rect2:
	return Rect2(view.screen(Vector2(cell))+STAND_OFFSET,STAND_SIZE)

## The stand's contents (wall, name board, pedestals) without eaves, posts and plinth.
static func stand_inner_rect(view,cell:Vector2i) -> Rect2:
	return Rect2(stand_rect(view,cell).position+Vector2(6,10),Vector2(44,36))

## Called by world_view in row order at the stand cell (static in every motion mode).
static func draw_stand(view,at:Vector2,cell:Vector2i) -> void:
	var data:Dictionary=view.data
	var alpha:=1.0
	var me:String=str(view.player_id)
	if view.display_positions.has(me):
		var local:Vector2=view.display_positions[me]
		var body:=Rect2(view.screen(local)+Vector2(-11,-38),Vector2(22,40))
		if floori(local.y)<cell.y and stand_rect(view,cell).intersects(body):alpha=0.45
	var tint:=Color(1,1,1,alpha)
	view.draw_texture(Art.stand(Exhibit.on_display_ids(data)),at+STAND_OFFSET,tint)
	if Exhibit.unread_count(data)>0:
		var dot:=at+STAND_OFFSET+Vector2(45,16)
		view.draw_circle(dot,4.5,Color("392d23",alpha))
		view.draw_circle(dot,3.5,Color(NEW_RED,alpha))
		view.draw_rect(Rect2(dot+Vector2(-1,-2),Vector2(2,2)),Color("fff3d2",alpha))

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("exhibit_body")

static func open(app) -> void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="MemoryExhibitPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("exhibit_body",body)
	app.modal.set_meta("exhibit_sent",[])
	app.modal.set_meta("exhibit_page",-1)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
		app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_theme_constant_override("separation",7)
	var s:Dictionary=app.session.snapshot
	app.modal.set_meta("exhibit_selected",default_selection(s))
	build(app,body)
	refresh(app,true)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上"
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## First unread exhibit on display, else the first on display, else 分水木牌.
static func default_selection(s:Dictionary) -> String:
	for row:Dictionary in Exhibit.exhibits(s):
		if bool(row.unread):return str(row.id)
	var shown:=Exhibit.on_display_ids(s)
	return str(shown[0]) if not shown.is_empty() else str(Exhibit.EXHIBIT_ORDER[0])

## main._layout_preview: centred horizontally, as tall as its content, with a fixed top
## edge so switching between the exhibit text and the recap pages never moves the cards.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(860,bounds.x-48)
	var top:=floorf(maxf(12.0,(bounds.y-600.0)/2.0))
	var cap:=bounds.y-top-12.0
	var height:=minf(cap,600)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),top)

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
	b.custom_minimum_size=Vector2(96,34)
	b.add_theme_font_size_override("font_size",15)
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

static func _paper(parent:Node,id:String) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",3)
	card.add_child(col)
	return col

static func build(app,body:VBoxContainer) -> void:
	var intro:=_wrapped(app,body,"MemoryIntro",14,MUTED)
	intro.text=INTRO
	_wrapped(app,body,"MemoryState",14,WARN)
	var cards:=HBoxContainer.new()
	cards.name="MemoryCards"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	var group:=ButtonGroup.new()
	group.allow_unpress=false
	for id:String in Exhibit.EXHIBIT_ORDER:_card(app,cards,id,group)
	var lower:=HBoxContainer.new()
	lower.name="MemoryLower"
	lower.add_theme_constant_override("separation",8)
	body.add_child(lower)
	# Detail / recap pager of the selected exhibit.
	var detail:=_paper(lower,"MemoryDetail")
	(detail.get_parent() as Control).size_flags_stretch_ratio=2.2
	var head:=HBoxContainer.new()
	head.add_theme_constant_override("separation",10)
	detail.add_child(head)
	var big:=picture(null,48)
	big.name="MemoryDetailIcon"
	head.add_child(big)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",1)
	head.add_child(words)
	_text(app,words,"MemoryDetailName",18)
	_text(app,words,"MemoryDetailRegion",13,MUTED)
	var info:=VBoxContainer.new()
	info.name="MemoryInfo"
	info.add_theme_constant_override("separation",2)
	detail.add_child(info)
	_wrapped(app,info,"MemoryBlurb",14)
	_wrapped(app,info,"MemorySource",13,MUTED)
	_wrapped(app,info,"MemoryDay",13)
	_wrapped(app,info,"MemoryDemand",13)
	_wrapped(app,info,"MemoryGates",13)
	_wrapped(app,info,"MemoryEmpty",14,MUTED)
	var pager:=VBoxContainer.new()
	pager.name="MemoryPager"
	pager.add_theme_constant_override("separation",3)
	detail.add_child(pager)
	_text(app,pager,"MemoryPageTitle",16,GOOD)
	_wrapped(app,pager,"MemoryPageLines",14)
	_wrapped(app,detail,"MemoryDisclaimer",12,MUTED)
	var actions:=HBoxContainer.new()
	actions.name="MemoryActions"
	actions.add_theme_constant_override("separation",8)
	detail.add_child(actions)
	_button(app,actions,"MemoryRecap",RECAP,func():_open_recap(app))
	_button(app,actions,"MemoryPrev",PREV,func():_turn(app,-1))
	_button(app,actions,"MemoryNext",NEXT,func():_turn(app,1))
	_button(app,actions,"MemoryBack",BACK,func():_close_recap(app))
	# Personal progress.
	var mine:=_paper(lower,"MemoryPersonal")
	_text(app,mine,"MemoryPersonalTitle",16).text="你的進度"
	_text(app,mine,"MemoryFirstShare",13)
	_text(app,mine,"MemoryPlaque",13)
	_text(app,mine,"MemorySeenCount",13)
	_wrapped(app,mine,"MemoryHint",13,MUTED)

static func _card(app,row:HBoxContainer,id:String,group:ButtonGroup) -> Button:
	var b:Button=app.button("",func():select(app,id))
	b.name="MemoryCard_"+id
	b.toggle_mode=true
	b.button_group=group
	b.focus_mode=Control.FOCUS_ALL
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.custom_minimum_size=Vector2(150,78)
	# Light paper cards; the chosen one keeps the paper colour with a thick green frame so
	# the dark ink stays readable (the pixel theme's pressed style is dark green).
	for state:Array in [["normal",Color("f1e3bf"),Color("b89b6a"),2],["hover",Color("f7ead0"),Color("9c7f4f"),2],
			["pressed",Color("fff6dc"),GOOD,3],["hover_pressed",Color("fff6dc"),GOOD,3],["disabled",Color("e8dcc0"),Color("b89b6a"),2]]:
		var box:=StyleBoxFlat.new()
		box.bg_color=state[1]
		box.border_color=state[2]
		box.set_border_width_all(int(state[3]))
		box.set_corner_radius_all(2)
		b.add_theme_stylebox_override(str(state[0]),box)
	row.add_child(b)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]:margin.add_theme_constant_override("margin_"+side,8)
	for side in ["top","bottom"]:margin.add_theme_constant_override("margin_"+side,5)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",6)
	line.mouse_filter=Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)
	var icon:=picture(Art.icon(id),32)
	icon.name="MemoryIcon_"+id
	line.add_child(icon)
	var col:=VBoxContainer.new()
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation",0)
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	var top:=HBoxContainer.new()
	top.add_theme_constant_override("separation",4)
	top.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_text(app,top,"MemoryName_"+id,15).text=str(Exhibit.EXHIBITS[id].name)
	var gap:=Control.new()
	gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	gap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_text(app,top,"MemoryBadge_"+id,12,NEW_RED)
	_text(app,col,"MemoryRegion_"+id,12,MUTED).text=str(Exhibit.EXHIBITS[id].region)
	_text(app,col,"MemoryStatus_"+id,12)
	return b

# ------------------------------------------------------------------ actions --

static func selected(app) -> String:
	return str(app.modal.get_meta("exhibit_selected","lanyang")) if is_open(app) else ""

static func page_index(app) -> int:
	return int(app.modal.get_meta("exhibit_page",-1)) if is_open(app) else -1

static func select(app,id:String) -> void:
	if not is_open(app):return
	app.modal.set_meta("exhibit_selected",id)
	app.modal.set_meta("exhibit_page",-1)
	refresh(app,true)

static func _open_recap(app) -> void:
	if not is_open(app):return
	if Exhibit.recap_pages(selected(app),app.session.snapshot).is_empty():return
	app.modal.set_meta("exhibit_page",0)
	refresh(app,true)
	_focus(app,"MemoryNext")

static func _close_recap(app) -> void:
	if not is_open(app):return
	app.modal.set_meta("exhibit_page",-1)
	refresh(app,true)
	_focus(app,"MemoryRecap")

## Turn one page. On the last page 「看完了」 returns to the exhibit.
static func _turn(app,step:int) -> void:
	if not is_open(app):return
	var pages:=Exhibit.recap_pages(selected(app),app.session.snapshot)
	var at:=page_index(app)
	if pages.is_empty() or at<0:return
	if step>0 and at>=pages.size()-1:
		_close_recap(app)
		return
	at=clampi(at+step,0,pages.size()-1)
	app.modal.set_meta("exhibit_page",at)
	if at==pages.size()-1:_finished(app,selected(app))
	refresh(app,true)

## Reached the last recap page: send exhibit_view once if this exhibit is unread.
static func _finished(app,id:String) -> void:
	var s:Dictionary=app.session.snapshot
	var sent:Array=app.modal.get_meta("exhibit_sent",[])
	if id in sent:return
	if not Exhibit.view_block(s,id).is_empty():return
	if not near_stand(s,str(app.session.own_id)):
		if is_instance_valid(app.modal_feedback):
			app.modal_feedback.text=NOT_NEAR_DONE
			app.modal_feedback.add_theme_color_override("font_color",WARN)
		return
	sent.append(id)
	app.modal.set_meta("exhibit_sent",sent)
	app.session.perform(Exhibit.VIEW_ACTION,stand_cell(s),Exhibit.extra_for(id))

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("exhibit_body") as Node).find_child(id,true,false) as Control

static func _put(app,id:String,value:String,color=null) -> Label:
	var l:=_node(app,id) as Label
	if l==null:return null
	l.text=value
	if color is Color:l.add_theme_color_override("font_color",color)
	l.visible=not value.is_empty()
	return l

static func _show(app,id:String,on:bool) -> void:
	var c:=_node(app,id)
	if c!=null:c.visible=on

static func refresh(app,force:=false) -> void:
	refresh_entries(app)
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var own_id:=str(app.session.own_id)
	var unlocked:=Exhibit.unlocked(s)
	var id:=selected(app)
	var rows:=Exhibit.exhibits(s)
	var row:=Exhibit.exhibit(s,id)
	var pages:=Exhibit.recap_pages(id,s)
	var at:=page_index(app)
	if pages.is_empty() and at>=0:
		at=-1
		app.modal.set_meta("exhibit_page",-1)
	var mine:=Exhibit.personal(s)
	var line:=page_line(s,own_id)
	var signature:=JSON.stringify([unlocked,id,at,rows,line,mine,app.modal.get_meta("exhibit_sent",[])])
	if not force and str(app.modal.get_meta("exhibit_signature",""))==signature:return
	app.modal.set_meta("exhibit_signature",signature)
	var focus_before:=_focus_owner(app)
	_put(app,"MemoryState",line,MUTED if line in [NONE_ON_DISPLAY,WALK] else WARN)
	for part in ["MemoryCards","MemoryLower"]:_show(app,part,unlocked)
	# Cards.
	for r:Dictionary in rows:
		var rid:=str(r.id)
		var card:=_node(app,"MemoryCard_"+rid) as Button
		if card!=null:
			card.set_pressed_no_signal(rid==id)
			card.tooltip_text=("%s・%s"%[str(r.name),str(r.story)]) if bool(r.on_display) else Exhibit.EMPTY_LINE
		var icon:=_node(app,"MemoryIcon_"+rid) as TextureRect
		if icon!=null:icon.modulate=Color(1,1,1,1.0 if bool(r.on_display) else 0.3)
		_put(app,"MemoryStatus_"+rid,STATUS_ON if bool(r.on_display) else STATUS_EMPTY,GOOD if bool(r.on_display) else MUTED)
		var badge:=BADGE_NEW if bool(r.unread) else (BADGE_SEEN if bool(r.seen) else "")
		_put(app,"MemoryBadge_"+rid,badge,NEW_RED if bool(r.unread) else GOOD)
	# Detail of the selected exhibit.
	var shown:=bool(row.get("on_display",false))
	var big:=_node(app,"MemoryDetailIcon") as TextureRect
	if big!=null:
		big.texture=Art.icon(id)
		big.modulate=Color(1,1,1,1.0 if shown else 0.3)
	_put(app,"MemoryDetailName",str(row.get("name","")))
	_put(app,"MemoryDetailRegion","%s・%s"%[str(row.get("region","")),str(row.get("story",""))])
	var paging:=at>=0 and not pages.is_empty()
	_show(app,"MemoryInfo",not paging)
	_show(app,"MemoryPager",paging)
	var lines:Array=row.get("lines",[])
	if shown and lines.size()>=7:
		_put(app,"MemoryBlurb",str(lines[0]))
		_put(app,"MemorySource","%s　%s"%[str(lines[1]),str(lines[2])])
		_put(app,"MemoryDay",str(lines[3]))
		_put(app,"MemoryDemand",str(lines[4]))
		_put(app,"MemoryGates",str(lines[5]))
		_put(app,"MemoryEmpty","")
	else:
		for part in ["MemoryBlurb","MemorySource","MemoryDay","MemoryDemand","MemoryGates"]:_put(app,part,"")
		_put(app,"MemoryEmpty",Exhibit.EMPTY_LINE)
	var disclaimer:=str(row.get("disclaimer","")) if shown else ""
	if paging and str(pages[at].lines).contains(disclaimer):disclaimer=""  # the last page already says it
	_put(app,"MemoryDisclaimer",disclaimer)
	if paging:
		var page:Dictionary=pages[at]
		_put(app,"MemoryPageTitle","回顧 %d／%d・%s"%[at+1,pages.size(),str(page.title)])
		_put(app,"MemoryPageLines","\n".join(PackedStringArray(page.lines)))
	# Actions.
	var recap:=_node(app,"MemoryRecap") as Button
	if recap!=null:
		recap.visible=not paging
		recap.disabled=pages.is_empty()
		recap.tooltip_text="翻閱 4 頁回顧" if not pages.is_empty() else Exhibit.EMPTY_LINE
	for part in ["MemoryPrev","MemoryNext","MemoryBack"]:_show(app,part,paging)
	var prev:=_node(app,"MemoryPrev") as Button
	if prev!=null:prev.disabled=at<=0
	var next:=_node(app,"MemoryNext") as Button
	if next!=null:
		var last:=paging and at>=pages.size()-1
		next.text=DONE if last else NEXT
		next.tooltip_text="回到展品說明" if last else "翻到下一頁"
	# Personal box: the selected exhibit decides which progress lines and hint are shown
	# (personal_hint_for); exhibits without a revisit story yet keep the 分水木牌 lines.
	var progress_id:=id if not Exhibit.personal_hint_for(s,id).is_empty() else "lanyang"
	if progress_id=="jinguashi":
		_put(app,"MemoryFirstShare",("✓ 已跟波波整理過礦樣" if bool(mine.sorting_done) else "○ 還沒跟波波整理過礦樣"),GOOD if bool(mine.sorting_done) else MUTED)
		_put(app,"MemoryPlaque",("✓ 已領礦燈" if bool(mine.lantern_claimed) else "○ 還沒領礦燈"),GOOD if bool(mine.lantern_claimed) else MUTED)
	elif progress_id=="tea_pottery":
		var compared:=bool(mine.get("comparison_done",false))
		var teaware:=bool(mine.get("teaware_claimed",false))
		_put(app,"MemoryFirstShare",("✓ 已跟茶茶比較過兩種包裝" if compared else "○ 還沒跟茶茶比較兩種包裝"),GOOD if compared else MUTED)
		_put(app,"MemoryPlaque",("✓ 已領茶陶組" if teaware else "○ 還沒領茶陶組"),GOOD if teaware else MUTED)
	elif progress_id=="beimen":
		var raked:=bool(mine.get("raking_done",false))
		var basket:=bool(mine.get("basket_claimed",false))
		_put(app,"MemoryFirstShare",("✓ 已在北門親手收過鹽" if raked else "○ 還沒在北門親手收過鹽"),GOOD if raked else MUTED)
		_put(app,"MemoryPlaque",("✓ 已領鹽籃" if basket else "○ 還沒領鹽籃"),GOOD if basket else MUTED)
	else:
		_put(app,"MemoryFirstShare",("✓ 已走完自己的第一次分水" if bool(mine.first_share_done) else "○ 還沒走完自己的第一次分水"),GOOD if bool(mine.first_share_done) else MUTED)
		_put(app,"MemoryPlaque",("✓ 已領分水木牌" if bool(mine.plaque_claimed) else "○ 還沒領分水木牌"),GOOD if bool(mine.plaque_claimed) else MUTED)
	var on_count:=Exhibit.on_display_ids(s).size()
	_put(app,"MemorySeenCount",("看過 %d／%d 件展出中的展品"%[on_count-int(mine.unread),on_count]) if on_count>0 else "目前沒有展出中的展品",INK)
	_put(app,"MemoryHint",Exhibit.personal_hint_for(s,progress_id),MUTED)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

## Journal / festival-page entries that live outside this page (updated in place).
static func refresh_entries(app) -> void:
	if not is_instance_valid(app.modal):return
	var s:Dictionary=app.session.snapshot
	var news:=app.modal.find_child("MemoryExhibitNews",true,false) as Button
	if news!=null:
		var text:=news_line(s)
		if news.text!=text and not text.is_empty():news.text=text
	var entry:=app.modal.find_child("MemoryExhibitEntry",true,false) as Button
	if entry!=null:
		var caption:=entry_caption(s)
		if entry.text!=caption:entry.text=caption
		entry.tooltip_text="" if Exhibit.unlocked(s) else Exhibit.LOCKED

## Entry button on the festival page / board (opens the page from anywhere).
static func entry_button(app) -> Button:
	var s:Dictionary=app.session.snapshot
	var b:Button=app.button(entry_caption(s),func():open(app))
	b.name="MemoryExhibitEntry"
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not Exhibit.unlocked(s):b.tooltip_text=Exhibit.LOCKED
	return b

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("exhibit_body") if app.modal.has_meta("exhibit_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("exhibit_body"):break
		node=node.get_parent()
	return true

static func cards(app) -> Array[Button]:
	var out:Array[Button]=[]
	for id:String in Exhibit.EXHIBIT_ORDER:
		var b:=_node(app,"MemoryCard_"+id) as Button
		if b!=null and _shown(b):out.append(b)
	return out

static func action_row(app) -> Array[Button]:
	var out:Array[Button]=[]
	for id:String in ["MemoryRecap","MemoryPrev","MemoryNext","MemoryBack"]:
		var b:=_node(app,id) as Button
		if b!=null and _shown(b):out.append(b)
	return out

static func link_focus(app) -> void:
	var rows:Array=[]
	var top:=cards(app)
	if not top.is_empty():rows.append(top)
	var bottom:=action_row(app)
	if not bottom.is_empty():rows.append(bottom)
	var close:=close_button(app)
	var flat:Array[Button]=[]
	for row:Array in rows:
		for b:Button in row:flat.append(b)
	var chosen:=_node(app,"MemoryCard_"+selected(app)) as Button
	for r in rows.size():
		var row:Array=rows[r]
		for i in row.size():
			var b:Button=row[i]
			b.focus_neighbor_left=b.get_path_to(row[(i-1+row.size())%row.size()])
			b.focus_neighbor_right=b.get_path_to(row[(i+1)%row.size()])
			if r==0:
				if close!=null:b.focus_neighbor_top=b.get_path_to(close)
			else:
				b.focus_neighbor_top=b.get_path_to(chosen if chosen!=null and chosen in rows[0] else rows[r-1][0])
			b.focus_neighbor_bottom=b.get_path_to(rows[r+1][0] if r+1<rows.size() else b)
			var at:=flat.find(b)
			b.focus_next=b.get_path_to(flat[(at+1)%flat.size()])
			b.focus_previous=b.get_path_to(flat[(at-1+flat.size())%flat.size()])
	if close!=null and not flat.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(chosen if chosen!=null and chosen in flat else flat[0])
		close.focus_next=close.get_path_to(flat[0])

static func _focus(app,id:String) -> void:
	var b:=_node(app,id) as Button
	if b!=null and _shown(b):b.grab_focus()

static func _focus_owner(app) -> Control:
	if not is_open(app):return null
	var owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if owner==null or not (app.modal as Node).is_ancestor_of(owner):return null
	return owner

## Focus the selected card (or the close button when the page is locked).
static func focus_first(app) -> void:
	if not is_open(app):return
	var b:=_node(app,"MemoryCard_"+selected(app)) as Button
	if b!=null and b.is_visible_in_tree():
		b.grab_focus()
		return
	var close:=close_button(app)
	if close!=null:close.grab_focus()

static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if not is_instance_valid(before) or not _shown(before):
		_refocus_if_lost.call_deferred(app)

## Deferred: only when nothing visible in the page holds focus any more (a caller may
## already have moved focus to the right button, e.g. 「翻閱回顧」 after 「看完了」).
static func _refocus_if_lost(app) -> void:
	if not is_open(app):return
	var owner:=_focus_owner(app)
	if owner!=null and _shown(owner) and owner.is_visible_in_tree():return
	focus_first(app)
