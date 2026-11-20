extends SceneTree

const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/inventory_item_art.gd")
const Industry=World.INDUSTRY
const BENCH:=Vector2i(39,34)
const WOODEN:=Vector2i(41,34)
const ROUND:=Vector2i(42,34)
# T069 S09 material chain. Amounts follow the live tables, nothing is seeded for these three items:
#   crystal_sand: 1 per gather at Coast.STAR_SAND, shared 90 s renewal, only after the boardwalk repair.
#   seashell:     1 per gather at Coast.SHELL_CELL, shared 90 s renewal, low tide only (120 s of every 240 s).
#   glass:        World.CRAFT.glass = 2 crystal_sand + 1 charcoal -> 2 glass at a workbench.
# Needs: 3 patterns x (2 glass + 3 seashell) + shell round table (4 seashell) = 6 glass, 13 seashell.
const Coast=preload("res://scripts/wangan_coast.gd")
const START_TIME:=720.0
const STEP_SECONDS:=30.0
const MAX_STEPS:=200
const GLASS_BATCHES:=3
const SAND_NEEDED:=6
const SHELLS_NEEDED:=13
var serial:=0
var app
var world:World
var owner:String
var path:String
var output:String
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

func stand_near(tile:Vector2i)->void:
	var person:Dictionary=world.state.players[owner]
	person.x=tile.x+0.5
	person.y=tile.y-0.5
	app.session._send_snapshot(1)

func bag(item:String)->int:
	return int(world.state.players[owner].inventory.get(item,0))

## Position fixture only: the 3.2-tile reach rule of World._apply is satisfied by standing on the point.
func stand_on(tile:Vector2i)->void:
	var person:Dictionary=world.state.players[owner]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

## A real World.act transaction (receipt, journal and save) with a fresh request id.
func coast_act(label:String,action:String,tile:Vector2i)->Dictionary:
	serial+=1
	return world.act(owner,"t069-%s-%d"%[label,serial],action,tile)

## Boardwalk repair through the real action. Dependencies examined in world.gd: the repair branch only
## needs the HOME region, the project sign cell, reach and Coast.STAR_COST; it has no story gate, so a
## fresh world is already the legitimate starting milestone. Only the 8 planks are fixtured (sawmill
## output upstream); the 4 fiber come from the ordinary starter backpack.
func repair_boardwalk()->bool:
	expect(not world.state.wangan_star_walk and float(world.state.wangan_star_sand_ready)==0.0,"A fresh world starts with the star coast boardwalk unrepaired")
	expect(bag("crystal_sand")==0 and bag(Coast.SHELL_ITEM)==0 and bag("glass")==0,"The maker starts with zero crystal sand, shells and glass")
	expect(world.blocked(Coast.STAR_SAND),"The unrepaired star shore cannot be walked on")
	stand_on(Coast.STAR_SAND)
	var early:=coast_act("sand-before-repair",Coast.STAR_SAND_POINT,Coast.STAR_SAND)
	expect(not early.ok and bag("crystal_sand")==0,"Crystal sand cannot be gathered before the repair: "+str(early.get("message","")))
	stand_on(Coast.STAR_REPAIR)
	var unfunded:=coast_act("repair-unfunded",Coast.STAR_REPAIR_POINT,Coast.STAR_REPAIR)
	expect(not unfunded.ok and not world.state.wangan_star_walk,"The repair is refused without planks: "+str(unfunded.get("message","")))
	var inventory:Dictionary=world.state.players[owner].inventory
	inventory["plank"]=int(Coast.STAR_COST.plank)
	var fiber_before:=bag("fiber")
	var repair:=coast_act("repair",Coast.STAR_REPAIR_POINT,Coast.STAR_REPAIR)
	if not expect(repair.ok and world.state.wangan_star_walk,"The real repair action opens the star coast boardwalk: "+str(repair.get("message",""))):return false
	expect(bag("plank")==0 and bag("fiber")==fiber_before-int(Coast.STAR_COST.fiber),"The repair consumes exactly 8 planks and 4 fiber")
	expect(not world.blocked(Coast.STAR_SAND),"The repaired star shore is walkable")
	expect(not coast_act("repair-again",Coast.STAR_REPAIR_POINT,Coast.STAR_REPAIR).ok,"The boardwalk cannot be repaired twice")
	return true

