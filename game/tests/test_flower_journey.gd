extends SceneTree
## Chapter 3 Tianwei flower nursery: earned headless journey (flower_exec_journey).
##
## EARNED ACTIONS, ACCELERATED IN-PROCESS CLOCK. A FRESH World is driven only by
## World.act (after walking with World.move_player along passable tiles) and
## World.step(dt,true); waits are compressed by calling step() directly instead of
## waiting real time. No items, coins, flags or records are injected: chapter one,
## the chapter-two tea comparison, the letter, transit, planting, saving, the order,
## dyeing, the garden and the report are all reached through validated actions.
## The only flower items that may appear without an action that consumes coins or
## crops are the contract's story grants (flower_intro STARTER, flower_report
## MEMENTO); every flower item and every coin delta is checked against a ledger.
##
## Player A: chapter one -> tea comparison -> flower_letter -> transit home ->
## yingge -> tianwei -> intro -> 6 beds -> harvest -> flower_save x3 (save + reload
## mid-journey while a saving job runs) -> flower_ship rejected (unsaved, reserve)
## then shipped -> buy seeds -> replant/harvest -> dye x2 -> give twice (garden
## completes on the second) -> report -> transit home -> buy a flower seed from
## 小栗 -> plant/water/harvest at home.
## Player B (late joiner, created after the garden completed): tea comparison ->
## letter -> transit -> intro -> plant/harvest/save/ship -> phase skips garden ->
## give refused, report grants the memento once, no second settlement.
## Prints FLOWER_JOURNEY_TESTS checks=N failures=M and quits 1 on failure.

const World=preload("res://scripts/world.gd")
const F=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const WEATHER=preload("res://scripts/weather.gd")
const Session=preload("res://scripts/session.gd")

class ProjectSession extends Session:
	var last_message := ""
	var last_success := false
	func _send_notice(_id:int,message:String,success:bool) -> void:
		last_message=message
		last_success=success
	func _send_snapshot(_id:int) -> void:
		pass

const TOKEN_A:="flower-journey-a"
const TOKEN_B:="flower-journey-b"
const RECEIVER:=Vector2i(43,29)
const FERRY:=Vector2i(47,30)
const LABEL:="earned actions, accelerated in-process clock"
const EXPECTED_A:=["locked","letter","travel","intro","plant","harvest","save","ship","garden","report","complete"]
const EXPECTED_B:=["locked","letter","travel","intro","plant","harvest","save","ship","report","complete"]

var world:=World.new()
var tok:=TOKEN_A
var checks:=0
var failures:=0
var failed:=false
var actions:=0
var walking:=0
var waters:=0
var reloads:=0
var save_path:=""
var phases:={TOKEN_A:[],TOKEN_B:[]}
## Expected flower-item counts and coins per player during the flower chapter.
var ledger:={}
var coins_ledger:={}
var ledger_on:={TOKEN_A:false,TOKEN_B:false}
var plots_a:Array[Vector2i]=[]
var plots_b:Array[Vector2i]=[]

