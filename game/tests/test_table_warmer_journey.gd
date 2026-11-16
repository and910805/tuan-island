extends "res://tests/test_mine_deep_journey.gd"
## T067「暖岩片」保溫底座 natural journey: a FRESH temp world, ONE player, ONE process.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (DEVIATION, disclosed): this file EXTENDS the unmodified
## test_mine_deep_journey.gd (itself extending festival_earned -> salt_pan ->
## flower) instead of copying its ~2,900 lines of transitive step helpers. The
## parent run() walks chapter one (picnic -> shared table), B1..B5 and the deep
## mine to B15 with all of its own exact checks; this file hooks four of its
## steps (chapter_one, strike, first_visit, glass_furnace_leg) to add the warmer
## checks at the natural moments, then continues after the parent's B15
## save/reload with the installation and the warm hotpot round.
##
## Everything goes through World.act after World.move_player along BFS routes,
## and World.step for waits. NO direct writes by this file to inventory, coins,
## flags, mine progress, community / table_warmer, position or time.
##
## Warmer path:
##  1. Fresh world, before chapter one: warmer_install / serve_hotpot_warm refused
##     with LOCKED, canonical whole state unchanged (no walking: the server gate
##     precedes every position check).
##  2. Every parent mine strike (B5..B15) is re-checked here: warm_stone +1 and a
##     「暖岩片 +1」 message on B12/B13, none on any other floor (B11/B14 included),
##     and the whole-bag delta (catalog ore yield + one of each catalog find).
##     The parent strikes each of B12 and B13 three times (first visits), so the
##     six stones are exactly the natural strikes; none are added.
##  3. Home visit 3 (3 warm stones, B12 done, B13 not yet): TOO_FAR from the
##     transit arrival point, then at the table: SHORT (exact 缺料 text from the
##     real bag) and NOT_INSTALLED for the warm serve. On B13 after its strikes:
##     WRONG_REGION for both actions.
##  4. After the parent's B15 save/reload and ride home: SHORT again if the real
##     bag lacks joints/stone, copper_joint 2 / stone 4 earned with the parent's
##     obtain() (bench craft from practice-vein copper, rocks), WRONG_CELL,
##     BAD_EXTRA, install (exact debit, coins unchanged, state.table_warmer ==
##     {installed:true}), ALREADY, HOTPOT_SHORT with 0 hotpots, save -> reload into a
##     fresh World (whole canonical state equal, floats within 1e-6).
##  5. Six hotpots earned: wait to winter, Jiaoxi upland cold spring for two snow
##     trout (pity: <=20 eligible catches each), two cabbage seeds and one star
##     mushroom spawn bought with earned coins, cabbage grown at home, mushrooms on
##     B5's cave bed, two trout_hotpot cooks on the player's own chapter-one stove
##     (4 + 4). Warm serve refused with 4 hotpots, served with 8 (6 used), warm and
##     plain re-serve refused while portions remain, own claim, re-claim refused,
##     final save -> reload equal.
## NOT walked here: a plain 4-portion serve_hotpot after installation (8 cooked,
## 6 served warm, 2 + 1 claimed = 3 left), claims by other islanders (single
## player: one claim, then the re-claim refusal) — both are covered by the
## fixture-based test_table_warmer.gd only.
## Time: walking (World.move_player), transit, stairs and lift consume NO world
## time; world seconds come only from World.step waits (crop growth, processing,
## node cooldowns, fishing bites, the wait to winter). The printed
## walk_seconds figure is walk_tiles / 3.6 (the 3.6 tiles/s move speed).
## Prints TABLE_WARMER_JOURNEY evidence lines before the parent's lines; the last
## checks=N failures=M line is the parent's MINE_DEEP_JOURNEY_TESTS (same totals).

const Warmer=preload("res://scripts/table_warmer.gd")
const Community=preload("res://scripts/community.gd")
const STOVE:=Vector2i(40,34)
const MUSHROOM_BED:=Vector2i(30,21)
const HOTPOT_COOKS:=2

