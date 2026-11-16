extends SceneTree
## Native renderer + actual local Session kitchen actions on a labelled seeded fixture.
## Animation clock is sampled explicitly; this is not a human playthrough or video.
const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
const Art=preload("res://scripts/community_art.gd")
const Feedback=preload("res://scripts/community_feedback.gd")
const HOST:="scene-host"
const GUEST:="scene-guest"
const STOVE:=Vector2i(38,33)
const SEATS:=[Vector2i(37,34),Vector2i(39,34)]
class TableCanvas extends Node2D:
	var kitchen:Dictionary={}
	var cue:Dictionary={}
	var elapsed:=0.0
	var reduced:=false
	var portions:=0
	var fruit:=0
	func _draw()->void:Art.draw_table(self,Vector2(64,72),elapsed,reduced,kitchen,cue,portions,fruit)
var checks:=0
var failures:=0
var app
var world
var output:=""
var table:TableCanvas
var viewport:SubViewport
func _initialize()->void:call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle(frames:=5)->void:
	for i in frames:await process_frame
func art_frame(cue:Dictionary,t:float,reduced:bool)->Image:
	table.cue=cue;table.elapsed=t;table.reduced=reduced;table.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func attach(token:String)->void:
	app.session.profile={"token":token}
	app.session.world=world
	app.session._attach_registered(1,token)
	app.session.set_physics_process(false)
	app.set_process(false)
	app.view.set_process(false)
	app._refresh_hud()
	await settle()
