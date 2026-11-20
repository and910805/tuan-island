extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Goals=World.RESIDENT_GOALS
const KIND:="chair"
const NAME:="矮背木椅"
const SIT:=Goals.MASTER_BENCH_SIT
const SEAT:=Goals.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
const UNDO_A:=Vector2i(44,34)
const UNDO_B:=Vector2i(46,34)
const OWNER_NAME:="山居木匠"
const GUEST:="low-chair-visitor-ahlian"
const GUEST_NAME:="路過的阿蓮"
const FAR:="low-chair-visitor-far-ahmei"
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.3).timeout
	app.view.queue_redraw()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WOOD_CHAIR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

## Everything a seat must NOT touch: the whole player record minus pose/position.
func stats_of(token:String)->Dictionary:
	var copy:Dictionary=world.state.players[token].duplicate(true)
	for field in [SEAT,"x","y","fishing","receipts"]:copy.erase(field)
	return copy

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://low-wood-chair-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="low-wood-chair-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,40.5,33.5)
	person.inventory.merge({"wood":30},true)
	world.state.time=720.0
	for tile in [SITE,MOVED,UNDO_A,UNDO_B]:world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	world.add_player(FAR,"遠方的阿美",Vector2(48.5,40.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Rename and recipe: same id, same cost, still passable ---------------------------------
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].name==NAME,"The existing chair id is displayed as 矮背木椅")
	expect(World.BUILD[KIND].get("wood")==6 and World.BUILD[KIND].size()==2,"Cost is unchanged: 6 wood plus the name only")
	expect(not World.BUILD.has("low_back_chair") and not World.BUILD.has("wood_chair"),"No second chair id was introduced")
	var wood:=int(person.inventory.wood)
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the chair for its owner"):
		await finish()
		return
	expect(person.inventory.wood==wood-6,"Building spends exactly six wood")
	expect(not world.blocked(SITE) and world.can_stand(Vector2(SITE)+Vector2(0.5,0.5)),"The chair tile stays passable")

	# --- Real interaction: sit, no stat/resource change ----------------------------------------
	app._select_tool("hoe")
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	var before:=stats_of(owner)
	var objects_before:=var_to_str(world.state.objects)
	await capture("low-wood-chair-empty")
	app._interact()
	expect(person.get(SEAT,{})=={"cell":World.key(SITE),"side":0},"app._interact sits via MASTER_BENCH_SIT with the MASTER_BENCH_SEAT pose")
	expect(not is_instance_valid(app.modal) or not app.modal.visible,"Sitting opens no dialog")
	expect(stats_of(owner)==before and var_to_str(world.state.objects)==objects_before,"Sitting changes no stat, inventory, coin or object")
	app.session._send_snapshot(1)
	await capture("low-wood-chair-owner-seated")
	app.session.perform("emote",Vector2i.ZERO,"hello")
	var shown:Dictionary=app.view.active_emote(app.session.own_id)
	expect(shown.get("caption")==Session.EMOTES.hello and person.has(SEAT),"Real hello emote keeps the owner seated")
	await capture("low-wood-chair-hello")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		expect(app.view.world_labels.any(func(label):return label.title==Session.EMOTES.hello),"The seated greeting is present in the native render")
		var region:=Rect2(Vector2.ZERO,Vector2(root.size)/app.view.view_zoom())
		var head:Vector2=app.view.screen(Vector2(SITE)+Vector2(0.5,0.91))-Vector2(0,34)
		var placed:Array=app.view.world_label_placements(region)
		expect(placed.any(func(label):return label.title==Session.EMOTES.hello and label.rect.end.y<head.y),"Greeting sits above the character's head")
	app.view.player_emotes.clear()

	# --- One at a time; anyone may sit; malformed requests are refused -------------------------
	expect(not world.act(GUEST,"busy",SIT,SITE).ok and not guest.has(SEAT),"Only one person fits on the chair")
	expect(not world.act(FAR,"far",SIT,SITE).ok and not world.state.players[FAR].has(SEAT),"Sitting needs the player to be near the chair")
	expect(world.act(owner,"stand-by-action",SIT,SITE).ok and not person.has(SEAT),"The sit action toggles the owner back up")
	expect(not world.act(GUEST,"extra",SIT,SITE,"1").ok and not guest.has(SEAT),"A sit request with a bogus side/extra is refused")
	expect(not world.act(GUEST,"empty-tile",SIT,Vector2i(41,35)).ok and not guest.has(SEAT),"Sitting on a tile with no chair is refused")
	expect(not world.act(GUEST,"far-tile",SIT,Vector2i(60,60)).ok and not guest.has(SEAT),"Sitting on a far-away tile is refused")
	var guest_before:=stats_of(GUEST)
	expect(world.act(GUEST,"guest-sit",SIT,SITE).ok and guest.get(SEAT,{})=={"cell":World.key(SITE),"side":0},"A visitor (not the owner) may sit")
	expect(stats_of(GUEST)==guest_before,"A visitor's sitting changes no stat or resource")
	expect(not world.act(owner,"owner-busy",SIT,SITE).ok and not person.has(SEAT),"The owner cannot take a chair a visitor is using")

	# --- Owner move/remove blocked while occupied ----------------------------------------------
	wood=int(person.inventory.wood)
	var move:=world.act(owner,"busy-move","move_object",SITE,World.key(MOVED))
	expect(not move.ok and not str(move.get("message","")).is_empty() and obj().get("type")==KIND and obj(MOVED).is_empty(),"Owner cannot move an occupied chair")
	var remove:=world.act(owner,"busy-remove","remove",SITE)
	expect(not remove.ok and not str(remove.get("message","")).is_empty() and obj().get("type")==KIND and person.inventory.wood==wood,"Owner cannot dismantle an occupied chair (no refund)")
	expect(guest.get(SEAT,{}).get("cell")==World.key(SITE),"A refused move/remove leaves the visitor seated")

	# --- Saved occupied chair compatibility ---------------------------------------------------
	expect(world.save(),"The world saves with a visitor on the chair")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and loaded.state.players[GUEST].get(SEAT,{}).get("cell")==World.key(SITE),"Reload keeps the chair and the occupied pose")
	expect(valid(world.state),"The live occupied-chair state passes save validation")
	var forged:=world.state.duplicate(true)
	forged.players[owner][SEAT]={"cell":World.key(SITE),"side":0}
	expect(not valid(forged),"Save validation rejects two occupants on one chair")
	forged=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(SITE),"side":1}
	expect(not valid(forged),"Save validation rejects a second seat index on a one-seat chair")
	forged=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(Vector2i(41,35)),"side":0}
	expect(not valid(forged),"Save validation rejects a pose on a tile with no seat")
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"矮背木椅",World.BUILD,World.NAMES)
	expect(cut.ok and cut.blueprint.pieces[0].kind==KIND,"Blueprint still captures the renamed chair by its old id")

	# --- A disconnected guest no longer reserves the seat ------------------------------------
	world.active_tokens.erase(GUEST)
	expect(not world.active_tokens.has(GUEST),"The disconnected visitor is no longer active")
	var mv:=world.act(owner,"after-leave-move","move_object",SITE,World.key(MOVED))
	if expect(mv.ok and obj(MOVED).get("type")==KIND and obj().is_empty(),"A chair whose visitor left can be moved again"):
		expect(world.act(owner,"back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"...and moved back")
	expect(not guest.has(SEAT),"Moving the chair clears the disconnected visitor's old pose")
	if person.has(SEAT):world.act(owner,"reset-stand",SIT,SITE)
	app.session._send_snapshot(1)
	app._interact()
	expect(person.get(SEAT,{}).get("cell")==World.key(SITE) and not guest.has(SEAT),"The next sitter is seated and the stale pose is cleared")

	# --- Keyboard movement releases; interacting again releases --------------------------------
	world.move_player(owner,Vector2.UP,0.1)
	expect(not person.has(SEAT),"Keyboard movement stands the owner up")
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	world.active_tokens[GUEST]=true
	expect(world.act(GUEST,"guest-sit-again",SIT,SITE).ok,"The returning visitor sits again")
	world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(not guest.has(SEAT),"Keyboard movement releases a visitor too")
	stand_at(owner,40.5,33.5)
	app.session._send_snapshot(1)
	app._interact()
	expect(person.has(SEAT),"Owner sits again")
	app._interact()
	expect(not person.has(SEAT),"Interacting again releases the seat")
	expect(person.inventory.wood==wood,"No wood moved during any sit, stand or refused action")

	# --- Undo that would replace an occupied chair is blocked ----------------------------------
	stand_at(owner,45.5,33.5)
	stand_at(GUEST,45.5,33.5)
	expect(world.act(owner,"undo-build","build",UNDO_A,KIND).ok,"Build the chair that will be undone")
	expect(world.act(owner,"undo-move","move_object",UNDO_A,World.key(UNDO_B)).ok and obj(UNDO_B).get("type")==KIND,"Move it so the undo would restore the old tile")
	var summary:=world.undo_summary(owner)
	expect(summary.get("available")==true and not str(summary.get("id","")).is_empty(),"Undo is offered for the move")
	expect(world.act(GUEST,"undo-sit",SIT,UNDO_B).ok and guest.get(SEAT,{}).get("cell")==World.key(UNDO_B),"A visitor sits on the moved chair")
	var undo:=world.act(owner,"undo-busy","undo_build",UNDO_B,str(summary.get("id","")))
	expect(not undo.ok and obj(UNDO_B).get("type")==KIND and obj(UNDO_A).is_empty() and guest.get(SEAT,{}).get("cell")==World.key(UNDO_B),"Undo is refused while the visitor sits and nothing changes")
	world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(world.act(owner,"free-move","move_object",UNDO_B,World.key(UNDO_A)).ok,"Once free, the chair may be moved again")
	undo=world.act(owner,"undo-free","undo_build",UNDO_A,str(world.undo_summary(owner).get("id","")))
	expect(undo.ok and obj(UNDO_B).get("type")==KIND and obj(UNDO_A).is_empty(),"The new unused move can be undone")
	expect(world.act(owner,"final-remove","remove",UNDO_B).ok and obj(UNDO_B).is_empty(),"The free chair can be dismantled")
	stand_at(owner,40.5,33.5)
	expect(world.act(owner,"final-remove-main","remove",SITE).ok and person.inventory.wood==wood+6,"Dismantling refunds the original six wood (the undo chair was already refunded)")
	await finish()
