extends RefCounted
## T071 「河岸釣魚會」 client: panel, world prompts, HUD tracker text and the art
## helpers shared with world_view.gd. Rules live in fishing_meet.gd; this file only
## reads snapshot.own_fish_meet (personal view) and snapshot.fish_meet (public,
## participants keyed by the same public id as snapshot.players). Start / join /
## leave go through Session.perform(fish_meet_start / fish_meet_join /
## fish_meet_leave); catches use the ordinary fish_start / fish_catch of the fishing
## tool, so nothing here sends a catch. Server replies reach app.modal_feedback /
## the toast via app._notice, like the harvest relay panel (harvest_relay_ui.gd,
## which this file mirrors).
##
## Art (no new PNGs): notice board = assets/ui-life/furniture.png "sign" with the
## carp icon of assets/ui-inventory/items.png on its board and a small blue pennant
## (runtime rectangles) so it reads differently from the 豐收接力 sign (radish icon);
## waters marker = runtime-drawn rope of dashes along the WATERS rect with red/white
## buoys on the corners and long-edge midpoints, gently bobbing unless reduced motion
## is on; species card icons = the four freshwater fish item icons.
##
## HUD priority: 豐收接力 tracking (harvest_relay_ui.refresh_hud) runs first and
## wins when both are somehow true; this tracker only writes when the harvest relay
## is not tracking. Both outrank 風鈴接力 / tea guidance (timed rounds).
const World=preload("res://scripts/world.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const TITLE:="河岸釣魚會"
const POINT:="fishmeet:sign"
const RULE:="1～8 人、5 分鐘：在告示牌旁這段河面（浮標圍起來的地方）釣魚，一起記錄 12 筆。魚記進魚種卡後放回河裡，不進背包。"
const BAG_NOTE:="浮標內釣到的魚只記錄、不進背包，鈴幣也不變；浮標外照常進背包。中途離開背包維持原樣，這一輪結算時仍會拿到參加紀念票。"
const TICKET_RULE:="參加 1 張、四種魚都記到 +1、記滿 12 筆 +1"
const WHERE:="到告示牌南北兩側的河岸，對著浮標內的河面拋竿"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const ROW_HEIGHT:=26
## Waters marker colours (rope, buoy body, buoy stripe, outline).
const ROPE:=Color("f3e6c4")
const BUOY:=Color("d8553f")
const BUOY_STRIPE:=Color("fff8e3")
const BUOY_EDGE:=Color("392d23")

# ------------------------------------------------------------------ state --

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_fish_meet",{})
	return found if found is Dictionary else {}

static func public_meet(s:Dictionary)->Dictionary:
	var found:Variant=s.get("fish_meet",{})
	return found if found is Dictionary else {}

static func at_home(s:Dictionary)->bool:
	return str(s.get("region_id","home"))=="home"

## The notice board is drawn and interactable only at home once unlocked and its cell is free.
static func on_field(s:Dictionary)->bool:
	return at_home(s) and World.fish_meet_available(s)

## The designated waters are marked for everyone at home while a round runs.
static func waters_marked(s:Dictionary)->bool:
	return on_field(s) and bool(public_meet(s).get("active",false))

## The HUD tracker follows the round only while I am joined in it at home.
static func tracking(s:Dictionary)->bool:
	var m:=own(s)
	return at_home(s) and bool(m.get("active",false)) and bool(m.get("joined",false))

static func near_sign(s:Dictionary,id:String)->bool:
	var person:Variant=s.get("players",{}).get(id)
	if not at_home(s) or not person is Dictionary:return false
	var at:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	return at.distance_to(Vector2(Meet.SIGN)+Vector2(0.5,0.5))<=Meet.SIGN_REACH

## World label of the notice board. Focused: what the interact key does.
static func sign_title(s:Dictionary,focused:bool)->String:
	if focused:return TITLE+"・打開活動"
	var m:=public_meet(s)
	return "%s %d／%d"%[TITLE,int(m.get("records",0)),Meet.GOAL] if bool(m.get("active",false)) else TITLE

static func fish_icon(kind:String)->Texture2D:
	return Items.icon(kind)

static func whole_seconds(value:Variant)->int:
	return HarvestUI.whole_seconds(value)

# ------------------------------------------------------------- world art --

## Screen rect (world px, unzoomed) of the WATERS rect for a view.
static func waters_rect(view)->Rect2:
	return Rect2(view.screen(Vector2(Meet.WATERS.position)),Vector2(Meet.WATERS.size)*32.0)

## Buoy centres (world px, unzoomed, before bobbing): four corners and the middle
## of both long edges, pulled 3 px inside the rect so they sit on the water.
static func buoy_points(view)->Array[Vector2]:
	var r:=waters_rect(view).grow(-3.0)
	var mid:=r.position.y+r.size.y/2.0
	return [r.position,Vector2(r.end.x,r.position.y),Vector2(r.position.x,mid),Vector2(r.end.x,mid),Vector2(r.position.x,r.end.y),r.end]

## Dashed rope + buoys around WATERS. Static when reduced motion is on.
static func draw_waters(view,elapsed:float,reduced_motion:bool)->void:
	var r:=waters_rect(view).grow(-3.0)
	var corners:=[r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]
	for i in 4:
		var a:Vector2=corners[i]
		var b:Vector2=corners[(i+1)%4]
		var length:=a.distance_to(b)
		var dir:=(b-a)/maxf(length,1.0)
		var t:=0.0
		while t<length:
			var e:=minf(t+6.0,length)
			view.draw_line((a+dir*t).round(),(a+dir*e).round(),ROPE,2.0)
			t+=10.0
	var index:=0
	for p:Vector2 in buoy_points(view):
		var bob:=0.0 if reduced_motion else roundf(sin(elapsed*2.2+index*1.3)*1.0)
		var c:=(p+Vector2(0,bob)).round()
		view.draw_rect(Rect2(c-Vector2(4,4),Vector2(8,8)),BUOY_EDGE)
		view.draw_rect(Rect2(c-Vector2(3,3),Vector2(6,6)),BUOY)
		view.draw_rect(Rect2(c-Vector2(3,0),Vector2(6,2)),BUOY_STRIPE)
		index+=1

## Notice board: the shared sign sprite (its board spans about at+(2..30, 0..24)),
## a carp icon covering the painted leaf on the board face and a small blue pennant
## on the right post, so it differs from the 豐收接力 sign (radish above the board).
static func draw_sign(view,at:Vector2,furniture)->void:
	furniture.draw_sprite(view,at,"sign")
	view.draw_rect(Rect2(at+Vector2(27,-6),Vector2(2,10)),Color("6b4a2f"))
	view.draw_colored_polygon(PackedVector2Array([at+Vector2(29,-6),at+Vector2(37,-3),at+Vector2(29,0)]),Color("4f86b0"))
	var carp:=fish_icon("carp")
	if carp:view.draw_texture_rect(carp,Rect2(at+Vector2(8,3),Vector2(16,16)),false)

# ------------------------------------------------------------------ HUD --

## main._refresh_hud, after HarvestUI.refresh_hud: while I am joined in an active
## round (and the harvest relay is not tracking) the tracker follows the meet.
static func refresh_hud(app,s:Dictionary)->void:
	if not tracking(s) or HarvestUI.tracking(s):return
	var m:=own(s)
	var lines:=PackedStringArray()
	lines.append(hud_line(m))
	lines.append(WHERE+"（%s 拿釣竿）"%app.binding_label("fish"))
	app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	app.objective.text="\n".join(lines)
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	if heading:heading.text="河岸釣魚會  ▾"
	var next:=app.hud.find_child("TrackerNext",true,false) as Button
	if next:next.text="查看河岸釣魚會  →"

## Two lines so the 202 px tracker never wraps mid-number.
static func hud_line(m:Dictionary)->String:
	return "%s 記錄 %d / %d\n魚種 %d / %d · 剩 %d 秒"%[TITLE,int(m.get("records",0)),int(m.get("goal",Meet.GOAL)),int(m.get("species_count",0)),int(m.get("species_total",Meet.KINDS.size())),whole_seconds(m.get("seconds_left",0.0))]

# ---------------------------------------------------------------- panel --

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="FishingMeetPanel"
	app.modal.set_meta("life_modal_layout","fishing_meet")
	app.modal.set_meta("fishmeet_body",body)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上 · 浮標內釣到的魚不會進背包"
	body.add_theme_constant_override("separation",8)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: wide like the harvest panel, as tall as its content.
static func layout(app,bounds:Vector2)->void:
	HarvestUI.layout(app,bounds)

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("fishmeet_body")

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("fishmeet_body")
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
	var body:Control=app.modal.get_meta("fishmeet_body") if app.modal.has_meta("fishmeet_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var id:String=app.session.own_id
	var m:=own(s)
	var body:VBoxContainer=app.modal.get_meta("fishmeet_body")
	# seconds_left changes every tick: update it in place instead of rebuilding.
	var signature:=JSON.stringify([m.duplicate(true).merged({"seconds_left":0},true),at_home(s),on_field(s),near_sign(s,id),whole_seconds(m.get("cooldown",0.0))])
	if str(app.modal.get_meta("fishmeet_signature",""))==signature:
		var time_label:=body.find_child("FishMeetTime",true,false) as Label
		if time_label:time_label.text=time_text(m)
		return
	app.modal.set_meta("fishmeet_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(m.get("unlocked",false)):
		var lock:=HarvestUI.wrapped(app,body,Meet.LOCKED,17)
		lock.name="FishMeetLocked"
		HarvestUI.wrapped(app,body,RULE,14,MUTED).name="FishMeetRule"
		app._layout_preview.call_deferred()
		return
	build(app,body,s,id,m)
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func time_text(m:Dictionary)->String:
	if bool(m.get("active",false)):return "剩 %d 秒"%whole_seconds(m.get("seconds_left",0.0))
	var wait:=whole_seconds(m.get("cooldown",0.0))
	return "整理魚種卡・約 %d 秒"%wait if wait>0 else "可以開始"

static func build(app,body:VBoxContainer,s:Dictionary,id:String,m:Dictionary)->void:
	var active:=bool(m.get("active",false))
	# 1. Header: round, progress, time.
	var header:=HBoxContainer.new();header.name="FishMeetHeader";header.add_theme_constant_override("separation",16);body.add_child(header)
	header.add_child(Shell.picture(fish_icon("carp"),32))
	HarvestUI.text(app,header,"第 %d 輪進行中"%int(m.get("round",0)) if active else "目前沒有進行中的一輪",17).name="FishMeetStatus"
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(spacer)
	# Between rounds the card still shows the finished round until the next start.
	var finished:=not active and int(m.get("round",0))>0
	HarvestUI.text(app,header,("上一輪 " if finished else "")+"記錄 %d / %d · 魚種 %d / %d"%[int(m.get("records",0)),Meet.GOAL,int(m.get("species_count",0)),Meet.KINDS.size()],16).name="FishMeetProgress"
	HarvestUI.text(app,header,time_text(m),16,WARN if active else MUTED).name="FishMeetTime"
	HarvestUI.wrapped(app,body,RULE,14,MUTED).name="FishMeetRule"
	# 2. Species card (left), participants (right).
	var columns:=HBoxContainer.new();columns.name="FishMeetColumns";columns.add_theme_constant_override("separation",12);body.add_child(columns)
	var left:=HarvestUI.paper(columns,"FishMeetSpeciesCard")
	HarvestUI.text(app,left,"魚種卡（這一輪）" if active else ("魚種卡（上一輪）" if finished else "魚種卡"),17).name="FishMeetSpeciesTitle"
	var names:Array=m.get("species_names",[]) if m.get("species_names",[]) is Array else []
	if names.is_empty():
		for kind:String in Meet.KINDS:names.append({"id":kind,"name":Meet.kind_name(kind),"count":0})
	for entry:Dictionary in names:
		var kind:=str(entry.get("id",""))
		var count:=int(entry.get("count",0))
		var row:=HBoxContainer.new();row.name="FishMeetSpecies_"+kind;row.add_theme_constant_override("separation",8);left.add_child(row)
		row.custom_minimum_size.y=ROW_HEIGHT
		var pic:=Shell.picture(fish_icon(kind),24)
		pic.modulate.a=1.0 if count>0 else 0.35
		row.add_child(pic)
		var name_label:=HarvestUI.text(app,row,str(entry.get("name","")),15,INK if count>0 else MUTED)
		name_label.custom_minimum_size.x=96
		HarvestUI.text(app,row,"記錄 %d 條"%count if count>0 else "尚未記錄",14,GOOD if count>0 else MUTED).name="FishMeetCount_"+kind
	var note:=HarvestUI.wrapped(app,left,BAG_NOTE,13,GOOD)
	note.name="FishMeetBagNote"
	var right:=HarvestUI.paper(columns,"FishMeetPeopleCard")
	var people_head:=HBoxContainer.new();right.add_child(people_head)
	var people_title:=HarvestUI.text(app,people_head,"參加者",17);people_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HarvestUI.text(app,people_head,"%d／%d 人在場"%[int(m.get("joined_count",0)),int(m.get("max_players",Meet.MAX_PLAYERS))],14).name="FishMeetPeopleCount"
	var rows:=VBoxContainer.new();rows.name="FishMeetPeople";rows.add_theme_constant_override("separation",2);right.add_child(rows)
	var list:Array=(m.get("participants",[]) as Array).duplicate() if m.get("participants",[]) is Array else []
	# Me first, then the others who are in (server order is stable), then those who left.
	var ordered:Array=list.filter(func(e):return bool(e.get("me",false)))+list.filter(func(e):return bool(e.get("joined",false)) and not bool(e.get("me",false)))+list.filter(func(e):return not bool(e.get("joined",false)) and not bool(e.get("me",false)))
	if ordered.is_empty():HarvestUI.text(app,rows,"還沒有人參加。" if not active else "還沒有人加入這一輪。",14,MUTED).name="FishMeetPeopleEmpty"
	for index in mini(ordered.size(),Meet.MAX_PLAYERS):
		var entry:Dictionary=ordered[index]
		var row:=HBoxContainer.new();row.name="FishMeetPerson_%d"%index;row.add_theme_constant_override("separation",6)
		row.custom_minimum_size.y=ROW_HEIGHT;rows.add_child(row)
		var here:=bool(entry.get("joined",false))
		var who:=HarvestUI.text(app,row,str(entry.get("name","島民"))+("（我）" if bool(entry.get("me",false)) else ""),15,INK if here or not active else MUTED)
		who.custom_minimum_size.x=130
		var state:="在場" if here else "已離開"
		if not active:state="本輪結束"
		HarvestUI.text(app,row,"%s · 記錄 %d 筆"%[state,int(entry.get("caught",0))],14,INK if here or not active else MUTED).name="FishMeetPersonDetail_%d"%index
	if ordered.size()>Meet.MAX_PLAYERS:
		HarvestUI.text(app,rows,"另有 %d 位曾參加這一輪。"%(ordered.size()-Meet.MAX_PLAYERS),13,MUTED).name="FishMeetPeopleMore"
	# 3. Actions + the one reason line.
	var reasons:=action_reasons(s,id,m)
	var bar:=HBoxContainer.new();bar.name="FishMeetActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var round_id:=str(int(m.get("round",0)))
	var buttons:Array[Button]=[]
	buttons.append(HarvestUI.action(app,bar,"FishMeetStart","開始一場",func():app.session.perform("fish_meet_start",Meet.SIGN,round_id),reasons.start.is_empty(),reasons.start))
	buttons.append(HarvestUI.action(app,bar,"FishMeetJoin","加入",func():app.session.perform("fish_meet_join",Meet.SIGN,round_id),reasons.join.is_empty(),reasons.join))
	buttons.append(HarvestUI.action(app,bar,"FishMeetLeave","離開活動",func():app.session.perform("fish_meet_leave",Meet.SIGN,""),reasons.leave.is_empty(),reasons.leave))
	for b in buttons:b.custom_minimum_size.x=128
	var hint:=HarvestUI.wrapped(app,body,hint_text(app,m,reasons),14,WARN if not reasons.hint_ok else GOOD)
	hint.name="FishMeetHint"
	link_focus(app,buttons)
	# 4. Last round + my record.
	var bottom:=HBoxContainer.new();bottom.name="FishMeetBottom";bottom.add_theme_constant_override("separation",12);body.add_child(bottom)
	var last_box:=HarvestUI.paper(bottom,"FishMeetLastCard")
	var last:Dictionary=m.get("last",{}) if m.get("last",{}) is Dictionary else {}
	HarvestUI.text(app,last_box,"上一輪成果",15)
	if last.is_empty():
		HarvestUI.text(app,last_box,"還沒有完成的一輪",14,MUTED).name="FishMeetLast"
	else:
		var why:="記滿 %d 筆"%Meet.GOAL if str(last.get("reason",""))=="goal" else "時間到"
		HarvestUI.text(app,last_box,"第 %d 輪 · %s · 記錄 %d / %d · 魚種 %d / %d"%[int(last.get("round",0)),why,int(last.get("records",0)),Meet.GOAL,int(last.get("species",0)),Meet.KINDS.size()],14).name="FishMeetLast"
		HarvestUI.text(app,last_box,"%d 人參加 · 每人 %d 張紀念票"%[int(last.get("players",0)),int(last.get("tickets",0))],14).name="FishMeetLastTickets"
	var record_box:=HarvestUI.paper(bottom,"FishMeetRecordCard")
	HarvestUI.souvenir_note(app,record_box,"FishMeet")
	HarvestUI.text(app,record_box,"紀念票 %d 張 · 參加 %d 場 · 最佳 %d 筆"%[int(m.get("tickets",0)),int(m.get("rounds",0)),int(m.get("best",0))],14).name="FishMeetRecord"
	HarvestUI.text(app,record_box,TICKET_RULE,13,MUTED).name="FishMeetTicketRule"

## Why each button is disabled ("" = enabled) plus whether the hint is good news.
static func action_reasons(s:Dictionary,id:String,m:Dictionary)->Dictionary:
	var active:=bool(m.get("active",false))
	var joined:=bool(m.get("joined",false))
	var near:=near_sign(s,id)
	var out:={"start":"","join":"","leave":"","hint_ok":false}
	var wait:=whole_seconds(m.get("cooldown",0.0))
	var field:=""
	if not at_home(s):field=Meet.WRONG_REGION
	elif not bool(m.get("available",false)):field=Meet.UNAVAILABLE
	var walk:="請走到河灣橋南邊、西岸的河岸釣魚會告示牌前（3 格內）再%s。"
	if not field.is_empty():out.start=field
	elif active:out.start="這一輪正在進行，按「加入」就能一起釣。"
	elif wait>0:out.start=Meet.COOLDOWN_MSG%wait
	elif not near:out.start=walk%"開始"
	if not field.is_empty():out.join=field
	elif not active:out.join="目前沒有進行中的一輪。"
	elif joined:out.join=Meet.ALREADY_JOINED
	elif int(m.get("joined_count",0))>=int(m.get("max_players",Meet.MAX_PLAYERS)):out.join=Meet.FULL%Meet.MAX_PLAYERS
	elif not near:out.join=walk%"加入"
	if not at_home(s):out.leave=Meet.WRONG_REGION
	elif not active or not joined:out.leave="還沒有加入這一輪。"
	return out

static func hint_text(app,m:Dictionary,reasons:Dictionary)->String:
	var active:=bool(m.get("active",false))
	var joined:=bool(m.get("joined",false))
	if not active:
		if reasons.start.is_empty():
			reasons.hint_ok=true
			return "可以開始：按「開始一場」，其他人在告示牌前按「加入」。"
		return str(reasons.start)
	if not joined:
		if reasons.join.is_empty():
			reasons.hint_ok=true
			return "按「加入」一起釣；中途也能加入或離開。"
		return str(reasons.join)
	reasons.hint_ok=true
	return "按 %s 拿釣竿，%s。"%[app.binding_label("fish"),WHERE]

## Explicit keyboard/gamepad neighbours (same scheme as the harvest relay panel).
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
