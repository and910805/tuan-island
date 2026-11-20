extends SceneTree

const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_ui.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func button_at(node:Node,title:String)->Button:
	if node is Button and node.text.begins_with(title):return node
	for child in node.get_children():
		var result:=button_at(child,title)
		if result!=null:return result
	return null

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide()
	app.hud.show()
	var world:=World.new()
	world.add_player("tester","島民")
	var person:Dictionary=world.state.players.tester
	person.x=38.5
	person.y=30.5
	app.session.snapshot=world.state
	app.view.update_snapshot(world.state,"tester")
	app.session.own_id="tester"
	app.session.world=world
	app.session.peers[1]="tester"
	app.session.sequences[1]=0
	app.session.rates[1]=[]
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		await process_frame
		Chapter.open(app)
		app._layout_preview()
		await process_frame
		await process_frame
		expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(app.modal.get_global_rect()),"Chapter fits "+str(size))
		expect(button_at(app.modal,"查看小島地圖").is_visible_in_tree(),"Map route visible")
		expect(app.modal.get_meta("chapter_step").id=="grow","Fresh world starts at grow")
	var first:Control=app.modal.get_meta("chapter_content").get_child(0)
	Chapter.refresh(app)
	expect(app.modal.get_meta("chapter_content").get_child(0)==first,"Unchanged refresh keeps controls")
	world.state.chapter_one.shipped=true
	world.state.board=true
	Chapter.refresh(app)
	expect(app.modal.get_meta("chapter_step").id=="water","Updated snapshot changes chapter")
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		app._layout_preview()
		await process_frame
		await process_frame
		var scroll:ScrollContainer=app.modal.get_meta("chapter_content").get_parent()
		for name in ["ChapterWaterFlow","ChapterDetails"]:
			var element:Control=app.modal.find_child(name,true,false)
			expect(element!=null and scroll.get_global_rect().encloses(element.get_global_rect()),"Water section fully visible at "+str(size)+": "+name)
	await capture(app,"chapter-water")
	world.state.chapter_one.watered=true
	Chapter.refresh(app)
	var recipes:Control=app.modal.find_child("ChapterPicnicRecipes",true,false)
	expect(recipes!=null,"Picnic letter shows the actual soup and bread recipes")
	if recipes!=null:
		expect(recipes.find_children("*","Label",true,false).any(func(note):return note.text.contains("蘿蔔 0／2")),
			"Recipe quantities use the current inventory")
		person.inventory.radish=2
		Chapter.refresh(app)
		recipes=app.modal.find_child("ChapterPicnicRecipes",true,false)
		expect(recipes.find_children("*","Label",true,false).any(func(note):return note.text.contains("蘿蔔 2／2")),
			"Inventory changes refresh the displayed recipe")
	await capture(app,"chapter-picnic")
	var stove_link:=app.modal.find_child("ChapterBuildStove",true,false) as Button
	expect(stove_link!=null and not stove_link.disabled,"Picnic letter offers the stove recipe")
	if stove_link!=null:stove_link.pressed.emit()
	await process_frame
	await process_frame
	var stove_title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(stove_title!=null and stove_title.text.contains(World.BUILD.stove.name),
		"The shortcut opens the stove's actual build recipe")
	await capture(app,"chapter-stove")
	world.state.chapter_one.watered=false
	Tasks.resident(app,"aru")
	expect(button_at(app.modal,"交付這段委託")!=null,"Original resident quest remains")
	var letter:=button_at(app.modal,"看渡口來信")
	expect(letter!=null,"Current resident offers chapter letter")
	var claim:=button_at(app.modal,"交材料換入門設備")
	expect(claim!=null and claim.is_visible_in_tree(),"Nearby resident opens with the equipment trade visible")
	if letter!=null and claim!=null:
		letter.pressed.emit()
		expect(not claim.is_visible_in_tree(),"Player can collapse the letter")
		letter.pressed.emit()
	await capture(app,"resident-water")
	person.inventory.wood=0
	var before:Dictionary=person.inventory.duplicate(true)
	if claim!=null:claim.pressed.emit()
	expect(app.session.sequences[1]>0 and app.toast.text.contains("需要木材 12"),"Claim reaches Session and reports insufficient materials")
	expect(person.inventory==before and world.state.chapter_one.starter_claims.is_empty(),"Missing materials change neither inventory nor claim")
	Tasks.resident(app,"milu")
	expect(button_at(app.modal,"看渡口來信")==null,"Unrelated resident has no chapter prompt")
	world.state.board=false
	world.add_player("picnic-neighbor","鄰居")
	var neighbor:Dictionary=world.state.players["picnic-neighbor"]
	neighbor.x=40.5
	neighbor.y=30.5
	neighbor.inventory.wood=30
	person.inventory.stone=0
	app.session._send_snapshot(1)
	Tasks.board(app)
	var donate:=app.modal.find_child("BoardDonateBridge",true,false) as Button
	expect(donate!=null and donate.disabled,"Bridge donation requires useful materials")
	var bridge_hint:=app.modal.find_child("BridgeDonationHint",true,false) as Label
	var wood_hint:="%s 砍樹"%app.binding_label("axe")
	var stone_hint:="%s 敲岩石"%app.binding_label("pick")
	expect(bridge_hint.text.contains(wood_hint) and bridge_hint.text.contains(stone_hint),"Unfinished materials have gathering directions")
	expect(world.act("picnic-neighbor","share-wood","donate",Vector2i(40,29)).ok,"Neighbor donates wood")
	app.session._send_snapshot(1)
	var tree_meter:=app.modal.find_child("BridgeWood",true,false).find_child("ProgressMeter",true,false) as ProgressBar
	expect(tree_meter.value==30 and donate.disabled,"Open board shows the neighbor's wood")
	expect(not bridge_hint.text.contains(wood_hint) and bridge_hint.text.contains(stone_hint),"Remote contribution removes the completed material from the gathering hint")
	neighbor.inventory.stone=10
	expect(world.act("picnic-neighbor","share-stone","donate",Vector2i(40,29)).ok,"Neighbor opens the bridge")
	app.session._send_snapshot(1)
	await process_frame
	await process_frame
	var serve:=app.modal.find_child("BoardServePicnic",true,false) as Button
	var picnic_hint:=app.modal.find_child("PicnicContributionHint",true,false) as Label
	expect(serve!=null and serve.disabled and serve.text=="先到小石灶準備料理","Empty bag points to the stove")
	person.inventory.soup=1
	app.session._send_snapshot(1)
	expect(serve!=null and not serve.disabled,"A partial donation is available")
	expect(picnic_hint.text.contains("%s ×1"%World.NAMES.soup) and picnic_hint.text.contains(World.NAMES.bread),
		"Partial contribution previews one soup and names the remaining dishes")
	var current_board:Control=app.modal
	app.session.rates[1].clear()
	serve.pressed.emit()
	expect(app.modal==current_board and world.state.picnic_materials.soup==1 and not world.state.picnic,
		"Donating one soup leaves the same board open and the project incomplete")
	person.inventory.soup=1
	neighbor.inventory.soup=1
	expect(world.act("picnic-neighbor","share-soup","picnic",Vector2i(40,29)).ok,"Neighbor contributes soup through World")
	app.session._send_snapshot(1)
	var soup_row:Node=app.modal.find_child("PicnicSoup",true,false)
	expect(soup_row.find_child("ProgressCaption",true,false).text.ends_with("2 / 2") and soup_row.find_child("ProgressMeter",true,false).value==2,
		"Open board updates both the soup count and meter")
	expect(serve!=null and serve.disabled,"Extra soup is not useful when only bread is missing")
	expect(picnic_hint.text=="桌上還缺 %s ×1"%World.NAMES.bread,"Remote soup completion leaves only the bread hint")
	person.inventory.bread=1
	app.session._send_snapshot(1)
	expect(serve!=null and not serve.disabled,"Bread enables the final contribution")
	neighbor.inventory.bread=3
	var seeds_before:=int(neighbor.inventory.radish_seed)
	expect(world.act("picnic-neighbor","share-bread","picnic",Vector2i(40,29)).ok,"Neighbor completes the picnic through World")
	expect(neighbor.inventory.bread==2 and neighbor.inventory.radish_seed==seeds_before+3,
		"Only the missing bread is consumed and the completion reward is granted once")
	expect(not world.act("picnic-neighbor","extra-bread","picnic",Vector2i(40,29)).ok
		and neighbor.inventory.bread==2 and neighbor.inventory.radish_seed==seeds_before+3,
		"A second delivery cannot consume leftovers or repeat the completion reward")
	app.session._send_snapshot(1)
	var bread_row:Node=app.modal.find_child("PicnicBread",true,false)
	expect(bread_row.find_child("ProgressCaption",true,false).text.ends_with("1 / 1") and bread_row.find_child("ProgressMeter",true,false).value==1,
		"Open board fills the bread count and meter on completion")
	expect(serve!=null and serve.disabled and serve.text=="野餐料理已上桌","Remote completion disables the old button")
	for entry in ["SouvenirEntry","FishingMeetEntry","ShowcaseEntry"]:
		expect(not app.modal.find_child(entry,true,false).text.contains("野餐後開放"),"Remote completion updates "+entry)
	await capture(app,"picnic-live")
	await verify_board_scales(app,world)
	await verify_story_route(app,world)
	await verify_mill_site(app,world)
	app.queue_free()
	await process_frame
	print("CHAPTER_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_board_scales(app,world:World)->void:
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		for scale_id in range(4):
			app.sound.preferred_text_scale=scale_id
			for open_picnic in [false,true]:
				world.state.picnic=open_picnic
				app.session._send_snapshot(1)
				Tasks.board(app)
				app._apply_font_scale_tree()
				await process_frame
				await process_frame
				await process_frame
				var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
				var content:=scroll.get_node("ModalContent") as VBoxContainer
				var tag:="size=%s scale=%d picnic=%s"%[extent,scale_id,open_picnic]
				expect(Rect2(Vector2.ZERO,Vector2(extent)).encloses(app.modal.get_global_rect()),"Board inside viewport "+tag)
				if scale_id>1:
					expect(app.modal.size.x<=800.0,"Activity rows do not force a wider board "+tag)
				expect(content.size.x<=scroll.size.x,"No hidden horizontal overflow "+tag)
				var project_heading:Label
				for candidate:Label in content.find_children("*","Label",true,false):
					if candidate.text=="渡口修繕":project_heading=candidate
				expect(project_heading!=null and project_heading.get_theme_font_size("font_size")==app.scaled_font_size(22),"Project heading uses selected font size "+tag)
				var activity:=button_at(content,"群島的來信") if open_picnic else content.find_child("ShowcaseEntry",true,false) as Button
				expect(activity!=null,"Final action exists "+tag)
				if activity==null:continue
				activity.grab_focus()
				scroll.ensure_control_visible(activity)
				await process_frame
				await process_frame
				expect(scroll.get_global_rect().encloses(activity.get_global_rect()),"Scroll reaches full activity button "+tag)
				if extent==Vector2i(1024,640) and scale_id==3 and open_picnic:
					await create_timer(0.3).timeout
					await capture(app,"board-xl")

func verify_story_route(app,world:World)->void:
	world.state[World.STONE_WORKSHOP.PROJECT_KEY]=World.STONE_WORKSHOP.fresh_project()
	world.state.public_kitchen=World.PUBLIC_KITCHEN.fresh()
	world.state.chapter_one.watered=true
	world.state.picnic=true
	app.session._send_snapshot(1)
	app._journal()
	var bookmark:=app.modal.find_child("StoryRouteBookmark",true,false) as Button
	expect(bookmark!=null,"The island journal links to the story route")
	if bookmark==null:return
	bookmark.pressed.emit()
	var route:Control=app.modal
	var opening:=route.find_child("StoryRouteStatus0",true,false) as Label
	var second:=route.find_child("StoryRouteStatus1",true,false) as Label
	var third:=route.find_child("StoryRouteStatus2",true,false) as Label
	var fourth:=route.find_child("StoryRouteStatus3",true,false) as Label
	var fifth:=route.find_child("StoryRouteStatus4",true,false) as Label
	expect(opening.text.contains("已完成") and not second.text.contains("已完成"),"The opening picnic completes only the first chapter")
	world.state.public_kitchen.opened=true
	app.session._send_snapshot(1)
	expect(app.modal==route and second.text.contains("接著到公告板修河灣橋"),"The same open page updates when the kitchen opens")
	world.state[World.STONE_WORKSHOP.PROJECT_KEY].done=true
	world.state.mine_depths.hoist=true
	world.state.mine_depths.unlocked=World.MINES.HOIST_DEPTH
	world.state.dock_stage=1
	app.session._send_snapshot(1)
	expect(second.text.contains("已完成"),"The second chapter requires the bridge and kitchen")
	expect(third.text.contains("升降台已修好") and third.text.contains("待修舊磨坊"),"The hoist is tracked separately from mill restoration")
	expect(fourth.text.contains("接著準備小船") and not fifth.text.contains("已完成"),"The pier, boat, and festival are distinct milestones")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		app._layout_preview()
		await process_frame
		await process_frame
		var scroll:=route.find_child("ModalScroll",true,false) as ScrollContainer
		var content:=scroll.get_node("ModalContent") as VBoxContainer
		expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(route.get_global_rect()) and content.size.x<=scroll.size.x,"The route fits the viewport at "+str(size))
		var back_button:=route.find_child("StoryRouteBack",true,false) as Button
		expect(back_button!=null and scroll.get_global_rect().encloses(back_button.get_global_rect()),"All five chapters and their links fit without scrolling at "+str(size))
	await capture(app,"story-route")
	var mill:=button_at(route,"磨坊")
	expect(mill!=null,"Chapter three links to the public mill")
	if mill==null:return
	mill.pressed.emit()
	var mill_page:Control=app.modal
	var repair:=button_at(mill_page,"交材料修磨坊")
	expect(repair!=null and mill_page.get_meta("mill_project").repair.visible,"The restoration shows shared material progress")
	var actor:Dictionary=world.state.players.tester
	actor.x=40.5
	actor.y=30.5
	for item:String in World.MILL_RESTORATION.COST:
		actor.inventory[item]=World.MILL_RESTORATION.COST[item]
	app.session._send_snapshot(1)
	if not app.arg_value("qa-capture","").is_empty():await create_timer(0.3).timeout
	await capture(app,"mill-restoration")
	if repair!=null:repair.pressed.emit()
	expect(app.modal==mill_page and mill_page.get_meta("mill_project").service.visible,"Repair switches the same page to working milling")
	actor.inventory["wheat"]=2
	app.session._send_snapshot(1)
	var flour:=mill_page.find_child("PublicMill_flour",true,false) as Button
	expect(flour!=null and not flour.disabled,"A player can send wheat to the restored mill")
	if flour!=null:flour.pressed.emit()
	var collect:=mill_page.find_child("PublicMillClaim",true,false) as Button
	expect(collect!=null and collect.disabled and actor.get(World.MILL_RESTORATION.JOB,{}).get("kind")=="flour","The flour control starts the proper recipe and waits")
	app.session.peers[2]="picnic-neighbor"
	var guest_view:Dictionary=app.session._snapshot_data(2,app.session._view_plan(2))
	app.session.peers.erase(2)
	var actor_id:="tester".sha256_text().left(16)
	expect(guest_view.players.has(actor_id) and not guest_view.players.get(actor_id,{}).has(World.MILL_RESTORATION.JOB),"A nearby islander receives the shared repair but not the other player's milling job")
	expect(World.MILL_RESTORATION.repaired(guest_view),"The same repaired project is visible to the other islander")
	await capture(app,"mill-working")
	expect(world.step(float(World.INDUSTRY.PROCESS.flour.time),true),"Advance the milling clock")
	app.session._send_snapshot(1)
	expect(collect!=null and not collect.disabled,"After the timer the owner can collect")
	if collect!=null:collect.pressed.emit()
	expect(int(actor.inventory.get("flour",0))==1,"Collecting from the UI gives the normal flour yield")
	var close_mill:=button_at(mill_page,"返回")
	if close_mill!=null:close_mill.pressed.emit()
	route=app.modal
	third=route.find_child("StoryRouteStatus2",true,false)
	fourth=route.find_child("StoryRouteStatus3",true,false)
	fifth=route.find_child("StoryRouteStatus4",true,false)
	expect(third.text.contains("已完成"),"Repair and hoist together complete chapter three")
	world.state.dock_stage=2
	world.state.festival_story_open=true
	app.session._send_snapshot(1)
	expect(fourth.text.contains("已完成") and fifth.text.contains("可以重看"),"The boat and festival reflect the shared saved milestones")
	var replay:=button_at(route,"重看風鈴節")
	expect(replay!=null and not replay.disabled,"The completed story links to the real replay")
	if replay==null:return
	replay.pressed.emit()
	var back:=button_at(app.modal,"返回五章故事")
	expect(back!=null and app.modal.find_child("FestivalScenePage",true,false)!=null,"The replay returns to the story route")
	if back!=null:back.pressed.emit()

