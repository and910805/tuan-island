extends SceneTree
## 第 40 章金瓜石初訪「運礦路線」頁 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_gold_panning_ui.gd: real main scene, real Session host, real snapshot round trips. Written
## against work/claude-agents/ore_route_contract.md (section 「頁面」 and the main.gd wiring).
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set
##    here (the runner passes no flag for this suite);
##  * before each size: state.ore_route ERASED, my coins set to 100, state.time = day 1 (30.0) —
##    the whole run stays inside that one world day, so the daily count (2 carts) is real;
##  * the local player is teleported by writing region/x/y (no walking or travel): home, the
##    centre of the cart's current cell (Route.cart_cell(stage)) and a Jinguashi spot 2.6 tiles
##    from the cart (out of Route.REACH, chosen away from the other Jinguashi interaction points);
##  * session rate buckets / action_clock are cleared before each of my own actions.
## REALLY EXERCISED (local player):
##  * main._interact() (the normal interaction entry, called directly, no key event) -> OreRouteUI
##    .interact: at stage 0 it opens the page; at stage >= 1 it does NOT open the page and pushes /
##    unloads directly through Session.perform(ore_cart, cart cell, next step) -> World -> snapshot;
##    world_view.interaction_focus() names the ore_cart point next to the cart;
##  * every OrAction press is a `pressed` signal emission on the real Button -> OreRouteUI ->
##    Session.perform -> World -> snapshot -> in-place refresh; every stage / count / total / coin
##    change after the reset is the server's (two whole carts per size, mixing page presses and
##    direct pushes, the second unloaded from the page);
##  * the server replies in the page footer (modal_feedback) or, page closed, in the HUD toast.
## NO real mouse, keyboard or gamepad input drives the page (only the template's harness step of
## one KEY_E push to dismiss a possible Wangan arrival card before the flows start).
## NOT COVERED HERE: world track / platform / cart pixels and the world name label (art / scene
## suites); a second connected client; gamepad / arrow-key focus travel; the non-preview layout;
## day rollover; the purse-full block in the live game (only in the pure action_reason table).
const World=preload("res://scripts/world.gd")
const Route=preload("res://scripts/ore_route.gd")
const UI=preload("res://scripts/ore_route_ui.gd")
const Art=preload("res://scripts/ore_route_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
## Home spot (walkable, used by test_jinguashi_revisit_ui as BUILD_SPOT).
const HOME_SPOT:=Vector2(42.5,34.5)
const START_COINS:=100
const FAR_DISTANCE:=2.6
## Hand-written expected stop chips: CHIPS[stage][index] (index 0 裝礦台 … 6 卸礦台).
const CHIPS:=[
	["▶ 裝礦台","○ 1","○ 2","○ 3","○ 4","○ 5","○ 卸礦台"],
	["▶ 裝礦台","○ 1","○ 2","○ 3","○ 4","○ 5","○ 卸礦台"],
	["✓ 裝礦台","▶ 1","○ 2","○ 3","○ 4","○ 5","○ 卸礦台"],
	["✓ 裝礦台","✓ 1","▶ 2","○ 3","○ 4","○ 5","○ 卸礦台"],
	["✓ 裝礦台","✓ 1","✓ 2","▶ 3","○ 4","○ 5","○ 卸礦台"],
	["✓ 裝礦台","✓ 1","✓ 2","✓ 3","▶ 4","○ 5","○ 卸礦台"],
	["✓ 裝礦台","✓ 1","✓ 2","✓ 3","✓ 4","▶ 5","○ 卸礦台"],
	["✓ 裝礦台","✓ 1","✓ 2","✓ 3","✓ 4","✓ 5","▶ 卸礦台"],
]
## Hand-written expected button captions per stage.
const CAPTION_TABLE:=["裝一車礦料","往前推一段（還剩 6 段）","往前推一段（還剩 5 段）","往前推一段（還剩 4 段）",
	"往前推一段（還剩 3 段）","往前推一段（還剩 2 段）","往前推一段（還剩 1 段）","卸下礦料"]
const AWAY_TABLE:=["請沿軌道到裝礦台找台車。","請沿軌道到裝礦台找台車。","請沿軌道到1 號停靠點找台車。",
	"請沿軌道到2 號停靠點找台車。","請沿軌道到3 號停靠點找台車。","請沿軌道到4 號停靠點找台車。",
	"請沿軌道到5 號停靠點找台車。","請沿軌道到卸礦台找台車。"]
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("ORE_ROUTE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE ORE_ROUTE_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func button(name:String)->Button:
	return control(name) as Button

func label_text(name:String)->String:
	var l:=control(name) as Label
	return l.text if l!=null else ""

func shown(name:String)->bool:
	var c:=control(name)
	return c!=null and c.is_visible_in_tree()

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func page_open()->bool:
	return layout_name()==UI.LAYOUT

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null:return false
	if b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x

func rect_info(c:Control)->String:
	var modal_rect:="none"
	if is_instance_valid(app.modal):modal_rect=str((app.modal as Control).get_global_rect())
	return "modal=%s control=%s"%[modal_rect,str(c.get_global_rect()) if c!=null else "null"]

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	app._refresh_hud()
	await settle()

func snap()->Dictionary:
	return app.session.snapshot

func person()->Dictionary:
	return w.state.players[id]

func coins()->int:
	return int(person().get("coins",0))

func snap_coins()->int:
	var me:Dictionary=UI.person_of(snap(),str(app.session.own_id))
	return int(me.get("coins",-1))

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func toast_text()->String:
	if app.toast==null or not is_instance_valid(app.toast):return ""
	return str((app.toast as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func server_stage()->int:
	return Route.stage(w.state,id)

func server_count()->int:
	return Route.count_today(w.state,id)

func server_total()->int:
	return Route.total(w.state,id)

## Centre of the cell the cart stands on at `stage`.
func cart_spot(stage:int)->Vector2:
	return Vector2(Route.cart_cell(stage))+Vector2(0.5,0.5)

## Every other Jinguashi interaction point main._interact knows about (centres).
func other_points()->Array:
	var out:Array=[]
	for site in World.JINGUASHI.NODES:out.append(Vector2(site)+Vector2(0.5,0.5))
	out.append(Vector2(World.MINES.ENTRY)+Vector2(0.5,0.5))
	out.append(Vector2(World.GOLD_PANNING.SITE)+Vector2(0.5,0.5))
	var workshop:Dictionary=World.BOBO_WORKSHOP.sites(snap())
	for field:String in ["npc","table"]:
		if workshop.get(field) is Vector2i:out.append(Vector2(workshop[field])+Vector2(0.5,0.5))
	var stations:Variant=World.TRANSIT.points(Route.REGION)
	if stations is Dictionary:
		for station_id in stations:
			var entry:Variant=stations[station_id]
			if entry is Dictionary and entry.get("cell") is Vector2i:out.append(Vector2(entry.cell)+Vector2(0.5,0.5))
	return out

## A Jinguashi spot FAR_DISTANCE from the cart (out of Route.REACH, inside main's 3.2 pick
## radius), preferring a direction where no other interaction point is closer than the cart.
func far_spot(stage:int)->Vector2:
	var centre:=cart_spot(stage)
	var others:=other_points()
	var d:=FAR_DISTANCE
	var diagonal:=FAR_DISTANCE/sqrt(2.0)
	for dir:Vector2 in [Vector2(0,d),Vector2(0,-d),Vector2(d,0),Vector2(-d,0),Vector2(diagonal,diagonal),Vector2(-diagonal,diagonal),Vector2(diagonal,-diagonal),Vector2(-diagonal,-diagonal)]:
		var spot:=centre+dir
		var clear:=true
		for other:Vector2 in others:
			if other.distance_to(spot)<=FAR_DISTANCE+0.1:clear=false
		if clear:return spot
	return centre+Vector2(0,d)

func stand(at:Vector2,region:String)->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:app.hud.remove_child(ribbon);ribbon.queue_free()
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

## The normal interaction entry (main._interact), no key event.
func interact()->void:
	app.action_clock=0
	app.session.rates[1].clear()
	app._interact()
	await settle()
	await refresh()

## Press OrAction through its `pressed` signal (no mouse / key event).
func press_action(label:String)->bool:
	var b:=button("OrAction")
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"OrAction enabled before pressing (%s)"%label)
	if b==null or b.disabled:return false
	app.action_clock=0
	app.session.rates[1].clear()
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

## The server's success message for the step taken at `stage` (count = carts done today before).
func expected_message(stage:int,count:int)->String:
	if stage==0:return Route.LOAD_OK
	if stage==Route.LAST:return Route.UNLOAD_OK%[Route.PAY,count+1]
	if stage==Route.LAST-1:return Route.PUSH_LAST
	return Route.PUSH_OK%[stage,Route.LAST-(stage+1)]

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / picture inside
## the page and whole, no ellipsis, seven chips in one row inside the cart card.
func layout_ok(label:String)->void:
	if not page_open():
		check(false,"Page %s open for layout: %s (got %s)"%[UI.LAYOUT,label,layout_name()])
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	for name in ["OrHeader","OrCount","OrCartCard","OrCart","OrStage","OrStops","OrAction","OrPurse","OrPay","OrBlurb","OrHow","OrDisclaimer"]:
		check(shown(name),"%s shown (%s)"%[name,label])
	var pic:=control("OrCart") as TextureRect
	check(pic!=null and pic.size.x>=127.5 and pic.size.y>=127.5,"Cart picture shown at 128×128 (%s): %s"%[label,str(pic.size) if pic!=null else "none"])
	# Seven chips: one row, left to right, inside the cart card.
	var card:=control("OrCartCard")
	var row:=control("OrStops")
	check(row is HBoxContainer,"OrStops is an HBoxContainer (%s)"%label)
	if card==null or row==null:return
	var card_rect:=card.get_global_rect().grow(0.5)
	check(card.is_ancestor_of(row) and card_rect.encloses(row.get_global_rect()),"OrStops inside OrCartCard (%s) card=%s row=%s"%[label,str(card.get_global_rect()),str(row.get_global_rect())])
	var last_right:=-INF
	var first_top:=NAN
	var one_row:=true
	var inside:=true
	var ordered:=true
	for i in range(Route.STOPS.size()):
		var chip:=control("OrStop_%d"%i)
		if chip==null or not chip.is_visible_in_tree() or chip.get_parent()!=row:
			check(false,"OrStop_%d is a visible child of OrStops (%s)"%[i,label])
			continue
		var r:=chip.get_global_rect()
		if is_nan(first_top):first_top=r.position.y
		elif absf(r.position.y-first_top)>1.0:one_row=false
		if r.position.x+0.5<last_right:ordered=false
		last_right=r.end.x
		if not card_rect.encloses(r):inside=false
	check(one_row,"Seven chips on one row (%s)"%label)
	check(ordered,"Chips left to right in stop order (%s)"%label)
	check(inside,"Every chip inside the cart card (%s)"%label)

func focus_on_action(label:String)->void:
	check(focused_name()=="OrAction" and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(root.gui_get_focus_owner()),"Keyboard focus on OrAction (%s): %s"%[label,focused_name()])

## Server record and snapshot only (works with the page closed).
func record_is(stage:int,count:int,total:int,label:String)->void:
	check(server_stage()==stage and server_count()==count and server_total()==total,"Server record stage %d count %d total %d (%s): %d %d %d"%[stage,count,total,label,server_stage(),server_count(),server_total()])
	var own:Variant=snap().get(Route.OWN_KEY,{})
	var ok:bool=own is Dictionary and int(own.get("stage",-1))==stage and int(own.get("count",-1))==count and int(own.get("total",-1))==total
	check(ok,"Snapshot own_ore_route (%s): %s"%[label,str(own)])
	check(not snap().has(Route.STATE_KEY),"Public snapshot never carries state.ore_route (%s)"%label)

## Everything on the page that follows the cart record, against the helpers and hand tables.
func cart_is(stage:int,count:int,total:int,label:String)->void:
	record_is(stage,count,total,label)
	check(label_text("OrStage")==Route.stage_text(stage) and shown("OrStage"),"Stage text %d (%s): %s"%[stage,label,label_text("OrStage")])
	var pic:=control("OrCart") as TextureRect
	check(pic!=null and pic.texture==Art.cart_texture(stage>0),"Cart picture is the %s cart (%s)"%["loaded" if stage>0 else "empty",label])
	for i in range(Route.STOPS.size()):
		var chip:String=UI.chip_text(stage,i)
		var want:String=CHIPS[stage][i]
		check(label_text("OrStop_%d"%i)==want and chip==want,"Chip %d at stage %d 「%s」 (%s): %s"%[i,stage,want,label,label_text("OrStop_%d"%i)])
	var b:=button("OrAction")
	var caption:String=UI.action_caption(stage)
	check(b!=null and b.text==CAPTION_TABLE[stage] and caption==CAPTION_TABLE[stage],"OrAction caption 「%s」 (%s): %s"%[CAPTION_TABLE[stage],label,b.text if b!=null else "none"])
	var count_line:String=UI.count_text(snap())
	check(label_text("OrCount")=="今天 %d／2 車・累計 %d 車"%[count,total] and label_text("OrCount")==count_line,"Count line (%s): %s"%[label,label_text("OrCount")])
	check(label_text("OrPurse")=="鈴幣：%d"%coins() and coins()==snap_coins(),"Purse line (%s): %s server %d snapshot %d"%[label,label_text("OrPurse"),coins(),snap_coins()])
	check(label_text("OrPay")=="運礦工資：每車 %d 鈴幣"%Route.PAY and label_text("OrPay")=="運礦工資：每車 12 鈴幣","Pay line (%s): %s"%[label,label_text("OrPay")])
	check(label_text("OrBlurb")==Route.BLURB,"Blurb verbatim (%s)"%label)
	check(label_text("OrHow")==Route.HOW,"How-to verbatim (%s)"%label)
	check(label_text("OrDisclaimer")==Route.DISCLAIMER,"Disclaimer verbatim (%s)"%label)

## Enabled: no reason line. Disabled: reason line, tooltip == reason, still focusable.
func action_state(enabled:bool,reason:String,label:String)->void:
	var b:=button("OrAction")
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"OrAction %s (%s)"%["enabled" if enabled else "disabled",label])
	if b==null:return
	if enabled:
		check(not shown("OrReason"),"No reason line while enabled (%s): %s"%[label,label_text("OrReason")])
	else:
		check(b.tooltip_text==reason,"OrAction tooltip 「%s」 (%s): %s"%[reason,label,b.tooltip_text])
		check(b.focus_mode==Control.FOCUS_ALL,"OrAction stays focusable while disabled (%s)"%label)
		check(shown("OrReason") and label_text("OrReason")==reason,"Reason line 「%s」 (%s): %s"%[reason,label,label_text("OrReason")])
	var me:Dictionary=UI.person_of(snap(),str(app.session.own_id))
	var expected:String=UI.action_reason(snap(),me)
	check(expected==reason,"action_reason on the live snapshot 「%s」 (%s): %s"%[reason,label,expected])

## One press on the page; checks the server's reply and the in-place update.
func step_once(label:String)->void:
	var stage:=server_stage()
	var count:=server_count()
	var total:=server_total()
	var coins_before:=coins()
	var modal_before:Node=app.modal
	var modal_id:=(app.modal as Object).get_instance_id() if is_instance_valid(app.modal) else 0
	var card_before:=control("OrCartCard")
	var pic:=control("OrCart") as TextureRect
	var texture_before:Texture2D=pic.texture if pic!=null else null
	var want:=expected_message(stage,count)
	var tag:="%s, press at stage %d"%[label,stage]
	if not await press_action(tag):return
	var same:bool=page_open() and app.modal==modal_before and is_instance_valid(app.modal) and (app.modal as Object).get_instance_id()==modal_id and control("OrCartCard")==card_before
	check(same,"Page stays open and is updated in place, same modal instance (%s)"%tag)
	check(control("OrCart")==pic,"Same cart picture node (%s)"%tag)
	check(feedback()==want,"Server reply in the footer 「%s」 (%s): %s"%[want,tag,feedback()])
	if stage==Route.LAST:
		cart_is(0,count+1,total+1,tag)
		check(coins()==coins_before+Route.PAY and snap_coins()==coins_before+Route.PAY,"Unload pays %d (%s): %d -> %d"%[Route.PAY,tag,coins_before,coins()])
	else:
		cart_is(stage+1,count,total,tag)
		check(coins()==coins_before,"Coins unchanged before the unload (%s)"%tag)
	if stage==0:check(pic!=null and pic.texture!=texture_before,"Cart picture changes on loading (%s)"%tag)
	check(is_instance_valid(app.modal) and (app.modal as Node).has_meta("or_signature"),"or_signature meta kept (%s)"%tag)
	focus_on_action(tag)

## Page closed: from too far nothing changes; next to the cart main._interact pushes / unloads
## directly without opening the page.
func direct_step(label:String)->void:
	var stage:=server_stage()
	var count:=server_count()
	var total:=server_total()
	var coins_before:=coins()
	var tag:="%s, direct at stage %d"%[label,stage]
	await close_page()
	await stand(far_spot(stage),Route.REGION)
	await interact()
	check(server_stage()==stage and server_count()==count and server_total()==total,"Too far: interact does not move the cart (%s): %d"%[tag,server_stage()])
	check(coins()==coins_before,"Too far: coins unchanged (%s)"%tag)
	check(not page_open(),"Too far: page not opened (%s): %s"%[tag,layout_name()])
	await close_page()
	await stand(cart_spot(stage),Route.REGION)
	check(str(app.view.interaction_focus())==UI.POINT,"Cart is the focused point next to it (%s): %s"%[tag,str(app.view.interaction_focus())])
	var want:=expected_message(stage,count)
	await interact()
	check(not page_open() and not is_instance_valid(app.modal),"Interact next to a loaded cart does not open the page (%s): %s"%[tag,layout_name()])
	check(toast_text()==want,"Server reply in the toast 「%s」 (%s): %s"%[want,tag,toast_text()])
	if stage==Route.LAST:
		record_is(0,count+1,total+1,tag)
		check(coins()==coins_before+Route.PAY and snap_coins()==coins_before+Route.PAY,"Direct unload pays %d (%s): %d -> %d (snapshot %d)"%[Route.PAY,tag,coins_before,coins(),snap_coins()])
	else:
		record_is(stage+1,count,total,tag)
		check(coins()==coins_before,"Coins unchanged by a push (%s)"%tag)
	await close_page()

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase(Route.STATE_KEY)  # PRESET
	person().coins=START_COINS  # PRESET
	w.state.time=30.0  # PRESET (day 1)
	await refresh()

func open_at_load(label:String)->void:
	await close_page()
	await stand(cart_spot(0),Route.REGION)
	check(server_stage()==0,"Cart is at the load platform (%s): stage %d"%[label,server_stage()])
	check(str(app.view.interaction_focus())==UI.POINT,"ore_cart is the focused point at the load platform (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact()
	check(page_open(),"Interaction at the load platform opens the page (%s): %s"%[label,layout_name()])

func away_from_jinguashi_flow(label:String)->void:
	await close_page()
	await stand(HOME_SPOT,World.REGIONS.HOME)
	check(not snap().has(Route.OWN_KEY),"No own_ore_route outside Jinguashi (%s)"%label)
	check(not snap().has(Route.STATE_KEY),"Public snapshot never carries state.ore_route (%s)"%label)
	UI.open(app)
	await settle()
	check(not UI.is_open(app) and not page_open(),"open() does nothing outside Jinguashi (%s): %s"%[label,layout_name()])
	await close_page()
	app.action_clock=0
	app.session.rates[1].clear()
	UI.interact(app)
	await settle()
	await refresh()
	check(not UI.is_open(app) and not page_open(),"interact() does not open the page outside Jinguashi (%s): %s"%[label,layout_name()])
	check(server_stage()==0 and server_total()==0,"interact() outside Jinguashi changes nothing (%s)"%label)
	await close_page()
	await interact()
	check(not page_open(),"main._interact at home does not open the ore route page (%s): %s"%[label,layout_name()])
	await close_page()

func open_flow(label:String)->void:
	await open_at_load("open "+label)
	if not page_open():return
	check(UI.is_open(app),"is_open (%s)"%label)
	check(str((app.modal as Node).name)=="OreRoutePanel","Modal node name (%s): %s"%[label,str((app.modal as Node).name)])
	check((app.modal as Node).has_meta("or_body"),"or_body meta (%s)"%label)
	check(bool((app.modal as Node).get_meta("suppress_world_prompts",false)),"suppress_world_prompts meta (%s)"%label)
	check((app.modal as Node).has_meta("or_signature"),"or_signature meta (%s)"%label)
	check(texts().contains(UI.PAGE_TITLE) and UI.PAGE_TITLE==Route.TITLE,"Page title 「%s」 shown (%s)"%[Route.TITLE,label])
	check(snap().has(Route.OWN_KEY) and not snap().has(Route.STATE_KEY),"Own record only in the Jinguashi snapshot (%s)"%label)
	focus_on_action("open "+label)
	var close:BaseButton=UI.close_button(app)
	check(close!=null and close.is_visible_in_tree() and not (app.modal.get_meta("or_body") as Node).is_ancestor_of(close),"close_button() outside the body (%s)"%label)
	cart_is(0,0,0,"fresh "+label)
	action_state(true,"","fresh "+label)
	layout_ok("fresh "+label)

## Load and the first push from the page; the cart then leaves the player behind.
func first_cart_page_flow(label:String)->void:
	if not page_open():return
	await step_once("cart 1 "+label)
	action_state(true,"","loaded, still next to the cart "+label)
	layout_ok("loaded "+label)
	await step_once("cart 1 "+label)
	var reason:=UI.away_text(2)
	check(reason==AWAY_TABLE[2],"away_text(2) literal (%s): %s"%[label,reason])
	action_state(false,reason,"cart left behind "+label)
	focus_on_action("cart left behind "+label)
	layout_ok("cart left behind "+label)

## Page closed: the remaining pushes and the unload straight from the world.
func first_cart_direct_flow(label:String)->void:
	await close_page()
	check(not is_instance_valid(app.modal) and not UI.is_open(app),"Page closed (%s)"%label)
	while server_stage()>=1 and server_total()==0:
		var before:=server_stage()
		await direct_step("cart 1 "+label)
		if server_stage()==before:break  # no progress; failures already recorded
	record_is(0,1,1,"first cart delivered "+label)
	check(coins()==START_COINS+Route.PAY,"One wage after the first cart (%s): %d"%[label,coins()])

## Page open while the player walks: the reason toggles in place.
func walk_toggle(stage:int,label:String)->void:
	if not page_open():return
	var modal_before:Node=app.modal
	await stand(far_spot(stage),Route.REGION)
	check(page_open() and app.modal==modal_before,"Page stays open while walking away (%s)"%label)
	var me:Dictionary=UI.person_of(snap(),str(app.session.own_id))
	check(not UI.near(snap(),me),"near() false away from the cart (%s)"%label)
	action_state(false,UI.away_text(stage),"walked away "+label)
	check(UI.away_text(stage)==AWAY_TABLE[stage],"away_text(%d) literal (%s)"%[stage,label])
	focus_on_action("walked away "+label)
	await stand(cart_spot(stage),Route.REGION)
	check(page_open() and app.modal==modal_before,"Same page after walking back (%s)"%label)
	me=UI.person_of(snap(),str(app.session.own_id))
	check(UI.near(snap(),me),"near() true next to the cart (%s)"%label)
	action_state(true,"","walked back "+label)
	focus_on_action("walked back "+label)

func second_cart_flow(label:String)->void:
	await open_at_load("second cart "+label)
	if not page_open():return
	cart_is(0,1,1,"reopened "+label)
	check(label_text("OrCount")=="今天 1／2 車・累計 1 車","Count 1 on reopening (%s): %s"%[label,label_text("OrCount")])
	action_state(true,"","reopened "+label)
	focus_on_action("reopened "+label)
	await step_once("cart 2 "+label)  # load
	await step_once("cart 2 "+label)  # push 1 -> cart leaves
	action_state(false,UI.away_text(2),"cart 2 left behind "+label)
	# Walk after the cart with the page open; it re-enables in place, then push from the page.
	var modal_before:Node=app.modal
	await stand(cart_spot(2),Route.REGION)
	check(page_open() and app.modal==modal_before,"Same page after following the cart (%s)"%label)
	action_state(true,"","caught up with the cart "+label)
	await step_once("cart 2 "+label)  # push 2 -> stage 3
	action_state(false,UI.away_text(3),"cart 2 left behind again "+label)
	await walk_toggle(3,"stage 3 "+label)  # far first (still disabled), then next to the cart
	layout_ok("cart 2 stage 3 "+label)
	# The rest of the pushes directly from the world, page closed.
	while server_stage()>=3 and server_stage()<Route.LAST:
		var before:=server_stage()
		await direct_step("cart 2 "+label)
		if server_stage()==before:break
	record_is(Route.LAST,1,1,"cart 2 at the unload platform "+label)
	# Unload from the page: open() works at any stage while in Jinguashi.
	await stand(cart_spot(Route.LAST),Route.REGION)
	UI.open(app)
	await settle()
	await refresh()
	check(page_open(),"open() at the unload platform (%s): %s"%[label,layout_name()])
	if not page_open():return
	cart_is(Route.LAST,1,1,"at the unload platform "+label)
	action_state(true,"","at the unload platform "+label)
	focus_on_action("at the unload platform "+label)
	layout_ok("at the unload platform "+label)
	await step_once("cart 2 "+label)  # unload
	check(coins()==START_COINS+2*Route.PAY,"Two wages after two carts (%s): %d"%[label,coins()])

func daily_flow(label:String)->void:
	if not page_open():return
	cart_is(0,2,2,"daily limit "+label)
	check(feedback()==Route.UNLOAD_OK%[Route.PAY,2],"Second unload reply (%s): %s"%[label,feedback()])
	# Rules first: the cart is back at the load platform, far away, but the reason is DAILY_DONE.
	action_state(false,Route.DAILY_DONE,"daily limit far "+label)
	focus_on_action("daily limit far "+label)
	layout_ok("daily limit "+label)
	await open_at_load("daily limit "+label)
	if not page_open():return
	cart_is(0,2,2,"daily limit at the load platform "+label)
	action_state(false,Route.DAILY_DONE,"daily limit near "+label)
	focus_on_action("daily limit near "+label)
	layout_ok("daily limit at the load platform "+label)
	await close_page()

func size_flow(label:String)->void:
	await reset()
	await away_from_jinguashi_flow(label)
	await open_flow(label)
	await first_cart_page_flow(label)
	await first_cart_direct_flow(label)
	await second_cart_flow(label)
	await daily_flow(label)

# ---------------------------------------------------------------- pure checks --

func fake(stage:int,count:int,total:int)->Dictionary:
	return {"time":30.0,"region_id":Route.REGION,Route.OWN_KEY:{"stage":stage,"count":count,"total":total}}

func at(stage:int,offset:Vector2=Vector2.ZERO,coins_value:int=START_COINS)->Dictionary:
	var spot:=cart_spot(stage)+offset
	return {"x":spot.x,"y":spot.y,"coins":coins_value,"inventory":{}}

func pure_checks()->void:
	check(UI.LAYOUT=="ore_route" and UI.POINT=="ore_cart" and UI.PAGE_TITLE==Route.TITLE,"Contract constants")
	check(Art.POINT==UI.POINT,"Art and UI share the ore_cart point")
	for stage in range(Route.LAST+1):
		var caption:String=UI.action_caption(stage)
		check(caption==CAPTION_TABLE[stage],"action_caption(%d) 「%s」: %s"%[stage,CAPTION_TABLE[stage],caption])
		for i in range(Route.STOPS.size()):
			var chip:String=UI.chip_text(stage,i)
			check(chip==CHIPS[stage][i],"chip_text(%d,%d) 「%s」: %s"%[stage,i,CHIPS[stage][i],chip])
		var away:String=UI.away_text(stage)
		check(away==AWAY_TABLE[stage],"away_text(%d): %s"%[stage,away])
	var counted:String=UI.count_text(fake(2,1,7))
	check(counted=="今天 1／2 車・累計 7 車","count_text: %s"%counted)
	var empty_count:String=UI.count_text({"region_id":Route.REGION})
	check(empty_count=="今天 0／2 車・累計 0 車","count_text without a record: %s"%empty_count)
	check(UI.region_of({"region_id":"jinguashi"})=="jinguashi","region_of")
	var me:Dictionary=at(0)
	var people:Dictionary={"players":{"me":me}}
	check(UI.person_of(people,"me")==me,"person_of finds the own player")
	check(UI.person_of(people,"other").is_empty(),"person_of: unknown id is empty")
	# near(): follows the cart's cell and Route.REACH, only in Jinguashi.
	for stage in range(Route.LAST+1):
		var s:Dictionary=fake(stage,0,0)
		check(UI.near(s,at(stage)),"near next to the cart at stage %d"%stage)
		check(UI.near(s,at(stage,Vector2(Route.REACH-0.05,0))) and not UI.near(s,at(stage,Vector2(Route.REACH+0.05,0))),"near follows Route.REACH at stage %d"%stage)
		check(not UI.near({"region_id":"home",Route.OWN_KEY:{"stage":stage,"count":0,"total":0}},at(stage)),"Not near outside Jinguashi at stage %d"%stage)
	check(not UI.near(fake(2,0,0),at(0)),"After the first push the load platform is out of reach")
	check(UI.near(fake(1,0,0),at(0)),"Loaded cart still at the load platform (stage 1)")
	# action_reason(): the rules first, then where to stand.
	for stage in range(Route.LAST+1):
		var reason:String=UI.action_reason(fake(stage,0,0),at(stage))
		check(reason.is_empty(),"Near at stage %d: no reason: %s"%[stage,reason])
		reason=UI.action_reason(fake(stage,0,0),at(stage,Vector2(0,FAR_DISTANCE)))
		check(reason==AWAY_TABLE[stage],"Far at stage %d: away_text: %s"%[stage,reason])
	var limit_reason:String=UI.action_reason(fake(0,2,2),at(0))
	check(limit_reason==Route.DAILY_DONE,"Daily limit near: DAILY_DONE: %s"%limit_reason)
	limit_reason=UI.action_reason(fake(0,2,2),at(0,Vector2(0,FAR_DISTANCE)))
	check(limit_reason==Route.DAILY_DONE,"Daily limit far: rules first: %s"%limit_reason)
	limit_reason=UI.action_reason(fake(0,2,2),at(Route.LAST))
	check(limit_reason==Route.DAILY_DONE,"Daily limit at the unload platform: DAILY_DONE: %s"%limit_reason)
	limit_reason=UI.action_reason(fake(3,2,5),at(3))
	check(limit_reason.is_empty(),"A cart already on the way can be finished at the limit: %s"%limit_reason)
	limit_reason=UI.action_reason(fake(Route.LAST,2,5),at(Route.LAST))
	check(limit_reason.is_empty(),"…and unloaded at the limit: %s"%limit_reason)
	var full:Dictionary=at(Route.LAST,Vector2.ZERO,Route.LIMIT)
	var purse_reason:String=UI.action_reason(fake(Route.LAST,0,0),full)
	check(purse_reason==Route.PURSE_FULL,"Purse full at the unload platform: PURSE_FULL: %s"%purse_reason)
	purse_reason=UI.action_reason(fake(Route.LAST,0,0),at(Route.LAST,Vector2(0,FAR_DISTANCE),Route.LIMIT))
	check(purse_reason==Route.PURSE_FULL,"Purse full far away: rules first: %s"%purse_reason)
	purse_reason=UI.action_reason(fake(6,0,0),at(6,Vector2.ZERO,Route.LIMIT))
	check(purse_reason.is_empty(),"Purse full does not block a push: %s"%purse_reason)
	# Art: the panel's 64×64 pictures, cached, loaded differs from empty.
	var empty_tex:Texture2D=Art.cart_texture(false)
	var loaded_tex:Texture2D=Art.cart_texture(true)
	check(empty_tex!=null and loaded_tex!=null and empty_tex.get_width()==Art.CART_SIZE and empty_tex.get_height()==Art.CART_SIZE and loaded_tex.get_width()==Art.CART_SIZE and loaded_tex.get_height()==Art.CART_SIZE and Art.CART_SIZE==64,"Two 64×64 cart pictures")
	check(empty_tex==Art.cart_texture(false) and loaded_tex==Art.cart_texture(true) and empty_tex!=loaded_tex,"Cart pictures cached, loaded differs from empty")

# ------------------------------------------------------------------------ run --

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("ore-route-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"運礦旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true");app.playing=true
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
		if failures>40:break
	await close_page()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
