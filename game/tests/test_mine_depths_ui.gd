extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/mine_ui.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func visible(c:Control)->bool:
	if not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func place(p:Vector2i)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	person.x=p.x-0.5;person.y=p.y+0.5
	app.session._send_snapshot(1)
func open(site:String)->void:
	UI.open(app,site)
	for i in range(5):await process_frame
	app._layout_preview();await process_frame
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Mine modal fits viewport: "+site)
	for c in app.modal.find_children("*","BaseButton",true,false):check(visible(c),"Mine button fully visible: "+c.text)
func press(name:String)->bool:
	var button=app.modal.find_child(name,true,false)
	if button==null:check(false,"Missing "+name);return false
	check(visible(button) and not button.disabled,"Enabled visible "+name)
	if button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await process_frame
	return true
func run()->void:
	var path:=OS.get_environment("TEMP").path_join("depth-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"礦場旅人",path)!=OK:check(false,"Host starts");quit(1);return
	var w=app.session.world;var id:String=app.session.profile.token
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		w.state.picnic=true;w.state.board=true
		w.state.players[id].region="jinguashi"
		place(World.MINES.ENTRY)
		await open("entry")
		await press("MineEnter")
		check(app.session.snapshot.region_id=="mine_1","Entry button enters real mine")
		app._close_modal();app._refresh_hud()
		var next_button:Button=app.hud.find_child("TrackerNext",true,false)
		next_button.pressed.emit();await process_frame
		check(app.modal.get_meta("life_modal_layout","")=="island_map","Mine tracker opens local return-route map rather than surface travel")
		app._close_modal()
		for level in range(1,6):
			w.state.players[id].region="mine_%d"%level
			w.state.players[id].mine_energy=40
			w.state.players[id].inventory.merge({"wood":20,"stone":20,"plank":10,"copper_joint":5,"reinforced_pick":1},true)
			# Q07: B1–B5 only, so the surface hoist is never repaired here.
			w.state.mine_depths={"unlocked":level,"ready":{},"pumped":24 if level>=4 else 0,"hoist":false}
			place(World.MINES.REST)
			await open("rest")
			await press("MineRest")
			check(w.state.players[id].mine_energy==100,"Rest button replenishes on actual host")
			place(World.MINES.SERVICE)
			await open("service")
			if level==3:
				var button=app.modal.find_child("MineCommission",true,false)
				check(button!=null and button.disabled,"Drain project unavailable before pumping")
				w.state.mine_depths.pumped=24
				app.session._send_snapshot(1)
				UI.refresh(app)
				await process_frame
				button=app.modal.find_child("MineCommission",true,false)
				check(button!=null and not button.disabled,"Live snapshot enables drained project")
			if level<5:
				await press("MineCommission")
				check(w.state.mine_depths.unlocked==level+1,"Commission button commits shared unlock")
				place(World.MINES.DOWN)
				await open("down")
				await press("MineDown")
				check(app.session.snapshot.region_id=="mine_%d"%(level+1),"Down button changes actual region")
				place(World.MINES.UP)
				await open("up")
				await press("MineUp")
				check(app.session.snapshot.region_id=="mine_%d"%level,"Up button changes actual region")
			else:check(app.modal.find_child("MineCommission",true,false)!=null,"T067: fifth floor now offers the B6 project")
			place(Vector2i(20,18))
			await open("rest")
			var rest=app.modal.find_child("MineRest",true,false)
			check(rest!=null and rest.disabled,"Remote rest cannot be submitted")
	check(preload("res://scripts/inventory_item_art.gd").icon("gold_ore")!=null and preload("res://scripts/inventory_item_art.gd").icon("gold_sample")!=null,"New item PNG icons resolve")
	await check_mud_event(w,id,path)
	await check_adventure_mud(w,id,path)
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_DEPTHS_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))

