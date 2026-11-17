extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const TOKEN:="gallery-owner"
const BOARD:=Vector2i(40,29)
var checks:=0
var failures:=0

func expect(ok:bool,description:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(description)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"田園島民")
	var person:Dictionary=world.state.players[TOKEN]
	person.inventory.merge({"radish":1,"quality_radish":2,"gold_sample":1},true)
	expect(not world.act(TOKEN,"too-far","collection_donate",BOARD,"radish").ok,"Donations require the public board")
	person.x=BOARD.x+0.5
	person.y=BOARD.y+0.5
	expect(not world.act(TOKEN,"not-donated","collection_display",BOARD,"radish").ok,"Cannot display an unregistered item")
	expect(not world.act(TOKEN,"wrong-grade","collection_donate",BOARD,"quality_radish").ok,"Premium crops are not consumed")
	expect(world.act(TOKEN,"donate","collection_donate",BOARD,"radish").ok and int(person.inventory.radish)==0
		and int(person.inventory.quality_radish)==2,"Donate precisely one ordinary item")
	expect(not world.act(TOKEN,"second","collection_donate",BOARD,"radish").ok,"A collection entry is only donated once")
	expect(world.act(TOKEN,"story","collection_donate",BOARD,"gold_sample").ok and int(person.inventory.gold_sample)==1,
		"Recording a story object keeps the original")
	for item in ["radish","gold_sample"]:
		expect(world.act(TOKEN,"display-"+item,"collection_display",BOARD,item).ok,"Show a recorded item")
	expect(not world.act(TOKEN,"duplicate-display","collection_display",BOARD,"radish").ok,"No duplicate public display")
	var path:="user://collection-gallery-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path),"Reload the collection gallery")
	person=world.state.players[TOKEN]
	expect(person.collection_display==["radish","gold_sample"] and int(person.inventory.gold_sample)==1,"Records and keepsake survive reloading")
	var server:=Session.new()
	server.world=world
	var public_view:=server.public_state()
	var exhibited:Array=public_view.collection_exhibits.values()
	expect(exhibited==[{"name":"田園島民","items":["radish","gold_sample"]}],"Public exhibition survives even when the collector is offline")
	server.free()
	if DisplayServer.get_name()!="headless":await verify_scene(world,public_view.collection_exhibits)
	expect(world.act(TOKEN,"remove","collection_unshow",BOARD,"radish").ok and person.collection_display==["gold_sample"]
		and person.collection_donations.radish,"Removing a display preserves the donation")
	var chest:=BOARD+Vector2i.DOWN
	world.state.objects[World.key(chest)]={"type":"chest","owner":TOKEN,"items":{"carrot":1}}
	expect(world.act(TOKEN,"loan","withdraw",chest,"carrot").ok and person.collection_acquired.carrot,
		"An item received through storage counts as acquired")
	expect(world.act(TOKEN,"give-back","deposit",chest,"carrot").ok and int(person.inventory.carrot)==0
		and person.collection_acquired.carrot,"Returning it keeps the acquisition record")
	for item in ["radish","lettuce","wheat","carp","minnow"]:
		if not person.collection_donations.has(item):
			person.inventory[item]=1
			expect(world.act(TOKEN,"donate-"+item,"collection_donate",BOARD,item).ok,"Donate the next gallery item")
		expect(world.act(TOKEN,"fill-"+item,"collection_display",BOARD,item).ok,"Fill the shelf to its limit")
	person.inventory.soup=1
	expect(world.act(TOKEN,"donate-soup","collection_donate",BOARD,"soup").ok,"Additional donations are still accepted")
	expect(not world.act(TOKEN,"overflow","collection_display",BOARD,"soup").ok
		and person.collection_display.size()==World.Collections.DISPLAY_CAP,"The gallery cannot overflow its six public places")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COLLECTION_GALLERY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_scene(world:World,exhibits:Dictionary)->void:
	var app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.session.snapshot.collection_exhibits=exhibits
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._collection_gallery()
	await create_timer(0.27).timeout
	var labels:Array=app.modal.find_children("*","Label",true,false)
	expect(labels.any(func(node):return node.text=="渡口收藏展示" and node.is_visible_in_tree()),"The almanac shows the public display")
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--gallery-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--gallery-preview="))==OK,"Capture the gallery")
	var crops:Button=app.modal.find_child("CollectionTab1",true,false)
	crops.pressed.emit()
	expect(labels.any(func(node):return node.text=="✓見過  ✓取得\n✓捐贈  ✓展示" and node.is_visible_in_tree()),"The card displays all four stamps")
	var story:Button=app.modal.find_child("CollectionTab5",true,false)
	story.pressed.emit()
	expect(labels.any(func(node):return node.text=="有點歪的第一塊板" and node.is_visible_in_tree()),
		"The story tab displays the resident keepsake catalogue")
	app.queue_free()
	await process_frame
