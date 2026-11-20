extends SceneTree
## T066 N01-1 阿榆〈有點歪的第一塊板〉: the completed-story furniture page, end to end through the real UI.
## Native Windows graphical smoke test (screenshots are skipped when headless).
## Optional user arg: --capture-dir=DIR  (PNG evidence at 1024x640 and 1280x800).
##
## Contract assumed (see the final report for open questions):
##  * completed story page (Tasks.bond_goal(app,"aru",1)) has a Button "AruFirstFurnitureEntry"; no entry when open/locked;
##  * the entry opens a page with Buttons "AruFirstFurnitureBuild_bed|table|chair";
##  * each build button opens the existing BuildFolio selected on that original kind;
##  * wording is read from game data; no rule, cost or unlock changes.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Bond:=World.RESIDENT_BOND
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

const RESIDENT:="aru"
const STAGE:=1
const KIND:="keepsake_aru"
const ENTRY:="AruFirstFurnitureEntry"
const KINDS:=["bed","table","chair"]
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const FALLBACK_COST:={"bed":{"wood":15,"fiber":10},"table":{"wood":12},"chair":{"wood":6}}

var app
var world:World
var token:String
var person:Dictionary
var path:String
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func button(id:String) -> Button:
	return node(id) as Button

func settle() -> void:
	for i in 3:await process_frame

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:target.pressed.emit()
	await settle()

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func resize(size:Vector2i) -> void:
	root.size=size
	await settle()

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

func goal_done() -> bool:
	return Goals.done(person,RESIDENT).has(STAGE)

func branch_buttons() -> int:
	var count:=0
	for kind:String in KINDS:
		if button("AruFirstFurnitureBuild_"+kind)!=null:count+=1
	return count

func entry_present() -> bool:
	return button(ENTRY)!=null

## Nothing vertically clipped: no scroll bar, no truncated wrapped text, no squeezed buttons, everything inside the window.
func check_fit(tag:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+tag+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+tag+")")
	var scroll:=node("ModalScroll") as ScrollContainer
	if scroll!=null:
		expect(not scroll.get_h_scroll_bar().visible,"No sideways scrolling ("+tag+")")
		expect(not scroll.get_v_scroll_bar().visible,"No vertical clipping or scrolling ("+tag+")")
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(12)])
		expect(label.get_visible_line_count()>=label.get_line_count(),"Text is not truncated (%s): %s"%[tag,label.text.left(12)])
		expect(screen.encloses(label.get_global_rect()),"Text is on screen (%s): %s"%[tag,label.text.left(12)])
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if not target.is_visible_in_tree():continue
		expect(target.size.x+1.0>=target.get_combined_minimum_size().x and target.size.y+1.0>=target.get_combined_minimum_size().y,"Button is not squeezed (%s): %s"%[tag,str(target.name)])
		expect(screen.encloses(target.get_global_rect()),"Button is on screen (%s): %s"%[tag,str(target.name)])

func check_page(tag:String) -> void:
	expect(branch_buttons()==3,"The page offers exactly the three original build branches ("+tag+")")
	for kind:String in KINDS:
		var branch:=button("AruFirstFurnitureBuild_"+kind)
		expect(branch!=null and branch.is_visible_in_tree() and not branch.disabled,"Branch %s is an enabled button (%s)"%[kind,tag])
		if branch!=null:
			var box:=branch.get_global_rect()
			expect(box.size.x>=44.0 and box.size.y>=32.0,"Branch %s is a comfortable target (%s)"%[kind,tag])
			expect(not str(branch.text).strip_edges().is_empty(),"Branch %s is labelled (%s)"%[kind,tag])
		expect(World.BUILD.has(kind),"Original build type exists: "+kind)
	var names:=0
	var text:=visible_text(app.modal)+"\n".join(PackedStringArray(app.modal.find_children("AruFirstFurnitureBuild_*","Button",true,false).map(func(b):return (b as Button).text)))
	for kind:String in KINDS:
		if text.contains(str(World.BUILD[kind].name)):names+=1
	expect(names==3,"All three original furniture names are shown ("+tag+")")
	expect(text.contains(str(Goals.KEEPSAKES[KIND].name)) or text.contains(str(Goals.goal(RESIDENT,STAGE).title)),"The page ties back to the first board ("+tag+")")
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders ("+tag+")")
	expect(button("BondGoalDo")==null and button("BondGoalClaim")==null,"The page offers no payment or claim ("+tag+")")
	check_fit(tag)

