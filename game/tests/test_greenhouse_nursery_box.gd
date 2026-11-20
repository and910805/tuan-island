extends SceneTree

const World=preload("res://scripts/world.gd")
const Nursery=World.NURSERY_BOX
const PLOT:=Vector2i(40,34)
const DOOR:=Vector2i(40,36)
const OUTDOOR:=Vector2i(37,35)
const BORDER:=[Vector2i(40,33),Vector2i(41,33),Vector2i(39,34),Vector2i(42,34),Vector2i(39,35),Vector2i(42,35),Vector2i(41,36)]
var app
var world:World
var owner:String
var directory:String
var serial:=0
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(action:String,tile:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"nursery-%d"%serial,action,tile,extra)

func build(kind:String,tile:Vector2i)->void:
	var result:=act("build",tile,kind)
	expect(result.ok,"Build %s at %s: %s"%[kind,tile,result.message])

func plant(tile:Vector2i,slot:int)->Dictionary:
	return world.state.objects.get(World.key(tile),{}).get(Nursery.SLOTS,{}).get(str(slot),{})

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	directory=app.arg_value("nursery-preview","")
	var path:="user://nursery-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="nursery-box-qa"
	if app.session.host(0,"星禾的育苗箱測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=35.5
	person.inventory.merge({"glass":35,"copper_ingot":10,"copper_joint":2,"wood":190,"stone":30,"radish_seed":6,"lettuce_seed":3,"carrot_seed":3,"wheat_seed":3,"rice_seed":1},true)
	expect(act("build",PLOT,Nursery.KIND).message==Nursery.UNLOCK_MESSAGE,"The actual build requires Xinghe's story")
	person.bonds={"xinghe":{"points":14,"talk_day":-1,"gift_day":-1}}
	person.greenhouse_glass_crafted=true
	var story:=World.bond_place(world.state,"xinghe")
	person.region=story[0]
	person.x=float(story[1].x)+0.5
	person.y=float(story[1].y)+0.5
	var completed:=act(World.RESIDENT_GOALS.ACTION,story[1],"xinghe:3::")
	expect(completed.ok,"Complete Xinghe's actual trust story to earn both recipes: "+str(completed.message))
	person.region=World.REGIONS.HOME
	person.x=40.5
	person.y=35.5
	world.state.time=World.WEATHER.DAY_SECONDS*World.WEATHER.DAYS_PER_SEASON*3+680.0
	var room_glass:int=person.inventory.glass
	var room_wood:int=person.inventory.wood
	build(Nursery.KIND,PLOT)
	expect(person.inventory.glass==room_glass-4 and person.inventory.wood==room_wood-10,"Two-tile recipe charges exactly 10 wood and 4 glass")
	expect(World.station_anchor(world.state.objects,PLOT+Vector2i.RIGHT)==PLOT and not world.can_stand(Vector2(41.5,34.5)),"Both parts are solid occurrences of one box")
	build(Nursery.KIND,OUTDOOR)
	var seeds:=int(person.inventory.radish_seed)
	expect(not act(Nursery.SOW,PLOT,"4:radish").ok and not act(Nursery.SOW,PLOT,"0:rice").ok,"Invalid compartment and non-soil crop are rejected")
	var dormant:=act(Nursery.SOW,OUTDOOR,"0:radish")
	expect(dormant.ok and "休眠" in dormant.message and act(Nursery.WATER,OUTDOOR,"0").ok,"Outdoor winter radish sows and waters through regular dormancy")
	for side:Vector2i in BORDER:build("window" if side==Vector2i(41,33) else "wall",side)
	build("door",DOOR)
	for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		build(World.GREENHOUSE_GLASS.XINGHE_ROOF,PLOT+offset)
	expect(world.greenhouse_covers(World.key(PLOT)) and world.greenhouse_covers(World.key(PLOT+Vector2i.RIGHT)),"Both halves are covered by the sealed greenhouse")
	person.y=35.25
	app.session._send_snapshot(1)
	app.LifeTasks.bond_goal(app,"xinghe",3)
	var recipe:=app.modal.find_child("XingheNurseryPattern",true,false) as Button
	expect(recipe!=null,"The completed story links to the workshop")
	if recipe!=null:recipe.pressed.emit()
	await capture("workshop")
	app._close_modal()
	await process_frame
	app._interact()
	var first:=app.modal.find_child("NurserySlot_0",true,false) as Button if is_instance_valid(app.modal) else null
	expect(first!=null,"Normal island interaction opens the four-slot nursery UI")
	if first!=null:
		var picker:=app.modal.find_child("NurserySeedPicker",true,false) as OptionButton
		for index in picker.item_count:
			if picker.get_item_metadata(index)=="radish":picker.select(index)
		first.pressed.emit()
		expect(first.text=="澆水","First slot updates immediately after the real sow request")
		first.pressed.emit()
	else:
		expect(act(Nursery.SOW,PLOT,"0:radish").ok and act(Nursery.WATER,PLOT,"0").ok,"Fallback permits further rule checks")
	expect(plant(PLOT,0).get("wet",false) and int(person.inventory.radish_seed)==seeds-2,"One seed is spent and only the selected slot is watered")
	expect(not act(Nursery.SOW,PLOT,"0:radish").ok and not act(Nursery.HARVEST,PLOT,"0").ok,"Duplicate sow and premature harvest are rejected")
	expect(act(Nursery.SOW,PLOT+Vector2i.RIGHT,"1:lettuce").ok,"Interacting on the second tile still resolves the box")
	expect(act(Nursery.SOW,PLOT,"2:carrot").ok and act(Nursery.SOW,PLOT,"3:wheat").ok,"All four compartments store their own crops")
	expect(act(Nursery.WATER,PLOT,"1").ok and act(Nursery.WATER,PLOT,"2").ok,"Select individual beds for watering")
	world.step(20.0,true)
	expect(float(plant(PLOT,0).get("growth",0.0))>0.0 and float(plant(PLOT,1).get("growth",0.0))>0.0 and float(plant(PLOT,3).get("growth",-1.0))==0.0,"Winter growth uses the normal watered crop clock for each slot")
	expect(float(plant(OUTDOOR,0).get("growth",-1.0))==0.0,"Outdoor planted slot remains dormant over the same 20 world seconds")
	expect(act("door",DOOR).ok,"Open the greenhouse door")
	var progress:float=plant(PLOT,0).get("growth",-1.0)
	world.step(20.0,true)
	expect(progress>0 and float(plant(PLOT,0).get("growth",-1.0))==progress,"Open greenhouse pauses the winter crop without losing growth")
	expect(act("door",DOOR).ok and act(Nursery.WATER,PLOT,"3").ok,"Close greenhouse and water the fourth slot")
	expect(act("move_object",PLOT,"42,35").message==Nursery.BUSY_MESSAGE,"A planted box cannot be moved")
	expect(act("remove",PLOT+Vector2i.RIGHT).ok and not world.has_glass_roof(World.key(PLOT+Vector2i.RIGHT)),"Roof removal retains its usual priority")
	expect(act("remove",PLOT+Vector2i.RIGHT).message==Nursery.BUSY_MESSAGE,"Removing the exposed second part cannot erase planted slots")
	build(World.GREENHOUSE_GLASS.XINGHE_ROOF,PLOT+Vector2i.RIGHT)
	expect(world.greenhouse_covers(World.key(PLOT)) and world.greenhouse_covers(World.key(PLOT+Vector2i.RIGHT)),"Repairing the selected glass tile restores the sealed greenhouse")
	world.add_player("nursery-guest","訪客")
	var guest:Dictionary=world.state.players["nursery-guest"]
	guest.x=40.5
	guest.y=35.5
	expect(not act(Nursery.WATER,PLOT,"0","nursery-guest").ok and not act(Nursery.HARVEST,PLOT,"0","nursery-guest").ok,"Guests cannot water or harvest another player's pods")
	guest.x=31.5
	guest.y=35.5
	expect(not act(Nursery.WATER,PLOT,"0","nursery-guest").ok,"Distant actions are rejected")
	world.step(220.0,true)
	app.session._send_snapshot(1)
	await capture("four-beds")
	if first!=null:
		var last:=app.modal.find_child("NurserySlot_3",true,false) as Button
		expect(first.text=="採收" and last.text=="採收" and not last.disabled,"All four ripe beds stay actionable")
	if is_instance_valid(app.modal):app._close_modal()
	person.x=41.0
	person.y=35.8
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(40.8,34.7)*32.0-Vector2(root.size)/4.0
	await capture("nursery-world")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[World.key(PLOT)].has(Nursery.SLOTS),"Reload keeps progress and the full footprint in the primary save")
	var stale:=world.state.duplicate(true)
	stale.objects[World.key(PLOT)][Nursery.SLOTS]["4"]=Nursery.empty_plot()
	expect(not World.SAVE_SCHEMA.validate(stale,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validator rejects illegal nursery slot numbers")
	var copy:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"育苗箱搬家圖",World.BUILD,World.NAMES)
	expect(copy.ok and copy.blueprint.pieces.any(func(piece):return piece.kind==Nursery.KIND and not piece.has(Nursery.SLOTS)),"Blueprint records the furniture but no crop")
	var old_count:=int(person.inventory.get("radish",0))
	for slot in Nursery.SLOT_COUNT:
		var result:=act(Nursery.HARVEST,PLOT,str(slot))
		expect(result.ok and plant(PLOT,slot).kind=="","Harvest mature bed %d exactly once: %s"%[slot,result.message])
	expect(int(person.inventory.get("radish",0))==old_count+int(World.CROPS.radish.yield) and not act(Nursery.HARVEST,PLOT,"0").ok,"Actual yield reached inventory and cannot be claimed twice")
	person.x=43.5
	person.y=35.5
	expect(act("move_object",PLOT,"40,35").ok,"Empty nursery can move as one piece")
	expect(act("remove",Vector2i(41,35)).ok and world.state.objects.has("40,35"),"Remove the pane at the new site")
	expect(act("remove",Vector2i(41,35)).ok and not world.state.objects.has("40,35"),"Demolishing part two removes the whole empty nursery")
	if copy.ok:
		var furniture:Dictionary=copy.blueprint.duplicate(true)
		furniture.pieces=furniture.pieces.filter(func(piece):return piece.kind==Nursery.KIND)
		var quoted:=world.quote_blueprint(owner,furniture,PLOT,1)
		expect(quoted.ok,"Quote a rotated empty nursery")
		if quoted.ok:
			var placed:=world.apply_blueprint(owner,"b".repeat(32),furniture,PLOT,1,quoted.hash)
			var vertical:Dictionary=world.state.objects.get(World.key(PLOT),{})
			expect(placed.ok and World.INDUSTRY.is_vertical(vertical) and not vertical.has(Nursery.SLOTS) and World.station_anchor(world.state.objects,PLOT+Vector2i.DOWN)==PLOT,"A rotated blueprint builds two correct tiles without duplicating crops")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("GREENHOUSE_NURSERY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(directory)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
