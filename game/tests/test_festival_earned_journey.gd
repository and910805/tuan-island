extends "res://tests/test_salt_pan_journey.gd"
## T068 chapter-five dock-to-festival journey on top of the latest NORMAL earned
## fixture (test_salt_pan_journey.gd, itself extending test_flower_journey.gd).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Provenance
##  * The unmodified salt-pan journey runs first in a fresh temp world (its own
##    assertions included): chapter one (board/picnic), tea route, Tianwei garden,
##    Beimen salt pans repaired, twelve islanders. No saved artifact is read.
##  * That earned save is then DUPLICATED to a unique temp path. Every festival
##    action runs on the duplicate; the source save's SHA-256 is checked unchanged.
####
## What is EARNED here (World.act after World.move_player along BFS routes,
## World.step for waits; deltas checked):
##  * dock_repair stages 0 and 1 (planks from an own sawmill, copper joints from
##    the practice vein, stone/fiber/wood gathered with axe/pick);
##  * the shared meal: buy a watermelon seed at Xiaoli's stall with earned coins,
##    hoe/seed/water/harvest in summer, cook watermelon_platter on the stove,
##    claim_cook, serve_watermelon on the picnic table;
##  * two own wooden lamps built within the 7x7 window around the table;
##  * festival_story_open at the dock board (40,29).
##
## All six public projects are earned in this journey.
## The save is read back with a plain World twice after opening.
##
## Negative gates exercised (exact messages, state unchanged): boat not ready,
## stale dock stage extra, missing dock material (when actually short), dock
## already repaired, projects/meal/lamps missing, one lamp only, wrong board
## cell, missing projects on a plain World, repeat opening (opener and late
## member, after restart), repeat watermelon claim after a second restart.
##
## The salt-chapter holdings ledger (sledger) is retired after the parent run:
## festival actions spend tracked items (plank/stone/coins) by design. Sea-salt
## and kit conservation checks keep running inside the inherited helpers.
##
## Optional evidence: --festival-output=<existing dir> keeps the final duplicate
## save and a JSON report there (never overwrites). Otherwise all temp files
## created by this run are removed.
## Prints FESTIVAL_EARNED_JOURNEY ... and FESTIVAL_EARNED_JOURNEY_TESTS lines
## before the parent's SALT_PAN_JOURNEY lines; exit code is the parent's.

const BOARD:=Vector2i(40,29)
const LATE:="festival-late-member"
const MSG_WHERE:="請到渡口公告板籌備風鈴節。"
const MSG_BOAT:="先完成第四章的碼頭與小船工程。"
const MSG_GATE:="請先完成六項工程、準備共餐，並在共餐桌周圍放兩盞燈。"
const MSG_OPENED:="風鈴節已經開幕，可以重看回憶。"
const MSG_DOCK_STALE:="工程進度有更新，請重新查看。"
const MSG_DOCK_DONE:="碼頭和小船都已修復。"
const MSG_CLAIMED:="你已領過這一輪，剩下的留給其他島民。"
const PROJECT_NAMES:=["dock_board","lanyang_repair","tianwei_garden","beimen_salt","public_kitchen","mine_depth_5"]
const REQUIRED_EARNED_BITS:=(1<<1)|(1<<2)|(1<<3)|(1<<5)
const REPLAYS:=3
const REPORT_FILES:=["festival-earned-complete.json","festival-earned-report.json"]

var fest_path:=""
var output_dir:=""
var fest_started:=false
var fest_checks_start:=0
var fest_failures_start:=0
var source_sha:=""
var real_mask:=-1
var lamp_cells:Array[Vector2i]=[]
var melon_plot:=Vector2i(-1,-1)
var spent:={}
var refusals:=[]
var fest_actions_start:=0
var fest_walk_start:=0
var time_start:=0.0
var restarts:=0
var moved_residents:=[]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--festival-output="):output_dir=argument.trim_prefix("--festival-output=")
	super._initialize()