## Gathers every unit through the real point actions. Both points give one unit and then renew for
## 90 s; shells additionally need low tide, so world time is advanced with World.step (the session's
## own physics tick is off, making the clock deterministic). Standing position is the only fixture.
func gather_materials()->bool:
	var started:=float(world.state.time)
	expect(Coast.high_tide(started),"The time fixture starts at high tide")
	stand_on(Coast.SHELL_CELL)
	var flooded:=coast_act("shell-high-tide",Coast.SHELL_POINT,Coast.SHELL_CELL)
	expect(not flooded.ok and bag(Coast.SHELL_ITEM)==0,"High tide refuses shell gathering: "+str(flooded.get("message","")))
	var sand_taken:=0
	var shells_taken:=0
	var steps:=0
	while (sand_taken<SAND_NEEDED or shells_taken<SHELLS_NEEDED) and steps<MAX_STEPS:
		var now:=float(world.state.time)
		var gathered:=false
		if sand_taken<SAND_NEEDED and now>=float(world.state.wangan_star_sand_ready):
			stand_on(Coast.STAR_SAND)
			var sand:=coast_act("sand",Coast.STAR_SAND_POINT,Coast.STAR_SAND)
			if not expect(sand.ok and bag("crystal_sand")==sand_taken+1,"Sand gather %d yields exactly one crystal sand: %s"%[sand_taken+1,str(sand.get("message",""))]):return false
			sand_taken+=1
			gathered=true
			if sand_taken==1:
				expect(is_equal_approx(float(world.state.wangan_star_sand_ready),now+Coast.STAR_SAND_RESPAWN),"Sand renews 90 s after a gather")
				expect(not coast_act("sand-early",Coast.STAR_SAND_POINT,Coast.STAR_SAND).ok and bag("crystal_sand")==1,"The sand point gives nothing more until it renews")
		if shells_taken<SHELLS_NEEDED and now>=float(world.state.wangan_shell_ready) and not Coast.high_tide(now):
			stand_on(Coast.SHELL_CELL)
			var shell:=coast_act("shell",Coast.SHELL_POINT,Coast.SHELL_CELL)
			if not expect(shell.ok and bag(Coast.SHELL_ITEM)==shells_taken+1,"Shell gather %d yields exactly one seashell: %s"%[shells_taken+1,str(shell.get("message",""))]):return false
			shells_taken+=1
			gathered=true
			if shells_taken==1:
				expect(is_equal_approx(float(world.state.wangan_shell_ready),now+Coast.SHELL_RESPAWN),"Shells renew 90 s after a gather")
				expect(not coast_act("shell-early",Coast.SHELL_POINT,Coast.SHELL_CELL).ok and bag(Coast.SHELL_ITEM)==1,"The shell point gives nothing more until it renews")
		if gathered:continue
		steps+=1
		if not expect(world.step(STEP_SECONDS,true),"World time advances by a normal step: "+str(world.step_error)):return false
	var elapsed:=float(world.state.time)-started
	print("SHELL_BOTTLE_CHAIN sand=%d shells=%d steps=%d elapsed=%.0fs days=%.2f"%[sand_taken,shells_taken,steps,elapsed,elapsed/World.WEATHER.DAY_SECONDS])
	expect(bag("crystal_sand")==SAND_NEEDED and bag(Coast.SHELL_ITEM)==SHELLS_NEEDED,"Natural gathering alone supplies 6 crystal sand and 13 shells")
	expect(steps>0 and elapsed>=float(SHELLS_NEEDED-1)*Coast.SHELL_RESPAWN,"The supply needed real renewal time rather than a single visit")
	var saved:=World.new()
	return expect(saved.load_world(path) and not saved.recovered_from_backup and saved.state.wangan_star_walk==true and int(saved.state.players[owner].inventory.get("crystal_sand",0))==SAND_NEEDED and int(saved.state.players[owner].inventory.get(Coast.SHELL_ITEM,0))==SHELLS_NEEDED,"The repaired coast and gathered materials reload from a valid primary save")

