extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const BENCH:=Vector2i(39,34)
const TABLE:=Vector2i(42,34)
const BLUE:="table_vase_bluebell"
var app
var world:World
var owner:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func widget(id:String)->Control:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func press(id:String)->bool:
	var control:=widget(id) as Button
	if not expect(control!=null and control.visible and not control.disabled,"Enabled control "+id):return false
	control.pressed.emit()
	return true

func stand_near(site:Vector2i)->void:
	var player:Dictionary=world.state.players[owner]
	player.x=site.x+0.5
	player.y=site.y-0.5
	app.session._send_snapshot(1)

func capture(name:String)->void:
	var output:String=app.arg_value("qa-dir","")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TABLE_VASE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	path="user://table-vase-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="table-vase-owner"
	if app.session.host(0,"陶藝師",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var inventory:Dictionary=world.state.players[owner].inventory
	inventory.merge({"wood":80,"stone":5,"clay":4,"chime_herb":1,"bluebell":1,"orange_blossom":1},true)
	world.state.time=720.0
	for tile:Vector2i in [BENCH,TABLE]:world.state.removed[World.key(tile)]=true
	stand_near(TABLE)
	app.session.perform("build",TABLE,"table")
	stand_near(BENCH)
	app.session.perform("build",BENCH,"bench")
	app._interact()
	if not press("WorkbenchRecipe_"+Industry.TABLE_VASE) or not press("CraftRecipe"):
		await finish()
		return
	expect(inventory.get(Industry.TABLE_VASE,0)==1 and inventory.clay==0 and inventory.chime_herb==0,"Craft places one starter bloom in the new vase")
	app._close_modal()
	stand_near(TABLE)
	app._interact()
	if not press("ShellTablePut"):
		await finish()
		return
	var table:Dictionary=world.state.objects[World.key(TABLE)]
	expect(table.items=={Industry.TABLE_VASE:1} and inventory.get(Industry.TABLE_VASE,0)==0,"Display transfers the vase from the bag")
	var picker:=widget("TableVaseBloom") as OptionButton
	if not expect(picker!=null and picker.get_item_metadata(picker.selected)=="bluebell","Available different blooms are offered in the panel"):
		await finish()
		return
	press("TableVaseSwap")
	expect(table.items=={BLUE:1} and inventory.bluebell==0 and inventory.chime_herb==1,"A swap consumes the new flower and returns the old one exactly once")
	await capture("vase-flower-picker")
	app._close_modal()
	app.view.set_process(false)
	app.view.camera=(Vector2(TABLE)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	await capture("vase-on-wood-table")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects[World.key(TABLE)].items=={BLUE:1},"Reload retains the current flower")
	world.add_player("vase-visitor","來客",Vector2(42.5,33.5))
	world.state.players["vase-visitor"].inventory.orange_blossom=1
	expect(not world.act("vase-visitor","swap",Industry.TABLE_VASE_SWAP,TABLE,"orange_blossom").ok,"A visitor cannot swap the owner's flower")
	expect(not world.act(owner,"try-same",Industry.TABLE_VASE_SWAP,TABLE,"bluebell").ok,"Re-selecting the same flower cannot mint a drop")
	expect(not world.act(owner,"try-remove","remove",TABLE).ok,"The vase must be retrieved before dismantle")
	inventory.bluebell=World.ITEM_CATALOG.STACK_CEILING
	expect(not world.act(owner,"try-full",Industry.TABLE_VASE_SWAP,TABLE,"orange_blossom").ok and inventory.orange_blossom==1 and table.items=={BLUE:1},"A full stack rejects the swap without partial mutation")
	inventory.bluebell=0
	var swapped:=world.act(owner,"swap-once",Industry.TABLE_VASE_SWAP,TABLE,"orange_blossom")
	var duplicate:=world.act(owner,"swap-once",Industry.TABLE_VASE_SWAP,TABLE,"orange_blossom")
	expect(swapped.ok and duplicate.ok and inventory.bluebell==1 and inventory.orange_blossom==0,"Retrying the same request returns one flower total")
	app.session._send_snapshot(1)
	app._interact()
	press("ShellTableTake")
	expect(table.items.is_empty() and inventory.get("table_vase_orange",0)==1,"Retrieval returns the filled vase without a duplicate flower")
	await finish()
