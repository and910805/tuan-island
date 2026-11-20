extends SceneTree
## T09 聽水風鈴 focused test. Works natively and with --headless.
##   godot --headless --path game --script res://tests/test_water_listening_chime.gd -- --qa-size=1024
## Run once per window size: --qa-size=1024 (1024x640) or default 1280x800. --qa-dir=<folder>
## saves a screenshot when not headless.

const World=preload("res://scripts/world.gd")
const Fixtures=World.WALL_FIXTURES
const Art=preload("res://scripts/water_listening_chime_art.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const Folio=preload("res://scripts/build_folio.gd")
const SoftAudio=preload("res://scripts/soft_audio.gd")
const KIND:=Fixtures.WATER_LISTENING_CHIME
const ASSET:="res://assets/ui-life/water-listening-chime.png"
const HOOK:=Vector2i(41,36)
const WALL:=HOOK+Vector2i.UP
var app
var world:World
var owner:String
var visitor:="water-chime-visitor-qa"
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

func act(action:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"water-chime-%d"%serial,action,cell,extra)

func snapshot_of(token:String)->Dictionary:
	return {"objects":world.state.objects.duplicate(true),"inventory":world.state.players[token].inventory.duplicate(true),
		"time":world.state.time,"ground":world.state.ground.duplicate(true)}

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	var output:String=app.arg_value("qa-dir","")
	await process_frame
	var path:="user://water-listening-chime-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="water-chime-builder-qa"
	if app.session.host(0,"聽水風鈴測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=37.5
	person.inventory.merge({"wood":40,"bamboo":4,"copper_ingot":1,"fiber":2},true)
	world.add_player(visitor,"訪客")
	var guest:Dictionary=world.state.players[visitor]
	guest.x=42.5
	guest.y=37.5

	# --- contract: art, recipe, ids, categories, existing chimes untouched
	expect(ResourceLoader.exists(ASSET),"Chime sprite exists at the agreed path")
	var texture:=load(ASSET) as Texture2D if ResourceLoader.exists(ASSET) else null
	expect(texture!=null and texture.get_size()==Vector2(22,32),"Chime sprite is 22x32")
	expect(KIND=="water_listening_chime" and KIND in Fixtures.KINDS and Fixtures.support_type(KIND)=="wall","Id is registered as a wall fixture")
	var recipe:Dictionary=World.BUILD[KIND]
	expect(recipe.name=="聽水風鈴" and recipe.bamboo==4 and recipe.copper_ingot==1 and recipe.fiber==2 and recipe.size()==4,"Recipe is 4 bamboo, 1 copper ingot, 2 fiber")
	expect(KIND in Folio.TEA_COLLECTION and KIND in Panels.FURNITURE and Folio.category(KIND,Panels.FOUNDATIONS,Panels.FURNITURE)==2,"Listed under tea collection and furniture")
	expect(Fixtures.CHIME in Fixtures.KINDS and World.BUILD[Fixtures.CHIME].clay==4 and World.BUILD[Fixtures.CHIME].fiber==2,"Ceramic chime recipe is unchanged")
	var probe:=SoftAudio.new()
	expect(is_equal_approx(probe.cue_gain("ceramic_chime"),probe.master_volume*probe.ambience_volume) and is_equal_approx(probe.cue_gain("shell_chime"),probe.master_volume*probe.ambience_volume),"Existing chimes still follow the ambient level")
	probe.free()

	# --- wall support and build
	expect(not act("build",HOOK,KIND).ok and person.inventory.bamboo==4 and person.inventory.copper_ingot==1 and person.inventory.fiber==2,"No wall: build fails and keeps materials")
	expect(act("build",WALL,"wall").ok,"Build a plain wood wall")
	expect(act("build",HOOK,KIND).ok and world.state.objects[World.key(HOOK)].type==KIND,"Build the chime on the wall's south face")
	expect(person.inventory.bamboo==0 and person.inventory.copper_ingot==0 and person.inventory.fiber==0,"Exact recipe is spent")
	expect(not world.blocked(HOOK),"The chime never blocks walking")
	expect(not act("remove",WALL).ok,"Wall cannot be removed while the chime hangs on it")
	expect(not act("move_object",HOOK,"44,36").ok,"Moving to an unsupported cell fails")
	expect(not act("build",Vector2i(44,36),KIND,visitor).ok,"A visitor without their own wall cannot hang one")

	# --- manual ring: owner and nearby visitor, nothing changes, far/odd requests fail
	var before:=snapshot_of(owner)
	var before_ring:Dictionary=world.state.duplicate(true)
	var visitor_bag:Dictionary=guest.inventory.duplicate(true)
	expect(act(Fixtures.WATER_CHIME_RING,HOOK).ok,"Owner can ring it")
	expect(act(Fixtures.WATER_CHIME_RING,HOOK,"",visitor).ok,"A nearby visitor can ring it")
	expect(snapshot_of(owner)==before and guest.inventory==visitor_bag,"Ringing changes no materials, objects or time")
	expect(world.state==before_ring,"Ringing also leaves receipts and saveable state unchanged")
	expect(not world.state.objects[World.key(HOOK)].has("bell_at"),"Ringing writes no timestamp to the save")
	guest.x=60.5
	expect(not act(Fixtures.WATER_CHIME_RING,HOOK,"",visitor).ok,"A distant visitor cannot ring it")
	guest.x=42.5
	expect(not act(Fixtures.WATER_CHIME_RING,HOOK,"x").ok and not act(Fixtures.WATER_CHIME_RING,Vector2i(30,30)).ok,"Bad extra or target is rejected")
	expect(snapshot_of(owner)==before,"Rejected rings change nothing either")
	expect(bool(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)),"State stays valid")

	# --- sound: own cue through the ambient level, then mute
	expect(SoftAudio.make_cue("water_chime").data.size()>0 and app.sound.sounds.has("water_chime"),"A dedicated quiet cue exists")
	expect(is_equal_approx(app.sound.cue_gain("water_chime"),app.sound.master_volume*app.sound.ambience_volume),"Cue gain is master x ambient level")
	app.session._send_snapshot(1)
	app.sound.master_volume=1.0
	app.sound.ambience_volume=0.25
	app.sound.volume=0.0
	app.sound.refresh_gains()
	await create_timer(0.28).timeout
	app._interact()
	await create_timer(0.26).timeout
	expect(app.sound.cue_kind=="water_chime" and app.sound.player.stream==app.sound.sounds.water_chime and app.sound.player.playing
		and is_equal_approx(app.sound.player.volume_db,linear_to_db(0.25)),"Interaction plays the chime at the ambient level, not the effects level")
	expect(app.view.water_chime_age(World.key(HOOK))>=0.0,"The local swing/note starts")
	expect(snapshot_of(owner).objects==before.objects and snapshot_of(owner).inventory==before.inventory,"In-game ring leaves the world untouched")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(output)
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(output.path_join("water-listening-chime-%d.png"%root.size.x))==OK,"Capture the chime")
	app.sound.ambience_volume=0.0
	app.sound.refresh_gains()
	app.sound.player.stop()
	await create_timer(0.2).timeout
	app.session.perform(Fixtures.WATER_CHIME_RING,HOOK)
	await create_timer(0.3).timeout
	expect(not app.sound.player.playing and "聽水風鈴" in app.toast.text,"Ambient mute silences it but keeps the text feedback")
	app.sound.ambience_volume=0.25
	app.sound.volume=0.45
	app.sound.refresh_gains()

	# --- reduced motion: no sway, brief note still shows
	expect(Art.sway(0.3,true)==0.0 and Art.sway(0.3,false)!=0.0 and Art.sway(5.0,false)==0.0,"Reduced motion removes the sway")
	expect(Art.note_alpha(0.1)>0.0 and Art.note_alpha(2.0)==0.0 and Art.note_alpha(-1.0)==0.0,"A short note mark replaces motion and then ends")

	# --- save, move, undo, remove
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(World.key(HOOK),{}).get("type")==KIND,"The chime survives reload")
	var second:=HOOK+Vector2i.RIGHT
	expect(act("build",second+Vector2i.UP,"wall").ok,"Build a second wall")
	expect(act("move_object",HOOK,World.key(second)).ok and world.state.objects[World.key(second)].type==KIND,"Move it to another supported wall")
	var undo:=world.undo_summary(owner)
	expect(act("undo_build",second,undo.get("id","")).ok and world.state.objects[World.key(HOOK)].type==KIND,"Undo restores the first mount")
	expect(act("remove",HOOK).ok and person.inventory.bamboo==4 and person.inventory.copper_ingot==1 and person.inventory.fiber==2,"Removing refunds the full recipe")
	expect(act("remove",WALL).ok,"The wall can go once the chime is removed")

	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WATER_LISTENING_CHIME_TESTS size=%d checks=%d failures=%d"%[root.size.x,checks,failures])
	quit(int(failures>0))
