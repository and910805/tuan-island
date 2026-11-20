extends SceneTree

## T066 N07-3 (Xinghe, trust): 〈不必把冬天趕走〉 end to end on a local host, outside winter.
## Earn trust in Lanyang -> craft glass at a real workbench -> exact hand-in (glass 2, copper_joint 2)
## -> both reward links (roof + nursery box) -> workshop pages -> real pieces placed -> save reload.
## Generic roof/door/crop rules stay in test_xinghe_greenhouse; nursery slot rules in test_greenhouse_nursery_box.
## Optional user args: --capture-dir=DIR (native only), --size=WxH (default 1024x640), --large-text.
## Wording is read from game data and constants, not retyped.

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const Bond=preload("res://scripts/resident_bond.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Nursery=World.NURSERY_BOX
const ROOF:=World.GREENHOUSE_GLASS.XINGHE_ROOF
const RESIDENT:="xinghe"
const STAGE:=3
const PLOT:=Vector2i(40,34)
const BENCH:=Vector2i(38,36)
const DOOR:=Vector2i(40,36)
const BORDER:=[Vector2i(40,33),Vector2i(41,33),Vector2i(39,34),Vector2i(42,34),Vector2i(39,35),Vector2i(42,35),Vector2i(41,36)]
const ROOF_TILES:=[Vector2i(40,34),Vector2i(41,34),Vector2i(40,35),Vector2i(41,35)]
const HOME_STAND:=Vector2(40.5,35.5)
const ITEMS:={"glass":2,"copper_joint":2}
var app
var world:World
var owner:String
var person:Dictionary
var serial:=0
var checks:=0
var failures:=0
var tag:=""

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,at:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(owner,"xinghe-story-%d"%serial,action,at,extra)

## --size=WxH; malformed or tiny values fall back to the default.
func window_size()->Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=640 and wanted.y>=480:return wanted
	return Vector2i(1024,640)

func capture(file_name:String)->void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		var directory:=arg.trim_prefix("--capture-dir=")
		DirAccess.make_dir_recursive_absolute(directory)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(directory.path_join("%s-%s.png"%[file_name,tag]))==OK,"Capture "+file_name)

func frames(count:=2)->void:
	for i in count:await process_frame

## Use the real region exits; position within each region is supplied by the fixture.
func stand(region:String,at:Vector2)->void:
	if world.player_region(owner)!=region:
		var exit_cell:=World.REGIONS.exit_cell(world.player_region(owner))
		person.x=exit_cell.x+0.5
		person.y=exit_cell.y+0.5
		var trip:=act("travel",exit_cell,region)
		expect(trip.ok and world.player_region(owner)==region,"Travel to %s: %s"%[region,trip.message])
		person=world.state.players[owner]
	person.x=at.x
	person.y=at.y
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func stand_home()->void:
	stand(World.REGIONS.HOME,HOME_STAND)

func stand_at_resident()->Array:
	var site:=World.bond_place(world.state,RESIDENT)
	stand(site[0],Vector2(site[1])+Vector2(0.5,0.5))
	return site

func button(id:String)->Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String)->void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled control: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await frames()

func perform(action:String,at:Vector2i,extra:="")->void:
	app.session.rates[1].clear()
	app.session.perform(action,at,extra)
	await frames()

## Normal route: relation events page -> the stage's 一起做的事 entry.
func open_goal_page()->void:
	Tasks.bond_events(app,RESIDENT)
	await frames()
	var open:=button("BondGoalOpen")
	expect(open!=null,"The relation page offers the trust event")
	if open!=null:open.pressed.emit()
	await frames()

func reason_text()->String:
	var label:=app.modal.find_child("BondGoalReason",true,false) as Label if is_instance_valid(app.modal) else null
	return label.text if label!=null and label.visible else ""

func done_stages()->Dictionary:
	return Goals.done(person,RESIDENT)

func earn_trust(cell:Vector2i)->void:
	expect(Bond.points(person,RESIDENT)==0,"Xinghe friendship starts at zero")
	person.inventory.sapling=3
	person.inventory.radish=1
	for day in range(4):
		if day>0:expect(world.step(World.WEATHER.DAY_SECONDS,true),"Advance to Xinghe's next gift day")
		expect(act("resident_talk",cell,RESIDENT).ok,"Talk to Xinghe on day %d"%(day+1))
		expect(Bond.stage(person,RESIDENT)<STAGE and not done_stages().has(STAGE),"The story remains locked before the required friendship")
		var gift:="sapling" if day<3 else "radish"
		expect(act("resident_gift",cell,RESIDENT+":"+gift).ok,"Give Xinghe "+gift)
	expect(Bond.points(person,RESIDENT)==Bond.THRESHOLDS[STAGE-1] and Bond.stage(person,RESIDENT)==STAGE,"The fourth day's ordinary gift reaches exactly 14 points")
	expect(person.inventory.sapling==0 and person.inventory.radish==0,"All four gifts were taken")
	app.session._send_snapshot(1)

