extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.POT_RACK
const POT:=Industry.POT_RACK_EMPTY
const FIELD:=Vector2i(38,34)
const PLOT:=Vector2i(40,34)
const FAR:=PLOT+Vector2i.RIGHT
const ROTATED:=Vector2i(42,34)
const MOVED:=PLOT+Vector2i.DOWN
const GUEST:="flower-rack-guest"
var app
var world:World
var owner:String
var directory:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"flower-rack-qa-%d"%serial,action,cell,extra)

func pots(at:Vector2i)->Array:
	return world.state.objects.get(World.key(at),{}).get("rack_pots",["","",""])

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Saved "+name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("rack-preview","")
	var path:="user://flower-rack-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="flower-rack-owner"
	if app.session.host(0,"銅框花架驗收",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=World.SPAWN.x
	person.y=World.SPAWN.y
	world.state.time=500.0
	var inv:Dictionary=person.inventory
	inv.wood=16
	inv.copper_ingot=12
	inv[POT]=3
	inv.bluebell_seed=1
	inv.orange_blossom=1
	expect(act("hoe",FIELD).ok and act("seed",FIELD,"bluebell").ok and act("water",FIELD).ok,"The displayed bluebell starts as a planted seed")
	world.step(151.0,true)
	expect(act("harvest",FIELD).ok and int(inv.bluebell)==2,"Real harvesting puts flowers into the bag")
	world.add_player(GUEST,"朋友",Vector2(41.5,33.5))
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for tab:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if tab.text=="星砂溫室":greenhouse=tab
	expect(greenhouse!=null,"The greenhouse workshop shelf is visible")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The shelf has a copper rack with the right artwork")
		if slot!=null:slot.pressed.emit()
	app._layout_preview()
	await capture("copper-rack-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The documented recipe is enabled")
	if place!=null:place.pressed.emit()
	app.session.perform("build",PLOT,KIND)
	expect(world.blocked(PLOT) and world.blocked(FAR) and World.station_anchor(world.state.objects,FAR)==PLOT,"Two furniture cells have a single anchor")
	expect(inv.wood==8 and inv.copper_ingot==6,"Building costs exactly 8 wood and 6 copper")
	person.x=41.5
	person.y=33.5
	app.session._send_snapshot(1)
	app.view.show_target=false
	app._interact()
	var picker:=app.modal.find_child("CopperRackPicker",true,false) as OptionButton if app.modal!=null else null
	var put:=app.modal.find_child("CopperRackPut_0",true,false) as Button if app.modal!=null else null
	expect(picker!=null and picker.item_count==3 and put!=null and not put.disabled,"The far cell offers the empty pot and the two owned flowers")
	if picker!=null and put!=null:
		picker.select(1)
		put.pressed.emit()
	expect(pots(PLOT)==["bluebell","",""] and inv[POT]==2 and inv.bluebell==1,"The first real UI action stores a pot and a harvested flower")
	var transfer:Dictionary=world.state.ledger.entries[-1]
	expect(transfer.kind=="container" and transfer.box[0].items=={POT:1,"bluebell":1},"The audit journal records the pot and flower as stored, not consumed")
	expect(not act(Industry.POT_RACK_PUT,FAR,"0:bluebell").ok and not act(Industry.POT_RACK_PUT,FAR,"3:flower_pot").ok,"An occupied or nonexistent slot cannot accept more stock")
	expect(not act(Industry.POT_RACK_PUT,FAR,"1:bluebell_seed").ok,"The rack accepts harvested flowers only")
	expect(act(Industry.POT_RACK_PUT,FAR,"1:orange_blossom").ok and act(Industry.POT_RACK_PUT,FAR,"2:flower_pot").ok,"The remaining slots accept a second flower and a plain pot")
	expect(inv[POT]==0 and inv.orange_blossom==0 and pots(PLOT)==["bluebell","orange_blossom","flower_pot"],"Each slot keeps its own contents")
	expect(not act(Industry.POT_RACK_TAKE,FAR,"0",GUEST).ok and not act("withdraw",FAR,"flower_pot",GUEST).ok,"Other players and generic chest actions cannot take display items")
	expect(not act("remove",FAR).ok,"A filled rack must be emptied before dismantling")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"銅框花架",World.BUILD,World.NAMES)
	expect(design.ok,"The filled rack has a structural blueprint")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if quote.ok:
			var built:=world.apply_blueprint(owner,"c".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(built.ok and Industry.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and pots(ROTATED)==["","",""],"The rotated blueprint does not duplicate display contents")
		else:expect(false,"The rotated shelf fits the neighboring plot")
	inv=world.state.players[owner].inventory
	for day in 3:world.step(World.WEATHER.DAY_SECONDS,true)
	expect(pots(PLOT)==["bluebell","orange_blossom","flower_pot"] and inv[POT]==0 and inv.bluebell==1,"A display retains the exact inventory over three simulated days")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(World.key(PLOT),{}).get("rack_pots")==pots(PLOT),"The primary save reloads the three display slots")
	for invalid in [["wrong_flower","",""],["bluebell"],["","",""]]:
		var bad:=loaded.state.duplicate(true)
		if bad.objects.has(World.key(PLOT)):
			bad.objects[World.key(PLOT)].rack_pots=invalid
			expect(not World.SAVE_SCHEMA.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The save rejects a malformed slot record")
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(41,34.5)*32-Vector2(root.size)/4.0
	await capture("copper-rack-placed")
	app._interact()
	expect(app.modal!=null and app.modal.find_child("CopperRackTake_2",true,false)!=null and app.modal.find_child("CopperRackPicker",true,false)==null,"The full rack offers one take action per slot and no unneeded controls")
	await capture("copper-rack-panel")
	app._close_modal()
	app.session.peers[1]=GUEST
	app.session._send_snapshot(1)
	app.LifeTasks.copper_flower_rack(app,FAR,app.session.snapshot.objects[World.key(PLOT)])
	expect(app.modal.find_child("CopperRackSlot_0",true,false).text==World.NAMES.bluebell and app.modal.find_child("CopperRackTake_0",true,false)==null,"Guests see the flowers without a take button")
	app._close_modal()
	app.session.peers[1]=owner
	app.session._send_snapshot(1)
	expect(act("move_object",FAR,World.key(MOVED)).ok and pots(MOVED)==["bluebell","orange_blossom","flower_pot"],"Moving from the second cell keeps all three positions")
	var move_id:String=world.state.construction.last.get(owner,{}).get("id","")
	inv[POT]=1000000000
	expect(not act(Industry.POT_RACK_TAKE,MOVED,"0").ok and pots(MOVED)[0]=="bluebell" and inv.bluebell==1,"A full bag keeps both pot and flower on the rack")
	inv[POT]=0
	expect(act(Industry.POT_RACK_TAKE,MOVED,"1").ok and pots(MOVED)==["bluebell","","flower_pot"],"Taking the middle position preserves its neighbors")
	expect(not move_id.is_empty() and not act(World.UNDO_ACTION,MOVED,move_id).ok and inv.orange_blossom==1,"Undo cannot restore items already taken from a moved rack")
	expect(act(Industry.POT_RACK_TAKE,MOVED,"0").ok and act(Industry.POT_RACK_TAKE,MOVED,"2").ok and inv[POT]==3 and inv.bluebell==2 and inv.orange_blossom==1,"Taking all positions returns each original pot and flower")
	expect(act("remove",MOVED).ok and inv.wood==8 and inv.copper_ingot==6 and pots(MOVED)==["","",""],"Dismantling the empty rack returns building materials once")
	expect(act(Industry.POT_RACK_PUT,ROTATED+Vector2i.DOWN,"2:bluebell").ok and pots(ROTATED)[2]=="bluebell","The southern cell of the rotated shelf can display a pot")
	app.session._send_snapshot(1)
	await capture("copper-rack-vertical")
	expect(act(Industry.POT_RACK_TAKE,ROTATED,"2").ok and inv[POT]==3 and inv.bluebell==2,"The vertical shelf returns the original pot and flower")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COPPER_FLOWER_RACK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
