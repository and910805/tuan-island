extends SceneTree
## Uses the normal interaction pages in a local game with the picnic and bond stage preset.
## UI contract: modal MiluRecipePages. Search view = MiluRecipeMap + MiluRecipeProgress
## + MiluRecipeClue_board/shop/table. Done view = MiluRecipeMend + MiluRecipeDish_hotpot/
## watermelon/chowder, MiluRecipeReplay (absent in reduced motion), MiluRecipeOpenTable (only in reach).
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const MendScene:=preload("res://scripts/milu_recipe_mend_scene.gd")
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const REACH:=3.2
var checks:=0
var failures:=0
var app
var world:World
var token:String
var person:Dictionary

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func capture(filename:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.24).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(filename))==OK,"Capture "+filename)

func node(name:String) -> Node:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func button(name:String) -> Button:
	return node(name) as Button

func press(name:String,message:String) -> bool:
	var target:=button(name)
	expect(target!=null and not target.disabled,message)
	if target==null or target.disabled:return false
	target.pressed.emit()
	return true

func place(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

## Wait until modal geometry has been unchanged for several frames and any mend animation is done.
func settle() -> void:
	var last:=Rect2()
	var still:=0
	var deadline:=Time.get_ticks_msec()+ceili(MendScene.END_TIME*1000.0)+2000
	while still<4 and Time.get_ticks_msec()<deadline:
		await process_frame
		var rect:=Rect2()
		if is_instance_valid(app.modal):rect=Rect2(app.modal.global_position,app.modal.size)
		var mend:=node("MiluRecipeMend")
		var running:bool=mend!=null and mend.has_method("is_finished") and not mend.is_finished()
		still=still+1 if rect==last and not running else 0
		last=rect
	expect(still>=4,"Modal layout and animation settle")

## At default fonts nothing may be clipped: modal inside the window, no scrolling, no wrapped label losing lines.
func expect_uncut(tag:String) -> void:
	var window:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	expect(is_instance_valid(app.modal) and window.encloses(Rect2(app.modal.global_position,app.modal.size)),tag+": modal fits the window")
	if not is_instance_valid(app.modal):return
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:
		var content:=scroll.get_child(0) as Control
		expect(content.get_combined_minimum_size().y<=scroll.size.y+1.0,tag+": body fits without scrolling (%s>%s)"%[content.get_combined_minimum_size().y,scroll.size.y])
		var view:=Rect2(scroll.global_position,scroll.size).grow(1.0)
		for child:Node in content.find_children("*","Control",true,false):
			var control:=child as Control
			if control.is_visible_in_tree() and control.size.x>0.0:
				expect(view.encloses(Rect2(control.global_position,control.size)),tag+": %s inside scroll area"%control.name)
	var area:=Rect2(app.modal.global_position,app.modal.size).grow(1.0)
	for child:Node in app.modal.find_children("*","Label",true,false):
		var text:=child as Label
		if text.is_visible_in_tree() and text.text!="":
			expect(text.get_visible_line_count()>=text.get_line_count(),tag+": label not truncated '%s'"%text.text.left(12))
			expect(area.encloses(Rect2(text.global_position,text.size)),tag+": label inside modal '%s'"%text.text.left(12))
	var back:=button("MiluRecipeBack")
	expect(back!=null and area.encloses(Rect2(back.global_position,back.size)),tag+": back button visible")
	for child:Node in app.modal.find_children("*","BaseButton",true,false):
		var control:=child as Control
		if control.is_visible_in_tree():expect(area.encloses(Rect2(control.global_position,control.size)),tag+": button %s inside modal"%control.name)

func open_via_journal() -> bool:
	app._close_modal()
	Tasks.journal(app)
	await process_frame
	var ok:=press("MiluRecipeBookmark","Journal lists the Milu recipe bookmark")
	await process_frame
	if ok:expect(app.modal.name=="MiluRecipePages","Bookmark opens MiluRecipePages")
	return ok

func progress_text() -> String:
	var progress:=node("MiluRecipeProgress") as Label
	return progress.text if progress!=null else ""

func expect_search_view(found:int,tag:String) -> void:
	expect(app.modal.name=="MiluRecipePages",tag+": modal name")
	expect(node("MiluRecipeMap")!=null,tag+": map")
	expect(progress_text()=="已找到 %d／3 片"%found,tag+": progress shows %d／3 (got '%s')"%[found,progress_text()])
	for site:String in ["board","shop","table"]:
		expect(node("MiluRecipeClue_"+site)!=null,tag+": clue "+site)
	for absent in ["MiluRecipeMend","MiluRecipeOpenTable","MiluRecipeReplay"]:
		expect(node(absent)==null,tag+": search view has no "+absent)

func expect_done_view(replay:bool,reach:bool,tag:String) -> void:
	expect(app.modal.name=="MiluRecipePages",tag+": modal name")
	expect(node("MiluRecipeMend")!=null,tag+": mend scene")
	for dish in ["hotpot","watermelon","chowder"]:
		expect(node("MiluRecipeDish_"+dish)!=null,tag+": dish "+dish)
	expect(node("MiluRecipeMap")==null and node("MiluRecipeProgress")==null,tag+": done view has no search widgets")
	expect((node("MiluRecipeReplay")!=null)==replay,tag+": replay presence is %s"%replay)
	expect((node("MiluRecipeOpenTable")!=null)==reach,tag+": open-table presence is %s"%reach)

func check_crowded_picnic() -> void:
	var crowded:=World.new()
	crowded.state.picnic=true
	crowded.state.community={"table":""}
	for i in World.COMMUNITY.CANDIDATES.size():
		var id:="spot-%d"%i
		crowded.add_player(id,"等候島民")
		var cell:Vector2i=World.COMMUNITY.CANDIDATES[i]
		crowded.state.players[id].x=cell.x+0.5
		crowded.state.players[id].y=cell.y+0.5
	expect(crowded.step(0.1,true,false) and World.milu_recipe_cell(crowded.state,"table")==World.COMMUNITY.NO_CELL,"The table waits until there is a free plaza location")
	crowded.active_tokens.erase("spot-0")
	expect(crowded.step(0.1,true,false),"The crowded plaza gets another placement attempt")
	var recovered:=World.milu_recipe_cell(crowded.state,"table")
	expect(recovered==World.COMMUNITY.CANDIDATES[0],"The table and the paper clue appear when a spot clears")
	crowded.active_tokens.erase("spot-1")
	expect(crowded.step(0.1,true,false) and World.milu_recipe_cell(crowded.state,"table")==recovered,"The table stays where it was placed")

func run() -> void:
	check_crowded_picnic()
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://milu-recipe-pages-%d.json"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var board:=World.milu_recipe_cell(world.state,"board")
	person.x=board.x+0.5
	person.y=board.y+0.5
	expect(not world.act(token,"too-early",Goals.RECIPE_PAGE_ACTION,board,"board").ok,"Paper requires stage two")
	person.bonds={"milu":{"points":6,"talk_day":-1,"gift_day":-1}}
	expect(not world.act(token,"wrong-cell",Goals.RECIPE_PAGE_ACTION,board,"shop").ok,"Forged landmark rejected")
	app.session._send_snapshot(1)
	Tasks.resident(app,"milu")
	await process_frame
	var book:=button("MiluRecipeBook")
	expect(book!=null,"Milu opens the search book")
	if book!=null:book.pressed.emit()
	await process_frame

	# Search view at 0/3 in both window sizes (default fonts, nothing cut off).
	for size:Vector2i in SIZES:
		root.size=size
		await process_frame
		await process_frame
		if not await open_via_journal():continue
		await settle()
		var tag:="search 0/3 %dx%d"%[size.x,size.y]
		expect_search_view(0,tag)
		expect_uncut(tag)
		await capture("01-plaza-clues-%dx%d.png"%[size.x,size.y])
	root.size=SIZES[0]
	await process_frame
	app._close_modal()

	# Real pickups in mixed order; progress is re-read through the journal route each time.
	var found:=0
	for site:String in ["shop","table","board"]:
		var cell:=World.milu_recipe_cell(world.state,site)
		place(cell)
		app._interact()
		await process_frame
		var marker:=button("MiluRecipePage")
		expect(marker!=null,"Ordinary interaction shows the paper at "+site)
		if marker!=null:marker.pressed.emit()
		await process_frame
		found+=1
		expect((int(app.session.snapshot.own_milu_recipe_pages)&int(Goals.RECIPE_PAGES[site].bit))!=0,"Collected "+site)
		expect(not world.act(token,"repeat-"+site,Goals.RECIPE_PAGE_ACTION,cell,site).ok,"Duplicate rejected at "+site)
		expect(not app.session.snapshot.players[app.session.own_id].has(Goals.RECIPE_PAGE_KEY),"Private progress stays out of public players")
		if found<3:
			if await open_via_journal():
				await settle()
				expect_search_view(found,"journal after "+site)
				expect(node("MiluRecipeMap").is_collected(site),"The new map marker is stamped for "+site)
				expect_uncut("search %d/3"%found)
				if found==1:await capture("03-one-paper-found.png")
		else:
			app._close_modal()
			app.session._send_snapshot(1)
			if await open_via_journal():
				await settle()
				expect_search_view(3,"journal after all pages")
				expect(((node("MiluRecipeNext") as Label).text).contains("米露"),"Three pages point back to Milu")
				expect_uncut("search 3/3")
		if is_instance_valid(app.modal):app._close_modal()

	# Hand the pages in through the normal bond event.
	var milu:Vector2i=World.bond_place(world.state,"milu")[1]
	place(milu)
	app._interact()
	await process_frame
	Tasks.bond_events(app,"milu",1)
	await process_frame
	Tasks.bond_goal(app,"milu",2)
	await process_frame
	var submit:=button("BondGoalDo")
	expect(submit!=null and not submit.disabled,"Complete through the event's normal submit button")
	if submit!=null:submit.pressed.emit()
	await process_frame
	expect(app.session.snapshot.resident_goals.milu["2"].state=="done","Milu accepts the three pages")

	# Done view next to the table: original table-side route, both sizes, animation settled before capture.
	var table:=World.milu_recipe_cell(world.state,"table")
	app._close_modal()
	for size:Vector2i in SIZES:
		root.size=size
		await process_frame
		await process_frame
		place(table)
		app._close_modal()
		app._interact()
		await process_frame
		book=button("MiluRecipeBook")
		expect(book!=null,"Completed guide can be read at the table (%dx%d)"%[size.x,size.y])
		if book!=null:book.pressed.emit()
		await process_frame
		await settle()
		var tag:="done %dx%d"%[size.x,size.y]
		expect_done_view(true,true,tag)
		var mend:=node("MiluRecipeMend") as MendScene
		expect(mend!=null and mend.is_finished(),tag+": mend animation finished before capture")
		expect_uncut(tag)
		await capture("02-table-guide-%dx%d.png"%[size.x,size.y])
		if size==SIZES[0] and mend!=null:
			var finishes:=[0]
			mend.animation_finished.connect(func():finishes[0]+=1)
			if press("MiluRecipeReplay",tag+": replay is actionable"):
				expect(not mend.is_finished(),tag+": replay starts the animation again")
				await capture("02-table-guide-replay-1024x640.png")
				await settle()
				expect(mend.is_finished() and finishes[0]==1,tag+": replay reaches the final pose once")
	root.size=SIZES[0]
	await process_frame

	# Journal route reaches the same done view; the bookmark is renamed once completed.
	app._close_modal()
	Tasks.journal(app)
	await process_frame
	var bookmark:=button("MiluRecipeBookmark")
	expect(bookmark!=null and bookmark.text=="米露的共餐桌手記","Completed bookmark title")
	if await open_via_journal():
		await settle()
		expect_done_view(true,true,"done via journal at table")
		# Back returns to the journal.
		if press("MiluRecipeBack","Back button on done view"):
			await process_frame
			expect(node("MiluRecipeBookmark")!=null,"Back returns to the journal")

	# Out of reach: the shortcut disappears but the page still reads.
	place(Vector2i(table.x+int(REACH)+6,table.y))
	if await open_via_journal():
		await settle()
		expect_done_view(true,false,"done away from table")
		expect_uncut("done away from table")

	# Reduced motion: no replay button, mend scene shows its end pose immediately.
	app.sound.reduced_motion=true
	place(table)
	if await open_via_journal():
		await process_frame
		expect_done_view(false,true,"done reduced motion")
		var mend:=node("MiluRecipeMend")
		expect(mend!=null and mend.is_finished(),"Reduced motion shows the finished pose at once")
		expect_uncut("done reduced motion")
	app.sound.reduced_motion=false

	# The genuine UI route opens the original table, not a copy.
	place(table)
	if await open_via_journal():
		await settle()
		if press("MiluRecipeOpenTable","Open-table button in reach"):
			await process_frame
			expect(is_instance_valid(app.modal) and app.modal.has_meta("community_body"),"Sharing controls opened")
			expect(app.modal.name!="MiluRecipePages","Original table replaced the guide")
			var serving:=button("DishMain_chowder")
			expect(serving!=null and serving.disabled,"Missing servings cannot be put on the table")
			person.inventory.corn_chowder=World.COMMUNITY.HOTPOT_PORTIONS
			app.session._send_snapshot(1)
			await process_frame
			if press("DishMain_chowder","Serve the four stocked chowders through the original table"):
				await process_frame
				expect(int(world.state.community.get("chowder",{}).get("portions",0))==4 and int(person.inventory.corn_chowder)==0,"Four bowls are served from the backpack")
				app.session.rates[1].clear()
				if press("DishMain_chowder","Claim one portion from the same table"):
					await process_frame
					expect(int(world.state.community.get("chowder",{}).get("portions",0))==3 and int(person.inventory.corn_chowder)==1,"The table gives exactly one portion")
					expect(button("DishMain_chowder").disabled,"Another portion cannot be claimed in the same round")
	var again:=World.milu_recipe_cell(world.state,"table")
	expect(again==table,"Table cell unchanged")
	expect(not world.act(token,"repeat-after-done",Goals.RECIPE_PAGE_ACTION,table,"table").ok,"Duplicate still rejected after completion")
	expect(not world.act(token,"forged-after-done",Goals.RECIPE_PAGE_ACTION,table,"board").ok,"Forged landmark still rejected after completion")

	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(int(loaded.state.players[token].get(Goals.RECIPE_PAGE_KEY,0))==Goals.RECIPE_PAGE_MASK,"Three pages survive reload")
	expect(Goals.done(loaded.state.players[token],"milu").has(2),"Handbook unlock survives reload")
	expect(not loaded.act(token,"repeat-reload",Goals.RECIPE_PAGE_ACTION,table,"table").ok,"Duplicate rejected after reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MILU_RECIPE_PAGE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