func _initialize() -> void:
	var temp:=OS.get_environment("TEMP")
	if temp.is_empty():
		expect(false,"TEMP must point at an isolated directory")
		finish()
		return
	save_path=temp.path_join("flower-journey-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak"):
		expect(false,"journey save path already exists")
		finish()
		return
	world.save_path=save_path
	for y in range(3):
		pass
	for x in range(6):
		plots_a.append(F.NURSERY_BEDS.position+Vector2i(x,0))
		plots_b.append(F.NURSERY_BEDS.position+Vector2i(x,2))
	run()
	for file in [save_path,save_path+".bak",save_path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	finish()

func finish() -> void:
	print("FLOWER_JOURNEY label=\"%s\" actions=%d walk_tiles=%d waters=%d reloads=%d world_seconds=%.1f phases_a=%s phases_b=%s"%[LABEL,actions,walking,waters,reloads,float(world.state.get("time",0.0)),JSON.stringify(phases[TOKEN_A]),JSON.stringify(phases[TOKEN_B])])
	print("FLOWER_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	world.add_player(TOKEN_A,"Bloom A")
	expect(F.phase(world.state,TOKEN_A)=="locked" and not world.state.flower_nursery.players.has(TOKEN_A),"fresh world: flower chapter locked, no record")
	expect(no_flower_items(),"fresh backpack holds no flower ids")
	note_phases()
	chapter_one()
	if failed:return
	tea_route()
	if failed:return
	flower_a()
	if failed:return
	late_joiner()
	if failed:return
	var events:=0
	for line in world.state.events:
		if str(line)==F.GARDEN_EVENT:events+=1
	expect(events==1,"exactly one garden completion event line in state.events (got %d)"%events)
	expect_same(phases[TOKEN_A],EXPECTED_A,"player A phase sequence")
	expect_same(phases[TOKEN_B],EXPECTED_B,"late joiner phase sequence (garden skipped)")
	tok=TOKEN_A
	visit_warm_springs()
	if failed:return
	complete_outlying_commissions()
	if failed:return
	expect(reload("final"),"final world reloads from disk through SaveSchema")

func gather_for_dock(item:String,resource:String,action:String,needed:int,hits:int) -> void:
	while not failed and int(bag().get(item,0))<needed:
		var tile:=find_resource(resource)
		if not expect(tile!=Vector2i(-1,-1),"Reachable source of "+item):return
		for hit in range(hits):act(action,tile)

func complete_outlying_commissions() -> void:
	# Both local catches and the tea leaves already came from normal gameplay.
	ledger_on[tok]=false
	var bench:=Vector2i(40,35)
	var sawmill:=Vector2i(40,36)
	var board:=Vector2i(40,29)
	var plank_recipe:Dictionary=World.INDUSTRY.PROCESS.plank
	var collector_cost:=World.LIVESTOCK.COLLECTOR_COST
	var joint_count:int=World.DOCK_REPAIRS[1].copper_joint+collector_cost.copper_joint
	var plank_batches:=ceili(float(World.DOCK_REPAIRS[0].plank+World.DOCK_REPAIRS[1].plank+collector_cost.plank)/float(plank_recipe.yield))
	var wood_needed:int=World.BUILD.bench.wood+World.CRAFT.sawmill_kit.ingredients.wood+World.CRAFT.reinforced_pick.ingredients.wood+joint_count*World.CRAFT.copper_joint.ingredients.wood+plank_batches*plank_recipe.ingredients.wood
	var stone_needed:int=World.BUILD.bench.stone+World.CRAFT.sawmill_kit.ingredients.stone+World.CRAFT.reinforced_pick.ingredients.stone+World.DOCK_REPAIRS[0].stone+World.OUTLYING_COMMISSIONS.DEFS.springs_footbath.needs.stone
	gather_for_dock("wood","tree","axe",wood_needed,3)
	gather_for_dock("stone","rock","pick",stone_needed,2)
	gather_for_dock("fiber","grass","axe",World.DOCK_REPAIRS[1].fiber+World.CRAFT.reinforced_pick.ingredients.fiber,1)
	act("build",bench,"bench")
	act("craft",bench,"sawmill_kit")
	act("build",sawmill,"sawmill")
	for batch in range(plank_batches):
		act("start_processing",sawmill,"plank")
		if failed:return
		expect(world.step(World.INDUSTRY.PROCESS.plank.time,true),"Saw fresh lumber into dock planks")
		act("claim_processing",sawmill)
	act("craft",bench,"reinforced_pick")
	travel(World.TRANSIT.points("home").ferry.cell,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").bus.cell,"jiufen")
	travel(World.TRANSIT.points("jiufen").shuttle.cell,"jinguashi")
	act("pick",World.JINGUASHI.NODES[0])
	act("pick",World.JINGUASHI.NODES[1])
	travel(World.REGIONS.exit_cell("jinguashi"),"home")
	for joint in range(joint_count):act("craft",bench,"copper_joint")
	check_managed_dock(board)
	act("dock_repair",board,"0")
	act("dock_repair",board,"1")
	for id:String in World.OUTLYING_COMMISSIONS.ids():
		if failed:return
		var definition:Dictionary=World.OUTLYING_COMMISSIONS.DEFS[id]
		var destination:String=definition.region
		travel(FERRY,destination)
		expect(person().get("outlying_boat_arrival",false),"Proven outbound boat journey to "+destination)
		var station:Vector2i=World.TRANSIT.STATIONS[destination].cell
		var before:=int(person().coins)
		act("outlying_deliver",station,id)
		expect(int(person().coins)==before+definition.reward_coins,"Earned local reward once for "+id)
		travel(station,"home")
	if not reload("outlying-commissions"):return
	for id:String in World.OUTLYING_COMMISSIONS.ids():
		expect(World.OUTLYING_COMMISSIONS.done(world.state,tok,id),"Earned commission preserved after restart: "+id)
		expect(not World.OUTLYING_COMMISSIONS.done(world.state,TOKEN_B,id),"A later player's commissions stay independent: "+id)
	verify_ranch_collector()

func check_managed_dock(board:Vector2i) -> void:
	if failed:return
	var fixture:=World.new()
	fixture.state=world.state.duplicate(true)
	fixture.save_path=world.save_path+".managed-dock"
	var server:=ProjectSession.new()
	server.world=fixture
	server.accepting=true
	var roster:=Session.Membership.new()
	server.membership=roster
	var roster_path:=fixture.save_path+".members"
	expect(roster.initialize(roster_path,"Test Island","owner","Owner"),"Initialize authenticated project roster")
	expect(roster.link_legacy("owner","member","Member",tok),"Map earned worker to ordinary member")
	expect(roster.link_legacy("owner","manager","Manager","dock-test-admin"),"Map manager to a separate character")
	expect(roster.set_admin("owner",roster.management_id("dock-test-admin"),true),"Grant construction launch permission")
	fixture.add_player("dock-test-admin","Manager")
	fixture.state.players["dock-test-admin"].x=40.5
	fixture.state.players["dock-test-admin"].y=30.5
	server.peers={2:tok,3:"dock-test-admin"}
	server.identities={2:{"account_id":"member","expires":Time.get_unix_time_from_system()+60},
		3:{"account_id":"manager","expires":Time.get_unix_time_from_system()+60}}
	server.sequences={2:0,3:0}
	server.rates={2:[],3:[]}
	var before:Dictionary=fixture.state.players[tok].inventory.duplicate()
	server._action(2,1,"dock_project_start",board,"")
	expect(not server.last_success and not fixture.state.has("dock_project_started"),"Member cannot launch authenticated dock project")
	server._action(2,2,"dock_repair",board,"0")
	expect(not server.last_success and fixture.state.players[tok].inventory==before,"Member materials stay intact while waiting for approval")
	server._action(3,1,"dock_project_start",board,"")
	expect(server.last_success and fixture.state.get("dock_project_started",false),"Manager starts dock project at the board")
	expect(fixture.load_world(fixture.save_path) and fixture.state.get("dock_project_started",false),"Dock launch survives reload")
	fixture.state.players[tok].x=39.5
	fixture.state.players[tok].y=30.5
	server._action(2,3,"dock_repair",board,"0")
	expect(server.last_success and int(fixture.state.get("dock_stage",0))==1,"Ordinary member supplies first stage after launch: "+server.last_message)
	server._action(2,4,"festival_story_open",board,"")
	expect(not server.last_success and server.last_message.contains("管理員"),"Member cannot announce festival opening")
	server._action(3,2,"festival_story_open",board,"")
	expect(not server.last_success and server.last_message.contains("小船"),"Manager must still satisfy festival prerequisites")
	server.free()
	for path in [fixture.save_path,fixture.save_path+".bak",roster_path]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func verify_ranch_collector() -> void:
	var cow:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	act("livestock_install",cow,"cow")
	if failed:return
	expect(int(bag().get("plank",0))==0 and int(bag().get("copper_joint",0))==0,"The dedicated collector uses the earned planks and joints")
	refuse("livestock_install",cow,"cow","收集器已裝好。")
	var stove:=Vector2i(40,34)
	act("buy",RECEIVER,"wheat")
	var plot:=empty_home_plot()
	if not expect(plot!=Vector2i(-1,-1),"A home plot remains for feed wheat"):return
	while not World.crop_grows_in_season("wheat","home",plot,float(world.state.time)) and not failed:
		expect(world.step(World.WEATHER.DAY_SECONDS,true),"Wait for wheat season")
	act("seed",plot,"wheat")
	grow([plot])
	act("harvest",plot)
	gather_for_dock("fiber","grass","axe",2,1)
	act("cook",stove,"feed")
	expect(world.step(float(World.RECIPES.feed.time),true),"Finish the homemade feed")
	act("claim_cook",stove)
	act("livestock_feed",cow,"cow")
	expect(world.step(World.LIVESTOCK.DAY,true),"Wait one livestock production cycle")
	expect(int(world.state.livestock.cow.collector)==1 and int(world.state.livestock.cow.ready)==0,"Milk is stored exactly once in the dedicated collector")
	if not reload("livestock-collector"):return
	act("livestock_empty",cow,"cow")
	refuse("livestock_empty",cow,"cow","收集器沒有可取的產物，或背包已滿。")
	expect(int(bag().get("milk",0))==1,"Milk from the saved collector reaches the player once")

## Chapter one, re-derived from test_chapter_journey's earned sequence.
func chapter_one() -> void:
	tok=TOKEN_A
	var plots:=[Vector2i(41,34),Vector2i(42,34),Vector2i(41,35),Vector2i(42,35),Vector2i(41,36)]
	for index in plots.size():
		var kind:="radish" if index<3 else "wheat"
		act("hoe",plots[index])
		act("seed",plots[index],kind)
		act("water",plots[index])
	expect(world.step(maxf(World.CROPS.wheat.time,World.CROPS.radish.time),true),"advance chapter-one crops")
	for plot in plots:act("harvest",plot)
	act("ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[["radish",1]],24]))
	act("buy",RECEIVER,"radish")
	for item in ["wood","stone"]:
		var need:=54 if item=="wood" else 33
		while int(bag().get(item,0))<need and not failed:
			var target:=find_resource("tree" if item=="wood" else "rock")
			if target==Vector2i(-1,-1):
				expect(false,"no reachable source for "+item)
				return
			for hit in range(3 if item=="wood" else 2):act("axe" if item=="wood" else "pick",target)
	act("donate",Vector2i(40,29))
	act("chapter_starter",World.CHAPTER_ONE.STARTER_CELL)
	act("build",Vector2i(43,34),"sprinkler")
	act("build",Vector2i(44,34),"water_pipe")
	act("build",Vector2i(44,35),"water_pipe")
	act("build",Vector2i(44,36),"water_tank")
	act("seed",Vector2i(42,34),"radish")
	act("refill_tank",Vector2i(44,36))
	act("toggle_sprinkler",Vector2i(43,34))
	expect(world.step(8.0,true),"advance irrigation")
	act("build",Vector2i(40,34),"stove")
	for recipe in ["soup","bread"]:
		act("cook",Vector2i(40,34),recipe)
		expect(world.step(World.RECIPES[recipe].time,true),"advance "+recipe)
		act("claim_cook",Vector2i(40,34))
	act("picnic",Vector2i(40,29))
	expect(World.CHAPTER_ONE.phase(world.state)=="complete","chapter one complete through earned actions")
	expect(F.phase(world.state,TOKEN_A)=="locked","flowers stay locked after chapter one")

## Chapter two up to comparison_complete, re-derived from the tea journeys.
func tea_route() -> void:
	act("tea_intro",Tea.RECEIVER)
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").rail.cell,Tea.MAOKONG)
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,Tea.YINGGE)
	act("tea_potter",Tea.POTTER)
	act("tea_fire",Tea.KILN)
	expect(world.step(Tea.KILN_SECONDS,true),"kiln wait")
	act("tea_fire_take",Tea.KILN)
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,Tea.MAOKONG)
	tea_batch("light","jar")
	act("tea_return",Tea.RECEIVER)
	travel(FERRY,Tea.MAOKONG)
	expect(world.step(Tea.RETURN_SECONDS,true),"jar return wait")
	act("tea_reclaim",Tea.PACKER)
	if int(bag().get("fiber",0))<1:
		travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,"home")
		var tree:=find_resource("tree")
		expect(tree!=Vector2i(-1,-1),"reachable tree for fiber")
		for hit in range(3):act("axe",tree)
		travel(FERRY,Tea.MAOKONG)
	tea_batch("deep","fiber")
	travel(FERRY,Tea.MAOKONG)
	expect(F.phase(world.state,tok)=="locked","flowers locked until the comparison")
	act("tea_discuss",Tea.TEA_NPC)
	expect(Tea.own_record(world.state,tok).comparison_complete,"tea comparison completed through two deliveries and a reclaim")
	expect(F.phase(world.state,tok)=="letter","flower letter becomes the next phase")
	visit_bamboo_grove()
	if failed:return
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,"home")

