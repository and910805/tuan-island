extends SceneTree
## T071 豐收接力 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_market_stall_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.picnic written directly (false for the locked checks, then true);
##  * state.harvest_relay and every player.harvest_relay erased before each size
##    (a fresh activity, no cooldown);
##  * the local player is teleported by writing region/x/y next to the sign, crate
##    and baskets ("walking" to them is a position write, not real movement input);
##  * extra participants are fake online players: World.add_player + a fake entry in
##    session.peers (as test_community_ui.gd does), positioned by writing x/y, and
##    their own join/pass actions are sent with World.act (they are other people);
##  * world time: to end the round, state.time is set past `ends`, then the normal
##    World.step(1.0) tick settles it.
## REALLY EXERCISED (local player):
##  * the interact key (KEY_E through root.push_input -> main._unhandled_input ->
##    _interact) at the sign opens 「豐收接力」, at the crate picks, at a basket sorts
##    (wrong basket -> the server's rejection in the toast, nothing changes), at the
##    crate with full hands and a teammate beside passes; Esc closes the panel;
##  * 開始一場 / 傳給身旁的夥伴 / 離開活動 are pressed by emitting `pressed` after
##    grabbing focus (real Session.perform -> World -> snapshot -> panel refresh);
##  * the activity menu (渡口派對 · 風鈴接力) entry button opens the panel;
##  * keyboard focus navigation with KEY_RIGHT / KEY_UP through push_input.
## NOT COVERED HERE: world pixels / label drawing (see test_harvest_relay_scene.gd).
const World=preload("res://scripts/world.gd")
const Relay=preload("res://scripts/harvest_relay.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const SIDES:=[Vector2(0.5,1.4),Vector2(1.4,0.5),Vector2(-0.4,0.5),Vector2(0.5,-0.4)]
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
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
	print("HARVEST_RELAY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE HARVEST_RELAY_UI "+message)

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
	return is_instance_valid(app.modal) and layout_meta()=="harvest_relay"

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
	return HarvestUI.own(app.session.snapshot)

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

func standable(tile:Vector2i)->bool:
	return World.land(tile) and not w.blocked(tile)

## Teleport (PRESET) next to a site so that it is the focused interaction and inside
## the server's reach (sign 3.2, crate/basket 1.6).
func stand_at(site:String,label:String)->bool:
	var cell:=HarvestUI.site_cell(site)
	var reach:=Relay.SIGN_REACH if site=="sign" else Relay.HAND_REACH
	for off:Vector2 in SIDES:
		var at:Vector2=Vector2(cell)+off
		if not standable(Vector2i(at.floor())):continue
		if at.distance_to(Vector2(cell)+Vector2(0.5,0.5))>reach:continue
		await stand(at)
		if focus()=="harvest:"+site:
			if off!=SIDES[0]:note("%s: standing at offset %s (%s)"%[site,str(off),label])
			return true
	check(false,"Some side of %s %s focuses harvest:%s (%s): last focus %s"%[site,str(cell),site,label,focus()])
	return false

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

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

func disabled_with_reason(name:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.disabled and not b.tooltip_text.is_empty(),"%s disabled with a reason (%s): %s"%[name,label,b.tooltip_text if b else "missing"])

func close_panel()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func public_id(token:String)->String:
	return token.sha256_text().left(16)

# ------------------------------------------------------------------- layout --

func layout_ok(label:String)->void:
	if not panel_open():
		check(false,"Panel open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Panel fits the viewport (%s) %s"%[label,rect_info(null)])
	check(modal.size.x<=1000.5 and modal.size.y<=620.5,"Panel within 1000×620 (%s) %s"%[label,str(modal.size)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer panel needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for name in ["HarvestStatus","HarvestProgress","HarvestTime","HarvestRule","HarvestCarry","HarvestBagNote","HarvestPeopleCount","HarvestPeople","HarvestStart","HarvestJoin","HarvestLeave","HarvestPass","HarvestHint","HarvestLast","HarvestRecord"]:
		var c:=control(name)
		check(c!=null and c.is_visible_in_tree(),"%s present (%s)"%[name,label])
		if c==null:continue
		check(view_rect.encloses(c.get_global_rect()) and modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside viewport and panel (%s) %s"%[name,label,rect_info(c)])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(view_rect.encloses(c.get_global_rect()),"%s inside the viewport (%s) %s"%[c.name,label,rect_info(c)])
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the panel (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the panel (%s)"%label)
	for name in ["HarvestColumns","HarvestActions","HarvestBottom"]:
		var row:=control(name)
		if row!=null:check(row.get_combined_minimum_size().x<=row.size.x+0.5,"%s does not overflow (%s)"%[name,label])
	check(texts().contains("不會放進背包") and texts().contains("背包維持原樣") and texts().contains("參加紀念票"),"Panel states the backpack is untouched and leaving keeps it (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and not (owner as BaseButton).disabled,"Keyboard focus is on an enabled button inside the panel (%s): %s"%[label,str(owner.name) if owner else "none"])

# ------------------------------------------------------------------- fixture --

func reset_activity()->void:
	w.state.erase("harvest_relay")  # PRESET fresh activity
	for token in w.state.players:(w.state.players[token] as Dictionary).erase("harvest_relay")

func set_picnic(on:bool)->void:
	w.state.picnic=on
	await refresh()

## PRESET: a fake online player (other person) standing at `at`.
func friend(index:int,at:Vector2)->String:
	var token:="harvest-friend-%d"%index
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

# --------------------------------------------------------------------- flows --

func locked_flow(label:String)->void:
	await close_panel()
	reset_activity()
	await set_picnic(false)
	check(not HarvestUI.on_field(app.session.snapshot),"Activity field not available before the picnic (%s)"%label)
	check(not bool(own().get("unlocked",true)),"own_harvest says locked before the picnic (%s)"%label)
	for site:String in HarvestUI.SITES:
		await stand(Vector2(HarvestUI.site_cell(site))+SIDES[0])
		check(not focus().begins_with("harvest:"),"No harvest focus next to %s before the picnic (%s): %s"%[site,label,focus()])
	var drawn:=false
	for entry in app.view.world_labels:
		if str(entry.id).begins_with("harvest:"):drawn=true
	check(not drawn,"No harvest world label before the picnic (%s)"%label)
	await stand(Vector2(Relay.SIGN)+SIDES[0])
	await key(KEY_E)
	check(not panel_open(),"E at the sign spot before the picnic opens no 豐收接力 (%s)"%label)
	await close_panel()
	# Activity menu entry explains the lock and opens the panel with the lock text.
	app._festival_menu()
	await settle()
	var entry:=button("HarvestRelayEntry")
	check(entry!=null and entry.text.contains("渡口野餐後開放"),"Activity menu lists 豐收接力 with its lock (%s): %s"%[label,entry.text if entry else "missing"])
	if entry!=null:
		entry.pressed.emit()
		await settle()
		check(panel_open() and label_text("HarvestLocked")==Relay.LOCKED,"Entry opens the panel showing the lock (%s): %s"%[label,label_text("HarvestLocked")])
		check(control("HarvestStart")==null,"No start button while locked (%s)"%label)
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the locked panel (%s)"%label)

func main_flow(label:String)->void:
	await set_picnic(true)
	var s:Dictionary=app.session.snapshot
	check(HarvestUI.on_field(s) and bool(own().get("available",false)),"Activity field available after the picnic (%s)"%label)
	check(own().get("sign")==Relay.SIGN and own().get("crate")==Relay.CRATE and own().get("baskets",{}).get("root")==Relay.BASKETS.root,"own_harvest reports the server's cells (%s)"%label)
	# Interact key at the sign opens the panel.
	if not await stand_at("sign",label):return
	check(HarvestUI.site_title(app.session.snapshot,app.session.own_id,"sign",true)=="豐收接力・打開活動","Sign prompt says it opens the activity (%s)"%label)
	await key(KEY_E)
	check(panel_open(),"Interact at the sign opens 豐收接力 (%s) texts=%s"%[label,texts().left(60).replace("\n"," | ")])
	if not panel_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the panel is open (%s)"%label)
	focus_ok("idle "+label)
	check(root.gui_get_focus_owner()==button("HarvestStart"),"開始一場 focused first (%s)"%label)
	layout_ok("idle "+label)
	check(label_text("HarvestStatus")=="目前沒有進行中的一輪" and label_text("HarvestTime")=="可以開始","Idle status (%s): %s / %s"%[label,label_text("HarvestStatus"),label_text("HarvestTime")])
	check(label_text("HarvestLast")=="還沒有完成的一輪","No last round yet (%s)"%label)
	disabled_with_reason("HarvestJoin",label)
	disabled_with_reason("HarvestLeave",label)
	disabled_with_reason("HarvestPass",label)
	var bag_before:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_before:=int(person().coins)
	# 開始一場.
	if not await press("HarvestStart",label):return
	var round_id:=int(own().get("round",0))
	check(bool(own().active) and bool(own().joined) and round_id>=1,"開始一場 starts and joins a round (%s): %s"%[label,str(own().get("round"))])
	check(feedback().contains("豐收接力開始"),"Server reply shown in the panel (%s): %s"%[label,feedback()])
	check(label_text("HarvestStatus")=="第 %d 輪進行中"%round_id and label_text("HarvestTime")=="剩 180 秒","Active status and time (%s): %s %s"%[label,label_text("HarvestStatus"),label_text("HarvestTime")])
	disabled_with_reason("HarvestStart",label)
	check(button("HarvestLeave")!=null and not button("HarvestLeave").disabled,"離開活動 enabled once joined (%s)"%label)
	focus_ok("started "+label)
	check(label_text("HarvestCarry")=="空手 → 到模型菜箱拿一個","Hands empty after joining (%s): %s"%[label,label_text("HarvestCarry")])
	layout_ok("started "+label)
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the panel (%s)"%label)
	# HUD tracker.
	await refresh()
	check(str(app.objective.text).begins_with("豐收接力 0 / 24 · 剩 180 秒"),"HUD tracker shows the round (%s): %s"%[label,app.objective.text])
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	check(heading!=null and heading.text.begins_with("豐收接力"),"Tracker heading follows 豐收接力 (%s)"%label)
	# Crate: interact picks.
	if not await stand_at("crate",label):return
	check(HarvestUI.site_title(app.session.snapshot,app.session.own_id,"crate",true)=="模型菜箱・拿一個蔬菜","Crate prompt says it picks (%s)"%label)
	await key(KEY_E)
	var kind:=Relay.kind_at(round_id,0)
	check(str(own().get("carry",""))==kind,"Interact at the crate picks %s (%s): %s"%[kind,label,str(own().get("carry"))])
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Picking never touches the backpack or coins (%s)"%label)
	check(toast().contains("拿到"),"Pick reply in the toast (%s): %s"%[label,toast()])
	await refresh()
	var right:=Relay.basket_of(kind)
	check(str(app.objective.text).contains("手上：%s → %s"%[Relay.kind_name(kind),HarvestUI.basket_label(right)]),"HUD says what is in my hands and where it goes (%s): %s"%[label,app.objective.text])
	var pass_hud:=app.hud.find_child("TrackerHarvestPass",true,false) as Button
	check(pass_hud!=null and pass_hud.is_visible_in_tree(),"Tracker offers 傳給身旁的夥伴 while carrying (%s)"%label)
	# Wrong basket: the server rejects, nothing changes.
	var wrong:="leaf" if right!="leaf" else "fruit"
	if not await stand_at(wrong,label):return
	check(HarvestUI.site_title(app.session.snapshot,app.session.own_id,wrong,true).contains("要放"+HarvestUI.basket_label(right)),"Wrong basket prompt warns (%s)"%label)
	var delivered_before:=int(own().get("delivered",0))
	await key(KEY_E)
	var rejection:=Relay.WRONG_BASKET%[Relay.kind_name(kind),Relay.BASKET_NAMES[right],Relay.BASKET_NAMES[right]]
	check(toast()==rejection,"Wrong basket shows the server's rejection (%s): %s"%[label,toast()])
	check(str(own().get("carry",""))==kind and int(own().get("delivered",0))==delivered_before,"Wrong basket changes nothing (%s)"%label)
	# Right basket: sorted.
	if not await stand_at(right,label):return
	check(HarvestUI.site_title(app.session.snapshot,app.session.own_id,right,true)==HarvestUI.basket_label(right)+"・放入"+Relay.kind_name(kind),"Right basket prompt says 放入 (%s)"%label)
	await key(KEY_E)
	check(str(own().get("carry",""))=="" and int(own().get("delivered",0))==delivered_before+1,"Interact at the right basket sorts (%s): %s"%[label,str(own().get("delivered"))])
	check(toast().contains("放進"),"Sort reply in the toast (%s): %s"%[label,toast()])
	# Pass: a second participant (fake online player) beside the crate.
	if not await stand_at("crate",label):return
	var mine:=Vector2(float(person().x),float(person().y))
	var buddy_spot:=mine+Vector2(1.0,0.0)
	if Vector2(buddy_spot).distance_to(Vector2(Relay.SIGN)+Vector2(0.5,0.5))>Relay.SIGN_REACH:buddy_spot=mine+Vector2(0.9,0.6)
	var buddy:=friend(0,buddy_spot)
	var joined:Dictionary=await friend_act(buddy,"harvest_join",Relay.SIGN,str(round_id))
	check(bool(joined.get("ok",false)),"Second participant joins (%s): %s"%[label,str(joined)])
	await key(KEY_E)
	var second:=Relay.kind_at(round_id,1)
	check(str(own().get("carry",""))==second,"Second pick: %s (%s)"%[second,label])
	check(HarvestUI.pass_ready(app.session.snapshot,app.session.own_id),"Client sees an empty-handed teammate within reach (%s)"%label)
	# Entry from the activity menu opens the panel from anywhere.
	app._festival_menu()
	await settle()
	var entry:=button("HarvestRelayEntry")
	check(entry!=null and entry.text.contains("豐收接力"),"Activity menu lists 豐收接力 (%s)"%label)
	if entry!=null:
		entry.pressed.emit()
		await settle()
	check(panel_open(),"Activity menu entry opens the 豐收接力 panel (%s)"%label)
	if not panel_open():return
	var pass_button:=button("HarvestPass")
	var leave_button:=button("HarvestLeave")
	check(pass_button!=null and not pass_button.disabled,"傳給身旁的夥伴 enabled with a teammate beside (%s)"%label)
	check(label_text("HarvestCarry").contains(Relay.kind_name(second)) and label_text("HarvestCarry").contains(Relay.BASKET_NAMES[Relay.basket_of(second)]),"Panel shows my hands and basket (%s): %s"%[label,label_text("HarvestCarry")])
	# Focus neighbours: left/right walk the enabled action buttons, up reaches 關閉.
	if pass_button!=null and leave_button!=null:
		check(leave_button.get_node_or_null(leave_button.focus_neighbor_right)==pass_button and pass_button.get_node_or_null(pass_button.focus_neighbor_right)==leave_button,"Focus neighbours chain 離開活動 ↔ 傳給身旁的夥伴 (%s)"%label)
		check(button("HarvestStart").focus_mode==Control.FOCUS_NONE,"Disabled 開始一場 is skipped by focus navigation (%s)"%label)
		leave_button.grab_focus();await settle()
		await key(KEY_RIGHT)
		check(root.gui_get_focus_owner()==pass_button,"KEY_RIGHT moves focus 離開活動 -> 傳給身旁的夥伴 (%s): %s"%[label,str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() else "none"])
		await key(KEY_UP)
		var up:=root.gui_get_focus_owner() as Button
		check(up!=null and up.text.contains("關閉"),"KEY_UP reaches 關閉 (%s): %s"%[label,up.text if up else "none"])
		await key(KEY_DOWN)
		check(root.gui_get_focus_owner()==button("HarvestLeave"),"KEY_DOWN from 關閉 returns to the first action (%s)"%label)
	if await press("HarvestPass",label):
		var buddy_entry:Dictionary=app.session.snapshot.get("harvest_relay",{}).get("participants",{}).get(public_id(buddy),{})
		check(str(own().get("carry",""))=="" and str(buddy_entry.get("carry",""))==second,"傳給身旁的夥伴 hands %s to the teammate (%s): %s"%[second,label,str(buddy_entry)])
		check(HarvestUI.carried(app.session.snapshot,public_id(buddy))==second,"Teammate's carried vegetable is in the public snapshot for drawing (%s)"%label)
		check(feedback().contains("傳給"),"Pass reply shown (%s): %s"%[label,feedback()])
		focus_ok("after pass "+label)
		layout_ok("after pass "+label)
	await close_panel()
	# Teammate passes back; with full hands, interact at the crate passes contextually.
	var back:Dictionary=await friend_act(buddy,"harvest_pass",Relay.SIGN,"")
	check(bool(back.get("ok",false)) and str(own().get("carry",""))==second,"Teammate passes back (%s): %s"%[label,str(back)])
	check(HarvestUI.site_title(app.session.snapshot,app.session.own_id,"crate",true)=="傳給身旁的夥伴","Crate prompt offers the pass with full hands (%s)"%label)
	await key(KEY_E)
	check(str(own().get("carry",""))=="","Interact at the crate with full hands passes to the teammate (%s): %s"%[label,toast()])
	# Eight participants: the panel still fits.
	for index in range(1,7):
		var spot:=Vector2(Relay.SIGN)+Vector2(0.5,0.5)+Vector2(cos(index*0.9),sin(index*0.9))*1.5
		var token:=friend(index,spot)
		var result:Dictionary=await friend_act(token,"harvest_join",Relay.SIGN,str(round_id))
		check(bool(result.get("ok",false)),"Participant %d joins (%s): %s"%[index+2,label,str(result)])
	check(int(own().get("joined_count",0))==8,"Eight participants joined (%s): %d"%[label,int(own().get("joined_count",0))])
	app._harvest_menu()
	await settle()
	check(control("HarvestPeople")!=null and control("HarvestPeople").get_child_count()==8,"Eight participant rows (%s): %d"%[label,control("HarvestPeople").get_child_count() if control("HarvestPeople") else -1])
	check(label_text("HarvestPeopleCount")=="8／8 人在場","Count 8／8 (%s): %s"%[label,label_text("HarvestPeopleCount")])
	check(texts().contains(FRIENDS[0]+"") and texts().contains("（我）"),"Participant names listed (%s)"%label)
	layout_ok("8 participants "+label)
	focus_ok("8 participants "+label)
	# 離開活動: hands emptied, backpack and coins exactly as before joining.
	if await press("HarvestLeave",label):
		check(not bool(own().get("joined",true)) and bool(own().get("active",false)),"離開活動 leaves the running round (%s)"%label)
		check(person().inventory==bag_before and int(person().coins)==coins_before,"Whole backpack and coins equal the pre-join values (%s)"%label)
		check(feedback().contains("背包沒有變動"),"Leave reply mentions the backpack (%s): %s"%[label,feedback()])
		check(button("HarvestJoin")!=null and not button("HarvestJoin").disabled,"加入 offered again after leaving (7／8, near the sign) (%s)"%label)
		layout_ok("left "+label)
	await refresh()
	check(not str(app.objective.text).begins_with("豐收接力"),"HUD tracker stops following after leaving (%s): %s"%[label,app.objective.text])
	# End of the round: participation ticket paid once, result shown.
	var relay:Dictionary=w.state.harvest_relay
	w.state.time=float(relay.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends the round (%s)"%label)
	await refresh()
	var last:Dictionary=own().get("last",{})
	check(not last.is_empty() and str(last.get("reason",""))=="time","Round settled by time (%s): %s"%[label,str(last)])
	var tickets:=Relay.tickets_for(int(last.get("delivered",0)))
	check(int(own().get("tickets",0))==tickets and int(own().get("rounds",0))==1,"Leaver still gets the participation ticket once (%s): %d"%[label,int(own().get("tickets",0))])
	check(panel_open(),"Panel survives the settlement refresh (%s)"%label)
	check(label_text("HarvestLast")=="第 %d 輪 · 時間到 · 完成 %d / 24 · 接力 %d"%[round_id,int(last.delivered),int(last.relays)],"Last round line (%s): %s"%[label,label_text("HarvestLast")])
	check(label_text("HarvestRecord")=="紀念票 %d 張 · 參加 1 場 · 最佳完成 %d 個"%[tickets,int(last.delivered)],"Record line (%s): %s"%[label,label_text("HarvestRecord")])
	check(button("HarvestStart")!=null and button("HarvestStart").disabled and button("HarvestStart").tooltip_text.contains("補貨"),"Cooldown reason on 開始一場 (%s): %s"%[label,button("HarvestStart").tooltip_text if button("HarvestStart") else "?"])
	layout_ok("result "+label)
	check(w.step(1.0,true),"Another tick (%s)"%label)
	await refresh()
	check(int(own().get("tickets",0))==tickets,"Ticket not paid again (%s)"%label)
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Backpack and coins still unchanged after settlement (%s)"%label)
	await key(KEY_ESCAPE)
	check(not panel_open(),"Esc closes the panel (%s)"%label)
	# Fake participants leave the world view for the next size.
	for token in friends:(w.state.players[token] as Dictionary).region=World.REGIONS.HOME

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("harvest-relay-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"豐收旅人",path)!=OK:check(false,"Host starts");finish();return
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
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