func check_folio(kind:String,tag:String) -> void:
	expect(is_instance_valid(app.modal) and node("BuildFolio")!=null,"Branch %s opens the existing build folio (%s)"%[kind,tag])
	expect(branch_buttons()==0,"The page is replaced by the folio (%s %s)"%[kind,tag])
	var title:=node("BuildTitle") as Label
	expect(title!=null and title.is_visible_in_tree() and title.text.contains(str(World.BUILD[kind].name)),"Folio title is %s (%s)"%[kind,tag])
	var chosen:=0
	var wrong:=0
	for candidate:Node in app.modal.find_children("BuildSlot_*","Button",true,false):
		var slot:=candidate as Button
		if not slot.button_pressed or not slot.is_visible_in_tree():continue
		if str(slot.name).begins_with("BuildSlot_"+kind+"_"):chosen+=1
		else:wrong+=1
	expect(chosen==1 and wrong==0,"Only the %s slot is selected (%s)"%[kind,tag])
	expect(node("BuildPlace")!=null,"Folio keeps its place button (%s %s)"%[kind,tag])

func open_completed(tag:="") -> void:
	app._close_modal()
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(node("BondGoalDone")!=null and button("BondGoalDo")==null,"Story page is the completed one "+tag)

func snapshot_state() -> Dictionary:
	return {"inv":person.inventory.duplicate(true),"objects":world.state.objects.duplicate(true),"goals":person.get(Goals.RECORD_KEY,{}).duplicate(true),"coins":int(person.get("coins",0))}

