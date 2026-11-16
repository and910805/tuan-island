extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/freight_ui.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func visible(c:Control)->bool:
	if not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func frames()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame
func check_layout()->void:
	await frames()
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Freight panel fits viewport")
	for button in app.modal.find_children("*","BaseButton",true,false):
		check(visible(button),"Visible control "+button.name)
func press(id:String)->void:
	var button=app.modal.find_child(id,true,false)
	check(button!=null,"Action exists: "+id)
	if button==null:return
	check(not button.disabled and visible(button),"Action ready: "+id)
	if button.disabled:return
	await create_timer(0.12).timeout
	button.pressed.emit();await frames()
func place(region:String,cell:Vector2i)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	person.region=region;person.x=cell.x+0.5;person.y=cell.y+0.5
	app.session._send_snapshot(1)
func run()->void:
	var path:=OS.get_environment("TEMP").path_join("freight-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"運礦旅人",path)!=OK:check(false,"Host starts");quit(1);return
	var w=app.session.world
	var id:String=app.session.profile.token
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		w.state.picnic=true;w.state.board=true
		w.state.mine_depths={"unlocked":5,"ready":{},"pumped":24}
		w.state.mine_freight=World.MINE_FREIGHT.fresh()
		w.state.players[id].inventory.merge({"stone":10,"copper_ore":40,"gold_ore":6},true)
		w.state.objects["41,35"]={"type":"private_chest","owner":id,"items":{}}
		place("mine_5",World.MINE_FREIGHT.LOAD_CELL)
		app._freight_menu();await check_layout()
		check(app.modal.find_child("FreightDispatch",true,false).disabled,"Empty shipment cannot dispatch")
		await press("Load_copper_ore")
		check(int(w.state.players[id].inventory.copper_ore)==35,"UI load debits exactly five")
		check(app.modal.find_child("Cargo_copper_ore",true,false).count==5,"Cargo slot reflects server amount")
		app.modal.find_child("LoadOne_gold_ore",true,false).grab_focus()
		await press("LoadOne_gold_ore")
		check(root.gui_get_focus_owner()!=null and root.gui_get_focus_owner().name=="LoadOne_gold_ore","Snapshot preserves the keyboard action focus")
		check(int(w.state.mine_freight.jobs[id].items.gold_ore)==1,"Single-item control supports exact quantity")
		await press("Unload_gold_ore")
		check(not w.state.mine_freight.jobs[id].items.has("gold_ore"),"Unload returns entire chosen stack")
		await press("Target_41_35")
		check(not app.modal.find_child("FreightDispatch",true,false).disabled,"Own target enables dispatch")
		await press("FreightDispatch")
		check(w.state.mine_freight.jobs[id].status=="transit","UI dispatch commits manifest")
		check(app.modal.find_child("Load_copper_ore",true,false)==null,"Transit cannot alter load")
		await check_layout()
		w.step(59,true);app.session._send_snapshot(1);await frames()
		check(w.state.objects["41,35"].items.is_empty(),"No early delivery through UI session")
		check(app.modal.find_child("FreightCountdown",true,false).text.contains("1 遊戲秒"),"Countdown updates without reopening")
		w.step(1,true);app.session._send_snapshot(1);await frames()
		check(int(w.state.objects["41,35"].items.copper_ore)==5,"Goods reach the actual destination")
		check(w.state.players[id].region=="mine_5","Owner stays underground during delivery")
		await press("Load_copper_ore")
		await press("Target_41_35")
		await press("FreightDispatch")
		w.state.objects.erase("41,35")
		w.step(60,true);app.session._send_snapshot(1);await frames()
		check(w.state.mine_freight.jobs[id].status=="held","Missing destination produces held UI state")
		check(app.modal.find_child("FreightClaim",true,false).disabled,"Cannot claim while underground")
		place("home",World.MINE_FREIGHT.CLAIM_CELL)
		app._board();await frames()
		await press("BoardFreight")
		await check_layout()
		var before:=int(w.state.players[id].inventory.copper_ore)
		await press("FreightClaim")
		check(int(w.state.players[id].inventory.copper_ore)==before+5,"Board UI returns whole held load")
		check(app.modal.find_child("FreightClaim",true,false)==null,"Claim action disappears after receipt")
		place("mine_5",Vector2i(20,18))
		app._freight_menu();await frames()
		check(app.modal.find_child("Load_copper_ore",true,false).disabled,"Far loading is disabled")
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_FREIGHT_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
