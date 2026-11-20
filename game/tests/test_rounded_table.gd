extends SceneTree

const World=preload("res://scripts/world.gd")
const Table=World.INDUSTRY
const SITE:=Vector2i(42,34)
const DEST:=Vector2i(44,35)
const GUEST:="table-guest"
var app
var world:World
var owner:String
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

func widget(name:String)->Control:
	return app.modal.find_child(name,true,false) as Control if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var button:=widget(name) as Button
	if not expect(button!=null and not button.disabled and button.visible,"Available button "+name):return false
	button.pressed.emit()
	return true

func place(item:String)->bool:
	var picker:=widget("RoundedTablePick") as OptionButton
	if not expect(picker!=null,"Table interface has an inventory selector"):return false
	for index in picker.item_count:
		if picker.get_item_metadata(index)==item:
			picker.select(index)
			return press("RoundedTablePut")
	return expect(false,"Inventory selector offers "+item)

func capture(name:String)->void:
	var output:String=app.arg_value("qa-dir","")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	app.view.queue_redraw()
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func standing(at:Vector2)->void:
	var person:Dictionary=world.state.players[owner]
	person.x=at.x
	person.y=at.y
	app.session._send_snapshot(1)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	path="user://rounded-table-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="rounded-table-owner"
	if app.session.host(0,"木工",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":24,"soup":2,"bluebell":1,"stone":1,Table.TABLE_VASE:1},true)
	world.state.time=720.0
	for cell:Vector2i in [SITE,SITE+Vector2i.RIGHT,DEST,DEST+Vector2i.DOWN]:world.state.removed[World.key(cell)]=true
	standing(Vector2(43.5,33.5))
	app._perform_build_action("build",SITE,Table.ROUNDED_TABLE)
	var table:Dictionary=world.state.objects.get(World.key(SITE),{})
	if not expect(table.get("type")==Table.ROUNDED_TABLE,"Normal construction places the round-corner table"):
		await finish()
		return
	expect(person.inventory.wood==12 and world.blocked(SITE) and world.blocked(SITE+Vector2i.RIGHT),"One 12-wood recipe occupies both cells")
	app._select_tool("hoe")
	app._interact()
	if not place("soup") or not place(Table.TABLE_VASE):
		await finish()
		return
	expect(table.items=={"soup":1,Table.TABLE_VASE:1} and (widget("RoundedTablePut") as Button).disabled,"Two distinct objects occupy both spots")
	expect(not world.act(owner,"third",Table.SHELL_PUT,SITE,"soup").ok,"A third item is refused without consuming it")
	expect(not world.act(owner,"stack-stone",Table.SHELL_PUT,SITE,"stone").ok,"A building material is not treated as decor")
	press("RoundedTableSwap1")
	var blue_vase:="table_vase_bluebell"
	expect(table.items=={"soup":1,blue_vase:1} and person.inventory.chime_herb==1,"Changing a vase preserves its neighboring plate")
	await capture("table-two-spots")
	if DisplayServer.get_name()!="headless":
		var scroll:=app.modal.find_children("*","ScrollContainer",true,false).front() as ScrollContainer
		expect(not scroll.get_v_scroll_bar().visible,"Both displayed items and the flower controls fit without scrolling")
	app._close_modal()
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(1,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	await capture("table-in-village")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(World.key(SITE),{}).get("items")==table.items,"Reload preserves the two displayed items")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"共餐角落",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":Table.ROUNDED_TABLE,"x":0,"y":0}],"Capture carries furniture but leaves contents with the original")
	if design.ok:
		standing(Vector2(45.5,35.5))
		var quote:=world.quote_blueprint(owner,design.blueprint,DEST,1)
		var applied:=world.apply_blueprint(owner,"2".repeat(32),design.blueprint,DEST,1,quote.hash)
		var copy:Dictionary=world.state.objects.get(World.key(DEST),{})
		expect(applied.ok and Table.is_vertical(copy) and copy.get("items")=={} and world.blocked(DEST+Vector2i.DOWN),"Rotated copy is empty and occupies its vertical footprint")
	standing(Vector2(43.5,33.5))
	world.add_player(GUEST,"訪客",Vector2(43.5,35.5))
	var guest:Dictionary=world.state.players[GUEST]
	guest.mine_energy=40
	expect(not world.act(GUEST,"take",Table.SHELL_TAKE,SITE+Vector2i.RIGHT,blue_vase).ok,"Guest cannot take decorative objects")
	expect(not world.act(GUEST,"eat-vase",Table.ROUNDED_EAT,SITE,blue_vase).ok,"Guest cannot consume decorative objects")
	var meal:=world.act(GUEST,"eat-once",Table.ROUNDED_EAT,SITE+Vector2i.RIGHT,"soup")
	var retry:=world.act(GUEST,"eat-once",Table.ROUNDED_EAT,SITE+Vector2i.RIGHT,"soup")
	expect(meal.ok and retry.ok and guest.mine_energy==52 and table.items=={blue_vase:1},"Retry eats one portion and grants one stamina recovery")
	expect(not world.act(GUEST,"eat-empty",Table.ROUNDED_EAT,SITE,"soup").ok,"An empty place does not produce another meal")
	expect(not world.act(owner,"remove-full","remove",SITE+Vector2i.RIGHT).ok,"Removal from either half requires clearing the table")
	app.session._send_snapshot(1)
	app._interact()
	press("RoundedTableTake0")
	expect(table.items.is_empty() and int(world.state.players[owner].inventory.get(blue_vase,0))==1,"Owner retrieves the filled vase")
	await finish()

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ROUNDED_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
