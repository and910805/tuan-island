extends RefCounted
## 灶台接力 client: the notice board panel (open(app)) and the three station panels
## (open(app,"prep"|"assembly"|"serve")). Rules live in cooking_relay.gd; this file only
## reads snapshot.cooking_relay (public) and snapshot.own_cooking_relay (personal) and
## sends every action through session.perform(ACTION, cell, payload):
##   board   : "crew" | "practice" | "join:<round>" | "begin:<round>" | "leave:<round>"
##   prep    : "prep:<round>:<item>"
##   assembly: "plate:<round>" | "undo:<round>"
##   serve   : "serve:<round>"
## The cell is Relay.SIGN for the board and Relay.STATIONS[station] for a station.
## Visually every panel is one warm recipe card: the dish, the exact ingredients it needs
## next to the two live tray slots, the three progressive steps and the score.
const Relay=preload("res://scripts/cooking_relay.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const LAYOUT:="cooking_relay"
const ACTION:="cooking_relay"
const TITLE:="料理接力"
const INGREDIENT_ICONS:={"root":"radish","green":"lettuce","fruit":"strawberry","grain":"wheat"}
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const CARD_BG:=Color("fff3d6")
const CARD_EDGE:=Color("c98a4b")
const SLOT_BG:=Color("fffaf0")
const SPECTATOR_TIMER:=10.0
const STATION_NAMES:={"prep":"備料檯","assembly":"裝盤檯","serve":"出餐口"}
const STEP_ORDER:=["prep","assembly","serve"]
const STEP_TITLES:={"prep":"1 備料","assembly":"2 裝盤","serve":"3 出餐"}

# ------------------------------------------------------------------ state --

static func public_relay(s:Dictionary)->Dictionary:
	var found:Variant=s.get("cooking_relay",{})
	return found if found is Dictionary else {}

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_cooking_relay",{})
	return found if found is Dictionary else {}

static func phase_of(p:Dictionary)->String:
	var phase:=str(p.get("phase","idle"))
	return phase if phase in ["idle","lobby","run","results"] else "idle"

static func round_id(p:Dictionary)->String:
	return str(int(p.get("round",0)))

static func item_label(id:String)->String:
	var v:Variant=Relay.ITEMS.get(id,id)
	if v is Dictionary:return str(v.get("label",v.get("name",id)))
	return str(v)

static func recipe_of(p:Dictionary)->Dictionary:
	var r:Variant=Relay.RECIPES.get(str(p.get("dish","")),{})
	return r if r is Dictionary else {}

static func need_items(p:Dictionary)->Array:
	var items:Variant=recipe_of(p).get("items",[])
	return items if items is Array else []

static func tray_items(p:Dictionary)->Array:
	var t:Variant=p.get("tray",[])
	return t.duplicate() if t is Array else []

static func tray_matches(p:Dictionary)->bool:
	var need:=need_items(p)
	var tray:=tray_items(p)
	if need.is_empty() or tray.size()!=need.size():return false
	var sorted_need:=need.duplicate()
	sorted_need.sort()
	tray.sort()
	return sorted_need==tray

static func whole_seconds(value:Variant)->int:
	return HarvestUI.whole_seconds(value)

## Current step of the dish: prep -> assembly -> serve (empty when nothing is cooking).
static func step_of(p:Dictionary)->String:
	if phase_of(p)!="run":return ""
	if bool(p.get("plated",false)):return "serve"
	if tray_matches(p):return "assembly"
	return "prep"

static func can_see_timer(p:Dictionary,_m:Dictionary)->bool:
	if phase_of(p)!="run":return false
	return float(p.get("remaining",0.0))<=SPECTATOR_TIMER

static func time_text(p:Dictionary,m:Dictionary)->String:
	if not can_see_timer(p,m):return ""
	return "剩 %d 秒"%whole_seconds(p.get("remaining",0.0))

static func is_spectating(p:Dictionary,m:Dictionary)->bool:
	return phase_of(p)=="run" and not bool(m.get("joined",false))

# ---------------------------------------------------------------- panel --

## station "" opens the sign board, otherwise one of prep / assembly / serve.
static func open(app,station:String="")->void:
	var body:VBoxContainer=app._open_modal(TITLE if station.is_empty() else "%s・%s"%[TITLE,STATION_NAMES.get(station,station)])
	app.modal.name="CookingRelayPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("cookrelay_body",body)
	app.modal.set_meta("cookrelay_station",station if STATION_NAMES.has(station) else "")
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	body.add_theme_constant_override("separation",8)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

static func layout(app,bounds:Vector2)->void:
	var modal:Control=app.modal
	modal.size.x=minf(760.0,bounds.x-32.0)
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var body:=modal.find_child("ModalContent",true,false) as Control
	var height:=420.0
	if outer and body:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=chrome+body.get_combined_minimum_size().y+2.0
	modal.size.y=minf(height,bounds.y-24.0)
	modal.position=((bounds-modal.size)/2.0).floor()

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("cookrelay_body")

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("cookrelay_body")
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode!=Control.FOCUS_NONE:
			b.grab_focus()
			return
	var close:=close_button(app)
	if close!=null:close.grab_focus()

static func close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("cookrelay_body") if app.modal.has_meta("cookrelay_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var p:=public_relay(s)
	var m:=own(s)
	var station:String=str(app.modal.get_meta("cookrelay_station",""))
	var body:VBoxContainer=app.modal.get_meta("cookrelay_body")
	update_footer(app,p,m,station)
	# remaining changes every tick: update the timer in place, rebuild only on real change.
	var stable:=p.duplicate(true)
	stable["remaining"]=0
	var signature:=JSON.stringify([stable,m,station,can_see_timer(p,m)])
	if str(app.modal.get_meta("cookrelay_signature",""))==signature:
		var time_label:=body.find_child("CookRelayTime",true,false) as Label
		if time_label:time_label.text=time_text(p,m)
		return
	app.modal.set_meta("cookrelay_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(m.get("unlocked",false)):
		HarvestUI.wrapped(app,body,"灶台接力尚未開放，之後再來看看。",17).name="CookRelayLocked"
		app._layout_preview.call_deferred()
		return
	build(app,body,p,m,station)
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func update_footer(app,p:Dictionary,m:Dictionary,station:String)->void:
	if not is_instance_valid(app.modal_feedback):return
	var text:="Esc 回到島上 · 按 %s 開啟或操作"%app.binding_label("interact")
	if bool(m.get("practice",false)) or str(p.get("mode",""))=="practice":text+=" · 練習不列入排名"
	# Only overwrite the footer while it still shows our own hint (keep server replies).
	var current:=str(app.modal_feedback.text)
	if current.is_empty() or current.begins_with("Esc 回到島上"):app.modal_feedback.text=text

# ---------------------------------------------------------------- build --

static func warm_card(parent:Node,id:String)->VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	var style:=StyleBoxFlat.new()
	style.bg_color=CARD_BG
	style.border_color=CARD_EDGE
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=12;style.content_margin_bottom=12
	card.add_theme_stylebox_override("panel",style)
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",6)
	card.add_child(inner)
	return inner

static func slot_box(parent:Node,id:String,edge:Color)->VBoxContainer:
	var box:=PanelContainer.new()
	box.name=id
	var style:=StyleBoxFlat.new()
	style.bg_color=SLOT_BG
	style.border_color=edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left=10;style.content_margin_right=10
	style.content_margin_top=6;style.content_margin_bottom=6
	box.add_theme_stylebox_override("panel",style)
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",2)
	box.add_child(inner)
	return inner

static func build(app,body:VBoxContainer,p:Dictionary,m:Dictionary,station:String)->void:
	var card:=warm_card(body,"CookRelayCard")
	build_card(app,card,p,m)
	if station.is_empty():build_board(app,body,p,m)
	else:build_station(app,body,p,m,station)

## The recipe card itself: title, need vs live slots, steps, score.
static func build_card(app,card:VBoxContainer,p:Dictionary,m:Dictionary)->void:
	var phase:=phase_of(p)
	var head:=HBoxContainer.new();head.name="CookRelayHeader";head.add_theme_constant_override("separation",14);card.add_child(head)
	var recipe:=recipe_of(p)
	var title:=str(recipe.get("title","今日菜單")) if phase!="idle" and not recipe.is_empty() else TITLE
	var title_label:=HarvestUI.text(app,head,title,22,WARN);title_label.name="CookRelayDish"
	title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HarvestUI.text(app,head,phase_text(p,m),15,INK).name="CookRelayPhase"
	var timer:=HarvestUI.text(app,head,time_text(p,m),16,WARN);timer.name="CookRelayTime"
	var mode:=str(p.get("mode",""))
	if mode=="practice":
		HarvestUI.text(app,card,"練習模式・不列入排名",14,GOOD).name="CookRelayPracticeNote"
	if phase=="run" or phase=="results":
		var need:=need_items(p)
		var tray:=tray_items(p)
		var live_slots:Array[String]=[]
		for item:String in need:
			live_slots.append(item if item in tray else "")
			if item in tray:tray.erase(item)
		for i in live_slots.size():
			if live_slots[i].is_empty() and not tray.is_empty():live_slots[i]=str(tray.pop_front())
		var slots:=HBoxContainer.new();slots.name="CookRelaySlots";slots.add_theme_constant_override("separation",10);card.add_child(slots)
		for i in maxi(need.size(),2):
			var want:=str(need[i]) if i<need.size() else ""
			var live:=live_slots[i] if i<live_slots.size() else ""
			var ok:=not live.is_empty() and live==want
			var wrong:=not live.is_empty() and live!=want
			var edge:=GOOD if ok else (WARN if wrong else CARD_EDGE)
			var box:=slot_box(slots,"CookRelaySlot_%d"%i,edge)
			var requirement:=HBoxContainer.new()
			requirement.add_theme_constant_override("separation",6)
			box.add_child(requirement)
			var icon:=TextureRect.new()
			icon.texture=Items.icon(INGREDIENT_ICONS.get(want,""))
			icon.custom_minimum_size=Vector2(32,32)
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			requirement.add_child(icon)
			HarvestUI.text(app,requirement,"需要 %s"%item_label(want),16).name="CookRelayNeed_%d"%i
			var state:="目前：%s"%item_label(live) if not live.is_empty() else "目前：空"
			if ok:state+=" ✓"
			elif wrong:state+=" ✗ 不對，到裝盤檯退回"
			HarvestUI.text(app,box,state,16,GOOD if ok else (WARN if wrong else MUTED)).name="CookRelayLive_%d"%i
		var steps:=HBoxContainer.new();steps.name="CookRelaySteps";steps.add_theme_constant_override("separation",10);card.add_child(steps)
		var step:=step_of(p)
		var done:=true
		for key:String in STEP_ORDER:
			var is_current:=key==step
			if is_current:done=false
			var mark:="▶ " if is_current else ("✓ " if done and phase=="run" else "")
			var label:=HarvestUI.text(app,steps,mark+str(STEP_TITLES[key])+"・"+str(STATION_NAMES[key]),14,WARN if is_current else (GOOD if done else MUTED))
			label.name="CookRelayStep_"+key
			label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	elif phase=="idle":
		HarvestUI.wrapped(app,card,"一份食譜卡、三個檯子：備料 → 裝盤 → 出餐。照卡上的食材接力做菜。",14,MUTED).name="CookRelayIntro"
	elif phase=="lobby":
		var need_names:=PackedStringArray()
		for r:Variant in Relay.RECIPES.values():
			if r is Dictionary:need_names.append(str(r.get("title","")))
		HarvestUI.wrapped(app,card,"菜單：%s。開始後每道菜要備齊兩樣食材。"%"、".join(need_names),14,MUTED).name="CookRelayIntro"
	var score:=HBoxContainer.new();score.name="CookRelayScore";score.add_theme_constant_override("separation",16);card.add_child(score)
	HarvestUI.text(app,score,"已出餐 %d 份"%int(p.get("plates",0)),15).name="CookRelayPlates"
	if mode=="crew":HarvestUI.text(app,score,"分數 %d"%int(p.get("score",0)),17,GOOD).name="CookRelayScoreText"
	HarvestUI.text(app,score,"%d 位上桌"%int(p.get("guests",0)),14,MUTED).name="CookRelayGuests"
	if phase=="results" and bool(m.get(mode,false)):
		HarvestUI.text(app,card,"料理接力紀念已收錄" if mode=="crew" else "首次練習紀念已收錄",14,GOOD).name="CookRelayKeepsake"

static func phase_text(p:Dictionary,m:Dictionary)->String:
	match phase_of(p):
		"lobby":return "招募中"
		"run":return "旁觀中・看大家做菜" if is_spectating(p,m) else "進行中・第 %d 輪"%int(p.get("round",0))
		"results":return "第 %d 輪結算"%int(p.get("round",0))
	return "目前沒有進行中的一輪"

# ---------------------------------------------------------------- board --

static func build_board(app,body:VBoxContainer,p:Dictionary,m:Dictionary)->void:
	var phase:=phase_of(p)
	var rid:=round_id(p)
	var joined:=bool(m.get("joined",false))
	var mode:=str(p.get("mode",""))
	var where:=HarvestUI.wrapped(app,body,board_where(app),14,MUTED)
	where.name="CookRelayWhere"
	var bar:=HBoxContainer.new();bar.name="CookRelayActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var cell:Vector2i=Relay.SIGN
	var buttons:Array[Button]=[]
	var open_round:=phase=="idle" or phase=="results"
	var idle_reason:=""
	if not open_round:idle_reason="目前這一輪還沒結束。"
	buttons.append(HarvestUI.action(app,bar,"CookRelayCrew","組隊開局",func():app.session.perform(ACTION,cell,"crew"),open_round,idle_reason))
	buttons.append(HarvestUI.action(app,bar,"CookRelayPractice","自己練習（不計排名）",func():app.session.perform(ACTION,cell,"practice"),open_round,idle_reason))
	var join_reason:=""
	if phase!="lobby" or mode!="crew":join_reason="現在沒有招募中的組隊場次。" if phase!="run" else "這一輪已經開始，可以旁觀。"
	elif joined:join_reason="你已經加入了。"
	buttons.append(HarvestUI.action(app,bar,"CookRelayJoin","加入",func():app.session.perform(ACTION,cell,"join:"+rid),join_reason.is_empty(),join_reason))
	var begin_reason:=""
	if phase!="lobby":begin_reason="還沒有招募中的場次。"
	elif not joined:begin_reason="先加入才能開始。"
	elif not bool(m.get("can_begin",false)):begin_reason="至少要有 2 位已加入的島民在線。"
	buttons.append(HarvestUI.action(app,bar,"CookRelayBegin","開始料理",func():app.session.perform(ACTION,cell,"begin:"+rid),begin_reason.is_empty(),begin_reason))
	var leave_reason:=""
	if not joined:leave_reason="你還沒加入。"
	buttons.append(HarvestUI.action(app,bar,"CookRelayLeave","離開",func():app.session.perform(ACTION,cell,"leave:"+rid),leave_reason.is_empty(),leave_reason))
	buttons[0].visible=open_round
	buttons[1].visible=open_round
	buttons[2].visible=phase=="lobby" and not joined
	buttons[3].visible=phase=="lobby" and joined
	buttons[4].visible=joined
	link_focus(app,buttons)
	var hint:=board_hint(p,m)
	HarvestUI.wrapped(app,body,hint,14,GOOD if hint.begins_with("可以") else MUTED).name="CookRelayHint"

static func board_where(app)->String:
	return "工位在廣場南側，由西往東是備料桌、裝盤桌、出餐口。走近後按 %s 操作。"%app.binding_label("interact")

static func board_hint(p:Dictionary,m:Dictionary)->String:
	var joined:=bool(m.get("joined",false))
	match phase_of(p):
		"idle":return "可以開局：組隊一起做，或自己練習（不計排名）。"
		"lobby":
			if joined:return "可以開始：人到齊後按「開始料理」。"
			return "招募中：按「加入」一起做。"
		"run":
			if joined:return "料理中：到備料檯、裝盤檯、出餐口接力。"
			return "這一輪已開始，你在旁觀；下一輪再加入。"
		"results":return "這一輪結束了，可以再開一局。"
	return ""

# -------------------------------------------------------------- stations --

static func build_station(app,body:VBoxContainer,p:Dictionary,m:Dictionary,station:String)->void:
	var phase:=phase_of(p)
	var rid:=round_id(p)
	var joined:=bool(m.get("joined",false))
	var cell:Vector2i=Relay.STATIONS.get(station,Relay.SIGN)
	var running:=phase=="run" and joined
	var reason:=""
	if phase!="run":reason="目前沒有進行中的一輪，到告示牌開局。"
	elif not joined:reason="你在旁觀，這一輪不能操作。"
	var tray:=tray_items(p)
	var need_count:=need_items(p).size()
	var plated:=bool(p.get("plated",false))
	var buttons:Array[Button]=[]
	var bar:=HBoxContainer.new();bar.name="CookRelayActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var hint:="";
	match station:
		"prep":
			var prep_reason:=reason
			if prep_reason.is_empty() and plated:prep_reason="這盤已裝好，先到出餐口送出。"
			elif prep_reason.is_empty() and tray.size()>=maxi(need_count,2):prep_reason="兩格都放滿了，到裝盤檯。"
			for key:Variant in Relay.ITEMS.keys():
				var item:=str(key)
				buttons.append(HarvestUI.action(app,bar,"CookRelayPrep_"+item,item_label(item),func():app.session.perform(ACTION,cell,"prep:%s:%s"%[rid,item]),prep_reason.is_empty(),prep_reason))
			hint="照食譜挑兩樣食材，順序不限。" if prep_reason.is_empty() else prep_reason
		"assembly":
			var plate_reason:=reason
			if plate_reason.is_empty() and plated:plate_reason="已經裝盤，到出餐口。"
			elif plate_reason.is_empty() and not tray_matches(p):plate_reason="兩格食材要和卡上完全一致才能裝盤。"
			var undo_reason:=reason
			if undo_reason.is_empty() and tray.is_empty():undo_reason="托盤上沒有食材。"
			buttons.append(HarvestUI.action(app,bar,"CookRelayPlate","裝盤",func():app.session.perform(ACTION,cell,"plate:"+rid),plate_reason.is_empty(),plate_reason))
			buttons.append(HarvestUI.action(app,bar,"CookRelayUndo","退回這盤食材",func():app.session.perform(ACTION,cell,"undo:"+rid),undo_reason.is_empty(),undo_reason))
			hint="食材對了就裝盤；放錯可以退回這盤食材。" if plate_reason.is_empty() else plate_reason
			if plate_reason.is_empty():hint="食材一致，可以裝盤。"
		"serve":
			var serve_reason:=reason
			if serve_reason.is_empty() and not plated:serve_reason="還沒有裝好的盤子。"
			buttons.append(HarvestUI.action(app,bar,"CookRelayServe","出餐",func():app.session.perform(ACTION,cell,"serve:"+rid),serve_reason.is_empty(),serve_reason))
			hint="盤子好了，送給客人！" if serve_reason.is_empty() else serve_reason
	for b in buttons:b.custom_minimum_size.x=104
	link_focus(app,buttons)
	if is_spectating(p,m):hint="你在旁觀：看得到進度，但不能操作。"
	HarvestUI.wrapped(app,body,hint,14,GOOD if running and not hint.begins_with("你") else MUTED).name="CookRelayHint"

## Explicit keyboard/gamepad neighbours between enabled buttons and the close button.
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
