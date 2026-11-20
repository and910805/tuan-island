extends SceneTree

const World=preload("res://scripts/world.gd")
const TOKEN:="woodland-forester"
const OUTSIDE:=Vector2i(33,28)
var checks:=0
var failures:=0
var action_id:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run()->void:
	var path:="user://woodland-stock-%d.json"%OS.get_process_id()
	var world:=World.new()
	world.save_path=path
	world.add_player(TOKEN,"林地旅人")
	var grove:=grove_trees(world)
	expect(grove.size()>=7,"The designated forest has at least seven accessible natural trees")
	if grove.size()>=7:await check_cycle(world,grove.slice(0,7))
	for suffix:String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WOODLAND_STOCK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func grove_trees(world:World)->Array[Vector2i]:
	var tiles:Array[Vector2i]=[]
	var rect:=World.WOODLAND.GROVE
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var tile:=Vector2i(x,y)
			if world.resource(tile)=="tree" and not world.protected(tile) and not world.water(tile) and not approach(world,tile).is_equal_approx(Vector2.INF):tiles.append(tile)
	return tiles

func approach(world:World,tile:Vector2i)->Vector2:
	for offset:Vector2i in World.INDUSTRY.NEIGHBORS:
		var stand_at:=Vector2(tile+offset)+Vector2(0.5,0.5)
		if world.can_stand(stand_at):return stand_at
	return Vector2.INF

func stand(world:World,point:Vector2)->void:
	var resident:Dictionary=world.state.players[TOKEN]
	resident.x=point.x
	resident.y=point.y

func act(world:World,verb:String,target:Vector2i,extra:String="")->Dictionary:
	action_id+=1
	return world.act(TOKEN,"woodland-%d"%action_id,verb,target,extra)

func cut_and_collect(world:World,tile:Vector2i)->void:
	stand(world,approach(world,tile))
	for _hit in range(3):expect(act(world,"axe",tile).ok,"Axing %s succeeds"%tile)
	stand(world,Vector2(tile)+Vector2(0.5,0.5))
	expect(world.step(World.GATHER_DROP_DELAY+0.1,true),"Collect the landed materials")
	expect(not world.state.get("gather_drops",{}).get("home",{}).has(World.key(tile)),"The bundle was picked up")

func check_cycle(world:World,grove:Array)->void:
	for tile:Vector2i in grove:cut_and_collect(world,tile)
	var restored_count:=func(w:World)->int:
		return grove.filter(func(tile):return w.resource(tile)=="tree").size()
	expect(grove.all(func(tile):return world.resource(tile)=="stump"),"All seven felled trees leave saved stumps")
	await capture_preview(world,grove[0])
	cut_and_collect(world,OUTSIDE)
	expect(world.resource(OUTSIDE).is_empty(),"The residential site has no automatically regrowing stump")
	var cleared:Vector2i=grove[0]
	stand(world,Vector2(cleared)+Vector2(0.5,0.5))
	expect(not act(world,"hoe",cleared).ok,"Unremoved stump cannot become farmland")
	expect(act(world,"remove",cleared).ok and world.resource(cleared).is_empty(),"The player can permanently clear the stump")
	expect(act(world,"hoe",cleared).ok and world.state.crops.has(World.key(cleared)),"The cleared tile becomes a real farm plot")
	var fence_time:=World.WEATHER.DAY_SECONDS*3.0
	expect(world.step(fence_time-float(world.state.time)-0.1,true),"Advance to just before the three-day boundary")
	expect(restored_count.call(world)==0,"Trees never sneak back before the boundary")
	var occupied:Vector2i=grove[1]
	stand(world,Vector2(occupied)+Vector2(0.5,0.5))
	expect(world.step(0.2,true),"Advance beyond the first regrowth boundary")
	expect(restored_count.call(world)==4 and world.resource(occupied)=="stump","Exactly four trees regrow and none overlaps a player")
	var reopened:=World.new()
	if not reopened.load_world(world.save_path) or reopened.recovered_from_backup:
		expect(false,"Stock loads from primary save")
		return
	expect(int(reopened.state[World.WOODLAND.KEY].grown)==4,"The cycle budget persists across restart")
	reopened.add_player(TOKEN,"林地旅人")
	stand(reopened,approach(reopened,occupied))
	expect(reopened.step(10.0,true) and restored_count.call(reopened)==4,"Reopening does not refill the same cycle")
	expect(reopened.step(fence_time*2-float(reopened.state.time)+0.1,true),"Advance through the second cycle")
	expect(restored_count.call(reopened)==6 and reopened.resource(occupied)=="tree","Both waiting trees regrow at the second boundary")
	expect(reopened.resource(cleared).is_empty() and reopened.state.crops.has(World.key(cleared)) and reopened.resource(OUTSIDE).is_empty(),"Neither a cleared farm nor the residential site grows a new wild tree")
	expect(not reopened.region_snapshot("lanyang").has(World.WOODLAND.KEY),"Other regions do not receive the grove stock")

func capture_preview(world:World,tile:Vector2i)->void:
	if DisplayServer.get_name()=="headless":return
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--woodland-preview="):continue
		var app=preload("res://main.tscn").instantiate()
		app.village_art_preview=true
		root.add_child(app)
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.size=Vector2i(1024,640)
		app.set_process(false)
		app.session.set_physics_process(false)
		stand(world,approach(world,tile))
		app.session.snapshot=world.region_snapshot("home")
		app.session.own_id=TOKEN
		app.playing=true
		app.menu.hide()
		app.hud.show()
		app._state_changed(app.session.snapshot,TOKEN)
		app.target=tile
		app.view.target=tile
		app.view.show_target=true
		app.view.selected="remove"
		app._select_tool("remove")
		app._refresh_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--woodland-preview="))==OK,"Capture the woodland stump and clearance hint")
		app.queue_free()
		await process_frame