func tea_batch(style:String,wrapping:String) -> void:
	act("tea_pick",Tea.TEA_NODES[0])
	act("tea_roast",Tea.ROASTER,style)
	expect(world.step(Tea.ROAST_SECONDS[style],true),"roast wait")
	act("tea_take",Tea.ROASTER)
	act("tea_pack",Tea.PACKER,style+":"+wrapping)
	act("tea_ship",Tea.PACKER)
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,"home")
	expect(world.step(Tea.SHIPPING_SECONDS,true),"tea shipping wait")
	var before:=int(person().coins)
	act("tea_sell",Tea.RECEIVER)
	expect(int(person().coins)==before+Tea.price_for(style,wrapping),"tea settlement %s/%s"%[style,wrapping])

func flower_a() -> void:
	tok=TOKEN_A
	start_ledger()
	# Home seed stall stays locked for flowers before the chapter.
	refuse("buy",RECEIVER,"bluebell",World.FLOWER_HOME_SEED_MSG)
	expect(not travel_has("home",FERRY,F.REGION),"tianwei hidden from transit before the letter")
	act("flower_letter",F.RECEIVER_HOME)
	expect_bag("letter")
	refuse("flower_letter",F.RECEIVER_HOME,"","介紹信已收下，可從手帳重看。")
	travel(FERRY,Tea.YINGGE)
	expect(F.phase(world.state,tok)=="travel","phase travel before reaching tianwei")
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,F.REGION)
	expect(world.player_region(tok)==F.REGION and person().travel_book.visited.get(F.REGION)==true,"arrived in tianwei by transit")
	refuse("hoe",plots_a[0],"","先向花農問好，再開墾育苗床。")
	act("flower_intro",F.FARMER)
	grant(F.STARTER)
	expect_bag("intro (story grant STARTER)")
	refuse("flower_intro",F.FARMER,"","阿蕾已經給過起始種子，可從手帳重看。")
	refuse("build",plots_a[0]+Vector2i(0,-3),"sprinkler",World.FLOWER_REJECT_MSG)
	# Batch 1: every starter seed into six owned beds.
	var batch1:=["bluebell","bluebell","orange_blossom","orange_blossom","chime_herb","chime_herb"]
	for i in batch1.size():
		act("hoe",plots_a[i])
		plant(plots_a[i],batch1[i])
	refuse("hoe",F.NURSERY_BEDS.position+Vector2i(6,0),"","田尾育苗床每人最多 %d 格，先收成或恢復自己的空床。"%F.PLOT_CAP)
	dry_check(plots_a[0])
	grow(plots_a)
	for i in batch1.size():harvest(plots_a[i])
	expect(F.phase(world.state,tok)=="save","phase save after three kinds harvested")
	expect_bag("batch 1 harvested")
	# Seed saving; the order is refused until all three were saved.
	save_seed("bluebell")
	refuse("flower_ship",F.MARKET,"",F.UNSAVED_MESSAGE)
	act("flower_save",F.SEED_TABLE,"orange_blossom")
	led("orange_blossom",-F.save_flower_cost("orange_blossom"))
	refuse("flower_save_take",F.SEED_TABLE,"","留種台上沒有完成的工作。")
	# Mid-journey save + reload while the saving job is running.
	expect(reload("saving-in-progress"),"reload while saving is pending")
	if failed:return
	expect(F.own_record(world.state,tok).saving.get("kind")=="orange_blossom","saving job survives reload")
	expect(world.step(F.SAVE_SECONDS,true),"seed-saving wait")
	act("flower_save_take",F.SEED_TABLE)
	led("orange_blossom_seed",1)
	save_seed("chime_herb")
	expect_bag("three seeds saved")
	expect(F.phase(world.state,tok)=="ship","phase ship")
	# Break the reserve by replanting the saved bluebell seed, then fix it with coins.
	plant(plots_a[0],"bluebell")
	refuse("flower_ship",F.MARKET,"",F.RESERVE_MESSAGE)
	buy("bluebell_seed")
	var coins_before:=int(person().coins)
	act("flower_ship",F.MARKET)
	for kind in F.ORDER:led(kind,-int(F.ORDER[kind]))
	coins_ledger[tok]+=F.ORDER_PAY
	expect(int(person().coins)==coins_before+F.ORDER_PAY,"order pays exactly %d"%F.ORDER_PAY)
	expect_bag("shipped")
	refuse("flower_ship",F.MARKET,"","合作訂單已出貨。")
	expect(F.phase(world.state,tok)=="garden","phase garden")
	# Batch 2 bought with earned coins.
	buy("bluebell_seed")
	buy("orange_blossom_seed")
	plant(plots_a[1],"bluebell")
	plant(plots_a[2],"bluebell")
	plant(plots_a[3],"orange_blossom")
	plant(plots_a[4],"orange_blossom")
	plant(plots_a[5],"chime_herb")
	grow(plots_a)
	for i in 6:harvest(plots_a[i])
	expect_bag("batch 2 harvested")
	for n in 2:
		act("flower_dye",F.DYE_TABLE)
		led("bluebell",-3)
		expect(world.step(float(F.DYE.time),true),"dye wait")
		act("flower_dye_take",F.DYE_TABLE)
		led("blue_dye",int(F.DYE.yield))
	expect_bag("dyed twice")
	give(false)
	refuse("flower_give",F.GARDEN_CELL,"","沒有可捐的染料、橙花或香草（種子不會被拿走）。")
	expect(F.phase(world.state,tok)=="garden","garden still open after the first donation")
	buy("chime_herb_seed")
	plant(plots_a[5],"chime_herb")
	grow([plots_a[5]])
	harvest(plots_a[5])
	give(true)
	var garden:Dictionary=world.state.flower_nursery.garden
	expect(garden.complete and int(garden.contributors.get(tok,0))==10 and garden.contributors.size()==1,"garden complete; A contributed all 10")
	refuse("flower_give",F.GARDEN_CELL,"","公共花園已完成。")
	expect(F.phase(world.state,tok)=="report","phase report")
	act("flower_report",F.XINGHE)
	grant(F.MEMENTO)
	expect_bag("report (story grant MEMENTO)")
	refuse("flower_report",F.XINGHE,"","第三章田尾段落已完成，可從手帳重看。")
	expect(F.phase(world.state,tok)=="complete","phase complete")
	expect(reload("chapter-complete"),"reload after the report")
	if failed:return
	visit_star_garden()
	if failed:return
	# Home: 小栗 now sells flower seeds; home planting does not touch chapter progress.
	travel(F.TRANSFER,"home")
	refuse("sell",RECEIVER,"bluebell_seed","這件商品尚未上架")
	var record_before:=F.own_record(world.state,tok)
	var coins_home:=int(person().coins)
	act("buy",RECEIVER,"bluebell")
	led("bluebell_seed",1)
	coins_ledger[tok]-=int(World.CROPS.bluebell.seed_price)
	expect(int(person().coins)==coins_home-int(World.CROPS.bluebell.seed_price),"home flower seed costs %d"%int(World.CROPS.bluebell.seed_price))
	var home_plot:=empty_home_plot()
	expect(home_plot!=Vector2i(-1,-1),"own empty home farmland from chapter one")
	if failed:return
	plant(home_plot,"bluebell")
	grow([home_plot])
	harvest(home_plot)
	expect_bag("home flower harvested")
	expect_same(F.own_record(world.state,tok),record_before,"home planting leaves the chapter-3 record unchanged")

