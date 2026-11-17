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
	app.queue_free()
	await process_frame
