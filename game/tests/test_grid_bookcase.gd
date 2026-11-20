extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Village=World.Village
const Design=preload("res://scripts/blueprint_design.gd")
const Catalog=preload("res://scripts/resident_story_catalog.gd")
const KIND:="grid_bookcase"
const SITE:=Vector2i(40,34)          ## vertical by default: (40,34) and (40,35)
const SECOND:=SITE+Vector2i.DOWN
const MOVED:=Vector2i(43,34)
const ROTATED:=Vector2i(46,34)       ## blueprint target; rotated -> horizontal (46,34),(47,34)
const GUEST:="grid-bookcase-guest"
const OWNER_NAME:="書櫃主人"
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
	print("GRID_BOOKCASE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func widget(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null

func press(id:String)->bool:
	var button:=widget(id) as Button
	if not expect(button!=null and not button.disabled,"Button is available: "+id):return false
	button.pressed.emit()
	return true

func story_buttons()->Array:
	var names:=[]
	if is_instance_valid(app.modal):
		for button in app.modal.find_children("BookcaseStory_*","Button",true,false):names.append(str(button.name))
	names.sort()
	return names

## Every visible string in the open modal (labels and buttons), without assuming layout.
func modal_text()->String:
	var text:=""
	if not is_instance_valid(app.modal):return text
	for node in app.modal.find_children("*","Label",true,false):text+=str(node.text)+"\n"
	for node in app.modal.find_children("*","Button",true,false):text+=str(node.text)+"\n"
	return text

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(0.5,1.0))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func hub_open()->bool:
	return widget("BookcaseStories")!=null and widget("BookcaseMemories")!=null and widget("BookcaseHistory")!=null