var last_result:={}
var table:=Vector2i(-1,-1)
var warm_refusals:=0
var warm_refusal_kinds:={}
var warm_strikes:={}
var warm_started:=false
var w_actions_start:=0
var w_walk_start:=0
var w_time_start:=0.0
var w_checks_start:=0
var hotpot_time_start:=0.0
var fish_casts:=0
var trout_casts:=[]
var coins_spent:=0
var coins_earned:=0
var warm_reloads:=0
var phase_marks:=[]

func finish() -> void:
	if warm_started:
		print("TABLE_WARMER_JOURNEY totals actions=%d walk_tiles=%d world_seconds=%.1f walk_seconds_at_3.6_tiles_per_s=%.1f warm_phase_actions=%d warm_phase_walk_tiles=%d warm_phase_world_seconds=%.1f hotpot_world_seconds=%.1f refusals=%d refusal_kinds=%s strikes=%s warm_strikes=%s fish_casts=%d trout_on_casts=%s coins_spent=%d coins_earned=%d reloads=%d warm_reloads=%d"%[actions,walking,now(),float(walking)/3.6,actions-w_actions_start,walking-w_walk_start,now()-w_time_start,now()-hotpot_time_start if hotpot_time_start>0.0 else 0.0,warm_refusals,JSON.stringify(warm_refusal_kinds),JSON.stringify(strikes),JSON.stringify(warm_strikes),fish_casts,JSON.stringify(trout_casts),coins_spent,coins_earned,reloads,warm_reloads])
		for line in phase_marks:print("TABLE_WARMER_JOURNEY phase "+str(line))
		print("TABLE_WARMER_JOURNEY_TESTS checks=%d failures=%d (warm slice checks=%d)"%[checks,failures,checks-w_checks_start])
	super.finish()

func run() -> void:
	super.run()
	if failed:return
	warm_started=true
	w_actions_start=actions
	w_walk_start=walking
	w_time_start=now()
	w_checks_start=checks
	mark("deep journey done (home)")
	install_leg()
	if failed:return
	hotpot_leg()

func mark(label:String) -> void:
	phase_marks.append("%s actions=%d walk_tiles=%d world_seconds=%.1f checks=%d coins=%d"%[label,actions,walking,now(),checks,int(person().coins)])

# ---------------------------------------------------------------- hooks into the parent

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	last_result=super.act(action,target,extra)
	return last_result

## Fresh world: both warmer actions refused before the picnic, then chapter one.
func chapter_one() -> void:
	expect(not world.state.get("picnic",false) and Community.table_cell(world.state)==Community.NO_CELL,"fresh world: no picnic, no shared table")
	expect(not world.state.has(Warmer.STATE_KEY),"fresh world: no table_warmer record")
	wrefuse(Warmer.INSTALL_ACTION,Community.CANDIDATES[0],"",Warmer.LOCKED,"install on a fresh world (before the picnic)",false)
	wrefuse(Warmer.SERVE_ACTION,Community.CANDIDATES[0],"",Warmer.LOCKED,"warm serve on a fresh world (before the picnic)",false)
	super.chapter_one()
	if failed:return
	table=Community.table_cell(world.state)
	expect(world.state.get("picnic")==true and table!=Community.NO_CELL,"earned picnic placed the shared table at %s"%str(table))
	expect(not world.state.has(Warmer.STATE_KEY),"picnic alone installs nothing")
	mark("chapter one / picnic")