func verify_mill_site(app,world:World)->void:
	const Mill=World.MILL_RESTORATION
	var actor:Dictionary=world.state.players.tester
	expect(Mill.site_clear(world.state) and world.blocked(Mill.SITE.position),"The empty village parcel contains a solid mill")
	expect(world.protected(Mill.SITE.position) and world.protected(Mill.APPROACH),"Builds cannot cover the mill or its approach")
	expect(not world.blocked(Mill.DOOR) and not world.blocked(Mill.APPROACH),"The door and its approach remain walkable")
	app._close_modal()
	actor.x=Mill.APPROACH.x+0.5
	actor.y=Mill.APPROACH.y+0.5
	world.move_player("tester",Vector2.UP,0.2)
	expect(actor.y<float(Mill.APPROACH.y),"A player can walk through the door from its approach")
	world.move_player("tester",Vector2.UP,0.45)
	expect(actor.y>float(Mill.DOOR.y),"The next tile is solid and stops the player")
	app.session._send_snapshot(1)
	expect(app.session.snapshot.get(Mill.SITE_VISIBLE,false),"The server publishes the physical site")
	expect(app.view.interaction_focus()==Mill.POINT,"The doorway is the player's interaction target")
	if not app.arg_value("qa-capture","").is_empty():await create_timer(0.4).timeout
	await capture(app,"mill-doorway")
	app._interact()
	expect(is_instance_valid(app.modal) and app.modal.get_meta("mill_project",{}).get("target")==Mill.DOOR,"The normal E interaction opens the physical mill")
	var feed:=app.modal.find_child("PublicMill_feed",true,false) as Button
	var results:Array[Dictionary]=[]
	var listener:=func(_sequence:int,action:String,result:Dictionary):
		if action==Mill.SERVICE:results.append(result)
	app.session.action_completed.connect(listener)
	actor.inventory["sweet_corn"]=1
	actor.inventory["fiber"]=2
	app.session._send_snapshot(1)
	expect(feed!=null and not feed.disabled,"The player can send feed ingredients in from the doorway")
	if feed!=null:feed.pressed.emit()
	expect(actor.get(Mill.JOB,{}).get("kind")=="feed","The host accepts the recipe at the actual doorway")
	expect(results.size()==1 and results[0].ok and not results[0].get("mill_claimed",false),"The host notifies the client that milling started")
	expect(app.session.snapshot.get(Mill.BUSY,false),"The active batch marks the mill working in the world")
	app.session.peers[2]="picnic-neighbor"
	var neighbor_view:Dictionary=app.session._snapshot_data(2,app.session._view_plan(2))
	app.session.peers.erase(2)
	var actor_id:="tester".sha256_text().left(16)
	expect(neighbor_view.get(Mill.BUSY,false) and not neighbor_view.players.get(actor_id,{}).has(Mill.JOB),"Other islanders see motion without receiving the owner's job data")
	app._close_modal()
	if not app.arg_value("qa-capture","").is_empty():await create_timer(0.35).timeout
	await capture(app,"mill-running")
	expect(world.step(float(World.INDUSTRY.PROCESS.feed.time),true),"World time completes the owner's queued batch")
	app.session._send_snapshot(1)
	expect(not app.session.snapshot.get(Mill.BUSY,false) and actor.has(Mill.JOB),"The wheel stops when the batch is ready and its output remains private")
	await capture(app,"mill-ready")
	var legacy_cell:=World.key(Mill.SITE.position)
	world.state.objects[legacy_cell]={"type":"chest","owner":"tester","items":{}}
	app.session._send_snapshot(1)
	expect(not app.session.snapshot.get(Mill.SITE_VISIBLE,true) and world.state.objects.has(legacy_cell),"A legacy building keeps its lot and suppresses the public facade")
	expect(not world.act("tester","mill-legacy-door",Mill.SERVICE,Mill.DOOR,"claim").ok,"A blocked legacy door does not become a hidden interaction")
	actor.x=40.5
	actor.y=30.5
	app.session.perform(Mill.SERVICE,Mill.BOARD,"claim")
	expect(results.size()==2 and results[1].ok and results[1].get("mill_claimed",false),"The board claims the same job and the host signals the pickup sound")
	app.session.action_completed.disconnect(listener)
	app.session._send_snapshot(1)
	app._map_menu()
	var route_button:=app.modal.find_child("MillWalkRoute",true,false) as Button
	expect(route_button!=null,"The local map offers a walking route to the mill")
	if route_button!=null:route_button.pressed.emit()
	var status:=app.modal.find_child("HomeWalkRouteStatus",true,false) as Label
	expect(status!=null and status.text.contains("公告板・磨坊代辦"),"The legacy route leads to the board")
	world.state.objects.erase(legacy_cell)
	app.session._send_snapshot(1)
	var cells:Array=app.map_view.home_route_cells
	expect(not cells.is_empty() and cells.back()==Mill.APPROACH,"The live map updates the route to the walkable mill approach")

func capture(app,name:String)->void:
	var target:String=app.arg_value("qa-capture","")
	if target.is_empty():return
	var size:String=app.arg_value("qa-size","1024x640")
	var extent:=size.split("x")
	root.size=Vector2i(int(extent[0]),int(extent[1]))
	app._layout_preview()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(target.path_join(name+"-"+size+".png"))==OK,"Saved rendered fixture")
