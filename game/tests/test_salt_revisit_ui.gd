extends SceneTree
## 第 40 章「臺南北門回訪・鹽籃批次」頁＋「鹽籃」(背包、家園工坊「生活」頁、訪客卡片)＋地方記憶展的
## 第四件展品 UI test (headless) at 1024×640 and 1280×800. Same harness as test_tea_revisit_ui.gd:
## real Session host, real snapshot round trips.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set here;
##  * the chapter 1/2/3 story fixture of test_salt_revisit (picnic / board / chapter_one, a finished
##    tea comparison, a complete flower record + garden, travel_book.visited tianwei + beimen);
##  * PERSONAL: my salt_pan record (letter / intro, then raked 1 with the chapter still running,
##    then auto_raked / order / complete = the finished chapter); the earned rake and chapter are
##    covered by test_salt_revisit(_session), test_salt_pan_journey and the revisit journey;
##  * the three Beimen gates (gates + repaired_at) — unrepaired for the locked state, then repaired;
##  * state.salt_revisit, my basket kit and placed basket, player.memory_exhibit are ERASED
##    before each size; state.time = day 1 (spring), later a rainy Beimen day and the dry day after;
##  * sea_salt and fiber counts in my bag;
##  * the local player is teleported by writing region/x/y (no walking or travel);
##  * memory exhibit: festival_story_open, the 蘭陽 unlock + completed lanyang_revisit, the hoist /
##    bobo_workshop.done / completed jinguashi_revisit and a completed tea_revisit record (as
##    test_tea_revisit_ui writes them), so four exhibits are on display (the salt batch itself is
##    the one this suite completed through the server); for the hint check my
##    salt_revisit.claimed entry and salt_pan raked count are briefly changed and restored;
##  * removed-tile entry for the build cell; session rate buckets / action_clock cleared.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._interact at 阿曬 (44,17), the co-op chest (47,23) and
##    the 鹽田站牌 bus stop (48,25); the existing pages keep their own actions; the
##    「臺南北門回訪・鹽籃批次」 entry (or its locked caption) is pressed with KEY_ENTER;
##    KEY_LEFT / RIGHT / UP / DOWN move focus; KEY_ENTER on the focused stock / pack / send / claim
##    buttons sends salt_revisit_stock / _pack / _send / _claim through Session.perform -> World ->
##    snapshot -> in-place update; KEY_ESCAPE closes; the tracker card button (real mouse click);
##  * every stock, pack, send and claim is the server's (no revisit writes after the reset):
##    NO_SALT / NO_FIBER / QUOTA_FULL / NEED_STOCK / RAIN_STOCK / STOCK_FULL / ALL_PACKED refusals
##    shown as reasons, a pack on a rainy day, completion, the basket in the bag;
##  * placing the basket: build folio -> 「生活」 tab -> slot -> BuildPlace (real mouse clicks) ->
##    real world click; KEY_E at the placed basket opens its card;
##  * the backpack detail (InventoryPanel.select_item) of the kit;
##  * the memory exhibit page with four exhibits: KEY_E at the stand, arrows + Enter to the 鹽籃 card
##    and through its 4 recap pages; the last page sends exhibit_view.
## NOT COVERED HERE: world pixels (test_salt_revisit_scene.gd); gamepad input (only the focus
## neighbours it uses, through the arrow keys); the non-preview layout; a second client; walking
## between 阿曬 and the chest (test_salt_revisit_session); summer/autumn/winter orders.
const World=preload("res://scripts/world.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const UI=preload("res://scripts/salt_revisit_ui.gd")
const Art=preload("res://scripts/salt_revisit_art.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Weather=preload("res://scripts/weather.gd")
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
const BASKET_SPOT:=Vector2(43.5,35.6)
const STAND_SPOT:=Vector2(39.5,27.5)
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false
var rain_time:=0.0
var dry_time:=0.0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SALT_REVISIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE SALT_REVISIT_UI "+message)

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

func salt_site()->String:
	return str((app.modal as Node).get_meta("salt_site","")) if is_instance_valid(app.modal) else ""

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

func bag()->Dictionary:
	return person().inventory

func salt_record()->Dictionary:
	return w.state.salt_pan.players[id]

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

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

func act_key(code:Key)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await key(code)
	await refresh()

func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

## Focus a button and press it with a real KEY_ENTER.
func enter_on(name:String,label:String)->bool:
	var b:=button(name)
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	b.grab_focus()
	await settle()
	await act_key(KEY_ENTER)
	return true

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
	await mouse_at(c.get_global_rect().get_center())
	await settle()

func click_cell(cell:Vector2i)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await mouse_at(app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*app.view.view_zoom())
	await refresh()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func world_label(id_value:String)->String:
	app.view._process(0.0)
	app.view.queue_redraw()
	await process_frame
	await process_frame
	for entry in app.view.world_labels:
		if str(entry.id)==id_value:return str(entry.title)
	return ""

func tracker()->String:
	return str(app.objective.text) if app.objective!=null else ""

func tracker_button()->Button:
	return app.hud.find_child("TrackerNext",true,false) as Button

func tracker_heading()->String:
	var b:=app.hud.find_child("TrackerHeading",true,false) as Button
	return b.text if b!=null else ""

func k(c:Vector2i)->String:
	return World.key(c)

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

## Disclosed lanyang / jinguashi / tea fixtures (first three exhibits).
func write_other_exhibits()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}  # PRESET
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET
	w.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true}  # PRESET
	w.state.bobo_workshop.done[id]=true  # PRESET
	w.state[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":1,"claimed":{}}  # PRESET
	w.state[TR.STATE_KEY]={"jars":{"tea_returned_jar":2,"tea_worn_jar":4},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":1,"claimed":{}}  # PRESET

## Chapter 1/2/3 FIXTURE (as test_salt_revisit.story_fixture) and my Beimen record.
func story_fixture()->void:
	w.state.picnic=true  # PRESET
	w.state.board=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[id]=tea  # PRESET
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[id]=a  # PRESET
	person().travel_book.visited[Flower.REGION]=true  # PRESET
	person().travel_book.visited[Salt.REGION]=true  # PRESET
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{id:10},"complete":true,"completed_at":0.0}  # PRESET
	var rec:Dictionary=Salt.RECORD.duplicate(true)
	rec.letter=true;rec.intro=true
	w.state.salt_pan.players[id]=rec  # PRESET

func set_gates(repaired:bool)->void:
	for g in Salt.GATE_ROWS.size():
		w.state.salt_pan.gates[g]={"plank":6,"resin":1,"stone":4} if repaired else {"plank":0,"resin":0,"stone":0}  # PRESET
	w.state.salt_pan.repaired_at=1.0 if repaired else -1.0  # PRESET

func chapter_done()->void:
	var rec:=salt_record()
	rec.raked=maxi(1,int(rec.raked));rec.wheel_raked=1;rec.auto_raked=1;rec.order=true;rec.complete=true  # PRESET

## A rainy Beimen day (not day 1) and the first dry day after it.
func find_days()->void:
	for d in range(1,30):
		if Weather.rains(float(d),SR.REGION) and not Weather.rains(float(d+1),SR.REGION):
			rain_time=d*1440.0+30.0
			dry_time=(d+1)*1440.0+30.0
			return

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon inside
## the page and whole, no ellipsis.
func layout_ok(label:String,expected:String=UI.LAYOUT)->void:
	if layout_name()!=expected:
		check(false,"Page %s open for layout: %s (got %s)"%[expected,label,layout_name()])
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
	if expected==UI.LAYOUT:
		check(label_text("SrDisclaimer")==SR.DISCLAIMER and shown("SrDisclaimer"),"Fiction disclaimer shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func button_state(name:String,enabled:bool,reason:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"%s %s (%s)"%[name,"enabled" if enabled else "disabled",label])
	if b!=null and not enabled:check(b.tooltip_text==reason,"%s tooltip 「%s」 (%s): %s"%[name,reason,label,b.tooltip_text])

func not_basket_tracker(label:String)->void:
	check(not tracker().begins_with("鹽籃批次") and UI.tracker_text(snap(),id).is_empty() and tracker_heading()!="臺南北門回訪  ▾","The salt chapter keeps the tracker (%s): %s"%[label,tracker()])

func basket_tracker(expected:String,label:String)->void:
	check(tracker()==expected,"Tracker follows the batch (%s): %s"%[label,tracker()])
	check(tracker_heading()=="臺南北門回訪  ▾" and tracker_button()!=null and tracker_button().text=="打開鹽籃批次  →","Tracker heading and button (%s): %s"%[label,tracker_heading()])

func progress_line(packed:int,rain:int=0)->String:
	var lots:=SR.stocked(w.state)
	var line:="入倉 %d／6 批（晴天 %d、多雲 %d）・已裝 %d／6 籃"%[SR.stocked_total(w.state),int(lots.sunny),int(lots.cloudy),packed]
	if rain>0:line+="（雨天裝 %d 籃）"%rain
	return line

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	story_fixture()
	set_gates(false)
	w.state.erase(SR.STATE_KEY)  # PRESET
	w.state.time=30.0  # PRESET (day 1, spring)
	w.state.festival_story_open=false  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	w.state.erase(JG.STATE_KEY)  # PRESET
	w.state.erase(TR.STATE_KEY)  # PRESET
	w.state.objects.erase(k(BUILD_CELL))  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for item in ["sea_salt","fiber",SR.BASKET_ITEM]:bag()[item]=0  # PRESET
	await refresh()

func open_entry(label:String)->void:
	var entry:=button("SaltRevisitEntry")
	check(entry!=null and entry.is_visible_in_tree(),"Entry offered (%s)"%label)
	await enter_on("SaltRevisitEntry",label)
	check(page_open(),"Entry opens the batch page (%s): %s"%[label,layout_name()])

func open_at_worker(label:String)->void:
	await stand(SR.WORKER_STAND,SR.REGION)
	check(str(app.view.interaction_focus())=="salt:worker","阿曬 focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()=="salt_pan" and salt_site()=="worker","E opens 阿曬's page (%s): %s %s"%[label,layout_name(),salt_site()])
	check(button("SaltJournal")!=null and button("SaltJournal").is_visible_in_tree(),"阿曬's page keeps 翻閱鹽田手帳 (%s)"%label)
	layout_ok("worker page "+label,"salt_pan")
	await open_entry("worker "+label)

func open_at_chest(label:String)->void:
	await stand(SR.CHEST_STAND,SR.REGION)
	check(str(app.view.interaction_focus())=="salt:coop_chest","Co-op chest focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()=="salt_pan" and salt_site()=="coop_chest","E opens the co-op chest page (%s): %s %s"%[label,layout_name(),salt_site()])
	check(control("SaltCoopAbout")!=null,"Chest page keeps its own text (%s)"%label)
	layout_ok("chest page "+label,"salt_pan")
	await open_entry("chest "+label)

func open_at_stop(label:String)->void:
	await stand(SR.STOP_STAND,SR.REGION)
	check(str(app.view.interaction_focus())=="transit:bus","Bus stop focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()=="travel_map" and button("TravelDepart")!=null,"E opens the 鹽田站牌 ticket page with its own departure (%s): %s"%[label,layout_name()])
	await open_entry("stop "+label)

func locked_flow(label:String)->void:
	await stand(SR.WORKER_STAND,SR.REGION)
	await interact_key()
	var entry:=button("SaltRevisitEntry")
	check(entry!=null and entry.text==UI.ENTRY_LOCKED and entry.tooltip_text==SR.LOCKED,"Locked caption with the reason on 阿曬's page (%s): %s"%[label,entry.text if entry else "none"])
	check(button("SaltOpenGates")!=null,"阿曬's page keeps 看三道閘門 (%s)"%label)
	layout_ok("worker locked "+label,"salt_pan")
	await enter_on("SaltRevisitEntry","locked "+label)
	check(page_open(),"Locked entry opens the page (%s)"%label)
	check(label_text("SrLockedText")==SR.LOCKED and shown("SrLocked"),"Locked reason (%s): %s"%[label,label_text("SrLockedText")])
	check(not shown("SrCards") and not shown("SrClaimCard") and not shown("SrProgress") and not shown("SrHold"),"Locked: no controls (%s)"%label)
	check(label_text("SrDay").begins_with("春季的訂單・第 1 日・北門") and label_text("SrReason")=="阿曬　「"+SR.REASONS.spring.trim_prefix("阿曬說，")+"」","Order day and 阿曬's reason (%s): %s / %s"%[label,label_text("SrDay"),label_text("SrReason")])
	check(focused_name()=="SrBack","Locked page focuses the way back (%s): %s"%[label,focused_name()])
	layout_ok("locked "+label)
	await key(KEY_ESCAPE)
	await stand(SR.STOP_STAND,SR.REGION)
	await interact_key()
	entry=button("SaltRevisitEntry")
	check(layout_name()=="travel_map" and entry!=null and entry.text==UI.ENTRY_LOCKED and entry.tooltip_text==SR.LOCKED,"Locked caption on the bus stop page (%s)"%label)
	check(button("TravelDepart")!=null and button("SelectRoute_tianwei")!=null,"Bus stop keeps its routes (%s)"%label)
	layout_ok("stop locked "+label,"travel_map")
	await close_page()
	await stand(SR.CHEST_STAND,SR.REGION)
	await interact_key()
	entry=button("SaltRevisitEntry")
	check(salt_site()=="coop_chest" and entry!=null and entry.text==UI.ENTRY_LOCKED,"Locked caption on the chest page (%s)"%label)
	layout_ok("chest locked "+label,"salt_pan")
	await close_page()

func not_ready_flow(label:String)->void:
	set_gates(true)
	await open_at_worker("not ready "+label)
	if not page_open():return
	check(label_text("SrHoldText")==SR.NOT_READY and shown("SrHold") and not shown("SrLocked"),"Catch-up message (%s): %s"%[label,label_text("SrHoldText")])
	check(not shown("SrCards") and not shown("SrClaimCard") and not shown("SrProgress") and shown("SrNotebook"),"No controls, link to the salt journal (%s)"%label)
	check(focused_name()=="SrNotebook","Focus on the journal link (%s): %s"%[label,focused_name()])
	layout_ok("not ready "+label)
	await act_key(KEY_ENTER)
	check(layout_name()=="salt_pan" and salt_site()=="journal","Link opens the salt journal (%s): %s %s"%[label,layout_name(),salt_site()])
	check(label_text("SaltRevisitLine")=="○ 鹽籃批次：先在保留手作池親手收一次鹽，再來幫忙","Journal line for a late joiner (%s): %s"%[label,label_text("SaltRevisitLine")])
	await close_page()
	not_basket_tracker("not ready "+label)
	# Raked once, but the Beimen chapter is still running: its step keeps the card.
	salt_record().raked=1  # PRESET
	bag().sea_salt=3  # PRESET
	await stand(SR.WORKER_STAND,SR.REGION)
	check(SR.stock_block(snap(),bag()).is_empty() and str(snap().salt_pan.own.phase)!="complete","Mid-chapter with a possible stock (%s): %s"%[label,str(snap().salt_pan.own.phase)])
	not_basket_tracker("chapter running "+label)
	chapter_done()
	bag().sea_salt=0  # PRESET
	await refresh()

func worker_flow(label:String)->void:
	await open_at_worker("nothing stocked "+label)
	if not page_open():return
	not_basket_tracker("nothing stocked "+label)
	check(not shown("SrHold") and not shown("SrLocked") and shown("SrCards") and shown("SrClaimCard"),"Ready: cards shown (%s)"%label)
	check(label_text("SrProgress")=="入倉 0／6 批（晴天 0、多雲 0）・已裝 0／6 籃","Progress (%s): %s"%[label,label_text("SrProgress")])
	check(label_text("SrStockName")=="阿曬・合作社工寮前（44,17）" and label_text("SrPackName")=="合作社收鹽箱（47,23）" and label_text("SrStopName")=="海邊公車站（48,25）","Card titles with points (%s)"%label)
	check(label_text("SrStockNote")==UI.STOCK_NOTE and label_text("SrOrder")=="春季訂單：料理用 3 籃、醃漬用 3 籃","Stock note and order (%s): %s"%[label,label_text("SrOrder")])
	button_state("Sr_stock",false,SR.NO_SALT%[3,0],"nothing stocked "+label)
	check(label_text("SrStockReason")==SR.NO_SALT%[3,0],"Stock reason (%s): %s"%[label,label_text("SrStockReason")])
	button_state("Sr_kitchen",false,SR.NEED_STOCK%[0,0],"nothing stocked "+label)
	button_state("Sr_pickle",false,SR.NEED_STOCK%[0,0],"nothing stocked "+label)
	check(label_text("SrPackReason")==SR.NEED_STOCK%[0,0],"Pack reason shown once (%s): %s"%[label,label_text("SrPackReason")])
	button_state("SrSend",false,SR.NOT_PACKED%0,"nothing stocked "+label)
	check(not shown("SrSendReason") and label_text("SrSendMark")=="○ 還沒送出","Send waits quietly (%s)"%label)
	check(button("SrClaim").disabled and label_text("SrClaimReason")==SR.NOT_DONE and label_text("SrStatus")==UI.STATUS_OPEN,"Claim waits (%s)"%label)
	check(label_text("SrLine_kitchen")=="料理用 已裝 0／3" and label_text("SrLine_pickle")=="醃漬用 已裝 0／3" and label_text("SrLine_stock")=="海鹽・背包 0","Rows (%s): %s"%[label,label_text("SrLine_kitchen")])
	check(label_text("SrFiber")=="纖維・背包 0（一籃用 2 份，編籃、綁口）","Fiber line (%s): %s"%[label,label_text("SrFiber")])
	check(not shown("SrRainNote") and not shown("SrRainPack"),"No rain lines on a dry day (%s)"%label)
	check(focused_name()=="Sr_stock","Focus rests on the stock button (%s): %s"%[label,focused_name()])
	check(button("SrBack")!=null and button("SrBack").text==UI.BACK_TEXT.worker,"Back names 阿曬 (%s)"%label)
	layout_ok("nothing stocked "+label)
	# Salt in the bag (written), stocked through the server.
	bag().sea_salt=13  # PRESET
	await refresh()
	var modal_before:Node=app.modal
	var card_before:=control("SrStockCard")
	button_state("Sr_stock",true,"","salt in the bag "+label)
	check(not shown("SrStockReason"),"No stock reason once salt can be stocked (%s)"%label)
	basket_tracker("鹽籃批次・入倉 0／6 批\n帶海鹽找阿曬入倉","stock possible "+label)
	for n in [1,2,3,4]:
		await act_key(KEY_ENTER)
		check(SR.stocked_total(w.state)==n and feedback()==SR.STOCK_OK%[3,str(Weather.LABELS[SR.weather_today(w.state)]),n],"KEY_ENTER stocks lot %d through the server (%s): %s"%[n,label,feedback()])
	check(app.modal==modal_before and control("SrStockCard")==card_before,"Page updated in place (%s)"%label)
	check(focused_name()=="Sr_stock","Focus stays on the pressed button (%s): %s"%[label,focused_name()])
	check(int(bag().sea_salt)==1,"12 sea salt used (%s): %d"%[label,int(bag().sea_salt)])
	# Short of salt.
	button_state("Sr_stock",false,SR.NO_SALT%[3,1],"short of salt "+label)
	check(label_text("SrStockReason")==SR.NO_SALT%[3,1] and label_text("SrLine_stock")=="海鹽・背包 1","Short of salt in place (%s): %s"%[label,label_text("SrStockReason")])
	check(label_text("SrProgress")==progress_line(0),"Partly stocked progress (%s): %s"%[label,label_text("SrProgress")])
	button_state("Sr_kitchen",false,SR.NO_FIBER%[2,0],"no fiber at 阿曬 "+label)
	focus_ok("partly stocked "+label)
	layout_ok("partly stocked "+label)
	# Fiber in the bag: the rule allows packing, but this is 阿曬 → say where to stand.
	bag().fiber=2  # PRESET
	await refresh()
	var away:=UI.AWAY_PACK%[47,23]
	button_state("Sr_kitchen",false,away,"wrong spot "+label)
	button_state("Sr_pickle",false,away,"wrong spot "+label)
	check(label_text("SrPackReason")==away,"Wrong spot: where to stand, once (%s): %s"%[label,label_text("SrPackReason")])
	await key(KEY_RIGHT)
	check(focused_name()=="Sr_kitchen","KEY_RIGHT to 料理用 (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="Sr_pickle","KEY_DOWN to 醃漬用 (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="Sr_kitchen","KEY_UP back (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	check(focused_name()=="Sr_stock","KEY_LEFT back to the stock button (%s): %s"%[label,focused_name()])
	basket_tracker("鹽籃批次・已裝 0／6 籃\n到收鹽箱旁裝料理用、醃漬用","pack possible "+label)
	layout_ok("wrong spot "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)

func chest_flow(label:String)->void:
	await open_at_chest(label)
	if not page_open():return
	check(focused_name()=="Sr_kitchen","At the chest focus starts on 料理用 (%s): %s"%[label,focused_name()])
	check(button("SrBack")!=null and button("SrBack").text==UI.BACK_TEXT.chest,"Back names the chest (%s)"%label)
	button_state("Sr_stock",false,SR.NO_SALT%[3,1],"stock rule first at the chest "+label)
	await act_key(KEY_ENTER)
	check(int(SR.packed(w.state).kitchen)==1 and feedback()==SR.PACK_OK%["料理用",1,1,0] and int(SR.record(w.state).day)==1,"KEY_ENTER packs one through the server (%s): %s"%[label,feedback()])
	check(label_text("SrDay").begins_with("春季的訂單（第 1 日開始裝籃）"),"Order day stamped (%s): %s"%[label,label_text("SrDay")])
	# Short of fiber.
	button_state("Sr_kitchen",false,SR.NO_FIBER%[2,0],"short of fiber "+label)
	button_state("Sr_pickle",false,SR.NO_FIBER%[2,0],"short of fiber "+label)
	check(label_text("SrPackReason")==SR.NO_FIBER%[2,0] and label_text("SrFiber")=="纖維・背包 0（一籃用 2 份，編籃、綁口）","Short of fiber once (%s): %s"%[label,label_text("SrPackReason")])
	focus_ok("short of fiber "+label)
	layout_ok("short of fiber "+label)
	not_basket_tracker("nothing doable "+label)
	bag().fiber=4  # PRESET
	await refresh()
	await act_key(KEY_ENTER)
	await act_key(KEY_ENTER)
	check(int(SR.packed(w.state).kitchen)==3,"Three 料理用 (%s): %s"%[label,str(SR.packed(w.state))])
	# Quota full for 料理用.
	var quota:=SR.QUOTA_FULL%["料理用",3,3,"醃漬用"]
	button_state("Sr_kitchen",false,quota,"quota full "+label)
	check(label_text("SrLine_kitchen")=="料理用 已裝 3／3 ✓" and label_text("SrPackReason").contains(quota),"Quota full ✓ and reason (%s): %s"%[label,label_text("SrPackReason")])
	check(label_text("SrProgress")==progress_line(3),"Progress in place (%s): %s"%[label,label_text("SrProgress")])
	layout_ok("quota full "+label)
	await key(KEY_ESCAPE)

func rain_flow(label:String)->void:
	w.state.time=rain_time  # PRESET (a rainy Beimen day)
	bag().sea_salt=6;bag().fiber=2  # PRESET
	await refresh()
	check(SR.rainy_today(snap()),"Rainy Beimen day found (%s): t=%.0f"%[label,rain_time])
	basket_tracker("鹽籃批次・已裝 3／6 籃・雨天\n到收鹽箱旁裝醃漬用","rain "+label)
	await open_at_chest("rain "+label)
	if not page_open():return
	check(label_text("SrDay").ends_with("北門"+str(Weather.at(rain_time,SR.REGION).label)),"Header names the Beimen weather (%s): %s"%[label,label_text("SrDay")])
	button_state("Sr_stock",false,SR.RAIN_STOCK,"rain "+label)
	check(label_text("SrStockReason")==SR.RAIN_STOCK and label_text("SrRainNote")==UI.RAIN_PACK_NOTE,"Rain: stock refused and packing goes on (%s): %s"%[label,label_text("SrRainNote")])
	button_state("Sr_pickle",true,"","rain pack "+label)
	check(label_text("SrRainPack")==UI.RAIN_PACK_GOOD and shown("SrRainPack"),"Rain: pack card says pack under the shed (%s)"%label)
	check(focused_name()=="Sr_pickle","Focus on the usable 醃漬用 (%s): %s"%[label,focused_name()])
	layout_ok("rainy day "+label)
	await act_key(KEY_ENTER)
	check(int(SR.packed(w.state).pickle)==1 and SR.rain_packs(w.state)==1 and feedback()==SR.PACK_OK%["醃漬用",4,3,1]+SR.PACK_RAIN_NOTE,"Rainy pack through the server (%s): %s"%[label,feedback()])
	check(label_text("SrProgress")==progress_line(4,1),"Rain pack in the progress (%s): %s"%[label,label_text("SrProgress")])
	button_state("Sr_pickle",false,SR.NEED_STOCK%[4,4],"stock needed "+label)
	check(not shown("SrRainPack"),"Rain pack note hides when nothing can be packed (%s)"%label)
	layout_ok("rain packed "+label)
	await key(KEY_ESCAPE)

func send_flow(label:String)->void:
	w.state.time=dry_time  # PRESET (the dry day after)
	bag().fiber=4  # PRESET
	await refresh()
	await open_at_worker("full "+label)
	if not page_open():return
	await act_key(KEY_ENTER)
	await act_key(KEY_ENTER)
	check(SR.stocked_total(w.state)==6,"Six lots (%s)"%label)
	button_state("Sr_stock",false,SR.STOCK_FULL,"stock full "+label)
	check(label_text("SrStockReason")==SR.STOCK_FULL,"Stock full reason (%s)"%label)
	layout_ok("stock full "+label)
	await key(KEY_ESCAPE)
	await open_at_chest("finish "+label)
	if not page_open():return
	await act_key(KEY_ENTER)
	await act_key(KEY_ENTER)
	check(SR.packed(w.state)=={"kitchen":3,"pickle":3},"All six packed (%s): %s"%[label,str(SR.packed(w.state))])
	check(label_text("SrPackReason")==SR.ALL_PACKED,"All packed reason (%s): %s"%[label,label_text("SrPackReason")])
	button_state("SrSend",true,"","ready to send "+label)
	check(label_text("SrSendMark")=="○ 6 籃都裝好了" and not shown("SrSendReason"),"Ready-to-send mark (%s)"%label)
	layout_ok("ready to send "+label)
	await key(KEY_ESCAPE)
	basket_tracker("鹽籃批次・6 籃都裝好了\n到海邊公車站送出","send "+label)
	await open_at_stop(label)
	if not page_open():return
	check(button("SrBack")!=null and button("SrBack").text==UI.BACK_TEXT.stop,"Back names the bus stop (%s)"%label)
	check(focused_name()=="SrSend","At the stop focus starts on 送出 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(SR.completed(w.state) and feedback()==SR.COMPLETE_OK and int(SR.record(w.state).done_day)==SR.today(w.state),"Batch sent through the server (%s): %s"%[label,feedback()])
	check(page_open(),"Page stays open on completion (%s)"%label)
	check(label_text("SrStatus")==UI.STATUS_DONE and label_text("SrDay")=="春季的訂單・第 %d 日送出了"%SR.today(w.state) and label_text("SrSendMark")=="✓ 第 %d 日送出"%SR.today(w.state),"Completion state (%s): %s"%[label,label_text("SrDay")])
	check(not shown("SrSend") and not shown("Sr_kitchen") and not shown("Sr_stock") and not shown("SrPackReason") and not shown("SrStockReason"),"Batch buttons and reasons hidden after sending (%s)"%label)
	check(button("SrClaim").disabled and label_text("SrClaimReason")==UI.AWAY_CLAIM%[44,17],"Claim says where to stand (%s): %s"%[label,label_text("SrClaimReason")])
	check(focused_name()=="SrClaim","Focus moves to the claim row (%s): %s"%[label,focused_name()])
	focus_ok("completed "+label)
	layout_ok("completed unclaimed "+label)
	await enter_on("SrBack","back to the stop "+label)
	check(layout_name()=="travel_map","Back returns to the ticket page (%s): %s"%[label,layout_name()])
	await key(KEY_ESCAPE)
	await close_page()
	basket_tracker("鹽籃批次送出了\n到阿曬那裡領鹽籃","claim "+label)

func claim_flow(label:String)->void:
	await stand(SR.WORKER_STAND,SR.REGION)
	await click_control(tracker_button())
	await refresh()
	check(page_open() and focused_name()=="SrClaim","Tracker click opens the page, focus on 領取 (%s): %s / %s"%[label,layout_name(),focused_name()])
	if not page_open():return
	await act_key(KEY_ENTER)
	check(int(bag().get(SR.BASKET_ITEM,0))==1 and feedback()==SR.CLAIM_OK,"Claim through the server (%s): %s"%[label,feedback()])
	check(label_text("SrStatus")==UI.STATUS_CLAIMED and button("SrClaim").disabled and label_text("SrClaimReason")==SR.CLAIMED,"Claimed state (%s): %s"%[label,label_text("SrClaimReason")])
	focus_ok("claimed "+label)
	layout_ok("claimed "+label)
	await key(KEY_ESCAPE)
	not_basket_tracker("claimed "+label)
	# The salt journal carries the batch line.
	app.SaltUI.open(app,"journal")
	await settle()
	check(label_text("SaltRevisitLine")=="✓ 鹽籃批次送出了・鹽籃已領，可擺在家園","Journal line (%s): %s"%[label,label_text("SaltRevisitLine")])
	var line:=control("SaltRevisitLine")
	check(line!=null and line.is_visible_in_tree() and (app.modal as Control).get_global_rect().grow(0.5).encloses(line.get_global_rect()) and not_cut(line as Label),"Journal line whole inside the page (%s)"%label)
	await close_page()

func basket_flow(label:String)->void:
	await stand(BUILD_SPOT,World.REGIONS.HOME)
	clear_tile(BUILD_CELL)
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	await click_control(tab)
	var slot:=button("BuildSlot_salt_basket_3")
	check(slot!=null and slot.is_visible_in_tree(),"鹽籃 on the 生活 page (%s)"%label)
	var shelf:Node=slot.get_parent() if slot!=null else null
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:
		(shelf as ScrollContainer).ensure_control_visible(slot)
		await settle()
		check((shelf as Control).get_global_rect().grow(0.5).encloses(slot.get_global_rect()),"鹽籃 slot scrolled into view (%s)"%label)
	await click_control(slot)
	check(label_text("BuildTitle")=="鹽籃","Recipe card shows 鹽籃 after a click (%s): %s"%[label,label_text("BuildTitle")])
	check(texts().contains("竹編小籃裡堆著一把海鹽"),"Recipe card shows the 生活 blurb (%s)"%label)
	var place:=button("BuildPlace")
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	await click_control(place)
	check(str(app.building)==SR.BASKET_KIND and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 鹽籃 by clicks (%s): %s %s"%[label,app.building,app.selected])
	await click_cell(BUILD_CELL)
	var obj:Dictionary=w.state.objects.get(k(BUILD_CELL),{})
	check(str(obj.get("type",""))==SR.BASKET_KIND and str(obj.get("owner",""))==id,"Click placed 鹽籃 (%s): %s"%[label,str(obj)])
	check(int(bag().get(SR.BASKET_ITEM,0))==0 and not w.blocked(BUILD_CELL),"Kit used; the basket does not block (%s)"%label)
	app._select_tool("hoe")
	await stand(BASKET_SPOT,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(BUILD_CELL),"Basket focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(BUILD_CELL))==SR.BASKET_NAME,"Basket prompt (%s)"%label)
	await interact_key()
	check(layout_name()==UI.CARD_LAYOUT,"E at the basket opens its card (%s): %s"%[label,layout_name()])
	check(label_text("BasketName")==SR.BASKET_NAME and label_text("BasketBlurb")==SR.BASKET_BLURB and label_text("BasketSource")==SR.BASKET_SOURCE and label_text("BasketProject")==SR.BASKET_PROJECT,"Card texts (%s): %s"%[label,texts().replace("\n"," | ")])
	check(label_text("BasketOwner")=="擺放者・鹽籃旅人","Card names who placed it (%s): %s"%[label,label_text("BasketOwner")])
	var pic:=control("BasketIcon") as TextureRect
	check(pic!=null and pic.texture==Art.basket_texture(),"Card shows the basket art (%s)"%label)
	layout_ok("basket card "+label,UI.CARD_LAYOUT)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the card (%s)"%label)

func inventory_flow(label:String)->void:
	bag()[SR.BASKET_ITEM]=1  # PRESET
	await refresh()
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item(SR.BASKET_ITEM)
		await settle()
		check(panel.detail_name.text=="鹽籃" and panel.detail_count.text=="持有 1","Basket name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.begins_with("紀念物・") and panel.detail_use.text.contains("「生活」") and panel.detail_use.text.contains("只是裝飾") and panel.detail_use.text.contains(app.binding_label("build_menu")),"Basket usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_value.text=="紀念物・不能出售或交易","Basket value line (%s): %s"%[label,panel.detail_value.text])
		check(panel.detail_icon.texture==Items.icon(SR.BASKET_ITEM) and panel.detail_icon.texture==Art.basket_texture() and panel.detail_icon.texture!=Items.icon("sea_salt"),"Basket icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use) and not_cut(panel.detail_value) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Basket texts whole (%s)"%label)
	await close_page()
	bag()[SR.BASKET_ITEM]=0  # PRESET
	await refresh()

func exhibit_flow(label:String)->void:
	w.state.festival_story_open=true  # PRESET
	write_other_exhibits()
	await stand(STAND_SPOT,World.REGIONS.HOME)
	check(Exhibit.on_display_ids(snap())==["lanyang","jinguashi","tea_pottery","beimen"],"Four exhibits on display (%s): %s"%[label,str(Exhibit.on_display_ids(snap()))])
	check(ExhibitUI.news_line(snap())=="地方記憶展：4 件展出・4 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%4,"Journal and home tracker count four new exhibits (%s)"%label)
	await interact_key()
	check(layout_name()==ExhibitUI.LAYOUT,"E at the stand opens the exhibit (%s): %s"%[label,layout_name()])
	if layout_name()!=ExhibitUI.LAYOUT:return
	check(focused_name()=="MemoryCard_lanyang","Focus on the first unread card (%s): %s"%[label,focused_name()])
	check(label_text("MemoryBadge_beimen")==ExhibitUI.BADGE_NEW and label_text("MemoryStatus_beimen")==ExhibitUI.STATUS_ON,"Fourth card 新・展出中 (%s)"%label)
	check((control("MemoryIcon_beimen") as TextureRect).texture==Art.basket_texture(),"鹽籃 card icon is the basket (%s)"%label)
	layout_ok("exhibit four "+label,ExhibitUI.LAYOUT)
	await key(KEY_RIGHT);await key(KEY_RIGHT);await key(KEY_RIGHT)
	check(focused_name()=="MemoryCard_beimen","KEY_RIGHT ×3 to 鹽籃 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	var done_day:=int(SR.record(w.state).done_day)
	check(label_text("MemoryDetailName")=="鹽籃" and label_text("MemoryBlurb")==SR.BASKET_BLURB,"鹽籃 detail (%s): %s"%[label,label_text("MemoryDetailName")])
	check(label_text("MemorySource").contains(SR.BASKET_SOURCE) and label_text("MemorySource").contains(SR.BASKET_PROJECT),"Source and project (%s): %s"%[label,label_text("MemorySource")])
	var lots:=SR.stocked(w.state)
	check(label_text("MemoryDay").begins_with("完成那天：第 %d 日・北門"%done_day) and label_text("MemoryDemand")=="春季的訂單：料理用 3 籃／醃漬用 3 籃" and label_text("MemoryGates")=="入倉的散鹽：晴天 %d 批、多雲 %d 批；雨天裝籃 1 籃"%[int(lots.sunny),int(lots.cloudy)],"Salt lines (%s): %s / %s / %s"%[label,label_text("MemoryDay"),label_text("MemoryDemand"),label_text("MemoryGates")])
	check(label_text("MemoryDisclaimer")==SR.DISCLAIMER,"Salt disclaimer (%s)"%label)
	check(label_text("MemoryHint")==Exhibit.HINT_SALT_CLAIMED and label_text("MemoryFirstShare")=="✓ 已在北門親手收過鹽" and label_text("MemoryPlaque")=="✓ 已領鹽籃","Salt progress box (%s): %s / %s / %s"%[label,label_text("MemoryHint"),label_text("MemoryFirstShare"),label_text("MemoryPlaque")])
	check((control("MemoryDetailIcon") as TextureRect).texture==Art.basket_texture(),"Detail icon is the basket (%s)"%label)
	check(not texts().contains("1818") and not texts().contains("井仔腳"),"No Beimen history text on the exhibit (%s)"%label)
	layout_ok("exhibit salt "+label,ExhibitUI.LAYOUT)
	# Personal hints follow raking_done / basket_claimed in place.
	var hint_node:=control("MemoryHint")
	w.state[SR.STATE_KEY].claimed.erase(id)  # PRESET (restored below)
	await refresh()
	check(control("MemoryHint")==hint_node and label_text("MemoryHint")==Exhibit.HINT_SALT_UNCLAIMED and label_text("MemoryPlaque")=="○ 還沒領鹽籃","Unclaimed hint in place (%s): %s"%[label,label_text("MemoryHint")])
	salt_record().raked=0  # PRESET (restored below)
	await refresh()
	check(label_text("MemoryHint")==Exhibit.HINT_SALT_NOT_READY and label_text("MemoryFirstShare")=="○ 還沒在北門親手收過鹽","Not-raked hint in place (%s): %s"%[label,label_text("MemoryHint")])
	layout_ok("exhibit salt hint "+label,ExhibitUI.LAYOUT)
	salt_record().raked=1  # PRESET (restored)
	w.state[SR.STATE_KEY].claimed[id]=true  # PRESET (restored)
	await refresh()
	check(label_text("MemoryHint")==Exhibit.HINT_SALT_CLAIMED,"Hint restored (%s)"%label)
	await key(KEY_DOWN)
	check(focused_name()=="MemoryRecap","KEY_DOWN to 翻閱回顧 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 1／4・回訪的緣由","Salt recap page 1 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("salt recap 1 "+label,ExhibitUI.LAYOUT)
	var counter:int=app.session.counter
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 2／4・訂單上的需要","Salt recap page 2 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("salt recap 2 "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 3／4・怎麼入倉與裝籃" and label_text("MemoryPageLines").contains("展台沒有記錄是誰入倉、誰裝籃、誰送出。") and label_text("MemoryPageLines").contains("其中 1 籃是在下雨天"),"Salt recap page 3 (%s): %s"%[label,label_text("MemoryPageLines")])
	layout_ok("salt recap 3 "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	check(app.session.counter==counter+1 and "beimen" in Exhibit.seen_ids(w.state,id),"Last page sends exhibit_view once (%s): %d"%[label,app.session.counter-counter])
	check(feedback()==Exhibit.VIEW_OK%"鹽籃","Server reply (%s): %s"%[label,feedback()])
	check(label_text("MemoryPageTitle")=="回顧 4／4・帶回家的紀念","Last page (%s)"%label)
	check(label_text("MemoryBadge_beimen")==ExhibitUI.BADGE_SEEN and label_text("MemoryBadge_tea_pottery")==ExhibitUI.BADGE_NEW,"Only the salt badge clears (%s)"%label)
	check(ExhibitUI.news_line(snap())=="地方記憶展：4 件展出・3 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%3,"Counts follow (%s)"%label)
	layout_ok("salt recap last "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	await key(KEY_UP)
	check(focused_name()=="MemoryCard_beimen","KEY_UP to the chosen card (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="陶器" and label_text("MemoryFirstShare").contains("茶茶"),"Back on 陶器: its own progress lines (%s): %s"%[label,label_text("MemoryFirstShare")])
	await key(KEY_ESCAPE)

func size_flow(label:String)->void:
	await reset()
	await locked_flow(label)
	await not_ready_flow(label)
	await worker_flow(label)
	await chest_flow(label)
	await rain_flow(label)
	await send_flow(label)
	await claim_flow(label)
	await basket_flow(label)
	await inventory_flow(label)
	await exhibit_flow(label)

func pure_checks()->void:
	var s:Dictionary={"time":30.0,"region_id":"beimen","players":{"me":{"x":44.5,"y":18.5,"inventory":{"sea_salt":3}}},"salt_pan":{"repaired":true,"own":{"phase":"complete","record":{"raked":0}}}}
	check(UI.tracker_text(s,"me").is_empty(),"No tracker for a player who has not raked")
	check(UI.journal_line(s)=="○ 鹽籃批次：先在保留手作池親手收一次鹽，再來幫忙","Journal line for a late joiner")
	s.salt_pan.own.record.raked=1
	check(UI.tracker_text(s,"me")=="鹽籃批次・入倉 0／6 批\n帶海鹽找阿曬入倉","Ready with salt: tracker")
	s.salt_pan.own.phase="automate"
	check(UI.tracker_text(s,"me").is_empty(),"A running chapter step keeps the tracker")
	s.salt_pan.own.phase="complete"
	var me:Dictionary=s.players.me
	check(UI.stock_reason(s,me).is_empty() and UI.pack_reason(s,me,"kitchen")==SR.NEED_STOCK%[0,0],"Rules reason first")
	me.x=47.5;me.y=24.5
	check(UI.stock_reason(s,me)==UI.AWAY_STOCK%[44,17],"Where to stand for stocking from the chest")
	check(UI.standing_origin(s,me)=="chest","Standing origin at the chest")
	s.region_id="home"
	check(UI.tracker_text(s,"me").is_empty(),"No salt tracker at home")
	check(UI.stock_reason(s,me)==UI.AWAY_STOCK%[44,17],"Away from Beimen: where to go")
	s.salt_pan.repaired=false
	check(UI.journal_line(s).is_empty() and UI.entry_caption(s)==UI.ENTRY_LOCKED and UI.stock_reason(s,me)==SR.LOCKED,"Locked before the gates")
	check(UI.journal_line({"time":0.0})=="" and UI.tracker_text({"time":0.0},"me")=="","Defensive reads of an empty snapshot")

func run()->void:
	create_timer(220.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 220 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	find_days()
	check(rain_time>0.0 and dry_time>rain_time,"Calendar has a rainy Beimen day followed by a dry one")
	path=OS.get_environment("TEMP").path_join("salt-revisit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"鹽籃旅人",path)!=OK:check(false,"Host starts");finish();return
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
