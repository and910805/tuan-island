extends RefCounted
## 第 40 章金瓜石初訪「河邊淘砂金」頁（規則在 gold_panning.gd，這裡只讀快照、送動作
## gold_pan，cell＝Gold.SITE，extra＝下一步 scoop／sift／swirl／pick）。
##
## 入口：金瓜石山城西側水邊的淘砂處 SITE。main._interact 把 POINT（"gold_pan"）加進金瓜石的
##  互動點，靠近按一般互動鍵就開這頁；沒有新按鍵。
##
## 版面（由上而下，1024×640 與 1280×800 都不需外層捲動）：
##  標頭卡（今天 n／3 盤・累計 n 盤）→ 淘砂盤卡（64×64 盤子俯視圖放大成 128×128、盤裡現在的樣子、
##  四個步驟小標「✓ 已做／▶ 現在／○ 還沒」）→ 一個動作按鈕（文字跟著下一步變）→ 不能按的原因 →
##  背包含金礦料數 → 說明 BLURB → 原創聲明。伺服器回覆由 main._notice 寫進頁底（modal_feedback）。
##  原因：規則的 step_block 優先；規則允許但人站得太遠時寫出要站到哪裡（AWAY）。
##  不能按的按鈕仍可取得焦點（tooltip＝原因）。結構只建一次，refresh() 依快照原地更新。
##
## 純函式：region_of / person_of / near / away_text / action_reason / action_caption / count_text /
##  chip_text。
const Gold=preload("res://scripts/gold_panning.gd")
const Art=preload("res://scripts/gold_panning_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

const LAYOUT:="gold_panning"
const POINT:="gold_pan"
const PAGE_TITLE:=Gold.TITLE
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const AWAY:="請站到山城西側水邊的淘砂處旁（%d,%d）再淘砂。"
const KEY_HINT:="Enter 確認・Esc 回到島上"
const COUNT_TEXT:="今天 %d／%d 盤・累計 %d 盤"
const CAPTIONS:=["舀一盤河砂","揀掉石礫","搖盤（還要 %d 次）","揀起金砂"]
const BAG_TEXT:="背包：含金礦料 %d"

# ------------------------------------------------------------ pure helpers --

static func region_of(s:Dictionary) -> String:
	return str(s.get("region_id","home"))

static func person_of(s:Dictionary,own_id:String) -> Dictionary:
	var people:Variant=s.get("players",{})
	if people is Dictionary and people.get(own_id) is Dictionary:return people[own_id]
	return {}

## Standing within REACH of the panning site in 金瓜石 (the rule's TOO_FAR check).
static func near(s:Dictionary,person:Dictionary) -> bool:
	if person.is_empty() or region_of(s)!=Gold.REGION:return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(Gold.SITE)+Vector2(0.5,0.5))<=Gold.REACH

static func away_text() -> String:
	return AWAY%[Gold.SITE.x,Gold.SITE.y]

## Why the action cannot be done ("" = it can): the rules first, then where to stand.
static func action_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=Gold.step_block(s,Gold.next_step(s),person.get("inventory"))
	if not block.is_empty():return block
	return "" if near(s,person) else away_text()

static func action_caption(stage:int) -> String:
	var at:=clampi(stage,0,Gold.STEPS.size()-1)
	match at:
		0:return str(CAPTIONS[0])
		1:return str(CAPTIONS[1])
		5:return str(CAPTIONS[3])
	return str(CAPTIONS[2])%Gold.swirls_left(at)

static func count_text(s:Dictionary) -> String:
	return COUNT_TEXT%[Gold.count_today(s),Gold.DAILY,Gold.total(s)]

static func _done(stage:int,step:String) -> bool:
	match step:
		"scoop":return stage>=1
		"sift":return stage>=2
		"swirl":return stage==5
	return false

static func _current(stage:int,step:String) -> bool:
	return str(Gold.STEPS[clampi(stage,0,Gold.STEPS.size()-1)])==step

## One step chip: "✓ 名稱" done, "▶ 名稱" current (swirl: "▶ 搖盤 n／3"), "○ 名稱" pending.
static func chip_text(stage:int,step:String) -> String:
	var at:=clampi(stage,0,Gold.STEPS.size()-1)
	var title:=str(Gold.STEP_NAMES.get(step,step))
	if _current(at,step):
		if step=="swirl":return "▶ %s %d／3"%[title,at-1]
		return "▶ "+title
	if _done(at,step):return "✓ "+title
	return "○ "+title

