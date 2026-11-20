extends SceneTree

const World=preload("res://scripts/world.gd")
const Sign=World.WELCOME_SIGN
const KIND:=World.WALL_FIXTURES.HOME_SIGN
const SITE:=Vector2i(42,35)
const COPY:=Vector2i(43,35)
const SUPPORT:=SITE+Vector2i.UP
const AUTHOR:="木工"
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

func widget(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null

func frame(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	app.view.queue_redraw()
	await create_timer(0.34).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("HANDCARVED_SIGN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func write(request:String,lines:Array,tile:=SITE,who:="")->Dictionary:
	return world.act(owner if who.is_empty() else who,request,Sign.WRITE,tile,JSON.stringify(lines))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://handcarved-sign-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="handcarved-sign-%d"%Time.get_ticks_usec()
	if app.session.host(0,AUTHOR,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=42.5
	person.y=36.3
	person.inventory.merge({"wood":40},true)
	world.state.time=720.0
	for target in [SITE,COPY,SUPPORT,COPY+Vector2i.UP]:
		world.state.removed[World.key(target)]=true
	app.session._send_snapshot(1)

	# Craft: needs the owner's own wall directly north and exactly 5 wood.
	expect(KIND=="handcarved_home_sign" and KIND in World.WALL_FIXTURES.KINDS,"Sign is registered as a wall fixture")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("wood")==5 and World.BUILD[KIND].size()==2,"Recipe is only 5 wood plus its name")
	var before:=int(person.inventory.wood)
	expect(not world.act(owner,"unmounted","build",SITE,KIND).ok and person.inventory.wood==before and obj().is_empty(),"Without a north wall the build is refused and nothing is charged")
	expect(world.act(owner,"wall","build",SUPPORT,"wall").ok and world.act(owner,"wall2","build",COPY+Vector2i.UP,"wall").ok,"Builds two real owned wall sections")
	person.inventory.wood=4
	expect(not world.act(owner,"poor","build",SITE,KIND).ok and person.inventory.wood==4 and obj().is_empty(),"Four wood is not enough and nothing is spent")
	person.inventory.wood=5
	app.session._send_snapshot(1)
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND,"Ordinary hand placement crafts the sign on the wall"):
		await finish()
		return
	expect(person.inventory.wood==0 and obj().get("owner")==owner and not world.blocked(SITE),"Craft spends exactly 5 wood and the front stays walkable")
	expect(obj().get("author")==AUTHOR,"The builder's name is stored as obj.author")

	# UI write by the owner.
	app._select_tool("hoe")
	app._interact()
	var author_label:=widget("HomeSignAuthor") as Label
	expect(author_label!=null and AUTHOR in author_label.text,"Owner panel names the author")
	var title:="風鈴渡口木工的小小山居屋"
	var copy:=[title,"歡迎回家，慢慢坐。","門口的燈一直亮著。"]
	for i in 3:
		var field:=widget("WelcomeSignField%d"%i) as LineEdit
		if expect(field!=null and field.max_length==Sign.LIMITS[i],"Field %d is bounded by the existing limit"%i):field.text=copy[i]
	await frame("handcarved-sign-editor")
	var save:=widget("WelcomeSignSave") as Button
	if expect(save!=null and not save.disabled,"Save button is enabled"):save.pressed.emit()
	expect(title.length()==12 and obj().get("welcome")==copy,"Exactly 12 title characters are saved through the real action")
	expect(obj().get("author")==AUTHOR,"Editing the text does not change the author")
	app._close_modal()
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	await frame("handcarved-sign-wall")

	# Invalid, far and visitor writes leave the old text intact.
	var long_line:="長".repeat(25)
	for data in [["太".repeat(13),"",""],["","跨\n行",""],["",long_line,""],["","",long_line],["缺欄位"],["a","b","c","d"],[1,"b","c"]]:
		expect(not write("invalid-%d"%checks,data).ok,"Invalid text or shape is refused")
	expect(not world.act(owner,"not-json",Sign.WRITE,SITE,"not json").ok,"Non-JSON payloads are refused")
	expect(write("max-lines",[title,"二".repeat(24),"三".repeat(24)]).ok,"The 12/24/24 limits are inclusive")
	expect(write("restore",copy).ok and obj().welcome==copy,"Owner can restore the intended text")
	world.add_player("handcarved-visitor","來客",Vector2(42.5,36.3))
	expect(not write("visitor-write",["改名","",""],SITE,"handcarved-visitor").ok and obj().welcome==copy and obj().author==AUTHOR,"A nearby visitor cannot edit text or author")
	person.x=48.5
	person.y=40.5
	expect(not write("far-write",["遠端","",""]).ok and obj().welcome==copy,"The owner cannot edit from outside reach")
	person.x=42.5
	person.y=36.3
	app.session._send_snapshot(1)

	# Visitor view has no fields and shows author and text.
	var original:String=app.session.own_id
	app.session.own_id="handcarved-visitor"
	app.LifeTasks.welcome_sign(app,SITE,app.session.snapshot.objects[World.key(SITE)])
	var read_title:=widget("WelcomeInnName") as Label
	var read_author:=widget("HomeSignAuthor") as Label
	expect(read_title!=null and read_title.text==title and read_author!=null and AUTHOR in read_author.text,"Visitor reads title and author")
	expect(widget("WelcomeSignField0")==null and widget("WelcomeSignField1")==null and widget("WelcomeSignField2")==null and widget("WelcomeSignSave")==null,"Visitor view has no editable fields or save button")
	await frame("handcarved-sign-visitor")
	app._close_modal()
	app.session.own_id=original

	# Reload.
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"The world file reloads from the primary save")
	var loaded:Dictionary=saved.state.objects.get(World.key(SITE),{})
	expect(loaded.get("type")==KIND and loaded.get("welcome")==copy and loaded.get("author")==AUTHOR,"Reload retains type, text and author")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.objects.erase(World.key(SUPPORT))
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A saved sign without its north wall is rejected")

	# Blueprint captures furniture without personal text.
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"門牌",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Blueprint carries the sign as plain furniture")
	var dump:=JSON.stringify(design)
	expect(not (title in dump) and not (copy[1] in dump) and not (AUTHOR in dump),"Blueprint leaks neither text nor author")

	# Support protection and move.
	var refused:=world.act(owner,"remove-wall","remove",SUPPORT)
	expect(not refused.ok and refused.get("message","")==World.WALL_FIXTURES.REMOVE_MESSAGE and world.state.objects.has(World.key(SUPPORT)),"Removing the supporting wall is refused while the sign hangs on it")
	expect(world.act(owner,"move","move_object",SITE,World.key(COPY)).ok and obj(COPY).get("welcome")==copy and obj(COPY).get("author")==AUTHOR,"Moving to another owned wall keeps text and author")
	expect(world.act(owner,"remove","remove",COPY).ok and person.inventory.wood==5 and obj(COPY).is_empty(),"Removing the sign refunds its 5 wood")
	expect(world.act(owner,"wall-after","remove",SUPPORT).ok,"The wall can be removed once the sign is gone")
	await finish()
