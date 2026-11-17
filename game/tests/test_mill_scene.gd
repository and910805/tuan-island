extends "res://tests/test_bakery_visual.gd"
## Extends the labelled seeded bakery UI fixture. Actual local Session queue,
## claim and automatic-buffer actions; sampled native frames, NOT human/video/network.
const View=preload("res://scripts/world_view.gd")
class MillCanvas extends View:
	var device:Dictionary={}
	func _draw()->void:
		draw_rect(Rect2(0,0,96,96),Color("9ba975"))
		object_sprite(Vector2(32,40),"mill",device)
var surface:SubViewport
var mill_canvas:MillCanvas
var extra_done:=false
func mill_pixels(device:Dictionary,now:float,t:float,quiet:bool)->Image:
	mill_canvas.device=device.duplicate(true)
	mill_canvas.data={"time":now}
	mill_canvas.elapsed=t
	mill_canvas.reduced_motion=quiet
	mill_canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return surface.get_texture().get_image()
func current_mill()->Dictionary:
	return app.session.snapshot.objects[World.key(MILL)].duplicate(true)
func publish_snapshot()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	app.toast.hide()
	await settle()
func scene_frame(name:String,t:float,quiet:bool)->void:
	app.view.elapsed=t;app.view.reduced_motion=quiet
	app.view._process(0.0)
	await super.shot(name)
	var viewport:=Rect2(Vector2.ZERO,Vector2(root.size)/app.view.view_zoom())
	var foot:Vector2=app.view.screen(app.view.display_positions[app.view.player_id])
	var body:=Rect2(foot-Vector2(15,44),Vector2(30,48))
	expect(not app.view.label_avoid_rects.is_empty(),"native visible HUD is wired to label exclusions")
	var focused:=false
	for placement in app.view.world_label_placements(viewport):
		if placement.active:
			focused=true
			expect(viewport.encloses(placement.rect),"native focused label remains inside viewport")
			expect(not body.intersects(placement.rect),"native focused label avoids player body")
			var mill_rect:=Rect2(app.view.screen(Vector2(MILL))+Vector2(0,-24),Vector2(34,56))
			expect(not mill_rect.intersects(placement.rect),"native focused label keeps mill and progress visible")
			for hud_rect in app.view.label_avoid_rects:
				var region:=Rect2(hud_rect.position/app.view.view_zoom(),hud_rect.size/app.view.view_zoom())
				expect(not region.intersects(placement.rect),"native focused label avoids visible HUD")
	expect(focused,"native mill keeps its interaction prompt")
func shot(name:String)->void:
	await super.shot(name)
	if name!="bakery-world" or extra_done:return
	extra_done=true
	surface=SubViewport.new();surface.size=Vector2i(96,96)
	surface.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	mill_canvas=MillCanvas.new();surface.add_child(mill_canvas)
	mill_canvas.set_process(false)
	var idle:=current_mill()
	var idle_a:=await mill_pixels(idle,float(world.state.time),0.0,false)
	var idle_b:=await mill_pixels(idle,float(world.state.time),0.45,false)
	expect(idle_a.get_data()==idle_b.get_data(),"idle mill has no phantom work animation")
	app.session.perform("queue_processing",MILL,"flour")
	expect(not world.state.objects[World.key(MILL)].get("processing",{}).get("active",{}).is_empty(),"real Session enqueues flour")
	expect(world.step(30.0,true),"explicit 30 simulated world seconds")
	await publish_snapshot()
	var active:=current_mill()
	var world_before:=JSON.stringify(world.state)
	var work_a:=await mill_pixels(active,float(world.state.time),0.05,false)
	var work_b:=await mill_pixels(active,float(world.state.time),0.45,false)
	expect(work_a.get_data()!=work_b.get_data(),"actual active mill changes native pixels with presentation time")
	var quiet_a:=await mill_pixels(active,float(world.state.time),0.05,true)
	var quiet_b:=await mill_pixels(active,float(world.state.time),0.45,true)
	expect(quiet_a.get_data()==quiet_b.get_data(),"reduced motion work state stays pixel-static")
	expect(quiet_a.get_data()!=idle_a.get_data(),"reduced motion still distinguishes work from idle")
	for i in 8:await scene_frame("mill-working-%02d"%i,float(i)*0.2,false)
	await scene_frame("mill-reduced",0.45,true)
	expect(JSON.stringify(world.state)==world_before,"presentation samples never mutate authoritative world")
	expect(world.step(30.0,true),"finish flour through actual World.step")
	await publish_snapshot()
	var ready:=current_mill()
	var ready_a:=await mill_pixels(ready,float(world.state.time),0.0,false)
	var ready_b:=await mill_pixels(ready,float(world.state.time),0.45,false)
	expect(ready_a.get_data()==ready_b.get_data(),"finished manual work stops processing animation")
	expect(ready_a.get_data()!=idle_a.get_data(),"ready manual output is visually distinguishable")
	var feed_ready:=ready.duplicate(true)
	feed_ready.processing.ready[0].kind="feed"
	var feed_frame:=await mill_pixels(feed_ready,float(world.state.time),0.0,true)
	expect(feed_frame.get_data()!=ready_a.get_data(),"Ready feed uses different pixels from ready flour")
	await scene_frame("mill-ready",0.45,false)
	app.session.perform("claim_processing",MILL,"")
	app.session.perform("feed_processing",MILL,"")
	app.session.perform("toggle_auto_processing",MILL,"")
	expect(world.step(2.0,true),"automatic mill begins on logistics tick")
	await publish_snapshot()
	var automatic:=current_mill()
	expect(automatic.get("job",{}).get("auto",false),"real automatic flour job exists")
	var auto_a:=await mill_pixels(automatic,float(world.state.time),0.05,false)
	var auto_b:=await mill_pixels(automatic,float(world.state.time),0.45,false)
	expect(auto_a.get_data()!=auto_b.get_data(),"automatic active mill changes native pixels")
	await scene_frame("mill-automatic",0.45,false)
	for size in [Vector2i(1280,800),Vector2i(1024,640)]:
		root.size=size;await settle()
		preload("res://scripts/public_kitchen_ui.gd").open(app,"kitchen")
		await settle();bounds()
		var found:=false
		for label in app.modal.find_children("*","Label",true,false):
			if label.is_visible_in_tree() and label.text.contains("磨坊"):
				found=true
				expect(app.modal.get_global_rect().encloses(label.get_global_rect()),"mill next step fits at "+str(size))
		expect(found,"opened kitchen shows mill next step at "+str(size))
		await super.shot("mill-story-%d"%size.x)
		app._close_modal()
	root.size=Vector2i(1280,800);await settle()
	surface.queue_free();await settle()
