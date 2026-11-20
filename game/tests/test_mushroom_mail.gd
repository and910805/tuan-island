extends SceneTree

const World=preload("res://scripts/world.gd")
const Mail=World.MUSHROOM_MAIL
const KIND:=World.INDUSTRY.MUSHROOM_POST
const SITE:=Vector2i(42,35)
const SECOND:=Vector2i(43,35)
const BASIC:=Vector2i(44,35)
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
	if not expect(control!=null and not control.disabled and control.is_visible_in_tree(),"Available button "+name):return false
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
	print("MUSHROOM_MAIL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func at(person:Dictionary,point:Vector2)->void:
	person.x=point.x
	person.y=point.y

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://mushroom-mail-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="mushroom-mail-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":55,"stone":10,"copper_ingot":4},true)
	world.state.time=720.0
	at(person,Vector2(42.5,36.55))
	for tile in [SITE,SECOND,BASIC]:world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	app._perform_build_action("build",SITE,KIND)
	if not expect(world.state.objects.get(World.key(SITE),{}).get("type")==KIND,"Normal building creates the mailbox"):
		await finish()
		return
	expect(person.inventory.wood==45 and person.inventory.copper_ingot==2 and world.blocked(SITE),"Uses the specified cost and one solid tile")
	app._select_tool("hoe")
	expect(app.session.snapshot.own_mushroom_mail=={Mail.ARRIVAL:"new"} and not person.has(Mail.RECORD),"A fresh mailbox has one naturally available unread letter")
	await frame("mushroom-mailbox-world")
	app._interact()
	if not press("MushroomLetter_"+Mail.ARRIVAL):
		await finish()
		return
	expect(person[Mail.RECORD][Mail.ARRIVAL]=="read" and Mail.has_pending(Mail.view(world.state,person)),"Reading retains the mailbox indicator while a parcel is awaiting pickup")
	expect(not world.act(owner,"future",Mail.CLAIM,SITE,Mail.BRIDGE).ok,"Cannot claim unopened progress rewards")
	var radish_before:=int(person.inventory.radish_seed)
	var wheat_before:=int(person.inventory.wheat_seed)
	person.inventory.wheat_seed=World.ITEM_CATALOG.stack_limit("wheat_seed")
	expect(not world.act(owner,"full",Mail.CLAIM,SITE,Mail.ARRIVAL).ok and person.inventory.radish_seed==radish_before and person[Mail.RECORD][Mail.ARRIVAL]=="read","A full stack blocks the whole parcel without marking or partially granting it")
	person.inventory.wheat_seed=wheat_before
	app.session._send_snapshot(1)
	await frame("mushroom-mailbox-letter")
	press("MushroomMailClaim")
	expect(person[Mail.RECORD][Mail.ARRIVAL]=="claimed" and person.inventory.radish_seed==radish_before+3 and person.inventory.wheat_seed==wheat_before+2,"One press grants both stacks and records the claim")
	expect((widget("MushroomMailClaim") as Button).disabled and not Mail.has_pending(Mail.view(world.state,person)),"Claim and indicator switch off after the authoritative update")
	expect(not world.act(owner,"duplicate",Mail.CLAIM,SITE,Mail.ARRIVAL).ok and person.inventory.radish_seed==radish_before+3,"A distinct second request cannot grant again")
	app._close_modal()
	expect(world.act(owner,"another","build",SECOND,KIND).ok and not world.act(owner,"other-box",Mail.CLAIM,SECOND,Mail.ARRIVAL).ok,"Another mailbox cannot reset the delivery")
	var guest:="mushroom-mail-guest"
	world.add_player(guest,"訪客",Vector2(43.5,36.5))
	expect(not world.act(guest,"steal",Mail.CLAIM,SITE,Mail.ARRIVAL).ok and not world.state.players[guest].has(Mail.RECORD),"Other players cannot claim the owner's parcel")
	var outsider:Dictionary=app.session.public_state("home",guest)
	expect(not outsider.players[owner.sha256_text().left(16)].has(Mail.RECORD),"Claim records are omitted from public players")
	var Stone=World.STONE_WORKSHOP
	person.inventory.merge({"wood":130,"stone":50,"rope":4},true)
	at(person,Vector2(40.5,30.5))
	var bridge:=world.act(owner,"bridge","donate",Vector2i(40,29))
	expect(bridge.ok and world.state.board and not Stone.bridge_open(world.state) and not Mail.view(world.state,person).has(Mail.BRIDGE),"A real Q03 donation does not deliver the bridge letter")
	expect(not Mail.eligible(world.state,person,Mail.BRIDGE) and not world.act(owner,"q03-read",Mail.READ,SITE,Mail.BRIDGE).ok and not world.act(owner,"q03-claim",Mail.CLAIM,SITE,Mail.BRIDGE).ok and not person[Mail.RECORD].has(Mail.BRIDGE),"The Q03-only state can neither read nor claim the parcel")
	at(person,Vector2(41.0,36.7))
	var bench:=world.act(owner,"q05-bench","build",Vector2i(40,35),Stone.KIND)
	expect(bench.ok,"The stone workbench is built: "+str(bench.get("message","")))
	var foundations:=0
	for step in 2:foundations+=int(world.act(owner,"q05-foundation-%d"%step,Stone.ACTION,Vector2i(40,35),Stone.FOUNDATION).ok)
	expect(foundations==2 and not Mail.view(world.state,person).has(Mail.BRIDGE),"Both foundations alone do not deliver the letter")
	at(person,Vector2(40.5,30.5))
	var q05:=world.act(owner,"q05-donate",Stone.DONATE_ACTION,Vector2i(40,29),"")
	expect(q05.ok and Stone.bridge_open(world.state) and Mail.view(world.state,person)[Mail.BRIDGE]=="new","Completing Q05 delivers a new letter")
	var legacy:=world.state.duplicate(true)
	legacy.erase(Stone.PROJECT_KEY)
	expect(Mail.eligible(legacy,person,Mail.BRIDGE),"A prior save without a bridge project keeps the letter")
	var pending:=world.state.duplicate(true)
	pending[Stone.PROJECT_KEY]=Stone.fresh_project()
	var claimed_player:={Mail.RECORD:{Mail.BRIDGE:"claimed"}}
	expect(Mail.view(pending,claimed_player).get(Mail.BRIDGE)=="claimed" and Mail.view(world.state,claimed_player).get(Mail.BRIDGE)=="claimed","An older claimed parcel remains visible without restoring the reward")
	at(person,Vector2(42.5,36.55))
	person.bonds={"luoluo":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.bond_goals={"luoluo":{"1":""}}
	expect(world.act(owner,"normal-box","build",BASIC,World.RESIDENT_GOALS.MAILBOX_KIND).ok and not world.act(owner,"normal-claim",Mail.CLAIM,BASIC,Mail.BRIDGE).ok,"The ordinary story mailbox remains separate")
	app.session._send_snapshot(1)
	app._interact()
	press("MushroomLetter_"+Mail.LUOLUO)
	expect(not (widget("MushroomMailClaim") as Button).visible,"The story reply has no claim control")
	press("MushroomLetter_"+Mail.BRIDGE)
	await frame("mushroom-mailbox-progress")
	press("MushroomMailClaim")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.players[owner][Mail.RECORD][Mail.BRIDGE]=="claimed","A real save preserves both opened parcels")
	expect(not saved.act(owner,"after-restart",Mail.CLAIM,SITE,Mail.BRIDGE).ok,"Restart does not restore a claimed parcel")
	var malformed:=world.state.duplicate(true)
	malformed.players[owner][Mail.RECORD][Mail.LUOLUO]="claimed"
	expect(not World.SAVE_SCHEMA.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A letter with no parcel cannot carry a claimed receipt")
	await finish()
