extends SceneTree
## N02-4 米露共餐桌小宴: the optional NPC invite on the picnic table, through the real UI. Native Windows render suite
## (screenshots skipped when headless). Optional user arg: --capture-dir=DIR (1024x640 and 1280x800).
##
## Contract assumed (names may need local adjusting; the game has no supper code yet):
##  * app._community_menu table has DishMain_chowder (serves 4 corn_chowder once) and a button MiluSupperPlanEntry;
##  * modal MiluSupperPlan: toggle buttons MiluSupperInvite_aru / _xiaoli / _lingpopo, and MiluSupperPlanBack;
##  * server action MILU_ACTION at the table cell toggles one invitee by id;
##    snapshot.own_milu_supper = {dish:"corn_chowder", guests:Array}; invalid / far / unknown strings are refused;
##  * BondGoalDo at stage 4 beside Milu opens modal MiluSupperBook (MiluSupperScene, MiluSupperReplay, MiluSupperBack);
##    the done page has MiluSupperMemory, the journal MiluSupperBookmark. Reduced motion: no replay.
## Fixture writes (disclosed): picnic flag, raw community {table} with no meals, friendship for rank 4, stages 1-3 recorded
## done, and 4 corn_chowder put straight into the bag (not cooked). Nothing else is written; serving/inviting/finishing
## go through the real UI and world actions.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Bond:=World.RESIDENT_BOND
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const R:="milu"
const DISH:="corn_chowder"
const MILU_ACTION:=World.MILU_SUPPER.ACTION
const GUESTS:=["aru","xiaoli","lingpopo"]
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const TABLE:=Vector2i(39,30)

var app
var world:World
var token:String
var person:Dictionary
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func rates_clear() -> void:app.session.rates[1].clear()

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	rates_clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	if not is_instance_valid(app.modal):return null
	return app.modal if str(app.modal.name)==id else app.modal.find_child(id,true,false)

func button(id:String) -> Button:return node(id) as Button

func settle() -> void:
	for i in 3:await process_frame

func wait_for(id:String,frames:=90) -> Node:
	for i in frames:
		if node(id)!=null:break
		await process_frame
	await settle()
	return node(id)

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:
		rates_clear()
		target.pressed.emit()
	await settle()

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for kind in ["Label","Button"]:
		for candidate:Node in root_node.find_children("*",kind,true,false):
			if candidate.is_visible_in_tree() and not str(candidate.text).strip_edges().is_empty():lines.append(str(candidate.text))
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

func check_fit(tag:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+tag+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+tag+")")
	var scroll:=node("ModalScroll") as ScrollContainer
	if scroll!=null:expect(not scroll.get_h_scroll_bar().visible and not scroll.get_v_scroll_bar().visible,"No scrolling or clipping ("+tag+")")
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if not target.is_visible_in_tree():continue
		expect(target.size.x+1.0>=target.get_combined_minimum_size().x and screen.encloses(target.get_global_rect()),"Button fits on screen ("+tag+"): "+str(target.name))
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():expect(label.get_visible_line_count()>=label.get_line_count() and screen.encloses(label.get_global_rect()),"Text not truncated ("+tag+"): "+label.text.left(12))

func count(item:String) -> int:return int(person.inventory.get(item,0))
func own() -> Dictionary:
	var row:Variant=app.session.snapshot.get("own_milu_supper",{})
	return row if row is Dictionary else {}
func guests() -> Array:return own().get("guests",[]) as Array
func meal() -> Dictionary:return world.state.community.get("chowder",{})
func act(extra:String) -> Dictionary:
	serial+=1
	rates_clear()
	return world.act(token,"supper-%d"%serial,MILU_ACTION,TABLE,extra)
func milu_cell() -> Vector2i:return World.bond_place(world.state,R)[1]
func world_state() -> Dictionary:
	return {"inv":person.inventory.duplicate(true),"community":world.state.community.duplicate(true),"coins":int(person.get("coins",0)),"goals":person.get(Goals.RECORD_KEY,{}).duplicate(true),"apron":person.get(Goals.APRON_KEY,false),"supper":World.MILU_SUPPER.view(person)}