func finish() -> void:
	if fest_started:
		var passed:=failures==fest_failures_start and not failed
		print("FESTIVAL_EARNED_JOURNEY label=\"%s\" source=test_salt_pan_journey earned_mask=%d dock_stage=%d lamps=%s melon_plot=%s spent=%s refusals=%d restarts=%d moved_residents=%s actions=%d walk_tiles=%d world_seconds=%.1f festival_world_seconds=%.1f passed=%s"%[SALT_LABEL,real_mask,int(world.state.get("dock_stage",0)),str(lamp_cells),str(melon_plot),JSON.stringify(spent),refusals.size(),restarts,JSON.stringify(moved_residents),actions-fest_actions_start,walking-fest_walk_start,float(world.state.get("time",0.0)),float(world.state.get("time",0.0))-time_start,passed])
		print("FESTIVAL_EARNED_JOURNEY_TESTS checks=%d failures=%d (festival slice: checks=%d failures=%d)"%[checks,failures,checks-fest_checks_start,failures-fest_failures_start])
	for file in [fest_path,fest_path+".bak",fest_path+".tmp"]:
		if not file.is_empty() and file.begins_with(OS.get_environment("TEMP")) and FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	super.finish()

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	print("FESTIVAL salt-pan earned prerequisite passed (checks so far %d, world_seconds %.1f)"%[checks,now()])
	fest_started=true
	fest_checks_start=checks
	fest_failures_start=failures
	fest_actions_start=actions
	fest_walk_start=walking
	sledger.clear()
	tok=TOKEN_A
	go_home()
	if failed:return
	repair_lanyang()
	if failed:return
	commission_deep_mine()
	if failed:return
	fork_fixture()
	if failed:return
	time_start=now()
	dock_gates()
	if failed:return
	dock_repairs()
	if failed:return
	deliver_festival_commissions()
	if failed:return
	shared_meal()
	if failed:return
	lamps_and_open()
	if failed:return
	expect(FileAccess.get_sha256(save_path)==source_sha,"source earned save untouched by the festival duplicate (sha256)")
	restart_and_replay()
	if failed:return
	second_restart()
	if failed:return
	keep_evidence()

func complete_outlying_commissions() -> void:
	# The prerequisite journey normally repairs the dock. This test earns the
	# same two stages after Beimen so it can exercise the pre-dock festival gate.
	pass

func go_home() -> void:
	var region:=world.player_region(tok)
	if region==S.REGION:strav(S.TRANSFER,"home")
	elif region==F.REGION:strav(tianwei_cell(),"home")
	expect(world.player_region(tok)=="home","A is back home for chapter five (was %s)"%region)

func repair_lanyang() -> void:
	var waterworks:=World.LANYANG_LIFE
	var cost:Dictionary=waterworks.REPAIR_COST.duplicate()
	cost.merge({"fiber":0,"copper_joint":0,"wood_extra":0})
	produce(cost)
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	for cell:Vector2i in waterworks.BLOCKAGES:
		act("lanyang_clear",cell)
	if failed:return
	var before:=bag().duplicate()
	act("lanyang_donate",waterworks.SERVICE)
	for item:String in waterworks.REPAIR_COST:
		expect(int(bag().get(item,0))==int(before.get(item,0))-int(cost[item]),"Waterway consumes the earned "+item)
	expect(world.state.lanyang_life.repaired,"Lanyang repair is saved by the real public action")
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")

