extends SceneTree
## Native-rendered seeded fixture, NOT an earned journey or network playthrough.
## Inventory/story/positions/crop stages are seeded; furniture and meals use World.act.
const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/bakery_art.gd")
const HOST:="bakery-visual"
const MILL:=Vector2i(40,33)
const STOVE:=Vector2i(38,33)
const SEATS:=[Vector2i(37,34),Vector2i(37,32)]
const DEMO_CROP_START:=Vector2i(45,35)
var app
var world
var checks:=0
var failures:=0
var output:=""
func _initialize()->void:call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle()->void:
	for i in 8:await process_frame
func shot(name:String)->void:
	await settle()
	await RenderingServer.frame_post_draw
	if not output.is_empty():
		var path:=output.path_join(name+".png")
		expect(root.get_texture().get_image().save_png(path)==OK,"native screenshot "+name)
		print("BAKERY_SHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
func act(action:String,cell:Vector2i,extra:="")->void:
	var r:Dictionary=world.act(HOST,"bakery-visual-%d"%checks,action,cell,extra)
	expect(r.ok,"%s %s: %s"%[action,extra,r])
func build_mill()->void:
	act("build",MILL,"mill")
func attach()->void:
	app.session.profile={"token":HOST}
	app.session.world=world
	app.session._attach_registered(1,HOST)
	app.session.set_physics_process(false)
	app.set_process(false)
	app.view.set_process(false)
	app._refresh_hud()
	app.view._process(0.0)
	app.toast.hide()
	await settle()
func bounds()->void:
	var box:Rect2=app.modal.get_global_rect()
	expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(box),"modal fits "+str(root.size))
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Native renderer required");quit(1);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for id in Art.ITEMS:
		var texture:Texture2D=Art.icon(id)
		expect(texture!=null and texture.get_size()==Vector2(32,32),"native item size "+id)
	for i in 4:expect(Art.growth_texture(i)!=null,"growth stage "+str(i))
	expect(Art.mill_texture()!=null and Art.mill_texture().get_size()==Vector2(32,48),"mill native size")
	app=load("res://main.tscn").instantiate();app.village_art_preview=true
	root.add_child(app);root.size=Vector2i(1280,800)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.title="糰糰島｜南瓜與磨坊原生畫面檢查"
	world=World.new();world.save_path="user://bakery-visual.json"
	world.add_player(HOST,"小禾")
	var player:Dictionary=world.state.players[HOST]
	player.x=38.5;player.y=32.5;player.stories.aru=2
	player.inventory={"wood":100,"stone":100,"fiber":100,"soup":4,"bread":2,"salad":2,"mill_kit":1,"wheat":8,"pumpkin":2,"flour":2,"egg":2,"pumpkin_seed":3}
	world.state.picnic=true;world.state.board=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	for piece in [[STOVE,"stove"],[SEATS[0],"long_bench"],[SEATS[1],"long_bench"]]:act("build",piece[0],piece[1])
	act("kitchen_register",STOVE,World.PUBLIC_KITCHEN.seat_extra(SEATS[0],SEATS[1]))
	act("kitchen_contribute",STOVE)
	player=world.state.players[HOST];player.x=40.5;player.y=32.5
	build_mill()
	# Keep the demonstration pumpkins outside the larger mill and its entrance.
	for i in 4:
		world.state.crops[World.key(DEMO_CROP_START+Vector2i(i,0))]={"kind":"pumpkin","owner":HOST,"wet":true,"growth":[0.0,80.0,190.0,270.0][i],"remaining":1}
	await attach()
	await shot("bakery-world")
	for size in [Vector2i(1280,800),Vector2i(1024,640)]:
		root.size=size;await settle()
		app._close_modal()
		preload("res://scripts/processing_queue_ui.gd").open(app,MILL)
		await settle();bounds();await shot("mill-%d"%size.x)
		app._close_modal()
		preload("res://scripts/cooking_queue_ui.gd").open(app,STOVE)
		var controller=app.modal.get_meta("cooking_queue")
		controller.select("pumpkin_pie")
		await settle();bounds()
		for row in controller.refs.ingredients.get_children():
			expect(app.modal.get_global_rect().encloses(row.get_global_rect()),"entire ingredient row fits: "+str(row.name))
		await shot("pie-%d"%size.x)
		app._close_modal();app._open_inventory_grid()
		await settle()
		app.modal.select_category(3)
		await settle()
		app.modal.select_item("pumpkin")
		app.modal.slots.pumpkin.grab_focus()
		app.modal.scroller.ensure_control_visible(app.modal.slots.pumpkin)
		expect(app.modal.selected_id=="pumpkin","inventory actually selects pumpkin")
		await settle()
		expect(app.modal.scroller.get_global_rect().intersects(app.modal.slots.pumpkin.get_global_rect()),"selected pumpkin slot is onscreen")
		await settle();bounds();await shot("inventory-%d"%size.x)
		app._close_modal()
	app.queue_free();await settle()
	print("BAKERY_VISUAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
