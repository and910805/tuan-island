extends SceneTree
const World=preload("res://scripts/world.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1024,640)
	var directory:String=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="resource-reaction-qa"
	assert(app.session.host(0,"採集動畫測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	var tree:=Vector2i(38,34)
	world.state.forest[World.key(tree)]={"owner":token,"mature":true,"growth":World.TREE_TIME}
	var rock:=Vector2i(-1,-1)
	for y in range(22,42):
		for x in range(28,55):
			var cell:=Vector2i(x,y)
			if World.base_resource(cell)=="rock" and not World.REGIONS.protected(cell,"home") and world.can_stand(Vector2(cell)+Vector2(0.5,1.5)):
				rock=cell
				break
		if rock.x>=0:break
	assert(rock.x>=0)
	var sequence:=0
	for pair in [["axe",tree,"wood",3],["pick",rock,"stone",2]]:
		var tool:String=pair[0]
		var cell:Vector2i=pair[1]
		person.x=cell.x+0.5
		person.y=cell.y+1.5
		app.session._send_snapshot(1)
		app.view.set_process(true)
		await create_timer(0.3).timeout
		app.view.set_process(false)
		app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
		var camera:Vector2=app.view.camera
		var terrain:Dictionary=world.state.ground.duplicate(true)
		var before:int=person.inventory.get(pair[2],0)
		app.session.rates[1]=[]
		sequence+=1
		app.session._action(1,sequence,tool,cell,"")
		app.session._send_snapshot(1)
		expect(world.state.damage.get(World.key(cell),0)==1,"First hit changes authoritative damage: "+tool)
		var started:float=app.view.elapsed
		var moved:=false
		for frame in 18:
			app.view.elapsed=started+frame*0.04
			var pose:Dictionary=app.view.tool_feedback.resource_pose(cell,tool,app.view.elapsed,app.view.reduced_motion)
			moved=moved or pose.angle!=0.0 or pose.shift!=Vector2.ZERO
			app.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(directory.path_join("%s_%02d.png"%[tool,frame]))==OK,"Capture hit")
		expect(camera==app.view.camera and terrain==world.state.ground,"Resource animation leaves terrain/camera fixed")
		expect(moved!=app.view.reduced_motion,"Resource reaction follows motion preference")
		for hit in range(1,int(pair[3])):
			app.session.rates[1]=[]
			sequence+=1
			app.session._action(1,sequence,tool,cell,"")
		app.session._send_snapshot(1)
		expect(world.state.removed.get(World.key(cell),false),"Final hit removes real resource: "+tool)
		expect(int(person.inventory.get(pair[2],0))==before+(6 if tool=="axe" else 5),"Original yield remains unchanged: "+tool)
		expect(world.can_stand(Vector2(cell)+Vector2(0.5,0.5)),"Cleared resource no longer blocks movement")
		var ended_at:float=app.view.elapsed
		var ending:Dictionary=app.view.tool_feedback.resource_finish(cell,ended_at,app.view.reduced_motion)
		expect(ending.is_empty()==app.view.reduced_motion,"Final-hit art follows motion preference")
		for frame in 24:
			app.view.elapsed=ended_at+frame*0.04
			app.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(directory.path_join("%s_finish_%02d.png"%[tool,frame]))==OK,"Capture final hit")
		expect(app.view.tool_feedback.resource_finish(cell,app.view.elapsed,false).is_empty(),"Final-hit art ends without another snapshot")
		expect(camera==app.view.camera and terrain==world.state.ground,"Final-hit art preserves camera and base terrain")
	print("RESOURCE_REACTION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