func fresh_files() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func boot(size:Vector2i,fresh:bool) -> bool:
	root.size=size
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if app.session.host(0,"小宴島民",path)!=OK:return false
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players.get(token,{})
	if person.is_empty():return false
	person.region=World.REGIONS.HOME
	if fresh:
		world.state.picnic=true
		world.state.community={"table":World.COMMUNITY.cell_key(TABLE)}
		person.bonds={R:{"points":int(Bond.THRESHOLDS[3]),"talk_day":-1,"gift_day":-1}}
		person[Goals.RECORD_KEY]={R:{"1":"","2":"","3":"soup"}}
		person.erase(Goals.APRON_KEY)
		person.inventory[DISH]=4
	await settle()
	return true

func shutdown_app() -> void:
	app._close_modal()
	expect(app.session.shutdown(),"Save and close the island")
	app.sound.close()
	app.queue_free()
	await settle()

func finish_run() -> void:
	if is_instance_valid(app):
		app.sound.close()
		app.queue_free()
	await settle()
	fresh_files()

func check_book(tag:String,reduced:bool) -> void:
	expect(node("MiluSupperBook")!=null and node("MiluSupperBook").is_visible_in_tree(),"Supper book is open ("+tag+")")
	var art:=node("MiluSupperScene") as Control
	expect(art!=null and art.is_visible_in_tree() and art.get_global_rect().size.x>=300.0,"Supper scene is readable ("+tag+")")
	if art!=null:
		expect(art.get("guests")==guests() and str(art.get("dish"))==str(own().get("dish","")),"The scene uses the saved seats and meal ("+tag+")")
	var back:=button("MiluSupperBack")
	expect(back!=null and not back.disabled and back.get_global_rect().size.y>=32.0,"Comfortable back ("+tag+")")
	if reduced:
		expect(button("MiluSupperReplay")==null and art!=null and art.is_finished() and not art.is_processing(),"Reduced motion shows the settled art without replay ("+tag+")")
	var text:=visible_text(app.modal)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains(DISH),"No raw placeholders or ids ("+tag+")")
	check_fit(tag)