func late_joiner() -> void:
	var garden_before:Dictionary=world.state.flower_nursery.garden.duplicate(true)
	var a_before:Dictionary=person_of(TOKEN_A).duplicate(true)
	tok=TOKEN_B
	world.add_player(TOKEN_B,"Bloom B")
	expect(no_flower_items(),"late joiner starts without flower ids")
	note_phases()
	tea_route()
	if failed:return
	start_ledger()
	act("flower_letter",F.RECEIVER_HOME)
	travel(FERRY,Tea.YINGGE)
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,F.REGION)
	act("flower_intro",F.FARMER)
	grant(F.STARTER)
	# A already harvested this bed. Attempt to plant it to exercise ownership
	# rather than asking to harvest an empty plot (which reports no crop).
	refuse("seed",plots_a[0],"bluebell","這是其他島民的育苗床")
	var kinds:=["bluebell","bluebell","orange_blossom","orange_blossom","chime_herb","chime_herb"]
	for i in kinds.size():
		act("hoe",plots_b[i])
		plant(plots_b[i],kinds[i])
	grow(plots_b)
	for i in kinds.size():harvest(plots_b[i])
	for kind in F.FLOWERS:save_seed(kind)
	var coins_before:=int(person().coins)
	act("flower_ship",F.MARKET)
	for kind in F.ORDER:led(kind,-int(F.ORDER[kind]))
	coins_ledger[tok]+=F.ORDER_PAY
	expect(int(person().coins)==coins_before+F.ORDER_PAY,"late joiner order pays %d"%F.ORDER_PAY)
	expect(F.phase(world.state,tok)=="report","late joiner skips the garden phase straight to report")
	refuse("flower_give",F.GARDEN_CELL,"","公共花園已完成。")
	act("flower_report",F.XINGHE)
	grant(F.MEMENTO)
	expect_bag("late joiner report (memento)")
	refuse("flower_report",F.XINGHE,"","第三章田尾段落已完成，可從手帳重看。")
	expect_same(world.state.flower_nursery.garden,garden_before,"no re-settlement: garden and contributors unchanged by the late joiner")
	var a_now:Dictionary=person_of(TOKEN_A)
	expect_same([a_now.coins,a_now.inventory],[a_before.coins,a_before.inventory],"player A untouched by the late joiner")

