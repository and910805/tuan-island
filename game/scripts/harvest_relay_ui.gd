extends RefCounted
## T071 「豐收接力」 client: panel, world prompts, HUD tracker text and the art
## helpers shared with world_view.gd. Rules live in harvest_relay.gd; this file only
## reads snapshot.own_harvest (personal view) and snapshot.harvest_relay (public,
## participants keyed by the same public id as snapshot.players). Every change goes
## through Session.perform(harvest_start / harvest_join / harvest_leave /
## harvest_pick / harvest_pass / harvest_sort); the panel re-renders from the next
## snapshot without closing. Server replies reach app.modal_feedback / the toast via
## app._notice, exactly like the market stall panel.
##
## Art (no new PNGs): sign = assets/ui-life/furniture.png "sign"; crate =
## assets/mine/freight.png frame 2 (wooden crate) with item icons on top; baskets =
## assets/bobo/tray.png with its felt recoloured per basket at runtime; vegetables =
## assets/ui-inventory/items.png icons (cabbage / cucumber / eggplant are runtime
## recolours of lettuce / carrot / tomato because they have no icon of their own).
const World=preload("res://scripts/world.gd")
const Relay=preload("res://scripts/harvest_relay.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const TRAY_PATH:="res://assets/bobo/tray.png"
const TITLE:="豐收接力"
const RULE:="1～8 人、3 分鐘：到模型菜箱拿蔬菜，傳給夥伴或自己送去，放進對的分類籃，一起完成 24 個。"
const BAG_NOTE:="模型蔬菜只在活動裡使用，不會放進背包；背包與鈴幣完全不變。中途離開時背包維持原樣，這一輪結算時仍會拿到一次參加紀念票。"
## T071: line beside 「我的紀錄」 on the three activity pages (see souvenir_note()).
const SOUVENIR_NOTE:="紀念票可到廣場北邊的紀念品交換攤換裝飾"
const SITES:=["sign","crate","root","leaf","fruit"]
## Representative vegetable drawn in each basket and in the panel legend.
const BASKET_ICON:={"root":"radish","leaf":"lettuce","fruit":"tomato"}
## Felt colour of each recoloured tray (hue, saturation, value boost) and the
## matching name-plaque colour drawn on the basket.
const BASKET_TINT:={"root":[0.075,0.7,2.1],"leaf":[0.29,0.6,2.0],"fruit":[0.985,0.7,2.1]}
const BASKET_COLOUR:={"root":Color("a77a2a"),"leaf":Color("4f8a36"),"fruit":Color("c23a3a")}
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const ROW_HEIGHT:=26
static var art_cache:Dictionary={}

# ------------------------------------------------------------------ state --

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_harvest",{})
	return found if found is Dictionary else {}

static func public_relay(s:Dictionary)->Dictionary:
	var found:Variant=s.get("harvest_relay",{})
	return found if found is Dictionary else {}

static func at_home(s:Dictionary)->bool:
	return str(s.get("region_id","home"))=="home"

## Props are drawn and interactable only at home once unlocked and the five cells are free.
static func on_field(s:Dictionary)->bool:
	return at_home(s) and Relay.available(s)

## The HUD tracker follows the round only while I am joined in it at home.
static func tracking(s:Dictionary)->bool:
	var h:=own(s)
	return at_home(s) and bool(h.get("active",false)) and bool(h.get("joined",false))

static func site_cell(site:String)->Vector2i:
	if site=="sign":return Relay.SIGN
	if site=="crate":return Relay.CRATE
	return Relay.BASKETS.get(site,Relay.NO_CELL)

static func site_at(p:Vector2i)->String:
	for site:String in SITES:
		if site_cell(site)==p:return site
	return ""

static func position_of(s:Dictionary,id:String)->Variant:
	var person:Variant=s.get("players",{}).get(id)
	if not person is Dictionary:return null
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))

static func own_cell(s:Dictionary,id:String)->Vector2i:
	var at:Variant=position_of(s,id)
	return Vector2i((at as Vector2).floor()) if at is Vector2 else Relay.SIGN

