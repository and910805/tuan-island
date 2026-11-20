extends SceneTree

const World=preload("res://scripts/world.gd")
const Glass=World.GREENHOUSE_GLASS
const KIND:=Glass.XINGHE_ROOF
const Music=preload("res://scripts/scene_music.gd")
const PLOT:=Vector2i(40,34)
const GLASS_TILES:=[PLOT,Vector2i(41,34),Vector2i(40,35),Vector2i(41,35)]
const BOUNDARY:=[Vector2i(40,33),Vector2i(41,33),Vector2i(39,34),Vector2i(42,34),Vector2i(39,35),Vector2i(42,35),Vector2i(41,36)]
const DOOR:=Vector2i(40,36)
const LEGACY_PLOT:=Vector2i(38,34)
var app
var world:World
var owner:String
var directory:String
var serial:=0
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,at:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(owner,"xinghe-roof-%d"%serial,action,at,extra)

func set_pos(person:Dictionary,position:Vector2)->void:
	person.x=position.x
	person.y=position.y

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Saved "+name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("xinghe-preview","")
	var path:="user://xinghe-roof-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="xinghe-roof-qa"
	if app.session.host(0,"星禾溫室測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"glass":18,"copper_ingot":8,"copper_joint":3,"wood":100,"stone":24,"radish_seed":6},true)
	expect(not act("build",PLOT,KIND).ok and person.inventory.glass==18,"Xinghe's trust episode gates the roof on the server")
	person.bonds={"xinghe":{"points":14,"talk_day":-1,"gift_day":-1}}
	person.greenhouse_glass_crafted=true
	var site:=World.bond_place(world.state,"xinghe")
	person.region=site[0]
	set_pos(person,Vector2(site[1])+Vector2(0.5,0.5))
	var completed:=act(World.RESIDENT_GOALS.ACTION,site[1],"xinghe:3::")
	expect(completed.ok and World.RESIDENT_GOALS.done(person,"xinghe").has(3),"Complete the actual trust episode with Xinghe in spring: "+str(completed.get("message","")))
	person.region=World.REGIONS.HOME
	set_pos(person,Vector2(40.5,34.5))
	app.session._send_snapshot(1)
	app.LifeTasks.bond_goal(app,"xinghe",3)
	var pattern:=app.modal.find_child("XingheGreenhousePattern",true,false) as Button
	expect(pattern!=null,"Xinghe's completed episode links to the real workshop pattern")
	if pattern!=null:pattern.pressed.emit()
	else:app._build_menu()
	var greenhouse:Button
	for tab:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if tab.text=="星砂溫室":greenhouse=tab
	expect(greenhouse!=null,"The greenhouse category is available")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The new pane has an illustrated workshop tile")
		if slot!=null:slot.pressed.emit()
	app._layout_preview()
	await capture("xinghe-roof-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The recipe is now enabled")
	if place!=null:place.pressed.emit()
	world.state.time=World.WEATHER.DAY_SECONDS*World.WEATHER.DAYS_PER_SEASON*3+650.0
	expect(act("hoe",PLOT).ok,"Prepare soil for a real test crop")
	app.session.perform("build",PLOT,KIND)
	var plot_key:=World.key(PLOT)
	expect(world.state.roofs.get(plot_key,{}).get("type")==KIND and person.inventory.glass==14 and person.inventory.copper_ingot==7,"The first roof tile costs two glass and one copper")
	var sowed:=act("seed",PLOT,"radish")
	expect(sowed.ok and "休眠" in str(sowed.get("message","")) and not world.greenhouse_covers(plot_key),"A crop under a lone tile enters dormancy in winter")
	for i in BOUNDARY.size():
		expect(act("build",BOUNDARY[i],"window" if i==1 else "wall").ok,"Build the greenhouse perimeter")
	expect(act("build",DOOR,"door").ok,"Put a closing door on the last perimeter tile")
	for cell:Vector2i in GLASS_TILES.slice(1,3):
		expect(act("build",cell,KIND).ok,"Cover another interior tile")
	expect(not world.greenhouse_covers(plot_key),"A missing roof tile leaves the entire room unsealed")
	var last:Vector2i=GLASS_TILES.back()
	expect(act("build",last,KIND).ok and world.greenhouse_covers(plot_key),"The final tile activates the enclosed greenhouse")
	expect(Music.local_track(world.state,"home",person)=="greenhouse_interior","An enclosed room selects the existing greenhouse BGM")
	expect(World.ORDER_CATALOG.own_greenhouse(world.state.roofs,world.state.crops,owner,world.state.objects),"The order board recognizes the enclosed private crop")
	expect(act("water",PLOT).ok,"Water the out-of-season crop in the finished greenhouse")
	world.step(24.0,true)
	var progress:float=world.state.crops[plot_key].growth
	expect(progress>0 and progress<float(World.CROPS.radish.time),"The crop starts growing in winter after watering")
	expect(act("door",DOOR).ok and not world.greenhouse_covers(plot_key),"Opening the door disables cross-season growth")
	expect(Music.local_track(world.state,"home",person).is_empty(),"Opening the room releases the greenhouse BGM selection")
	expect(not World.ORDER_CATALOG.own_greenhouse(world.state.roofs,world.state.crops,owner,world.state.objects),"The order board cannot mistake an open room for an active greenhouse")
	world.step(24.0,true)
	expect(is_equal_approx(float(world.state.crops[plot_key].growth),progress),"Opening the door pauses the crop without losing progress")
	app.session._send_snapshot(1)
	expect(app.dormant_crop_hint(app.session.snapshot,PLOT).contains("關好門"),"The HUD describes why an open greenhouse crop is dormant")
	expect(app.view.crop_dormant(PLOT,app.session.snapshot.crops[plot_key]),"The rendered crop is also marked dormant")
	await capture("xinghe-roof-open")
	expect(act("door",DOOR).ok and world.greenhouse_covers(plot_key),"Closing the door resumes the greenhouse immediately")
	app.session._send_snapshot(1)
	expect(app.dormant_crop_hint(app.session.snapshot,PLOT).is_empty() and not app.view.crop_dormant(PLOT,app.session.snapshot.crops[plot_key]),"Both client views clear dormancy after closing")
	await capture("xinghe-roof-growing")
	expect(act("remove",PLOT).ok and world.state.crops[plot_key].kind=="radish" and not world.state.roofs.has(plot_key),"Removing the roof leaves the planted crop alone")
	expect(not world.greenhouse_covers(plot_key),"Removing the roof drops the climate benefit")
	var undo:String=world.state.construction.last.get(owner,{}).get("id","")
	var restored:=act(World.UNDO_ACTION,PLOT,undo)
	expect(not undo.is_empty() and restored.ok and world.greenhouse_covers(plot_key),"Undo restores the glass tile directly above the live crop: "+str(restored.get("message","")))
	expect(act("remove",BOUNDARY[1]).ok and not world.greenhouse_covers(plot_key),"A gap in the side of the greenhouse also breaks the enclosure")
	expect(act("build",BOUNDARY[1],"window").ok and world.greenhouse_covers(plot_key),"Rebuilding the window seals the greenhouse again")
	var blueprint:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,2)),"星禾的溫室頂",World.BUILD,World.NAMES)
	expect(blueprint.ok and blueprint.blueprint.pieces.size()==4,"Blueprint capture recognizes all four new roof tiles")
	var pane:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(last,Vector2i.ONE),"單格銅框玻璃",World.BUILD,World.NAMES)
	expect(pane.ok and act("remove",last).ok,"Keep a single pane pattern and reopen one ceiling tile")
	if pane.ok:
		var quote:=world.quote_blueprint(owner,pane.blueprint,last,0)
		if quote.ok:
			var result:=world.apply_blueprint(owner,"4".repeat(32),pane.blueprint,last,0,quote.hash)
			expect(result.ok and world.greenhouse_covers(plot_key),"The blueprint actually replaces the pane and reseals the room")
		else:expect(false,"The roof blueprint can be built without a wood floor: "+str(quote.get("message","")))
	world.step(90.0,true)
	expect(act("harvest",PLOT).ok and person.get("greenhouse_cross_season_crop")=="radish","A winter harvest qualifies for the existing cross-season story")
	expect(act("hoe",LEGACY_PLOT).ok and act("build",LEGACY_PLOT,Glass.LEGACY_ROOF).ok and world.greenhouse_covers(World.key(LEGACY_PLOT)),"Earlier standalone greenhouse glass still works")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.greenhouse_covers(plot_key),"A real save reloads the perimeter, four tiles, and the room's active state")
	set_pos(person,Vector2(42.5,33.5))
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(41.5,34.5)*32-Vector2(root.size)/4.0
	await capture("xinghe-roof-built")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XINGHE_GREENHOUSE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