# ---------------------------------------------------------------- flower helpers

func start_ledger() -> void:
	var counts:={}
	for id in F.NAMES:counts[id]=int(bag().get(id,0))
	ledger[tok]=counts
	coins_ledger[tok]=int(person().coins)
	ledger_on[tok]=true
	expect(counts.values().all(func(v):return v==0),"no flower items before the flower chapter (%s)"%tok)

func led(item:String,delta:int) -> void:
	ledger[tok][item]=int(ledger[tok][item])+delta

func grant(items:Dictionary) -> void:
	for item in items:led(item,int(items[item]))

func expect_bag(label:String) -> void:
	var got:={}
	for id in F.NAMES:got[id]=int(bag().get(id,0))
	expect(got==ledger[tok],"%s: flower items %s == ledger %s"%[label,JSON.stringify(got),JSON.stringify(ledger[tok])])
	expect(int(person().coins)==int(coins_ledger[tok]),"%s: coins %d == ledger %d"%[label,int(person().coins),int(coins_ledger[tok])])

func buy(item:String) -> void:
	var before:=int(person().coins)
	act("flower_buy",F.MARKET,item)
	led(item,1)
	coins_ledger[tok]-=int(F.MARKET_PRICES[item])
	expect(int(person().coins)==before-int(F.MARKET_PRICES[item]),"bought %s for %d earned coins"%[item,int(F.MARKET_PRICES[item])])

