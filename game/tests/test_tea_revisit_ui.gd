extends SceneTree
## 第 40 章「貓空與鶯歌回訪・茶罐大單」頁＋「茶陶組」(背包、家園工坊「生活」頁、訪客卡片)＋地方記憶展的
## 第三件展品 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_jinguashi_revisit_ui.gd: real Session host, real snapshot round trips.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set
##    here (the runner passes no flag for this suite);
##  * chapter one complete (state.board / picnic / chapter_one.shipped / watered), as
##    test_tea_ceramics_ui does;
##  * PERSONAL: my tea_ceramics record = FRESH with intro / potter / potter_story / trials /
##    reused / tea_discussed = true and comparison_complete = false (not-ready page) then true;
##    the earned comparison chain is covered by test_tea_revisit(_session) and the journey;
##  * state.tea_revisit, my tea ware kit and placed tea ware, player.memory_exhibit are ERASED
##    before each size; state.time = day 1 (spring);
##  * jar and tea counts in my bag (tea_returned_jar 2 / tea_worn_jar 1, later +1 and 3 worn;
##    one tea_jar and one tea_spent_jar for the refusal note; tea_light 5 / tea_deep 3);
##  * the local player is teleported by writing region/x/y (no walking or travel);
##  * memory exhibit: state.festival_story_open=true, the 蘭陽 unlock and a completed
##    lanyang_revisit record (as test_jinguashi_revisit_ui writes them), state.mine_depths.hoist,
##    bobo_workshop.done[me] and a completed jinguashi_revisit record, so three exhibits are on
##    display (the tea order itself is the one this suite completed through the server);
##  * removed-tile entry for the build cell; session rate buckets / action_clock cleared.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._interact at the 鶯歌 potter (20,20) and the 貓空
##    packing table (26,20); the existing tea pages keep their own actions; the
##    「貓空與鶯歌回訪・茶罐大單」 entry is pressed with KEY_ENTER; KEY_LEFT / RIGHT / UP / DOWN
##    move focus; KEY_ENTER on the focused jar / fill / send / claim buttons sends
##    tea_revisit_jar / _fill / _send / _claim through Session.perform -> World -> snapshot ->
##    in-place update; KEY_ESCAPE closes; the tracker card button (real mouse click);
##  * every jar, fill, send and claim is the server's (no revisit writes after the reset):
##    six jars handed in, NEED_JARS / QUOTA_FULL / ALL_FILLED refusals shown as reasons,
##    completion, the tea ware in the bag;
##  * placing the tea ware: build folio -> 「生活」 tab -> slot -> BuildPlace (real mouse clicks)
##    -> real world click; KEY_E at the placed tea ware opens its card;
##  * the backpack detail (InventoryPanel.select_item) of the kit;
##  * the memory exhibit page with three exhibits: KEY_E at the stand, arrows + Enter to the
##    陶器 card and through its 4 recap pages; the last page sends exhibit_view.
## NOT COVERED HERE: world pixels (test_tea_revisit_scene.gd); gamepad input (only the focus
## neighbours it uses, through the arrow keys); the non-preview layout; a second client;
## walking between 貓空 and 鶯歌 (test_tea_revisit_session / the journey).
const World=preload("res://scripts/world.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const UI=preload("res://scripts/tea_revisit_ui.gd")
const Art=preload("res://scripts/tea_revisit_art.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
## Standing spots used by the rules tests (all walkable).
const POTTER_SPOT:=Vector2(20.5,21.5)
const PACKER_SPOT:=Vector2(26.5,21.5)
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
const TEAWARE_SPOT:=Vector2(43.5,35.6)
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
	print("TEA_REVISIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE TEA_REVISIT_UI "+message)

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

func tea_site()->String:
	return str((app.modal as Node).get_meta("tea_site","")) if is_instance_valid(app.modal) else ""

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

func k(c:Vector2i)->String:
	return World.key(c)

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func tea_record()->Dictionary:
	return w.state.tea_ceramics.players[id]

## Disclosed lanyang fixture (first exhibit) and a completed jinguashi record (second).
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
		check(label_text("TrDisclaimer")==TR.DISCLAIMER and shown("TrDisclaimer"),"Fiction disclaimer shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func button_state(name:String,enabled:bool,reason:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"%s %s (%s)"%[name,"enabled" if enabled else "disabled",label])
	if b!=null and not enabled:check(b.tooltip_text==reason,"%s tooltip 「%s」 (%s): %s"%[name,reason,label,b.tooltip_text])

func not_revisit_tracker(label:String)->void:
	check(not tracker().begins_with("茶罐大單") and UI.tracker_text(snap(),id).is_empty(),"Tea notebook keeps the tracker (%s): %s"%[label,tracker()])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	var rec:Dictionary=Tea.FRESH.duplicate(true)
	for field in ["intro","potter","potter_story","reused","tea_discussed"]:rec[field]=true  # PRESET
	rec.trials={"jar":true,"fiber":true}  # PRESET
	w.state.tea_ceramics.players[id]=rec  # PRESET (comparison_complete false)
	w.state.erase(TR.STATE_KEY)  # PRESET
	w.state.time=30.0  # PRESET (day 1, spring)
	w.state.festival_story_open=false  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	w.state.erase(JG.STATE_KEY)  # PRESET
	w.state.objects.erase(k(BUILD_CELL))  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for item in ["tea_returned_jar","tea_worn_jar","tea_jar","tea_spent_jar","tea_light","tea_deep","tea_leaf","clay","fiber",TR.TEAWARE_ITEM]:bag()[item]=0  # PRESET
	await refresh()

func entry_of(site:String,label:String)->Button:
	check(layout_name()=="tea_ceramics" and tea_site()==site,"E opens the tea %s page (%s): %s %s"%[site,label,layout_name(),tea_site()])
	var entry:=button("TeaRevisitEntry")
	check(entry!=null and entry.is_visible_in_tree() and entry.text==UI.ENTRY,"Tea %s page offers the revisit entry (%s)"%[site,label])
	check(button("TeaJournal")!=null and button("TeaJournal").is_visible_in_tree(),"Tea %s page keeps 翻閱茶陶手帳 (%s)"%[site,label])
	return entry

func open_at_potter(label:String)->void:
	await stand(POTTER_SPOT,"yingge")
	check(str(app.view.interaction_focus())=="tea:potter","Potter focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	entry_of("potter",label)
	await enter_on("TeaRevisitEntry","potter "+label)
	check(page_open(),"Entry opens the revisit page at the potter (%s): %s"%[label,layout_name()])

func open_at_packer(label:String)->void:
	await stand(PACKER_SPOT,"maokong")
	check(str(app.view.interaction_focus())=="tea:pack","Packer focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	entry_of("pack",label)
	await enter_on("TeaRevisitEntry","packer "+label)
	check(page_open(),"Entry opens the revisit page at the packer (%s): %s"%[label,layout_name()])

func not_ready_flow(label:String)->void:
	await open_at_potter("not ready "+label)
	if not page_open():return
	check(label_text("TrHoldText")==TR.NOT_READY and shown("TrHold"),"Catch-up message (%s): %s"%[label,label_text("TrHoldText")])
	check(not shown("TrCards") and not shown("TrClaimCard") and not shown("TrProgress") and shown("TrNotebook"),"No controls, link to the tea notebook (%s)"%label)
	check(label_text("TrDay").begins_with("春季的訂單・第 1 日・貓空") and label_text("TrReason")=="茶茶　「"+TR.REASONS.spring.trim_prefix("茶茶說，")+"」","Order day and 茶茶's reason (%s): %s"%[label,label_text("TrDay")])
	check(focused_name()=="TrNotebook","Focus on the notebook link (%s): %s"%[label,focused_name()])
	layout_ok("not ready "+label)
	await act_key(KEY_ENTER)
	check(layout_name()=="tea_ceramics" and tea_site()=="journal","Link opens the tea notebook (%s): %s %s"%[label,layout_name(),tea_site()])
	check(control("TeaRevisitLine")==null,"No revisit line in the notebook before the comparison (%s)"%label)
	await close_page()
	not_revisit_tracker("not ready "+label)
	tea_record().comparison_complete=true  # PRESET
	await refresh()

func yingge_flow(label:String)->void:
	bag().tea_jar=1;bag().tea_spent_jar=1  # PRESET (refusal note)
	await open_at_potter(label)
	if not page_open():return
	not_revisit_tracker("nothing handed "+label)
	check(not shown("TrHold") and shown("TrCards") and shown("TrClaimCard"),"Ready: cards shown (%s)"%label)
	check(label_text("TrProgress")=="回收空罐 0／6（回收陶罐 0、磨損陶罐 0）・已裝 0／6","Progress (%s): %s"%[label,label_text("TrProgress")])
	check(label_text("TrYinggeName")=="鶯歌・陶師的工作桌（20,20）" and label_text("TrMaokongName")=="貓空・包裝台（26,20）","Card titles with points (%s)"%label)
	check(label_text("TrJarNote")==UI.JAR_NOTE,"Only delivered jars count, handed jars are not returned (%s)"%label)
	check(label_text("TrJarOther")==TR.NEW_JAR+"\n"+TR.SPENT_JAR,"Why new and spent jars are refused (%s): %s"%[label,label_text("TrJarOther")])
	button_state("Tr_tea_returned_jar",false,TR.NO_JAR%"回收陶罐","nothing handed "+label)
	button_state("Tr_tea_worn_jar",false,TR.NO_JAR%"磨損陶罐","nothing handed "+label)
	check(label_text("TrJarReason")==TR.NO_JAR%"回收陶罐"+"\n"+TR.NO_JAR%"磨損陶罐","Jar reasons (%s): %s"%[label,label_text("TrJarReason")])
	button_state("Tr_light",false,TR.NEED_JARS%[0,0],"nothing handed "+label)
	check(label_text("TrFillReason")==TR.NEED_JARS%[0,0],"Fill reason shown once (%s): %s"%[label,label_text("TrFillReason")])
	button_state("TrSend",false,TR.NOT_FILLED%0,"nothing handed "+label)
	check(not shown("TrSendReason") and label_text("TrSendMark")=="○ 還沒寄出","Send waits quietly (%s)"%label)
	check(button("TrClaim").disabled and label_text("TrClaimReason")==TR.NOT_DONE and label_text("TrStatus")==UI.STATUS_OPEN,"Claim waits (%s)"%label)
	check(label_text("TrLine_light")=="淺焙 已裝 0／4・背包 0" and label_text("TrLine_deep")=="深焙 已裝 0／2・背包 0" and label_text("TrOrder")=="春季訂單：淺焙 4 罐、深焙 2 罐","Order rows (%s): %s"%[label,label_text("TrLine_light")])
	check(focused_name()=="Tr_tea_returned_jar","Focus rests on the first jar button (%s): %s"%[label,focused_name()])
	layout_ok("nothing handed "+label)
	# Hand in jars (written into the bag, handed in through the server).
	bag().tea_jar=0;bag().tea_spent_jar=0  # PRESET
	bag().tea_returned_jar=2;bag().tea_worn_jar=1  # PRESET
	await refresh()
	var modal_before:Node=app.modal
	var card_before:=control("TrYingge")
	check(not shown("TrJarOther") and not shown("TrJarReason"),"No refusal lines once jars can be handed in (%s)"%label)
	await act_key(KEY_ENTER)
	check(int(TR.jars(w.state).tea_returned_jar)==1 and int(bag().tea_returned_jar)==1 and feedback()==TR.JAR_OK%["回收陶罐",1],"KEY_ENTER hands in a jar through the server (%s): %s"%[label,feedback()])
	check(app.modal==modal_before and control("TrYingge")==card_before,"Page updated in place (%s)"%label)
	check(focused_name()=="Tr_tea_returned_jar","Focus stays on the pressed button (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="Tr_tea_worn_jar","KEY_DOWN to the worn jar (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	await key(KEY_UP)
	check(focused_name()=="Tr_tea_returned_jar","KEY_UP back (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(TR.jars_total(w.state)==3 and int(bag().tea_returned_jar)==0 and int(bag().tea_worn_jar)==0,"Three jars handed in (%s): %s"%[label,str(TR.jars(w.state))])
	check(label_text("TrProgress")=="回收空罐 3／6（回收陶罐 2、磨損陶罐 1）・已裝 0／6","Progress in place (%s): %s"%[label,label_text("TrProgress")])
	button_state("Tr_tea_returned_jar",false,TR.NO_JAR%"回收陶罐","partly handed "+label)
	check(label_text("TrLine_tea_returned_jar")=="回收陶罐・背包 0","Bag count in place (%s)"%label)
	await key(KEY_RIGHT)
	check(focused_name()=="Tr_light","KEY_RIGHT to the light fill (%s): %s"%[label,focused_name()])
	check(label_text("TrFillReason")==TR.NO_TEA%"淺焙茶"+"\n"+TR.NO_TEA%"深焙茶","No tea yet (%s): %s"%[label,label_text("TrFillReason")])
	focus_ok("partly handed "+label)
	layout_ok("partly handed "+label)
	not_revisit_tracker("partly handed, no tea "+label)
	# Tea in the bag: the rule allows filling, but this is 鶯歌 → say where to go.
	bag().tea_light=5;bag().tea_deep=3  # PRESET
	await refresh()
	var away:=UI.AWAY_FILL%[26,20]
	button_state("Tr_light",false,away,"wrong region "+label)
	button_state("Tr_deep",false,away,"wrong region "+label)
	check(label_text("TrFillReason")==away,"Wrong region: where to go, once (%s): %s"%[label,label_text("TrFillReason")])
	check(tracker()=="茶罐大單・已裝 0／6\n到貓空的包裝台裝淺焙、深焙","Tracker follows the order (%s): %s"%[label,tracker()])
	layout_ok("wrong region "+label)
	check(button("TrBack")!=null and button("TrBack").text==UI.BACK_TEXT.potter,"Back names the potter's table (%s)"%label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)

func maokong_flow(label:String)->void:
	bag().tea_worn_jar=1  # PRESET (a jar the rule would take, but not in 貓空)
	await open_at_packer(label)
	if not page_open():return
	check(focused_name()=="Tr_light","At the packer focus starts on the light fill (%s): %s"%[label,focused_name()])
	button_state("Tr_tea_worn_jar",false,UI.AWAY_JAR%[20,20],"jar in 貓空 "+label)
	check(label_text("TrJarReason").contains(UI.AWAY_JAR%[20,20]),"Jar card says to go to 鶯歌 (%s): %s"%[label,label_text("TrJarReason")])
	for n in [1,2,3]:
		await act_key(KEY_ENTER)
		check(int(TR.filled(w.state).light)==n and feedback()==TR.FILL_OK%["淺焙茶",n,n,0],"Light fill %d through the server (%s): %s"%[n,label,feedback()])
	check(int(TR.record(w.state).day)==1 and label_text("TrDay").begins_with("春季的訂單（第 1 日開始裝茶）"),"Order day stamped (%s): %s"%[label,label_text("TrDay")])
	var short:=TR.NEED_JARS%[3,3]
	button_state("Tr_light",false,short,"jars short "+label)
	button_state("Tr_deep",false,short,"jars short "+label)
	check(label_text("TrFillReason")==short,"Jars short reason (%s): %s"%[label,label_text("TrFillReason")])
	focus_ok("jars short "+label)
	layout_ok("jars short "+label)
	check(tracker()=="茶罐大單・空罐 3／6\n帶回收空罐到鶯歌交給陶師","Tracker sends me to 鶯歌 (%s): %s"%[label,tracker()])
	check(button("TrBack")!=null and button("TrBack").text==UI.BACK_TEXT.pack,"Back names the packing page (%s)"%label)
	await enter_on("TrBack","back "+label)
	check(layout_name()=="tea_ceramics" and tea_site()=="pack","Back returns to the packing page (%s): %s"%[label,tea_site()])
	await key(KEY_ESCAPE)

func jars_full_flow(label:String)->void:
	bag().tea_worn_jar=3  # PRESET
	await stand(POTTER_SPOT,"yingge")
	var next:=tracker_button()
	check(next!=null and next.text=="打開茶罐大單  →" and next.is_visible_in_tree(),"Tracker button opens the order (%s): %s"%[label,next.text if next else "none"])
	await click_control(next)
	await refresh()
	check(page_open() and focused_name()=="Tr_tea_worn_jar","Tracker click opens the page, focus on the usable jar (%s): %s / %s"%[label,layout_name(),focused_name()])
	if not page_open():return
	for n in [4,5,6]:
		await act_key(KEY_ENTER)
		check(TR.jars_total(w.state)==n,"Jar %d (%s)"%[n,label])
	button_state("Tr_tea_worn_jar",false,TR.JARS_FULL,"jars full "+label)
	button_state("Tr_tea_returned_jar",false,TR.JARS_FULL,"jars full "+label)
	check(label_text("TrJarReason")==TR.JARS_FULL,"Jars full reason once (%s): %s"%[label,label_text("TrJarReason")])
	layout_ok("jars full "+label)
	await key(KEY_ESCAPE)

func send_flow(label:String)->void:
	await open_at_packer("send "+label)
	if not page_open():return
	check(focused_name()=="Tr_light","Focus on the light fill (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(int(TR.filled(w.state).light)==4,"Fourth light jar (%s)"%label)
	var quota:=TR.QUOTA_FULL%["淺焙",4,4,"深焙"]
	button_state("Tr_light",false,quota,"quota full "+label)
	button_state("Tr_deep",true,"","quota full "+label)
	check(label_text("TrFillReason")==quota and label_text("TrLine_light")=="淺焙 已裝 4／4・背包 1 ✓","Quota full reason and ✓ (%s): %s"%[label,label_text("TrLine_light")])
	layout_ok("quota full "+label)
	await key(KEY_DOWN)
	check(focused_name()=="Tr_deep","KEY_DOWN to the deep fill (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	await act_key(KEY_ENTER)
	check(TR.filled(w.state)=={"light":4,"deep":2},"All six filled (%s): %s"%[label,str(TR.filled(w.state))])
	check(label_text("TrFillReason")==TR.ALL_FILLED,"All filled reason (%s): %s"%[label,label_text("TrFillReason")])
	button_state("TrSend",true,"","ready to send "+label)
	check(label_text("TrSendMark")=="○ 6 罐都裝好了" and not shown("TrSendReason"),"Ready-to-send mark (%s)"%label)
	check(tracker()=="茶罐大單・6 罐都裝好了\n到貓空的包裝台寄出","Tracker: send (%s): %s"%[label,tracker()])
	layout_ok("ready to send "+label)
	await key(KEY_DOWN)
	check(focused_name()=="TrSend","KEY_DOWN to 寄出 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(TR.completed(w.state) and feedback()==TR.COMPLETE_OK,"Order sent through the server (%s): %s"%[label,feedback()])
	check(page_open(),"Page stays open on completion (%s)"%label)
	check(label_text("TrStatus")==UI.STATUS_DONE and label_text("TrDay")=="春季的訂單・第 1 日寄出了" and label_text("TrSendMark")=="✓ 第 1 日寄出","Completion state (%s): %s"%[label,label_text("TrDay")])
	check(not shown("TrSend") and not shown("Tr_light") and not shown("Tr_tea_worn_jar") and not shown("TrFillReason") and not shown("TrJarReason"),"Order buttons and reasons hidden after sending (%s)"%label)
	check(button("TrClaim").disabled and label_text("TrClaimReason")==UI.AWAY_CLAIM%[20,20],"Claim says where to go (%s): %s"%[label,label_text("TrClaimReason")])
	check(focused_name()=="TrClaim","Focus moves to the claim row (%s): %s"%[label,focused_name()])
	focus_ok("completed "+label)
	layout_ok("completed unclaimed "+label)
	await key(KEY_ESCAPE)
	check(tracker()=="茶罐大單寄出了\n到鶯歌陶師那裡領茶陶組","Tracker sends me to the potter (%s): %s"%[label,tracker()])

func claim_flow(label:String)->void:
	await stand(POTTER_SPOT,"yingge")
	await click_control(tracker_button())
	await refresh()
	check(page_open() and focused_name()=="TrClaim","Tracker click opens the page, focus on 領取 (%s): %s / %s"%[label,layout_name(),focused_name()])
	if not page_open():return
	await act_key(KEY_ENTER)
	check(int(bag().get(TR.TEAWARE_ITEM,0))==1 and feedback()==TR.CLAIM_OK,"Claim through the server (%s): %s"%[label,feedback()])
	check(label_text("TrStatus")==UI.STATUS_CLAIMED and button("TrClaim").disabled and label_text("TrClaimReason")==TR.CLAIMED,"Claimed state (%s): %s"%[label,label_text("TrClaimReason")])
	focus_ok("claimed "+label)
	layout_ok("claimed "+label)
	await key(KEY_ESCAPE)
	not_revisit_tracker("claimed "+label)
	# The tea notebook carries the revisit line.
	app.TeaUI.open(app,"journal")
	await settle()
	check(label_text("TeaRevisitLine")=="✓ 茶罐大單寄出了・茶陶組已領，可擺在家園","Notebook line (%s): %s"%[label,label_text("TeaRevisitLine")])
	var line:=control("TeaRevisitLine")
	check(line!=null and line.is_visible_in_tree() and (app.modal as Control).get_global_rect().grow(0.5).encloses(line.get_global_rect()) and not_cut(line as Label),"Notebook line whole inside the page (%s)"%label)
	await close_page()

func teaware_flow(label:String)->void:
	await stand(BUILD_SPOT,World.REGIONS.HOME)
	clear_tile(BUILD_CELL)
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	await click_control(tab)
	var slot:=button("BuildSlot_tea_ware_3")
	check(slot!=null and slot.is_visible_in_tree(),"茶陶組 on the 生活 page (%s)"%label)
	var shelf:Node=slot.get_parent() if slot!=null else null
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:
		(shelf as ScrollContainer).ensure_control_visible(slot)
		await settle()
		check((shelf as Control).get_global_rect().grow(0.5).encloses(slot.get_global_rect()),"茶陶組 slot scrolled into view (%s)"%label)
	await click_control(slot)
	check(label_text("BuildTitle")=="茶陶組","Recipe card shows 茶陶組 after a click (%s): %s"%[label,label_text("BuildTitle")])
	check(texts().contains("茶壺和茶杯擺在木托盤上") and not texts().contains("上菜"),"Recipe card shows the 生活 blurb, no serving claim (%s)"%label)
	var place:=button("BuildPlace")
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	await click_control(place)
	check(str(app.building)==TR.TEAWARE_KIND and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 茶陶組 by clicks (%s): %s %s"%[label,app.building,app.selected])
	await click_cell(BUILD_CELL)
	var obj:Dictionary=w.state.objects.get(k(BUILD_CELL),{})
	check(str(obj.get("type",""))==TR.TEAWARE_KIND and str(obj.get("owner",""))==id,"Click placed 茶陶組 (%s): %s"%[label,str(obj)])
	check(int(bag().get(TR.TEAWARE_ITEM,0))==0 and not w.blocked(BUILD_CELL),"Kit used; tea ware does not block (%s)"%label)
	app._select_tool("hoe")
	await stand(TEAWARE_SPOT,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(BUILD_CELL),"Tea ware focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(BUILD_CELL))==TR.TEAWARE_NAME,"Tea ware prompt (%s)"%label)
	await interact_key()
	check(layout_name()==UI.CARD_LAYOUT,"E at the tea ware opens its card (%s): %s"%[label,layout_name()])
	check(label_text("TeawareName")==TR.TEAWARE_NAME and label_text("TeawareBlurb")==TR.TEAWARE_BLURB and label_text("TeawareSource")==TR.TEAWARE_SOURCE and label_text("TeawareProject")==TR.TEAWARE_PROJECT,"Card texts (%s): %s"%[label,texts().replace("\n"," | ")])
	check(label_text("TeawareOwner")=="擺放者・茶陶旅人","Card names who placed it (%s): %s"%[label,label_text("TeawareOwner")])
	check(not texts().contains("上菜"),"Card does not claim the tea ware serves food (%s)"%label)
	var pic:=control("TeawareIcon") as TextureRect
	check(pic!=null and pic.texture==Art.teaware_texture(),"Card shows the tea ware art (%s)"%label)
	layout_ok("tea ware card "+label,UI.CARD_LAYOUT)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the card (%s)"%label)

func inventory_flow(label:String)->void:
	bag()[TR.TEAWARE_ITEM]=1  # PRESET
	await refresh()
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item(TR.TEAWARE_ITEM)
		await settle()
		check(panel.detail_name.text=="茶陶組" and panel.detail_count.text=="持有 1","Tea ware name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.begins_with("紀念物・") and panel.detail_use.text.contains("「生活」") and panel.detail_use.text.contains("只是裝飾") and panel.detail_use.text.contains(app.binding_label("build_menu")) and not panel.detail_use.text.contains("上菜"),"Tea ware usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_value.text=="紀念物・不能出售或交易","Tea ware value line (%s): %s"%[label,panel.detail_value.text])
		check(panel.detail_icon.texture==Items.icon(TR.TEAWARE_ITEM) and panel.detail_icon.texture==Art.teaware_texture() and panel.detail_icon.texture!=Items.icon("tea_jar"),"Tea ware icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use) and not_cut(panel.detail_value) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Tea ware texts whole (%s)"%label)
	await close_page()
	bag()[TR.TEAWARE_ITEM]=0  # PRESET
	await refresh()

func exhibit_flow(label:String)->void:
	w.state.festival_story_open=true  # PRESET
	write_other_exhibits()
	await stand(STAND_SPOT,World.REGIONS.HOME)
	check(Exhibit.on_display_ids(snap())==["lanyang","jinguashi","tea_pottery"],"Three exhibits on display (%s): %s"%[label,str(Exhibit.on_display_ids(snap()))])
	check(ExhibitUI.news_line(snap())=="地方記憶展：3 件展出・3 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%3,"Journal and home tracker count three new exhibits (%s)"%label)
	await interact_key()
	check(layout_name()==ExhibitUI.LAYOUT,"E at the stand opens the exhibit (%s): %s"%[label,layout_name()])
	if layout_name()!=ExhibitUI.LAYOUT:return
	check(focused_name()=="MemoryCard_lanyang","Focus on the first unread card (%s): %s"%[label,focused_name()])
	check(label_text("MemoryBadge_tea_pottery")==ExhibitUI.BADGE_NEW and label_text("MemoryStatus_tea_pottery")==ExhibitUI.STATUS_ON,"Third card 新・展出中 (%s)"%label)
	check((control("MemoryIcon_tea_pottery") as TextureRect).texture==Art.teaware_texture(),"陶器 card icon is the tea ware (%s)"%label)
	layout_ok("exhibit three "+label,ExhibitUI.LAYOUT)
	await key(KEY_RIGHT);await key(KEY_RIGHT)
	check(focused_name()=="MemoryCard_tea_pottery","KEY_RIGHT ×2 to 陶器 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="陶器" and label_text("MemoryBlurb")==TR.TEAWARE_BLURB,"陶器 detail (%s): %s"%[label,label_text("MemoryDetailName")])
	check(label_text("MemorySource").contains(TR.TEAWARE_SOURCE) and label_text("MemorySource").contains(TR.TEAWARE_PROJECT),"Source and project (%s): %s"%[label,label_text("MemorySource")])
	check(label_text("MemoryDay").begins_with("完成那天：第 1 日・貓空") and label_text("MemoryDemand")=="春季的訂單：淺焙 4 罐／深焙 2 罐" and label_text("MemoryGates")=="回收的空罐：回收陶罐 2 只、磨損陶罐 4 只","Tea lines (%s): %s / %s / %s"%[label,label_text("MemoryDay"),label_text("MemoryDemand"),label_text("MemoryGates")])
	check(label_text("MemoryDisclaimer")==TR.DISCLAIMER,"Tea disclaimer (%s)"%label)
	check(label_text("MemoryHint")==Exhibit.HINT_TEA_CLAIMED and label_text("MemoryFirstShare")=="✓ 已跟茶茶比較過兩種包裝" and label_text("MemoryPlaque")=="✓ 已領茶陶組","Tea progress box (%s): %s / %s / %s"%[label,label_text("MemoryHint"),label_text("MemoryFirstShare"),label_text("MemoryPlaque")])
	check((control("MemoryDetailIcon") as TextureRect).texture==Art.teaware_texture(),"Detail icon is the tea ware (%s)"%label)
	check(not texts().contains("上菜"),"Exhibit page does not claim serving (%s)"%label)
	layout_ok("exhibit tea "+label,ExhibitUI.LAYOUT)
	await key(KEY_DOWN)
	check(focused_name()=="MemoryRecap","KEY_DOWN to 翻閱回顧 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 1／4・回訪的緣由","Tea recap page 1 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("tea recap 1 "+label,ExhibitUI.LAYOUT)
	var counter:int=app.session.counter
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 2／4・訂單上的需要","Tea recap page 2 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("tea recap 2 "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryPageTitle")=="回顧 3／4・怎麼回收與裝罐" and label_text("MemoryPageLines").contains("展台沒有記錄是誰交罐、誰裝茶、誰寄出。"),"Tea recap page 3 (%s): %s"%[label,label_text("MemoryPageTitle")])
	layout_ok("tea recap 3 "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	check(app.session.counter==counter+1 and "tea_pottery" in Exhibit.seen_ids(w.state,id),"Last page sends exhibit_view once (%s): %d"%[label,app.session.counter-counter])
	check(feedback()==Exhibit.VIEW_OK%"陶器","Server reply (%s): %s"%[label,feedback()])
	check(label_text("MemoryPageTitle")=="回顧 4／4・帶回家的紀念","Last page (%s)"%label)
	check(label_text("MemoryBadge_tea_pottery")==ExhibitUI.BADGE_SEEN and label_text("MemoryBadge_lanyang")==ExhibitUI.BADGE_NEW and label_text("MemoryBadge_jinguashi")==ExhibitUI.BADGE_NEW,"Only the tea badge clears (%s)"%label)
	check(ExhibitUI.news_line(snap())=="地方記憶展：3 件展出・2 件還沒看" and ExhibitUI.tracker_text(snap())==ExhibitUI.TRACKER%2,"Counts follow (%s)"%label)
	layout_ok("tea recap last "+label,ExhibitUI.LAYOUT)
	await act_key(KEY_ENTER)
	await key(KEY_UP)
	check(focused_name()=="MemoryCard_tea_pottery","KEY_UP to the chosen card (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="礦燈" and label_text("MemoryHint")==Exhibit.personal_hint_for(snap(),"jinguashi") and label_text("MemoryFirstShare").contains("波波"),"Back on 礦燈: its own progress lines (%s): %s"%[label,label_text("MemoryFirstShare")])
	await key(KEY_LEFT)
	await act_key(KEY_ENTER)
	check(label_text("MemoryDetailName")=="分水木牌" and label_text("MemoryPlaque").contains("分水木牌"),"Back on 分水木牌: Lanyang progress (%s): %s"%[label,label_text("MemoryPlaque")])
	await key(KEY_ESCAPE)

func size_flow(label:String)->void:
	await reset()
	await not_ready_flow(label)
	await yingge_flow(label)
	await maokong_flow(label)
	await jars_full_flow(label)
	await send_flow(label)
	await claim_flow(label)
	await teaware_flow(label)
	await inventory_flow(label)
	await exhibit_flow(label)

func pure_checks()->void:
	var s:Dictionary={"time":30.0,"region_id":"yingge","players":{"me":{"x":20.5,"y":21.5,"inventory":{"tea_worn_jar":1}}}}
	check(UI.tracker_text(s,"me").is_empty(),"No tracker for a player who has not compared")
	s.tea_ceramics={"own_record":{"comparison_complete":true}}
	check(UI.tracker_text(s,"me")=="茶罐大單・空罐 0／6\n帶回收空罐到鶯歌交給陶師","Ready with a jar: tracker")
	var me:Dictionary=s.players.me
	check(UI.jar_reason(s,me,"tea_worn_jar").is_empty() and UI.jar_reason(s,me,"tea_returned_jar")==TR.NO_JAR%"回收陶罐","Jar reasons at the potter")
	check(UI.fill_reason(s,me,"light")==TR.NEED_JARS%[0,0],"Rules reason first")
	s.region_id="maokong"
	check(UI.jar_reason(s,me,"tea_worn_jar")==UI.AWAY_JAR%[20,20],"Where to go for jars from 貓空")
	s.region_id="home"
	check(UI.tracker_text(s,"me").is_empty(),"No tea tracker at home")
	s.region_id="yingge"
	me.inventory={}
	check(UI.tracker_text(s,"me").is_empty(),"Nothing doable: the tea notebook keeps the tracker")
	check(UI.journal_line(s)=="○ 茶罐大單：回收空罐 0／6・已裝 0／6（鶯歌交罐、貓空裝茶寄出）","Notebook line before the order")

func run()->void:
	create_timer(150.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 150 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("tea-revisit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"茶陶旅人",path)!=OK:check(false,"Host starts");finish();return
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