## Every parent strike: warm_stone only on B12/B13, exact whole-bag delta, message.
func strike(d:int,node:Vector2i,how:String) -> void:
	if failed:return
	var before:=bag().duplicate(true)
	var count_before:=int(strikes.get(str(d),0))
	super.strike(d,node,how)
	if failed or int(strikes.get(str(d),0))==count_before:return
	var finds:Array=["crystal_sand"] if d==5 else Catalog.DEPTHS[d].finds
	var want_warm:=1 if d in [12,13] else 0
	expect(finds.count("warm_stone")==want_warm,"catalog B%d finds list warm_stone %d time(s) (%s)"%[d,want_warm,str(finds)])
	var ore:String=World.MINES.ORES[4] if d<=5 else str(Catalog.DEPTHS[d].ore)
	var amount:int=World.MINES.YIELDS[d-1] if d<=5 else int(Catalog.DEPTHS[d]["yield"])
	var delta:={ore:amount}
	for found:String in finds:delta[found]=int(delta.get(found,0))+1
	expect_delta(before,delta,"warm check: B%d %s at %s whole-bag delta %s"%[d,how,str(node),JSON.stringify(delta)])
	var warm:=int(bag().get("warm_stone",0))-int(before.get("warm_stone",0))
	var message:=str(last_result.get("message",""))
	expect(warm==want_warm,"B%d strike %d gives warm_stone +%d (got %+d)"%[d,count_before+1,want_warm,warm])
	if want_warm==1:
		expect(message.contains("暖岩片 +1"),"B%d strike message names 暖岩片 +1 (%s)"%[d,message])
	else:
		expect(not message.contains("暖岩片"),"B%d strike message has no 暖岩片 (%s)"%[d,message])
	if warm!=0:warm_strikes[str(d)]=int(warm_strikes.get(str(d),0))+warm

## On B13, after its three strikes: the table cannot be used from the mine.
func first_visit(d:int) -> void:
	super.first_visit(d)
	if failed:return
	if d==12:
		expect(int(bag().get("warm_stone",0))==3,"three B12 strikes earned 3 warm stones (has %d)"%int(bag().get("warm_stone",0)))
	elif d==13:
		expect(int(bag().get("warm_stone",0))==6,"three more B13 strikes: 6 warm stones held (has %d)"%int(bag().get("warm_stone",0)))
		wrefuse(Warmer.INSTALL_ACTION,table,"",Warmer.WRONG_REGION,"install from B13 (6 stones in the bag)",false)
		wrefuse(Warmer.SERVE_ACTION,table,"",Warmer.WRONG_REGION,"warm serve from B13",false)
		mark("B13 strikes done, 6 warm stones")

## Home visit 3 (between B12 and B13): too far, then one-material-short at the table.
func glass_furnace_leg() -> void:
	if failed:return
	expect(world.player_region(tok)=="home" and int(bag().get("warm_stone",0))==3,"home visit 3 holds the 3 B12 warm stones (has %d)"%int(bag().get("warm_stone",0)))
	var gap:=Vector2(person().x,person().y).distance_to(Vector2(table)+Vector2(0.5,0.5))
	if expect(gap>Warmer.REACH,"transit arrival point is %.2f tiles from the table (> %.1f)"%[gap,Warmer.REACH]):
		wrefuse(Warmer.INSTALL_ACTION,table,"",Warmer.TOO_FAR,"install from the transit arrival point",false)
	wrefuse(Warmer.INSTALL_ACTION,table,"",short_message(),"install at the table with only 3 warm stones")
	wrefuse(Warmer.SERVE_ACTION,table,"",Warmer.NOT_INSTALLED,"warm serve before any base exists")
	mark("home visit 3 refusals")
	super.glass_furnace_leg()

# ---------------------------------------------------------------- install

