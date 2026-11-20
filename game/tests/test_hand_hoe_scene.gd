extends SceneTree

const World=preload("res://scripts/world.gd")
const FARMER:="hoe-preview-farmer"
const NEIGHBOR:="hoe-preview-neighbor"
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if ok:return
	failures+=1
	push_error(label)

func run()->void:
	var save_path:="user://hand-hoe-scene-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=save_path
	fixture.add_player(FARMER,"島民")
	fixture.add_player(NEIGHBOR,"鄰居")
	var farmer:Dictionary=fixture.state.players[FARMER]
	farmer.inventory.precision_hoe=1
	farmer.inventory.precision_can=1
	farmer.inventory.precision_seed_pouch=1
	farmer.inventory.precision_sickle=1
	fixture.state.chapter_one.shipped=true
	var center:=find_plot(fixture,farmer)
	expect(center.x>=0,"Find native preview terrain")
	if failures>0:
		finish()
		return
	var neighbor_plot:=center+Vector2i.RIGHT
	fixture.state.crops[World.key(neighbor_plot)]={"kind":"radish","growth":0.0,"wet":false,"owner":NEIGHBOR,"owner_water":true}
	expect(fixture.save(),"Save the isolated preview fixture")
	var app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=Vector2i(1024,640)
	app.set_process(false)
	app.session.profile={"token":FARMER}
	var started:bool=app.session.host(0,"島民",save_path,"","127.0.0.1",false,"enet",true)==OK
	expect(started,"Open the fixture in a real local game session")
	if started:
		app.session.set_physics_process(false)
		for _frame in 3:await process_frame
		await verify_controls(app,center,neighbor_plot)
		if failures==0:await verify_watering(app,center,neighbor_plot)
		if failures==0:await verify_sowing(app,center,neighbor_plot)
		if failures==0:await verify_harvesting(app,center,neighbor_plot)
		app.session.shutdown()
	app.queue_free()
	await process_frame
	for suffix:String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)
	finish()

func find_plot(world:World,farmer:Dictionary)->Vector2i:
	for y in range(27,39):
		for x in range(35,50):
			var tile:=Vector2i(x,y)
			farmer.x=x+0.5
			farmer.y=y+0.5
			var offsets:Array=World.TILLER.SQUARE+[Vector2i(0,2),Vector2i(-2,0),Vector2i(2,0)]
			if world.can_stand(Vector2(farmer.x,farmer.y)) and World.TILLER.plan(world,FARMER,tile,offsets).cells.size()==offsets.size():return tile
	return Vector2i(-1,-1)

func verify_controls(app,center:Vector2i,neighbor:Vector2i)->void:
	var world:World=app.session.world
	app._select_tool("hoe")
	app._refresh_hud()
	app.toast_time=0.0
	app.toast.hide()
	expect(app.selected_label.text.contains("Shift") and app.selected_label.text.contains("9 格"),"The HUD explains the current range modifier and size")
	var preview:Dictionary=app.view.hand_farm_preview(center,"precision_hoe")
	expect(preview.cells.size()==8 and preview.skipped.get(World.key(neighbor))=="已有農田","The native cursor preview skips the other farmer's tile")
	app.view.target=center
	app.view.selected="hoe"
	app.view.show_target=true
	app.view.hand_farm_wide=true
	app.view.queue_redraw()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--hoe-preview=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--hoe-preview="))==OK,"Capture the range preview")
	var plain:=center+Vector2i(0,2)
	click(app,plain,false)
	expect(world.state.crops.size()==2 and world.state.crops.get(World.key(plain),{}).get("owner")==FARMER,"A plain world click tills one tile")
	click(app,center,true)
	var recorded:Array=world.state.crops.keys().filter(func(key):return key!=World.key(plain) and key!=World.key(neighbor))
	recorded.sort()
	preview.cells.sort()
	expect(recorded==preview.cells and world.state.crops[World.key(neighbor)].owner==NEIGHBOR,"Shift click applies exactly the preview without changing the neighbor's crop")
	expect(app._controller_world_button(JOY_BUTTON_RIGHT_STICK,0) and app.controller_farm_wide,"Pressing R3 selects wide hoe mode")
	app.controller_offset=Vector2i(-2,0)
	var controller_target:=center+Vector2i(-2,0)
	var controller_preview:Dictionary=app.view.hand_farm_preview(controller_target,"precision_hoe")
	var count_before:int=world.state.crops.size()
	app.action_clock=0.0
	app._controller_world_button(JOY_BUTTON_X,0)
	expect(controller_preview.cells.size()>1 and world.state.crops.size()==count_before+controller_preview.cells.size(),"Controller X tills the indicated range in wide mode")
	expect(app._controller_world_button(JOY_BUTTON_RIGHT_STICK,0) and not app.controller_farm_wide,"Pressing R3 again selects single-tile mode")
	app.controller_offset=Vector2i(2,0)
	count_before=world.state.crops.size()
	app.action_clock=0.0
	app._controller_world_button(JOY_BUTTON_X,0)
	expect(world.state.crops.size()==count_before+1 and world.state.crops.get(World.key(center+Vector2i(2,0)),{}).get("owner")==FARMER,"Controller X works in single-tile mode")
	app.controller_aim=false
	var reassigned:bool=app.bindings.rebind("area_modifier",KEY_CTRL).ok
	app._select_tool("hoe")
	expect(reassigned and app.selected_label.text.contains("Ctrl"),"The hoe hint follows the existing rebindable range modifier")

