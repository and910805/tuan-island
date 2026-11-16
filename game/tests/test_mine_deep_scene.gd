extends SceneTree
## T067 native render check for B6–B15. Isolated host save; mine progress is a
## PRESET (unlocked 15, pumped 24, hoist repaired) and the player is placed by the fixture. World
## time is not advanced. Screenshots go to outputs/第六至十五層預覽 (or --capture-dir=).
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/mine_ui.gd")
const MineArt=preload("res://scripts/mine_art.gd")
var app
var w
var id:String
var checks:=0
var failures:=0
var output:=""

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	if is_instance_valid(app.toast):app.toast.hide()
	await settle()

func shot(name:String)->Image:
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var path:=output.path_join(name+".png")
	check(image.save_png(path)==OK,"native screenshot "+name)
	print("MINE_DEEP_SHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
	return image

func place(region:String,p:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x;person.y=p.y
	await refresh()

func label_texts(node:Node)->String:
	var out:=PackedStringArray()
	for label in node.find_children("*","Label",true,false):
		if label.is_visible_in_tree():out.append(label.text)
	return "\n".join(out)

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/第六至十五層預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	var path:=OS.get_environment("TEMP").path_join("deep-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"深層旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.picnic=true;w.state.board=true
	w.state.mine_depths={"unlocked":15,"ready":{},"pumped":24,"hoist":true}  # PRESET (Q07 hoist already repaired)
	w.state.players[id].mine_energy=80
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var floors:={}
		for depth in [5,6,10,13,15]:
			await place("mine_%d"%depth,Vector2(World.MINES.LIFT)+Vector2(2.5,2.5))
			check(app.session.snapshot.region_id=="mine_%d"%depth,"Snapshot on B%d"%depth)
			floors[depth]=await shot("B%02d-lift-%s"%[depth,tag])
			var hud:=label_texts(app)
			check(hud.contains("地下第 %d 層"%depth),"HUD names B%d at %s"%[depth,tag])
		check(floors[6].get_data()!=floors[13].get_data(),"Rust and warm-rock zones render differently at "+tag)
		check(floors[10].get_data()!=floors[15].get_data(),"Seep and lantern zones render differently at "+tag)
		# Station cards on real floors.
		await place("jinguashi",Vector2(World.MINES.ENTRY)+Vector2(0.5,1.5))
		UI.open(app,"entry");await settle()
		check(app.modal.find_child("MineLift15",true,false)!=null,"Entry lists the B15 landing at "+tag)
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Entry card fits at "+tag)
		await shot("surface-entry-%s"%tag)
		app._close_modal()
		await place("mine_12",Vector2(World.MINES.LIFT)+Vector2(0.5,1.5))
		UI.open(app,"lift");await settle()
		check(app.modal.find_child("MineLiftUp",true,false)!=null and not (app.modal.find_child("MineLiftUp",true,false) as BaseButton).disabled,"B12 hoist button is enabled at "+tag)
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Lift card fits at "+tag)
		await shot("B12-lift-card-%s"%tag)
		app._close_modal()
		w.state.mine_depths.unlocked=14
		await place("mine_14",Vector2(World.MINES.SERVICE)+Vector2(-0.5,1.5))
		UI.open(app,"service");await settle()
		check(app.modal.find_child("MineCommission",true,false)!=null,"B14 commission card at "+tag)
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Service card fits at "+tag)
		await shot("B14-service-%s"%tag)
		app._close_modal()
		w.state.mine_depths.unlocked=15
	finish()

func finish()->void:
	print("MINE_DEEP_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