func run()->void:
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	tag="%dx%d%s"%[root.size.x,root.size.y,"-large" if large_text else ""]
	var path:="user://xinghe-story-%d.json"%OS.get_process_id()
	app.session.profile.token="xinghe-story-qa"
	if app.session.host(0,"星禾小溫室",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	person=world.state.players[owner]
	app.sound.reduced_motion=large_text

	# A non-winter day (summer): the event never asks for winter login.
	world.state.time=World.WEATHER.DAY_SECONDS*World.WEATHER.DAYS_PER_SEASON+650.0
	var season:String=World.WEATHER.season_on_day(floor(world.state.time/World.WEATHER.DAY_SECONDS))
	expect(season!="winter","Fixture clock is outside winter: "+season)

	# Begin after the opening picnic, with ordinary gifts and construction supplies.
	world.state.picnic=true
	person.inventory.merge({"wood":220,"stone":40,"crystal_sand":2,"charcoal":1,"copper_ingot":4,"copper_joint":1},true)
	person.inventory.erase("glass")
	expect(not person.get("greenhouse_glass_crafted",false),"Fresh save has not crafted glass yet")
	stand_home()
	expect(act("build",BENCH,"bench").ok and world.state.objects.get(World.key(BENCH),{}).get("type")=="bench","A real workbench is built at home")

	# Both rewards are locked before the event is done.
	expect(act("build",PLOT,Nursery.KIND).message==Nursery.UNLOCK_MESSAGE,"The nursery box waits for the event")
	expect(not act("build",PLOT,ROOF).ok and not world.state.roofs.has(World.key(PLOT)),"The workshop roof waits for the event")

	# Gate 1: exact materials alone are not enough without personally crafted glass.
	person.inventory.glass=int(ITEMS.glass)
	person.inventory.copper_joint=int(ITEMS.copper_joint)
	var site:=stand_at_resident()
	earn_trust(site[1])
	expect(str(app.session.snapshot.resident_goals[RESIDENT][str(STAGE)].state)=="open","The trust event is open at friendship stage 3")
	await open_goal_page()
	var do_button:=button("BondGoalDo")
	expect(do_button!=null and do_button.disabled and reason_text().begins_with("要先"),"Materials without self-crafted glass: the button names the missing step ("+reason_text()+")")
	await capture("01-needs-crafted-glass")
	var early:=act(Goals.ACTION,site[1],"%s:%d::"%[RESIDENT,STAGE])
	expect(not early.ok and not done_stages().has(STAGE) and int(person.inventory.glass)==2 and int(person.inventory.copper_joint)==2,"The server also refuses and takes nothing")
	app._close_modal()
	person.inventory.erase("glass")

	# Gate 2: the personal crafting action at the bench, not a flag write.
	stand_home()
	await perform("craft",BENCH,"glass")
	expect(person.get("greenhouse_glass_crafted",false)==true,"Crafting at the workbench records the personal flag")
	expect(int(person.inventory.get("glass",0))==int(World.CRAFT.glass.yield) and int(person.inventory.get("crystal_sand",0))==0 and int(person.inventory.get("charcoal",0))==0,"One batch makes exactly the event's glass from sand and charcoal")

	# Gate 3: one joint short is named on the page, then the exact bundle enables it.
	person.inventory.copper_joint=1
	stand_at_resident()
	await open_goal_page()
	do_button=button("BondGoalDo")
	var short:="還差%s %d／%d。"%[str(World.NAMES.copper_joint),1,int(ITEMS.copper_joint)]
	expect(do_button!=null and do_button.disabled and reason_text()==short,"One copper joint short: "+reason_text())
	app._close_modal()
	person.inventory.copper_joint=int(ITEMS.copper_joint)
	var spare:={"wood":int(person.inventory.wood),"stone":int(person.inventory.stone),"copper_ingot":int(person.inventory.copper_ingot)}
	app.session._send_snapshot(1)
	await open_goal_page()
	expect(button("BondGoalDo")!=null and not button("BondGoalDo").disabled and reason_text().is_empty(),"Self-crafted glass plus the exact bundle enables 一起完成")
	for item:String in ITEMS:
		var row:Node=app.modal.find_child("BondGoalCost_"+item,true,false)
		expect(row!=null,"The page lists the cost row for "+item)
	await press("BondGoalDo")
	expect(done_stages().has(STAGE),"The hand-in completes the trust event")
	expect(int(person.inventory.get("glass",0))==0 and int(person.inventory.get("copper_joint",0))==0,"Exactly 2 glass and 2 copper joints are taken")
	for item:String in spare:expect(int(person.inventory.get(item,0))==int(spare[item]),"Unrelated stock untouched: "+item)
	expect(not act(Goals.ACTION,site[1],"%s:%d::"%[RESIDENT,STAGE]).ok and int(person.inventory.get("glass",0))==0,"A second hand-in is refused and charges nothing")

	# The finished page shows the result and both reward links.
	app.session._send_snapshot(1)
	await open_goal_page()
	expect(is_instance_valid(app.modal) and app.modal.find_child("BondGoalDone",true,false)!=null,"The relation page shows the finished event")
	expect(button("XingheGreenhousePattern")!=null and button("XingheNurseryPattern")!=null,"Both reward links are offered after completion")
	for id in ["XingheGreenhousePattern","XingheNurseryPattern"]:
		var pattern:=button(id)
		expect(pattern!=null and pattern.icon!=null and pattern.is_visible_in_tree(),"The reward link is illustrated: "+id)
	await capture("02-relation-result")
	app._close_modal()

	# Back home with fresh glass: both links open the real workshop.
	stand_home()
	person.inventory.merge({"crystal_sand":20,"charcoal":10,"copper_ingot":4},true)
	for batch in 10:await perform("craft",BENCH,"glass")
	expect(int(person.inventory.get("glass",0))==20,"Ten more batches make glass for the roof and the box")
	await open_goal_page()
	await press("XingheGreenhousePattern")
	var place:=button("BuildPlace")
	expect(place!=null and not place.disabled,"The roof pattern opens the workshop with an enabled recipe")
	await capture("03-roof-workshop")
	app._close_modal()
	await open_goal_page()
	await press("XingheNurseryPattern")
	place=button("BuildPlace")
	expect(place!=null and not place.disabled,"The nursery pattern opens the workshop with an enabled recipe")
	await capture("04-nursery-workshop")
	if place!=null and not place.disabled:
		place.pressed.emit()
		await frames()
	expect(app.building==Nursery.KIND,"The normal build tool holds the nursery box")
	var glass_before:=int(person.inventory.glass)
	var wood_before:=int(person.inventory.wood)
	app.session.rates[1].clear()
	app._perform_build_action("build",PLOT,Nursery.KIND)
	await frames()
	expect(world.state.objects.get(World.key(PLOT),{}).get("type")==Nursery.KIND and int(person.inventory.glass)==glass_before-4 and int(person.inventory.wood)==wood_before-10,"The workshop places the box and charges its recipe")

	# Perimeter, door, four roof tiles: the room is sealed with the unlocked pieces.
	for side:Vector2i in BORDER:
		var result:=act("build",side,"window" if side==Vector2i(41,33) else "wall")
		expect(result.ok,"Build wall piece at %s: %s"%[side,result.message])
	expect(act("build",DOOR,"door").ok,"Build the door")
	var ingots:=int(person.inventory.copper_ingot)
	for tile:Vector2i in ROOF_TILES:expect(act("build",tile,ROOF).ok,"Build roof tile at %s"%str(tile))
	expect(int(person.inventory.copper_ingot)==ingots-ROOF_TILES.size(),"Each roof tile costs one copper ingot")
	expect(world.greenhouse_covers(World.key(PLOT)) and world.greenhouse_covers(World.key(PLOT+Vector2i.RIGHT)),"Both halves of the box sit in the sealed greenhouse")
	person.y=35.25
	app.session._send_snapshot(1)
	app._interact()
	await frames()
	expect(button("NurserySlot_0")!=null,"Normal interaction opens the placed nursery")
	if is_instance_valid(app.modal):app._close_modal()
	await frames()
	app.view.zoom=2.0
	app.view.camera=Vector2(41.0,34.7)*32.0-Vector2(root.size)/4.0
	await capture("05-greenhouse-built")
	stand(World.REGIONS.HOME,Vector2(44.5,35.5))
	await frames()
	app.view.camera=Vector2(41.0,34.7)*32.0-Vector2(root.size)/4.0
	await capture("06-greenhouse-roof-outside")

	# Persistence: exact progress survives a reload from the primary save.
	var final_glass:=int(person.inventory.glass)
	expect(world.save(),"Write the save")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The save reloads from its primary file")
	var saved:Dictionary=loaded.state.players.get(owner,{})
	expect(Goals.done(saved,RESIDENT).has(STAGE) and saved.get("greenhouse_glass_crafted",false)==true,"Reload keeps the finished event and the crafted-glass flag")
	expect(int(saved.inventory.get("copper_joint",0))==0 and int(saved.inventory.get("glass",0))==final_glass,"Reload keeps the post-hand-in and post-build stock")
	expect(loaded.state.objects.get(World.key(PLOT),{}).get("type")==Nursery.KIND,"Reload keeps the nursery box")
	for tile:Vector2i in ROOF_TILES:expect(loaded.state.roofs.get(World.key(tile),{}).get("type")==ROOF,"Reload keeps roof tile %s"%str(tile))
	expect(loaded.greenhouse_covers(World.key(PLOT)),"The reloaded room is still sealed")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XINGHE_GREENHOUSE_STORY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
