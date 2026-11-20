extends SceneTree

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const KIND:=Goals.COAST_WARDROBE
const SITE:=Vector2i(40,34)
const OUTSIDE:=Vector2i(41,34)
var app
var world:World
var owner:String
var output:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("booth-preview","")
	var path:="user://coast-booth-qa-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="seaside-fitting-room-owner"
	if app.session.host(0,"藍白更衣棚測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	world.state.time=680.0
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=33.5
	person.inventory.merge({"wood":40,"cotton_cloth":12},true)
	app.session._send_snapshot(1)
	app._build_menu()
	var tab:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text=="海邊":tab=candidate
	expect(tab!=null,"Open the actual coastal workshop")
	if tab!=null:
		tab.pressed.emit()
		var entry:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(tab.name).trim_prefix("BuildTab"),true,false) as Button
		expect(entry!=null and entry.is_visible_in_tree(),"The dedicated changing booth appears in the coastal collection")
		if entry!=null:entry.pressed.emit()
	await capture("workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	if place!=null:place.pressed.emit()
	expect(app.building==KIND and app.building_style=="","The recipe selects the dedicated object")
	app._perform_build_action("build",SITE,KIND)
	var tile:=World.key(SITE)
	expect(world.state.objects.get(tile,{}).get("type")==KIND and world.blocked(SITE) and not world.blocked(OUTSIDE),"Only the occupied tile has booth collision")
	expect(person.inventory.wood==28 and person.inventory.cotton_cloth==6,"Build consumes 12 wood and 6 cloth")
	app._interact()
	expect(is_instance_valid(app.modal) and app.modal.find_child("InnWardrobeOutfit",true,false)==null and app.modal.find_child("GuestWardrobeApron",true,false)==null,"Locked clothes cannot be selected at the real booth")
	if is_instance_valid(app.modal):app._close_modal()
	expect(not world.act(owner,"locked-blue","inn_outfit",SITE,"blue").ok and not world.act(owner,"locked-apron",Goals.APRON_ACTION,SITE).ok,"The server rejects both unearned outfits")
	person.blue_outfit_unlocked=true
	person.bonds={"milu":{"points":24,"talk_day":-1,"gift_day":-1}}
	person.bond_goals={"milu":{"4":""}}
	var identity:=[person.name,person.region,person.x,person.y,person.coins,person.inventory.duplicate(true),app.session.own_id]
	app.session._send_snapshot(1)
	await create_timer(0.60).timeout
	await capture("original")
	app._interact()
	var outfit:=app.modal.find_child("InnWardrobeOutfit",true,false) as Button if is_instance_valid(app.modal) else null
	expect(outfit!=null and outfit.text=="換上藍染工作服","World interaction offers dye already unlocked by this player")
	await capture("wardrobe")
	if outfit!=null:outfit.pressed.emit()
	expect(person.get("blue_outfit",false),"Actual wardrobe button equips blue workwear")
	await capture("blue-workwear")
	app._interact()
	var apron:=app.modal.find_child("GuestWardrobeApron",true,false) as Button if is_instance_valid(app.modal) else null
	expect(apron!=null and apron.text=="換上米露的圍裙","The unlocked apron uses the same booth")
	if apron!=null:apron.pressed.emit()
	expect(person.get(Goals.APRON_KEY,false) and person.get("blue_outfit",false),"Apron and base dye remain independent")
	expect(identity==[person.name,person.region,person.x,person.y,person.coins,person.inventory,app.session.own_id],"Neither operation changes identity, position, island, coins or items")
	await capture("changed")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.players[owner].get("blue_outfit",false) and loaded.state.players[owner].get(Goals.APRON_KEY,false),"The primary save restores both outfit flags")
	world.add_player("coast-booth-guest","更衣棚訪客")
	var guest:Dictionary=world.state.players["coast-booth-guest"]
	guest.x=41.5
	guest.y=33.5
	expect(not world.act("coast-booth-guest","guest-locked","inn_outfit",SITE,"blue").ok and not world.act("coast-booth-guest","guest-apron",Goals.APRON_ACTION,SITE).ok,"The guest does not inherit the owner's rewards")
	guest.blue_outfit_unlocked=true
	expect(world.act("coast-booth-guest","guest-blue","inn_outfit",SITE,"blue").ok and guest.get("blue_outfit",false) and person.get(Goals.APRON_KEY,false),"The guest changes their own unlocked appearance")
	guest.x=31.5
	expect(not world.act("coast-booth-guest","guest-far","inn_outfit",SITE,"original").ok and guest.get("blue_outfit",false),"Remote requests cannot change outfits")
	app._interact()
	outfit=app.modal.find_child("InnWardrobeOutfit",true,false) as Button
	expect(outfit!=null and outfit.text=="換回原色工作服","Original workwear remains selectable")
	if outfit!=null:outfit.pressed.emit()
	app._interact()
	apron=app.modal.find_child("GuestWardrobeApron",true,false) as Button
	if apron!=null:apron.pressed.emit()
	expect(not person.has("blue_outfit") and not person.has(Goals.APRON_KEY) and person.blue_outfit_unlocked and Goals.apron_unlocked(person),"Returning to original outfit keeps both unlocks")
	var copy:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i.ONE),"藍白更衣棚",World.BUILD,World.NAMES)
	expect(copy.ok and copy.blueprint.pieces.size()==1 and copy.blueprint.pieces[0].kind==KIND,"One-tile blueprint contains the booth")
	expect(world.act(owner,"move-booth","move_object",SITE,World.key(OUTSIDE)).ok and world.state.objects.has(World.key(OUTSIDE)), "Move the booth using existing placement rules")
	expect(world.act(owner,"remove-booth","remove",OUTSIDE).ok and person.inventory.wood==40 and person.inventory.cotton_cloth==12,"Dismantling refunds the full cost")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COAST_CHANGING_BOOTH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)
