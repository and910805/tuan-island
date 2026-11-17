extends SceneTree

const World=preload("res://scripts/world.gd")
const S=World.Squirrel
const TOKEN:="squirrel-observer"
var checks:=0
var failures:=0

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"林邊訪客")
	var player:Dictionary=world.state.players[TOKEN]
	player.x=S.SITE.x+0.5
	player.y=S.SITE.y+1.5
	expect(not world.act(TOKEN,"before","squirrel_observe",S.SITE).ok,"Before 08:00 there is no squirrel")
	world.step(480.0-float(world.state.time),true)
	var path:="user://squirrel-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	for i in S.COST:
		expect(world.act(TOKEN,"observe-%d"%i,"squirrel_observe",S.SITE).ok,"Look for the squirrel on each day")
		expect(int(player.inventory[S.ACORN])==i+1,"Each observation grants one acorn")
		expect(not world.act(TOKEN,"duplicate-%d"%i,"squirrel_observe",S.SITE).ok,"The day's observation does not repeat")
		expect(world.save() and world.load_world(path),"The observation survives reload")
		player=world.state.players[TOKEN]
		expect(not world.act(TOKEN,"retry-%d"%i,"squirrel_observe",S.SITE).ok,"Reload cannot grant another acorn on the same day")
		if i<S.COST-1:
			expect(not world.act(TOKEN,"not-enough-%d"%i,"squirrel_exchange",S.SITE).ok,"You need three acorns")
			world.step(World.WEATHER.DAY_SECONDS,true)
	if DisplayServer.get_name()!="headless":await verify_scene(world)
	expect(world.act(TOKEN,"trade","squirrel_exchange",S.SITE).ok and int(player.inventory[S.ACORN])==0
		and int(player.inventory[S.KIT])==1,"Trade exactly three acorns for the ornament")
	var tile:=Vector2i(40,35)
	player.x=tile.x+0.5
	player.y=tile.y+0.5
	expect(world.act(TOKEN,"place","build",tile,S.ORNAMENT).ok and world.state.objects[World.key(tile)].type==S.ORNAMENT,
		"Place the ornament using the ordinary construction action")
	expect(world.save() and world.load_world(path),"The decoration survives reload")
	var capture:=World.BLUEPRINT_DESIGN.capture(world.state,TOKEN,Rect2i(tile,Vector2i.ONE),"林邊掛飾",World.BUILD,World.NAMES)
	expect(capture.ok and capture.get("blueprint",{}).get("pieces",[]).size()==1,"Capture the placed ornament in the blueprint")
	expect(world.act(TOKEN,"remove","remove",tile).ok and int(world.state.players[TOKEN].inventory[S.KIT])==1,
		"Removing the decoration returns its kit")
	if capture.ok:
		var blueprint:Dictionary=capture.blueprint
		var quote:=world.quote_blueprint(TOKEN,blueprint,tile)
		expect(quote.ok and quote.cost=={S.KIT:1},"The copied ornament requires exactly one earned kit")
		if quote.ok:
			var nonce:="a".repeat(32)
			var result:=world.apply_blueprint(TOKEN,nonce,blueprint,tile,0,str(quote.hash))
			expect(result.ok and int(world.state.players[TOKEN].inventory.get(S.KIT,0))==0
				and world.state.objects.get(World.key(tile),{}).get("type") == S.ORNAMENT,
				"Apply the captured ornament and consume the returned kit once: "+str(result.get("message","")))
			var saved_state:Dictionary=world.state.duplicate(true)
			expect(world.apply_blueprint(TOKEN,nonce,blueprint,tile,0,str(quote.hash))==result and world.state==saved_state,
				"Retrying the blueprint cannot spend or place again")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WOODLAND_SQUIRREL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_scene(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.session.snapshot.players[TOKEN].x+=1.0
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--squirrel-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--squirrel-preview="))==OK,"Capture the native squirrel scene")
	app._interact()
	await create_timer(0.27).timeout
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	expect(buttons.any(func(node):return node.text=="換橡果掛飾" and not node.disabled),"The forest interaction offers an enabled exchange")
	app._build_menu()
	await process_frame
	var furniture:Button=app.modal.find_child("BuildTab2",true,false)
	var ornament:Button=app.modal.find_child("BuildSlot_acorn_ornament_2",true,false)
	expect(furniture!=null and ornament!=null,"The ornament has a slot in the furniture tab")
	if furniture!=null and ornament!=null:
		furniture.pressed.emit()
		expect(ornament.is_visible_in_tree(),"The ornament is visible to players browsing furniture")
		ornament.pressed.emit()
		var title:Label=app.modal.find_child("BuildTitle",true,false)
		expect(title!=null and title.text=="橡果掛飾","Selecting the ornament shows its recipe")
	app.queue_free()
	await process_frame