func plant(c:Vector2i,kind:String) -> void:
	act("seed",c,kind)
	led(F.SEEDS[kind],-1)

func harvest(c:Vector2i) -> void:
	var crop:Dictionary=region_crops().get(World.key(c),{})
	var kind:=str(crop.get("kind",""))
	act("harvest",c)
	if kind in F.FLOWERS:led(kind,int(F.CROPS[kind].yield))

func save_seed(kind:String) -> void:
	act("flower_save",F.SEED_TABLE,kind)
	led(kind,-F.save_flower_cost(kind))
	refuse("flower_save_take",F.SEED_TABLE,"","留種台上沒有完成的工作。")
	expect(world.step(F.SAVE_SECONDS,true),"seed-saving wait")
	act("flower_save_take",F.SEED_TABLE)
	led(F.SEEDS[kind],1)

func give(completes:bool) -> void:
	var garden:Dictionary=world.state.flower_nursery.garden
	var take:={}
	for item in F.GARDEN_NEEDS:
		take[item]=mini(int(F.GARDEN_NEEDS[item])-int(garden.given[item]),int(bag().get(item,0)))
	var seeds_before:=[int(bag().get("bluebell_seed",0)),int(bag().get("orange_blossom_seed",0)),int(bag().get("chime_herb_seed",0))]
	var events_before:int=world.state.events.size()
	act("flower_give",F.GARDEN_CELL)
	for item in take:led(item,-int(take[item]))
	expect_bag("donation")
	expect(seeds_before==[int(bag().get("bluebell_seed",0)),int(bag().get("orange_blossom_seed",0)),int(bag().get("chime_herb_seed",0))],"donation never takes seeds")
	garden=world.state.flower_nursery.garden
	expect(garden.complete==completes,"garden complete == %s after donation"%str(completes))
	expect(world.state.events.size()==events_before+(1 if completes else 0),"completion event appended only on completion")
	if completes:expect(float(garden.completed_at)==float(world.state.time),"completed_at is the donation time")

## Before the first watering a planted bed only grows if it rains today.
func dry_check(c:Vector2i) -> void:
	var crop:Dictionary=region_crops().get(World.key(c),{})
	var raining:=WEATHER.rains(WEATHER.day_index(float(world.state.time)),F.REGION)
	expect(crop.get("wet")==raining,"unwatered bed wet only if it rains (rain=%s)"%str(raining))
	expect(world.step(5.0,true),"short wait before watering")
	crop=region_crops().get(World.key(c),{})
	expect(is_equal_approx(float(crop.growth),5.0 if raining else 0.0),"dry bed does not grow; rain does (growth %.2f)"%float(crop.growth))

## Advance the clock in 10 s steps, watering own beds whenever the weather rules
## left them dry (midnight drying); stops when every listed bed is mature.
func grow(cells:Array) -> void:
	for guard in 600:
		if failed:return
		var waiting:=false
		for c in cells:
			var crop:Dictionary=region_crops().get(World.key(c),{})
			var kind:=str(crop.get("kind",""))
			if kind=="" or float(crop.growth)>=float(World.CROPS[kind].time):continue
			waiting=true
			if crop.get("wet")!=true:
				act("water",c)
				waters+=1
		if not waiting:return
		expect(world.step(10.0,true),"growth step")
	expect(false,"crops did not mature within 6000 world seconds")

func region_crops() -> Dictionary:
	var region:=world.player_region(tok)
	return world.state.crops if region=="home" else world.state.regions[region].crops

func empty_home_plot() -> Vector2i:
	for k in world.state.crops:
		var crop:Dictionary=world.state.crops[k]
		if str(crop.get("kind",""))=="" and crop.get("owner","")==tok:
			var c:=World.cell(k)
			if not route(c).is_empty():return c
	return Vector2i(-1,-1)

func no_flower_items() -> bool:
	for id in F.NAMES:
		if int(bag().get(id,0))!=0:return false
	return true

func travel_has(region:String,cell:Vector2i,destination:String) -> bool:
	for option in World.TRANSIT.route_options(world.state,tok,World.TRANSIT.point_at(region,cell)):
		if option.region==destination:return true
	return false