func verify_watering(app,center:Vector2i,neighbor:Vector2i)->void:
	var world:World=app.session.world
	var single:=center+Vector2i(0,2)
	var already:=center+Vector2i.UP
	# Planted fixture isolating the watering controls. The other owner's tile remains locked.
	for offset:Vector2i in World.TILLER.SQUARE+[Vector2i(0,2)]:
		var tile:=center+offset
		var crop:Dictionary=world.state.crops[World.key(tile)]
		crop.kind="radish"
		crop.remaining=1
		crop.growth=5.0
		crop.wet=tile==already
	app.session._send_snapshot(1)
	app._select_tool("water")
	app._refresh_hud()
	expect(app.selected_label.text.contains("Ctrl") and app.selected_label.text.contains("作物"),"The watering hint follows the rebound modifier")
	var preview:Dictionary=app.view.hand_farm_preview(center,"precision_can")
	var skipped:Dictionary=preview.skipped
	expect(preview.cells.size()==7 and skipped.has(World.key(neighbor)) and skipped.get(World.key(already))=="已經澆水","Watering preview skips private and wet crops")
	app.toast_time=0.0
	app.toast.hide()
	app.view.target=center
	app.view.selected="water"
	app.view.show_target=true
	app.view.hand_farm_wide=true
	app.view.queue_redraw()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--water-preview=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--water-preview="))==OK,"Capture the watering preview")
	click(app,single,false)
	expect(world.state.crops[World.key(single)].wet and not world.state.crops[World.key(center)].wet,"A plain water click affects only one crop")
	click(app,neighbor,true)
	expect(not world.state.crops[World.key(center)].wet and not world.state.crops[World.key(neighbor)].wet,"A private center blocks the entire spread")
	click(app,center,true)
	expect(preview.cells.all(func(key):return world.state.crops[key].wet) and not world.state.crops[World.key(neighbor)].wet,"Ctrl click waters exactly the valid crop cells")

func verify_sowing(app,center:Vector2i,neighbor:Vector2i)->void:
	var world:World=app.session.world
	var single:=center+Vector2i(0,2)
	var bag:Dictionary=world.state.players[FARMER].inventory
	bag.radish_seed=3
	var fuel:=int(bag.get("charcoal",0))
	# Keep the neighbor's crop. Prepare the actor's own tilled plots for sowing.
	for offset:Vector2i in World.TILLER.SQUARE+[Vector2i(0,2)]:
		var tile:=center+offset
		if tile!=neighbor:world.state.crops[World.key(tile)]={"kind":"","growth":0.0,"wet":false,"owner":FARMER}
	app.session._send_snapshot(1)
	app.crop="radish"
	app._select_tool("seed")
	app._refresh_hud()
	expect(app.selected_label.text.contains("Ctrl") and app.selected_label.text.contains("奶白蘿蔔"),"Sowing guidance shows the modifier and the selected seed")
	click(app,single,false)
	expect(world.state.crops[World.key(single)].kind=="radish" and int(bag.radish_seed)==2,"Ordinary click sows one seed")
	var neighbor_before:Dictionary=world.state.crops[World.key(neighbor)].duplicate(true)
	click(app,neighbor,true)
	expect(int(bag.radish_seed)==2 and world.state.crops[World.key(neighbor)]==neighbor_before,"A foreign center rejects the spread without taking seeds")
	app._refresh_hud() # The normal HUD timer is stopped in this fixture.
	app.view.seed_kind="radish"
	var preview:Dictionary=app.view.hand_farm_preview(center,"precision_seed_pouch")
	var ordered:bool=preview.cells==[World.key(center),World.key(center+Vector2i.UP)]
	expect(ordered and preview.skipped.get(World.key(center+Vector2i.LEFT))=="種子不足" and app.selected_label.text.contains("×2"),"Limited seeds reserve the center and nearest tile, and the HUD shows the remaining count")
	app.toast_time=0.0
	app.toast.hide()
	app.view.target=center
	app.view.selected="seed"
	app.view.show_target=true
	app.view.hand_farm_wide=true
	app.view.queue_redraw()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed-preview=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--seed-preview="))==OK,"Capture the limited-seed preview")
	click(app,center,true)
	expect(preview.cells.all(func(key):return world.state.crops[key].kind=="radish") and world.state.crops[World.key(center+Vector2i.LEFT)].kind.is_empty() and int(bag.radish_seed)==0,"Range sowing applies exactly the two affordable tiles")
	expect(int(bag.get("charcoal",0))==fuel and world.state.crops[World.key(neighbor)]==neighbor_before,"The hand pouch uses no fuel and leaves other farmers' crops unchanged")

