extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Art=preload("res://scripts/coast_awning_art.gd")
const KIND=Industry.COAST_AWNING
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,35)
const ROTATED:=Vector2i(40,36)
const STALL:=Vector2i(43,29)
var app
var world:World
var owner:String
var path:String
var output:String
var checks:=0
var failures:=0
var sequence:=0

func _initialize()->void:
	run.call_deferred()

func expect(condition:bool,message:String)->void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func action(name:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	sequence+=1
	return world.act(owner if actor.is_empty() else actor,"awning-%d"%sequence,name,cell,extra)

func stand(person:Dictionary,position:Vector2)->void:
	person.x=position.x
	person.y=position.y

func valid_footprint(anchor:Vector2i,vertical:bool)->bool:
	var offsets:=Industry.station_cells(KIND,vertical)
	for part in offsets.size():
		var tile:=anchor+Vector2i(offsets[part])
		var obj:Dictionary=world.state.objects.get(World.key(tile),{})
		if obj.get("type")!=KIND or obj.get("owner")!=owner or Industry.square_part(obj)!=part or Industry.is_vertical(obj)!=vertical or world.blocked(tile):return false
	return true

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.26).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BLUE_STRIPE_AWNING_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("awning-preview","")
	path="user://awning-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="awning-builder"
	if app.session.host(0,"海邊工坊的木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":50,"cotton_cloth":26,"fiber":20,"radish":1},true)
	world.state.time=720.0
	for area:Rect2i in [Rect2i(SITE,Vector2i(3,2)),Rect2i(MOVED,Vector2i(3,2)),Rect2i(ROTATED,Vector2i(2,3))]:
		for y in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				world.state.removed[World.key(Vector2i(x,y))]=true
	stand(person,Vector2(41.5,33.5))
	app.session._send_snapshot(1)
	app._build_menu()
	var shelf:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text=="海邊":shelf=candidate
	expect(shelf!=null,"The workshop has a coastal shelf")
	if shelf==null:
		finish()
		return
	shelf.pressed.emit()
	var recipe:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(shelf.name).trim_prefix("BuildTab"),true,false) as Button
	expect(recipe!=null and recipe.is_visible_in_tree(),"The coastal shelf shows the awning")
	if recipe==null:
		finish()
		return
	recipe.pressed.emit()
	await capture("workshop")
	var build:=app.modal.find_child("BuildPlace",true,false) as Button
	if build!=null:build.pressed.emit()
	expect(app.building==KIND and app.view.build_placement_offsets(KIND).size()==6,"The build tool uses the six-cell footprint")
	var corner:=World.key(SITE+Vector2i(2,1))
	world.state.objects[corner]={"type":"chair","owner":owner,"items":{}}
	expect(not action("build",SITE,KIND).ok and person.inventory.wood==50 and not world.state.objects.has(World.key(SITE)),"A blocked corner refuses the entire placement before charging")
	world.state.objects.erase(corner)
	app._perform_build_action("build",SITE,KIND)
	var placed:=valid_footprint(SITE,false)
	expect(placed,"The normal build tool constructs the six walkable canopy squares")
	if not placed:
		finish()
		return
	expect(person.inventory.wood==32 and person.inventory.cotton_cloth==18 and person.inventory.fiber==14,"The recipe is charged once at the right quantities")
	app._select_tool("hoe")
	await capture("awning")
	for step:int in range(3):world.move_player(owner,Vector2.DOWN,0.10)
	var inside:=Vector2(person.x,person.y)
	expect(Rect2(Vector2(SITE),Vector2(3,2)).has_point(inside),"A normal movement input can enter under the roof")
	app.session._send_snapshot(1)
	expect(Art.opacity(SITE,false,inside,false)<0.50 and Art.opacity(SITE,false,inside,true)==0.37,"The canopy reveals the person in either motion setting")
	expect(Art.opacity(SITE,false,Vector2(SITE)-Vector2.ONE,false)==1.0,"The roof is opaque when viewed from outside")
	await capture("under-awning")
	for step:int in range(5):world.move_player(owner,Vector2.DOWN,0.10)
	expect(float(person.y)>=36.0,"The player can walk out the other side of the canopy")
	stand(person,Vector2(43.5,30.5))
	var coins:=int(person.coins)
	expect(action("sell",STALL,"radish").ok and person.coins==coins+World.CROPS.radish.price,"The existing shop pays the normal sale price with the canopy present")
	var raw:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i(3,2)),"海邊遮陽棚",World.BUILD,World.NAMES)
	expect(raw.ok and raw.blueprint.pieces.size()==1,"A blueprint captures all six squares as one item")
	expect(not World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i(2,2)),"局部棚",World.BUILD,World.NAMES).ok,"A clipped blueprint is rejected")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup and saved.state.objects.get(World.key(SITE+Vector2i(2,1)),{}).get("awning_part")==5,"Reload restores a complete footprint from the primary save")
	var broken:=world.state.duplicate(true)
	broken.objects.erase(World.key(SITE+Vector2i(2,1)))
	expect(not World.SAVE_SCHEMA.validate(broken,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A save with a missing square is rejected")
	world.add_player("awning-guest","訪客")
	stand(world.state.players["awning-guest"],Vector2(43.5,34.5))
	expect(not action("remove",SITE+Vector2i(2,0),"","awning-guest").ok and valid_footprint(SITE,false),"A visitor cannot dismantle the canopy")
	stand(world.state.players["awning-guest"],Vector2(47.5,34.5))
	stand(person,Vector2(42.5,35.5))
	expect(action("move_object",SITE+Vector2i(1,0),World.key(MOVED)).ok and valid_footprint(MOVED,false) and not world.state.objects.has(World.key(SITE)),"Moving from a secondary square relocates the whole canopy")
	expect(action("remove",MOVED+Vector2i(1,0)).ok and person.inventory.wood==50 and person.inventory.cotton_cloth==26 and person.inventory.fiber==20,"Removal from a secondary square refunds the recipe once")
	if raw.get("ok",false):
		stand(person,Vector2(41.5,35.5))
		var quote:=world.quote_blueprint(owner,raw.blueprint,ROTATED,1)
		expect(quote.ok,"The rotated blueprint quotes a legal site: "+str(quote.get("message","")))
		if quote.ok:
			var applied:=world.apply_blueprint(owner,"a".repeat(32),raw.blueprint,ROTATED,1,quote.hash)
			expect(applied.ok and valid_footprint(ROTATED,true),"A quarter-turn places the canopy two across and three deep: "+str(applied.get("message","")))
			app.session._send_snapshot(1)
			await capture("rotated")
			expect(action("remove",ROTATED+Vector2i.DOWN).ok,"The long orientation can also be dismantled from a secondary square")
	finish()
