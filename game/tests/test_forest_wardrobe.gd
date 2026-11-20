extends SceneTree
## W08 Forest Wardrobe regression checks. Run from the game project.
##   godot --headless --path game --script <this file> -- [--qa-dir=DIR] [--qa-size=1024]
## Optional screenshots are skipped when headless or when --qa-dir is absent.

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const Design=preload("res://scripts/blueprint_design.gd")
const KIND:="forest_wardrobe"
const SITE:=Vector2i(41,36)
const MOVED:=Vector2i(44,36)
const COPY:=Vector2i(47,36)
const GUEST:="forest-wardrobe-guest"
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
	print("FOREST_WARDROBE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func widget(id:String)->Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func open_from(cell:Vector2i)->void:
	stand_at(owner,float(cell.x)+0.5,float(cell.y)+1.5)
	app.session._send_snapshot(1)
	app._close_modal()
	app._interact()

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(0.5,1.0))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://forest-wardrobe-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="forest-wardrobe-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,"森林更衣櫃",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	world.state.time=720.0
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	for tile in [SITE,MOVED,COPY]:world.state.removed[World.key(tile)]=true
	person.inventory.merge({"wood":40,"cotton_cloth":5},true)
	stand_at(owner,float(SITE.x)+0.5,float(SITE.y)+1.5)
	world.add_player(GUEST,"路過的訪客",Vector2(SITE.x+1.5,SITE.y+1.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Contract: constant, recipe, size ---------------------------------------------------------
	expect(Goals.FOREST_WARDROBE==KIND,"RESIDENT_GOALS.FOREST_WARDROBE is forest_wardrobe")
	expect(World.BUILD.has(KIND) and not str(World.BUILD[KIND].get("name","")).is_empty(),"The wardrobe has a display name")
	expect(World.BUILD[KIND].get("wood")==18 and World.BUILD[KIND].get("cotton_cloth")==2 and World.BUILD[KIND].size()==3,"Recipe is exactly 18 wood and 2 cotton cloth plus the name")
	if not expect(World.BUILD.has(KIND),"Cannot continue without the recipe"):
		await finish()
		return

	# --- Insufficient materials change nothing ----------------------------------------------------
	var bag:Dictionary=person.inventory.duplicate(true)
	person.inventory.wood=17
	expect(not world.act(owner,"poor-wood","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==17 and person.inventory.cotton_cloth==5,"17 wood is refused and nothing is spent")
	person.inventory.wood=40
	person.inventory.cotton_cloth=1
	expect(not world.act(owner,"poor-cloth","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==40 and person.inventory.cotton_cloth==1,"1 cotton cloth is refused and nothing is spent")
	person.inventory.cotton_cloth=5
	expect(person.inventory.wood==bag.wood and person.inventory.cotton_cloth==bag.cotton_cloth,"Refused builds leave the bag untouched")

	# --- Build: spends recipe, 1x1 solid, owner recorded -------------------------------------------
	app._select_tool("hoe")
	app._perform_build_action("build",SITE,KIND)
	expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the wardrobe for its owner")
	expect(person.inventory.wood==22 and person.inventory.cotton_cloth==3,"Building spends exactly 18 wood and 2 cotton cloth")
	expect(world.blocked(SITE) and World.station_anchor(world.state.objects,SITE)==SITE,"The wardrobe is solid and anchors itself")
	expect(not world.blocked(SITE+Vector2i.RIGHT) and not world.blocked(SITE+Vector2i.DOWN) and not obj(SITE+Vector2i.RIGHT).has("type") and not obj(SITE+Vector2i.DOWN).has("type"),"It occupies exactly one cell")
	expect(not world.act(owner,"overlap","build",SITE,KIND).ok and person.inventory.wood==22,"A second wardrobe cannot overlap and costs nothing")
	expect(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The world with a wardrobe passes save validation")
	var player_keys:=person.keys()
	stand_at(owner,SITE.x+1.5,SITE.y+0.5)
	app.session._send_snapshot(1)
	focus_camera(SITE)
	app.view.set_process(false)
	await capture("forest-wardrobe-placed")

	# --- Server validation while blue is locked ----------------------------------------------------
	expect(not person.get("blue_outfit_unlocked",false) and not person.get("blue_outfit",false),"Fixture: blue is still locked")
	var inv_before:=var_to_str(person.inventory)
	expect(not world.act(owner,"locked-blue","inn_outfit",SITE,"blue").ok and not person.get("blue_outfit",false) and not person.get("blue_outfit_unlocked",false),"Server rejects blue while locked and grants nothing")
	expect(not world.act(owner,"bad-extra","inn_outfit",SITE,"green").ok and not world.act(owner,"empty-extra","inn_outfit",SITE,"").ok,"Server rejects unknown outfit names")
	stand_at(owner,SITE.x+9.5,SITE.y+9.5)
	expect(not world.act(owner,"far","inn_outfit",SITE,"original").ok,"A distant player cannot use the wardrobe")
	stand_at(owner,float(SITE.x)+0.5,float(SITE.y)+1.5)

	# --- Locked modal -----------------------------------------------------------------------------
	open_from(SITE)
	var original:=widget("ForestWardrobeOriginal")
	var blue:=widget("ForestWardrobeBlue")
	if expect(original!=null and blue!=null,"_interact opens the modal with both outfit controls"):
		expect(blue.disabled,"Locked blue option is disabled")
		expect(original.disabled,"The active original option is disabled")
		await capture("forest-wardrobe-locked")
		expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect()),"The wardrobe fits within the viewport")
		blue.pressed.emit()
		expect(not person.get("blue_outfit",false) and not person.get("blue_outfit_unlocked",false),"Pressing the disabled blue option changes nothing")

	# --- Original before unlock: allowed, never grants blue -----------------------------------------
	expect(world.act(owner,"orig-locked","inn_outfit",SITE,"original").ok,"Original is allowed on this wardrobe before the blue unlock")
	expect(not person.get("blue_outfit",false) and not person.get("blue_outfit_unlocked",false) and not World.FLOWER_NURSERY.blue_outfit_unlocked(person),"Original before unlock does not grant blue")
	expect(var_to_str(person.inventory)==inv_before,"Outfit changes are free")
	expect(not world.act(owner,"locked-blue-2","inn_outfit",SITE,"blue").ok,"Blue is still rejected after using original")

	# --- Unlocked via the existing flag --------------------------------------------------------------
	person.blue_outfit_unlocked=true
	app.session._send_snapshot(1)
	open_from(SITE)
	original=widget("ForestWardrobeOriginal")
	blue=widget("ForestWardrobeBlue")
	if expect(original!=null and blue!=null,"Unlocked modal has both controls"):
		expect(not blue.disabled and original.disabled,"Unlocked: blue enabled, active original disabled")
		blue.pressed.emit()
	expect(person.get("blue_outfit",false)==true and var_to_str(person.inventory)==inv_before,"The real UI equips blue for free")
	app.session._send_snapshot(1)
	open_from(SITE)
	original=widget("ForestWardrobeOriginal")
	blue=widget("ForestWardrobeBlue")
	if expect(original!=null and blue!=null,"Modal reopens while wearing blue"):
		expect(blue.disabled and not original.disabled,"Wearing blue: blue disabled, original enabled")
		focus_camera(SITE)
		await capture("forest-wardrobe-unlocked-blue")
		original.pressed.emit()
	expect(not person.has("blue_outfit") and person.blue_outfit_unlocked,"The real UI returns to original and keeps the unlock")
	expect(var_to_str(person.inventory)==inv_before,"Returning to original is free")

	# Older save: dyed clothes worn but only blue_outfit stored; flag semantics unchanged.
	person.erase("blue_outfit_unlocked")
	person.blue_outfit=true
	expect(world.act(owner,"legacy-original","inn_outfit",SITE,"original").ok and not person.has("blue_outfit") and person.blue_outfit_unlocked,"A legacy save keeps its dye unlock after switching to original")
	expect(world.act(owner,"legacy-blue","inn_outfit",SITE,"blue").ok and person.blue_outfit,"The restored unlock allows blue again")

	# --- Guest ---------------------------------------------------------------------------------------
	stand_at(GUEST,SITE.x+0.5,SITE.y+1.5)
	expect(not world.act(GUEST,"guest-locked","inn_outfit",SITE,"blue").ok and not guest.get("blue_outfit",false),"The owner's unlock does not transfer to a guest")
	expect(world.act(GUEST,"guest-orig","inn_outfit",SITE,"original").ok and not guest.get("blue_outfit_unlocked",false),"A guest may wear original without gaining blue")
	guest.blue_outfit_unlocked=true
	expect(world.act(GUEST,"guest-blue","inn_outfit",SITE,"blue").ok and guest.blue_outfit and person.blue_outfit,"An unlocked guest changes only their own clothes")

	# --- Apron stays independent -----------------------------------------------------------------------
	var apron_key:String=Goals.APRON_KEY
	person.erase(apron_key)
	expect(not world.act(owner,"apron-locked",Goals.APRON_ACTION,SITE).ok and not person.has(apron_key),"The apron keeps its existing gate (not opened by the wardrobe)")
	expect(person.blue_outfit and not person.has(apron_key),"Outfit state and apron state remain separate")
	var saved_goals:Variant=person.get("bond_goals")
	person.bond_goals={"milu":{"4":""}}
	open_from(SITE)
	var apron:=widget("GuestWardrobeApron")
	if expect(apron!=null and not apron.disabled,"An earned apron appears in the same wardrobe"):
		apron.pressed.emit()
		expect(person.get(apron_key,false) and person.blue_outfit,"The apron can be worn over the selected workwear")
		open_from(SITE)
		await capture("forest-wardrobe-apron")
		apron=widget("GuestWardrobeApron")
		if expect(apron!=null,"The apron can be taken off separately"):
			if DisplayServer.get_name()!="headless":
				var scroll:=app.modal.find_children("*","ScrollContainer",true,false)[0] as ScrollContainer
				expect(scroll.get_global_rect().encloses(apron.get_global_rect()),"The apron control fully fits without scrolling")
			apron.pressed.emit()
		expect(not person.has(apron_key) and person.blue_outfit,"Taking off the apron keeps the blue workwear")
	if saved_goals==null:person.erase("bond_goals")
	else:person.bond_goals=saved_goals

	# --- No saved wardrobe data -------------------------------------------------------------------------
	var added:=[]
	for key in person.keys():
		if not player_keys.has(key):added.append(str(key))
	added.sort()
	expect(added==["blue_outfit","blue_outfit_unlocked"],"Players gain only the existing outfit flags: "+str(added))
	expect("forest" not in JSON.stringify(person).to_lower() and "wardrobe" not in JSON.stringify(person).to_lower(),"No wardrobe-specific data in the player record")
	expect(obj().get("items",{}).is_empty() and "outfit" not in JSON.stringify(obj()).to_lower(),"The wardrobe object carries no outfit state")
	expect(not ("forest_wardrobe" in JSON.stringify(world.state.get("resident_goals",{}))),"No wardrobe progress is stored in resident goals")

	# --- Save and reload --------------------------------------------------------------------------------
	expect(world.save(),"The world saves")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and loaded.blocked(SITE),"Reload keeps the solid wardrobe")
	expect(loaded.state.players[owner].get("blue_outfit",false) and loaded.state.players[owner].blue_outfit_unlocked,"Reload keeps outfit flags")

	# --- Final render (screenshot only; no pixel assertions) -----------------------------------------------
	app.session._send_snapshot(1)
	focus_camera(SITE)
	await capture("forest-wardrobe-final")

	# --- Move, ownership, blueprint, remove -------------------------------------------------------------------
	stand_at(owner,float(SITE.x)+0.5,float(SITE.y)+1.5)
	expect(not world.act(GUEST,"guest-remove","remove",SITE).ok and obj().get("type")==KIND,"A guest cannot dismantle the owner's wardrobe")
	expect(not world.act(GUEST,"guest-move","move_object",SITE,World.key(MOVED)).ok and obj().get("type")==KIND,"A guest cannot move it")
	var moved:=world.act(owner,"wardrobe-move","move_object",SITE,World.key(MOVED))
	if expect(moved.ok,"The owner can move the wardrobe: "+str(moved.get("message",""))):
		expect(obj().is_empty() and obj(MOVED).get("type")==KIND and world.blocked(MOVED) and not world.blocked(SITE),"Moving clears the old cell and blocks the new one")
		expect(world.act(owner,"wardrobe-back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"The owner can move it back")

	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(1,1)),"森林更衣櫃",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"Blueprint captures the wardrobe as one piece"):
		expect(cut.blueprint.width==1 and cut.blueprint.height==1,"It is a 1x1 blueprint")
		stand_at(owner,COPY.x+0.5,COPY.y+1.5)
		var quote:=world.quote_blueprint(owner,cut.blueprint,COPY,0)
		if expect(quote.get("ok")==true,"Blueprint quote succeeds: "+str(quote.get("message",""))):
			var wood:int=person.inventory.wood
			var cloth:int=person.inventory.cotton_cloth
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,COPY,0,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.wood==wood-18 and person.inventory.cotton_cloth==cloth-2,"The blueprint charges exactly one recipe")
			expect(obj(COPY).get("type")==KIND and world.blocked(COPY),"The blueprint places a solid wardrobe")
			expect(world.act(owner,"remove-copy","remove",COPY).ok and obj(COPY).is_empty(),"The copy can be removed")

	stand_at(owner,float(SITE.x)+0.5,float(SITE.y)+1.5)
	var wood_now:int=person.inventory.wood
	var cloth_now:int=person.inventory.cotton_cloth
	expect(world.act(owner,"final-remove","remove",SITE).ok and obj().is_empty(),"The owner can dismantle the wardrobe")
	expect(person.inventory.wood==wood_now+18 and person.inventory.cotton_cloth==cloth_now+2,"Dismantling refunds the full recipe")
	expect(not world.blocked(SITE),"The cell is walkable again")
	expect(person.blue_outfit and person.blue_outfit_unlocked,"Removing the wardrobe does not touch outfit state")
	await finish()