func capture(name:String,t:float,reduced:=false)->void:
	app.view.elapsed=t
	app.view.reduced_motion=reduced
	app.view._process(0.0)
	await settle(2)
	await RenderingServer.frame_post_draw
	if not output.is_empty():
		var path:=output.path_join(name+".png")
		var pic:=root.get_texture().get_image()
		expect(pic!=null and pic.save_png(path)==OK,"native frame saved: "+name)
		print("COMMUNITY_SCENE_SHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Native renderer required");quit(1);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1280,800)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.title="糰糰島｜共餐場景動畫檢查"
	world=World.new();world.save_path="user://community-scene.json"
	for token in [HOST,GUEST]:
		world.add_player(token,"小禾" if token==HOST else "米香")
		world.state.players[token].x=38.5;world.state.players[token].y=32.5
	world.state.picnic=true;world.state.board=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	world.state.players[HOST].stories.aru=2
	world.state.players[HOST].inventory={"wood":100,"stone":100,"fiber":100,"soup":2,"bread":1}
	world.state.players[GUEST].inventory={"soup":2,"bread":1,"salad":2}
	for piece in [[STOVE,"stove"],[SEATS[0],"long_bench"],[SEATS[1],"long_bench"]]:
		expect(world.act(HOST,"scene-build-"+World.key(piece[0]),"build",piece[0],piece[1]).ok,"fixture furniture built by World.act")
	expect(world.act(HOST,"scene-register","kitchen_register",STOVE,World.PUBLIC_KITCHEN.seat_extra(SEATS[0],SEATS[1])).ok,"fixture site registered by World.act")
	await attach(HOST)
	app.view.elapsed=10.0
	expect(app.view.community_feedback.sample(10.0,false).is_empty(),"initial registration snapshot is not an animation event")
	await capture("community-before",10.0)
	app.session.perform("kitchen_contribute",STOVE,"")
	expect(world.state.public_kitchen.meals=={"soup":2,"bread":1,"salad":0},"real Session partial contribution")
	expect(app.view.community_feedback.sample(10.5,false).get("kind")=="contribute","WorldView observes real contribution snapshot")
	await capture("community-contribute",10.5)
	await attach(GUEST)
	app.view.elapsed=20.0
	app.session.perform("kitchen_contribute",STOVE,"")
	expect(world.state.public_kitchen.opened,"real second member finishes meal")
	expect(app.view.community_feedback.sample(20.5,false).get("kind")=="opened","opening supersedes contribution in actual WorldView")
	var before:Dictionary=world.state.duplicate(true)
	for frame in 16:await capture("community-open-%02d"%frame,20.0+float(frame)*0.25)
	await capture("community-reduced",20.5,true)
	expect(app.view.community_feedback.sample(20.5,true).is_empty(),"reduced motion suppresses scene burst")
	await capture("community-settled",25.0)
	expect(app.view.community_feedback.sample(25.0,false).is_empty(),"opening expires on presentation clock")
	var newcomer:=View.new()
	newcomer.update_snapshot(app.session.snapshot,app.session.own_id)
	expect(newcomer.community_feedback.sample(0.5,false).is_empty(),"new view joining opened kitchen does not replay opening")
	newcomer.free()
	expect(world.state==before,"all scene presentation frames leave authoritative state unchanged")
	var public_table:=World.COMMUNITY.table_cell(world.state)
	world.state.players[GUEST].inventory["trout_hotpot"]=4
	app.session.perform("serve_hotpot",public_table)
	expect(int(app.view.data.community.get("hotpot",{}).get("portions",0))==4,"WorldView receives the served pot")
	await capture("hotpot-four",26.0)
	app.session.perform("claim_hotpot",public_table)
	expect(int(app.view.data.community.get("hotpot",{}).get("portions",0))==3,"WorldView receives the remaining portions")
	await capture("hotpot-three",27.0,true)
	world.state.players[GUEST].inventory["watermelon_platter"]=4
	app.session.perform("serve_watermelon",public_table)
	expect(int(app.view.data.community.get("watermelon",{}).get("portions",0))==4,"WorldView receives the platter")
	await capture("hotpot-and-watermelon",28.0,true)
	app.session.perform("claim_watermelon",public_table)
	expect(int(app.view.data.community.get("watermelon",{}).get("portions",0))==3 and int(app.view.data.community.hotpot.portions)==3,"Fruit and hotpot update independently")
	await capture("watermelon-three",29.0,true)
	world.state.festival_story_open=true
	app.session._send_snapshot(1)
	expect(app.view.data.festival_story_open,"Opened festival reaches the world renderer")
	await capture("festival-table",29.0,true)
	# Isolate the table pixels so no other world animations can mask a broken cue.
	viewport=SubViewport.new();viewport.size=Vector2i(160,128)
	viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	table=TableCanvas.new();table.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(table)
	table.kitchen=World.PUBLIC_KITCHEN.fresh()
	var picnic:=await art_frame({},0.0,true)
	table.kitchen=world.state.public_kitchen.duplicate(true)
	var opened:=await art_frame({},0.0,true)
	expect(picnic.get_data()!=opened.get_data(),"opened kitchen permanently changes the PNG table setting")
	expect(opened.get_data()==(await art_frame({},1.1,true)).get_data(),"reduced motion table pixels remain static across time")
	var normal_a:=await art_frame({},0.1,false)
	var normal_b:=await art_frame({},0.8,false)
	expect(normal_a.get_data()!=normal_b.get_data(),"soup steam visibly moves on native renderer")
	var cue_a:=await art_frame({"kind":"contribute","age":0.3,"meals":["soup"]},0.0,false)
	var cue_b:=await art_frame({"kind":"contribute","age":1.0,"meals":["soup"]},0.0,false)
	expect(cue_a.get_data()!=cue_b.get_data(),"contribution cue moves even with ambient steam clock frozen")
	var quiet:=await art_frame({},0.0,false)
	var party:=await art_frame({"kind":"opened","age":0.5,"meals":["soup","bread","salad"]},0.0,false)
	expect(quiet.get_data()!=party.get_data(),"opening adds visible scene feedback")
	expect(opened.get_data()==(await art_frame({"kind":"opened","age":0.5,"meals":["salad"]},0.0,true)).get_data(),"art layer also suppresses transient effects in reduced mode")
	table.portions=4
	var full:=await art_frame({},0.0,true)
	expect(full.get_data()==(await art_frame({},1.0,true)).get_data(),"Hotpot is static with reduced motion")
	table.portions=3
	var leftovers:=await art_frame({},0.0,true)
	expect(full.get_data()!=leftovers.get_data() and leftovers.get_data()!=opened.get_data(),"Portion markers change as hotpot is claimed")
	table.fruit=4
	var platter:=await art_frame({},0.0,true)
	table.fruit=3
	expect(platter.get_data()!=leftovers.get_data() and platter.get_data()!=(await art_frame({},0.0,true)).get_data(),"Visible watermelon slices match the portions")
	var caretaker:Dictionary=world.state.players[GUEST]
	caretaker.x=49.5
	caretaker.y=35.5
	caretaker.inventory.feed=2
	app.session._send_snapshot(1)
	app.view.display_positions[app.session.own_id]=Vector2(49.5,35.5)
	await capture("livestock-idle",0.0,true)
	for id:String in World.LIVESTOCK.ANIMALS:
		app.session.perform("livestock_feed",World.LIVESTOCK.ANIMALS[id].cell,id)
		expect(int(app.view.data.livestock.get(id,{}).get("feed",0))==1,"Animal feed state reaches the live renderer")
	await capture("livestock-fed",0.0,false)
	await capture("livestock-fed-frame-2",0.7,false)
	expect(world.step(World.LIVESTOCK.DAY*2,true),"Animal products mature through world time")
	app.session._send_snapshot(1)
	for id:String in World.LIVESTOCK.ANIMALS:
		expect(int(app.view.data.livestock[id].ready)==1,"Animal product state reaches the live renderer")
	await capture("livestock-produce",0.0,true)
	root.size=Vector2i(1024,640)
	preload("res://scripts/life_ui_almanac.gd").livestock_menu(app,"cow")
	app._layout_preview()
	await settle()
	var feed:Button
	var collect:Button
	var pet:Button
	for node in app.modal.find_children("*","Button",true,false):
		if node.text=="補充一份飼料":feed=node
		if node.text=="領取一份鮮奶":collect=node
	expect(feed!=null and feed.disabled,"Feed button reflects the empty backpack")
	expect(collect!=null and not collect.disabled,"Ready milk enables collection")
	expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect()),"Livestock card fits the compact desktop window")
	await capture("livestock-station-1024",0.0,true)
	if collect!=null:collect.pressed.emit()
	expect(int(caretaker.inventory.get("milk",0))==1,"Station control collects milk through the live session")
	preload("res://scripts/life_ui_almanac.gd").livestock_menu(app,"cow")
	for node in app.modal.find_children("*","Button",true,false):
		if node.text=="摸摸奶糖牛":pet=node
	expect(pet!=null and not pet.disabled,"Station offers petting")
	if pet!=null:pet.pressed.emit()
	expect(int(app.view.data.livestock.cow.get("bond",0))==1,"Actual pet control persists a bond in the local World")
	var pet_started:float=app.view.livestock_pet_feedback.get("cow",-10.0)
	expect(is_equal_approx(pet_started,app.view.elapsed),"Live snapshot triggers the cow reaction")
	app.session._send_snapshot(1)
	expect(app.view.livestock_pet_feedback.get("cow",-10.0)==pet_started,"Repeated snapshots do not restart the reaction")
	var art=preload("res://scripts/livestock_scene_art.gd")
	expect(art.pet_heart_origin(Vector2.ZERO,0.0,false).y>art.pet_heart_origin(Vector2.ZERO,0.7,false).y,"The heart rises on whole pixels")
	expect(art.pet_heart_origin(Vector2.ZERO,0.0,true)==art.pet_heart_origin(Vector2.ZERO,0.7,true),"Low-motion heart stays still")
	await capture("livestock-pet-heart",pet_started+0.7,false)
	# Seed the three storage states to check the device at a fixed camera position.
	var equipment_frames:Array[PackedByteArray]=[]
	for count in [0,3,World.LIVESTOCK.COLLECTOR_CAPACITY]:
		world.state.livestock.cow.collector=count
		app.session._send_snapshot(1)
		expect(int(app.view.data.livestock.cow.collector)==count,"Collector storage reaches the scene")
		await capture("livestock-collector-%d"%count,pet_started+2.0,true)
		equipment_frames.append(root.get_texture().get_image().get_data())
	expect(equipment_frames[0]!=equipment_frames[1] and equipment_frames[1]!=equipment_frames[2],"Collector storage states change native scene pixels")
	var cow:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	caretaker=world.state.players[GUEST]
	caretaker.x=cow.x+0.5
	caretaker.y=cow.y+0.5
	caretaker.inventory.wood=60
	caretaker.inventory.fiber=4
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i(0,2),Vector2i(-1,1),Vector2i(1,1)]:
		var tile:Vector2i=cow+offset
		world.state.removed[World.key(tile)]=true
		app.session._send_snapshot(1)
		app.session.perform("build",tile,"door" if offset==Vector2i.UP else "wall")
		await create_timer(0.2).timeout
	expect(World.LIVESTOCK.pen_status(world.state.objects,"cow"),"Live building actions form a cattle pen")
	app.session.perform("livestock_pen",cow,"cow")
	expect(world.state.livestock.cow.get("managed_pen",false),"Pen registers through the local session")
	app.view.display_positions[app.session.own_id]=Vector2(cow)+Vector2(0.5,0.5)
	await capture("livestock-pen-secure",pet_started+2.0,true)
	app.session.perform("remove",cow+Vector2i.RIGHT)
	await capture("livestock-pen-gap",pet_started+2.0,true)
	expect(app.view.world_labels.any(func(row):return row.id=="livestock:cow" and "圈舍待修" in row.title),"The focused animal shows the repair prompt on the map")
	app.session.shutdown()
	print("COMMUNITY_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
