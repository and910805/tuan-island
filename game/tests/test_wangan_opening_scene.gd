extends SceneTree
## 望安開場 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/望安開場預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
##
## Art: no new PNGs. The arrival card uses the existing paper panel style and
## Xiaoli's existing portrait frame; the plot marker (corner stakes, twine, soil
## hint) is program-drawn by wangan_opening_ui.draw_plot and has no time input,
## so it is identical with or without reduced motion. No boat sprite exists in
## the project, so the card has no boat picture (text only).
##
## PRESET / FIXTURE (not human play):
##  * each world is an isolated host save in %TEMP% (deleted at the end);
##    app.village_art_preview=true; app processing / Session physics off;
##  * the local player is teleported by writing x/y (VIEW_SPOT for the frames,
##    WORK_SPOT for the farm actions); the crop grows with World.step;
##  * the occupied cases add a fake neighbour with World.add_player, give them
##    wood/stone by writing their inventory, and fill plot cells with their
##    World.act hoe / build floor actions;
##  * the shipment is sent with session.perform("ship", …) like the shipping panel.
## REALLY EXERCISED: Session.host -> main._entered -> arrival card; my farm
##  actions through session.perform (hoe / seed / water / harvest / ship).
## SHOTS per size (11): arrival, plot_empty, plot_tilled, plot_sown, plot_watered,
##  plot_mature, plot_harvested, after_ship, occupied_partial, occupied_full,
##  hud_tracker (crop of the tracker during the find step).
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
## Below the plot (plot rows 26-27): with the player-centred camera the whole plot
## and its tag sit between the tracker (left) and the weather badge (right).
const VIEW_SPOT:=Vector2(46.5,30.5)
const WORK_SPOT:=Vector2(45.5,28.5)
const WORK_CELL:=Vector2i(45,27)
var app
var w
var me:=""
var id:=""
var path:=""
var paths:Array[String]=[]
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var neighbour:=""

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	for item in paths:
		for suffix in ["",".bak",".tmp",".writer-lock"]:
			if FileAccess.file_exists(item+suffix):DirAccess.remove_absolute(item+suffix)
	print("WANGAN_OPENING_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func person()->Dictionary:
	return w.state.players[me]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	if v.goals.has(id):
		v.starts[id]=v.goals[id]
		v.display_positions[id]=v.goals[id]
	v.facings[id]=Vector2i.UP
	v._process(0.0)
	await settle()

func perform(action:String,cell:Vector2i,extra:String="")->void:
	app.session.rates[1].clear()
	app.session.perform(action,cell,extra)
	await refresh()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func shot(step:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("WANGAN_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func plot_world_rect()->Rect2:
	var cells:=Opening.plot_rect()
	return Rect2(app.view.screen(Vector2(cells.position)),Vector2(cells.size)*32.0)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func hud_panels()->Array:
	var result:=[]
	var area:=Vector2(root.size).x*Vector2(root.size).y
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		if c.size.x*c.size.y>area*0.5:continue
		result.append({"name":str(c.name),"rect":c.get_global_rect()})
	return result

## Stake pixels at the four plot corners (exact program colours).
func stake_pixels(image:Image)->int:
	var r:=plot_world_rect().grow(-1.0)
	var count:=0
	for corner in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
		var box:=view_to_pixels(Rect2((corner as Vector2).round()+Vector2(-2,-9),Vector2(4,11)))
		for x in range(int(box.position.x),int(box.end.x)):
			for y in range(int(box.position.y),int(box.end.y)):
				if x<0 or y<0 or x>=image.get_width() or y>=image.get_height():continue
				var c:=image.get_pixel(x,y)
				if absf(c.r-WanganUI.STAKE.r)+absf(c.g-WanganUI.STAKE.g)+absf(c.b-WanganUI.STAKE.b)<0.06:count+=1
	return count

func marker_ok(image:Image,label:String,shown:bool)->void:
	var list:=placements()
	var tag_entry:={}
	for entry:Dictionary in list:
		if str(entry.id)==Opening.PLOT_LABEL_ID:tag_entry=entry
	var stakes:=stake_pixels(image) if image!=null else 0
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	if not shown:
		check(not Opening.marker_shown(app.session.snapshot,id),"Marker off in the snapshot (%s)"%label)
		check(tag_entry.is_empty(),"No 「小栗留的田」 tag (%s)"%label)
		# Floor planks share a few stake-brown pixels; a drawn marker has >= 40.
		check(stakes<20,"No plot stakes drawn (%s): %d px"%[label,stakes])
		return
	check(not tag_entry.is_empty() and str(tag_entry.title)=="小栗留的田","Tag 「小栗留的田」 placed (%s)"%label)
	check(stakes>=40,"Corner stakes drawn (%s): %d px"%[label,stakes])
	var plot_px:=view_to_pixels(plot_world_rect())
	check(screen_rect.encloses(plot_px),"Whole plot on screen (%s) %s"%[label,str(plot_px)])
	for panel:Dictionary in hud_panels():
		check(not plot_px.grow(12).intersects(panel.rect),"Plot clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(plot_px),str(panel.rect)])
		if not tag_entry.is_empty():check(not view_to_pixels(tag_entry.rect).intersects(panel.rect),"Tag clear of HUD %s (%s)"%[panel.name,label])
	if not tag_entry.is_empty():
		var tag_rect:Rect2=tag_entry.rect
		check(screen_rect.encloses(view_to_pixels(tag_rect)),"Tag on screen (%s)"%label)
		check(not tag_rect.intersects(plot_world_rect().grow(-2.0)),"Tag does not cover the plot cells or crops (%s) %s"%[label,str(tag_rect)])
		for entry:Dictionary in list:
			if entry!=tag_entry:check(not tag_rect.intersects(entry.rect),"Tag does not overlap 「%s」 (%s)"%[entry.title,label])
		var foot:Vector2=app.view.screen(app.view.display_positions.get(id,Vector2(person().x,person().y)))
		check(not tag_rect.intersects(Rect2(foot+Vector2(-16,-48),Vector2(32,48))),"Tag clear of my body (%s)"%label)

func open_world()->bool:
	path=OS.get_environment("TEMP").path_join("wangan-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	paths.append(path)
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"望安旅人",path)!=OK:
		check(false,"Host starts")
		return false
	await settle()
	w=app.session.world;me=app.session.profile.token;id=app.session.own_id
	if not app.playing:app.playing=true
	app._update_world_label_obstacles()
	await refresh()
	return true

func close_world()->void:
	app.session.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	await process_frame

func step_id()->String:
	return str(Chapter.first_crop_step(app.session.snapshot,id).get("id",""))

func size_flow(size:Vector2i)->void:
	root.size=size
	tag="%dx%d"%[size.x,size.y]
	if not await open_world():return
	# Arrival card over the landing.
	var card:=WanganUI.card(app)
	check(card!=null and card.is_visible_in_tree(),"Arrival card shown (%s)"%tag)
	await shot("arrival")
	if card!=null:
		for panel:Dictionary in hud_panels():
			if panel.name!=WanganUI.CARD:check(not card.get_global_rect().intersects(panel.rect),"Card clear of HUD %s (%s)"%[panel.name,tag])
	var image:=await shot("hud_tracker_full")
	if image!=null:
		var tracker_rect:=Rect2i(app.preview_tracker.get_global_rect().grow(6.0))
		tracker_rect=tracker_rect.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		var crop:=image.get_region(tracker_rect)
		var file:=output.path_join("%s_hud_tracker.png"%tag)
		check(crop.save_png(file)==OK,"tracker crop saved (%s)"%tag)
		DirAccess.remove_absolute(output.path_join("%s_hud_tracker_full.png"%tag))
	WanganUI.dismiss(app)
	# Plot marker through the first crop.
	await stand(VIEW_SPOT)
	check(step_id()=="till","At the view spot the step is till (%s): %s"%[tag,step_id()])
	marker_ok(await shot("plot_empty"),"empty "+tag,true)
	await stand(WORK_SPOT)
	await perform("hoe",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="sow","Tilled (%s)"%tag)
	marker_ok(await shot("plot_tilled"),"tilled "+tag,true)
	await stand(WORK_SPOT)
	await perform("seed",WORK_CELL,"radish")
	await stand(VIEW_SPOT)
	check(step_id()=="water","Sown (%s)"%tag)
	marker_ok(await shot("plot_sown"),"sown "+tag,true)
	await stand(WORK_SPOT)
	await perform("water",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="wait","Watered (%s)"%tag)
	marker_ok(await shot("plot_watered"),"watered "+tag,true)
	for i in 30:
		if float(w.state.crops[World.key(WORK_CELL)].growth)>=float(World.CROPS.radish.time):break
		w.step(5.0,true)
	await refresh()
	check(step_id()=="harvest","Mature (%s)"%tag)
	marker_ok(await shot("plot_mature"),"mature "+tag,true)
	await stand(WORK_SPOT)
	await perform("harvest",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="ship","Harvested (%s)"%tag)
	marker_ok(await shot("plot_harvested"),"harvested "+tag,true)
	await stand(Vector2(42.5,32.5))
	await perform("ship",World.SHIPPING.cell_for(w.state),JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)]))
	check(bool(w.state.chapter_one.shipped),"Shipped (%s)"%tag)
	await stand(VIEW_SPOT)
	marker_ok(await shot("after_ship"),"after ship "+tag,false)
	await close_world()
	# Occupied plot (another player's soil and floors).
	if not await open_world():return
	WanganUI.dismiss(app)
	neighbour="wangan-scene-neighbour"
	w.add_player(neighbour,"鄰居")
	var other:Dictionary=w.state.players[neighbour]
	other.inventory.wood=100;other.inventory.stone=100
	other.x=46.5;other.y=28.5
	var cells:=Chapter.STARTER_PLOT
	for i in 3:
		var result:Dictionary=w.act(neighbour,"scene-occupy-%d"%i,"hoe" if i%2==0 else "build",cells[i],"" if i%2==0 else "floor")
		check(result.ok,"Neighbour occupies %s (%s)"%[str(cells[i]),tag])
	other.x=50.5;other.y=33.5
	await stand(VIEW_SPOT)
	marker_ok(await shot("occupied_partial"),"occupied partial "+tag,true)
	other.x=46.5;other.y=28.5
	for i in range(3,cells.size()):
		var result:Dictionary=w.act(neighbour,"scene-occupy-%d"%i,"hoe" if i%2==0 else "build",cells[i],"" if i%2==0 else "floor")
		check(result.ok,"Neighbour occupies %s (%s)"%[str(cells[i]),tag])
	other.x=50.5;other.y=33.5
	await stand(VIEW_SPOT)
	check(Chapter.first_crop_step(app.session.snapshot,id).get("cell")==Chapter.NO_PLOT_CELL,"Fully occupied: no plot target (%s)"%tag)
	marker_ok(await shot("occupied_full"),"occupied full "+tag,false)
	await close_world()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/望安開場預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		await size_flow(size)
		print("NOTE size %dx%d done at %.1f s"%[size.x,size.y,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=22,"11 screenshots per size (%d)"%shots)
	finish()
