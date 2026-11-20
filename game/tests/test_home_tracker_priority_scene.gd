extends SceneTree
## 第 40 章：家園追蹤卡的優先順序（分流閘提示、地方記憶展提示 vs 茶陶合作手帳）。
## Native render test at 1024×640 and 1280×800; screenshots go to outputs/家園追蹤優先預覽.
## Harness follows test_memory_exhibit_ui.gd (real Session host, real snapshot round trips,
## the full main._refresh_hud path — no extra LifeShell.refresh_hud call).
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / picnic / chapter_one.shipped+watered, festival_story_open, state.time=30;
##  * unlock fixture + completed 蘭陽回訪 written directly exactly as test_memory_exhibit_ui
##    (earned path: test_lanyang_revisit_journey / test_memory_exhibit_journey);
##  * the tea record is erased at the start of each resolution; the player is teleported;
##  * one diversion_gate_kit written into the bag to clear the 分流閘 hint;
##  * state.festival.active written for the 風鈴接力 priority check; region written to lanyang.
## REALLY EXERCISED: tea_intro and exhibit_view go through Session.perform -> World -> snapshot;
## the tracker button is pressed (signal) and the page it opens is checked.
## NOT COVERED: gamepad; the non-preview layout; 豐收接力／釣魚會／布置題 rounds on top of the hint
## (they write after this block and are covered by their own suites).
const World=preload("res://scripts/world.gd")
const Tea=World.TEA_CERAMICS
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const UI=preload("res://scripts/memory_exhibit_ui.gd")
const RevisitUI=preload("res://scripts/lanyang_revisit_ui.gd")
const STAND:=Vector2i(39,26)
const NEAR:=Vector2(39.5,27.5)
const AWAY:=Vector2(36.5,33.5)
const HINT_HEADING:="渡口的新鮮事  ▾"
const TEA_HEADING:="茶陶合作手帳  ▾"
var app
var w
var id:String=""
var path:String=""
var output:String=""
var checks:=0
var failures:=0
var shots:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func note(message:String)->void:
	print("NOTE HOME_TRACKER_PRIORITY "+message)

func finish()->void:
	if finished:return
	finished=true
	print("HOME_TRACKER_PRIORITY_TESTS checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

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

func k(c:Vector2i)->String:
	return World.key(c)

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

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func heading()->Button:
	return app.hud.find_child("TrackerHeading",true,false) as Button

func next_button()->Button:
	return app.hud.find_child("TrackerNext",true,false) as Button

func text()->String:
	return str(app.objective.text)

func flat()->String:
	return "%s | %s | %s"%[heading().text,text().replace("\n"," / "),next_button().text]

func shot(tag:String,step:String)->void:
	app.toast.hide()
	var arrival:=app.hud.get_node_or_null("TravelArrival") as Control
	if arrival:arrival.hide()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"screenshot saved %s_%s"%[tag,step])
	shots+=1

## The tracker card stays inside the viewport, the text inside the card, nothing cut.
func card_ok(label:String,hint:=false)->void:
	var card:Rect2=app.preview_tracker.get_global_rect()
	check(root.get_visible_rect().encloses(card),"Tracker card inside the viewport (%s) %s"%[label,str(card)])
	check(card.encloses(app.objective.get_global_rect()),"Tracker text inside the card (%s) %s in %s"%[label,str(app.objective.get_global_rect()),str(card)])
	var l:Label=app.objective
	check(l.get_visible_line_count()>=l.get_line_count(),"Tracker text shows every line (%s)"%label)
	if hint:check(l.get_line_count()==text().split("\n").size(),"Hint lines are not re-wrapped (%s): %d lines for 「%s」"%[label,l.get_line_count(),text().replace("\n"," / ")])
	for b:Button in [heading(),next_button()]:
		check(card.grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"%s caption whole inside the card (%s)"%[b.name,label])

func write_unlock()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}  # PRESET

func base()->void:
	await close_page()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	# PRESET: the 島民第一課 is finished (a fresh Wangan landing starts it and it would own the card).
	person().erase(World.CHAPTER_ONE.PERSONAL_START)
	w.state.festival_story_open=true  # PRESET
	w.state.festival.active=false  # PRESET
	w.state.time=30.0  # PRESET
	w.state.tea_ceramics.players.erase(id)  # PRESET: tea record back to FRESH
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	(person().inventory as Dictionary).erase("diversion_gate_kit")  # PRESET
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects.erase(k(cell))
	write_unlock()
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET
	await stand(AWAY)