## Opens the shelf with the real _interact, standing beside the given cell.
func open_from(cell:Vector2i)->void:
	stand_at(app.session.peers[1],float(cell.x)+1.5,float(cell.y)+0.5)
	app.session._send_snapshot(1)
	app._close_modal()
	app._interact()

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://grid-bookcase-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="grid-bookcase-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,41.5,34.5)
	person.inventory.merge({"wood":60,"fiber":12},true)
	world.state.time=720.0
	for tile in [SITE,SECOND,MOVED,MOVED+Vector2i.DOWN,ROTATED,ROTATED+Vector2i.RIGHT,SITE+Vector2i.RIGHT,SECOND+Vector2i.RIGHT]:
		world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,"路過的讀者",Vector2(41.5,35.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Contract: constant, recipe ------------------------------------------------------------
	expect(Industry.GRID_BOOKCASE==KIND,"INDUSTRY.GRID_BOOKCASE is grid_bookcase")
	expect(World.BUILD.has(KIND) and not str(World.BUILD[KIND].get("name","")).is_empty(),"The bookcase has a display name")
	expect(World.BUILD[KIND].get("wood")==16 and World.BUILD[KIND].get("fiber")==4 and World.BUILD[KIND].size()==3,"Recipe is exactly 16 wood and 4 fiber plus the name")

	# --- Insufficient materials: nothing built, nothing charged --------------------------------
	var saved_bag:Dictionary=person.inventory.duplicate(true)
	person.inventory.wood=15
	expect(not world.act(owner,"poor-wood","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==15 and person.inventory.fiber==12,"15 wood is refused and nothing is spent")
	person.inventory.wood=60
	person.inventory.fiber=3
	expect(not world.act(owner,"poor-fiber","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==60 and person.inventory.fiber==3,"3 fiber is refused and nothing is spent")
	person.inventory.fiber=12
	expect(person.inventory.wood==saved_bag.wood and person.inventory.fiber==saved_bag.fiber,"Refused attempts leave the bag as it was")

	# --- Normal build: spends the recipe, vertical by default, two solid cells -----------------
	app._select_tool("hoe")
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the bookcase for its owner"):
		await finish()
		return
	expect(person.inventory.wood==44 and person.inventory.fiber==8,"Building spends exactly 16 wood and 4 fiber")
	expect(Industry.is_vertical(obj()),"A normal build is vertical by default")
	expect(obj(SECOND).get("type")==KIND,"The second half is the same bookcase, directly below")
	expect(world.blocked(SITE) and world.blocked(SECOND),"Both cells are solid")
	expect(World.station_anchor(world.state.objects,SITE)==SITE and World.station_anchor(world.state.objects,SECOND)==SITE,"Both halves resolve to one conventional station anchor")
	expect(not world.blocked(SITE+Vector2i.RIGHT) and not world.blocked(SECOND+Vector2i.RIGHT),"The reader's side stays walkable")
	expect(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The world with a bookcase passes save validation")
	focus_camera(SITE)
	app.view.set_process(false)
	await capture("grid-bookcase-placed")

	# --- Fixtures: one completed chapter, everything else untouched ---------------------------
	person.stories.aru=1
	guest.stories.milu=1
	var owner_beats:Array=Catalog.available_beats(world.state,owner)
	var guest_beats:Array=Catalog.available_beats(world.state,GUEST)
	var stories_before:=var_to_str(person.stories)
	var person_shape:=person.keys()
	person_shape.sort()
	var guest_stories_before:=var_to_str(guest.stories)
	var world_shape:=world.state.keys()
	world_shape.sort()

	# --- Real _interact from EITHER half opens the hub, and opening alone changes nothing ------
	for half in [SITE,SECOND]:
		open_from(half)
		expect(is_instance_valid(app.modal) and app.modal.visible and hub_open(),"_interact beside half %s opens the bookcase hub"%str(half))
		expect(var_to_str(person.stories)==stories_before,"Opening from half %s does not change the story record"%str(half))
	await capture("grid-bookcase-hub")
	expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect()),"The hub fits inside the viewport")

	# --- 已讀故事: completed chapters only ------------------------------------------------------
	if press("BookcaseStories"):
		expect("已讀故事" in modal_text(),"The stories page is titled 已讀故事")
		expect(story_buttons()==["BookcaseStory_aru_0"],"Owner with one completed aru chapter sees exactly BookcaseStory_aru_0")
		var text:=modal_text()
		for resident in Village.NPCS:
			var stage:=int(person.stories.get(resident,0))
			for index in range(stage,Village.QUESTS[resident].size()):
				expect(not (str(Village.QUESTS[resident][index].title) in text),"Uncompleted chapter %s_%d is not rendered"%[resident,index])
		expect(widget("BookcaseBack")!=null,"The stories page offers BookcaseBack")
		await capture("grid-bookcase-stories")
		# Reading a story is read-only.
		if press("BookcaseStory_aru_0"):
			expect(str(Village.QUESTS.aru[0].line) in modal_text(),"The completed chapter displays its story text")
			expect(var_to_str(person.stories)==stories_before and int(person.stories.aru)==1,"Reading a story neither advances nor rewrites the story record")
			expect(Catalog.available_beats(world.state,owner)==owner_beats,"Reading a story does not unlock resident memories")
			await capture("grid-bookcase-story-detail")
			if press("BookcaseBack"):expect(story_buttons()==["BookcaseStory_aru_0"],"The story returns to the list")
			if press("BookcaseBack"):expect(hub_open() and obj().get("type")==KIND,"The list returns to the shelf")

	# --- 居民回憶: existing resident_memories, personal snapshot --------------------------------
	if press("BookcaseMemories"):
		expect(widget("BookcaseStories")==null,"The memories page replaces the hub")
		expect(app.session.snapshot.get("resident_memories",[])==owner_beats,"The snapshot memories are the owner's own list")
		var memory_text:=modal_text()
		expect("居民回憶" in memory_text and widget("BookcaseBack")!=null,"The memories page returns to the bookcase")
		for resident in Catalog.RESIDENTS.values():
			for beat in resident.beats:
				if not owner_beats.has(beat.id):expect(not (str(beat.local_work) in memory_text),"Memory %s that is not in the personal snapshot stays hidden"%beat.id)
		await capture("grid-bookcase-memories")
		expect(var_to_str(person.stories)==stories_before,"Viewing memories does not touch the story record")
		if press("BookcaseBack"):expect(hub_open(),"The memories page returns to the hub")

	# --- 歷史: existing local HistoryUI journal --------------------------------------------------
	if press("BookcaseHistory"):
		expect(is_instance_valid(app.modal) and str(app.modal.get_meta("history_mode",""))=="journal","BookcaseHistory opens the existing HistoryUI journal")
		await capture("grid-bookcase-history")
		if press("BookcaseBack"):expect(hub_open(),"The history journal returns to the hub")
		expect(obj().get("type")==KIND,"Closing the journal leaves the bookcase in place")

	# --- Guest reads their OWN record, never the owner's ------------------------------------------
	# Run the host's snapshot builder with the guest as recipient.
	app.session.peers[1]=GUEST
	guest.stories.milu=0
	app.session._send_snapshot(1)
	open_from(SECOND)
	if expect(hub_open(),"A guest can open the hub from the lower half"):
		press("BookcaseStories")
		expect(story_buttons().is_empty(),"A guest with no completed chapters sees none of the owner's stories")
		guest.stories.milu=1
		open_from(SECOND)
		press("BookcaseStories")
		expect(story_buttons()==["BookcaseStory_milu_0"],"A guest sees only their own completed chapter")
		expect(app.session.snapshot.get("resident_memories",[])==guest_beats,"The guest receives their own memories")
		await capture("grid-bookcase-guest-stories")
	expect(var_to_str(guest.stories)==guest_stories_before,"Reading never writes to the guest's record")
	expect(var_to_str(person.stories)==stories_before,"Reading never writes to the owner's record")
	app._close_modal()
	app.session.peers[1]=owner
	app.session._send_snapshot(1)

	# --- Nothing new was added to the player or world -------------------------------------------
	var shape_after:=person.keys()
	shape_after.sort()
	var world_after:=world.state.keys()
	world_after.sort()
	expect(shape_after==person_shape,"The player record gained no new keys")
	expect(world_after==world_shape,"The world state gained no new top-level keys")
	expect(not ("bookcase" in JSON.stringify(person).to_lower()),"No bookcase data was written to the player")
	expect(not ("read_stories" in JSON.stringify(world.state)) and obj().get("items",{}).is_empty() and obj().size()==5,"The bookcase object carries no reading state")

	# --- Save and reload -------------------------------------------------------------------------
	expect(world.save(),"The world saves")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and Industry.is_vertical(loaded.state.objects.get(World.key(SITE),{})),"Reload keeps the vertical bookcase")
	expect(World.station_anchor(loaded.state.objects,SECOND)==SITE,"Reload keeps the anchor")

	# --- Move keeps orientation, remove refunds, others cannot dismantle -------------------------
	stand_at(owner,41.5,34.5)
	expect(not world.act(GUEST,"guest-remove","remove",SITE).ok and obj().get("type")==KIND,"A guest cannot dismantle the owner's bookcase")
	expect(not world.act(GUEST,"guest-move","move_object",SITE,World.key(MOVED)).ok and obj().get("type")==KIND,"A guest cannot move the owner's bookcase")
	var moved:=world.act(owner,"bookcase-move","move_object",SECOND,World.key(MOVED))
	if expect(moved.ok,"The owner can move the bookcase by its second half: "+str(moved.get("message",""))):
		expect(obj().is_empty() and obj(SECOND).is_empty(),"The old cells are cleared")
		expect(obj(MOVED).get("type")==KIND and obj(MOVED+Vector2i.DOWN).get("type")==KIND,"The bookcase stands on both new cells")
		expect(Industry.is_vertical(obj(MOVED)) and world.blocked(MOVED) and world.blocked(MOVED+Vector2i.DOWN),"The moved bookcase keeps vertical orientation and both solid cells")
		expect(World.station_anchor(world.state.objects,MOVED+Vector2i.DOWN)==MOVED,"The moved bookcase resolves to its new anchor")
		expect(world.act(owner,"bookcase-back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"The owner can move it back")

	# --- Blueprint: vertical capture, rotated placement is horizontal -----------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(1,2)),"格子書櫃",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"Blueprint captures the bookcase as one piece"):
		expect(cut.blueprint.width==1 and cut.blueprint.height==2,"The vertical bookcase is a 1x2 blueprint")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		if expect(turned.get("ok")==true and turned.blueprint.pieces.size()==1,"One quarter turn rotates the blueprint"):
			expect(turned.blueprint.width==2 and turned.blueprint.height==1,"The rotated bookcase is a 2x1 blueprint")
		stand_at(owner,45.5,35.5)
		var quote:=world.quote_blueprint(owner,cut.blueprint,ROTATED,1)
		if expect(quote.get("ok")==true,"Quote for the rotated placement succeeds: "+str(quote.get("message",""))):
			var wood:int=person.inventory.wood
			var fiber:int=person.inventory.fiber
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,ROTATED,1,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the rotated blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.wood==wood-16 and person.inventory.fiber==fiber-4,"The blueprint charges exactly one bookcase recipe")
			expect(obj(ROTATED).get("type")==KIND and not Industry.is_vertical(obj(ROTATED)),"The rotated blueprint places a horizontal bookcase")
			expect(world.blocked(ROTATED) and world.blocked(ROTATED+Vector2i.RIGHT) and World.station_anchor(world.state.objects,ROTATED+Vector2i.RIGHT)==ROTATED,"Its two horizontal cells are solid and share one anchor")
			app.session._send_snapshot(1)
			focus_camera(ROTATED)
			await capture("grid-bookcase-horizontal")
			stand_at(owner,46.5,35.5)
			app.session._send_snapshot(1)
			app._close_modal()
			app._interact()
			expect(hub_open(),"The horizontal bookcase opens the same hub")
			app._close_modal()
			var refund:int=person.inventory.wood
			expect(world.act(owner,"remove-horizontal","remove",ROTATED+Vector2i.RIGHT).ok and obj(ROTATED).is_empty() and obj(ROTATED+Vector2i.RIGHT).is_empty(),"Removing by either half dismantles the whole bookcase")
			expect(person.inventory.wood==refund+16,"Dismantling refunds the 16 wood")

	# --- Final removal of the original ---------------------------------------------------------------
	stand_at(owner,41.5,34.5)
	var wood_now:int=person.inventory.wood
	var fiber_now:int=person.inventory.fiber
	expect(world.act(owner,"final-remove","remove",SECOND).ok and obj().is_empty() and obj(SECOND).is_empty(),"The bookcase can be dismantled by its lower half")
	expect(person.inventory.wood==wood_now+16 and person.inventory.fiber==fiber_now+4,"Dismantling refunds the full recipe")
	expect(not world.blocked(SITE) and not world.blocked(SECOND),"Both cells are walkable again")
	await finish()