func install_leg() -> void:
	expect(world.player_region(tok)=="home","back home after the deep journey")
	expect(int(bag().get("warm_stone",0))==6,"exactly 6 warm stones held, all from strikes (has %d)"%int(bag().get("warm_stone",0)))
	expect(int(warm_strikes.get("12",0))==3 and int(warm_strikes.get("13",0))==3 and warm_strikes.size()==2,"warm stones came from 3 B12 + 3 B13 strikes only (%s)"%JSON.stringify(warm_strikes))
	var short:=false
	for item in ["copper_joint","stone"]:
		if int(bag().get(item,0))<int(Warmer.INSTALL_COST[item]):short=true
	if short:
		wrefuse(Warmer.INSTALL_ACTION,table,"",short_message(),"install with 6 stones but short of joints/stone (bag %s)"%JSON.stringify(pick_items(Warmer.INSTALL_COST)))
	phase_marks.append("pre-install bag for cost items %s short=%s"%[JSON.stringify(pick_items(Warmer.INSTALL_COST)),str(short)])
	obtain("copper_joint",int(Warmer.INSTALL_COST.copper_joint))
	obtain("stone",int(Warmer.INSTALL_COST.stone))
	if failed:return
	for item in Warmer.INSTALL_COST:
		expect(int(bag().get(item,0))>=int(Warmer.INSTALL_COST[item]),"holding %s >= %d (has %d)"%[item,int(Warmer.INSTALL_COST[item]),int(bag().get(item,0))])
	walk_to(table)
	wrefuse(Warmer.INSTALL_ACTION,table+Vector2i(1,1),"",Warmer.WRONG_CELL,"install aimed at a cell beside the table")
	wrefuse(Warmer.INSTALL_ACTION,BOARD,"",Warmer.WRONG_CELL,"install aimed at the dock board")
	wrefuse(Warmer.INSTALL_ACTION,table,"x",Warmer.BAD_EXTRA,"install with a non-empty extra")
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	expect(not world.state.has(Warmer.STATE_KEY),"no table_warmer record before installation")
	var result:=act(Warmer.INSTALL_ACTION,table)
	if failed:return
	expect(str(result.message)==Warmer.INSTALLED_OK,"install message (%s)"%str(result.message))
	var delta:={}
	for item in Warmer.INSTALL_COST:delta[item]=-int(Warmer.INSTALL_COST[item])
	expect_delta(before,delta,"install debits exactly warm_stone 6 / copper_joint 2 / stone 4")
	expect(int(bag().get("warm_stone",0))==0,"all six earned warm stones spent")
	expect(int(person().coins)==coins,"install costs no coins")
	expect(canon_bytes(world.state.get(Warmer.STATE_KEY))==canon_bytes({"installed":true}),"state.table_warmer == {installed:true}")
	expect(Warmer.installed(world.state),"Warmer.installed() true")
	wrefuse(Warmer.INSTALL_ACTION,table,"",Warmer.ALREADY,"second install")
	wrefuse(Warmer.SERVE_ACTION,table,"",Warmer.HOTPOT_SHORT,"warm serve with no hotpot")
	mark("installed")
	warm_reload("after install")
	if failed:return
	expect(Warmer.installed(world.state),"reloaded world still has the base")
	wrefuse(Warmer.INSTALL_ACTION,table,"",Warmer.ALREADY,"install after reload")

func short_message() -> String:
	var parts:=PackedStringArray()
	var labels:={"warm_stone":"暖岩片","copper_joint":"銅接頭","stone":"石材"}
	for item in ["warm_stone","copper_joint","stone"]:
		var lack:=int(Warmer.INSTALL_COST[item])-int(bag().get(item,0))
		if lack>0:parts.append("%s %d"%[labels[item],lack])
	return "保溫底座的材料不夠，還差%s。"%"、".join(parts)

# ---------------------------------------------------------------- hotpot

func hotpot_leg() -> void:
	hotpot_time_start=now()
	expect(world.player_region(tok)=="home","hotpot leg starts at home")
	wait_for_winter()
	if failed:return
	mark("winter noon")
	catch_trout(HOTPOT_COOKS)
	if failed:return
	mark("trout caught")
	buy_seeds()
	if failed:return
	grow_cabbage()
	if failed:return
	mark("cabbage harvested")
	grow_mushrooms()
	if failed:return
	mark("mushrooms harvested")
	cook_and_serve()