func flow(tag:String)->void:
	await base()
	check((snap().get(Exhibit.STATE_KEY,{}) as Dictionary).get("on_display",[])==["lanyang"],"分水木牌 on display (%s)"%tag)
	check(RevisitUI.home_hint(snap(),app.session.own_id)==RevisitUI.HOME_HINT and UI.tracker_text(snap())==UI.TRACKER%1,"Both chapter-40 hints are pending (%s)"%tag)
	# 1. Tea step at home (介紹信) keeps the card even with both hints pending.
	check(app._tea_guidance_active() and app._home_memory_hint().is_empty(),"Tea step at the 渡口 outranks the hints (%s)"%tag)
	check(heading().text==TEA_HEADING and text().contains("介紹信"),"Card shows the 介紹信 step (%s): %s"%[tag,flat()])
	card_ok("tea at home "+tag)
	await shot(tag,"01_tea_step_at_home")
	next_button().pressed.emit()
	await settle()
	check(is_instance_valid(app.modal) and str(app.modal.get_meta("tea_site",""))=="home","Button still opens 小栗's tea order (%s)"%tag)
	await close_page()
	# 2. Accept the letter for real: next tea step is in 鶯歌 -> the 分流閘 hint shows.
	await stand(Vector2(Tea.RECEIVER.x+0.5,Tea.RECEIVER.y+1.5))
	app.session.rates[1].clear()
	app.session.perform("tea_intro",Tea.RECEIVER)
	await refresh()
	check(bool(snap().tea_ceramics.own_record.intro),"tea_intro accepted through the session (%s)"%tag)
	await stand(AWAY)
	var tea_step:Dictionary=app.TeaGuidance.next_step(snap(),app.session.own_id)
	check(str(tea_step.region)!="home","Next tea step is away from home (%s): %s"%[tag,str(tea_step.get("title",""))])
	check(str(app._home_memory_hint().get("kind",""))=="gate","Hint kind is the 分流閘 (%s)"%tag)
	check(heading().text==HINT_HEADING and text()==RevisitUI.HOME_HINT and next_button().text=="茶陶手帳下一步  →","Card shows the 分流閘 hint after the full refresh (%s): %s"%[tag,flat()])
	card_ok("gate hint "+tag,true)
	await shot(tag,"02_gate_hint")
	next_button().pressed.emit()
	await settle()
	check(is_instance_valid(app.modal) and app.modal.has_meta("travel_body"),"Gate-hint button leads to the tea step's travel page (%s)"%tag)
	await close_page()
	# 3. Holding a gate kit clears that hint -> the unread exhibit shows.
	person().inventory["diversion_gate_kit"]=1  # PRESET
	await refresh()
	check(str(app._home_memory_hint().get("kind",""))=="exhibit","Hint kind is the exhibit (%s)"%tag)
	check(heading().text==HINT_HEADING and text()==UI.TRACKER%1 and next_button().text=="打開地方記憶展  →","Card shows the unread exhibit after the full refresh (%s): %s"%[tag,flat()])
	card_ok("exhibit hint "+tag,true)
	await shot(tag,"03_exhibit_hint")
	next_button().pressed.emit()
	await settle()
	check(UI.is_open(app),"Exhibit-hint button opens the 地方記憶展 page (%s)"%tag)
	await shot(tag,"04_exhibit_page_from_tracker")
	await close_page()
	# 4. 風鈴接力 running keeps its own card.
	w.state.festival.active=true  # PRESET
	await refresh()
	check(app._home_memory_hint().is_empty() and text().contains("風鈴接力") and heading().text.begins_with("風鈴接力  ") and next_button().text=="查看風鈴接力  →","風鈴接力 outranks the hints (%s): %s"%[tag,flat()])
	w.state.festival.active=false  # PRESET
	await refresh()
	check(text()==UI.TRACKER%1,"Exhibit hint returns after the relay (%s)"%tag)
	# 5. Away from home the hint never shows.
	await stand(Vector2(33.5,27.5),"lanyang")
	check(app._home_memory_hint().is_empty() and not text().contains("地方記憶展") and heading().text!=HINT_HEADING,"No home hint in 蘭陽 (%s): %s"%[tag,flat()])
	# 6. View the exhibit for real -> the card goes back to the tea guidance.
	await stand(NEAR)
	check(text()==UI.TRACKER%1,"Hint still shown beside the stand before viewing (%s)"%tag)
	app.session.rates[1].clear()
	app.session.perform(Exhibit.VIEW_ACTION,STAND,Exhibit.extra_for("lanyang"))
	await refresh()
	var record:Variant=person().get(Exhibit.RECORD_KEY)
	check(record is Dictionary and (record as Dictionary).get("seen",[])==["lanyang"],"exhibit_view recorded through the session (%s): %s"%[tag,str(record)])
	await stand(AWAY)
	check(app._home_memory_hint().is_empty(),"No hint left once seen (%s)"%tag)
	check(heading().text==TEA_HEADING and text().contains("陶師") and next_button().text=="查看轉乘  →","Card returns to the tea guidance (%s): %s"%[tag,flat()])
	card_ok("tea after hints "+tag)
	await shot(tag,"05_back_to_tea")
	note("%s final card: %s"%[tag,flat()])

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/家園追蹤優先預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("home-tracker-priority-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"追蹤卡旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		await flow("%dx%d"%[size.x,size.y])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
