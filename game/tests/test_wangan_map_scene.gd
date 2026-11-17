extends SceneTree
## 旅圖「澎湖・望安」native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/望安旅圖預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## shape as test_showcase_scene.gd.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic written directly (picnic false only for the local-map
##    caption frame shown before the first picnic); state.dock_stage written 0;
##  * the player is placed by writing region / x / y next to the ferry gate (home) or the
##    Lanyang exit; travel_book reset to Transit.fresh();
##  * the four flower/salt map crops set the map control's flower_open / salt_open meta.
## REALLY EXERCISED: app._travel_menu() (same path as the M key) builds the travel modal
##  with the real taiwan_map.gd control; TravelDepart is pressed to sail home -> Lanyang
##  so the Lanyang frames come from a real travel action; app._map_menu() opens the local map.
## SHOTS per size (10): travel_home, map_home (crop), map_home_<flowers>_<salt> (4 crops),
##  travel_lanyang, map_lanyang (crop), local_map_home_before_picnic, local_map_home.
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Map=preload("res://scripts/taiwan_map.gd")
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("WANGAN_MAP_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:(ribbon as CanvasItem).hide()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("WANGAN_MAP_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

func shot(step:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	hide_toast()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step)
	return image

func crop(image:Image,rect:Rect2,step:String)->void:
	if image==null:return
	var box:=Rect2i(rect.grow(4)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	check(box.size.x>0 and box.size.y>0,"Crop box inside image (%s_%s)"%[tag,step])
	if box.size.x>0 and box.size.y>0:save_image(image.get_region(box),step)

func map_control()->Control:
	if not is_instance_valid(app.modal):return null
	for node in app.modal.find_children("*","Control",true,false):
		if node.get_script()==Map:return node
	return null

func place(region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[id]
	p.region=region;p.x=at.x;p.y=at.y
	app.session._send_snapshot(1)
	app.view.update_snapshot(app.session.snapshot,app.session.own_id)
	await settle()

func modal_fits(label:String)->void:
	check(is_instance_valid(app.modal),"Modal open (%s)"%label)
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Modal fits the viewport (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the modal 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"Button whole inside the modal 「%s」 (%s)"%[b.text,label])

## Map: whole control visible, home label/caption/inset clear of every other label rect.
func map_ok(map:Control,label:String)->void:
	check(map!=null,"Map in modal (%s)"%label)
	if map==null:return
	check(root.get_visible_rect().encloses(map.get_global_rect()) and app.modal.get_global_rect().grow(0.5).encloses(map.get_global_rect()),"Map whole on screen (%s) %s"%[label,str(map.get_global_rect())])
	var rects:Dictionary=map.layout_rects()
	for own in ["home","home_caption","home_icon","lanyang"]:
		check(Rect2(Vector2.ZERO,map.size).encloses(rects[own]),"%s inside map (%s)"%[own,label])
		for other in rects:
			if other==own or (own.begins_with("home") and str(other).begins_with("home")):continue
			check(not (rects[own] as Rect2).intersects(rects[other]),"%s clear of %s (%s)"%[own,other,label])

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.picnic=true;w.state.board=true;w.state.dock_stage=0  # PRESET
	w.state.players[id].travel_book=Transit.fresh()  # PRESET
	await place("home",Vector2(47.5,31.5))
	app._travel_menu();await settle()
	modal_fits("travel home "+tag)
	var map:=map_control()
	map_ok(map,"travel home "+tag)
	var image:Image=await shot("travel_home")
	if map!=null:
		crop(image,map.get_global_rect(),"map_home")
		for flowers in [false,true]:
			for salt in [false,true]:
				map.set_meta("flower_open",flowers);map.set_meta("salt_open",salt);map.queue_redraw()
				map_ok(map,"home flowers=%s salt=%s %s"%[flowers,salt,tag])
				var state_image:Image=await shot("travel_home_state")
				shots-=1
				crop(state_image,map.get_global_rect(),"map_home_%s_%s"%["flowers" if flowers else "noflowers","salt" if salt else "nosalt"])
		DirAccess.remove_absolute(output.path_join("%s_travel_home_state.png"%tag))
	var depart:=app.modal.find_child("TravelDepart",true,false) as Button
	check(depart!=null and not depart.disabled and depart.text=="搭乘出發  →","Depart ready (%s)"%tag)
	if depart!=null and not depart.disabled:
		app.session.rates[1].clear()
		await create_timer(0.12).timeout
		depart.pressed.emit()
		await settle()
	check(str(w.state.players[id].region)=="lanyang","Sailed to Lanyang (%s)"%tag)
	if is_instance_valid(app.modal):app._close_modal()
	await place("lanyang",Vector2(12.5,20.5))
	app._travel_menu();await settle()
	modal_fits("travel lanyang "+tag)
	map=map_control()
	map_ok(map,"travel lanyang "+tag)
	image=await shot("travel_lanyang")
	if map!=null:crop(image,map.get_global_rect(),"map_lanyang")
	app._close_modal()
	# Local map caption before the first picnic (home), then the general area title.
	w.state.picnic=false  # PRESET
	await place("home",Vector2(47.5,31.5))
	app._map_menu();await settle()
	check(is_instance_valid(app.modal),"Local map open (%s)"%tag)
	await shot("local_map_home_before_picnic")
	app._close_modal()
	var player:Dictionary=w.state.players[id]
	var saved_inventory:Dictionary=player.inventory.duplicate(true)
	for item in player.inventory.keys():
		if str(item).ends_with("_seed"):player.inventory.erase(item)
	var plot:="45,26"
	w.state.crops[plot]={"owner":id,"kind":"","growth":0.0,"wet":false}
	await place("home",Vector2(47.5,31.5))
	app._map_menu();await settle()
	var restock:Dictionary=app.map_view.letter_target(app.session.snapshot,app.session.own_id)
	check(restock.personal and restock.at==Vector2(43.5,29.5),"Map pins Xiaoli when seeds run out (%s)"%tag)
	await shot("local_map_home_restock")
	app._close_modal()
	player.inventory=saved_inventory
	w.state.crops.erase(plot)
	w.state.picnic=true  # PRESET
	await place("home",Vector2(47.5,31.5))
	app._map_menu();await settle()
	await shot("local_map_home")
	app._close_modal()

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/望安旅圖預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("wangan-map-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"望安旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
	check(shots>=20,"10 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
