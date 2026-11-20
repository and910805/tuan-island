extends SceneTree

const World=preload("res://scripts/world.gd")
var app
var output:=""

func _initialize()->void:
	run.call_deferred()

func capture(file:String)->void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(file+".png"))==OK)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	assert(not output.is_empty() and DirAccess.make_dir_recursive_absolute(output)==OK)
	var path:="user://pickup-preview-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="pickup-preview"
	assert(app.session.host(0,"採石測試",path)==OK)
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	var world:World=app.session.world
	var person:Dictionary=world.state.players[app.session.peers[1]]
	var tile:=Vector2i(-1,-1)
	var spot:=Vector2.ZERO
	var drop_position:=Vector2.ZERO
	for y in range(35,43):
		for x in range(35,48):
			var candidate:=Vector2i(x,y)
			var at:=Vector2(candidate)+Vector2(1.8,0.6)
			if tile.x<0 and world.resource(candidate)=="rock" and not world.protected(candidate) and world.can_stand(at) and world.can_stand(at-Vector2(0.5,0.0)):
				tile=candidate
				spot=at
				drop_position=Vector2(tile)+Vector2(0.5,0.5)
	assert(tile.x>=0)
	person.x=spot.x
	person.y=spot.y
	world.state.time=720.0
	app.session._send_snapshot(1)
	app._select_tool("pick")
	await create_timer(0.25).timeout
	assert("走近撿材料" in app.selected_label.text)
	await capture("stone-before")
	var before:=int(person.inventory.get("stone",0))
	app.session.perform("pick",tile)
	assert(app.view.tool_feedback.pickups.is_empty())
	await create_timer(0.60).timeout
	app.session.perform("pick",tile)
	var tile_key:=World.key(tile)
	assert(int(person.inventory.stone)==before)
	assert(app.session.snapshot.gather_drops[tile_key].items=={"stone":5})
	var reloaded:=World.new()
	assert(reloaded.load_world(path))
	assert(reloaded.region_snapshot("home").gather_drops[tile_key].items=={"stone":5.0})
	assert(reloaded.region_snapshot("lanyang").gather_drops.is_empty())
	assert(app.session.world.step(1.0,true))
	app.session._send_snapshot(1)
	await create_timer(0.9).timeout
	assert(int(person.inventory.stone)==before)
	await capture("stone-on-ground")
	# This visual fixture changes which player owns the already tested
	# bundle. Peer enforcement is exercised by test_shared_resource_race_session.
	var drop:Dictionary=world.state.gather_drops[World.REGIONS.HOME][tile_key]
	var gatherer:String=drop.reserved_for
	var other_gatherer:="pickup-preview-other"
	world.add_player(other_gatherer,"另一位採集者")
	drop.reserved_for=other_gatherer
	app.session._send_snapshot(1)
	await create_timer(0.15).timeout
	await capture("stone-reserved")
	assert(app.view.world_labels.any(func(label):return label.id.begins_with("gather-reservation:")))
	drop.reserved_for=gatherer
	app.session._send_snapshot(1)
	await capture("stone-owner-view")
	assert(not app.view.world_labels.any(func(label):return label.id.begins_with("gather-reservation:")))
	app.session.set_physics_process(true)
	var direction:Vector2=spot.direction_to(drop_position)
	for frame in range(10):
		app.session.input_direction(direction)
		await physics_frame
	app.session.input_direction(Vector2.ZERO)
	assert(int(person.inventory.stone)==before+5)
	await create_timer(0.12).timeout
	assert(app.session.snapshot.gather_drops.is_empty())
	assert(app.view.tool_feedback.pickups.values().any(func(event):return event.get("collected",false)))
	await capture("stone-pickup")
	await create_timer(0.35).timeout
	assert(int(person.inventory.stone)==before+5)
	assert(reloaded.load_world(path) and reloaded.region_snapshot("home").gather_drops.is_empty())
	print("GATHER_PICKUP_CAPTURE_PASS stone_delta=5")
	app.session.set_physics_process(false)
	person.x=spot.x
	person.y=spot.y
	world.state.forest[tile_key]={"growth":180.0,"mature":true,"owner":app.session.profile.token}
	app.session._send_snapshot(1)
	app._select_tool("axe")
	var tree_items:={"wood":6,"fiber":2,"sapling":1,"resin":1,"hardwood":World.HARDWOOD_YIELD}
	var tree_inventory:Dictionary=person.inventory.duplicate()
	for strike in range(3):
		app.session.perform("axe",tile)
		await create_timer(0.65).timeout
	assert(app.session.snapshot.gather_drops[tile_key].items==tree_items)
	assert(person.inventory==tree_inventory)
	assert(world.step(1.0,true))
	app.session._send_snapshot(1)
	await create_timer(0.20).timeout
	await capture("tree-materials-on-ground")
	app.session.set_physics_process(true)
	for frame in range(10):
		app.session.input_direction(direction)
		await physics_frame
	app.session.input_direction(Vector2.ZERO)
	for item:String in tree_items:
		assert(int(person.inventory[item])==int(tree_inventory.get(item,0))+tree_items[item])
	await create_timer(0.12).timeout
	assert(app.session.snapshot.gather_drops.is_empty())
	print("MIXED_GATHER_PICKUP_CAPTURE_PASS items=5")
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	quit()
