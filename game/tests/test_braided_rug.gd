extends SceneTree

const World=preload("res://scripts/world.gd")
const KIND:=World.INDUSTRY.BRAIDED_RUG
const SITE:=Vector2i(42,34)
const DESTINATION:=Vector2i(43,35)
const PARTS:=World.INDUSTRY.SQUARE_CELLS
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(condition:bool,message:String)->void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func parts_match(world:World,site:Vector2i)->bool:
	for i in PARTS.size():
		var k:=World.key(site+PARTS[i])
		var object:Dictionary=world.state.objects.get(k,{})
		if object.get("type")!=KIND or object.get("braided_rug_part")!=i or world.blocked(site+PARTS[i]):return false
	return true

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	var path:="user://braided-rug-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="braided-rug-owner"
	if app.session.host(0,"織繩師",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	var world:World=app.session.world
	var owner:String=app.session.peers[1]
	var player:Dictionary=world.state.players[owner]
	player.inventory.merge({"fiber":12,"cotton_cloth":2,"wood":8},true)
	player.x=41.5
	player.y=35.5
	world.state.time=720.0
	for base in [SITE,DESTINATION]:
		for offset:Vector2i in PARTS:world.state.removed[World.key(base+offset)]=true
	for i in 3:
		expect(world.act(owner,"floor-%d"%i,"build",SITE+PARTS[i],"floor").ok,"Lay wooden floor before placing the rug")
	app.session._send_snapshot(1)
	app._perform_build_action("build",SITE,KIND)
	expect(parts_match(world,SITE),"Normal build adds a single walkable 2×2 rug")
	expect(player.inventory.fiber==0 and player.inventory.cotton_cloth==0,"One build spends exactly one recipe")
	expect(world.act(owner,"last-floor","build",SITE+Vector2i.ONE,"floor").ok,"Wood flooring may be installed beneath an owned rug")
	world.move_player(owner,Vector2.RIGHT,0.33)
	expect(player.x>42.0 and player.x<44.0,"Player walks onto the rug from the side")
	app.session._send_snapshot(1)
	app._select_tool("hoe")
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2.ONE)*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	if DisplayServer.get_name()!="headless":
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var output:String=app.arg_value("qa-dir","")
		if not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output)
			expect(root.get_texture().get_image().save_png(output.path_join("rug-over-wood.png"))==OK,"Capture character standing on the rug")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and parts_match(reloaded,SITE),"Reload restores all four rug pieces and collision stays disabled")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,2)),"編繩角落",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces.size()==5 and design.blueprint.pieces.back().kind==KIND,"Blueprint captures four wood tiles and a single rug")
	player.x=42.0
	player.y=34.3
	world.add_player("rug-visitor","客人",SITE+Vector2i.LEFT)
	expect(not world.act("rug-visitor","take-rug","remove",SITE+Vector2i.RIGHT).ok,"Visitor cannot remove another owner's rug")
	expect(world.act(owner,"move-rug","move_object",SITE+Vector2i.ONE,World.key(DESTINATION)).ok and parts_match(world,DESTINATION),"Moving from a corner transports the full rug, including partial overlap")
	var floor_count:=0
	for offset:Vector2i in PARTS:
		if world.state.ground.get(World.key(SITE+offset),{}).get("type")=="floor":floor_count+=1
	expect(floor_count==4,"All four original floor tiles survive moving")
	expect(world.act(owner,"remove-rug","remove",DESTINATION+Vector2i.RIGHT).ok and player.inventory.fiber==12 and player.inventory.cotton_cloth==2,"Removal from a corner refunds exactly one rug")
	if design.ok:
		var origin:=Vector2i(44,35)
		for offset:Vector2i in PARTS:world.state.removed[World.key(origin+offset)]=true
		player.x=43.0
		player.y=35.5
		player.inventory.wood=8
		var quote:=world.quote_blueprint(owner,design.blueprint,origin,1)
		expect(quote.ok,"Rotated blueprint quotes the wood flooring and rug together")
		if quote.ok:
			var built:=world.apply_blueprint(owner,"1".repeat(32),design.blueprint,origin,1,quote.hash)
			expect(built.ok and parts_match(world,origin) and world.state.ground.get(World.key(origin+Vector2i.ONE),{}).get("type")=="floor","Blueprint builds both layers and keeps the rug walkable")
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for file in [path,path+".bak",path+".writer-lock"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("BRAIDED_RUG_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
