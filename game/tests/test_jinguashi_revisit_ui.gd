extends SceneTree
## 第 40 章「金瓜石回訪・礦料調度」頁＋「礦燈」(背包、家園工坊「生活」頁、訪客卡片)＋地方記憶展的
## 第二件展品 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_lanyang_revisit_ui.gd: real Session host, real snapshot round trips.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set
##    here (the runner passes no flag for this suite);
##  * UNLOCK: state.mine_depths = {unlocked:6, pumped:24, hoist:true} (false while "locked");
##    PERSONAL: state.bobo_workshop.done[me]=true (erased for the not-ready page); the earned
##    path (hoist repair, Bobo sort) is covered by test_jinguashi_revisit(_session/_journey);
##  * state.jinguashi_revisit, my lantern kit and placed lantern, player.memory_exhibit are
##    ERASED before each size; state.time = day 1 (spring);
##  * ore counts in my bag (gold_ore 2 / copper_ore 4 / stone 6, and 0 for the short state);
##  * the local player is teleported by writing region/x/y (no walking or travel);
##  * memory exhibit: state.festival_story_open=true, the 蘭陽 unlock (lanyang_life repaired,
##    history_memory with my first 分水 and the plaque) and a completed lanyang_revisit
##    record (gates 3/2, day 1) so two exhibits are on display;
##  * session rate buckets / action_clock are cleared between my own actions.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._interact at Bobo's table (bobo_sort page), the
##    山城接駁站 (ticket page) and the 下坑路牌 (mine entry card); the existing pages still
##    offer their own actions; the 「金瓜石回訪・礦料調度」 entry in each is pressed with
##    KEY_ENTER; KEY_LEFT / RIGHT / UP / DOWN move focus; KEY_ENTER on the focused sort /
##    ship / claim buttons sends jg_revisit_sort / jg_revisit_ship / jg_revisit_claim through
##    Session.perform -> World -> snapshot -> in-place update; KEY_ESCAPE closes;
##  * every sort, ship and claim is the server's (no revisit writes after the reset):
##    wrong-assignment reply, short of ore, the three sends at the table / shuttle / hoist,
##    completion, the lantern in the bag; the tracker card button (real mouse click);
##  * placing the lantern: build folio -> 「生活」 tab -> slot -> BuildPlace (real mouse
##    clicks) -> real world click; KEY_E at the placed lantern opens its card;
##  * the backpack detail (InventoryPanel.select_item) of the kit;
##  * the memory exhibit page with two exhibits: KEY_E at the stand, arrows + Enter to the
##    礦燈 card and through its 4 recap pages; the last page sends exhibit_view.
## NOT COVERED HERE: world pixels (test_jinguashi_revisit_scene.gd); gamepad input (only the
## focus neighbours it uses, through the arrow keys); the non-preview layout; a second
## connected client.
const World=preload("res://scripts/world.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const UI=preload("res://scripts/jinguashi_revisit_ui.gd")
const Art=preload("res://scripts/jinguashi_revisit_art.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const DAY:=1440.0
## Standing spots used by the rules tests (all walkable).
const TABLE_SPOT:=Vector2(23.5,21.5)
const HOIST_SPOT:=Vector2(27.5,19.5)
const SHUTTLE_SPOT:=Vector2(12.5,20.5)
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
const LANTERN_SPOT:=Vector2(43.5,35.6)
const STAND_SPOT:=Vector2(39.5,27.5)
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
	print("JINGUASHI_REVISIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE JINGUASHI_REVISIT_UI "+message)

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

func bag()->Dictionary:
	return person().inventory

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func stand(at:Vector2,region:String="jinguashi")->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
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

func k(c:Vector2i)->String:
	return World.key(c)

func crates()->Dictionary:
	return JG.crates(w.state)

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

## Disclosed lanyang fixture for the second exhibit (see header).
func write_lanyang()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}  # PRESET
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET

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
		check(label_text("JgDisclaimer")==JG.DISCLAIMER and shown("JgDisclaimer"),"Fiction disclaimer shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func sorts_disabled(reason:String,label:String)->void:
	var all:=true
	for dest in JG.DESTS:
		for ore in JG.ORES:
			var b:=button("JgSort_%s_%s"%[dest,ore])
			all=all and b!=null and b.disabled and b.tooltip_text==reason
	check(all,"All nine sort buttons disabled with 「%s」 (%s)"%[reason,label])
	check(label_text("JgSortReason")==reason and shown("JgSortReason"),"Sort reason shown once (%s): %s"%[label,label_text("JgSortReason")])

func ship_state(dest:String,enabled:bool,reason:String,label:String)->void:
	var b:=button("JgShip_"+dest)
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"Ship %s %s (%s)"%[dest,"enabled" if enabled else "disabled",label])
	if b!=null and not enabled:check(b.tooltip_text==reason,"Ship %s tooltip 「%s」 (%s): %s"%[dest,reason,label,b.tooltip_text])
	check(label_text("JgShipReason_"+dest)==reason and shown("JgShipReason_"+dest)==not reason.is_empty(),"Ship %s reason line 「%s」 (%s): %s"%[dest,reason,label,label_text("JgShipReason_"+dest)])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase(JG.STATE_KEY)  # PRESET
	w.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":false}  # PRESET
	(w.state.bobo_workshop.done as Dictionary).erase(id)  # PRESET
	w.state.bobo_workshop.jobs={}  # PRESET
	w.state.time=30.0  # PRESET (day 1, spring)
	w.state.festival_story_open=false  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	w.state.objects.erase(k(BUILD_CELL))  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for item in ["gold_ore","copper_ore","stone",JG.LANTERN_ITEM]:bag()[item]=0  # PRESET
	await refresh()

func entry_of(expected_layout:String,label:String)->Button:
	check(layout_name()==expected_layout,"E opens %s (%s): %s"%[expected_layout,label,layout_name()])
	var entry:=button("JgRevisitEntry")
	check(entry!=null and entry.is_visible_in_tree(),"%s offers the revisit entry (%s)"%[expected_layout,label])
	return entry

func locked_flow(label:String)->void:
	await stand(TABLE_SPOT)
	check(str(app.view.interaction_focus())=="bobo_sort","Table focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(UI.tracker_text(snap()).is_empty() and not tracker().begins_with("礦料調度"),"No revisit tracker before the hoist (%s): %s"%[label,tracker()])
	await interact_key()
	var entry:=entry_of("bobo_sort","locked table "+label)
	check(shown("SortSurveyJournal"),"Bobo page keeps its journal button (%s)"%label)
	if entry!=null:check(entry.text==UI.ENTRY_LOCKED and entry.tooltip_text==JG.LOCKED,"Locked entry caption and reason (%s): %s"%[label,entry.text])
	if await enter_on("JgRevisitEntry","locked "+label):
		check(page_open(),"Locked entry opens the page (%s)"%label)
		check(shown("JgHold") and label_text("JgHoldText")==JG.LOCKED,"Lock reason on the page (%s): %s"%[label,label_text("JgHoldText")])
		check(not shown("JgCrates") and not shown("JgClaimCard") and not shown("JgSortPractice"),"No controls while locked (%s)"%label)
		focus_ok("locked "+label)
		layout_ok("locked "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)
	# The other two entrances say the same.
	await stand(SHUTTLE_SPOT)
	check(str(app.view.interaction_focus())=="transit:shuttle","Shuttle focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	entry=entry_of("travel_map","locked shuttle "+label)
	check(shown("TravelDepart") and shown("TravelLocalMap"),"Ticket page keeps depart and map (%s)"%label)
	if entry!=null:check(entry.text==UI.ENTRY_LOCKED,"Shuttle entry locked (%s)"%label)
	await key(KEY_ESCAPE)
	await stand(HOIST_SPOT)
	check(str(app.view.interaction_focus())=="mine_site:entry","Entry sign focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	entry=entry_of("mine_station","locked hoist "+label)
	check(shown("MineEnter") and shown("MineSurveyJournal"),"Mine entry card keeps 進入第一層 and the journal (%s)"%label)
	if entry!=null:check(entry.text==UI.ENTRY_LOCKED,"Hoist entry locked (%s)"%label)
	await key(KEY_ESCAPE)

func not_ready_flow(label:String)->void:
	w.state.mine_depths.hoist=true  # PRESET
	await stand(TABLE_SPOT)
	check(UI.tracker_text(snap()).is_empty() and not tracker().begins_with("礦料調度"),"Not ready: the Bobo story tracker stays (%s): %s"%[label,tracker()])
	await interact_key()
	var entry:=entry_of("bobo_sort","not ready "+label)
	if entry!=null:check(entry.text==UI.ENTRY_OPEN and entry.tooltip_text.is_empty(),"Unlocked entry caption (%s): %s"%[label,entry.text])
	if await enter_on("JgRevisitEntry","not ready "+label):
		check(page_open() and label_text("JgHoldText")==JG.NOT_READY,"Catch-up message (%s): %s"%[label,label_text("JgHoldText")])
		check(not shown("JgCrates") and shown("JgSortPractice"),"No crates, link to the sorting table (%s)"%label)
		check(focused_name()=="JgSortPractice","Focus on the sorting-table link (%s): %s"%[label,focused_name()])
		layout_ok("not ready "+label)
		await act_key(KEY_ENTER)
		check(layout_name()=="bobo_sort","Link opens Bobo's sorting table (%s): %s"%[label,layout_name()])
	await close_page()
	w.state.bobo_workshop.done[id]=true  # PRESET
	await refresh()

func table_flow(label:String)->void:
	await stand(TABLE_SPOT)
	check(tracker().begins_with("礦料調度・春季訂單\n到整理桌分揀 0／3 箱"),"Tracker shows the order (%s): %s"%[label,tracker()])
	await interact_key()
	entry_of("bobo_sort","table "+label)
	check(shown("SortStart"),"Bobo's own sort start is still there (%s)"%label)
	if not await enter_on("JgRevisitEntry","table "+label):return
	check(page_open(),"Entry opens the revisit page (%s): %s"%[label,layout_name()])
	if not page_open():return
	check(label_text("JgDay").begins_with("春季的訂單・第 1 日・金瓜石"),"Season/day line (%s): %s"%[label,label_text("JgDay")])
	check(label_text("JgReason")=="波波　「"+JG.REASONS.spring+"」","Bobo's reason (%s): %s"%[label,label_text("JgReason")])
	check(label_text("JgCrateName_bobo")=="波波的整理桌（23,20）" and label_text("JgCrateName_ferry")=="渡口家園工坊（11,20）" and label_text("JgCrateName_depot")=="坑內礦務站（28,19）","Crate names with their points (%s)"%label)
	check(label_text("JgCrateHow_ferry")==JG.DEST_HOW.ferry and label_text("JgCrateHow_depot")==JG.DEST_HOW.depot,"How each crate is sent (%s)"%label)
	check(label_text("JgCrateNeed_bobo")=="訂單：含金礦料 ×2・背包 0" and label_text("JgCrateNeed_ferry")=="訂單：銅礦 ×4・背包 0" and label_text("JgCrateNeed_depot")=="訂單：石材 ×6・背包 0","Needed ore, amount and bag (%s): %s"%[label,label_text("JgCrateNeed_bobo")])
	check(label_text("JgCrateNow_bobo")=="分揀：還沒分揀","Unsorted (%s)"%label)
	check(label_text("JgCrateMark_bobo")==UI.MARK_OPEN+UI.MARK_HERE and label_text("JgCrateMark_ferry")==UI.MARK_OPEN,"Marks: you are at the table (%s): %s"%[label,label_text("JgCrateMark_bobo")])
	ship_state("bobo",false,JG.UNSORTED%"波波的整理桌","unsorted "+label)
	ship_state("ferry",false,JG.UNSORTED%"渡口家園工坊","unsorted "+label)
	check(not shown("JgSortReason") and not button("JgSort_bobo_gold_ore").disabled,"Sorting allowed at the table (%s)"%label)
	check(button("JgClaim").disabled and label_text("JgClaimReason")==JG.NOT_DONE,"Claim waits (%s)"%label)
	check(focused_name()=="JgSort_bobo_stone","Focus starts on the first crate's sort buttons (%s): %s"%[label,focused_name()])
	layout_ok("nothing sorted "+label)
	# Sort 波波 → 含金礦料 with the arrows and Enter.
	var modal_before:Node=app.modal
	var card_before:=control("JgCrate_bobo")
	await key(KEY_RIGHT);await key(KEY_RIGHT)
	check(focused_name()=="JgSort_bobo_gold_ore","KEY_RIGHT ×2 reaches 含金礦料 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(str(crates().bobo)=="gold_ore" and feedback()==JG.SORT_OK%["含金礦料","波波的整理桌"],"KEY_ENTER sorts through the server (%s): %s"%[label,feedback()])
	check(app.modal==modal_before and control("JgCrate_bobo")==card_before,"Page updated in place (%s)"%label)
	check(focused_name()=="JgSort_bobo_gold_ore","Focus stays on the pressed button (%s): %s"%[label,focused_name()])
	check(button("JgSort_bobo_gold_ore").button_pressed and not button("JgSort_bobo_stone").button_pressed,"Current sort shown pressed (%s)"%label)
	check(label_text("JgCrateNow_bobo")=="分揀：含金礦料 ✓","Sorted ✓ (%s): %s"%[label,label_text("JgCrateNow_bobo")])
	check(tracker().begins_with("礦料調度・春季訂單\n到整理桌分揀 1／3 箱"),"Tracker counts sorted crates (%s): %s"%[label,tracker()])
	# Wrong assignment: 渡口 → 石材.
	await key(KEY_RIGHT)
	check(focused_name()=="JgSort_ferry_stone","KEY_RIGHT into the ferry crate (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(str(crates().ferry)=="stone","Ferry crate sorted to 石材 (%s)"%label)
	check(label_text("JgCrateNow_ferry")=="分揀：石材 ✗ 不符訂單","Wrong ✗ shown (%s): %s"%[label,label_text("JgCrateNow_ferry")])
	ship_state("ferry",false,JG.WRONG_ORE%["渡口家園工坊","石材","銅礦"],"wrong "+label)
	ship_state("bobo",false,JG.OTHER_WRONG%"波波的整理桌","wrong "+label)
	focus_ok("wrong "+label)
	layout_ok("wrong assignment "+label)
	await key(KEY_RIGHT)
	await act_key(KEY_ENTER)
	check(str(crates().ferry)=="copper_ore","Ferry fixed to 銅礦 (%s)"%label)
	await key(KEY_RIGHT);await key(KEY_RIGHT)
	check(focused_name()=="JgSort_depot_stone","KEY_RIGHT into the depot crate (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(crates()==JG.order(w.state),"All three crates match the order (%s): %s"%[label,str(crates())])
	# Short of ore.
	ship_state("bobo",false,JG.SHORT%["含金礦料",2,0],"short "+label)
	ship_state("ferry",false,JG.SHORT%["銅礦",4,0],"short "+label)
	layout_ok("short of ore "+label)
	bag().gold_ore=2;bag().copper_ore=4;bag().stone=6  # PRESET
	await refresh()
	ship_state("bobo",true,"","stocked "+label)
	ship_state("ferry",false,UI.AWAY_SHIP%["山城接駁站",11,20],"far ferry "+label)
	ship_state("depot",false,UI.AWAY_SHIP%["下坑路牌",28,19],"far depot "+label)
	check(label_text("JgCrateNeed_bobo")=="訂單：含金礦料 ×2・背包 2","Bag count in place (%s): %s"%[label,label_text("JgCrateNeed_bobo")])
	await key(KEY_DOWN)
	check(focused_name()=="JgShip_depot","KEY_DOWN from a crate's sort buttons goes to that crate's 送出 (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT);await key(KEY_LEFT)
	check(focused_name()=="JgShip_bobo","KEY_LEFT to the table crate (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(JG.sent(w.state)==["bobo"] and int(bag().gold_ore)==0,"Table crate sent through the server (%s): %s"%[label,str(JG.sent(w.state))])
	check(feedback()==JG.SHIP_OK%["波波的整理桌","含金礦料",2,1],"Ship reply (%s): %s"%[label,feedback()])
	check(page_open() and label_text("JgCrateMark_bobo")==UI.MARK_SENT and not shown("JgShip_bobo"),"Sent mark, button gone (%s)"%label)
	sorts_disabled(JG.SENT_LOCKED,"partly sent "+label)
	focus_ok("partly sent "+label)
	layout_ok("partly sent "+label)
	check(focused_name()=="JgShip_ferry","Focus moves to the next crate's 送出 (it says where to go) (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="JgSort_ferry_copper_ore","KEY_UP from 送出 to that crate's current sort (%s): %s"%[label,focused_name()])
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)
	check(tracker().begins_with("礦料調度・已送出 1／3\n下一箱：山城接駁站"),"Tracker names the next point (%s): %s"%[label,tracker()])

func shuttle_flow(label:String)->void:
	await stand(SHUTTLE_SPOT)
	await interact_key()
	var entry:=entry_of("travel_map","shuttle "+label)
	if entry!=null:check(entry.text==UI.ENTRY_OPEN,"Shuttle entry open (%s)"%label)
	check(shown("TravelDepart"),"Ticket page still offers 搭乘出發 (%s)"%label)
	if not await enter_on("JgRevisitEntry","shuttle "+label):return
	check(page_open() and focused_name()=="JgShip_ferry","Opened at the shuttle with focus on the ferry crate (%s): %s"%[label,focused_name()])
	check(label_text("JgCrateMark_ferry")==UI.MARK_OPEN+UI.MARK_HERE,"You are at the shuttle (%s)"%label)
	sorts_disabled(JG.SENT_LOCKED,"shuttle "+label)
	await act_key(KEY_ENTER)
	check(JG.sent(w.state)==["bobo","ferry"] and int(bag().copper_ore)==0,"Ferry crate sent at the shuttle (%s): %s"%[label,str(JG.sent(w.state))])
	check(feedback()==JG.SHIP_OK%["渡口家園工坊","銅礦",4,2],"Second ship reply (%s): %s"%[label,feedback()])
	focus_ok("after ferry "+label)
	check(button("JgBack")!=null and button("JgBack").text==UI.BACK_TEXT.ferry,"Back button names the ticket page (%s)"%label)
	await enter_on("JgBack","back to ticket "+label)
	check(layout_name()=="travel_map","Back returns to the ticket page (%s): %s"%[label,layout_name()])
	await key(KEY_ESCAPE)

func hoist_flow(label:String)->void:
	await stand(HOIST_SPOT)
	await interact_key()
	entry_of("mine_station","hoist "+label)
	check(shown("MineEnter") and shown("MineHoistReady"),"Entry card keeps 進入第一層 and the hoist note (%s)"%label)
	if not await enter_on("JgRevisitEntry","hoist "+label):return
	check(page_open() and focused_name()=="JgShip_depot","Opened at the hoist with focus on the depot crate (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(JG.completed(w.state) and feedback()==JG.COMPLETE_OK,"Third crate completes (%s): %s"%[label,feedback()])
	check(page_open(),"Page stays open on completion (%s)"%label)
	check(label_text("JgStatus")==UI.STATUS_DONE and label_text("JgDay").contains("三箱都送到了"),"Completion state (%s): %s"%[label,label_text("JgStatus")])
	for dest in JG.DESTS:check(label_text("JgCrateMark_"+dest)==UI.MARK_SENT,"%s ✓ (%s)"%[dest,label])
	check(not shown("JgSortRow_bobo") and not shown("JgSortReason"),"Sort buttons hidden after completion (%s)"%label)
	check(button("JgClaim").disabled and label_text("JgClaimReason")==UI.AWAY_CLAIM%[23,20],"Claim says where to go (%s): %s"%[label,label_text("JgClaimReason")])
	focus_ok("completed "+label)
	layout_ok("completed unclaimed "+label)
	await key(KEY_ESCAPE)
	check(tracker().begins_with("礦料調度完成\n到整理桌找波波領礦燈"),"Tracker sends me to Bobo (%s): %s"%[label,tracker()])

func claim_flow(label:String)->void:
	await stand(TABLE_SPOT)
	var next:=app.hud.find_child("TrackerNext",true,false) as Button
	check(next!=null and next.text=="打開礦料調度  →" and next.is_visible_in_tree(),"Tracker button opens the revisit (%s): %s"%[label,next.text if next else "none"])
	await click_control(next)
	await refresh()
	check(page_open() and focused_name()=="JgClaim","Tracker click opens the page, focus on 領取 (%s): %s / %s"%[label,layout_name(),focused_name()])
	if not page_open():return
	await act_key(KEY_ENTER)
	check(int(bag().get(JG.LANTERN_ITEM,0))==1 and feedback()==JG.CLAIM_OK,"Claim through the server (%s): %s"%[label,feedback()])
	check(label_text("JgStatus")==UI.STATUS_CLAIMED and button("JgClaim").disabled and label_text("JgClaimReason")==JG.CLAIMED,"Claimed state (%s): %s"%[label,label_text("JgClaimReason")])
	focus_ok("claimed "+label)
	layout_ok("claimed "+label)
	await key(KEY_ESCAPE)
	check(tracker().begins_with("礦料調度完成\n礦燈可擺在家園了"),"Tracker after claiming (%s): %s"%[label,tracker()])
	# Bobo's journal page carries the revisit line.
	app._journal("bobo")
	await settle()
	check(label_text("BoboRevisitLine")=="✓ 礦料調度完成・礦燈已領，可擺在家園","Journal line on Bobo's page (%s): %s"%[label,label_text("BoboRevisitLine")])
	await close_page()

func lantern_flow(label:String)->void:
	await stand(BUILD_SPOT,World.REGIONS.HOME)
	clear_tile(BUILD_CELL)
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	await click_control(tab)
	var slot:=button("BuildSlot_mine_lantern_3")
	check(slot!=null and slot.is_visible_in_tree(),"礦燈 on the 生活 page (%s)"%label)
	var shelf:Node=slot.get_parent() if slot!=null else null
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:
		(shelf as ScrollContainer).ensure_control_visible(slot)
		await settle()
		check((shelf as Control).get_global_rect().grow(0.5).encloses(slot.get_global_rect()),"礦燈 slot scrolled into view (%s)"%label)
	await click_control(slot)
	check(label_text("BuildTitle")=="礦燈","Recipe card shows 礦燈 after a click (%s): %s"%[label,label_text("BuildTitle")])
	var place:=button("BuildPlace")
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	await click_control(place)
	check(str(app.building)==JG.LANTERN_KIND and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 礦燈 by clicks (%s): %s %s"%[label,app.building,app.selected])
	await click_cell(BUILD_CELL)
	var obj:Dictionary=w.state.objects.get(k(BUILD_CELL),{})
	check(str(obj.get("type",""))==JG.LANTERN_KIND and str(obj.get("owner",""))==id,"Click placed 礦燈 (%s): %s"%[label,str(obj)])
	check(int(bag().get(JG.LANTERN_ITEM,0))==0 and not w.blocked(BUILD_CELL),"Kit used; lantern does not block (%s)"%label)
	app._select_tool("hoe")
	await stand(LANTERN_SPOT,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(BUILD_CELL),"Lantern focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(BUILD_CELL))==JG.LANTERN_NAME,"Lantern prompt (%s)"%label)
	await interact_key()
	check(layout_name()==UI.CARD_LAYOUT,"E at the lantern opens its card (%s): %s"%[label,layout_name()])
	check(Array(texts().split("\n")).count(JG.LANTERN_NAME)==1 and label_text("LanternBlurb")==JG.LANTERN_BLURB and label_text("LanternSource")==JG.LANTERN_SOURCE and label_text("LanternProject")==JG.LANTERN_PROJECT,"Card texts (%s): %s"%[label,texts().replace("\n"," | ")])
	check(label_text("LanternOwner")=="擺放者・礦燈旅人","Card names who placed it (%s): %s"%[label,label_text("LanternOwner")])
	var pic:=control("LanternIcon") as TextureRect
	check(pic!=null and pic.texture==Art.lantern_texture(),"Card shows the lantern art (%s)"%label)
	layout_ok("lantern card "+label,UI.CARD_LAYOUT)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the card (%s)"%label)

func inventory_flow(label:String)->void:
	bag()[JG.LANTERN_ITEM]=1  # PRESET
	await refresh()
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item(JG.LANTERN_ITEM)
		await settle()
		check(panel.detail_name.text=="礦燈" and panel.detail_count.text=="持有 1","Lantern name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.begins_with("紀念物・") and panel.detail_use.text.contains("「生活」") and panel.detail_use.text.contains("不會照明") and panel.detail_use.text.contains(app.binding_label("build_menu")),"Lantern usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_value.text=="紀念物・不能出售或交易","Lantern value line (%s): %s"%[label,panel.detail_value.text])
		check(panel.detail_icon.texture==Items.icon(JG.LANTERN_ITEM) and panel.detail_icon.texture==Art.lantern_texture() and panel.detail_icon.texture!=Items.icon("lantern_post_kit"),"Lantern icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use) and not_cut(panel.detail_value) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Lantern texts whole (%s)"%label)
	await close_page()
	bag()[JG.LANTERN_ITEM]=0  # PRESET
	await refresh()

func exhibit_flow(label:String)->void:
	w.state.festival_story_open=true  # PRESET
	write_lanyang()
	await stand(STAND_SPOT,World.REGIONS.HOME)
	check(Exhibit.on_display_ids(snap())==["lanyang","jinguashi"],"Two exhibits on display (%s): %s"%[label,str(Exhibit.on_display_ids(snap()))])
	check(ExhibitUI.news_line(snap())=="地方記憶展：2 件展出・2 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%2,"Journal and home tracker count two new exhibits (%s)"%label)
	check(ExhibitUI.stand_title(snap(),false)=="地方記憶展・新","Stand label 新 (%s)"%label)
	await interact_key()
	check(layout_name()==ExhibitUI.LAYOUT,"E at the stand opens the exhibit (%s): %s"%[label,layout_name()])
	if layout_name()!=ExhibitUI.LAYOUT:return
	check(focused_name()=="MemoryCard_lanyang","Focus on the first unread card (%s): %s"%[label,focused_name()])
	check(label_text("MemoryBadge_lanyang")==ExhibitUI.BADGE_NEW and label_text("MemoryBadge_jinguashi")==ExhibitUI.BADGE_NEW and label_text("MemoryStatus_jinguashi")==ExhibitUI.STATUS_ON,"Both cards 新・展出中 (%s)"%label)
	check((control("MemoryIcon_jinguashi") as TextureRect).texture==Art.lantern_texture(),"Lantern card icon (%s)"%label)
	check(label_text("MemoryHint")==Exhibit.personal_hint(snap()) and label_text("MemoryFirstShare").contains("第一次分水"),"分水木牌 selected: its own progress (unchanged) (%s): %s"%[label,label_text("MemoryHint")])
	await key(KEY_RIGHT)
	check(focused_name()=="MemoryCard_jinguashi","KEY_RIGHT to 礦燈 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="礦燈" and label_text("MemoryBlurb")==JG.LANTERN_BLURB,"礦燈 detail (%s): %s"%[label,label_text("MemoryDetailName")])
	check(label_text("MemorySource").contains(JG.LANTERN_SOURCE) and label_text("MemorySource").contains(JG.LANTERN_PROJECT),"Source and project (%s): %s"%[label,label_text("MemorySource")])
	check(label_text("MemoryDay").begins_with("完成那天：第 1 日") and label_text("MemoryDemand").begins_with("春季的訂單：波波的整理桌 含金礦料 2") and label_text("MemoryGates")=="送出的先後：波波的整理桌、渡口家園工坊、坑內礦務站","Lantern lines (%s): %s / %s / %s"%[label,label_text("MemoryDay"),label_text("MemoryDemand"),label_text("MemoryGates")])
	check(label_text("MemoryDisclaimer")==JG.DISCLAIMER,"Lantern disclaimer (%s)"%label)
	check(label_text("MemoryHint")==Exhibit.HINT_JG_CLAIMED and label_text("MemoryFirstShare")=="✓ 已跟波波整理過礦樣" and label_text("MemoryPlaque")=="✓ 已領礦燈","Lantern progress box (%s): %s"%[label,label_text("MemoryHint")])
	check((control("MemoryDetailIcon") as TextureRect).texture==Art.lantern_texture(),"Detail icon is the lantern (%s)"%label)
	layout_ok("exhibit lantern "+label,ExhibitUI.LAYOUT)
	await key(KEY_DOWN)
	check(focused_name()=="MemoryRecap","KEY_DOWN to 翻閱回顧 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 1／4・回訪的緣由","Lantern recap page 1 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("lantern recap 1 "+label,ExhibitUI.LAYOUT)
	var counter:int=app.session.counter
	await act_key(KEY_ENTER)
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 3／4・怎麼分揀與寄運" and label_text("MemoryPageLines").contains("展台沒有記錄是誰分揀、誰寄運"),"Lantern recap page 3 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("lantern recap 3 "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	check(app.session.counter==counter+1 and "jinguashi" in Exhibit.seen_ids(w.state,id),"Last page sends exhibit_view once (%s): %d"%[label,app.session.counter-counter])
	check(feedback()==Exhibit.VIEW_OK%"礦燈","Server reply (%s): %s"%[label,feedback()])
	check(label_text("MemoryPageTitle")=="回顧 4／4・帶回家的紀念","Last page (%s)"%label)
	check(label_text("MemoryBadge_jinguashi")==ExhibitUI.BADGE_SEEN and label_text("MemoryBadge_lanyang")==ExhibitUI.BADGE_NEW,"Only the lantern badge clears (%s)"%label)
	check(ExhibitUI.news_line(snap())=="地方記憶展：2 件展出・1 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%1,"Counts follow (%s)"%label)
	layout_ok("lantern recap last "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	await key(KEY_UP)
	check(focused_name()=="MemoryCard_jinguashi","KEY_UP to the chosen card (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="分水木牌" and label_text("MemoryHint")==Exhibit.personal_hint(snap()) and label_text("MemoryPlaque").contains("分水木牌"),"Back on 分水木牌: Lanyang progress again (%s): %s"%[label,label_text("MemoryHint")])
	await key(KEY_ESCAPE)

func size_flow(label:String)->void:
	await reset()
	await locked_flow(label)
	await not_ready_flow(label)
	await table_flow(label)
	await shuttle_flow(label)
	await hoist_flow(label)
	await claim_flow(label)
	await lantern_flow(label)
	await inventory_flow(label)
	await exhibit_flow(label)

func pure_checks()->void:
	var s:Dictionary={"time":30.0,"region_id":"jinguashi"}
	check(UI.tracker_text(s).is_empty() and UI.entry_caption(s)==UI.ENTRY_LOCKED,"No tracker and a locked caption before the hoist")
	s.mine_depths={"hoist":true}
	check(UI.tracker_text(s).is_empty() and UI.entry_caption(s)==UI.ENTRY_OPEN,"No revisit tracker for a player who has not sorted with Bobo")
	s.bobo_workshop={"own_done":true}
	check(UI.tracker_text(s)=="礦料調度・春季訂單\n到整理桌分揀 0／3 箱","Ready tracker")
	var person:={"x":12.5,"y":20.5,"inventory":{"copper_ore":4}}
	s[JG.STATE_KEY]={"crates":JG.order_for("spring"),"day":1,"sent":["bobo"],"completed":false,"done_day":0}
	check(UI.standing_dest(s,person)=="ferry" and UI.ship_reason(s,person,"ferry").is_empty(),"At the shuttle the ferry crate can be sent")
	check(UI.ship_reason(s,person,"depot")==JG.SHORT%["石材",6,0],"Rules reason before the place")
	check(UI.sort_reason(s,person)==JG.SENT_LOCKED and UI.claim_reason(s,person)==JG.NOT_DONE,"Sort / claim reasons from the rules")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("jinguashi-revisit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"礦燈旅人",path)!=OK:check(false,"Host starts");finish();return
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