func commission_deep_mine() -> void:
	var mine:=World.MINES
	var costs:={"wood":0,"stone":0,"resin":0,"plank":0,"copper_joint":0}
	for recipe:String in ["kiln_kit","pump_kit","pipe_kit","tank_kit"]:
		for item:String in World.CRAFT[recipe].ingredients:
			if costs.has(item):costs[item]+=int(World.CRAFT[recipe].ingredients[item])
	# The fifth-floor festival project needs B1–B4 only (T067 deep commissions follow).
	for stage:Dictionary in mine.COSTS.slice(0,mine.SHALLOW_DEPTH-1):
		for item:String in stage:costs[item]+=int(stage[item])
	costs.wood+=int(World.INDUSTRY.PROCESS.charcoal.ingredients.wood)
	costs.wood_extra=costs.wood
	costs.fiber=0
	produce(costs)
	if failed:return
	var kiln:=open_cell()
	if not expect(kiln!=Vector2i(-1,-1),"Find a buildable spot for the charcoal kiln"):return
	craft("kiln_kit")
	act("build",kiln,"charcoal_kiln")
	act("start_processing",kiln,"charcoal")
	wait(float(World.INDUSTRY.PROCESS.charcoal.time))
	act("claim_processing",kiln)
	for kit:String in ["pump_kit","pipe_kit","tank_kit"]:craft(kit)
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").bus.cell,"jiufen")
	travel(World.TRANSIT.points("jiufen").shuttle.cell,"jinguashi")
	act("mine_travel",mine.ENTRY,mine.IDS[0])
	for depth in range(4):
		if failed:return
		if depth==2:
			act("build",Vector2i(29,23),"water_pump")
			act("build",Vector2i(30,23),"water_pipe")
			act("build",Vector2i(31,23),"water_tank")
			act("toggle_pump",Vector2i(29,23))
			for tick in range(3):wait(World.INDUSTRY.INTERVAL)
			expect(int(world.state.mine_depths.pumped)==24,"Working pump drains the third level")
		act("mine_commission",mine.SERVICE)
		act("mine_travel",mine.DOWN,mine.IDS[depth+1])
	expect(world.player_region(tok)==mine.IDS[4] and int(world.state.mine_depths.unlocked)==5,"Real commissions and drainage open the fifth level")
	act("pick",mine.NODES[0])
	expect(int(bag().get("gold_ore",0))>0,"The deepest work face is accessible")
	for depth in range(4,0,-1):act("mine_travel",mine.UP,mine.IDS[depth-1])
	act("mine_travel",mine.UP,"jinguashi")
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")

func fork_fixture() -> void:
	expect(world.save(),"source earned save written before forking")
	source_sha=FileAccess.get_sha256(save_path)
	var temp:=OS.get_environment("TEMP")
	var id:=Crypto.new().generate_random_bytes(8).hex_encode()
	fest_path=temp.path_join("festival-earned-%s.json"%id)
	for file in [fest_path,fest_path+".bak"]:
		if FileAccess.file_exists(file):
			fest_path=""
			expect(false,"temp path already exists, refusing to adopt it: "+file)
			return
	if not output_dir.is_empty():
		expect(DirAccess.dir_exists_absolute(output_dir),"explicit output directory exists: "+output_dir)
		for report_name in REPORT_FILES:expect(not FileAccess.file_exists(output_dir.path_join(report_name)),"evidence never overwritten: "+report_name)
	if failed:return
	expect(DirAccess.copy_absolute(save_path,fest_path)==OK,"earned save duplicated to an isolated festival path")
	var fixture:=World.new()
	if not expect(fixture.load_world(fest_path) and not fixture.recovered_from_backup,"festival duplicate loads through SaveSchema"):return
	fixture.save_path=fest_path
	fixture.add_player(TOKEN_A,str(names.get(TOKEN_A,"Bloom A")))
	real_mask=fixture.island_project_mask()
	expect(real_mask&REQUIRED_EARNED_BITS==REQUIRED_EARNED_BITS,"waterway, garden, salt-pan and deep-mine projects are earned in the fixture (mask %d)"%real_mask)
	expect(bool(fixture.state.picnic) and World.COMMUNITY.table_cell(fixture.state)!=World.COMMUNITY.NO_CELL,"earned picnic table exists")
	expect(World.CHAPTER_ONE.phase(fixture.state)=="complete","chapter one earned complete")
	expect(int(fixture.state.get("dock_stage",0))==0 and not World.TRANSIT.boat_open(fixture.state),"dock not repaired in the earned fixture")
	expect(not fixture.festival_story_view().opened,"festival not opened in the earned fixture")
	world=fixture

# ---------------------------------------------------------------- dock