func check_mud_event(world:World,id:String,path:String)->void:
	app._close_modal()
	var person:Dictionary=world.state.players[id]
	person.region=World.MINES.MUD_REGION
	person.x=World.MINES.MUD_GATE.x+0.5
	person.y=World.MINES.MUD_GATE.y+1.5
	person.inventory.radish=0
	person.inventory.quality_radish=0
	for step in 10:world.move_player(id,Vector2.UP,1.0/60.0)
	check(person.y>=World.MINES.MUD_ALCOVE_EDGE,"Mudling blocks only the optional upper pocket")
	check(not world.act(id,"mud-empty","mine_mud_lure",World.MINES.MUD_GATE).ok,"A player without bait can still use the main mine")
	person.inventory.radish=1
	app.session._send_snapshot(1)
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--mud-preview="):continue
		root.size=Vector2i(1280,800)
		app.toast.hide()
		await create_timer(0.3).timeout
		app.view.queue_redraw()
		RenderingServer.force_draw()
		check(root.get_texture().get_image().save_png(arg.trim_prefix("--mud-preview="))==OK,"Capture mudling in the actual cave")
	app._interact()
	await process_frame
	if not await press("MineMudLure"):return
	check(person.get("mud_alcove",0)==1 and person.inventory.radish==0,"Offering a radish opens the side pocket")
	check(not world.act(id,"mud-outside-claim","mine_mud_claim",World.MINES.MUD_REWARD).ok,"Player must cross the passage to collect")
	for step in 11:world.move_player(id,Vector2.UP,1.0/60.0)
	for step in 30:world.move_player(id,Vector2.LEFT,1.0/60.0)
	var copper:=int(person.inventory.get("copper_ore",0))
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	if not await press("MineMudClaim"):return
	check(person.get("mud_alcove",0)==2 and int(person.inventory.get("copper_ore",0))==copper+World.MINES.MUD_COPPER,"Collects the fixed copper reward")
	check(not world.act(id,"mud-repeat","mine_mud_claim",World.MINES.MUD_REWARD).ok,"A second claim cannot duplicate copper")
	var reopened:=World.new()
	check(reopened.load_world(path) and reopened.state.players[id].get("mud_alcove",0)==2,"Side pocket completion survives reload")

func check_adventure_mud(world:World,id:String,path:String)->void:
	app._close_modal()
	world.state.world_mode="adventure"
	var person:Dictionary=world.state.players[id]
	person.erase("mud_alcove")
	person.region=World.MINES.MUD_REGION
	person.x=World.MINES.MUD_GATE.x+0.5
	person.y=World.MINES.MUD_GATE.y+1.5
	var gate:=World.MINES.MUD_GATE
	check(not world.act(id,"adventure-bait","mine_mud_lure",gate).ok,"Adventure uses the duel branch")
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	if not await press("MineMudDuel"):return
	check(person.has("mud_duel") and not person.mud_duel.dodged,"Adventure menu starts the warning")
	check(not world.act(id,"adventure-early","mine_mud_duel",gate,"strike").ok,"Early strike cannot clear the alcove")
	check(world.step(World.MINES.MUD_WINDUP+0.1,true),"Advance to the first recovery window")
	check(not world.act(id,"adventure-no-dodge","mine_mud_duel",gate,"strike").ok,"A player who stood still cannot clear the encounter")
	check(world.step(World.MINES.MUD_RECOVERY,true),"Wait out the failed round")
	check(world.act(id,"adventure-retry","mine_mud_duel",gate,"start").ok,"Player can retry without losing tools")
	for step in 15:world.move_player(id,Vector2.LEFT,1.0/60.0)
	check(person.mud_duel.dodged,"Actual lateral movement counts as a dodge")
	check(world.step(World.MINES.MUD_WINDUP+0.1,true),"Reach the counter window")
	app.session._send_snapshot(1)
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--adventure-preview="):continue
		root.size=Vector2i(1280,800)
		app.toast.hide()
		await create_timer(0.25).timeout
		app.view.queue_redraw()
		RenderingServer.force_draw()
		check(root.get_texture().get_image().save_png(arg.trim_prefix("--adventure-preview="))==OK,"Capture the adventure counter prompt")
	app._interact()
	check(person.get("mud_alcove",0)==1 and not person.has("mud_duel"),"Interaction counters successfully after the dodge")
	for step in 15:world.move_player(id,Vector2.UP,1.0/60.0)
	for step in 15:world.move_player(id,Vector2.LEFT,1.0/60.0)
	var copper:=int(person.inventory.get("copper_ore",0))
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	if not await press("MineMudClaim"):return
	check(int(person.inventory.get("copper_ore",0))==copper+World.MINES.MUD_COPPER,"Adventure yields the same copper reward as life mode")
	var reloaded:=World.new()
	check(reloaded.load_world(path) and reloaded.state.world_mode=="adventure" and reloaded.state.players[id].mud_alcove==2,
		"Adventure mode and event completion survive reload")