func place_bottle(tile:Vector2i,item:String)->void:
	stand_near(tile)
	app._interact()
	var picker:=app.modal.find_child("ShellTablePicker",true,false) as OptionButton if is_instance_valid(app.modal) else null
	if not expect(picker!=null,"Interact opens the tabletop panel"):return
	for index in picker.item_count:
		if picker.get_item_metadata(index)==item:
			picker.select(index)
			var put:=app.modal.find_child("ShellTablePut",true,false) as Button
			put.pressed.emit()
			expect(world.state.objects[World.key(tile)].items=={item:1},"Chosen pattern is placed on the table")
			return
	expect(false,"The maker can select %s from the backpack"%item)

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHELL_BOTTLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://shell-bottle-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="shell-bottle-owner"
	if app.session.host(0,"海邊工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	# Fixtures, each an ordinary upstream prerequisite and nothing from the tested chain:
	#   wood/stone  furniture and workbench costs (axe and pick gathering);
	#   charcoal    3 units of kiln fuel, one per glass batch;
	#   plank       8 units, added inside repair_boardwalk after the unfunded refusal;
	#   time        noon, which is also high tide; cleared build tiles; standing positions.
	person.inventory.merge({"wood":80,"stone":14,"charcoal":GLASS_BATCHES},true)
	world.state.time=START_TIME
	for tile in [BENCH,WOODEN,ROUND]:world.state.removed[World.key(tile)]=true
	if not repair_boardwalk() or not gather_materials():
		finish()
		return
	person=world.state.players[owner]
	app.session._send_snapshot(1)
	await capture("south-shore-shells")
	stand_on(Coast.STAR_SAND)
	app.session._send_snapshot(1)
	await capture("star-coast-materials")
	stand_near(WOODEN)
	app.session.perform("build",WOODEN,"table")
	app.session.perform("build",ROUND,Industry.SHELL_TABLE)
	expect(world.state.objects.get(World.key(ROUND),{}).get("type","")==Industry.SHELL_TABLE and bag(Coast.SHELL_ITEM)==SHELLS_NEEDED-4,"The shell round table is built from four gathered shells")
	stand_near(BENCH)
	app.session.perform("build",BENCH,"bench")
	app._interact()
	for batch in GLASS_BATCHES:
		var glass_recipe:=app.modal.find_child("WorkbenchRecipe_glass",true,false) as Button if is_instance_valid(app.modal) else null
		if not expect(glass_recipe!=null,"The workbench offers the glass recipe"):
			finish()
			return
		glass_recipe.pressed.emit()
		var smelt:=app.modal.find_child("CraftRecipe",true,false) as Button
		if not expect(smelt!=null and not smelt.disabled,"Glass batch %d can be crafted from gathered sand"%(batch+1)):
			finish()
			return
		smelt.pressed.emit()
		for frame in range(30):
			if bag("glass")==(batch+1)*2:break
			await process_frame
		expect(bag("glass")==(batch+1)*2 and bag("crystal_sand")==SAND_NEEDED-(batch+1)*2 and bag("charcoal")==GLASS_BATCHES-batch-1,"Each batch turns two crystal sand and one charcoal into two glass")
	person=world.state.players[owner]
	expect(person.get("greenhouse_glass_crafted",false)==true and bag("glass")==6 and bag("crystal_sand")==0,"All six glass came from the real workbench recipe")
	# The session accepts 12 actions per second; let the builds and glass batches leave that window.
	await create_timer(1.1).timeout
	var patterns:Array=Industry.SHELL_BOTTLES
	var images:Dictionary={}
	for index in patterns.size():
		var id:String=patterns[index]
		var button:=app.modal.find_child("WorkbenchRecipe_"+id,true,false) as Button if is_instance_valid(app.modal) else null
		if not expect(button!=null and button.icon!=null,"Workbench offers an illustrated recipe for "+id):
			finish()
			return
		button.pressed.emit()
		images[button.icon.get_image().get_data().hex_encode()]=true
		if index==patterns.size()-1:await capture("workbench-three-patterns")
		var craft:=app.modal.find_child("CraftRecipe",true,false) as Button
		if not expect(craft!=null and not craft.disabled,"The selected pattern can be crafted"):
			finish()
			return
		craft.pressed.emit()
		for frame in range(30):
			if int(person.inventory.get(id,0))==1:break
			await process_frame
		expect(int(person.inventory.get(id,0))==1,"Crafting yields the chosen pattern exactly once")
		expect(int(person.inventory.glass)==4-index*2 and int(person.inventory.seashell)==6-index*3,"Each pattern costs two glass and three shells")
	expect(images.size()==3,"The three recipes use distinct pixel art")
	expect(not world.act(owner,"no-materials","craft",BENCH,patterns[0]).ok,"Insufficient materials generate no extra bottle")
	app._close_modal()
	place_bottle(WOODEN,patterns[0])
	app._close_modal()
	place_bottle(ROUND,patterns[1])
	app._close_modal()
	await capture("bottles-on-tables")
	var loaded:=World.new()
	var wooden_key:=World.key(WOODEN)
	var round_key:=World.key(ROUND)
	expect(loaded.load_world(path) and loaded.state.objects[wooden_key].items=={patterns[0]:1} and loaded.state.objects[round_key].items=={patterns[1]:1},"Both table displays retain their exact pattern on reload")
	var guest:="shell-bottle-guest"
	world.add_player(guest,"旅客",Vector2(41.5,33.5))
	expect(not world.act(guest,"guest-take",Industry.SHELL_TAKE,WOODEN,patterns[0]).ok,"Guest cannot take a displayed bottle")
	expect(not world.act(owner,"remove-full","remove",WOODEN).ok,"A displayed bottle prevents accidental dismantling")
	stand_near(WOODEN)
	app._interact()
	var take:=app.modal.find_child("ShellTableTake",true,false) as Button if is_instance_valid(app.modal) else null
	if expect(take!=null and take.visible,"Owner can retrieve the decorated bottle"):take.pressed.emit()
	expect(int(person.inventory.get(patterns[0],0))==1 and world.state.objects[wooden_key].items.is_empty(),"Taking the bottle returns the same pattern")
	app._close_modal()
	place_bottle(WOODEN,patterns[2])
	app._close_modal()
	await capture("tide-pattern-on-table")
	finish()