func run() -> void:
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	path="user://aru-first-furniture-%d.json"%OS.get_process_id()
	if app.session.host(0,"小板島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.region=World.REGIONS.HOME
	var rules_before:={}
	for kind:String in KINDS:rules_before[kind]=World.BUILD[kind].duplicate(true)
	for kind:String in KINDS:
		var recipe:Dictionary=World.BUILD[kind]
		for item:String in FALLBACK_COST[kind]:expect(int(recipe.get(item,0))==int(FALLBACK_COST[kind][item]),"Recipe unchanged: %s %s"%[kind,item])
	var aru:Vector2i=World.bond_place(world.state,RESIDENT)[1]
	var spot:=Vector2i(38,34)
	var entry:Dictionary=Goals.goal(RESIDENT,STAGE)
	expect(str(entry.title)=="有點歪的第一塊板" and entry.get("needs",[])==["own_bed"] and entry.get("items",{})=={"wood":10},"Fixture knows the authored first event")
	var kit:=Goals.keepsake_item(KIND)

	# ---- Gating: locked (no friendship) and open (friendship, no bed) both hide the entry.
	person.bonds={}
	person.inventory.wood=25
	person.inventory.fiber=10
	person.inventory.erase(kit)
	stand(aru)
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(not entry_present() and branch_buttons()==0,"No entry while the event is locked")
	person.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[0]),"talk_day":-1,"gift_day":-1}}
	stand(aru)
	expect(Bond.stage(person,RESIDENT)==STAGE,"Fixture friendship reaches the first stage")
	app._close_modal()
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(node("BondGoalDone")==null and not entry_present() and branch_buttons()==0,"No entry while the event is open")
	var finish:=button("BondGoalDo")
	expect(finish!=null and finish.disabled,"Finish is closed without an own bed")
	await capture("01-open-no-entry.png")
	expect(not goal_done() and not Goals.keepsake_claimed(person,KIND),"Nothing is recorded before the report")

	# ---- Own bed built through the normal tool; the event is still open and still has no entry.
	stand(spot+Vector2i(0,1))
	app._close_modal()
	app._perform_build_action("build",spot,"bed")
	await settle()
	expect(str(world.state.objects.get(World.key(spot),{}).get("type",""))=="bed" and int(person.inventory.wood)==10 and int(person.inventory.fiber)==0,"A normal bed is built at the normal cost")
	stand(aru)
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(not entry_present() and node("BondGoalDone")==null,"The bed alone does not open the entry")
	finish=button("BondGoalDo")
	expect(finish!=null and not finish.disabled,"Finish opens once the own bed stands")
	await capture("02-open-ready.png")

	# ---- Live completion with the page still on screen: the entry appears either by repopulation or after a reopen.
	var before_complete:=snapshot_state()
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals[RESIDENT][str(STAGE)].state=="done" and goal_done(),"The report is confirmed by the server")
	expect(int(person.inventory.get("wood",0))==int(before_complete.inv.get("wood",0))-10 and int(person.inventory.get(kit,0))==1,"The report costs the 10 wood and hands over one kit")
	expect(Goals.done(person,RESIDENT).size()==1,"Only the first event is recorded")
	var repopulated:=entry_present()
	if not repopulated:
		await open_completed("after reopen")
	expect(entry_present(),"The entry shows after confirmation (%s)"%("live repopulation" if repopulated else "reopen"))
	print("ARU_FIRST_FURNITURE live_repopulation=%s"%str(repopulated))
	expect(not world.act(token,"repeat-aru-1",Goals.ACTION,aru,"%s:%d::"%[RESIDENT,STAGE]).ok and int(person.inventory.get(kit,0))==1,"The event cannot be paid or claimed twice")

	# ---- Page and every branch at both sizes.
	for size:Vector2i in SIZES:
		var tag:="%dx%d"%[size.x,size.y]
		await resize(size)
		await open_completed(tag)
		var opener:=button(ENTRY)
		expect(opener!=null and opener.is_visible_in_tree() and not opener.disabled,"Completed story shows an enabled entry ("+tag+")")
		if opener!=null:expect(opener.get_global_rect().size.x>1.0 and opener.get_global_rect().size.y>1.0,"Entry has a real box ("+tag+")")
		check_fit("completed "+tag)
		await capture("03-completed-entry-%s.png"%tag)
		await press(ENTRY)
		check_page(tag)
		var before_page:=snapshot_state()
		await capture("04-furniture-page-%s.png"%tag)
		expect(snapshot_state()==before_page,"Opening the page changes no items, objects or progress ("+tag+")")
		await press("AruFirstFurnitureStory")
		var story:=node("AruFirstBoardScene")
		expect(story!=null and story.is_playing(),"The board story plays when opened ("+tag+")")
		check_fit("board story "+tag)
		await capture("04-board-story-%s.png"%tag)
		if story!=null:
			story.advance(3.0)
			expect(story.is_finished(),"The board comes to rest on the workbench ("+tag+")")
			await press("AruFirstBoardReplay")
			expect(story.is_playing(),"Replay starts the table animation again ("+tag+")")
		await press("AruFirstBoardBack")
		expect(branch_buttons()==3,"The story returns to the three patterns ("+tag+")")
		for kind:String in KINDS:
			await open_completed(tag+" "+kind)
			await press(ENTRY)
			await press("AruFirstFurnitureBuild_"+kind)
			await settle()
			check_folio(kind,tag)
			expect(snapshot_state()==before_page,"Folio %s places and spends nothing (%s)"%[kind,tag])
			await capture("05-folio-%s-%s.png"%[kind,tag])

	# ---- Rules are unchanged.
	for kind:String in KINDS:expect(World.BUILD[kind]==rules_before[kind],"Recipe untouched: "+kind)
	expect(Goals.done(person,RESIDENT).size()==1 and int(person.inventory.get(kit,0))==1,"Browsing the branches never changes the event or the kit")

	# ---- Late/saved player: close, reopen the island, completed story still offers the entry and every branch.
	app._close_modal()
	expect(app.session.shutdown(),"Save and close the island")
	app.sound.close()
	app.queue_free()
	await settle()
	await resize(SIZES[0])
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	expect(app.session.host(0,"小板島民",path)==OK,"Reopen the saved island")
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	expect(world.state.players.has(token),"The saved player is found after reopening")
	person=world.state.players.get(token,{})
	if person.is_empty():
		quit(1)
		return
	person.region=World.REGIONS.HOME
	stand(aru)
	expect(goal_done(),"The completed event survives the reload")
	for size:Vector2i in SIZES:
		var tag:="reloaded %dx%d"%[size.x,size.y]
		await resize(size)
		await open_completed(tag)
		expect(entry_present(),"Late player sees the entry without redoing the event ("+tag+")")
		await capture("06-reloaded-completed-%dx%d.png"%[size.x,size.y])
		await press(ENTRY)
		check_page(tag)
		await press("AruFirstFurnitureBuild_bed")
		await settle()
		check_folio("bed",tag)
	# Also from the resident menu route a player would really take.
	app._close_modal()
	app._resident_menu(RESIDENT)
	await settle()
	expect(is_instance_valid(app.modal),"The resident menu opens for a returning player")
	app._close_modal()
	Tasks.journal(app)
	await settle()
	await press("AruFirstFurnitureBookmark")
	expect(branch_buttons()==3,"The patterns can be opened from the island journal after reloading")
	app.sound.reduced_motion=true
	await press("AruFirstFurnitureStory")
	var still:=node("AruFirstBoardScene")
	expect(still!=null and still.is_finished() and not still.is_playing(),"Reduced motion shows the completed board immediately")
	expect(button("AruFirstBoardReplay")!=null and not button("AruFirstBoardReplay").visible,"Reduced motion suppresses the replay control")
	for kind:String in KINDS:expect(World.BUILD[kind]==rules_before[kind],"Recipe untouched after reload: "+kind)

	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ARU_FIRST_FURNITURE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
