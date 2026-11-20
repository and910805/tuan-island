extends "res://tests/test_tool_action_session.gd"
## Native observer rendering over real local WebSocket RPC, one process/three peers.
const View=preload("res://scripts/world_view.gd")
var resource_tree:=Vector2i.ZERO
var resource_rock:=Vector2i.ZERO
var observer
var capture_dir:=""

func seed_fixture()->bool:
	if not super.seed_fixture():return false
	var world:=World.new()
	if not world.load_world(save_path):return false
	var found:=false
	for y in range(24,42):
		for x in range(28,54):
			var stone:=Vector2i(x,y)
			var tree:=stone+Vector2i(2,0)
			if World.base_resource(stone)!="rock" or world.protected(stone) or world.protected(tree):continue
			if world.resource(tree)!="" or not world.is_land(tree) or world.state.objects.has(World.key(tree)):continue
			if not world.can_stand(Vector2(stone)+Vector2(0.5,1.5)) or not world.can_stand(Vector2(stone)+Vector2(0.5,2.5)):continue
			resource_rock=stone
			resource_tree=tree
			found=true
			break
		if found:break
	if not found:return false
	world.state.forest[World.key(resource_tree)]={"owner":ALPHA,"mature":true,"growth":World.TREE_TIME}
	for pair in [[ALPHA,1.5],[BETA,2.5]]:
		world.state.players[pair[0]].x=resource_rock.x+0.5
		world.state.players[pair[0]].y=resource_rock.y+pair[1]
	return world.save()

func scenario()->bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):capture_dir=arg.trim_prefix("--qa-dir=")
	if capture_dir.is_empty():return false
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size=Vector2i(1024,640)
	expect(seed_fixture(),"Resource fixture saved using real schema and natural rock")
	var port:=start_server()
	if port==0:return false
	alpha=await join("採集者",ALPHA,port)
	beta=await join("旁觀島民",BETA,port)
	gamma=await join("其他區域",GAMMA,port)
	if not (joined(alpha) and joined(beta) and joined(gamma)):return false
	observer=View.new()
	observer.village_art_preview=true
	root.add_child(observer)
	beta.session.changed.connect(observer.update_snapshot)
	observer.update_snapshot(beta.session.snapshot,beta.session.own_id)
	await settle(live())
	for spec in [["axe",resource_tree,3,"wood",6],["pick",resource_rock,2,"stone",5]]:
		var tool:String=spec[0]
		var cell:Vector2i=spec[1]
		var key:=World.key(cell)
		var amount_before:int=server.world.state.players[ALPHA].inventory.get(spec[3],0)
		for hit in range(int(spec[2])-1):
			var partial:=await act(alpha,tool,cell)
			expect(partial.ok,"Non-final hit accepted via WebSocket")
			expect(not observer.tool_feedback.finishes.has(key),"Partial hit does not fell resource on observer")
		frozen_ms=Time.get_ticks_msec()
		alpha.session.perform(tool,cell)
		var seen:=await wait_until(func():return observer.tool_feedback.finishes.has(key),4.0)
		expect(seen,"Observer receives authoritative final-hit animation: "+tool)
		if not seen:return false
		expect(server.world.state.removed.has(key),"Server has really removed the resource")
		expect(int(server.world.state.players[ALPHA].inventory.get(spec[3],0))==amount_before,"Inventory has not credited a ground drop")
		var drops:Dictionary=server.world.region_snapshot("home").get("gather_drops",{})
		expect(int(drops.get(key,{}).get("items",{}).get(spec[3],0))==int(spec[4]),"Authoritative ground yield unchanged")
		expect(alpha.feedback.finishes.has(key),"Actor also observes final-hit animation")
		expect(gamma.feedback.finishes.is_empty(),"Other region receives no resource-ending animation")
		var began:float=observer.tool_feedback.finishes[key].started
		var recorded:Array=[]
		for frame in 24:
			observer.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var name:="%s_%02d.png"%[tool,frame]
			expect(root.get_texture().get_image().save_png(capture_dir.path_join(name))==OK,"Capture remote observer")
			recorded.append({"file":name,"elapsed":observer.elapsed-began})
			if frame==5:
				var placements:Array=observer.world_label_placements(Rect2(Vector2.ZERO,root.size/observer.view_zoom()))
				for entry:Dictionary in placements:
					if not entry.active:continue
					for body:Rect2 in observer.character_label_obstacles:
						expect(not entry.rect.intersects(body),"Native focused prompt keeps residents and both players visible")
			await create_timer(0.025).timeout
		var record:=FileAccess.open(capture_dir.path_join(tool+"-frames.json"),FileAccess.WRITE)
		record.store_string(JSON.stringify(recorded,"\t"))
		expect(observer.tool_feedback.resource_finish(cell,observer.elapsed,false).is_empty(),"Remote animation expires without replay")
		# Keep the event in the server TTL window while the observer reconnects.
		await leave(beta)
		clients.erase(beta)
		await wait_until(func():return not server.peers.values().has(BETA),4.0)
		beta=await join("旁觀島民",BETA,port)
		expect(joined(beta) and not beta.first_events.is_empty(),"Reconnect baseline contains retained successful tool event")
		observer.tool_feedback.reset()
		observer.update_snapshot(beta.session.snapshot,beta.session.own_id)
		beta.session.changed.connect(observer.update_snapshot)
		expect(observer.tool_feedback.finishes.is_empty() and beta.feedback.finishes.is_empty(),"Reconnect never replays an old felling/breaking animation")
		frozen_ms=-1
	print("RESOURCE_FINISH_SESSION native_observer=true machine=single process=single transport=websocket clients=3")
	return true