static func near_sign(s:Dictionary,id:String)->bool:
	var at:Variant=position_of(s,id)
	return at_home(s) and at is Vector2 and (at as Vector2).distance_to(Vector2(Relay.SIGN)+Vector2(0.5,0.5))<=Relay.SIGN_REACH

## Client-side preview of the server's pass target: another joined, empty-handed
## participant from the public snapshot standing within PASS_REACH.
static func pass_ready(s:Dictionary,id:String)->bool:
	var h:=own(s)
	if not bool(h.get("active",false)) or not bool(h.get("joined",false)) or str(h.get("carry","")).is_empty():return false
	var here:Variant=position_of(s,id)
	if not here is Vector2:return false
	var people:Variant=public_relay(s).get("participants",{})
	if not people is Dictionary:return false
	for other in people:
		if str(other)==id:continue
		var entry:Variant=people[other]
		if not entry is Dictionary or entry.get("joined")!=true or not str(entry.get("carry","")).is_empty():continue
		var there:Variant=position_of(s,str(other))
		if there is Vector2 and (here as Vector2).distance_to(there)<=Relay.PASS_REACH:return true
	return false

## Model vegetable a visible player carries in the active round ("" when none).
static func carried(s:Dictionary,id:String)->String:
	var relay:=public_relay(s)
	if not bool(relay.get("active",false)):return ""
	var entry:Variant=relay.get("participants",{}).get(id) if relay.get("participants",{}) is Dictionary else null
	if not entry is Dictionary or entry.get("joined")!=true:return ""
	var kind:=str(entry.get("carry",""))
	return kind if Relay.KINDS.has(kind) else ""

static func basket_label(basket:String)->String:
	return str(Relay.BASKET_NAMES.get(basket,""))+"籃"

## World label for a site. Focused titles say what the interact key will do.
static func site_title(s:Dictionary,id:String,site:String,focused:bool)->String:
	var h:=own(s)
	var active:=bool(h.get("active",false))
	var playing:=active and bool(h.get("joined",false))
	var carry:=str(h.get("carry",""))
	if site=="sign":
		if focused:return "豐收接力・打開活動"
		return "豐收接力 %d／%d"%[int(h.get("delivered",0)),Relay.GOAL] if active else "豐收接力"
	if site=="crate":
		if not focused:return "模型菜箱"
		if not playing:return "模型菜箱・查看活動"
		if carry.is_empty():return "模型菜箱・拿一個蔬菜"
		return "傳給身旁的夥伴" if pass_ready(s,id) else "模型菜箱・手上已有蔬菜"
	var name:=basket_label(site)
	if not focused:return name
	if not playing:return name+"・查看活動"
	if carry.is_empty():return name+"・先到菜箱拿蔬菜"
	var right:=Relay.basket_of(carry)
	if right==site:return name+"・放入"+Relay.kind_name(carry)
	return "%s・%s要放%s"%[name,Relay.kind_name(carry).trim_prefix("模型"),basket_label(right)]

## main._interact: the natural action for the focused site.
static func interact(app,site:String)->void:
	var s:Dictionary=app.session.snapshot
	var h:=own(s)
	if site=="sign" or not (bool(h.get("active",false)) and bool(h.get("joined",false))):
		open(app)
		return
	if site=="crate":
		# Empty hands pick; full hands pass when a teammate is close, otherwise the
		# server explains (HANDS_FULL) — the backpack is never involved.
		var full:=not str(h.get("carry","")).is_empty()
		app.session.perform("harvest_pass" if full and pass_ready(s,app.session.own_id) else "harvest_pick",Relay.CRATE,"")
		return
	app.session.perform("harvest_sort",site_cell(site),"")

static func pass_now(app)->void:
	var s:Dictionary=app.session.snapshot
	app.session.perform("harvest_pass",own_cell(s,app.session.own_id),"")

# -------------------------------------------------------------------- art --

