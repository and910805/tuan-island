extends SceneTree
## 第 40 章「定量分區配水」水塔頁設定列 UI test (headless) at 1024×640 and 1280×800.
## Same harness as test_water_tower_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (same as the reference suite);
##  * UNLOCK FIXTURE written directly (same as test_water_tower_ui.gd: lanyang_life,
##    history_memory, state.lanyang_revisit completed);
##  * the local player is teleported by writing region/x/y (no walking);
##  * home network written as objects (same cells as the reference):
##      y=24:  S_A(44)  P1(45)  TOWER(46)  GATE(47)  S_N(48)  TANK(49)
##    plus another player's tower (46,28) "鄰居阿岸" (World.add_player), water 30 / 只蓄水;
##    state.removed on tiles with a base resource;
##  * WATER written directly for the quota ticks: tank water 0, tower water 60, sprinkler
##    water 9 / 12 / 0 (standing in for sprinklers having used their water);
##  * four extra sprinklers at (44,23) (45,23) (48,23) (49,23) are written (full, 12) for
##    the largest consumer list, then erased; S_A is erased once for the empty-list case;
##  * the neighbour's tower gets reserve 24 / quota 8 / quota_day today / quota_used 3
##    written directly (its owner is not a connected player);
##  * state.time is written forward only if the world clock is within 120 min of the
##    next world-day boundary (so every quota tick stays on one world day);
##  * bag count of water_tower_kit is written to 0 before the remove check;
##  * session rate buckets / action_clock are cleared before each action;
##  * network ticks run through a real World.step after writing
##    state.next_network_check = state.time (the session's physics step is off);
##  * keyboard focus is put on a setting button with grab_focus() before KEY_ENTER.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact opens the tower
##    page (mine / the neighbour's); KEY_ESCAPE closes;
##  * TowerReserveLess/More and TowerQuotaLess/More through their `pressed` signal
##    (TowerUI._step -> Session.perform("tower_set") -> World -> snapshot -> in-place update);
##    KEY_ENTER on a focused setting button and on the focused TowerToggle;
##  * a real mouse click on the visitor's disabled 「＋」; a direct Session.perform
##    tower_set on the neighbour's tower (refusal, state unchanged);
##  * gate_mode closed/open and remove (my tower) are real Session.perform calls.
## NOT COVERED HERE: world pixels; gamepad; the non-preview layout; a second connected
## client; reserve's effect on refills (rules suites cover it).
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const TowerUI=preload("res://scripts/water_tower_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="tower-quota-ui-neighbour-71c4"
const S_A:=Vector2i(44,24)
const P1:=Vector2i(45,24)
const TOWER:=Vector2i(46,24)
const GATE:=Vector2i(47,24)
const S_N:=Vector2i(48,24)
const TANK:=Vector2i(49,24)
const OTHER_TOWER:=Vector2i(46,28)
const EXTRA:=[Vector2i(44,23),Vector2i(45,23),Vector2i(48,23),Vector2i(49,23)]
const TOWER_SPOT:=Vector2(46.3,25.6)
const OTHER_SPOT:=Vector2(46.5,29.4)
const SETTING_BUTTONS:=["TowerReserveLess","TowerReserveMore","TowerQuotaLess","TowerQuotaMore"]
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
	print("WATER_TOWER_QUOTA_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE WATER_TOWER_QUOTA_UI "+message)

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
	return layout_name()==TowerUI.LAYOUT

func is_disabled(name:String)->bool:
	var b:=button(name)
	return b!=null and b.disabled

func is_enabled(name:String)->bool:
	var b:=button(name)
	return b!=null and not b.disabled

func modal_id()->int:
	return (app.modal as Object).get_instance_id() if is_instance_valid(app.modal) else 0

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func consumer_lines()->Array:
	var out:=[]
	var list:=control("TowerConsumers")
	if list==null:return out
	for child in list.get_children():
		if child is Label and not (child as Node).is_queued_for_deletion() and child.name.begins_with("TowerConsumer_"):out.append((child as Label).text)
	out.sort()
	return out

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

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func stand(at:Vector2,region:String=World.REGIONS.HOME)->void:
	var p:Dictionary=person()
	p.region=region
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func act_key(code:Key)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await key(code)
	await refresh()

func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

func perform(action:String,cell:Vector2i,extra:String="")->void:
	app.action_clock=0
	app.session.rates[1].clear()
	app.session.perform(action,cell,extra)
	await refresh()

func mouse_at(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point
		event.global_position=point
		root.push_input(event,true)
		await process_frame

func click_control(c:Control)->void:
	if c==null:return
	app.action_clock=0
	app.session.rates[1].clear()
	await mouse_at(c.get_global_rect().get_center())
	await settle()
	await refresh()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func k(c:Vector2i)->String:
	return World.key(c)

func obj(c:Vector2i)->Dictionary:
	return w.state.objects.get(k(c),{})

func snap_obj(c:Vector2i)->Dictionary:
	var objects:Variant=app.session.snapshot.get("objects",{})
	if not objects is Dictionary:return {}
	var o:Variant=(objects as Dictionary).get(k(c),{})
	if o is Dictionary:return o
	return {}

func canon(d:Dictionary)->String:
	return JSON.stringify(d,"",true)

func today()->int:
	return Industry.tower_day(float(w.state.time))

## Real network tick: World.step after making the network check due.
func tick()->void:
	w.state.next_network_check=float(w.state.time)  # PRESET (step timing)
	w.step(1.0,true)
	await refresh()

## Press a page button through its `pressed` signal (what a click / Enter emits).
func press(name:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.is_visible_in_tree() and not b.disabled,"%s visible and enabled before the press (%s)"%[name,label])
	if b==null:return
	app.action_clock=0
	app.session.rates[1].clear()
	b.pressed.emit()
	await refresh()

## Put keyboard focus on `name` and press KEY_ENTER through root.push_input.
func enter_on(name:String,label:String,with_pad:=false)->void:
	var b:=button(name)
	check(b!=null and not b.disabled,"%s can take focus (%s)"%[name,label])
	if b==null:return
	b.grab_focus()
	await settle()
	check(focused_name()==name,"Focus on %s before Enter (%s): %s"%[name,label,focused_name()])
	if with_pad:
		app.action_clock=0
		app.session.rates[1].clear()
		for pressed in [true,false]:
			var event:=InputEventJoypadButton.new()
			event.button_index=JOY_BUTTON_A
			event.pressed=pressed
			root.push_input(event)
		await refresh()
	else:await act_key(KEY_ENTER)

## Disclosed unlock fixture (copied from test_water_tower_ui.gd).
func write_unlock()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":0,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}

func sprinkler(water:int=0)->Dictionary:
	return {"type":"sprinkler","owner":id,"items":{},"water":water,"enabled":true,"next_water":0.0,"last_water":-1.0}

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func write_network()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in [S_A,P1,TOWER,GATE,S_N,TANK,OTHER_TOWER]:clear_tile(c)
	o[k(S_A)]=sprinkler();o[k(S_N)]=sprinkler()
	o[k(P1)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(TOWER)]={"type":"water_tower","owner":id,"items":{},"water":0,"enabled":true}
	o[k(GATE)]={"type":"diversion_gate","owner":id,"items":{},"mode":"open"}
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":48}
	o[k(OTHER_TOWER)]={"type":"water_tower","owner":OTHER,"items":{},"water":30,"enabled":false}

func erase_home()->void:
	for c:Vector2i in [S_A,P1,TOWER,GATE,S_N,TANK,OTHER_TOWER]:w.state.objects.erase(k(c))
	for c:Vector2i in EXTRA:w.state.objects.erase(k(c))

## Keep every quota tick of this size on one world day.
func ensure_midday()->void:
	var t:=float(w.state.time)
	var into:=fmod(t,Industry.TOWER_DAY)
	if into>Industry.TOWER_DAY-120.0:
		w.state.time=(floorf(t/Industry.TOWER_DAY)+1.0)*Industry.TOWER_DAY+60.0  # PRESET (clock)
		note("state.time moved from %.1f to %.1f (too close to a world-day boundary)"%[t,float(w.state.time)])

func reset()->void:
	await close_page()
	write_unlock()
	erase_home()
	bag()[Industry.TOWER_KIT]=0  # PRESET
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	write_network()
	ensure_midday()
	await refresh()

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, no ellipsis (same rules as test_water_tower_ui.gd).
func layout_ok(label:String)->void:
	if layout_name()!=TowerUI.LAYOUT:
		check(false,"Tower page open for layout: %s (got %s)"%[label,layout_name()])
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	var content:=control("ModalContent")
	var need:float=content.get_combined_minimum_size().y if content!=null else -1.0
	note("layout %s viewport=%s modal=%s content_min_h=%.0f cap=%.0f"%[label,str(view_rect.size),str(modal.size),need,view_rect.size.y-40.0])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect or c is ProgressBar):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	if shown("TowerReserveRow"):rows_ok(label)

func no_overlap(a:Control,b:Control)->bool:
	if a==null or b==null or not b.is_visible_in_tree() or b.size.y<1.0 or b.size.x<1.0:return true
	return not a.get_global_rect().grow(-0.5).intersects(b.get_global_rect().grow(-0.5))

## The two settings rows: inside their card, 「－」「＋」 to the right of the label in
## order, label on one line, no overlap with the other lines of the card or each other.
func rows_ok(label:String)->void:
	var specs:=[["TowerReserve","TowerRefillCard",["TowerRefillTitle","TowerRefill","TowerTanks"]],
		["TowerQuota","TowerSupplyCard",["TowerSupplyTitle","TowerConsumers"]]]
	for spec:Array in specs:
		var row_id:String=spec[0]
		var card:=control(str(spec[1]))
		var row:=control(row_id+"Row")
		var text:=control(row_id) as Label
		var less:=button(row_id+"Less")
		var more:=button(row_id+"More")
		check(card!=null and row!=null and text!=null and less!=null and more!=null,"%s row parts exist (%s)"%[row_id,label])
		if card==null or row==null or text==null or less==null or more==null:continue
		var cr:=card.get_global_rect().grow(0.5)
		check(cr.encloses(row.get_global_rect()),"%sRow inside %s (%s) row=%s card=%s"%[row_id,card.name,label,str(row.get_global_rect()),str(card.get_global_rect())])
		check(cr.encloses(less.get_global_rect()) and cr.encloses(more.get_global_rect()),"%s －/＋ inside %s (%s) less=%s more=%s"%[row_id,card.name,label,str(less.get_global_rect()),str(more.get_global_rect())])
		check(row.get_global_rect().grow(0.5).encloses(text.get_global_rect()),"%s label inside its row (%s)"%[row_id,label])
		check(text.get_global_rect().end.x<=less.get_global_rect().position.x+0.5 and less.get_global_rect().end.x<=more.get_global_rect().position.x+0.5,"%s: label, －, ＋ left to right (%s)"%[row_id,label])
		check(less.size.x>=39.5 and less.size.y>=29.5 and more.size.x>=39.5 and more.size.y>=29.5,"%s buttons keep 40×30 (%s): %s %s"%[row_id,label,str(less.size),str(more.size)])
		check(text.get_line_count()==1,"%s label on one line (%s): %d lines 「%s」"%[row_id,label,text.get_line_count(),text.text])
		check(text.size.x>=40.0,"%s label has room (%s): %.0f"%[row_id,label,text.size.x])
		for sib_name in spec[2]:
			var sib:=control(str(sib_name))
			check(no_overlap(row,sib),"%sRow does not overlap %s (%s) row=%s other=%s"%[row_id,str(sib_name),label,str(row.get_global_rect()),str(sib.get_global_rect()) if sib!=null else "null"])
	var reserve_row:=control("TowerReserveRow")
	var quota_row:=control("TowerQuotaRow")
	check(no_overlap(reserve_row,quota_row),"The two settings rows do not overlap (%s)"%label)
	var tanks:=control("TowerTanks")
	if reserve_row!=null and tanks!=null:
		check(reserve_row.get_global_rect().position.y>=tanks.get_global_rect().end.y-0.5,"Reserve row below the tank count (%s)"%label)
	var title:=control("TowerSupplyTitle")
	var list:=control("TowerConsumers")
	if quota_row!=null and title!=null and list!=null:
		check(quota_row.get_global_rect().position.y>=title.get_global_rect().end.y-0.5,"Quota row below the supply title (%s)"%label)
		check(list.size.y<1.0 or quota_row.get_global_rect().end.y<=list.get_global_rect().position.y+0.5,"Quota row above the consumer list (%s)"%label)
	var refill_card:=control("TowerRefillCard")
	var supply_card:=control("TowerSupplyCard")
	if refill_card!=null and supply_card!=null:
		check(refill_card.get_global_rect().end.y<=supply_card.get_global_rect().position.y+0.5,"補水 card above the supply card (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree() and not (owner as BaseButton).disabled,"Keyboard focus on a visible enabled button inside the page (%s): %s"%[label,focused_name()])

# ----------------------------------------------------------- expectations --

## Buttons of one settings row for the owner.
func buttons_state(tag:String,row_id:String,less_on:bool,more_on:bool)->void:
	var less:=button(row_id+"Less")
	var more:=button(row_id+"More")
	check(less!=null and more!=null,"%s buttons exist (%s)"%[row_id,tag])
	if less==null or more==null:return
	check(less.disabled!=less_on,"%sLess %s (%s)"%[row_id,"enabled" if less_on else "disabled",tag])
	check(more.disabled!=more_on,"%sMore %s (%s)"%[row_id,"enabled" if more_on else "disabled",tag])
	check(shown(row_id+"Row") and less.is_visible_in_tree() and more.is_visible_in_tree(),"%s row and buttons visible (%s)"%[row_id,tag])
	check(less.text=="－" and more.text=="＋","%s captions 「－」「＋」 (%s): %s %s"%[row_id,tag,less.text,more.text])
	check(less.focus_mode==Control.FOCUS_ALL and more.focus_mode==Control.FOCUS_ALL,"%s buttons focusable (%s)"%[row_id,tag])
	var help:String=TowerUI.RESERVE_HELP if row_id=="TowerReserve" else TowerUI.QUOTA_HELP
	check(less.tooltip_text==help and more.tooltip_text==help and control(row_id).tooltip_text==help,"%s tooltips explain the setting (%s)"%[row_id,tag])

## Page labels, button states, server object and snapshot object for my tower.
func expect(label:String,reserve:int,quota:int,used:int)->void:
	var tag:="reserve %d quota %d used %d, %s"%[reserve,quota,used,label]
	check(label_text("TowerReserve")==TowerUI.reserve_text(reserve),"Reserve label (%s): %s"%[tag,label_text("TowerReserve")])
	check(label_text("TowerQuota")==TowerUI.quota_text(quota,used),"Quota label (%s): %s"%[tag,label_text("TowerQuota")])
	var ri:int=Industry.TOWER_RESERVES.find(reserve)
	var qi:int=Industry.TOWER_QUOTAS.find(quota)
	buttons_state(tag,"TowerReserve",ri>0,ri<Industry.TOWER_RESERVES.size()-1)
	buttons_state(tag,"TowerQuota",qi>0,qi<Industry.TOWER_QUOTAS.size()-1)
	for pair:Array in [["server",obj(TOWER)],["snapshot",snap_obj(TOWER)]]:
		var where:String=pair[0]
		var o:Dictionary=pair[1]
		check(not o.is_empty(),"Tower object in the %s (%s)"%[where,tag])
		if reserve==0:check(not o.has("reserve"),"No reserve field in the %s (%s): %s"%[where,tag,str(o)])
		else:check(int(o.get("reserve",-1))==reserve,"%s reserve %d (%s): %s"%[where,reserve,tag,str(o.get("reserve"))])
		if quota==0:
			check(not o.has("quota") and not o.has("quota_day") and not o.has("quota_used"),"No quota fields in the %s (%s): %s"%[where,tag,str(o)])
		else:
			check(int(o.get("quota",-1))==quota and int(o.get("quota_used",-1))==used and int(o.get("quota_day",-1))==today(),"%s quota %d / used %d / today (%s): %s"%[where,quota,used,tag,str(o)])

func same_page(before:int,label:String)->void:
	check(page_open() and modal_id()==before,"Same tower page instance, updated in place (%s)"%label)

func set_step(row_id:String,field:String,dir:String,value:int,reserve:int,quota:int,used:int,label:String,before:int)->void:
	var node:=control(row_id)
	await press(row_id+dir,label)
	check(feedback()==Industry.tower_set_message("%s:%d"%[field,value]),"Server reply for %s:%d (%s): %s"%[field,value,label,feedback()])
	expect(label,reserve,quota,used)
	same_page(before,label)
	check(control(row_id)==node,"%s label node kept (%s)"%[row_id,label])
	if shown("TowerReserveRow"):rows_ok("%s %s:%d %s"%[dir,field,value,label])

# --------------------------------------------------------------------- flows --

func open_mine(label:String)->bool:
	await stand(TOWER_SPOT)
	check(str(app.view.interaction_focus())==k(TOWER),"Tower focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(page_open(),"E at my tower opens the tower page (%s): %s"%[label,layout_name()])
	return page_open()

func fresh_flow(label:String)->void:
	check(label_text("TowerReserve")==TowerUI.reserve_text(0) and label_text("TowerReserve")=="桶水保留：不保留","Fresh reserve label (%s): %s"%[label,label_text("TowerReserve")])
	check(label_text("TowerQuota")==TowerUI.quota_text(0,0) and label_text("TowerQuota")=="每日配水：不限","Fresh quota label (%s): %s"%[label,label_text("TowerQuota")])
	expect("fresh "+label,0,0,0)
	check(shown("TowerReserveRow") and shown("TowerQuotaRow"),"Both settings rows shown (%s)"%label)
	var rr:=control("TowerReserveRow")
	var qr:=control("TowerQuotaRow")
	check(rr!=null and rr.get_parent()!=null and rr.get_parent().get_parent()==control("TowerRefillCard"),"Reserve row lives in the 補水 card (%s)"%label)
	check(qr!=null and qr.get_parent()!=null and qr.get_parent().get_parent()==control("TowerSupplyCard"),"Quota row lives in the supply card (%s)"%label)
	check(focused_name()=="TowerToggle","Focus still starts on the toggle (%s): %s"%[label,focused_name()])
	check(label_text("TowerSupplyTitle")=="出水會送到" and label_text("TowerSupplyTitle")==TowerUI.SUPPLY_TITLE[true],"Supply title while 出水 (%s): %s"%[label,label_text("TowerSupplyTitle")])
	check(label_text("TowerAbout")==TowerUI.ABOUT,"About text is TowerUI.ABOUT (%s)"%label)
	check(feedback()=="Esc 回到島上","Owner footer (%s): %s"%[label,feedback()])
	layout_ok("fresh "+label)

func reserve_walk(label:String)->void:
	var before:=modal_id()
	var r:=0
	for value:int in [12,24,36,48]:
		r=value
		await set_step("TowerReserve","reserve","More",value,r,0,0,"reserve up "+label,before)
		if value==12:check(label_text("TowerReserve")=="桶水保留：儲水桶留 12 份","Reserve 12 wording (%s): %s"%[label,label_text("TowerReserve")])
	check(is_disabled("TowerReserveMore") and is_enabled("TowerReserveLess"),"At 48: ＋ disabled, － enabled (%s)"%label)
	layout_ok("reserve 48 "+label)
	for value:int in [36,24,12,0]:
		await set_step("TowerReserve","reserve","Less",value,value,0,0,"reserve down "+label,before)
	check(feedback()=="水塔已設為「不保留桶水」","Back to 不保留 reply (%s): %s"%[label,feedback()])
	check(is_disabled("TowerReserveLess") and is_enabled("TowerReserveMore"),"At 0: － disabled, ＋ enabled (%s)"%label)
	layout_ok("reserve back to 0 "+label)

func quota_walk(label:String)->void:
	var before:=modal_id()
	for value:int in [4,8,16,24]:
		await set_step("TowerQuota","quota","More",value,0,value,0,"quota up "+label,before)
		if value==8:check(label_text("TowerQuota")=="每日配水：8 份・已送 0・剩 8","Quota 8 wording (%s): %s"%[label,label_text("TowerQuota")])
	check(is_disabled("TowerQuotaMore") and is_enabled("TowerQuotaLess"),"At 24: ＋ disabled, － enabled (%s)"%label)
	layout_ok("quota 24 "+label)
	for value:int in [16,8,4,0]:
		await set_step("TowerQuota","quota","Less",value,0,value,0,"quota down "+label,before)
	check(feedback()=="水塔已設為「每日配水不限」","Back to 不限 reply (%s): %s"%[label,feedback()])
	check(is_disabled("TowerQuotaLess") and is_enabled("TowerQuotaMore"),"At 不限: － disabled, ＋ enabled (%s)"%label)
	layout_ok("quota back to 不限 "+label)

## Real ticks with a quota: the label follows 今天已送 in place, then 送完了.
func tick_flow(label:String)->void:
	var before:=modal_id()
	obj(TANK).water=0  # PRESET (isolate the tower's outflow)
	obj(TOWER).water=60  # PRESET
	obj(S_A).water=9  # PRESET (room 3)
	obj(S_N).water=12  # PRESET (full)
	await refresh()
	for value:int in [4,8]:
		await set_step("TowerQuota","quota","More",value,0,value,0,"quota for ticks "+label,before)
	var quota_label:=control("TowerQuota")
	await tick()
	check(int(obj(TOWER).water)==57 and int(obj(S_A).water)==12 and int(obj(S_N).water)==12,"Tick 1: tower sends 3 into the room left (%s): tower %d S_A %d S_N %d"%[label,int(obj(TOWER).water),int(obj(S_A).water),int(obj(S_N).water)])
	expect("tick 1 "+label,0,8,3)
	check(label_text("TowerQuota")=="每日配水：8 份・已送 3・剩 5" and not label_text("TowerQuota").contains("送完了"),"Label shows 今天已送 3 (%s): %s"%[label,label_text("TowerQuota")])
	same_page(before,"tick 1 "+label)
	check(control("TowerQuota")==quota_label,"Quota label updated in place (%s)"%label)
	check(label_text("TowerWater")=="存水 57／96","Water line follows the tick (%s): %s"%[label,label_text("TowerWater")])
	layout_ok("tick 1 "+label)
	obj(S_A).water=0  # PRESET (sprinkler used its water)
	await tick()
	check(int(obj(TOWER).water)==52 and int(obj(S_A).water)==5,"Tick 2: only the 5 left of the quota goes out (%s): tower %d S_A %d"%[label,int(obj(TOWER).water),int(obj(S_A).water)])
	expect("tick 2 "+label,0,8,8)
	check(label_text("TowerQuota")=="每日配水：8 份・今天已送 8（今天送完了）","Label shows 送完了 (%s): %s"%[label,label_text("TowerQuota")])
	check(control("TowerQuota")==quota_label and modal_id()==before,"Still the same page and label (%s)"%label)
	layout_ok("quota used up "+label)
	await tick()
	check(int(obj(TOWER).water)==52 and int(obj(S_A).water)==5 and int(obj(TOWER).get("quota_used",-1))==8,"Tick 3: nothing more today (%s): tower %d S_A %d"%[label,int(obj(TOWER).water),int(obj(S_A).water)])
	expect("tick 3 "+label,0,8,8)
	# Lowering keeps today's count; 不限 then 4 starts from 0.
	await set_step("TowerQuota","quota","Less",4,0,4,8,"lower below used "+label,before)
	check(label_text("TowerQuota")=="每日配水：4 份・今天已送 8（今天送完了）","Lowered quota keeps today's 8 (%s): %s"%[label,label_text("TowerQuota")])
	await set_step("TowerQuota","quota","Less",0,0,0,0,"quota off "+label,before)
	await set_step("TowerQuota","quota","More",4,0,4,0,"quota on again "+label,before)
	check(label_text("TowerQuota")=="每日配水：4 份・已送 0・剩 4","Re-enabled quota counts from 0 (%s): %s"%[label,label_text("TowerQuota")])
	for value:int in [8,16,24]:
		await set_step("TowerQuota","quota","More",value,0,value,0,"quota to 24 "+label,before)
	obj(S_A).water=0  # PRESET
	obj(S_N).water=0  # PRESET
	await tick()
	check(int(obj(TOWER).water)==28 and int(obj(S_A).water)==12 and int(obj(S_N).water)==12,"Tick 4: 24 goes out, 12 each (%s): tower %d"%[label,int(obj(TOWER).water)])
	expect("quota 24 used "+label,0,24,24)
	check(label_text("TowerQuota")=="每日配水：24 份・今天已送 24（今天送完了）","Longest quota wording (%s): %s"%[label,label_text("TowerQuota")])

## 只蓄水 title, reserve 48 by keyboard, worst-case layouts, back to 出水.
func worst_flow(label:String)->void:
	var before:=modal_id()
	await enter_on("TowerToggle","to 只蓄水 "+label)
	check(obj(TOWER).get("enabled")==false and feedback()=="水塔已設為「只蓄水」","Real toggle sets 只蓄水 (%s): %s"%[label,feedback()])
	check(label_text("TowerSupplyTitle")=="改為出水後會送到" and label_text("TowerSupplyTitle")==TowerUI.SUPPLY_TITLE[false],"Supply title while 只蓄水 (%s): %s"%[label,label_text("TowerSupplyTitle")])
	same_page(before,"只蓄水 "+label)
	for value:int in [12,24,36]:
		await set_step("TowerReserve","reserve","More",value,value,24,24,"reserve while 只蓄水 "+label,before)
	await enter_on("TowerReserveMore","reserve 48 by Enter "+label)
	check(int(obj(TOWER).get("reserve",-1))==48 and feedback()==Industry.tower_set_message("reserve:48"),"KEY_ENTER on ＋ sets reserve 48 (%s): %s"%[label,feedback()])
	expect("worst "+label,48,24,24)
	check(is_disabled("TowerReserveMore"),"＋ disabled at 48 (%s)"%label)
	check(focused_name()!="TowerReserveMore","Focus left the disabled ＋ (%s): %s"%[label,focused_name()])
	check(focused_name()=="TowerReserveLess","Focus stays in the reserve row (%s): %s"%[label,focused_name()])
	focus_ok("after reserve 48 "+label)
	# 只蓄水 does not send and does not touch the quota record.
	obj(S_A).water=0  # PRESET
	await tick()
	check(int(obj(S_A).water)==0 and int(obj(TOWER).water)==28 and int(obj(TOWER).get("quota_used",-1))==24 and int(obj(TOWER).get("quota_day",-1))==today(),"只蓄水 tick: nothing sent, record unchanged (%s): %s"%[label,str(obj(TOWER))])
	expect("worst after tick "+label,48,24,24)
	layout_ok("worst 只蓄水+48+24 used "+label)
	# Largest consumer list: four more sprinklers on the same pipe.
	for c:Vector2i in EXTRA:
		clear_tile(c)
		w.state.objects[k(c)]=sprinkler(12)  # PRESET
	await refresh()
	check(consumer_lines().size()==6,"Six consumers listed (%s): %s"%[label,str(consumer_lines())])
	expect("worst 6 consumers "+label,48,24,24)
	layout_ok("worst + 6 consumers "+label)
	for c:Vector2i in EXTRA:w.state.objects.erase(k(c))  # PRESET
	await refresh()
	# Empty list (two-line explanation): gate closed and the near sprinkler gone.
	await perform(Industry.GATE_ACTION,GATE,"closed")
	var kept:Dictionary=obj(S_A).duplicate(true)
	w.state.objects.erase(k(S_A))  # PRESET
	await refresh()
	check(consumer_lines().is_empty() and shown("TowerConsumerEmpty"),"Empty consumer line (%s): %s"%[label,label_text("TowerConsumerEmpty")])
	layout_ok("worst + empty list "+label)
	w.state.objects[k(S_A)]=kept  # PRESET
	await perform(Industry.GATE_ACTION,GATE,"open")
	check(consumer_lines()==["小型灑水器（44,24）","小型灑水器（48,24）"],"Both sprinklers back (%s): %s"%[label,str(consumer_lines())])
	await enter_on("TowerToggle","back to 出水 "+label)
	check(obj(TOWER).get("enabled")==true and feedback()=="水塔已設為「出水」","Real toggle back to 出水 (%s): %s"%[label,feedback()])
	check(label_text("TowerSupplyTitle")=="出水會送到","Supply title back (%s): %s"%[label,label_text("TowerSupplyTitle")])
	same_page(before,"出水 again "+label)
	# Down to 0 with the keyboard on the last step.
	for value:int in [36,24,12]:
		await set_step("TowerReserve","reserve","Less",value,value,24,24,"reserve down "+label,before)
	await enter_on("TowerReserveLess","reserve 0 by Enter "+label)
	expect("reserve 0 by Enter "+label,0,24,24)
	check(is_disabled("TowerReserveLess") and focused_name()=="TowerReserveMore","Focus stays in the reserve row at the lower limit (%s): %s"%[label,focused_name()])
	focus_ok("after reserve 0 "+label)
	for value:int in [16,8,4]:
		await set_step("TowerQuota","quota","Less",value,0,value,24,"quota down after use "+label,before)
	await enter_on("TowerQuotaLess","quota 不限 by A "+label,true)
	expect("quota 不限 by A "+label,0,0,0)
	check(is_disabled("TowerQuotaLess") and focused_name()=="TowerQuotaMore","Focus stays in the quota row at the lower limit (%s): %s"%[label,focused_name()])
	focus_ok("after quota 不限 "+label)
	layout_ok("settings cleared "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the tower page (%s)"%label)

func visitor_flow(label:String)->void:
	var other:Dictionary=obj(OTHER_TOWER)
	other.reserve=24  # PRESET
	other.quota=8  # PRESET
	other.quota_day=today()  # PRESET
	other.quota_used=3  # PRESET
	await stand(OTHER_SPOT)
	check(str(app.view.interaction_focus())==k(OTHER_TOWER),"Neighbour's tower focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(page_open(),"Neighbour's tower page opens (%s)"%label)
	if not page_open():return
	check(label_text("TowerReserve")==TowerUI.reserve_text(24),"Visitor sees the owner's reserve (%s): %s"%[label,label_text("TowerReserve")])
	check(label_text("TowerQuota")==TowerUI.quota_text(8,3),"Visitor sees the owner's quota (%s): %s"%[label,label_text("TowerQuota")])
	check(shown("TowerReserveRow") and shown("TowerQuotaRow"),"Rows shown to a visitor (%s)"%label)
	for name:String in SETTING_BUTTONS:
		var b:=button(name)
		check(b!=null and b.is_visible_in_tree() and b.disabled and b.tooltip_text==TowerUI.NOT_OWNER,"%s visible, disabled, explained (%s): %s"%[name,label,b.tooltip_text if b!=null else "missing"])
	check(label_text("TowerSupplyTitle")=="改為出水後會送到","Visitor supply title for a 只蓄水 tower (%s): %s"%[label,label_text("TowerSupplyTitle")])
	check(feedback()==TowerUI.NOT_OWNER,"Read-only note at the bottom (%s): %s"%[label,feedback()])
	check(label_text("TowerAbout")==TowerUI.ABOUT,"About text for a visitor (%s)"%label)
	focus_ok("visitor "+label)
	check(focused_name() not in SETTING_BUTTONS,"Visitor focus not on a setting button (%s): %s"%[label,focused_name()])
	layout_ok("visitor "+label)
	var state_before:=canon(obj(OTHER_TOWER))
	var before:=modal_id()
	await click_control(button("TowerReserveMore"))
	check(canon(obj(OTHER_TOWER))==state_before,"Click on the disabled ＋ changes nothing (%s)"%label)
	check(label_text("TowerReserve")==TowerUI.reserve_text(24) and modal_id()==before,"Visitor page unchanged after the click (%s)"%label)
	await perform(Industry.TOWER_SET_ACTION,OTHER_TOWER,"reserve:36")
	check(feedback()==Industry.TOWER_NOT_OWNER,"Server refuses a visitor's reserve (%s): %s"%[label,feedback()])
	check(canon(obj(OTHER_TOWER))==state_before,"Refused reserve leaves the tower unchanged (%s)"%label)
	await perform(Industry.TOWER_SET_ACTION,OTHER_TOWER,"quota:16")
	check(feedback()==Industry.TOWER_NOT_OWNER,"Server refuses a visitor's quota (%s): %s"%[label,feedback()])
	check(canon(obj(OTHER_TOWER))==state_before,"Refused quota leaves the tower unchanged (%s)"%label)
	check(label_text("TowerQuota")==TowerUI.quota_text(8,3) and label_text("TowerReserve")==TowerUI.reserve_text(24),"Visitor labels unchanged after refusals (%s)"%label)
	for name:String in SETTING_BUTTONS:check(is_disabled(name),"%s still disabled (%s)"%[name,label])
	layout_ok("visitor after refusal "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the visitor page (%s)"%label)

func removed_flow(label:String)->void:
	var opened:bool=await open_mine("remove "+label)
	if not opened:return
	var before:=modal_id()
	await set_step("TowerReserve","reserve","More",12,12,0,0,"before remove "+label,before)
	await set_step("TowerQuota","quota","More",4,12,4,0,"before remove "+label,before)
	await perform("remove",TOWER)
	check(not w.state.objects.has(k(TOWER)) and int(bag().get(Industry.TOWER_KIT,0))==1,"Removed through the server, kit back (%s)"%label)
	check(page_open() and modal_id()==before and label_text("TowerWater")==TowerUI.GONE,"Page shows the removed state in place (%s): %s"%[label,label_text("TowerWater")])
	for row_id:String in ["TowerReserveRow","TowerQuotaRow"]:
		var row:=control(row_id)
		check(row!=null and not row.visible and not row.is_visible_in_tree(),"%s hidden once removed (%s)"%[row_id,label])
	for name:String in SETTING_BUTTONS:check(not shown(name),"%s not shown once removed (%s)"%[name,label])
	check(not shown("TowerReserve") and not shown("TowerQuota"),"Setting labels not shown once removed (%s)"%label)
	focus_ok("removed "+label)
	layout_ok("removed "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the removed page (%s)"%label)

func size_flow(label:String)->void:
	await reset()
	var opened:bool=await open_mine(label)
	if not opened:return
	await fresh_flow(label)
	await reserve_walk(label)
	await quota_walk(label)
	await tick_flow(label)
	await worst_flow(label)
	await visitor_flow(label)
	await removed_flow(label)

func pure_checks()->void:
	check(TowerUI.reserve_text(0)=="桶水保留：不保留" and TowerUI.reserve_text(12)=="桶水保留：儲水桶留 12 份" and TowerUI.reserve_text(48)=="桶水保留：儲水桶留 48 份","reserve_text wording")
	check(TowerUI.quota_text(0,0)=="每日配水：不限" and TowerUI.quota_text(0,5)=="每日配水：不限","quota_text 不限")
	check(TowerUI.quota_text(8,3)=="每日配水：8 份・已送 3・剩 5","quota_text partly used")
	check(TowerUI.quota_text(8,8)=="每日配水：8 份・今天已送 8（今天送完了）" and TowerUI.quota_text(4,8)=="每日配水：4 份・今天已送 8（今天送完了）","quota_text used up")
	check(TowerUI.SUPPLY_TITLE[true]=="出水會送到" and TowerUI.SUPPLY_TITLE[false]=="改為出水後會送到","Supply titles")
	check(Industry.TOWER_RESERVES==[0,12,24,36,48] and Industry.TOWER_QUOTAS==[0,4,8,16,24],"Option tables")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("water-tower-quota-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"水塔旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
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
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