func wait_for_winter() -> void:
	var day:=WEATHER.DAY_SECONDS
	var year:=4*WEATHER.DAYS_PER_SEASON*day
	var winter_noon:float=(3*WEATHER.DAYS_PER_SEASON)*day+720.0
	if winter_noon<now():winter_noon+=ceilf((now()-winter_noon)/year)*year
	if WEATHER.season_on_day(WEATHER.day_index(now()))!="winter":wait(winter_noon-now())
	expect(WEATHER.season_on_day(WEATHER.day_index(now()))=="winter","it is winter (day %d)"%int(WEATHER.day_index(now())))

func catch_trout(count:int) -> void:
	var springs:=World.REGIONS.Springs.REGION
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,springs)
	if failed:return
	var pool:Vector2i=World.REGIONS.Springs.POOLS.upland.water.position
	var since:=0
	for guard in count*World.Collections.RARE_FISH_LIMIT+2:
		if failed or int(bag().get("snow_trout",0))>=count:break
		act("fish_start",pool)
		if failed:return
		wrefuse("fish_catch",pool,"","魚還沒咬鉤，再稍等一下","catch before the bite")
		wait(3.1)
		var before:=bag().duplicate(true)
		var misses:=int(person().get("jiaoxi_trout_misses",0))
		act("fish_catch",pool)
		if failed:return
		fish_casts+=1
		since+=1
		var got:="snow_trout" if int(bag().get("snow_trout",0))>int(before.get("snow_trout",0)) else "minnow"
		expect_delta(before,{got:1},"cold-spring catch %d is exactly one %s"%[fish_casts,got])
		if got=="snow_trout":
			expect(since<=World.Collections.RARE_FISH_LIMIT and int(person().get("jiaoxi_trout_misses",-1))==0,"trout within %d eligible casts (took %d), pity reset"%[World.Collections.RARE_FISH_LIMIT,since])
			trout_casts.append(since)
			since=0
		else:
			expect(int(person().get("jiaoxi_trout_misses",-1))==misses+1,"miss counter %d -> %d"%[misses,misses+1])
	expect(int(bag().get("snow_trout",0))==count,"caught %d snow trout (has %d)"%[count,int(bag().get("snow_trout",0))])
	travel(World.REGIONS.exit_cell(springs),"toucheng")
	travel(World.TRANSIT.points("toucheng").street.cell,"home")

func buy_seeds() -> void:
	var want:=[["cabbage",HOTPOT_COOKS],["star_mushroom",ceili(float(HOTPOT_COOKS)/float(World.CROPS.star_mushroom.yield))]]
	var price:=0
	for row in want:price+=int(World.CROPS[row[0]].seed_price)*int(row[1])
	phase_marks.append("seed bill %d coins, holding %d"%[price,int(person().coins)])
	if int(person().coins)<price and int(bag().get("minnow",0))>0:
		var coins:=int(person().coins)
		var amount:=int(bag().minnow)*int(World.FISH.minnow.price)
		act("sell",RECEIVER,"minnow")
		expect(int(person().coins)==coins+amount and int(bag().get("minnow",0))==0,"sold the cold-spring minnows for %d"%amount)
		coins_earned+=int(person().coins)-coins
	expect(int(person().coins)>=price,"earned coins %d cover the seeds (%d)"%[int(person().coins),price])
	for row in want:
		for n in int(row[1]):
			var coins:=int(person().coins)
			var before:=bag().duplicate(true)
			act("buy",RECEIVER,str(row[0]))
			if failed:return
			expect(int(person().coins)==coins-int(World.CROPS[row[0]].seed_price),"%s seed costs %d"%[row[0],int(World.CROPS[row[0]].seed_price)])
			expect_delta(before,{str(row[0])+"_seed":1},"bought one %s seed"%row[0])
			coins_spent+=coins-int(person().coins)

