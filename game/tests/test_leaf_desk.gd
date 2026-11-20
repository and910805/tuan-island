extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.LEAF_DESK
const FIELD:=Industry.DESK_DRAFT_FIELD
const SITE:=Vector2i(40,35)
const END:=SITE+Vector2i.RIGHT
const COPY:=Vector2i(43,35)
const DRAFT:="明早到渡口集合，記得帶一盞燈。"
var app
var world:World
var owner:String
var path:String
var output:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(label)
	return success

func widget(name:String)->Node:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var control:=widget(name) as Button
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func frame(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.34).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LEAF_DESK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func at(player:Dictionary,point:Vector2)->void:
	player.x=point.x
	player.y=point.y

func type_text(field:LineEdit,value:String)->void:
	field.text=value
	field.text_changed.emit(value)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://leaf-desk-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="leaf-desk-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":28,"hardwood":8},true)
	world.state.time=720.0
	at(person,Vector2(41.5,36.4))
	for tile in [SITE,END,COPY,COPY+Vector2i.DOWN]:
		world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	app._perform_build_action("build",SITE,KIND)
	if not expect(world.state.objects.get(World.key(SITE),{}).get("type")==KIND,"Normal build menu places the desk"):
		await finish()
		return
	expect(world.blocked(SITE) and world.blocked(END) and World.station_anchor(world.state.objects,END)==SITE,"The desk is solid and both halves link to its anchor")
	expect(person.inventory.wood==14 and person.inventory.hardwood==4,"One desk charges the plan materials")
	app._select_tool("hoe")
	await frame("leaf-desk-room")
	app._interact()
	var input:=widget("LeafDeskDraft") as LineEdit
	if not expect(input!=null and input.text.is_empty() and input.max_length==120,"Interact from the far half opens a 120-character editor"):
		await finish()
		return
	type_text(input,DRAFT)
	expect(not person.has(FIELD) and world.state.get("island_notes",[]).is_empty(),"Typing has no server or public board effect")
	press("LeafDeskSave")
	expect(person.get(FIELD)==DRAFT and world.state.get("island_notes",[]).is_empty(),"The explicit save stores only a private draft")
	expect((widget("LeafDeskSave") as Button).disabled,"Save acknowledges the stored version")
	await frame("leaf-desk-draft")
	press("LeafDeskJournal")
	expect(is_instance_valid(app.modal) and widget("LeafDeskDraft")==null and person.get(FIELD)==DRAFT,"Opens the actual journal without clearing or publishing the draft")
	expect(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.begins_with("島民手冊")),"Journal title is presented")
	app._close_modal()
	app.LifeTasks.island_notes(app)
	press("IslandNoteLoadDeskDraft")
	var public_editor:=widget("IslandNoteDraft") as LineEdit
	expect(public_editor!=null and public_editor.text==DRAFT and world.state.get("island_notes",[]).is_empty(),"Bringing in a private draft only fills the editor")
	app._close_modal()
	app._interact()
	input=widget("LeafDeskDraft")
	expect(input!=null and input.text==DRAFT,"Reopening the editor reads the saved draft")
	app._close_modal()
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.players[owner].get(FIELD)==DRAFT and loaded.state.objects.has(World.key(END)),"Restart retains the draft and both desk parts")
	var visitor:="leaf-desk-visitor"
	world.add_player(visitor,"訪客",Vector2(41.5,36.3))
	var outsider:Dictionary=app.session.public_state("home",visitor)
	var hashed_owner:String=owner.sha256_text().left(16)
	expect(not outsider.players[hashed_owner].has(FIELD),"A guest snapshot does not expose the owner's draft")
	expect(world.act(visitor,"visitor-draft",Industry.DESK_DRAFT_ACTION,END,"訪客的草稿").ok and person.get(FIELD)==DRAFT,"Guest can use the desk for their own independent draft")
	expect(not world.act(owner,"unrelated",Industry.DESK_DRAFT_ACTION,END+Vector2i.DOWN,"錯位置").ok,"A draft requires an actual desk")
	expect(not world.act(owner,"long",Industry.DESK_DRAFT_ACTION,END,"葉".repeat(121)).ok and person.get(FIELD)==DRAFT,"Oversized text leaves the last draft intact")
	var malformed:=world.state.duplicate(true)
	malformed.players[owner][FIELD]="換行\n文字"
	expect(not World.SAVE_SCHEMA.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Invalid drafts fail save validation")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"落葉書桌",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"A blueprint keeps the furniture and never embeds drafts")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,COPY,1)
		if expect(quote.ok,"The 90-degree layout quotes successfully"):
			expect(world.apply_blueprint(owner,"f".repeat(32),design.blueprint,COPY,1,quote.hash).ok and Industry.is_vertical(world.state.objects[World.key(COPY)]),"Rotating a blueprint places the two vertical parts")
		at(world.state.players[owner],Vector2(43.5,37.4))
		app.session._send_snapshot(1)
		app._interact()
		input=widget("LeafDeskDraft")
		expect(input!=null and input.text==DRAFT,"The same draft is available from another desk")
		if input!=null:
			type_text(input,"")
			press("LeafDeskSave")
			expect(not world.state.players[owner].has(FIELD) and world.state.players[visitor].get(FIELD)=="訪客的草稿","Clearing the draft affects only the active player")
	await finish()