func dock_gates() -> void:
	frefuse("festival_story_open",BOARD,"",MSG_BOAT)
	frefuse("dock_repair",BOARD,"1",MSG_DOCK_STALE)
	var cost:Dictionary=World.DOCK_REPAIRS[0]
	for item in cost:
		if int(bag().get(item,0))<int(cost[item]):
			frefuse("dock_repair",BOARD,"0","還需要 %s。"%World.NAMES[item])
			break

func dock_repairs() -> void:
	var need:={}
	for stage in World.DOCK_REPAIRS:
		for item in stage:need[item]=int(need.get(item,0))+int(stage[item])
	produce({"plank":int(need.plank),"resin":0,"stone":int(need.stone),"fiber":int(need.fiber),"copper_joint":int(need.copper_joint),"wood_extra":0})
	if failed:return
	for stage in World.DOCK_REPAIRS.size():
		var cost:Dictionary=World.DOCK_REPAIRS[stage]
		var before:=bag().duplicate(true)
		act("dock_repair",BOARD,str(stage))
		if failed:return
		for item in cost:
			expect(int(bag().get(item,0))==int(before.get(item,0))-int(cost[item]),"dock stage %d debits exactly %d %s"%[stage,int(cost[item]),item])
			spent[item]=int(spent.get(item,0))+int(cost[item])
		expect(int(world.state.dock_stage)==stage+1,"dock_stage advanced to %d"%(stage+1))
	expect(World.TRANSIT.boat_open(world.state),"boat open after both earned dock stages")
	frefuse("dock_repair",BOARD,"2",MSG_DOCK_DONE)
	frefuse("festival_story_open",BOARD,"",MSG_GATE)
	frefuse("festival_story_open",BOARD+Vector2i(0,1),"",MSG_WHERE)

func deliver_festival_commissions() -> void:
	var commissions:Dictionary=World.OUTLYING_COMMISSIONS.DEFS
	gather_for_dock("stone","rock","pick",int(commissions.springs_footbath.needs.stone),2)
	for id:String in World.OUTLYING_COMMISSIONS.ids():
		if failed:return
		var destination:String=commissions[id].region
		travel(FERRY,destination)
		expect(person().get("outlying_boat_arrival",false),"Festival journey sails to "+destination)
		var station:Vector2i=World.TRANSIT.STATIONS[destination].cell
		act("outlying_deliver",station,id)
		travel(station,"home")

# ---------------------------------------------------------------- meal

func shared_meal() -> void:
	var table:=World.COMMUNITY.table_cell(world.state)
	for dish in World.COMMUNITY.DISHES:
		expect(int(world.state.get("community",{}).get(dish,{}).get("portions",0))==0,"no %s already on the table before the meal step"%dish)
	wait_for_summer()
	if failed:return
	var price:=int(World.CROPS.watermelon.seed_price)
	expect(int(person().coins)>=price,"BLOCKER check: earned coins %d cover a watermelon seed (%d)"%[int(person().coins),price])
	var coins:=int(person().coins)
	act("buy",RECEIVER,"watermelon")
	expect(int(person().coins)==coins-price and int(bag().get("watermelon_seed",0))>=1,"bought one watermelon seed with earned coins")
	spent.coins=price
	melon_plot=open_cell()
	if not expect(melon_plot!=Vector2i(-1,-1),"open home cell for a watermelon plot"):return
	act("hoe",melon_plot)
	act("seed",melon_plot,"watermelon")
	grow([melon_plot])
	var melons:=int(bag().get("watermelon",0))
	act("harvest",melon_plot)
	expect(int(bag().get("watermelon",0))>=melons+int(World.CROPS.watermelon.yield),"harvested an own summer watermelon")
	var recipe:Dictionary=World.RECIPES.watermelon_platter
	act("cook",stove_cell,"watermelon_platter")
	frefuse("claim_cook",stove_cell,"","還要 %d 秒就好了"%ceili(float(recipe.time)))
	wait(float(recipe.time))
	var platters:=int(bag().get("watermelon_platter",0))
	act("claim_cook",stove_cell)
	expect(int(bag().get("watermelon_platter",0))>=platters+World.COMMUNITY.HOTPOT_PORTIONS,"claimed at least %d cooked platters (recipe yield %d)"%[World.COMMUNITY.HOTPOT_PORTIONS,int(recipe.yield)])
	frefuse("festival_story_open",BOARD,"",MSG_GATE)
	act("serve_watermelon",table)
	expect(int(world.state.community.watermelon.portions)==World.COMMUNITY.HOTPOT_PORTIONS,"four earned platters on the shared table")
	expect(world.festival_story_view().meal,"festival plan sees the shared meal")