func grow_cabbage() -> void:
	var plots:Array=[]
	for n in HOTPOT_COOKS:
		var plot:=Vector2i(-1,-1)
		for k in world.state.crops:
			var crop:Dictionary=world.state.crops[k]
			var c:=World.cell(k)
			if str(crop.get("kind",""))=="" and crop.get("owner","")==tok and c not in plots and not route(c).is_empty():
				plot=c
				break
		if not expect(plot!=Vector2i(-1,-1),"own empty chapter-one plot %d for cabbage"%(n+1)):return
		plots.append(plot)
	for plot:Vector2i in plots:
		expect(World.crop_grows_in_season("cabbage","home",plot,now()),"cabbage grows at home in winter")
		var before:=bag().duplicate(true)
		act("seed",plot,"cabbage")
		expect_delta(before,{"cabbage_seed":-1},"cabbage seed planted at %s"%str(plot))
		act("water",plot)
	grow(plots)
	for plot:Vector2i in plots:
		var before:=bag().duplicate(true)
		act("harvest",plot)
		expect_delta(before,{"cabbage":int(World.CROPS.cabbage.yield)},"cabbage harvest at %s"%str(plot))
	expect(int(bag().get("cabbage",0))>=HOTPOT_COOKS,"holding %d cabbage"%int(bag().get("cabbage",0)))

func grow_mushrooms() -> void:
	ride_to_mine_town()
	act("mine_travel",World.MINES.ENTRY,"mine_1")
	for depth in range(1,5):act("mine_travel",World.MINES.DOWN,"mine_%d"%(depth+1))
	if not expect(world.player_region(tok)=="mine_5","stairs down to B5's cave beds"):return
	var bed_crop:Dictionary=region_crops().get(World.key(MUSHROOM_BED),{})
	if bed_crop.is_empty():act("hoe",MUSHROOM_BED)
	var before:=bag().duplicate(true)
	act("seed",MUSHROOM_BED,"star_mushroom")
	expect_delta(before,{"star_mushroom_seed":-1},"mushroom spawn planted on B5")
	act("water",MUSHROOM_BED)
	grow([MUSHROOM_BED])
	before=bag().duplicate(true)
	act("harvest",MUSHROOM_BED)
	expect_delta(before,{"star_mushroom":int(World.CROPS.star_mushroom.yield)},"star mushroom harvest on B5")
	for depth in range(5,1,-1):act("mine_travel",World.MINES.UP,"mine_%d"%(depth-1))
	act("mine_travel",World.MINES.UP,"jinguashi")
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")

