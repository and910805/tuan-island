extends SceneTree
## 第 40 章金瓜石初訪歷史時間軸 (real main.tscn + real HistoryUI modal). Runs in a native 1024x640
## window or --headless. Pass -- --capture-dir=<absolute path> for a native screenshot.
##
## FIXTURE (written directly into the isolated host save in %TEMP%, deleted at the end):
##  * the player is teleported to region "jinguashi" (first visit, no travel_book needed);
##  * state.gold_panning / state.ore_route get a one-pan / one-delivery record
##    ({"stage":0,"day":1,"count":1,"total":1}); session._send_snapshot then derives
##    history_memory.mine_fieldwork {panned, delivered} exactly as in play.
## EXERCISED: HistoryUI.open(app,"jinguashi"), HistoryUI.refresh, the journal button
##  JinguashiHistoryJournal, JinguashiHistoryBack (direct return callable and journal re-open).
## NOT DONE: the LinkButton is never pressed (no external browser); only its uri is checked.
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/history_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Gold=preload("res://scripts/gold_panning.gd")
const Route=preload("res://scripts/ore_route.gd")
const PANNED_DATES:=["1890","1894"]
const DELIVERED_DATES:=["1897","1904","1933"]
const SOURCE_PREFIX:="https://www.gep.ntpc.gov.tw/"
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false
var returned:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("JINGUASHI_TIMELINE checks=%d failures=%d display=%s"%[checks,failures,DisplayServer.get_name()])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

## Visible in the tree and (like test_history_ui) not scrolled out of an enclosing ScrollContainer.
func on_page(c:Control)->bool:
	if c==null or not c.is_visible_in_tree():return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().grow(1.0).encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

## Every Label / Button / LinkButton text of the open modal (hidden ones included when all=true).
func texts(all:=false)->PackedStringArray:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return out
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not (c is Label or c is BaseButton):continue
		if not all and not c.is_visible_in_tree():continue
		out.append(c.text)
	return out

func all_text()->String:
	return "\n".join(texts())

func has_date(text:String,dates:Array)->bool:
	for d:String in dates:
		if text.contains(d):return true
	return false

func person()->Dictionary:
	return w.state.players[id]

func set_flags(panned:bool,delivered:bool)->void:
	w.state.erase(Gold.STATE_KEY)  # FIXTURE
	w.state.erase(Route.STATE_KEY)  # FIXTURE
	if panned:w.state[Gold.STATE_KEY]={"players":{id:{"stage":0,"day":1,"count":1,"total":1}}}
	if delivered:w.state[Route.STATE_KEY]={"players":{id:{"stage":0,"day":1,"count":1,"total":1}}}
	app.session._send_snapshot(1)
	var fw:Dictionary=app.session.snapshot.get("history_memory",{}).get("mine_fieldwork",{})
	check(bool(fw.get("panned",false))==panned and bool(fw.get("delivered",false))==delivered,
		"Snapshot mine_fieldwork mirrors panned=%s delivered=%s: %s"%[panned,delivered,str(fw)])
	if is_instance_valid(app.modal):UI.refresh(app)

func open_page(back:Callable=Callable(),from_journal:=false)->void:
	if is_instance_valid(app.modal):app._close_modal()
	UI.open(app,"jinguashi",Vector2i(-1,-1),back,from_journal)
	await settle()
	check(is_instance_valid(app.modal) and app.modal.get_meta("history_mode","")=="jinguashi","Jinguashi history page open")

func fits(label:String)->void:
	if not is_instance_valid(app.modal):return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Modal fits the %s viewport (%s)"%[str(root.size),label])
	check(on_page(control("JinguashiHistoryBack")),"Return button is on the visible page (%s)"%label)

## The two entries as seen right now. Locked dates must not be anywhere on the visible page.
func expect_state(panned:bool,delivered:bool,label:String)->void:
	var p:=label_text("MineHistoryPanning")
	var h:=label_text("MineHistoryHauling")
	check(control("MineHistoryPanning") is Label and control("MineHistoryHauling") is Label,"Stable named labels exist (%s)"%label)
	var page:=all_text()
	for d:String in PANNED_DATES:
		check(on_page(control("MineHistoryPanningDate"+d))==panned,"Panning timeline date %s matches progress (%s)"%[d,label])
		check(page.contains(d)==panned,"Page-wide %s %s (%s)"%[d,"visible" if panned else "absent",label])
	for d:String in DELIVERED_DATES:
		check(on_page(control("MineHistoryHaulingDate"+d))==delivered,"Hauling timeline date %s matches progress (%s)"%[d,label])
		check(page.contains(d)==delivered,"Page-wide %s %s (%s)"%[d,"visible" if delivered else "absent",label])
	check(not p.is_empty() and not h.is_empty(),"Both entries carry text, locked ones a fieldwork clue (%s)"%label)
	check(on_page(control("MineHistoryPanning"))==not panned,"Only the locked panning entry shows the clue (%s)"%label)
	check(on_page(control("MineHistoryHauling"))==not delivered,"Only the locked hauling entry shows the clue (%s)"%label)
	if not panned:check(p.contains("淘"),"Locked panning entry hints at panning (%s): %s"%[label,p])
	if not delivered:check(h.contains("礦"),"Locked hauling entry hints at hauling (%s): %s"%[label,h])
	fits(label)