static func recolour(base:Texture2D,keep:Callable,hue:float,sat:float,boost:float)->Texture2D:
	var image:Image=base.get_image() if base!=null else null
	if image==null or image.is_empty():return base
	if image.is_compressed() and image.decompress()!=OK:return base
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			if c.a<=0.0 or not keep.call(c):continue
			image.set_pixel(x,y,Color.from_hsv(hue,clampf(maxf(c.s,sat),0.0,1.0),clampf(c.v*boost,0.0,1.0),c.a))
	return ImageTexture.create_from_image(image)

## Icon of a model vegetable kind (KINDS[kind].icon).
static func veg_icon(kind:String)->Texture2D:
	var icon_id:=str(Relay.KINDS.get(kind,{}).get("icon",kind))
	if art_cache.has("veg:"+icon_id):return art_cache["veg:"+icon_id]
	var result:Texture2D
	match icon_id:
		"cabbage":result=recolour(Items.icon("lettuce"),func(c:Color):return c.g>c.r and c.g>=c.b,0.24,0.32,1.18)
		"cucumber":result=recolour(Items.icon("carrot"),func(c:Color):return c.r>c.g+0.08 and c.r>c.b,0.31,0.62,0.78)
		"eggplant":result=recolour(Items.icon("tomato"),func(c:Color):return c.r>c.g+0.12 and c.r>c.b,0.79,0.55,0.78)
		_:result=Items.icon(icon_id)
	art_cache["veg:"+icon_id]=result
	return result

static func basket_icon(basket:String)->Texture2D:
	return Items.icon(str(BASKET_ICON.get(basket,"radish")))

## bobo/tray.png (64×48, felt inset) with the felt recoloured for this basket.
static func basket_texture(basket:String)->Texture2D:
	if art_cache.has("tray:"+basket):return art_cache["tray:"+basket]
	var base:Texture2D=load(TRAY_PATH) as Texture2D if ResourceLoader.exists(TRAY_PATH) else null
	var tint:Array=BASKET_TINT.get(basket,BASKET_TINT.root)
	var result:=recolour(base,func(c:Color):return c.g>c.r+0.02 and c.g>=c.b-0.02,float(tint[0]),float(tint[1]),float(tint[2])) if base!=null else null
	art_cache["tray:"+basket]=result
	return result

# ------------------------------------------------------------------ HUD --

## main._refresh_hud (after every other objective writer): while I am joined in an
## active round the tracker follows 豐收接力 (it takes priority over 風鈴接力 and the
## tea guidance because it is timed and my hands are busy).
static func refresh_hud(app,s:Dictionary)->void:
	var on:=tracking(s)
	var h:=own(s)
	var carry:=str(h.get("carry",""))
	var pass_button:=app.hud.find_child("TrackerHarvestPass",true,false) as Button if is_instance_valid(app.hud) else null
	if pass_button and pass_button.visible!=(on and not carry.is_empty()):
		pass_button.visible=on and not carry.is_empty()
		if is_instance_valid(app.preview_tracker):app.preview_tracker.size.y=0
	if not on:return
	var lines:=PackedStringArray()
	lines.append(hud_line(h))
	if carry.is_empty():lines.append("手上空著 → 到模型菜箱拿一個")
	else:lines.append("手上：%s → %s"%[str(h.get("carry_name","")),basket_label(str(h.get("carry_basket","")))])
	lines.append("靠近菜箱、分類籃按 %s"%app.binding_label("interact"))
	app.objective.text="\n".join(lines)
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	if heading:heading.text="豐收接力  ▾"
	var next:=app.hud.find_child("TrackerNext",true,false) as Button
	if next:next.text="查看豐收接力  →"

static func hud_line(h:Dictionary)->String:
	return "豐收接力 %d / %d · 剩 %d 秒"%[int(h.get("delivered",0)),int(h.get("goal",Relay.GOAL)),whole_seconds(h.get("seconds_left",0.0))]

## Whole seconds shown to players; tolerant of float noise (180.0000001 -> 180).
static func whole_seconds(value:Variant)->int:
	return maxi(0,ceili(float(value)-0.001))

