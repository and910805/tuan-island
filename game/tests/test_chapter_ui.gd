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
	expect(world.act("picnic-neighbor","share-wood","donate",Vector2i(40,29)).ok,"Neighbor donates wood")
	app.session._send_snapshot(1)
	var tree_meter:=app.modal.find_child("BridgeWood",true,false).find_child("ProgressMeter",true,false) as ProgressBar
	expect(tree_meter.value==30 and donate.disabled,"Open board shows the neighbor's wood")
	neighbor.inventory.stone=10
	expect(world.act("picnic-neighbor","share-stone","donate",Vector2i(40,29)).ok,"Neighbor opens the bridge")
	app.session._send_snapshot(1)
	await process_frame
	await process_frame
	var serve:=app.modal.find_child("BoardServePicnic",true,false) as Button
	expect(serve!=null and serve.disabled and serve.text=="先到小石灶準備料理","Empty bag points to the stove")
	person.inventory.soup=1
	app.session._send_snapshot(1)
	expect(serve!=null and not serve.disabled,"A partial donation is available")
	neighbor.inventory.soup=2
	expect(world.act("picnic-neighbor","share-soup","picnic",Vector2i(40,29)).ok,"Neighbor contributes soup through World")
	app.session._send_snapshot(1)
	var soup_row:Node=app.modal.find_child("PicnicSoup",true,false)
	expect(soup_row.find_child("ProgressCaption",true,false).text.ends_with("2 / 2") and soup_row.find_child("ProgressMeter",true,false).value==2,
		"Open board updates both the soup count and meter")
	expect(serve!=null and serve.disabled,"Extra soup is not useful when only bread is missing")
	person.inventory.bread=1
	app.session._send_snapshot(1)
	expect(serve!=null and not serve.disabled,"Bread enables the final contribution")
	neighbor.inventory.bread=1
	expect(world.act("picnic-neighbor","share-bread","picnic",Vector2i(40,29)).ok,"Neighbor completes the picnic through World")
	app.session._send_snapshot(1)
	var bread_row:Node=app.modal.find_child("PicnicBread",true,false)
	expect(bread_row.find_child("ProgressCaption",true,false).text.ends_with("1 / 1") and bread_row.find_child("ProgressMeter",true,false).value==1,
		"Open board fills the bread count and meter on completion")
	expect(serve!=null and serve.disabled and serve.text=="野餐料理已上桌","Remote completion disables the old button")
	for entry in ["SouvenirEntry","FishingMeetEntry","ShowcaseEntry"]:
		expect(not app.modal.find_child(entry,true,false).text.contains("野餐後開放"),"Remote completion updates "+entry)
	await capture(app,"picnic-live")
	await verify_board_scales(app,world)
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

