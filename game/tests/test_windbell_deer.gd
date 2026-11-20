extends SceneTree

const World=preload("res://scripts/world.gd")
const Deer=World.Deer
const TOKEN:="windbell-deer-preview"
var checks:=0
var failures:=0

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"樹下的訪客")
	var player:Dictionary=world.state.players[TOKEN]
	player.x=Deer.SITE.x+1.55
	player.y=Deer.SITE.y+0.6
	expect(not Deer.present(world.state),"No visitor before the festival")
	expect(not world.act(TOKEN,"before",Deer.ACTION,Deer.SITE).ok,"Interaction is locked before opening")
	world.state.festival_story_open=true
	expect(Deer.present(world.state),"The visitor arrives when the festival opens")
	expect(Deer.site({"crops":{World.key(Deer.SITE):{}}})!=Deer.SITE,"The visitor stays clear of a player's field")
	verify_crowded_sites(world)
	verify_resident_fallback(world)
	if DisplayServer.get_name()!="headless":await verify_scene(world)
	expect(world.act(TOKEN,"observe",Deer.ACTION,Deer.SITE).ok and player.windbell_deer_seen,"Record the personal encounter")
	expect(not world.act(TOKEN,"again",Deer.ACTION,Deer.SITE).ok,"The encounter cannot be repeated")
	var path:="user://windbell-deer-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path),"Festival visitor save reloads")
	expect(world.state.players[TOKEN].windbell_deer_seen and Deer.present(world.state),"The personal observation and visitor survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WINDBELL_DEER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_crowded_sites(world:World)->void:
	var scene:Dictionary=world.region_snapshot("home")
	for cell:Vector2i in Deer.SITES:
		expect(world.can_stand(Vector2(cell)+Vector2(0.5,0.5)),"Every candidate starts on clear ground")
	for index in range(4):
		scene[["crops","forest","objects","roofs"][index]][World.key(Deer.SITES[index])]={}
	expect(Deer.present(scene) and Deer.site(scene)==Deer.SITES[4],"A crowded tree shifts the deer to a nearby spot")
	for index in range(4,Deer.SITES.size()):
		scene.objects[World.key(Deer.SITES[index])]={}
	expect(not Deer.present(scene) and Deer.site(scene)==Deer.NO_SITE,"A fully crowded tree does not draw a deer inside the furniture")
	scene.objects.erase(World.key(Deer.SITES[5]))
	expect(Deer.present(scene) and Deer.site(scene)==Deer.SITES[5],"Clearing a spot brings the deer back")

func verify_resident_fallback(world:World)->void:
	var festival:=World.new()
	festival.state=world.state.duplicate(true)
	var scene:Dictionary=festival.state
	scene.picnic=true
	var bell:=World.RESIDENT_BOND.bell_cell(scene)
	scene.objects[World.key(bell)]={"type":"wall","owner":TOKEN}
	var fallback:=World.RESIDENT_BOND.bell_cell(scene)
	var deer_cell:=Deer.site(scene)
	expect(fallback==Deer.SITE,"A blocked resident space moves 鈴婆婆 to the first deer candidate")
	expect(deer_cell!=fallback and deer_cell!=Deer.NO_SITE,"During the festival both the resident and deer keep separate sites")
	var nearby:=Vector2(fallback+Vector2i.RIGHT)+Vector2(0.5,0.5)
	expect(festival.can_stand(nearby),"The shared approach remains walkable")
	var person:Dictionary=scene.players[TOKEN]
	person.x=nearby.x
	person.y=nearby.y
	expect(festival.act(TOKEN,"fallback-talk","resident_talk",fallback,"lingpopo").ok,"Talk to 鈴婆婆 at the fallback cell")
	expect(festival.act(TOKEN,"fallback-deer",Deer.ACTION,deer_cell).ok,"Observe the deer at its own cell")

func verify_scene(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.session.snapshot.festival_story=world.festival_story_view()
	app.session.snapshot.time=1060.0
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--deer-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--deer-preview="))==OK,"Capture the visitor at the festival")
	app._interact()
	await create_timer(0.25).timeout
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	var replay:Button=null
	for button:Button in buttons:
		if button.text=="重看風鈴節尾聲":replay=button
	expect(replay!=null,"The deer interaction opens the epilogue card")
	if replay!=null:
		replay.pressed.emit()
		var labels:Array=app.modal.find_children("*","Label",true,false)
		expect(labels.any(func(node):return node.text=="樹下的最後一位訪客"),"The deer has a replayable closing scene")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--deer-crowded-preview="):
			await capture_crowded_scene(app,world,arg.trim_prefix("--deer-crowded-preview="))
	app.queue_free()
	await process_frame

func capture_crowded_scene(app,world:World,path:String)->void:
	var crowded:=World.new()
	crowded.state=world.state.duplicate(true)
	var person:Dictionary=crowded.state.players[TOKEN]
	for index in range(4):
		var cell:Vector2i=Deer.SITES[index]
		person.x=cell.x+0.5
		person.y=cell.y+0.5
		expect(crowded.act(TOKEN,"preview-%d"%index,"hoe",cell).ok,"Prepare the crowded layout through the farming action")
	var spot:=Deer.site(crowded.state)
	person.x=spot.x+1.5
	person.y=spot.y+0.5
	app._close_modal()
	app.session.snapshot=crowded.region_snapshot("home")
	app.session.snapshot.festival_story=crowded.festival_story_view()
	app.session.snapshot.time=1060.0
	app._state_changed(app.session.snapshot,TOKEN)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(path)==OK,"Capture the deer beside, clear of the tilled plots")