# ---------------------------------------------------------------- panel --

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="HarvestRelayPanel"
	app.modal.set_meta("life_modal_layout","harvest_relay")
	app.modal.set_meta("harvest_body",body)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上 · 模型蔬菜不會進背包"
	body.add_theme_constant_override("separation",8)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: wide like the market panel, as tall as its content.
static func layout(app,bounds:Vector2)->void:
	var cap:=Vector2(minf(1000,bounds.x-24),minf(620,bounds.y-20))
	var modal:Control=app.modal
	modal.size.x=cap.x
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	var height:=cap.y
	if outer!=null and content!=null:
		var shell:=outer.get_parent() as VBoxContainer
		if shell!=null and shell.get_theme_constant("separation")!=3:
			shell.add_theme_constant_override("separation",3)
			var footer_divider:=shell.get_node_or_null("ModalFooterDivider") as HSeparator
			if footer_divider!=null:footer_divider.hide()
			if is_instance_valid(app.modal_feedback):app.modal_feedback.custom_minimum_size.y=0
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap.y,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(cap.x,height)
	modal.position=((bounds-modal.size)/2).floor()

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("harvest_body")

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("harvest_body")
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode!=Control.FOCUS_NONE:
			b.grab_focus()
			return
	var close:=close_button(app)
	if close!=null:close.grab_focus()