func run_live(size:Vector2i) -> void:
	var tag:="%dx%d"%[size.x,size.y]
	path="user://milu-supper-%d-%d.json"%[OS.get_process_id(),size.x]
	fresh_files()
	if not await boot(size,true):
		expect(false,"Isolated island starts ("+tag+")")
		return
	var milu:=milu_cell()
	expect(Bond.stage(person,R)>=4 and world.state.community.size()==1,"Fixture: rank four, raw community without dishes ("+tag+")")

	# ---- Serve four through the original table menu.
	stand(TABLE+Vector2i(0,1))
	var coins:=int(person.get("coins",0))
	app._close_modal()
	app._community_menu()
	await settle()
	expect(node("CommunityServings")!=null and button("MiluSupperPlanEntry")!=null,"The table menu offers the optional plan ("+tag+")")
	expect(not Goals.done(person,R).has(4) and not bool(person.get("resident_participation",{}).get("shared_meal",false)),"Nothing is shared before serving ("+tag+")")
	expect(not bool(act("aru").ok),"Invitations require personally serving a batch ("+tag+")")
	await press("DishMain_chowder")
	expect(count(DISH)==0 and int(meal().get("portions",0))==4 and meal().get("claimed",{}).is_empty(),"Four bowls handed to the table once ("+tag+")")
	expect(int(app.session.snapshot.community.chowder.portions)==4 and int(person.coins)==coins,"Public portions are 4 and no coin moves ("+tag+")")
	expect(person.get("resident_participation",{}).get("shared_meal",false)==true and not Goals.done(person,R).has(4),"Serving counts as shared, stage 4 stays optional ("+tag+")")
	var served:=world_state()
	rates_clear()
	expect(not world.act(token,"supper-again","serve_chowder",TABLE,"").ok and world_state()==served,"A second serve is refused and costs nothing ("+tag+")")
	expect(own().get("guests",[]).is_empty(),"No guests before any choice ("+tag+")")

	# ---- Plan modal: select, take out, capacity.
	await press("MiluSupperPlanEntry")
	expect(node("MiluSupperPlan")!=null,"The plan modal opens ("+tag+")")
	for id:String in GUESTS:expect(button("MiluSupperInvite_"+id)!=null,"Invitation button: "+id)
	check_fit("plan "+tag)
	await capture("01-plan-%s.png"%tag)
	await press("MiluSupperInvite_aru")
	await press("MiluSupperInvite_xiaoli")
	expect(guests()==["aru","xiaoli"] and str(own().get("dish",""))==DISH,"Snapshot shows dish and two guests ("+tag+")")
	expect(button("MiluSupperInvite_lingpopo").disabled and not bool(act("lingpopo").ok),"Both player and server enforce the two guest capacity ("+tag+")")
	await press("MiluSupperInvite_xiaoli")
	expect(guests()==["aru"],"Taking a guest out keeps the rest ("+tag+")")
	await press("MiluSupperInvite_xiaoli")
	await capture("02-plan-chosen-%s.png"%tag)
	await press("MiluSupperPlanBack")
	expect(node("MiluSupperPlan")==null and node("CommunityServings")!=null,"Back returns to the table ("+tag+")")
	expect(int(meal().portions)==4 and count(DISH)==0 and int(person.coins)==coins,"Planning costs nothing ("+tag+")")

	# ---- Server rejections leave everything as it was.
	var chosen:=world_state()
	var before:=guests().duplicate()
	for bad:String in ["ghost","aru,aru","aru,xiaoli,lingpopo,milu","milu","ARU"," aru","aru;xiaoli","corn_chowder","aru,"]:
		expect(not bool(act(bad).ok) and guests()==before and world_state()==chosen,"Rejected invitation string: '%s' (%s)"%[bad,tag])
	stand(milu+Vector2i(8,8))
	expect(not bool(act("aru").ok) and guests()==before,"Far from the table is refused ("+tag+")")
	stand(TABLE+Vector2i(0,1))
	person.region="jiaoxi"
	expect(not bool(act("aru").ok) and guests()==before,"Another region is refused ("+tag+")")
	person.region=World.REGIONS.HOME
	app.session._send_snapshot(1)

	# ---- Finish stage 4 beside Milu; the book opens after the confirmed result.
	stand(milu)
	app._close_modal()
	Tasks.bond_goal(app,R,4)
	await settle()
	if button("BondGoalConfirm")!=null:await press("BondGoalConfirm")
	var before_done:=world_state()
	await press("BondGoalDo")
	if button("BondGoalConfirm")!=null:await press("BondGoalConfirm")
	var book:Node=await wait_for("MiluSupperBook")
	expect(book!=null and Goals.done(person,R).has(4),"Confirmed completion opens the book ("+tag+")")
	expect(world_state().inv==before_done.inv and int(person.coins)==int(before_done.coins),"No item or coin is paid for the supper ("+tag+")")
	expect(guests()==["aru","xiaoli"],"Chosen guests are kept after completion ("+tag+")")
	check_book("success "+tag,false)
	await create_timer(2.65).timeout
	await capture("03-book-%s.png"%tag)
	if button("MiluSupperReplay")!=null:await press("MiluSupperReplay")
	await press("MiluSupperBack")
	expect(node("MiluSupperBook")==null,"Back leaves the book ("+tag+")")

	# ---- Memory and bookmark revisit the done page, changing nothing.
	var done_state:=world_state()
	app._close_modal()
	Tasks.bond_goal(app,R,4)
	await settle()
	expect(node("BondGoalDone")!=null and button("BondGoalDo")==null and node("MiluSupperBook")==null,"Done page shows no automatic book ("+tag+")")
	await press("MiluSupperMemory")
	check_book("memory "+tag,false)
	await press("MiluSupperBack")
	app._close_modal()
	Tasks.journal(app)
	await settle()
	await press("MiluSupperBookmark")
	check_book("journal "+tag,false)
	await press("MiluSupperBack")
	expect(world_state()==done_state,"Revisiting changes nothing ("+tag+")")

	# ---- Reduced motion.
	app._close_modal()
	app.sound.reduced_motion=true
	Tasks.journal(app)
	await settle()
	await press("MiluSupperBookmark")
	check_book("reduced "+tag,true)
	await capture("04-reduced-%s.png"%tag)
	await press("MiluSupperBack")
	app._close_modal()
	app.sound.reduced_motion=false

	# ---- Apron through the original resident page.
	app._resident_menu(R)
	await settle()
	await press("MiluApron")
	expect(person.get(Goals.APRON_KEY,false)==true,"The apron goes on ("+tag+")")

	# ---- Reload keeps invites and apron.
	await shutdown_app()
	if not await boot(size,false):
		expect(false,"Reopen the saved island ("+tag+")")
		return
	stand(milu)
	expect(guests()==["aru","xiaoli"] and str(own().get("dish",""))==DISH and person.get(Goals.APRON_KEY,false)==true,"Invites and apron survive the reload ("+tag+")")
	expect(int(meal().get("portions",-1))==4 and count(DISH)==0,"Public portions survive too ("+tag+")")
	Tasks.bond_goal(app,R,4)
	await settle()
	await press("MiluSupperMemory")
	check_book("reloaded "+tag,false)
	await finish_run()

