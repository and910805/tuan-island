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
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_DEPTHS_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