## The 「關閉  Esc」 button of the modal heading (outside the body).
static func close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("harvest_body") if app.modal.has_meta("harvest_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func text(app,parent:Node,value:String,size:int=15,color:Color=INK)->Label:
	var l:Label=Shell.text(app,value,size)
	l.size_flags_horizontal=Control.SIZE_FILL
	l.add_theme_color_override("font_color",color)
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

static func wrapped(app,parent:Node,value:String,size:int=14,color:Color=INK)->Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func action(app,parent:Node,id:String,title:String,callback:Callable,enabled:bool,reason:String="")->Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.disabled=not enabled
	b.custom_minimum_size=Vector2(0,36)
	b.add_theme_font_size_override("font_size",15)
	# Disabled buttons keep their tooltip but leave keyboard/gamepad navigation.
	b.focus_mode=Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled and not reason.is_empty():b.tooltip_text=reason
	parent.add_child(b)
	return b

static func paper(parent:Node,id:String)->VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",3)
	card.add_child(inner)
	return inner

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var id:String=app.session.own_id
	var h:=own(s)
	var body:VBoxContainer=app.modal.get_meta("harvest_body")
	# seconds_left changes every tick: update it in place instead of rebuilding.
	var signature:=JSON.stringify([h.duplicate(true).merged({"seconds_left":0},true),at_home(s),on_field(s),near_sign(s,id),pass_ready(s,id),whole_seconds(h.get("cooldown",0.0))])
	if str(app.modal.get_meta("harvest_signature",""))==signature:
		var time_label:=body.find_child("HarvestTime",true,false) as Label
		if time_label:time_label.text=time_text(h)
		return
	app.modal.set_meta("harvest_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(h.get("unlocked",false)):
		var lock:=wrapped(app,body,Relay.LOCKED,17)
		lock.name="HarvestLocked"
		wrapped(app,body,RULE,14,MUTED).name="HarvestRule"
		app._layout_preview.call_deferred()
		return
	build(app,body,s,id,h)
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func time_text(h:Dictionary)->String:
	if bool(h.get("active",false)):return "剩 %d 秒"%whole_seconds(h.get("seconds_left",0.0))
	var wait:=whole_seconds(h.get("cooldown",0.0))
	return "補貨中・約 %d 秒"%wait if wait>0 else "可以開始"

static func build(app,body:VBoxContainer,s:Dictionary,id:String,h:Dictionary)->void:
	var active:=bool(h.get("active",false))
	var joined:=bool(h.get("joined",false))
	var carry:=str(h.get("carry",""))
	# 1. Header: round, progress, time.
	var header:=HBoxContainer.new();header.name="HarvestHeader";header.add_theme_constant_override("separation",16);body.add_child(header)
	header.add_child(Shell.picture(veg_icon("radish"),32))
	text(app,header,"第 %d 輪進行中"%int(h.get("round",0)) if active else "目前沒有進行中的一輪",17).name="HarvestStatus"
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(spacer)
	text(app,header,"完成 %d / %d · 接力 %d"%[int(h.get("delivered",0)),Relay.GOAL,int(h.get("relays",0))],16).name="HarvestProgress"
	text(app,header,time_text(h),16,WARN if active else MUTED).name="HarvestTime"
	wrapped(app,body,RULE,14,MUTED).name="HarvestRule"
	# 2. My hands + baskets (left), participants (right).
	var columns:=HBoxContainer.new();columns.name="HarvestColumns";columns.add_theme_constant_override("separation",12);body.add_child(columns)
	var left:=paper(columns,"HarvestHandsCard")
	text(app,left,"我的雙手",17)
	var hands:=HBoxContainer.new();hands.add_theme_constant_override("separation",8);left.add_child(hands)
	hands.add_child(Shell.picture(veg_icon(carry) if not carry.is_empty() else null,32))
	var carry_text:="還沒有加入這一輪"
	if joined and carry.is_empty():carry_text="空手 → 到模型菜箱拿一個"
	elif joined:carry_text="%s → 放進「%s」籃"%[str(h.get("carry_name","")),str(h.get("carry_basket_name",""))]
	text(app,hands,carry_text,16,INK if joined else MUTED).name="HarvestCarry"
	for basket:String in Relay.BASKET_ORDER:
		var row:=HBoxContainer.new();row.name="HarvestBasket_"+basket;row.add_theme_constant_override("separation",6);left.add_child(row)
		row.add_child(Shell.picture(basket_icon(basket),24))
		var kinds:=PackedStringArray()
		for kind:String in Relay.ORDER:
			if Relay.basket_of(kind)==basket and not kinds.has(Relay.kind_name(kind).trim_prefix("模型")):kinds.append(Relay.kind_name(kind).trim_prefix("模型"))
		text(app,row,"%s：%s"%[basket_label(basket),"、".join(kinds)],14)
	var note:=wrapped(app,left,BAG_NOTE,13,GOOD)
	note.name="HarvestBagNote"
	var right:=paper(columns,"HarvestPeopleCard")
	var people_head:=HBoxContainer.new();right.add_child(people_head)
	var people_title:=text(app,people_head,"參加者",17);people_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text(app,people_head,"%d／%d 人在場"%[int(h.get("joined_count",0)),int(h.get("max_players",Relay.MAX_PLAYERS))],14).name="HarvestPeopleCount"
	var rows:=VBoxContainer.new();rows.name="HarvestPeople";rows.add_theme_constant_override("separation",2);right.add_child(rows)
	var list:Array=(h.get("participants",[]) as Array).duplicate() if h.get("participants",[]) is Array else []
	# Me first, then the others who are in (server order is stable), then those who
	# left; at most 8 rows.
	var ordered:Array=list.filter(func(e):return bool(e.get("me",false)))+list.filter(func(e):return bool(e.get("joined",false)) and not bool(e.get("me",false)))+list.filter(func(e):return not bool(e.get("joined",false)) and not bool(e.get("me",false)))
	if ordered.is_empty():text(app,rows,"還沒有人參加。" if not active else "還沒有人加入這一輪。",14,MUTED).name="HarvestPeopleEmpty"
	for index in mini(ordered.size(),Relay.MAX_PLAYERS):
		var entry:Dictionary=ordered[index]
		var row:=HBoxContainer.new();row.name="HarvestPerson_%d"%index;row.add_theme_constant_override("separation",6)
		row.custom_minimum_size.y=ROW_HEIGHT;rows.add_child(row)
		var kind:=str(entry.get("carry",""))
		row.add_child(Shell.picture(veg_icon(kind) if not kind.is_empty() else null,24))
		var who:=text(app,row,str(entry.get("name","島民"))+("（我）" if bool(entry.get("me",false)) else ""),15)
		who.custom_minimum_size.x=120
		var state:="已離開"
		if bool(entry.get("joined",false)):state="手上：%s"%str(entry.get("carry_name","")) if not kind.is_empty() else "空手"
		if not active:state="本輪結束"
		var detail:=text(app,row,"%s · 分類 %d · 傳遞 %d"%[state,int(entry.get("sorted",0)),int(entry.get("passed",0))],14,INK if bool(entry.get("joined",false)) or not active else MUTED)
		detail.name="HarvestPersonDetail_%d"%index
	if ordered.size()>Relay.MAX_PLAYERS:
		text(app,rows,"另有 %d 位曾參加這一輪。"%(ordered.size()-Relay.MAX_PLAYERS),13,MUTED).name="HarvestPeopleMore"
	# 3. Actions + the one reason line.
	var reasons:=action_reasons(s,id,h)
	var bar:=HBoxContainer.new();bar.name="HarvestActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var round_id:=str(int(h.get("round",0)))
	var buttons:Array[Button]=[]
	buttons.append(action(app,bar,"HarvestStart","開始一場",func():app.session.perform("harvest_start",Relay.SIGN,round_id),reasons.start.is_empty(),reasons.start))
	buttons.append(action(app,bar,"HarvestJoin","加入",func():app.session.perform("harvest_join",Relay.SIGN,round_id),reasons.join.is_empty(),reasons.join))
	buttons.append(action(app,bar,"HarvestLeave","離開活動",func():app.session.perform("harvest_leave",own_cell(app.session.snapshot,app.session.own_id),""),reasons.leave.is_empty(),reasons.leave))
	buttons.append(action(app,bar,"HarvestPass","傳給身旁的夥伴",func():pass_now(app),reasons.pass.is_empty(),reasons.pass))
	for b in buttons:b.custom_minimum_size.x=128
	var hint:=wrapped(app,body,hint_text(app,s,id,h,reasons),14,WARN if not reasons.hint_ok else GOOD)
	hint.name="HarvestHint"
	link_focus(app,buttons)
	# 4. Last round + my record.
	var bottom:=HBoxContainer.new();bottom.name="HarvestBottom";bottom.add_theme_constant_override("separation",12);body.add_child(bottom)
	var last_box:=paper(bottom,"HarvestLastCard")
	var last:Dictionary=h.get("last",{}) if h.get("last",{}) is Dictionary else {}
	text(app,last_box,"上一輪成果",15)
	if last.is_empty():
		text(app,last_box,"還沒有完成的一輪",14,MUTED).name="HarvestLast"
	else:
		var why:="全部分類完成" if str(last.get("reason",""))=="goal" else "時間到"
		text(app,last_box,"第 %d 輪 · %s · 完成 %d / %d · 接力 %d"%[int(last.get("round",0)),why,int(last.get("delivered",0)),Relay.GOAL,int(last.get("relays",0))],14).name="HarvestLast"
		text(app,last_box,"%d 人參加 · 每人 %d 張紀念票"%[int(last.get("players",0)),int(last.get("tickets",0))],14).name="HarvestLastTickets"
	var record_box:=paper(bottom,"HarvestRecordCard")
	souvenir_note(app,record_box,"Harvest")
	text(app,record_box,"紀念票 %d 張 · 參加 %d 場 · 最佳完成 %d 個"%[int(h.get("tickets",0)),int(h.get("rounds",0)),int(h.get("best",0))],14).name="HarvestRecord"
	text(app,record_box,"每輪 1 張，每完成 8 個多 1 張（最多 4 張）",13,MUTED).name="HarvestTicketRule"

## 「我的紀錄」 heading of the record card with the T071 紀念品交換攤 note on the same
## line (shared by the three activity pages; no extra card height). <prefix>SouvenirNote.
static func souvenir_note(app,record_box:Node,prefix:String)->Label:
	var head:=HBoxContainer.new();head.name=prefix+"RecordHead";head.add_theme_constant_override("separation",10);record_box.add_child(head)
	text(app,head,"我的紀錄",15)
	var note:=text(app,head,SOUVENIR_NOTE,13,GOOD)
	note.name=prefix+"SouvenirNote"
	return note

## Why each button is disabled ("" = enabled) plus whether the hint is good news.
static func action_reasons(s:Dictionary,id:String,h:Dictionary)->Dictionary:
	var active:=bool(h.get("active",false))
	var joined:=bool(h.get("joined",false))
	var carry:=str(h.get("carry",""))
	var near:=near_sign(s,id)
	var out:={"start":"","join":"","leave":"","pass":"","hint_ok":false}
	var wait:=whole_seconds(h.get("cooldown",0.0))
	var field:=""
	if not at_home(s):field=Relay.WRONG_REGION
	elif not bool(h.get("available",false)):field=Relay.UNAVAILABLE
	if not field.is_empty():out.start=field
	elif active:out.start="這一輪正在進行，按「加入」就能一起玩。"
	elif wait>0:out.start=Relay.COOLDOWN_MSG%wait
	elif not near:out.start="請走到廣場西側的豐收接力告示牌前（3 格內）再開始。"
	if not field.is_empty():out.join=field
	elif not active:out.join="目前沒有進行中的一輪。"
	elif joined:out.join=Relay.ALREADY_JOINED
	elif int(h.get("joined_count",0))>=int(h.get("max_players",Relay.MAX_PLAYERS)):out.join=Relay.FULL%Relay.MAX_PLAYERS
	elif not near:out.join="請走到廣場西側的豐收接力告示牌前（3 格內）再加入。"
	if not active or not joined:out.leave="還沒有加入這一輪。"
	if not active or not joined:out.pass="先加入這一輪。"
	elif carry.is_empty():out.pass="手上沒有模型蔬菜。"
	elif not pass_ready(s,id):out.pass="身旁 %.1f 格內沒有空手的夥伴。"%Relay.PASS_REACH
	return out

static func hint_text(app,s:Dictionary,id:String,h:Dictionary,reasons:Dictionary)->String:
	var key:String=app.binding_label("interact")
	var active:=bool(h.get("active",false))
	var joined:=bool(h.get("joined",false))
	var carry:=str(h.get("carry",""))
	if not active:
		if reasons.start.is_empty():
			reasons.hint_ok=true
			return "可以開始：按「開始一場」，其他人在告示牌前按「加入」。"
		return str(reasons.start)
	if not joined:
		if reasons.join.is_empty():
			reasons.hint_ok=true
			return "按「加入」一起玩；中途也能加入或離開。"
		return str(reasons.join)
	reasons.hint_ok=true
	if carry.is_empty():return "到模型菜箱旁按 %s 拿一個蔬菜。"%key
	if reasons.pass.is_empty():return "把%s送到「%s」籃按 %s，或按「傳給身旁的夥伴」。"%[str(h.get("carry_name","")),str(h.get("carry_basket_name","")),key]
	return "把%s送到「%s」籃按 %s；靠近空手的夥伴就能傳給他。"%[str(h.get("carry_name","")),str(h.get("carry_basket_name","")),key]

## Explicit keyboard/gamepad neighbours: left/right walk the enabled action buttons
## (wrapping), up goes to 「關閉」, and 「關閉」 down returns to the first action.
static func link_focus(app,buttons:Array[Button])->void:
	var enabled:Array[Button]=[]
	for b in buttons:
		if not b.disabled:enabled.append(b)
	var close:=close_button(app)
	for i in enabled.size():
		var b:=enabled[i]
		var left:=enabled[(i-1+enabled.size())%enabled.size()]
		var right:=enabled[(i+1)%enabled.size()]
		b.focus_neighbor_left=b.get_path_to(left)
		b.focus_neighbor_right=b.get_path_to(right)
		b.focus_next=b.get_path_to(right)
		b.focus_previous=b.get_path_to(left)
		b.focus_neighbor_bottom=b.get_path_to(b)
		if close!=null:b.focus_neighbor_top=b.get_path_to(close)
	if close!=null and not enabled.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(enabled[0])
		close.focus_next=close.get_path_to(enabled[0])