func run_standalone(size:Vector2i,legacy:bool) -> void:
	var tag:="%dx%d"%[size.x,size.y]
	path="user://milu-supper-solo-%d-%d.json"%[OS.get_process_id(),size.x]
	fresh_files()
	if not await boot(size,true):
		expect(false,"Isolated island starts ("+tag+")")
		return
	if legacy:
		person[Goals.RECORD_KEY][R]["4"]=""
		person.erase(World.MILU_SUPPER.KEY)
		person.inventory.erase(DISH)
		stand(milu_cell())
		expect(Goals.done(person,R).has(4) and guests().is_empty(),"Old record has no guests ("+tag+")")
		Tasks.bond_goal(app,R,4)
		await settle()
		await press("MiluSupperMemory")
	else:
		stand(TABLE+Vector2i.DOWN)
		app._community_menu()
		await settle()
		await press("DishMain_chowder")
		stand(milu_cell())
		Tasks.bond_goal(app,R,4)
		await settle()
		await press("BondGoalDo")
		expect(await wait_for("MiluSupperBook")!=null and Goals.done(person,R).has(4),"A solo player finishes with no invitations")
		expect(count(DISH)==0 and int(meal().portions)==4,"The solo story uses the same four shared servings")
	check_book("standalone memory "+tag,false)
	expect(visible_text(app.modal).strip_edges()!="" and guests().is_empty(),"The book reads without guests ("+tag+")")
	await create_timer(2.65).timeout
	await capture("05-%s-%s.png"%["legacy" if legacy else "solo",tag])
	await press("MiluSupperBack")
	app._close_modal()
	app._resident_menu(R)
	await settle()
	await press("MiluApron")
	expect(person.get(Goals.APRON_KEY,false)==true,"Apron works on an old save ("+tag+")")
	await finish_run()

func run() -> void:
	var native:=DisplayServer.get_name()!="headless"
	for size:Vector2i in SIZES:
		await run_live(size)
		await run_standalone(size,false)
		await run_standalone(size,true)
	await create_timer(0.15).timeout
	print("MILU_SUPPER_UI_TESTS checks=%d failures=%d render=%s"%[checks,failures,"native" if native else "headless"])
	if failures==0:print("MILU_SUPPER_UI_PASS")
	quit(int(failures>0))