func wait_for_summer() -> void:
	var season_len:=float(WEATHER.DAYS_PER_SEASON)*WEATHER.DAY_SECONDS
	var year:=season_len*4.0
	var pos:=fposmod(now(),year)
	var dt:=0.0
	# Leave at least half a season of summer for growth (270 s) and cooking.
	if pos<season_len:dt=season_len-pos+60.0
	elif pos>season_len*1.5:dt=year-pos+season_len+60.0
	if dt>0.0:wait(dt,720.0)
	expect(WEATHER.season_on_day(WEATHER.day_index(now()))=="summer","world clock reached summer (t=%.1f, waited %.1f)"%[now(),dt])

# ---------------------------------------------------------------- lamps + opening

func lamps_and_open() -> void:
	var table:=World.COMMUNITY.table_cell(world.state)
	var lights:=int(world.festival_story_view().lights)
	if lights>=2:print("FESTIVAL note: fixture already had %d lamps near the table; one-lamp gate not exercised"%lights)
	var lamp_cost:Dictionary=World.BUILD.lamp
	var want:={}
	for item in lamp_cost:
		if item!="name":want[item]=int(bag().get(item,0))+int(lamp_cost[item])*maxi(0,2-lights)
	gather(want)
	if failed:return
	var residents_before:={}
	for id in World.Village.FESTIVAL_SPOTS:residents_before[id]=World.Village.resident_cell(world.state,id)
	while int(world.festival_story_view().lights)<2 and not failed:
		if int(world.festival_story_view().lights)==1:frefuse("festival_story_open",BOARD,"",MSG_GATE)
		var cell:=lamp_cell(table)
		if not expect(cell!=Vector2i(-1,-1),"free cell for a lamp within 3 tiles of the table %s"%str(table)):return
		var before:=bag().duplicate(true)
		act("build",cell,"lamp")
		for item in lamp_cost:
			if item=="name":continue
			expect(int(bag().get(item,0))==int(before.get(item,0))-int(lamp_cost[item]),"lamp debits %d %s"%[int(lamp_cost[item]),item])
			spent[item]=int(spent.get(item,0))+int(lamp_cost[item])
		lamp_cells.append(cell)
	expect(int(world.festival_story_view().lights)>=2,"two lamps counted around the table")
	frefuse("festival_story_open",BOARD,"",MSG_GATE)
	open_festival_kitchen()
	if failed:return
	var plan:=world.festival_story_view()
	expect(plan.boat_ready and plan.meal and int(plan.lights)>=2 and int(plan.projects)==World.ISLAND_NOTES.project_mask() and not plan.opened,"festival plan complete before opening: "+JSON.stringify(plan))
	var events:int=world.state.events.size()
	var portions:=int(world.state.community.watermelon.portions)
	act("festival_story_open",BOARD)
	expect(world.festival_story_view().opened and bool(world.state.festival_story_open),"festival opened by the board action")
	act(World.Deer.ACTION,World.Deer.site(world.state))
	expect(bool(world.state.players[tok].get("windbell_deer_seen",false)),"The festival journey ends with the visitor at the windbell tree")
	expect(int(world.state.community.watermelon.portions)==portions,"opening leaves the shared portions on the table")
	expect(world.state.events.size()>=events,"opening does not drop event history")
	for id in residents_before:
		var after:=World.Village.resident_cell(world.state,id)
		if after!=residents_before[id]:moved_residents.append(str(id))
	expect(not moved_residents.is_empty(),"residents gather at festival spots after opening")
	for id in World.Village.FESTIVAL_SPOTS:
		expect(world.protected(World.Village.FESTIVAL_SPOTS[id]),"festival spot %s protected after opening"%str(id))
	frefuse("festival_story_open",BOARD,"",MSG_OPENED)

