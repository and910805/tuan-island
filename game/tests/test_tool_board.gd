extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Fixtures=World.WALL_FIXTURES
const KIND:=Fixtures.TOOL_BOARD
const WRITE:=Fixtures.TOOL_BOARD_WRITE
const OPTIONS:=["","hoe","axe","pick","water","fish","seed"]
const SITE:=Vector2i(42,35)             ## halves at (42,35) and (43,35); walls at y=34
const RIGHT:=Vector2i(43,35)
const MOVED:=Vector2i(46,35)            ## second supported pair, walls at y=34
const BROKEN:=Vector2i(50,35)           ## only the left wall is own, right wall missing
const FOREIGN:=Vector2i(51,35)          ## right wall belongs to somebody else
const OWNER_NAME:="木工阿福"
const GUEST:="tool-board-visitor"
const GUEST_NAME:="路過的阿蓮"
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
	print("TOOL_BOARD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func tools(tile:=SITE)->Array:
	return world.state.objects.get(World.key(World.station_anchor(world.state.objects,tile)),{}).get(Fixtures.TOOL_BOARD_FIELD,["",""])

func write(request:String,extra:String,tile:=SITE,who:="")->Dictionary:
	return world.act(owner if who.is_empty() else who,request,WRITE,tile,extra)

func stand(x:float,y:float,who:="")->void:
	var person:Dictionary=world.state.players[owner if who.is_empty() else who]
	person.x=x
	person.y=y

func focus(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(1.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

## Selects an option on ToolBoardPickerN by its String metadata (not by index/label).
func choose(slot:int,value:String)->bool:
	var picker:=widget("ToolBoardPicker%d"%slot) as OptionButton
	if not expect(picker!=null,"Picker %d exists"%slot):return false
	for i in picker.item_count:
		if str(picker.get_item_metadata(i))==value:
			picker.select(i)
			picker.item_selected.emit(i)
			return true
	return expect(false,"Picker %d offers option '%s'"%[slot,value])

func picked(slot:int)->String:
	var picker:=widget("ToolBoardPicker%d"%slot) as OptionButton
	if picker==null or picker.selected<0:return "<none>"
	var meta=picker.get_item_metadata(picker.selected)
	return meta if meta is String else "<not string>"

func press_save(slot:int)->bool:
	var button:=widget("ToolBoardSave%d"%slot) as Button
	if not expect(button!=null and not button.disabled,"Save button %d is available"%slot):return false
	button.pressed.emit()
	return true

func open_from(tile:Vector2i)->void:
	app._close_modal()
	stand(float(tile.x)+0.5,float(tile.y)+1.3)
	app.session._send_snapshot(1)
	app._interact()

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://tool-board-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="tool-board-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":60,"copper_ingot":10},true)
	person.inventory.erase("hoe")   # tools are optional labels: nothing real is needed or charged
	world.state.time=720.0
	for base in [SITE,MOVED,BROKEN,FOREIGN]:
		for target in [base,base+Vector2i.RIGHT,base+Vector2i.UP,base+Vector2i.UP+Vector2i.RIGHT]:
			world.state.removed[World.key(target)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(42.5,36.3))
	stand(42.5,36.3)
	app.session._send_snapshot(1)

	# Contract: constants, exact recipe.
	expect(KIND=="wall_tool_board" and KIND in Fixtures.KINDS,"Tool board is a registered wall fixture")
	expect(WRITE=="tool_board_write","Write request name is tool_board_write")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("wood")==8 and World.BUILD[KIND].get("copper_ingot")==2 and World.BUILD[KIND].size()==3,"Recipe is exactly 8 wood and 2 copper ingot plus the name")
	expect(not str(World.BUILD[KIND].get("name","")).is_empty(),"The board has a display name")

	# Missing and foreign wall: refused, nothing charged, nothing placed.
	var wood:int=person.inventory.wood
	var copper:int=person.inventory.copper_ingot
	expect(not world.act(owner,"no-wall","build",SITE,KIND).ok and obj().is_empty() and obj(RIGHT).is_empty(),"No wall: refused")
	expect(person.inventory.wood==wood and person.inventory.copper_ingot==copper,"No wall: no material lost")
	stand(50.5,36.3)
	expect(world.act(owner,"wall-b","build",BROKEN+Vector2i.UP,"wall").ok,"Builds only the left wall of the broken site")
	expect(not world.act(owner,"half-wall","build",BROKEN,KIND).ok and obj(BROKEN).is_empty() and obj(BROKEN+Vector2i.RIGHT).is_empty(),"Only one supported half: refused, nothing placed")
	stand(51.5,36.3)
	if not expect(world.act(owner,"wall-f1","build",FOREIGN+Vector2i.UP,"wall").ok and world.act(owner,"wall-f2","build",FOREIGN+Vector2i.UP+Vector2i.RIGHT,"wall").ok,"Builds two walls at the foreign site"):
		await finish()
		return
	world.state.objects[World.key(FOREIGN+Vector2i.UP+Vector2i.RIGHT)].owner=GUEST
	wood=person.inventory.wood
	copper=person.inventory.copper_ingot
	expect(not world.act(owner,"foreign-wall","build",FOREIGN,KIND).ok and obj(FOREIGN).is_empty() and obj(FOREIGN+Vector2i.RIGHT).is_empty(),"A wall owned by someone else: refused")
	expect(person.inventory.wood==wood and person.inventory.copper_ingot==copper,"Refused builds never charge materials")
	stand(42.5,36.3)
	person.inventory.wood=7
	expect(world.act(owner,"wall-a","build",SITE+Vector2i.UP,"wall").ok and world.act(owner,"wall-a2","build",RIGHT+Vector2i.UP,"wall").ok,"Builds two own wall sections at the main site")
	person.inventory.wood=7
	person.inventory.copper_ingot=2
	expect(not world.act(owner,"poor-wood","build",SITE,KIND).ok and person.inventory.wood==7 and person.inventory.copper_ingot==2 and obj().is_empty(),"7 wood is not enough, nothing spent")
	person.inventory.wood=8
	person.inventory.copper_ingot=1
	expect(not world.act(owner,"poor-copper","build",SITE,KIND).ok and person.inventory.wood==8 and person.inventory.copper_ingot==1 and obj().is_empty(),"1 copper ingot is not enough, nothing spent")
	person.inventory.wood=20
	person.inventory.copper_ingot=5
	app.session._send_snapshot(1)

	# Build through the real hand action.
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Hand placement builds the board for its owner"):
		await finish()
		return
	expect(person.inventory.wood==12 and person.inventory.copper_ingot==3,"Craft spends exactly 8 wood and 2 copper ingot")
	expect(not obj(RIGHT).is_empty() and World.station_anchor(world.state.objects,RIGHT)==SITE and World.station_anchor(world.state.objects,SITE)==SITE,"Both halves share the left cell as anchor")
	expect(not world.blocked(SITE) and not world.blocked(RIGHT),"The area below the board stays walkable")
	expect(tools()==["",""] and tools(RIGHT)==["",""],"New board defaults to two empty slots, visible from both halves")

	# State from both halves, bad payloads, range, guest.
	for half in [SITE,RIGHT]:
		var other:=RIGHT if half==SITE else SITE
		stand(42.5+float(half.x-SITE.x),36.3)
		expect(write("set-%d"%half.x,"0:hoe",half).ok and tools(SITE)==["hoe",""] and tools(RIGHT)==["hoe",""],"Writing via %s updates the shared state"%str(half))
		expect(write("set2-%d"%half.x,"1:fish",other).ok and tools(SITE)==["hoe","fish"],"Writing via the other half updates the same anchor")
		expect(write("clear-%d"%half.x,"0:",half).ok and tools()==["","fish"] and write("clear2-%d"%half.x,"1:",half).ok and tools()==["",""],"An empty option clears a slot")
	expect(obj(RIGHT).get("tool_board_tools")==null or obj(RIGHT).get("tool_board_tools")==obj().get("tool_board_tools"),"The state lives on the anchor, not as a diverging copy on the second half")
	var good:=["hoe","fish"]
	expect(write("good","0:hoe").ok and write("good2","1:fish").ok and tools()==good,"Configured choices are stored as obj.tool_board_tools")
	inventory_unchanged(person,12,3,"Selecting tools charges nothing and needs no real tool")
	for option in OPTIONS:
		expect(write("opt-"+option,"0:"+option).ok and tools()[0]==option,"Option '%s' is valid"%option)
	expect(write("back","0:hoe").ok and tools()==good,"Restores the configured choices")
	var bad:=["","0","2:hoe","-1:hoe","0:sword","0:HOE","0: hoe","0:hoe:fish","0:hoe,1:fish","hoe","a:hoe","1.0:hoe",":hoe","0:hoe\n","00:hoe","0:hoe "]
	for extra in bad:
		expect(not write("bad-"+extra,extra).ok and tools()==good,"Wrong extra '%s' is refused and changes nothing"%extra.c_escape())
	expect(not write("guest-write","0:axe",SITE,GUEST).ok and not write("guest-write2","1:pick",RIGHT,GUEST).ok and tools()==good,"A nearby guest cannot edit from either half")
	stand(48.5,40.5)
	expect(not write("far","0:axe").ok and tools()==good,"The owner out of reach cannot edit")
	stand(42.5,36.3)
	app.session._send_snapshot(1)

	# Real UI from either half, owner edit.
	app._select_tool("hoe")
	app.view.set_process(false)
	focus(SITE)
	for half in [SITE,RIGHT]:
		open_from(half)
		expect(is_instance_valid(app.modal) and app.modal.visible and widget("ToolBoardPicker0")!=null and widget("ToolBoardPicker1")!=null and widget("ToolBoardSave0")!=null and widget("ToolBoardSave1")!=null,"_interact on half %s opens the editor with both pickers and saves"%str(half))
		expect(picked(0)=="hoe" and picked(1)=="fish","Pickers show the saved choices (String metadata) on half %s"%str(half))
	var picker0:=widget("ToolBoardPicker0") as OptionButton
	if picker0!=null:
		var metas:=[]
		for i in picker0.item_count:metas.append(picker0.get_item_metadata(i))
		expect(metas==OPTIONS or (metas.size()==OPTIONS.size() and OPTIONS.all(func(o):return o in metas)),"Picker offers exactly the seven options as String metadata")
		expect(metas.all(func(m):return m is String),"Every option metadata is a String")
		var missing:Array[String]=[]
		for i in picker0.item_count:
			if not str(metas[i]).is_empty() and picker0.get_item_icon(i)==null:missing.append(metas[i])
		expect(missing.is_empty(),"Each tool option has a real pixel icon: "+str(missing))
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"工具板",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Blueprint captures both halves as one blank board")
	if design.ok:
		expect(not World.BLUEPRINT_DESIGN.rotate(design.blueprint,1,World.BUILD,World.NAMES).ok,"A quarter turn cannot mount the horizontal board vertically")
	await frame("tool-board-editor")
	if choose(0,"axe") and press_save(0):
		expect(tools()==["axe","fish"],"Slot 0 saves through the real button")
	open_from(RIGHT)
	if choose(1,"") and press_save(1):
		expect(tools()==["axe",""],"Slot 1 can be cleared through the real button")
	open_from(SITE)
	if choose(0,"hoe") and choose(1,"fish"):
		press_save(0)
		press_save(1)
	expect(tools()==good,"Owner restores hoe + fish through the UI")
	app._close_modal()
	app.view.camera=(Vector2(SITE)+Vector2(1.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	await frame("tool-board-wall")

	# Guest reads, does not edit.
	var original:String=app.session.own_id
	app.set_process(false)
	app._close_modal()
	stand(42.5,36.3,GUEST)
	app.session.peers[2]=GUEST
	app.session._send_snapshot(1)
	app.session.peers.erase(2)
	app.session.own_id=Session._public_actor(GUEST)
	app._interact()
	expect(is_instance_valid(app.modal) and app.modal.visible,"A guest can open the board for reading")
	expect(widget("ToolBoardSave0")==null and widget("ToolBoardSave1")==null,"The guest view has no save buttons")
	for slot in 2:
		var p:=widget("ToolBoardPicker%d"%slot) as OptionButton
		expect(p==null or p.disabled,"The guest picker %d is absent or disabled"%slot)
	await frame("tool-board-guest")
	app._close_modal()
	app.session.own_id=original
	app.set_process(true)
	expect(tools()==good,"Guest reading leaves state alone")

	# Reload: configured, then default.
	expect(world.save(),"The world saves")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"Primary save reloads")
	var anchor:Dictionary=saved.state.objects.get(World.key(SITE),{})
	expect(anchor.get("type")==KIND and anchor.get("tool_board_tools")==good and World.station_anchor(saved.state.objects,RIGHT)==SITE,"Reload keeps type, configured tools and shared anchor")
	expect(valid(world.state),"Live state passes save validation")
	var forged:=world.state.duplicate(true)
	forged.objects[World.key(SITE)].tool_board_tools=["sword",""]
	expect(not valid(forged),"Validation rejects an unknown tool")
	forged=world.state.duplicate(true)
	forged.objects[World.key(SITE)].tool_board_tools=["hoe"]
	expect(not valid(forged),"Validation rejects a wrong slot count")
	var unsupported:=world.state.duplicate(true)
	unsupported.objects.erase(World.key(SITE+Vector2i.UP))
	expect(not valid(unsupported),"A saved board without its wall is rejected")
	expect(write("clear-all-1","0:").ok and write("clear-all-2","1:").ok and world.save(),"Default (cleared) board saves")
	var defaults:=World.new()
	expect(defaults.load_world(path) and defaults.state.objects.get(World.key(SITE),{}).get("tool_board_tools",["",""])==["",""],"Default board reloads as two empty slots")
	expect(write("reconfig","0:hoe").ok and write("reconfig2","1:fish").ok and tools()==good,"Choices reconfigured")

	# Support protection and move.
	var refused:=world.act(owner,"remove-wall","remove",SITE+Vector2i.UP)
	expect(not refused.ok and refused.get("message","")==Fixtures.REMOVE_MESSAGE and world.state.objects.has(World.key(SITE+Vector2i.UP)),"Left wall cannot be removed while the board hangs on it")
	refused=world.act(owner,"remove-wall2","remove",RIGHT+Vector2i.UP)
	expect(not refused.ok and world.state.objects.has(World.key(RIGHT+Vector2i.UP)),"Right wall is protected too")
	stand(44.5,36.5)
	expect(not world.act(owner,"move-bad","move_object",SITE,World.key(Vector2i(44,35))).ok and obj().get("type")==KIND and tools()==good,"Moving onto a half-supported pair is refused and keeps everything")
	stand(46.5,36.3)
	expect(world.act(owner,"wall-m1","build",MOVED+Vector2i.UP,"wall").ok and world.act(owner,"wall-m2","build",MOVED+Vector2i.UP+Vector2i.RIGHT,"wall").ok,"Builds the two target walls")
	stand(44.5,36.5)
	expect(world.act(owner,"move","move_object",SITE,World.key(MOVED)).ok and obj().is_empty() and obj(RIGHT).is_empty(),"Moves to two supported cells")
	expect(obj(MOVED).get("type")==KIND and tools(MOVED)==good and tools(MOVED+Vector2i.RIGHT)==good and World.station_anchor(world.state.objects,MOVED+Vector2i.RIGHT)==MOVED,"Moving preserves the choices on the new anchor")
	expect(world.act(owner,"old-wall","remove",SITE+Vector2i.UP).ok,"The old wall is free once the board left")

	# Remove refund.
	stand(46.5,36.3)
	wood=person.inventory.wood
	copper=person.inventory.copper_ingot
	expect(world.act(owner,"remove","remove",MOVED+Vector2i.RIGHT).ok and obj(MOVED).is_empty() and obj(MOVED+Vector2i.RIGHT).is_empty(),"Removing by either half dismantles the whole board")
	expect(person.inventory.wood==wood+8 and person.inventory.copper_ingot==copper+2,"Removal refunds exactly one recipe")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,MOVED)
		if expect(quote.ok,"A blueprint will also use both supporting wall sections"):
			var rebuilt:=world.apply_blueprint(owner,"3".repeat(32),design.blueprint,MOVED,0,quote.hash)
			expect(rebuilt.ok and obj(MOVED).get("type")==KIND and tools(MOVED)==["",""] and World.station_anchor(world.state.objects,MOVED+Vector2i.RIGHT)==MOVED,"The blueprint builds one supported board with two empty hooks")
	await finish()

func inventory_unchanged(person:Dictionary,wood:int,copper:int,label:String)->void:
	expect(person.inventory.wood==wood and person.inventory.copper_ingot==copper and not person.inventory.has("hoe"),label)