## Reload the primary save into a new World, re-register both known players and
## require that nothing about them changed (no grant, no teleport).
func reload(label:String) -> bool:
	if failed:return false
	var expected:Dictionary=world.state.players.duplicate(true)
	var flowers:Dictionary=world.state.flower_nursery.duplicate(true)
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": primary save loads through SaveSchema"):return false
	if not expect(int(reopened.state.version)==int(World.SAVE_SCHEMA.VERSION),label+": saved version is SaveSchema.VERSION"):return false
	for token in world.active_tokens:
		reopened.add_player(token,str(expected[token].name))
		for field in ["region","x","y","coins","inventory","receipts","travel_book"]:
			expect_same(reopened.state.players[token].get(field),expected[token].get(field),label+": "+field+" preserved")
	expect_same(reopened.state.flower_nursery,flowers,label+": flower records and garden preserved")
	if failed:return false
	world=reopened
	reloads+=1
	return true

# ---------------------------------------------------------------- movement / acts

func note_phases() -> void:
	for token in [TOKEN_A,TOKEN_B]:
		if not world.state.players.has(token):continue
		var current:=F.phase(world.state,token)
		var seen:Array=phases[token]
		if seen.is_empty() or seen.back()!=current:seen.append(current)

func visit_warm_springs() -> void:
	var springs:=World.REGIONS.Springs.REGION
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,springs)
	if failed:return
	var day:=World.WEATHER.DAY_SECONDS
	var noon:=World.WEATHER.day_index(world.state.time)*day+720.0
	if noon<float(world.state.time):noon+=day
	expect(world.step(noon-float(world.state.time),true),"Wait for daylight at the warm creek")
	var warm_pool:Rect2i=World.REGIONS.Springs.POOLS.spring.water
	act("fish_start",warm_pool.position)
	if failed:return
	expect(world.step(3.1,true),"Wait for a bite in the warm creek")
	act("fish_catch",warm_pool.position)
	expect(int(bag().get("glass_shrimp",0))==1 and person().collection.fish.has("glass_shrimp"),"Daylight catch registers one glass shrimp")
	if failed:return
	var season_days:=World.WEATHER.DAYS_PER_SEASON
	var winter_noon:float=(3*season_days)*day+720.0
	var year:=4*season_days*day
	if winter_noon<float(world.state.time):
		winter_noon+=ceilf((float(world.state.time)-winter_noon)/year)*year
	expect(world.step(winter_noon-float(world.state.time),true),"Advance to winter in the same world")
	var cold_pool:Rect2i=World.REGIONS.Springs.POOLS.upland.water
	expect(int(person().get("jiaoxi_trout_misses",0))==0,"Winter trout starts without seeded pity")
	for attempt in range(World.Collections.RARE_FISH_LIMIT):
		act("fish_start",cold_pool.position)
		if failed:return
		expect(world.step(3.1,true),"Wait for a bite in the cold spring")
		act("fish_catch",cold_pool.position)
		if failed or int(bag().get("snow_trout",0))>0:break
	expect(int(bag().get("snow_trout",0))==1 and person().collection.fish.has("snow_trout"),"Earn the winter trout in at most twenty eligible catches")
	if not reload("warm-springs"):return
	expect(person().collection.fish.has("glass_shrimp") and person().collection.fish.has("snow_trout"),"Both fish discoveries survive reopening Jiaoxi")
	travel(World.REGIONS.exit_cell(springs),"toucheng")
	travel(World.TRANSIT.points("toucheng").street.cell,"home")

func visit_bamboo_grove() -> void:
	var grove:=World.REGIONS.Bamboo.REGION
	var map_site:=preload("res://scripts/island_map.gd").reserve_landmark(grove)
	expect(World.REGIONS.Bamboo.TEA_BEDS.has_point(map_site.cell) and map_site.item=="mist_tea","Brook map places tea at the real growing beds")
	var station:Vector2i=World.TRANSIT.points(Tea.MAOKONG).transfer.cell
	var brew:="mist_tea_brew"
	if tok==TOKEN_A:
		travel(station,"home")
		act("buy",RECEIVER,"mist_tea")
		travel(FERRY,Tea.MAOKONG)
	expect(travel_has(Tea.MAOKONG,station,grove),"The tea route opens the bamboo trail")
	travel(station,grove)
	if tok==TOKEN_A:
		var bed:Vector2i=World.REGIONS.Bamboo.TEA_BEDS.position
		act("hoe",bed)
		act("seed",bed,"mist_tea")
		for cycle in range(2):
			act("water",bed)
			expect(world.step(float(World.CROPS.mist_tea.time),true),"Let the tea bush grow")
			act("harvest",bed)
		expect(int(bag().get("mist_tea",0))==4 and person().collection.crops.has("mist_tea"),"Two harvests from the same tea bush")
	var water:Rect2i=World.REGIONS.Bamboo.POOLS.brook.water
	var morning:=World.WEATHER.day_index(world.state.time)*World.WEATHER.DAY_SECONDS+400.0
	if morning<float(world.state.time):morning+=World.WEATHER.DAY_SECONDS
	expect(world.step(morning-float(world.state.time),true),"Wait for the morning breeze")
	for attempt in range(World.Collections.RARE_FISH_LIMIT):
		act("fish_start",water.position)
		if failed:return
		expect(world.step(3.1,true),"Wait for a bite at the bamboo brook")
		act("fish_catch",water.position)
		if failed or int(bag().get("bamboo_ayu",0))>0:break
	expect(int(bag().get("bamboo_ayu",0))==1 and person().collection.fish.has("bamboo_ayu"),"Earn one bamboo ayu and register it within twenty catches")
	expect(reload("bamboo-brook"),"Reload the brook visit and earned catch")
	travel(World.REGIONS.exit_cell(grove),Tea.MAOKONG)
	if tok==TOKEN_A:
		travel(station,"home")
		var stove:=Vector2i(40,34)
		act("queue_cook",stove,brew)
		expect(world.step(float(World.RECIPES[brew].time),true),"Steep the harvested leaves")
		act("claim_cook",stove)
		expect(int(bag().get(brew,0))==2 and person().collection.meals.has(brew),"Brew two servings from the harvested leaves")
		travel(FERRY,Tea.MAOKONG)

