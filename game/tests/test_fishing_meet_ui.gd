extends SceneTree
## T071 河岸釣魚會 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_harvest_relay_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * state.board=true and state.picnic written directly (picnic false for the locked
##    checks, then true);
##  * state.fish_meet and every player.fish_meet erased before each size (a fresh
##    activity, no cooldown); the player's own `fishing` cast is erased too;
##  * the local player is teleported by writing region/x/y (next to the sign, onto the
##    shore cells (54,34) / (54,36)); "walking" there is a position write;
##  * teammates are fake online players: World.add_player + a fake session.peers entry
##    (as test_harvest_relay_ui.gd), positioned by writing x/y; their join and their
##    fish_start / fish_catch are sent with World.act (they are other people);
##  * world clock: state.time is set to a cast's `ready` time (bite) instead of
##    waiting; to time out the round state.time is set past `ends` and the normal
##    World.step(1.0) tick settles it; session rate buckets are cleared between my
##    own clicks (as test_fishing_input.gd);
##  * the occupied-sign case writes a lamp object onto the sign cell directly.
## REALLY EXERCISED (local player):
##  * the interact key (KEY_E through root.push_input -> main._unhandled_input ->
##    _interact) at the sign opens the panel; Esc closes it;
##  * 開始一場 / 離開活動 pressed by emitting `pressed` after grabbing focus (real
##    Session.perform -> World -> snapshot -> panel refresh);
##  * casting and reeling with the fishing tool by left-clicking the water tile through
##    root.push_input (the same path as test_fishing_input.gd);
##  * the entries in 渡口派對 · 風鈴接力 (activity page), the 公告板 and the HUD tracker
##    button open the panel; KEY_UP / KEY_DOWN focus navigation through push_input.
## NOT COVERED HERE: world pixels / marker drawing (see test_fishing_meet_scene.gd).
const World=preload("res://scripts/world.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const FishUI=preload("res://scripts/fishing_meet_ui.gd")
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
const SIGN_SPOT:=Vector2(54.5,39.5)   # shore cell (54,39): 1.0 below the sign
const FISH_SPOT:=Vector2(54.5,36.5)   # shore cell (54,36): 2.0 from the sign, casts at (55,36)
const NORTH_SPOT:=Vector2(54.5,34.5)  # shore cell (54,34): reaches (55,34) inside and (55,33) outside
const INSIDE:=Vector2i(55,34)
const OUTSIDE:=Vector2i(55,33)
const AWAY:=Vector2(46.5,36.5)
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var finished:=false
var friends:Array[String]=[]
var peer_seq:=900

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("FISHING_MEET_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE FISHING_MEET_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func button(name:String)->Button:
	return control(name) as Button

func label_text(name:String)->String:
	var l:=control(name) as Label
	return l.text if l!=null else ""

func layout_meta()->String:
	if not is_instance_valid(app.modal):return ""
	return str((app.modal as Node).get_meta("life_modal_layout",""))

func panel_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="fishing_meet"

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

func own()->Dictionary:
	return FishUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

func toast()->String:
	return str((app.toast as Label).text) if app.toast!=null and is_instance_valid(app.toast) else ""

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focus()->String:
	return str(app.view.interaction_focus()) if app.view!=null and app.view.has_method("interaction_focus") else "?"

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

## Left click on a world cell, as test_fishing_input.gd does.
func click(cell:Vector2i)->void:
	app.action_clock=0
	var point:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*app.view.view_zoom()
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=point
	event.global_position=point
	root.push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event,true)
	await process_frame
	await refresh()

func press(name:String,label:String,stay_open:=true)->bool:
	var b:=control(name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	b.grab_focus()  # as a keyboard/controller press would
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	if stay_open:check(panel_open(),"Panel stays open after %s (%s)"%[name,label])
	return true

func disabled_with_reason(name:String,label:String,contains:String="")->void:
	var b:=button(name)
	check(b!=null and b.disabled and not b.tooltip_text.is_empty() and (contains.is_empty() or b.tooltip_text.contains(contains)),"%s disabled with a reason (%s): %s"%[name,label,b.tooltip_text if b else "missing"])

func close_panel()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func fish_total(p:Dictionary)->int:
	var total:=0
	for fish in World.FISH:total+=int((p.inventory as Dictionary).get(fish,0))
	return total

func world_label(id_value:String)->Dictionary:
	app.view.queue_redraw()
	await process_frame
	await process_frame
	for entry in app.view.world_labels:
		if str(entry.id)==id_value:return entry
	return {}

# ------------------------------------------------------------------- layout --

func layout_ok(label:String)->void:
	if not panel_open():
		check(false,"Panel open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Panel fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer panel needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for name in ["FishMeetStatus","FishMeetProgress","FishMeetTime","FishMeetRule","FishMeetBagNote","FishMeetPeopleCount","FishMeetPeople","FishMeetStart","FishMeetJoin","FishMeetLeave","FishMeetHint","FishMeetLast","FishMeetRecord","FishMeetTicketRule"]:
		var c:=control(name)
		check(c!=null and c.is_visible_in_tree(),"%s present (%s)"%[name,label])
		if c==null:continue
		check(view_rect.encloses(c.get_global_rect()) and modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside viewport and panel (%s) %s"%[name,label,rect_info(c)])
	for kind:String in Meet.KINDS:
		check(control("FishMeetSpecies_"+kind)!=null,"Species row %s (%s)"%[kind,label])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(view_rect.encloses(c.get_global_rect()),"%s inside the viewport (%s) %s"%[c.name,label,rect_info(c)])
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the panel (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the panel (%s)"%label)
	for name in ["FishMeetHeader","FishMeetColumns","FishMeetActions","FishMeetBottom"]:
		var row:=control(name)
		if row!=null:check(row.get_combined_minimum_size().x<=row.size.x+0.5,"%s does not overflow (%s)"%[name,label])
	var all:=texts()
	check(all.contains("1～8 人") and all.contains("5 分鐘") and all.contains("不進背包") and all.contains(FishUI.TICKET_RULE),"Rule, backpack note and ticket rule shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and not (owner as BaseButton).disabled,"Keyboard focus is on an enabled button inside the panel (%s): %s"%[label,str(owner.name) if owner else "none"])

## A page opened from an entry point gains no outer scrolling from the new entry:
## its scroll overflow with the entry equals the overflow with the entry removed
## (some pages, e.g. the 公告板, already scrolled before this activity existed).
func page_fits(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Page open: "+label)
		return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	var entry:=button("FishingMeetEntry")
	if outer!=null and entry!=null:
		var bar:=outer.get_v_scroll_bar()
		var with_entry:=maxf(0.0,bar.max_value-bar.page)
		var parent:=entry.get_parent()
		var index:=entry.get_index()
		parent.remove_child(entry)
		await settle()
		var without:=maxf(0.0,bar.max_value-bar.page)
		parent.add_child(entry)
		parent.move_child(entry,index)
		await settle()
		note("%s outer overflow with entry %.0f px, without %.0f px"%[label,with_entry,without])
		check(with_entry<=without+1.0,"The 河岸釣魚會 entry adds no outer scrolling (%s): %.0f vs %.0f"%[label,with_entry,without])
		if without<=1.0:check(with_entry<=1.0,"Page needs no outer scrolling (%s)"%label)
	if entry!=null:
		# The 公告板 is a scrolling page (other board cards already push it past the
		# fold), so the entry must be reachable by scrolling: bring it into view the
		# way keyboard focus / the scroll wheel does, then require it whole inside
		# both the visible scroll area and the page.
		if outer!=null:
			outer.ensure_control_visible(entry)
			await settle()
			check(outer.get_global_rect().grow(0.5).encloses(entry.get_global_rect()),"河岸釣魚會 entry reachable by scrolling inside the visible scroll area (%s) %s"%[label,rect_info(entry)])
		check(modal.get_global_rect().grow(0.5).encloses(entry.get_global_rect()) and button_not_cut(entry),"河岸釣魚會 entry whole inside the page (%s)"%label)
		var harvest:=button("HarvestRelayEntry")
		if harvest!=null:check(button_not_cut(harvest),"豐收接力 entry caption not cut (%s)"%label)

# ------------------------------------------------------------------- fixture --

func reset_activity()->void:
	w.state.erase("fish_meet")  # PRESET fresh activity
	for token in w.state.players:
		(w.state.players[token] as Dictionary).erase("fish_meet")
		(w.state.players[token] as Dictionary).erase("fishing")
	w.state.objects.erase(World.key(Meet.SIGN))

func set_picnic(on:bool)->void:
	w.state.board=true  # PRESET
	w.state.picnic=on   # PRESET
	await refresh()

## PRESET: a fake online player (other person) standing at `at`.
func friend(index:int,at:Vector2)->String:
	var token:="fishmeet-friend-%d"%index
	if not w.state.players.has(token):
		w.add_player(token,FRIENDS[index])
		peer_seq+=1
		app.session.peers[peer_seq]=token
		friends.append(token)
	var p:Dictionary=w.state.players[token]
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	return token

func friend_act(token:String,action:String,p:Vector2i,extra:String="")->Dictionary:
	var result:Dictionary=w.act(token,"ui-%d"%Time.get_ticks_usec(),action,p,extra)
	await refresh()
	return result

## Entry button on the current page: present, captioned, opens the panel.
func entry_opens(page:String,label:String,locked:bool)->void:
	var entry:=button("FishingMeetEntry")
	var expect_text:="渡口野餐後開放" if locked else "河岸釣魚會（"
	check(entry!=null and entry.text.contains("河岸釣魚會") and entry.text.contains(expect_text),"%s lists 河岸釣魚會%s (%s): %s"%[page,"（鎖定）" if locked else "",label,entry.text if entry else "missing"])
	if entry==null:return
	await page_fits(page+" "+label)
	entry=button("FishingMeetEntry")
	entry.pressed.emit()
	await settle()
	check(panel_open(),"%s entry opens the 河岸釣魚會 panel (%s)"%[page,label])
	if locked:
		check(label_text("FishMeetLocked")==Meet.LOCKED and control("FishMeetStart")==null,"Locked panel from %s shows the lock (%s): %s"%[page,label,label_text("FishMeetLocked")])

# --------------------------------------------------------------------- flows --

func locked_flow(label:String)->void:
	await close_panel()
	reset_activity()
	await set_picnic(false)
	check(not FishUI.on_field(app.session.snapshot) and not bool(own().get("unlocked",true)),"Locked before the picnic (%s)"%label)
	await stand(SIGN_SPOT)
	check(focus()!=FishUI.POINT,"No 河岸釣魚會 focus at the sign spot before the picnic (%s): %s"%[label,focus()])
	check((await world_label(FishUI.POINT)).is_empty(),"No 河岸釣魚會 world label before the picnic (%s)"%label)
	await key(KEY_E)
	check(not panel_open(),"E at the sign spot before the picnic opens no 河岸釣魚會 (%s)"%label)
	await close_panel()
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁",label,true)
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the locked panel (%s)"%label)
	app._board()
	await settle()
	await entry_opens("公告板",label,true)
	await close_panel()

func main_flow(label:String)->void:
	await set_picnic(true)
	check(FishUI.on_field(app.session.snapshot) and bool(own().get("available",false)),"Activity available after the picnic (%s)"%label)
	check(own().get("sign")==Meet.SIGN and own().get("waters_rect")==Meet.WATERS,"own_fish_meet reports the server's cells (%s)"%label)
	# Entry pages after the picnic.
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁",label,false)
	await close_panel()
	app._board()
	await settle()
	await entry_opens("公告板",label,false)
	await close_panel()
	# Unfocused sign label, from the north shore spot (4 tiles away).
	await stand(NORTH_SPOT)
	var idle_label:=await world_label(FishUI.POINT)
	check(str(idle_label.get("title",""))=="河岸釣魚會","Sign world label 「河岸釣魚會」 (%s): %s"%[label,str(idle_label)])
	check(not FishUI.waters_marked(app.session.snapshot),"Waters not marked without a round (%s)"%label)
	# Interact key at the sign opens the panel.
	await stand(SIGN_SPOT)
	check(focus()==FishUI.POINT,"Standing below the sign focuses it (%s): %s"%[label,focus()])
	var focused_label:=await world_label(FishUI.POINT)
	check(str(focused_label.get("title",""))=="河岸釣魚會・打開活動","Focused sign prompt says it opens the activity (%s): %s"%[label,str(focused_label)])
	await key(KEY_E)
	check(panel_open(),"Interact at the sign opens 河岸釣魚會 (%s) texts=%s"%[label,texts().left(60).replace("\n"," | ")])
	if not panel_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the panel is open (%s)"%label)
	focus_ok("idle "+label)
	check(root.gui_get_focus_owner()==button("FishMeetStart"),"開始一場 focused first (%s)"%label)
	layout_ok("idle "+label)
	check(label_text("FishMeetStatus")=="目前沒有進行中的一輪" and label_text("FishMeetTime")=="可以開始","Idle status (%s): %s / %s"%[label,label_text("FishMeetStatus"),label_text("FishMeetTime")])
	check(label_text("FishMeetLast")=="還沒有完成的一輪","No last round yet (%s)"%label)
	for kind:String in Meet.KINDS:check(label_text("FishMeetCount_"+kind)=="尚未記錄","%s 尚未記錄 (%s)"%[kind,label])
	disabled_with_reason("FishMeetJoin",label)
	disabled_with_reason("FishMeetLeave",label)
	# Focus neighbours with one enabled button: up -> 關閉, down -> back.
	await key(KEY_UP)
	var up:=root.gui_get_focus_owner() as Button
	check(up!=null and up.text.contains("關閉"),"KEY_UP reaches 關閉 (%s): %s"%[label,up.text if up else "none"])
	await key(KEY_DOWN)
	check(root.gui_get_focus_owner()==button("FishMeetStart"),"KEY_DOWN from 關閉 returns to 開始一場 (%s)"%label)
	var start:=button("FishMeetStart")
	check(start.get_node_or_null(start.focus_neighbor_left)==start and start.get_node_or_null(start.focus_neighbor_right)==start,"Lone enabled button wraps to itself (%s)"%label)
	check(button("FishMeetJoin").focus_mode==Control.FOCUS_NONE,"Disabled 加入 is skipped by focus navigation (%s)"%label)
	var bag_before:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_before:=int(person().coins)
	var caught_before:=int(person().get("fish_caught",0))
	var collection_before:Variant=person().get("collection",{}).duplicate(true)
	# 開始一場.
	if not await press("FishMeetStart",label):return
	var round_id:=int(own().get("round",0))
	check(bool(own().active) and bool(own().joined) and round_id>=1,"開始一場 starts and joins a round (%s): %s"%[label,str(own().get("round"))])
	check(feedback().contains("河岸釣魚會開始"),"Server reply shown in the panel (%s): %s"%[label,feedback()])
	check(label_text("FishMeetStatus")=="第 %d 輪進行中"%round_id and label_text("FishMeetTime")=="剩 300 秒","Active status and time (%s): %s %s"%[label,label_text("FishMeetStatus"),label_text("FishMeetTime")])
	disabled_with_reason("FishMeetStart",label,"加入")
	check(button("FishMeetLeave")!=null and not button("FishMeetLeave").disabled,"離開活動 enabled once joined (%s)"%label)
	check(label_text("FishMeetHint").contains("浮標內的河面"),"Hint says where to cast (%s): %s"%[label,label_text("FishMeetHint")])
	focus_ok("started "+label)
	layout_ok("started "+label)
	# Seconds update in place (no rebuild) as the clock moves.
	var time_node:=control("FishMeetTime")
	w.state.time=float(w.state.time)+2.0  # PRESET clock
	await refresh()
	check(control("FishMeetTime")==time_node and label_text("FishMeetTime")=="剩 298 秒","Time label updated in place (%s): %s"%[label,label_text("FishMeetTime")])
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the panel (%s)"%label)
	# HUD tracker and world label during the round.
	await refresh()
	check(str(app.objective.text).begins_with("河岸釣魚會 記錄 0 / 12\n魚種 0 / 4 · 剩 298 秒"),"HUD tracker shows the round (%s): %s"%[label,app.objective.text])
	check(str(app.objective.text).contains("浮標內的河面拋竿"),"HUD tracker says where to cast (%s)"%label)
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	check(heading!=null and heading.text.begins_with("河岸釣魚會"),"Tracker heading follows 河岸釣魚會 (%s)"%label)
	check(FishUI.waters_marked(app.session.snapshot),"Waters marked during the round (%s)"%label)
	var tracker_next:=app.hud.find_child("TrackerNext",true,false) as Button
	check(tracker_next!=null and tracker_next.text.contains("河岸釣魚會"),"Tracker button names the meet (%s)"%label)
	if tracker_next!=null:
		tracker_next.pressed.emit()
		await settle()
		check(panel_open(),"Tracker button opens the panel (%s)"%label)
		await close_panel()
	# A real cast and catch into WATERS with the fishing tool.
	await stand(NORTH_SPOT)
	var round_label:=await world_label(FishUI.POINT)
	check(str(round_label.get("title",""))=="河岸釣魚會 0／12","Sign label shows progress during a round (%s): %s"%[label,str(round_label)])
	app.sound.standard_fishing=false
	app._select_tool("fish")
	await settle()
	app.session.rates[1].clear()
	await click(INSIDE)
	check(person().has("fishing") and int(person().fishing.x)==INSIDE.x and int(person().fishing.y)==INSIDE.y,"Click casts into the meet waters (%s): %s"%[label,toast()])
	if not person().has("fishing"):return
	w.state.time=float(person().fishing.ready)+0.1  # PRESET clock: the fish bites
	await refresh()
	app.session.rates[1].clear()
	await click(INSIDE)
	var first_kind:=Meet.kind_at(round_id,0)
	check(not person().has("fishing"),"Ready click reels in (%s)"%label)
	check(toast().contains("記進釣魚會的魚種卡後放回河裡") and toast().contains("背包沒有變動") and toast().contains(Meet.kind_name(first_kind)),"Meet catch message shown (%s): %s"%[label,toast()])
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Meet catch leaves the whole backpack and coins unchanged (%s)"%label)
	check(int(person().get("fish_caught",0))==caught_before and person().get("collection",{})==collection_before,"Meet catch adds no fishing count or collection entry (%s)"%label)
	check(int(own().get("records",0))==1 and int((own().get("species",{}) as Dictionary).get(first_kind,0))==1 and int(own().get("caught",0))==1,"Species card and counts update (%s): %s"%[label,str(own().get("species"))])
	check(str(app.objective.text).begins_with("河岸釣魚會 記錄 1 / 12\n魚種 1 / 4"),"Tracker counts the record (%s): %s"%[label,app.objective.text])
	# A catch outside WATERS while joined goes to the backpack normally.
	var fish_before:=fish_total(person())
	app.session.rates[1].clear()
	await click(OUTSIDE)
	check(person().has("fishing") and int(person().fishing.y)==OUTSIDE.y,"Click casts outside the meet waters (%s): %s"%[label,toast()])
	if not person().has("fishing"):return
	w.state.time=float(person().fishing.ready)+0.1  # PRESET clock
	await refresh()
	app.session.rates[1].clear()
	await click(OUTSIDE)
	check(fish_total(person())==fish_before+1 and int(person().get("fish_caught",0))==caught_before+1,"Outside catch goes to the backpack (%s): %s"%[label,toast()])
	check(int(own().get("records",0))==1,"Outside catch is not a meet record (%s)"%label)
	check(not toast().contains("魚種卡"),"Outside catch shows the ordinary message (%s): %s"%[label,toast()])
	var bag_joined:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_joined:=int(person().coins)
	app._select_tool("hoe")
	# A teammate joins directly in the world and records a fish.
	var buddy:=friend(0,FISH_SPOT)
	var joined:Dictionary=await friend_act(buddy,"fish_meet_join",Meet.SIGN,str(round_id))
	check(bool(joined.get("ok",false)),"Teammate joins (%s): %s"%[label,str(joined)])
	var cast:Dictionary=await friend_act(buddy,"fish_start",Vector2i(55,36),"")
	check(bool(cast.get("ok",false)),"Teammate casts (%s): %s"%[label,str(cast)])
	w.state.time=float((w.state.players[buddy] as Dictionary).fishing.ready)+0.1  # PRESET clock
	var reeled:Dictionary=await friend_act(buddy,"fish_catch",Vector2i(55,36),"")
	check(bool(reeled.get("ok",false)) and str(reeled.get("message","")).contains("魚種卡"),"Teammate's catch is a meet record (%s): %s"%[label,str(reeled)])
	app._fishmeet_menu()
	await settle()
	check(panel_open(),"Menu opens the panel (%s)"%label)
	var second_kind:=Meet.kind_at(round_id,1)
	check(int(own().get("records",0))==2 and label_text("FishMeetProgress").begins_with("記錄 2 / 12"),"Panel counts both records (%s): %s"%[label,label_text("FishMeetProgress")])
	check(label_text("FishMeetCount_"+first_kind).begins_with("記錄") and label_text("FishMeetCount_"+second_kind).begins_with("記錄"),"Species card shows both kinds (%s)"%label)
	var unrecorded:=0
	for kind:String in Meet.KINDS:
		if label_text("FishMeetCount_"+kind)=="尚未記錄":unrecorded+=1
	check(unrecorded==Meet.KINDS.size()-int(own().get("species_count",0)),"Unrecorded kinds say 尚未記錄 (%s): %d"%[label,unrecorded])
	check(label_text("FishMeetPeopleCount")=="2／8 人在場","Two people in (%s): %s"%[label,label_text("FishMeetPeopleCount")])
	check(texts().contains("（我）") and texts().contains(FRIENDS[0]),"Me and the teammate listed (%s)"%label)
	check(label_text("FishMeetPersonDetail_0")=="在場 · 記錄 1 筆" and label_text("FishMeetPersonDetail_1")=="在場 · 記錄 1 筆","Each person's catch count (%s): %s / %s"%[label,label_text("FishMeetPersonDetail_0"),label_text("FishMeetPersonDetail_1")])
	layout_ok("two records "+label)
	await close_panel()
	# Eight participants: the panel still fits.
	var spots:=[Vector2(54.5,35.5),Vector2(53.5,36.5),Vector2(53.5,37.5),Vector2(53.5,38.5),Vector2(53.5,39.5),Vector2(54.5,40.5)]
	for index in range(1,7):
		var token:=friend(index,spots[index-1])
		var result:Dictionary=await friend_act(token,"fish_meet_join",Meet.SIGN,str(round_id))
		check(bool(result.get("ok",false)),"Participant %d joins (%s): %s"%[index+2,label,str(result)])
	check(int(own().get("joined_count",0))==8,"Eight participants joined (%s): %d"%[label,int(own().get("joined_count",0))])
	await stand(SIGN_SPOT)
	app._fishmeet_menu()
	await settle()
	check(control("FishMeetPeople")!=null and control("FishMeetPeople").get_child_count()==8,"Eight participant rows (%s): %d"%[label,control("FishMeetPeople").get_child_count() if control("FishMeetPeople") else -1])
	check(label_text("FishMeetPeopleCount")=="8／8 人在場","Count 8／8 (%s): %s"%[label,label_text("FishMeetPeopleCount")])
	var first_row:=control("FishMeetPerson_0")
	var first_name:Label=first_row.get_child(0) as Label if first_row!=null and first_row.get_child_count()>0 else null
	check(first_name!=null and first_name.text.ends_with("（我）") and label_text("FishMeetPersonDetail_0")=="在場 · 記錄 1 筆","Me first in the list (%s)"%label)
	layout_ok("8 participants "+label)
	focus_ok("8 participants "+label)
	# 離開活動: backpack identical, tracker gone.
	if await press("FishMeetLeave",label):
		check(not bool(own().get("joined",true)) and bool(own().get("active",false)),"離開活動 leaves the running round (%s)"%label)
		check(person().inventory==bag_joined and int(person().coins)==coins_joined,"Whole backpack and coins identical after leaving (%s)"%label)
		check(feedback().contains("背包沒有變動"),"Leave reply mentions the backpack (%s): %s"%[label,feedback()])
		check(label_text("FishMeetPersonDetail_0")=="已離開 · 記錄 1 筆","I am listed first as 已離開 (%s): %s"%[label,label_text("FishMeetPersonDetail_0")])
		check(button("FishMeetJoin")!=null and not button("FishMeetJoin").disabled,"加入 offered again after leaving (7／8, near the sign) (%s)"%label)
		layout_ok("left "+label)
	await close_panel()
	await refresh()
	check(not str(app.objective.text).begins_with("河岸釣魚會"),"HUD tracker stops following after leaving (%s): %s"%[label,app.objective.text])
	check(heading==null or not heading.text.begins_with("河岸釣魚會"),"Tracker heading no longer 河岸釣魚會 (%s)"%label)
	# Time-out: participation tickets paid once, result shown.
	var meet:Dictionary=w.state.fish_meet
	w.state.time=float(meet.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends the round (%s)"%label)
	await refresh()
	app._fishmeet_menu()
	await settle()
	var last:Dictionary=own().get("last",{})
	check(not last.is_empty() and str(last.get("reason",""))=="time","Round settled by time (%s): %s"%[label,str(last)])
	var tickets:=Meet.tickets_for(int(last.get("species",0)),int(last.get("records",0)))
	check(int(own().get("tickets",0))==tickets and int(own().get("rounds",0))==1,"Leaver gets the participation ticket once (%s): %d"%[label,int(own().get("tickets",0))])
	check(label_text("FishMeetLast")=="第 %d 輪 · 時間到 · 記錄 2 / 12 · 魚種 %d / 4"%[round_id,int(last.species)],"Last round line (%s): %s"%[label,label_text("FishMeetLast")])
	check(label_text("FishMeetLastTickets")=="8 人參加 · 每人 %d 張紀念票"%tickets,"Result tickets line (%s): %s"%[label,label_text("FishMeetLastTickets")])
	check(label_text("FishMeetRecord")=="紀念票 %d 張 · 參加 1 場 · 最佳 2 筆"%tickets,"Record line (%s): %s"%[label,label_text("FishMeetRecord")])
	disabled_with_reason("FishMeetStart",label,"整理")
	layout_ok("result "+label)
	w.step(1.0,true)  # another normal tick
	await refresh()
	check(int(own().get("tickets",0))==tickets and label_text("FishMeetRecord").begins_with("紀念票 %d 張"%tickets),"Tickets not paid again (%s)"%label)
	check(person().inventory==bag_joined and int(person().coins)==coins_joined,"Backpack and coins unchanged after settlement (%s)"%label)
	check(not FishUI.waters_marked(app.session.snapshot),"Waters marker off after the round (%s)"%label)
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the panel (%s)"%label)
	# Occupied sign cell: activity paused with the UNAVAILABLE reason.
	w.state.objects[World.key(Meet.SIGN)]={"type":"lamp","owner":id,"items":{}}  # PRESET occupation
	w.state.fish_meet.ready=float(w.state.time)  # PRESET: cooldown over
	await refresh()
	check(not FishUI.on_field(app.session.snapshot) and focus()!=FishUI.POINT,"Occupied sign: no board, no focus (%s): %s"%[label,focus()])
	app._fishmeet_menu()
	await settle()
	disabled_with_reason("FishMeetStart",label,Meet.UNAVAILABLE)
	check(label_text("FishMeetHint")==Meet.UNAVAILABLE,"Hint shows UNAVAILABLE (%s): %s"%[label,label_text("FishMeetHint")])
	layout_ok("occupied "+label)
	await close_panel()
	w.state.objects.erase(World.key(Meet.SIGN))
	for token in friends:
		var p:Dictionary=w.state.players[token]
		p.x=AWAY.x;p.y=AWAY.y;p.erase("fishing")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("fishing-meet-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"釣魚會旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await locked_flow(tag)
		await main_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
