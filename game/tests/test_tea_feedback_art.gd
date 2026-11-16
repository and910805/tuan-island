extends SceneTree

const Art=preload("res://scripts/tea_ceramics_art.gd")
const View=preload("res://scripts/world_view.gd")

class Workbench extends Node2D:
	var region:="maokong"
	var site:="roast"
	var record:Dictionary={}
	var now:=0.0
	var elapsed:=0.0
	var reduced:=false

	func _draw()->void:
		if not site in View.tea_points(region).values():return
		var at:=Vector2(56,64)
		Art.draw_site(self,at,site)
		Art.draw_feedback(self,at,site,record,now,elapsed,reduced)

var viewport:SubViewport
var workbench:=Workbench.new()
var checks:=0
var failures:=0
var capture_dir:=""

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func frame(now:float,elapsed:float,reduced:=false)->Image:
	workbench.now=now
	workbench.elapsed=elapsed
	workbench.reduced=reduced
	workbench.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run()->void:
	if DisplayServer.get_name()=="headless":
		push_error("Tea feedback art test requires native rendering")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-frames="):capture_dir=arg.trim_prefix("--qa-frames=")
	viewport=SubViewport.new()
	viewport.size=Vector2i(144,108)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	workbench.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(workbench)
	for site in ["roast","kiln","pack"]:
		workbench.site=site
		workbench.region="yingge" if site=="kiln" else "maokong"
		workbench.record={}
		var idle:=await frame(1,0.15)
		expect(idle.get_data()==(await frame(8,0.65)).get_data(),"Empty "+site+" has no animation")
		match site:
			"roast":workbench.record={"roast":{"style":"light","ready":10.0}}
			"kiln":workbench.record={"kiln":{"ready":10.0}}
			"pack":workbench.record={"outbound":{"wrap":"fiber","ready":10.0},"returning":{"count":1,"ready":10.0}}
		var active:=await frame(8,0.15)
		var later:=await frame(8,0.65)
		if site!="pack":expect(active.get_data()!=later.get_data(),site+" live processing animates")
		var reduced:=await frame(8,0.15,true)
		expect(reduced.get_data()==(await frame(8,0.65,true)).get_data(),site+" reduced motion is stable")
		expect(reduced.get_data()!=idle.get_data(),site+" active phase remains visible with reduced motion")
		var ready:=await frame(10,0.15)
		expect(ready.get_data()!=active.get_data() and ready.get_data()!=idle.get_data(),site+" switches to finished at deadline")
		expect(ready.get_data()==(await frame(15,0.65)).get_data(),site+" completed phase has no processing animation")
		if not capture_dir.is_empty():
			for mode in ["normal","reduced"]:
				var path:=capture_dir.path_join(site).path_join(mode)
				expect(DirAccess.make_dir_recursive_absolute(path)==OK,"Create "+path)
				for index in range(24):
					var rendered:=await frame(8.0+index*0.15,index*0.08,mode=="reduced")
					expect(rendered.save_png(path.path_join("%03d.png"%index))==OK,"Save "+site+" "+mode+" frame")
		workbench.region="home"
		var away:=await frame(10,0.15)
		expect(away.get_used_rect()==Rect2i(),"Changing region clears "+site+" visuals even with saved job")
	viewport.queue_free()
	print("TEA_FEEDBACK_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