func cook_and_serve() -> void:
	expect(str(world.state.objects.get(World.key(STOVE),{}).get("type",""))=="stove" and not world.state.objects[World.key(STOVE)].has("job"),"own idle chapter-one stove at %s"%str(STOVE))
	var recipe:Dictionary=World.RECIPES.trout_hotpot
	for n in HOTPOT_COOKS:
		var before:=bag().duplicate(true)
		act("cook",STOVE,"trout_hotpot")
		if failed:return
		var delta:={}
		for item in recipe.ingredients:delta[item]=-int(recipe.ingredients[item])
		expect_delta(before,delta,"hotpot cook %d debits trout/cabbage/mushroom"%(n+1))
		wrefuse("claim_cook",STOVE,"","還要 %d 秒就好了"%ceili(float(recipe.time)),"claim before the hotpot is done")
		wait(float(recipe.time))
		before=bag().duplicate(true)
		act("claim_cook",STOVE)
		expect_delta(before,{"trout_hotpot":int(recipe.yield)},"hotpot cook %d yields %d"%[n+1,int(recipe.yield)])
		if n==0:
			wrefuse(Warmer.SERVE_ACTION,table,"",Warmer.HOTPOT_SHORT,"warm serve with %d hotpots"%int(bag().get("trout_hotpot",0)))
	if failed:return
	var held:=int(bag().get("trout_hotpot",0))
	expect(held>=Warmer.WARM_PORTIONS,"holding %d earned hotpots"%held)
	mark("hotpots cooked (%d)"%held)
	walk_to(table)
	var before:=bag().duplicate(true)
	var result:=act(Warmer.SERVE_ACTION,table)
	if failed:return
	expect(str(result.message)==Warmer.WARM_SERVED,"warm serve message (%s)"%str(result.message))
	expect_delta(before,{"trout_hotpot":-6},"warm serve takes exactly six hotpots")
	expect(canon_bytes(world.state.community.get("hotpot"))==canon_bytes({"portions":6,"claimed":{},"total":6}),"six warm portions on the table (%s)"%JSON.stringify(world.state.community.get("hotpot")))
	wrefuse(Warmer.SERVE_ACTION,table,"",Warmer.STILL_SERVING,"warm serve while warm portions remain")
	wrefuse("serve_hotpot",table,"","餐桌上還有雪點鱒魚火鍋，先留給晚點回來的島民。","plain serve while warm portions remain")
	before=bag().duplicate(true)
	result=act("claim_hotpot",table)
	expect(str(result.message)=="已領取一份雪點鱒魚火鍋。","claim message (%s)"%str(result.message))
	expect_delta(before,{"trout_hotpot":1},"own claim gives one portion")
	var claimed:={}
	claimed[tok]=true
	expect(canon_bytes(world.state.community.hotpot)==canon_bytes({"portions":5,"claimed":claimed,"total":6}),"table now 5 of 6 with one claim")
	wrefuse("claim_hotpot",table,"","你已領過這一輪，剩下的留給其他島民。","re-claim from the same round")
	mark("served and claimed")
	warm_reload("final")
	if failed:return
	expect(int(world.state.community.hotpot.portions)==5 and Warmer.installed(world.state),"reloaded: base installed, 5 warm portions left")
	wrefuse("claim_hotpot",table,"","你已領過這一輪，剩下的留給其他島民。","re-claim after reload")

# ---------------------------------------------------------------- helpers

## Refused with the exact message; whole canonical world state unchanged.
func wrefuse(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	actions+=1
	var before:=canon_bytes(world.state)
	var snapshot:Variant=_canon(world.state)
	var result:=world.act(tok,"warmer-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var after:=canon_bytes(world.state)
	expect(after==before,"%s: canonical world state unchanged %s"%[label,"" if after==before else first_diff(snapshot,_canon(world.state),"state")])
	warm_refusals+=1
	var kind:=action+":"+message.left(12)
	warm_refusal_kinds[kind]=int(warm_refusal_kinds.get(kind,0))+1

## Save, reload into a fresh World, compare the WHOLE canonical state (floats 1e-6).
func warm_reload(label:String) -> void:
	if failed:return
	expect(world.save(),label+": save")
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": fresh World loads the save"):return
	var diff:=close_diff(_canon(world.state),_canon(reopened.state),"state")
	expect(diff=="",label+": whole canonical state equal after reload %s"%diff)
	reopened.save_path=save_path
	reopened.add_player(tok,"Bloom A")
	for field in ["region","x","y","inventory","coins","mine_energy"]:
		expect(close_diff(_canon(reopened.state.players[tok].get(field)),_canon(person().get(field)),field)=="",label+": player %s kept after rejoin"%field)
	world=reopened
	warm_reloads+=1

## "" when equal; numbers compare with 1e-6 tolerance (JSON turns ints into floats).
func close_diff(a:Variant,b:Variant,path:String) -> String:
	var na:=a is int or a is float
	var nb:=b is int or b is float
	if na and nb:return "" if absf(float(a)-float(b))<=1e-6 else "%s: %s vs %s"%[path,str(a),str(b)]
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		if a.keys()!=b.keys():return "%s keys %s vs %s"%[path,str(a.keys()).left(200),str(b.keys()).left(200)]
		for k in a:
			var d:=close_diff(a[k],b[k],path+"."+str(k))
			if d!="":return d
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=close_diff(a[i],b[i],"%s[%d]"%[path,i])
			if d!="":return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a).left(80),str(b).left(80)]