static func _chip_color(stage:int,step:String) -> Color:
	var at:=clampi(stage,0,Gold.STEPS.size()-1)
	if _current(at,step):return GOOD
	if _done(at,step):return MUTED
	return INK

static func _person(app) -> Dictionary:
	return person_of(app.session.snapshot,str(app.session.own_id))

static func _ore(person:Dictionary) -> int:
	var inv:Variant=person.get("inventory")
	if inv is Dictionary:return int((inv as Dictionary).get(Gold.ITEM,0))
	return 0

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("gp_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

static func open(app) -> void:
	var s:Dictionary=app.session.snapshot
	if region_of(s)!=Gold.REGION:return
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	_style(app)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	app.modal.name="GoldPanningPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("gp_body",body)
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
	# Today's and total pans.
	var head:=_paper(body,"GpHeader",1)
	_text(app,head,"GpCount",16)
	# The pan: picture, what is in it, and the four steps.
	var card:=_paper(body,"GpPanCard",4)
	var row:=HBoxContainer.new()
	row.name="GpPanRow"
	row.add_theme_constant_override("separation",12)
	card.add_child(row)
	var pan:=TextureRect.new()
	pan.name="GpPan"
	pan.texture=Art.pan_texture(0)
	pan.custom_minimum_size=Vector2(128,128)
	pan.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	pan.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pan.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	pan.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	pan.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(pan)
	var col:=VBoxContainer.new()
	col.name="GpPanInfo"
	col.add_theme_constant_override("separation",8)
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	col.alignment=BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_wrapped(app,col,"GpStage",15)
	var steps:=HBoxContainer.new()
	steps.name="GpSteps"
	steps.add_theme_constant_override("separation",10)
	col.add_child(steps)
	for step:String in Gold.STEP_IDS:
		_text(app,steps,"GpStep_"+step,13)
	var action:=_button(app,col,"GpAction",str(CAPTIONS[0]),func():_send(app))
	action.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_wrapped(app,col,"GpReason",13,WARN)
	_text(app,col,"GpBag",13)
	_wrapped(app,body,"GpBlurb",13,MUTED).text=Gold.BLURB
	_wrapped(app,body,"GpDisclaimer",13,MUTED).text=Gold.DISCLAIMER

# ------------------------------------------------------------------ actions --

static func _send(app) -> void:
	if not is_open(app):return
	app.session.perform(Gold.ACTION,Gold.SITE,Gold.next_step(app.session.snapshot))
	refresh(app,true)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("gp_body") as Node).find_child(id,true,false) as Control

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
	var now:Dictionary=Gold.view(s)
	var close_by:=near(s,person)
	var reason:=action_reason(s,person)
	var ore:=_ore(person)
	var signature:=JSON.stringify([now,close_by,reason,region_of(s),
		snappedf(float(person.get("x",0.0)),0.1),snappedf(float(person.get("y",0.0)),0.1),ore])
	if not force and str(app.modal.get_meta("gp_signature",""))==signature:return
	app.modal.set_meta("gp_signature",signature)
	var focus_before:=_focus_owner(app)
	var stage:=int(now.get("stage",0))
	_put(app,"GpCount",count_text(s))
	var pan:=_node(app,"GpPan") as TextureRect
	if pan!=null:pan.texture=Art.pan_texture(stage)
	_put(app,"GpStage",Gold.stage_text(stage))
	for step:String in Gold.STEP_IDS:
		_put(app,"GpStep_"+step,chip_text(stage,step),_chip_color(stage,step))
	var action:=_node(app,"GpAction") as Button
	if action!=null:
		action.text=action_caption(stage)
		action.disabled=not reason.is_empty()
		action.tooltip_text=reason if not reason.is_empty() else Gold.BLURB
		action.focus_mode=Control.FOCUS_ALL
	_put(app,"GpReason",reason,WARN)
	_put(app,"GpBag",BAG_TEXT%ore)
	link_focus(app)
	_restore_focus(app,focus_before)
	app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("gp_body") if app.modal.has_meta("gp_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("gp_body"):break
		node=node.get_parent()
	return true

## The single action button: ↑ / ↓ / Tab go to 關閉 and back.
static func link_focus(app) -> void:
	var b:=_node(app,"GpAction") as Button
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
	var b:=_node(app,"GpAction") as Button
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