func open_festival_kitchen() -> void:
	var kitchen:=World.PUBLIC_KITCHEN
	var quests:Array=World.Village.QUESTS.aru
	var cost:={"wood":0,"stone":0,"fiber":0}
	for kind in ["bed","long_bench","long_bench"]:
		for item in cost:cost[item]+=int(World.BUILD[kind].get(item,0))
	for stage in range(2):
		for item in cost:cost[item]+=int(quests[stage].items.get(item,0))
	gather(cost)
	var bed:=open_cell()
	if not expect(bed!=Vector2i(-1,-1),"Find room for Aru's bed"):return
	act("build",bed,"bed")
	for stage in range(2):
		act("quest",World.Village.NPCS.aru.cell,"aru:%d"%stage)
	var seats:Array[Vector2i]=[]
	for y in range(stove_cell.y-3,stove_cell.y+4):
		for x in range(stove_cell.x-3,stove_cell.x+4):
			var tile:=Vector2i(x,y)
			if seats.size()<2 and Vector2(tile-stove_cell).length()<=kitchen.SEAT_RANGE and lamp_ok(tile,false):
				act("build",tile,"long_bench")
				seats.append(tile)
	if not expect(seats.size()==2,"Find two kitchen benches beside the stove") or failed:return
	act(kitchen.REGISTER,stove_cell,kitchen.seat_extra(seats[0],seats[1]))
	for meal:String in kitchen.MEALS:
		var recipe:Dictionary=World.RECIPES[meal]
		var batches:=ceili(float(kitchen.REQUIREMENTS[meal])/float(recipe.yield))
		for crop:String in recipe.ingredients:
			var required:=batches*int(recipe.ingredients[crop])
			while not failed and int(bag().get(crop,0))<required:
				var plot:=open_cell()
				if not expect(plot!=Vector2i(-1,-1),"Find a free plot for "+crop):return
				wait_for_kitchen_crop(crop,plot)
				act("buy",RECEIVER,crop)
				act("hoe",plot)
				act("seed",plot,crop)
				grow([plot])
				act("harvest",plot)
		for batch in range(batches):
			if failed:return
			act("cook",stove_cell,meal)
			wait(float(recipe.time))
			act("claim_cook",stove_cell)
		act(kitchen.CONTRIBUTE,stove_cell)
	expect(world.state.public_kitchen.opened,"Cooking and donating all meals opens the public kitchen")
	real_mask=world.island_project_mask()
	expect(real_mask==World.ISLAND_NOTES.project_mask(),"All six projects are earned in the same save")

func wait_for_kitchen_crop(crop:String,plot:Vector2i) -> void:
	var duration:=float(World.CROPS[crop].time)
	var day:=WEATHER.day_index(now())
	var next_day:float=(day+1)*WEATHER.DAY_SECONDS
	if World.crop_grows_in_season(crop,"home",plot,now()) and now()+duration<next_day:return
	for offset in range(1,WEATHER.DAYS_PER_SEASON*4+1):
		var morning:float=(day+offset)*WEATHER.DAY_SECONDS
		if World.crop_grows_in_season(crop,"home",plot,morning):
			wait(morning-now(),720.0)
			return
	expect(false,"No growing season for "+crop)

func lamp_cell(table:Vector2i) -> Vector2i:
	for strict in [true,false]:
		for distance in range(1,4):
			for y in range(table.y-distance,table.y+distance+1):
				for x in range(table.x-distance,table.x+distance+1):
					var c:=Vector2i(x,y)
					if maxi(absi(x-table.x),absi(y-table.y))!=distance:continue
					if lamp_ok(c,strict):return c
	return Vector2i(-1,-1)