func verify_harvesting(app,center:Vector2i,neighbor:Vector2i)->void:
	var world:World=app.session.world
	var immature:=center+Vector2i.UP
	var tomato:=center+Vector2i.DOWN
	var single:=center+Vector2i(0,2)
	for offset:Vector2i in World.TILLER.SQUARE+[Vector2i(0,2)]:
		var tile:=center+offset
		var plot:Dictionary=world.state.crops[World.key(tile)]
		plot.kind="tomato" if tile==tomato else "radish"
		plot.growth=0.0 if tile==immature else float(World.CROPS[plot.kind].time)
		plot.remaining=3 if tile==tomato else 1
		plot.wet=true
	app.session.rates[1].clear() # Earlier phases used injected input without waiting between actions.
	app.session._send_snapshot(1)
	app._select_tool("harvest")
	app._refresh_hud()
	expect(app.selected_label.text.contains("Ctrl") and app.selected_label.text.contains("成熟作物"),"The harvest hint shows the rebound area modifier")
	var preview:Dictionary=app.view.hand_farm_preview(center,"precision_sickle")
	expect(preview.cells.size()==7 and preview.skipped.get(World.key(immature))=="還沒成熟" and preview.skipped.get(World.key(neighbor))=="無採收權限","Preview differentiates immature and private crops")
	app.toast_time=0.0
	app.toast.hide()
	app.view.target=center
	app.view.selected="harvest"
	app.view.show_target=true
	app.view.hand_farm_wide=true
	app.view.queue_redraw()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--harvest-preview=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--harvest-preview="))==OK,"Capture the mixed harvest preview")
	click(app,single,false)
	expect(world.state.crops[World.key(single)].kind.is_empty() and world.state.crops[World.key(center)].kind=="radish","Ordinary clicking harvests only one crop")
	click(app,neighbor,true)
	expect(world.state.crops[World.key(center)].kind=="radish","A private center rejects the entire sweep")
	var bag:Dictionary=world.state.players[FARMER].inventory
	var radish:=int(bag.get("radish",0))
	var fuel:=int(bag.get("charcoal",0))
	click(app,center,true)
	expect(int(bag.get("radish",0))==radish+6 and int(bag.get("tomato",0))==2 and int(bag.get("charcoal",0))==fuel,"Six radishes and two tomatoes were harvested without fuel")
	expect(world.state.crops[World.key(immature)].growth==0.0 and world.state.crops[World.key(neighbor)].kind=="radish","Private and unripe crops stay in the field")
	var regrowing:Dictionary=world.state.crops[World.key(tomato)]
	expect(regrowing.kind=="tomato" and int(regrowing.remaining)==2 and not regrowing.wet,"A repeating crop stays planted with its next cycle")

func click(app,tile:Vector2i,spread:bool)->void:
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.shift_pressed=spread and int(app.bindings.keys.area_modifier)==KEY_SHIFT
	press.ctrl_pressed=spread and int(app.bindings.keys.area_modifier)==KEY_CTRL
	press.position=app.view.screen(Vector2(tile)+Vector2(0.5,0.5))*app.view.view_zoom()
	app.action_clock=0.0
	app._unhandled_input(press)

func finish()->void:
	print("HAND_HOE_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