func visit_star_garden() -> void:
	var map_site:=preload("res://scripts/island_map.gd").reserve_landmark(World.REGIONS.StarGarden.REGION)
	expect(map_site.cell==World.RESIDENT_BOND.GARDEN_CELL and World.land(map_site.cell,"star_garden"),"Garden map places Diandian on the actual bank")
	expect(travel_has("tianwei",F.TRANSFER,"star_garden"),"Earned public garden opens the trail")
	travel(F.TRANSFER,"star_garden")
	var pool:Vector2i=World.REGIONS.StarGarden.POOL.position
	var night:=World.WEATHER.day_index(world.state.time)*World.WEATHER.DAY_SECONDS+1220.0
	if night<float(world.state.time):night+=World.WEATHER.DAY_SECONDS
	expect(world.step(night-float(world.state.time),true),"Wait until the reflecting pool opens at night")
	for attempt in range(World.Collections.RARE_FISH_LIMIT):
		act("fish_start",pool)
		if failed:return
		expect(world.step(3.1,true),"Wait for a bite at the reflecting pool")
		act("fish_catch",pool)
		if failed:return
		var caught:="star_spot" if int(bag().get("star_spot",0))>0 else "carp"
		if caught=="star_spot" or failed:break
	expect(person().collection.fish.has("star_spot"),"Earn a Star Spot in at most twenty eligible catches")
	expect(int(bag().get("star_spot",0))==1,"The earned Star Spot enters the shared backpack once")
	expect(reload("reflecting-pool"),"Reload the earned fish and garden visit")
	travel(World.REGIONS.exit_cell("star_garden"),"tianwei")

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	walk_to(target)
	if failed:return {"ok":false,"message":"skipped"}
	actions+=1
	var result:=world.act(tok,"flower-journey-%d"%actions,action,target,extra)
	expect(result.ok,"%s %s %s at %s: %s"%[tok,action,extra,str(target),str(result.message)])
	note_phases()
	if ledger_on.get(tok,false) and action not in ["seed","harvest","flower_buy","flower_ship","flower_give","flower_save","flower_save_take","flower_dye","flower_dye_take","flower_intro","flower_report","buy","fish_catch"]:
		expect_bag("after "+action)
	return result

func refuse(action:String,target:Vector2i,extra:String,message:String) -> void:
	if failed:return
	walk_to(target)
	if failed:return
	actions+=1
	var before:=world.state.duplicate(true)
	var result:=world.act(tok,"flower-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s refused with exact message '%s' (got ok=%s '%s')"%[action,message,str(result.ok),str(result.message)])
	expect(world.state==before,"%s refusal changed nothing"%action)

func travel(gate:Vector2i,destination:String) -> void:
	act("transit",gate,destination)
	expect(world.player_region(tok)==destination,"arrived in "+destination)

func person() -> Dictionary:
	return world.state.players[tok]

func person_of(token:String) -> Dictionary:
	return world.state.players[token]

func bag() -> Dictionary:
	return person().inventory

func find_resource(kind:String) -> Vector2i:
	var origin:=Vector2i(int(person().x),int(person().y))
	for distance in range(1,30):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				var tile:=Vector2i(x,y)
				if maxi(absi(x-origin.x),absi(y-origin.y))!=distance:continue
				if world.resource(tile)==kind and not world.protected(tile) and not route(tile).is_empty():return tile
	return Vector2i(-1,-1)

func route(target:Vector2i,reach:float=2.0,allow_tile:=Callable()) -> Array:
	var local_world:=World.new()
	local_world.state=world.region_snapshot(world.player_region(tok))
	local_world._region=world.player_region(tok)
	var start:=Vector2i(int(person().x),int(person().y))
	var queue:=[start]
	var previous:={start:start}
	var index:=0
	while index<queue.size():
		var tile:Vector2i=queue[index]
		index+=1
		if tile!=target and Vector2(tile-target).length()<=reach and (not allow_tile.is_valid() or allow_tile.call(tile)):
			var path:=[tile]
			while tile!=start:
				tile=previous[tile]
				path.push_front(tile)
			return path
		for offset in World.INDUSTRY.NEIGHBORS:
			var next:Vector2i=tile+offset
			if not previous.has(next) and local_world.can_stand(Vector2(next)+Vector2(0.5,0.5)):
				previous[next]=tile
				queue.append(next)
	return []

func walk_to(target:Vector2i,reach:float=2.0) -> void:
	if failed:return
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=2.5:return
	var path:=route(target,reach)
	if path.is_empty():
		expect(false,"%s: no path to %s in %s"%[tok,str(target),world.player_region(tok)])
		return
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for step in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
		if not expect(Vector2(person().x,person().y).distance_to(Vector2(path[index])+Vector2(0.5,0.5))<=0.001,"movement followed a passable route"):return

# ---------------------------------------------------------------- assertions

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("FLOWER_JOURNEY FAIL: "+message)
	return condition

func expect_same(a:Variant,b:Variant,message:String) -> void:
	expect(JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b)),message+" (%s vs %s)"%[JSON.stringify(a).left(300),JSON.stringify(b).left(300)])