func lamp_ok(c:Vector2i,strict:bool) -> bool:
	if c==BOARD or c==RECEIVER or c==stove_cell:return false
	if c in World.Village.FESTIVAL_SPOTS.values() or World.Festival.VISITORS.has(c):return false
	if not world.is_land(c) or world.water(c) or world.protected(c) or world.resource(c)!="" or world.blocked(c):return false
	var k:=World.key(c)
	for layer in ["crops","objects","ground","roofs","forest"]:
		if world.state[layer].has(k):return false
	if strict:
		for dy in [-1,0,1]:
			for dx in [-1,0,1]:
				var n:=c+Vector2i(dx,dy)
				if world.blocked(n) or world.protected(n) or world.state.crops.has(World.key(n)):return false
	return not route(c).is_empty()

# ---------------------------------------------------------------- restart + replay

func reopen(label:String) -> World:
	var reopened:=World.new()
	if not expect(reopened.load_world(fest_path) and not reopened.recovered_from_backup,label+": festival save reloads in a plain World"):return null
	reopened.save_path=fest_path
	restarts+=1
	return reopened

func restart_and_replay() -> void:
	var expected_a:Dictionary=person().duplicate(true)
	var reopened:=reopen("restart")
	if reopened==null:return
	reopened.add_player(TOKEN_A,str(expected_a.name))
	world=reopened
	tok=TOKEN_A
	for field in ["x","y","coins","inventory","region"]:expect_same(person().get(field),expected_a.get(field),"restart: A %s preserved"%field)
	expect(world.festival_story_view().opened,"restart: opening persisted without any project override")
	expect(bool(person().get("windbell_deer_seen",false)),"restart: the earned visitor encounter is preserved")
	for id:String in World.OUTLYING_COMMISSIONS.ids():
		expect(World.OUTLYING_COMMISSIONS.done(world.state,TOKEN_A,id),"restart: festival journey retains local commission "+id)
	expect(int(world.state.dock_stage)==World.DOCK_REPAIRS.size() and int(world.state.community.watermelon.portions)==World.COMMUNITY.HOTPOT_PORTIONS,"restart: dock and shared meal persisted")
	for id in moved_residents:
		expect(World.Village.resident_cell(world.state,id)!=World.Village.NPCS[id].cell if World.Village.NPCS.has(id) else true,"restart: %s still at the festival"%id)
	frefuse("festival_story_open",BOARD,"",MSG_OPENED)
	world.add_player(LATE,"Late Member")
	tok=LATE
	frefuse("festival_story_open",BOARD,"",MSG_OPENED)
	var table:=World.COMMUNITY.table_cell(world.state)
	act("claim_watermelon",table)
	expect(int(bag().get("watermelon_platter",0))==1 and int(world.state.community.watermelon.portions)==World.COMMUNITY.HOTPOT_PORTIONS-1,"late member claims one festival portion")
	late_member_uses_public_facilities()
	if failed:return
	# Personal replay is read-only and repeatable.
	var scenes:=festival_scene_count()
	expect(scenes>=3,"festival memory has at least three replay scenes (%d)"%scenes)
	var before:=canon_bytes(world.state)
	for n in REPLAYS:
		var view:=world.festival_story_view()
		expect(view.opened,"replay %d sees the opened festival"%(n+1))
	expect(canon_bytes(world.state)==before,"replaying the festival memory %d times changes nothing"%REPLAYS)
	tok=TOKEN_A