## Authored fiction is flagged, and the page never says gold was first found in Jinguashi.
func claims_and_credits(label:String)->void:
	var note:=""
	for t in texts():
		if t.begins_with("遊戲改編"):note=t
	check(not note.is_empty(),"Authored-fiction note 「遊戲改編」 visible (%s)"%label)
	check(note.contains("淘砂處") and note.contains("設計"),"Fiction note names the invented site and says it is designed (%s): %s"%[label,note])
	for t in texts():
		for sentence in t.split("。"):
			var gold_found:bool=sentence.contains("發現砂金") or sentence.contains("發現黃金")
			if gold_found:check(not sentence.contains("金瓜石") or sentence.contains("基隆河"),
				"No claim that gold was first found in Jinguashi (%s): %s"%[label,sentence])
			check(not (sentence.contains("金瓜石") and (sentence.contains("最早") or sentence.contains("首度") or sentence.contains("首次")) and sentence.contains("金")),
				"No 'first in Jinguashi' wording (%s): %s"%[label,sentence])
	var links:=(app.modal as Node).find_children("*","LinkButton",true,false)
	var museum:LinkButton=null
	for l in links:
		if (l as LinkButton).uri.begins_with(SOURCE_PREFIX):museum=l
	check(museum!=null,"Official Gold Museum source link exists (%s)"%label)
	if museum!=null:
		check(museum.uri.begins_with("https://") and museum.is_visible_in_tree() and museum.text.contains("黃金博物館"),"Museum link is visible https with its name (%s): %s"%[label,museum.uri])
		check(on_page(museum),"Museum link sits inside the visible page (%s)"%label)
	for l in links:check((l as LinkButton).uri.begins_with("https://"),"Every source URI is https (%s): %s"%[label,(l as LinkButton).uri])

func came_back()->void:returned+=1

func capture() -> void:
	if DisplayServer.get_name()=="headless":return
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		var dir:=arg.trim_prefix("--capture-dir=")
		DirAccess.make_dir_recursive_absolute(dir)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(dir.path_join("1024x640-history-timeline.png"))==OK,
			"Capture the unlocked timeline")

func run()->void:
	create_timer(100.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 100 s")
		finish())
	path=OS.get_environment("TEMP").path_join("jinguashi-timeline-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	root.size=Vector2i(1024,640)
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"金瓜石旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	app.view.set_process(false)
	w.state.time=30.0  # FIXTURE (day 1)
	var p:=person()
	p.region="jinguashi";p.x=12.5;p.y=20.5  # FIXTURE: first visit, at the shuttle stop
	app.session._send_snapshot(1)
	app._refresh_hud()
	await settle()
	check(str(app.session.snapshot.get("region_id",""))=="jinguashi","Player is in Jinguashi (real snapshot)")
	check(root.size==Vector2i(1024,640),"Window is 1024x640: %s"%str(root.size))

	# 1) First visit: neither flag.
	set_flags(false,false)
	await open_page()
	expect_state(false,false,"neither")
	claims_and_credits("neither")
	# 2) One flag each way; the other's dates stay locked.
	set_flags(true,false)
	await settle()
	expect_state(true,false,"panned only")
	set_flags(false,true)
	await settle()
	expect_state(false,true,"delivered only")
	# 3) Both flags (live refresh of the open page).
	set_flags(true,true)
	await settle()
	expect_state(true,true,"both")
	claims_and_credits("both")
	await capture()
	# Locked text must not leak into the open page again after state is cleared.
	set_flags(false,false)
	await settle()
	expect_state(false,false,"neither again")

	# 4) Direct return: the 回到現場 callable runs and the page is the one the caller supplied.
	set_flags(true,true)
	await open_page(came_back)
	expect_state(true,true,"direct return page")
	var back:=control("JinguashiHistoryBack") as Button
	check(back!=null and back.text=="回到現場","Direct entry offers 回到現場: %s"%(back.text if back!=null else "none"))
	if back!=null:back.pressed.emit()
	await settle()
	check(returned==1,"Back runs the supplied return callable once (%d)"%returned)

	# 5) Journal re-opening: journal -> Jinguashi entry -> back lands on the journal; state persists.
	if is_instance_valid(app.modal):app._close_modal()
	UI.open(app)
	await settle()
	var entry:=control("JinguashiHistoryJournal") as Button
	check(entry!=null and on_page(entry),"Journal lists the Jinguashi entry after a visit")
	if entry!=null:
		entry.pressed.emit()
		await settle()
		check(app.modal.get_meta("history_mode","")=="jinguashi","Journal button opens the Jinguashi page")
		expect_state(true,true,"journal")
		var home:=control("JinguashiHistoryBack") as Button
		check(home!=null and home.text=="回到地方記憶","Journal entry offers 回到地方記憶: %s"%(home.text if home!=null else "none"))
		if home!=null:
			home.pressed.emit()
			await settle()
			check(is_instance_valid(app.modal) and app.modal.get_meta("history_mode","")=="journal","Back returns to the journal")
			check(control("JinguashiHistoryJournal")!=null,"Journal still lists the entry after returning")
		# Re-open from the journal again, with progress reset: dates lock again (private, per player).
		var again:=control("JinguashiHistoryJournal") as Button
		set_flags(false,false)
		if again!=null:
			again.pressed.emit()
			await settle()
			expect_state(false,false,"journal reopened, no flags")
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

	w.state.erase(Gold.STATE_KEY)  # FIXTURE cleanup before the final save
	w.state.erase(Route.STATE_KEY)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
