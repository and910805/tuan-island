extends SceneTree

const World=preload("res://scripts/world.gd")
const Cards=World.POSTCARDS
const Goals=World.RESIDENT_GOALS
const SITE:=Vector2i(40,34)
const NEXT:=SITE+Vector2i.RIGHT
var app
var world:World
var token:String
var output:String
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
	return world.act(token if actor.is_empty() else actor,"postcards-%d"%serial,action,tile,extra)

func shown(tile:Vector2i)->Array:
	return world.state.objects.get(World.key(tile),{}).get(Cards.SLOTS,[])

func use_picker(id:String)->bool:
	if not is_instance_valid(app.modal):return false
	var picker:=app.modal.find_child("PostcardPicker",true,false) as OptionButton
	var place:=app.modal.find_child("PostcardPlace",true,false) as Button
	if picker==null or place==null:return false
	for index in picker.item_count:
		if picker.get_item_metadata(index)!=id:continue
		picker.select(index)
		place.pressed.emit()
		return true
	return false

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("postcard-preview","")
	var path:="user://postcard-rack-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="postcard-rack-player"
	if app.session.host(0,"海風明信片架測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	token=app.session.peers[1]
	world.state.time=700.0
	world.state.picnic=true
	var person:Dictionary=world.state.players[token]
	person.inventory.merge({"wood":36,"fiber":10},true)
	person.x=40.5
	person.y=33.5
	expect(act("build",SITE,Cards.RACK).message==Cards.UNLOCK_MESSAGE and Cards.earned(person).is_empty(),"A fresh player has no cards and the rack is story-gated")
	var origin:Vector2i=World.TRANSIT.STATIONS.home.cell
	person.x=origin.x+0.5
	person.y=origin.y+0.5
	var outward:=act("transit",origin,"toucheng")
	expect(outward.ok and person.region=="toucheng" and Cards.earned(person)==["toucheng"],"A genuine crossing to Toucheng grants its postcard: "+str(outward.message))
	var toucheng:Vector2i=World.TRANSIT.STATIONS.toucheng.cell
	person.x=toucheng.x+0.5
	person.y=toucheng.y+0.5
	expect(act("transit",toucheng,"home").ok and person.region=="home","Return through the route to display the postcard")
	person.travel_book.visited.merge({"maokong":true,"yingge":true,"tianwei":true})
	person.bonds={
		"luoluo":{"points":6,"talk_day":-1,"gift_day":-1},
		"aru":{"points":2,"talk_day":-1,"gift_day":-1},
		"milu":{"points":2,"talk_day":-1,"gift_day":-1},
		"xiaoli":{"points":2,"talk_day":-1,"gift_day":-1},
	}
	person[Goals.POSTCARD_CLUES_KEY]=["aru","milu","xiaoli"] # FIXTURE: clue need seeded next to the bonds above
	var luoluo:Vector2i=World.bond_place(world.state,"luoluo")[1]
	person.x=luoluo.x+0.5
	person.y=luoluo.y+0.5
	var story:=act(Goals.ACTION,luoluo,"luoluo:2::")
	expect(story.ok and Goals.done(person,"luoluo").has(2),"Complete the existing LuoLuo story: "+str(story.message))
	person.x=40.5
	person.y=33.5
	app.session._send_snapshot(1)
	expect(app.session.snapshot.get("own_postcards",[])==["toucheng","maokong","yingge","tianwei"],"The owner sees arrival and earlier travel records without re-travelling")
	app.LifeTasks.bond_goal(app,"luoluo",2)
	var reward:=app.modal.find_child("LuoluoPostcardPattern",true,false) as Button if is_instance_valid(app.modal) else null
	expect(reward!=null,"Story completion links to the postcard recipe")
	if reward!=null:reward.pressed.emit()
	else:app._build_menu()
	await capture("workshop")
	var build:=app.modal.find_child("BuildPlace",true,false) as Button
	if build!=null:build.pressed.emit()
	expect(app.building==Cards.RACK,"Reward link selects the actual rack")
	app._perform_build_action("build",SITE,Cards.RACK)
	var key:=World.key(SITE)
	expect(world.state.objects.get(key,{}).get("type")==Cards.RACK and person.inventory.wood==28 and person.inventory.fiber==8 and world.blocked(SITE),"Build is a solid one-tile rack with the exact recipe")
	person.x=SITE.x+1.1
	person.y=SITE.y+0.5
	app.session._send_snapshot(1)
	app._interact()
	var display:bool=is_instance_valid(app.modal) and app.modal.has_meta("postcard_rack")
	expect(display,"Normal interaction opens the travel display")
	var original_bag:Dictionary=person.inventory.duplicate(true)
	var featured:=["toucheng","yingge","tianwei"]
	for id:String in featured:
		if display:expect(use_picker(id),"Use the real display picker for "+id)
		else:expect(act(Cards.PUT,SITE,id).ok,"Populate display for secondary checks")
	expect(shown(SITE)==featured and person.inventory==original_bag,"Three postcards are displayed without consuming items")
	expect(not act(Cards.PUT,SITE,"maokong").ok and not act(Cards.PUT,SITE,"beimen").ok and not act(Cards.PUT,SITE,"toucheng").ok,"Capacity, unlock and duplicate guards are independent")
	await capture("display")
	if is_instance_valid(app.modal):app._close_modal()
	await capture("island")
	world.add_player("postcard-guest","看展訪客")
	var guest:Dictionary=world.state.players["postcard-guest"]
	guest.x=41.5
	guest.y=33.5
	expect(not act(Cards.TAKE,SITE,"toucheng","postcard-guest").ok and Cards.earned(guest).is_empty(),"Viewing somebody’s cards does not grant ownership or editing")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[key][Cards.SLOTS]==featured and Cards.earned(loaded.state.players[token]).has("toucheng"),"Primary save preserves both travel collection and rack contents")
	var bad:=world.state.duplicate(true)
	bad.objects[key][Cards.SLOTS]=["beimen"]
	expect(not World.SAVE_SCHEMA.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects a displayed destination the owner never visited")
	var pattern:=World.BLUEPRINT_DESIGN.capture(world.state,token,Rect2i(SITE,Vector2i.ONE),"海風明信片架",World.BUILD,World.NAMES)
	expect(pattern.ok and pattern.blueprint.pieces.size()==1 and not pattern.blueprint.pieces[0].has(Cards.SLOTS),"Blueprint captures the rack without personal cards")
	person.x=SITE.x+0.5
	person.y=SITE.y-0.5
	expect(act("move_object",SITE,World.key(NEXT)).ok and shown(NEXT)==featured and not world.state.objects.has(key),"Moving keeps the displayed cards together")
	expect(act(Cards.TAKE,NEXT,"toucheng").ok and shown(NEXT)==["yingge","tianwei"] and Cards.earned(person).has("toucheng"),"Taking a card off the rack keeps its personal collection entry")
	expect(act("remove",NEXT).ok and int(person.inventory.wood)==36 and int(person.inventory.fiber)==10 and Cards.earned(person).size()==4,"Removing the display refunds materials but keeps all collected cards")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("POSTCARD_RACK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)