func late_member_uses_public_facilities() -> void:
	expect(World.crafting_level(person())==1 and World.farming_level(person())==1 and not person().get("borrowed_mine_pick",false),
		"The late resident begins at base skill levels without a loan")
	var kitchen:=World.PUBLIC_KITCHEN
	var stove:=kitchen.parse_cell(str(world.state.public_kitchen.stove))
	expect(kitchen.stage(world.state)=="open" and world.state.objects[World.key(stove)].owner==TOKEN_A,
		"The original resident built the public stove")
	expect(preload("res://scripts/island_map.gd").public_kitchen_marker(world.state)==stove,
		"The map points newcomers to the actual public stove")
	var recipe:Dictionary=World.RECIPES.soup
	for i in int(recipe.ingredients.radish):
		var plot:=open_cell()
		if not expect(plot!=Vector2i(-1,-1),"Find a free garden tile for the new resident"):return
		wait_for_kitchen_crop("radish",plot)
		act("hoe",plot)
		act("seed",plot,"radish")
		act("water",plot)
		grow([plot])
		act("harvest",plot)
	act("cook",stove,"soup")
	wait(float(recipe.time))
	act("claim_cook",stove)
	expect(int(bag().get("soup",0))==int(recipe.yield) and int(person().get("builds",0))==0,
		"The newcomer cooked with their own crops and the existing stove")
	act("borrow_mine_pick",World.COPPER_CELL)
	act("mine_copper",World.COPPER_CELL)
	expect(int(bag().get("copper_ore",0))==2 and not bag().has("reinforced_pick"),
		"The same newcomer can mine through the public loan without obtaining a physical tool")
	var coins:=int(person().coins)
	walk_to(RECEIVER)
	if failed:return
	actions+=1
	var sale:=world.act(tok,"late-loan-sale","sell",RECEIVER,"reinforced_pick")
	expect(not sale.ok and int(person().coins)==coins,"Selling a public loan cannot credit coins")

func second_restart() -> void:
	expect(world.save(),"explicit save before the second restart")
	var reopened:=reopen("second restart")
	if reopened==null:return
	reopened.add_player(TOKEN_A,"Bloom A")
	reopened.add_player(LATE,"Late Member")
	world=reopened
	expect(world.festival_story_view().opened,"second restart: still opened")
	expect(world.state.community.watermelon.claimed.has(LATE),"second restart: late member's claim persisted")
	tok=LATE
	expect(person().get("borrowed_mine_pick",false) and int(bag().get("soup",0))==int(World.RECIPES.soup.yield)
		and int(bag().get("copper_ore",0))==2,"second restart: the newcomer retains the loan and their earned output")
	frefuse("claim_watermelon",World.COMMUNITY.table_cell(world.state),"",MSG_CLAIMED)
	frefuse("festival_story_open",BOARD,"",MSG_OPENED)
	tok=TOKEN_A

func festival_scene_count() -> int:
	var almanac:=load("res://scripts/life_ui_almanac.gd") as GDScript
	if almanac==null:return 0
	var scenes:Variant=almanac.get_script_constant_map().get("FESTIVAL_SCENES",[])
	return (scenes as Array).size() if scenes is Array else 0

# ---------------------------------------------------------------- helpers

func frefuse(action:String,target:Vector2i,extra:String,message:String) -> void:
	refuse(action,target,extra,message)
	refusals.append("%s:%s"%[action,message])

func mask_names(mask:int) -> Array:
	var out:=[]
	for i in PROJECT_NAMES.size():
		if mask&(1<<i):out.append(PROJECT_NAMES[i])
	return out

func keep_evidence() -> void:
	if output_dir.is_empty() or failed:return
	expect(world.save(),"final festival save written")
	var save_out:=output_dir.path_join(REPORT_FILES[0])
	var report_out:=output_dir.path_join(REPORT_FILES[1])
	expect(DirAccess.copy_absolute(fest_path,save_out)==OK,"kept the festival completion save")
	var report:={"journey":"test_festival_earned_journey.gd","source":"test_salt_pan_journey.gd (fresh temp world, earned)",
		"label":SALT_LABEL,"earned_projects":mask_names(real_mask),
		"earned":["dock_repair x2","watermelon seed->harvest->watermelon_platter->serve_watermelon","2 lamps","festival_story_open"],
		"lamps":lamp_cells.map(func(c):return [c.x,c.y]),"spent":spent,"refusals":refusals,"restarts":restarts,
		"moved_residents":moved_residents,"save_sha256":FileAccess.get_sha256(save_out),
		"world_seconds":now(),"festival_world_seconds":now()-time_start}
	var file:=FileAccess.open(report_out,FileAccess.WRITE)
	if not expect(file!=null,"open festival report"):return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("FESTIVAL_EARNED_EVIDENCE save=%s report=%s"%[save_out,report_out])
