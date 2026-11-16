extends "res://tests/test_tea_revisit_journey.gd"
## Chapter 40「臺南北門回訪・鹽籃批次」+ 鹽籃 natural journey: a FRESH temp world, ONE
## player (A) for the whole batch (plus the late joiners the parents add), one brand-new
## islander C and the never-raked flower late joiner B (rejoining) at the end, ONE
## process (reloads are in-process World.new().load_world on the same save; the journey
## continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_tea_revisit_journey.gd (-> jinguashi revisit -> memory exhibit -> festival earned
## -> salt pan -> flower journeys). That chain earns chapter one, the Beimen gates (A and
## B give the materials), A's own hand rakes (raked=2), the real 風鈴節 opening and the
## 分水木牌 / 礦燈 / 茶陶組 exhibits. It never touches state.salt_revisit.
##
## Hooks (no walking): chapter_one() (fresh world: A at home, the four actions answer
## WRONG_REGION, the pure blocks LOCKED), act() right before A's own first salt_intro
## (A in 北門, gates not repaired: LOCKED) and right before A's own first salt_flood
## (gates repaired, A never raked: NOT_READY).
##
## Segment: A stashes the sea salt and fiber the chain left in the bag in a new home
## chest (build + deposit, real actions) so that every lot and every basket of the batch
## uses salt raked and fiber gathered in this segment. Salt comes only from the public
## hand pans (salt_flood -> World.step -> salt_rake); fiber only from felling trees.
## Everything goes through World.act after World.move_player along BFS routes, waits
## only through World.step (inherited wait()), travel through the real transit action.
## NO direct writes by this file to inventory, coins, flags, records, objects, positions
## or time. C joins with World.add_player (the Session join path); B rejoins the same way.
## Prints SALT_REVISIT_JOURNEY lines before the parents' summary lines.

const SR=preload("res://scripts/salt_revisit.gd")
const SR_C:="salt-revisit-late-c"
const SR_C_NAME:="Basket Late"
## Independent copy of the season order table from the rules report.
const SR_ORDER_TABLE:={
	"spring":{"kitchen":3,"pickle":3},
	"summer":{"kitchen":2,"pickle":4},
	"autumn":{"kitchen":4,"pickle":2},
	"winter":{"kitchen":5,"pickle":1},
}
const SR_PANS:=[16,17]
const SR_BASKET_SPOTS:=[Vector2i(36,36),Vector2i(34,37),Vector2i(36,37),Vector2i(33,37),Vector2i(37,37),Vector2i(35,37),Vector2i(37,36),Vector2i(32,36)]

var sr_fresh_done:=false
var sr_locked_done:=false
var sr_notready_done:=false
var sr_started:=false
var sr_ms:=0
var sr_actions_start:=0
var sr_walk_start:=0
var sr_time_start:=0.0
var sr_checks_start:=0
var sr_reloads_start:=0
var sr_refusals:=[]
var sr_changed:=0
var sr_info:={}
var sr_rakes:=[]
var sr_floods:={}
var sr_flood_log:=[]
var sr_stocks:=[]
var sr_packs:=[]
var sr_trees:=[]
var sr_chest:=Vector2i(-1,-1)

# ---------------------------------------------------------------- hooks

func chapter_one() -> void:
	if not sr_fresh_done:
		sr_fresh_done=true
		sr_fresh()
	super.chapter_one()

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if not failed and tok==TOKEN_A and world.state.players.has(TOKEN_A) and world.state.get("salt_pan") is Dictionary:
		var raked:=int((world.state.salt_pan.players as Dictionary).get(TOKEN_A,{}).get("raked",0))
		if action=="salt_intro" and not sr_locked_done:
			sr_locked_done=true
			sr_locked_in_beimen()
		elif action=="salt_flood" and not sr_notready_done and S.repaired(world.state) and raked==0:
			sr_notready_done=true
			sr_not_ready_in_beimen()
	return super.act(action,target,extra)

## Fresh world: A at home, no gates.
func sr_fresh() -> void:
	var s:=world.state
	sr_check(world.player_region(tok)=="home" and not SR.unlocked(s) and not SR.player_ready(s,tok) and not s.has(SR.STATE_KEY),"fresh world: A at home, gates not repaired, not ready, no record")
	sr_blocks_all(SR.LOCKED,"fresh world")
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_LOCKED and not ME.available(s,"beimen"),"fresh world: basket hint LOCKED, no exhibit")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.WRONG_REGION,"fresh world stock (at home)",false)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.WRONG_REGION,"fresh world pack (at home)",false)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.WRONG_REGION,"fresh world send (at home)",false)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"fresh world claim (at home)",false)

## A in 北門 for the first time, right before the intro: gates not repaired.
func sr_locked_in_beimen() -> void:
	var s:=world.state
	sr_check(world.player_region(tok)==SR.REGION and not SR.unlocked(s) and not s.has(SR.STATE_KEY),"pre-intro: A in 北門, gates not repaired, no record")
	sr_blocks_all(SR.LOCKED,"pre-intro")
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_LOCKED,"pre-intro: hint LOCKED")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.LOCKED,"pre-intro stock in 北門",false,true)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.LOCKED,"pre-intro pack in 北門",false,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.LOCKED,"pre-intro send in 北門",false,true)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.LOCKED,"pre-intro claim in 北門",false,true)
	sr_info.locked_hook={"day":SR.today(s),"world_seconds":now(),"pos":[float(person().x),float(person().y)]}

## Gates repaired (B closed the last gap), right before A's own first flood: never raked.
func sr_not_ready_in_beimen() -> void:
	var s:=world.state
	sr_check(world.player_region(tok)==SR.REGION and SR.unlocked(s) and not SR.player_ready(s,tok) and not s.has(SR.STATE_KEY),"pre-rake: A in 北門, gates repaired, A never raked, no record")
	sr_blocks_all(SR.NOT_READY,"pre-rake")
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_NOT_DONE_NOT_READY,"pre-rake: hint NOT_DONE_NOT_READY")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.NOT_READY,"pre-rake stock",false,true)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.NOT_READY,"pre-rake pack",false,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.NOT_READY,"pre-rake send",false,true)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_READY,"pre-rake claim",false,true)
	sr_check(not world.state.has(SR.STATE_KEY),"pre-rake: no record written")
	sr_info.not_ready_hook={"day":SR.today(s),"world_seconds":now(),"pos":[float(person().x),float(person().y)]}

func sr_blocks_all(want:String,label:String) -> void:
	var s:=world.state
	var inv:Dictionary=bag()
	sr_check(SR.stock_block(s,inv,tok)==want and SR.pack_block(s,"kitchen",inv,tok)==want and SR.pack_block(s,"pickle",inv,tok)==want and SR.send_block(s,tok)==want and SR.claim_block(s,inv,tok)==want and not SR.can_claim(s,inv,tok),"%s: stock/pack/send/claim blocks all '%s'"%[label,want])

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	sr_check(sr_fresh_done and sr_locked_done and sr_notready_done,"fresh-world, pre-intro and pre-rake hooks ran")
	sr_started=true
	sr_ms=Time.get_ticks_msec()
	sr_actions_start=actions
	sr_walk_start=walking
	sr_time_start=now()
	sr_checks_start=checks
	sr_reloads_start=ex_reloads
	tok=TOKEN_A
	sr_info.start={"day":SR.today(world.state),"season":SR.order_season(world.state),"weather":SR.weather_today(world.state),"world_seconds":now(),"held":sr_held(),"raked":int(S.own_record(world.state,tok).raked)}
	print("SALT_REVISIT_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d %s %s, A holds %s)"%[checks,actions,now(),SR.today(world.state),SR.order_season(world.state),SR.weather_today(world.state),JSON.stringify(sr_held())])
	sr_start()
	if not failed:sr_stash_and_fiber()
	if not failed:sr_day_one()
	if not failed:sr_day_two()
	if not failed:sr_rain_day()
	if not failed:sr_last_day()
	if not failed:sr_send()
	if not failed:sr_claim_and_reload()
	if not failed:sr_basket_home()
	if not failed:sr_exhibit()
	if not failed:sr_late_c()
	if not failed:sr_rejoin_b()
	if not failed:sr_final()

## A at home after the parents: ready, no record; refusals that do not need travel.
func sr_start() -> void:
	var s:=world.state
	sr_check(world.player_region(tok)=="home" and SR.unlocked(s) and SR.player_ready(s,tok) and not s.has(SR.STATE_KEY),"start: A at home, gates repaired, A raked, no revisit record")
	sr_check(ME.on_display_ids(s)==["lanyang","jinguashi","tea_pottery"] and not ME.available(s,"beimen") and ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_NOT_DONE,"start: three exhibits on display, basket hint NOT_DONE")
	var inv:Dictionary=bag()
	var salt:=int(inv.get("sea_salt",0))
	sr_check(SR.stock_block(s,inv,tok)==("" if salt>=3 else SR.NO_SALT%[3,salt]) and SR.pack_block(s,"kitchen",inv,tok)==SR.NEED_STOCK%[0,0] and SR.send_block(s,tok)==SR.NOT_PACKED%0 and SR.claim_block(s,inv,tok)==SR.NOT_DONE,"start: pure blocks (stock by salt held %d, pack NEED_STOCK 0/0, send NOT_PACKED 0, claim NOT_DONE)"%salt)
	sr_check(SR.order_season(s)==WEATHER.season_on_day(WEATHER.day_index(now())) and SR.order(s)==SR_ORDER_TABLE[SR.order_season(s)] and SR.reason(s)==SR.reason_for(SR.order_season(s)),"start: order follows today's season %s %s"%[SR.order_season(s),JSON.stringify(SR.order(s))])
	var stand:=ME.stand_cell(s)
	sr_deny(ME.VIEW_ACTION,stand,"beimen",ME.NOT_ON_DISPLAY,"view the salt basket before the revisit")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.WRONG_REGION,"stock at home (ready)",false)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.WRONG_REGION,"pack at home (ready)",false)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.WRONG_REGION,"send at home (ready)",false)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"claim at home (ready)",false)

## Home: put the chain's sea salt and fiber away in a new chest, then fell trees for
## exactly 10 fiber (the 12th basket fiber comes later when A runs out).
func sr_stash_and_fiber() -> void:
	var a0:=actions
	var before:=sr_held(["sea_salt","fiber","wood","resin","sapling"])
	while not failed and int(bag().get("wood",0))<int(World.BUILD.chest.wood):sr_fell_tree("wood for the chest")
	if failed:return
	sr_chest=open_cell()
	if not sr_check(sr_chest!=Vector2i(-1,-1),"open home cell for the stash chest"):return
	var w0:=int(bag().get("wood",0))
	act("build",sr_chest,"chest")
	if failed:return
	sr_check(int(bag().get("wood",0))==w0-int(World.BUILD.chest.wood) and str(world.state.objects.get(World.key(sr_chest),{}).get("type",""))=="chest","chest built at %s for wood %d"%[str(sr_chest),int(World.BUILD.chest.wood)])
	var stash:={}
	for item in ["sea_salt","fiber"]:
		var n:=int(bag().get(item,0))
		stash[item]=n
		for i in n:
			act("deposit",sr_chest,item)
			if failed:return
	var box:Dictionary=world.state.objects[World.key(sr_chest)].items
	sr_check(int(bag().get("sea_salt",0))==0 and int(bag().get("fiber",0))==0 and int(box.get("sea_salt",0))==int(stash.sea_salt) and int(box.get("fiber",0))==int(stash.fiber),"stash: bag sea_salt 0 / fiber 0; chest holds %s"%JSON.stringify(stash))
	sr_info.stash={"chest":[sr_chest.x,sr_chest.y],"items":stash,"bag_before":before,"deposit_actions":int(stash.sea_salt)+int(stash.fiber)}
	sr_info.stash_box=canon_bytes(box)
	for n in 5:
		sr_fell_tree("fiber for the batch")
		if failed:return
	sr_check(int(bag().get("fiber",0))==10,"10 fiber gathered for the first five baskets")
	sr_info.home_prep={"actions":actions-a0,"after":sr_held(["sea_salt","fiber","wood","resin","sapling"])}

## Fell one tree; the whole bag delta is exactly wood +6, fiber +2, sapling +1, resin +1.
func sr_fell_tree(label:String) -> void:
	var b:=bag().duplicate(true)
	var target:=find_resource("tree")
	if not sr_check(target!=Vector2i(-1,-1),"reachable tree (%s)"%label):return
	var hits:=0
	for guard in 3:
		if failed or world.resource(target)!="tree":break
		act("axe",target)
		hits+=1
	if failed:return
	var e:=b.duplicate(true)
	e["wood"]=int(b.get("wood",0))+6
	e["fiber"]=int(b.get("fiber",0))+2
	e["sapling"]=int(b.get("sapling",0))+1
	e["resin"]=int(b.get("resin",0))+1
	expect_same(bag(),e,"SALT_REVISIT_JOURNEY: tree %s felled (%s): whole bag delta wood +6 fiber +2 sapling +1 resin +1"%[str(target),label])
	sr_trees.append({"cell":[target.x,target.y],"hits":hits,"label":label,"day":SR.today(world.state)})

## Day 1 (expected sunny): travel, location refusals, rake, stock two sunny lots.
func sr_day_one() -> void:
	travel(FERRY,SR.REGION)
	if failed:return
	var s:=world.state
	sr_check(Vector2(person().x,person().y)==SR.STOP_STAND,"arrived at the 北門 stop (%.1f,%.1f)"%[float(person().x),float(person().y)])
	sr_check(SR.weather_today(s)=="sunny","day %d in 北門 is sunny (got %s)"%[SR.today(s),SR.weather_today(s)])
	sr_info.day_one={"day":SR.today(s),"weather":SR.weather_today(s),"arrive_seconds":now()}
	sr_check(sr_dist(SR.WORKER)>SR.REACH and sr_dist(SR.CHEST)<=SR.REACH and sr_dist(SR.STOP)<=SR.REACH,"at the arrival: 阿曬 %.2f away (out of reach), chest %.2f and stop %.2f in reach"%[sr_dist(SR.WORKER),sr_dist(SR.CHEST),sr_dist(SR.STOP)])
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.TOO_FAR,"stock from the arrival (too far)",false)
	sr_deny(SR.STOCK_ACTION,SR.CHEST,"",SR.WRONG_STOCK_CELL,"stock at the chest (wrong cell)",false)
	sr_deny(SR.PACK_ACTION,SR.WORKER,"kitchen",SR.WRONG_PACK_CELL,"pack at 阿曬 (wrong cell)",false)
	sr_deny(SR.SEND_ACTION,SR.CHEST,"",SR.WRONG_SEND_CELL,"send at the chest (wrong cell)",false)
	sr_deny(SR.CLAIM_ACTION,SR.STOP,"",SR.WRONG_CLAIM_CELL,"claim at the stop (wrong cell)",false)
	var msg:=SR.NEED_STOCK%[0,0]
	sr_check(msg=="倉棚裡入倉的散鹽有 0 批，已經裝了 0 籃；先帶海鹽找阿曬入倉。","NEED_STOCK text")
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",msg,"pack before anything is stocked",false,true)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"salt",SR.BAD_KIND,"pack an unknown kind",false,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%0,"send before anything is packed",false,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"now",SR.BAD_EXTRA,"send with a non-empty extra",false)
	walk_to(SR.WORKER)
	if failed:return
	sr_check(sr_dist(SR.WORKER)<=SR.REACH and sr_dist(SR.CHEST)>SR.REACH and sr_dist(SR.STOP)>SR.REACH,"at 阿曬: chest %.2f and stop %.2f out of reach"%[sr_dist(SR.CHEST),sr_dist(SR.STOP)])
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.TOO_FAR,"pack from 阿曬 (too far)",false)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.TOO_FAR,"send from 阿曬 (too far)",false)
	var no_salt:=SR.NO_SALT%[3,0]
	sr_check(no_salt=="入倉一批要海鹽 3 份，你的背包裡有 0 份。","NO_SALT text")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",no_salt,"stock with no sea salt",false,true)
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"x",SR.BAD_EXTRA,"stock with a non-empty extra",false)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_DONE,"claim before completion",false,true)
	sr_check(not world.state.has(SR.STATE_KEY),"no record after the day-1 refusals")
	# Salt: whatever already formed in the public pans, then flood -> wait -> rake.
	if not sr_salt_until(9,next_midnight()-1.0):return
	# Only 2 of the 3 possible lots today: one stays in the bag (3 salt) for later.
	var held:=int(bag().get("sea_salt",0))
	sr_stock()
	sr_check(int(bag().get("sea_salt",0))==held-3,"stock takes 3 sea salt")
	if failed:return
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.TOO_FAR,"pack from 阿曬 after the first lot (too far)",false)
	sr_stock()
	sr_flood_empty()
	sr_check(SR.stocked(world.state)=={"sunny":2,"cloudy":0},"day 1: two sunny lots %s"%JSON.stringify(SR.stocked(world.state)))
	sr_next_day()

## Day 2 (expected cloudy): one lot from the bag, rake, one more lot, keep 3 salt.
func sr_day_two() -> void:
	var s:=world.state
	sr_check(SR.weather_today(s)=="cloudy","day %d in 北門 is cloudy (got %s)"%[SR.today(s),SR.weather_today(s)])
	sr_info.day_two={"day":SR.today(s),"weather":SR.weather_today(s)}
	sr_stock()
	if failed:return
	var no_salt:=SR.NO_SALT%[3,int(bag().get("sea_salt",0))]
	if int(bag().get("sea_salt",0))<3:sr_deny(SR.STOCK_ACTION,SR.WORKER,"",no_salt,"stock again with too little salt (day 2)",true,true)
	if not sr_salt_until(6,next_midnight()-1.0):return
	sr_stock()
	sr_flood_empty()
	sr_check(SR.stocked(world.state)=={"sunny":2,"cloudy":2} and int(bag().get("sea_salt",0))>=3,"day 2: lots sunny 2 / cloudy 2, %d salt kept in the bag"%int(bag().get("sea_salt",0)))
	sr_check(SR.packed_total(world.state)==0 and int(SR.record(world.state).day)==0,"nothing packed yet, order day 0")
	sr_next_day()

## Day 3 (expected rainy): the shed refuses salt; pack the four stocked lots instead.
func sr_rain_day() -> void:
	var s:=world.state
	sr_check(SR.weather_today(s)=="rainy" and SR.rainy_today(s) and raining(),"day %d in 北門 is rainy (got %s)"%[SR.today(s),SR.weather_today(s)])
	var season:=SR.order_season(s)
	var order:=SR.order(s)
	sr_check(season==WEATHER.season_on_day(WEATHER.day_index(now())) and order==SR_ORDER_TABLE[season] and SR.order_for(season)==order and SR.reason(s)==SR.reason_for(season),"%s order %s matches the copied table"%[season,JSON.stringify(order)])
	sr_info.rain_day={"day":SR.today(s),"weather":SR.weather_today(s),"season":season,"order":order,"salt_held":int(bag().get("sea_salt",0))}
	sr_check(int(bag().get("sea_salt",0))>=3 and SR.progress(s).rainy_today==true,"holding %d sea salt on the rainy day"%int(bag().get("sea_salt",0)))
	sr_check(SR.RAIN_STOCK=="下雨天倉棚不收散鹽，怕受潮；已經入倉的鹽可以先裝籃。","RAIN_STOCK text")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.RAIN_STOCK,"stock on a rainy day (holding salt)",true,true)
	print("SALT_REVISIT_JOURNEY order day=%d season=%s order=%s held=%s"%[SR.today(s),season,JSON.stringify(order),JSON.stringify(sr_held())])
	# Pack the smaller quota first, then try it once more (QUOTA_FULL).
	var first:="kitchen" if int(order.kitchen)<=int(order.pickle) else "pickle"
	var other:="pickle" if first=="kitchen" else "kitchen"
	var lots:=SR.stocked_total(s)
	var plan:=[]
	for n in int(order[first]):plan.append(first)
	for n in int(order[other]):plan.append(other)
	var quota_msg:=SR.QUOTA_FULL%[str(SR.KIND_NAMES[first]),int(order[first]),int(order[first]),str(SR.KIND_NAMES[other])]
	if season=="summer":sr_check(quota_msg=="這批料理用只要 2 籃，已經裝了 2 籃；剩下的要醃漬用。","QUOTA_FULL text (summer)")
	sr_info.pack_plan=plan
	sr_info.quota_msg=quota_msg
	for i in lots:
		if failed:return
		if i==int(order[first]):sr_deny(SR.PACK_ACTION,SR.CHEST,first,quota_msg,"pack %s beyond the season quota"%first,true,true)
		sr_pack(str(plan[i]))
		if i==0:
			sr_check(int(SR.record(world.state).day)==SR.today(world.state),"first pack stamps the order day %d"%SR.today(world.state))
	if failed:return
	s=world.state
	sr_check(SR.packed_total(s)==lots and SR.rain_packs(s)==lots,"packed %d on the rainy day, rain_packs %d"%[SR.packed_total(s),SR.rain_packs(s)])
	sr_deny(SR.PACK_ACTION,SR.CHEST,str(plan[lots]),SR.NEED_STOCK%[lots,lots],"pack beyond the stock (%d/%d)"%[lots,lots],true,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%lots,"send with %d packed"%lots,true,true)
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.RAIN_STOCK,"stock again later the same rainy day",true,true)
	sr_info.rain_day.order_day=int(SR.record(world.state).day)
	sr_next_day()

## Day 4 (expected sunny): stock the last two lots, pack, run out of fiber, fell a tree
## at home, pack the sixth, save/reload with 6 packed but not sent.
func sr_last_day() -> void:
	var s:=world.state
	sr_check(SR.weather_today(s)=="sunny","day %d in 北門 is sunny (got %s)"%[SR.today(s),SR.weather_today(s)])
	sr_check(SR.order_season(s)==str(sr_info.rain_day.season) and SR.order(s)==sr_info.rain_day.order,"order stays locked to day %d (%s)"%[int(SR.record(s).day),SR.order_season(s)])
	sr_info.last_day={"day":SR.today(s),"weather":SR.weather_today(s)}
	sr_stock()
	if failed:return
	if not sr_salt_until(6,next_midnight()-1.0):return
	sr_stock()
	if failed:return
	s=world.state
	sr_check(SR.stocked_total(s)==SR.TOTAL and SR.stocked(s)=={"sunny":4,"cloudy":2},"all 6 lots in: %s"%JSON.stringify(SR.stocked(s)))
	sr_check(int(bag().get("sea_salt",0))>=3,"still holding %d sea salt"%int(bag().get("sea_salt",0)))
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.STOCK_FULL,"a seventh lot (holding salt)",true,true)
	var plan:Array=sr_info.pack_plan
	var done:=SR.packed_total(s)
	sr_pack(str(plan[done]))
	if failed:return
	done+=1
	sr_check(int(bag().get("fiber",0))==0,"fiber used up after %d baskets"%done)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%done,"send with %d packed"%done,true,true)
	var no_fiber:=SR.NO_FIBER%[2,0]
	sr_check(no_fiber=="裝一籃要纖維 2 份（編籃、綁口），你的背包裡有 0 份。","NO_FIBER text")
	sr_deny(SR.PACK_ACTION,SR.CHEST,str(plan[done]),no_fiber,"pack without fiber",true,true)
	travel(SR.STOP,"home")
	sr_fell_tree("fiber for the sixth basket")
	travel(FERRY,SR.REGION)
	if failed:return
	sr_check(SR.today(world.state)==int(sr_info.last_day.day),"the fiber trip took no world time (still day %d)"%SR.today(world.state))
	sr_pack(str(plan[done]))
	if failed:return
	s=world.state
	sr_check(SR.packed_total(s)==SR.TOTAL and SR.packed(s)==SR.order(s) and int(bag().get("fiber",0))==0,"6 packed %s = the order"%JSON.stringify(SR.packed(s)))
	sr_deny(SR.PACK_ACTION,SR.CHEST,"pickle",SR.ALL_PACKED,"pack a seventh basket",true,true)
	sr_check(SR.progress(world.state).ready_to_send==true and SR.send_block(world.state,tok)=="" and not SR.completed(world.state),"ready to send, not completed")
	var rec:=canon_bytes(world.state[SR.STATE_KEY])
	ex_reload("6 packed, not yet sent")
	if failed:return
	sr_check(canon_bytes(world.state[SR.STATE_KEY])==rec and not SR.completed(world.state) and SR.packed_total(world.state)==SR.TOTAL,"6-packed record identical after reload and still not sent")

func sr_send() -> void:
	walk_to(SR.STOP)
	var rid:=sr_ok(SR.SEND_ACTION,SR.STOP,"",SR.COMPLETE_OK,"send the batch",["state.%s"%SR.STATE_KEY])
	if failed:return
	var bytes:=canon_bytes(world.state)
	var again:=world.act(tok,rid,SR.SEND_ACTION,SR.STOP,"")
	sr_check(again.ok==true and str(again.message)==SR.COMPLETE_OK and canon_bytes(world.state)==bytes,"resend of the send %s returns the stored receipt"%rid)
	var s:=world.state
	var rec:=SR.record(s)
	sr_check(rec.completed==true and int(rec.done_day)==SR.today(s) and int(rec.day)==int(sr_info.rain_day.order_day) and (rec.claimed as Dictionary).is_empty(),"completed record %s"%JSON.stringify(SR.public(s)))
	sr_check(ME.available(s,"beimen") and ME.on_display_ids(s)==["lanyang","jinguashi","tea_pottery","beimen"],"completion itself puts the salt basket on the exhibit: all four on display")
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_UNCLAIMED,"hint UNCLAIMED")
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.ALREADY_DONE,"send again (new request)",false,true)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"pickle",SR.ALREADY_DONE,"pack after completion",false,true)
	var weather:=WEATHER.outdoor_id(float(int(rec.done_day)-1))
	sr_info.revisit={"order_day":int(rec.day),"done_day":int(rec.done_day),"season":str(sr_info.rain_day.season),"order":sr_info.rain_day.order,"stocked":SR.stocked(s),"packed":SR.packed(s),"rain_packs":SR.rain_packs(s),"weather_done_day":weather,"world_seconds":now()}
	print("SALT_REVISIT_JOURNEY completed %s"%JSON.stringify(sr_info.revisit))

func sr_claim_and_reload() -> void:
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.TOO_FAR,"claim from the stop (too far)",false)
	walk_to(SR.WORKER)
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.ALREADY_DONE,"stock after completion",false,true)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"x",SR.BAD_EXTRA,"claim with a non-empty extra",false)
	sr_check(int(bag().get(SR.BASKET_ITEM,0))==0,"no basket kit before claiming")
	var rid:=sr_ok(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIM_OK,"claim the salt basket",["state.%s.claimed"%SR.STATE_KEY,"state.players.%s.inventory.%s"%[tok,SR.BASKET_ITEM]])
	if failed:return
	sr_check(int(bag().get(SR.BASKET_ITEM,0))==1 and SR.claimed_own(world.state,tok) and ME.personal_hint_for(world.state,"beimen",tok)==ME.HINT_SALT_CLAIMED,"one basket kit; hint CLAIMED")
	var bytes:=canon_bytes(world.state)
	var again:=world.act(tok,rid,SR.CLAIM_ACTION,SR.WORKER,"")
	sr_check(again.ok==true and str(again.message)==SR.CLAIM_OK and canon_bytes(world.state)==bytes and int(bag().get(SR.BASKET_ITEM,0))==1,"resend of the claim %s: stored receipt, still one kit"%rid)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"second claim (new request)",false,true)
	sr_deny("build",Vector2i(30,18),SR.BASKET_KIND,S.REJECT_MESSAGE,"build the basket in 北門")
	var rec:=canon_bytes(world.state[SR.STATE_KEY])
	ex_reload("after the basket claim (in 北門)")
	if failed:return
	sr_check(canon_bytes(world.state[SR.STATE_KEY])==rec and typeof(world.state[SR.STATE_KEY].day)==TYPE_INT and typeof(world.state[SR.STATE_KEY].done_day)==TYPE_INT,"revisit record identical after reload (day/done_day int)")
	sr_check(world.player_region(tok)==SR.REGION and int(bag().get(SR.BASKET_ITEM,0))==1,"A still in 北門 with one kit after reload")
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"claim after the reload",true,true)

## Home: the basket is a keepsake, not currency; build / move / remove / build.
func sr_basket_home() -> void:
	travel(SR.STOP,"home")
	if failed:return
	var kit:=SR.BASKET_ITEM
	sr_check(not World.trade_items().has(kit) and World.NAMES.get(kit,"")==SR.BASKET_NAME and World.BUILD[SR.BASKET_KIND].get(kit)==1,"basket kit excluded from trade items; build kind costs one kit")
	sr_deny("sell",RECEIVER,kit,"這件商品尚未上架","小栗 refuses to buy the basket kit")
	sr_deny("ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[[kit,1]],10]),"出貨項目重複或無法出售。","shipping bin refuses the basket kit")
	sr_deny("market_stock",World.MARKET.cell_for(world.state),kit+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%SR.BASKET_NAME,"market stall refuses the basket kit")
	var spot:=Vector2i(-1,-1)
	for tile:Vector2i in SR_BASKET_SPOTS:
		if ex_free(tile):
			spot=tile
			break
	if spot==Vector2i(-1,-1):spot=open_cell()
	if not sr_check(spot!=Vector2i(-1,-1),"free home cell for the basket %s"%str(spot)):return
	var before:=bag().duplicate(true)
	act("build",spot,SR.BASKET_KIND)
	if failed:return
	sr_check(int(bag().get(kit,0))==int(before.get(kit,0))-1,"build debits the kit")
	sr_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":SR.BASKET_KIND,"owner":tok,"items":{}}) and not world.blocked(spot),"鹽籃 placed at %s, walk-through"%str(spot))
	var dest:=Vector2i(-1,-1)
	for off:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1)]:
		var c:=spot+off
		if ex_free(c) and sr_dist(c)<=3.0:
			dest=c
			break
	if not sr_check(dest!=Vector2i(-1,-1),"free cell beside the basket within reach"):return
	sr_deny("build",dest,SR.BASKET_KIND,"材料不足，需要%s 1"%SR.BASKET_NAME,"second basket without a kit (free cell %s)"%str(dest),false)
	act("move_object",spot,"%d,%d"%[dest.x,dest.y])
	if failed:return
	sr_check(world.state.objects.has(World.key(dest)) and not world.state.objects.has(World.key(spot)) and str(world.state.objects[World.key(dest)].type)==SR.BASKET_KIND,"basket moved %s -> %s"%[str(spot),str(dest)])
	act("remove",dest)
	if failed:return
	sr_check(int(bag().get(kit,0))==1 and not world.state.objects.has(World.key(dest)),"remove returns the kit")
	act("build",spot,SR.BASKET_KIND)
	if failed:return
	sr_check(int(bag().get(kit,0))==0 and str(world.state.objects.get(World.key(spot),{}).get("type",""))==SR.BASKET_KIND,"basket placed again at %s"%str(spot))
	sr_info.basket=[spot.x,spot.y]
	sr_info.basket_moved_to=[dest.x,dest.y]
	ex_reload("after placing the basket at home")
	if failed:return
	sr_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":SR.BASKET_KIND,"owner":tok,"items":{}}),"basket persists after reload")

## The exhibit at the festival plaza (the festival opening was earned by the parents).
func sr_exhibit() -> void:
	var s:=world.state
	sr_check(s.get("festival_story_open")==true,"festival opened by the earned parent steps")
	var stand:=ME.stand_cell(s)
	walk_to(stand)
	s=world.state
	var rv:Dictionary=sr_info.revisit
	var row:=ME.exhibit(s,"beimen",tok)
	sr_check(row.on_display==true and row.unread==true and row.seen==false and str(row.source)==SR.BASKET_SOURCE and str(row.project)==SR.BASKET_PROJECT and str(row.blurb)==SR.BASKET_BLURB and str(row.disclaimer)==SR.DISCLAIMER,"鹽籃 slot on display and unread %s"%JSON.stringify(row))
	# Independent counts from the action logs.
	var sunny:=0
	var cloudy:=0
	for st:Dictionary in sr_stocks:
		if str(st.weather)=="sunny":sunny+=1
		elif str(st.weather)=="cloudy":cloudy+=1
	var kitchen:=0
	var pickle:=0
	var rain:=0
	for pk:Dictionary in sr_packs:
		if str(pk.kind)=="kitchen":kitchen+=1
		else:pickle+=1
		if pk.rain==true:rain+=1
	sr_check(sunny==4 and cloudy==2 and kitchen==2 and pickle==4 and rain==4,"action log: lots sunny %d cloudy %d, baskets kitchen %d pickle %d, rainy packs %d"%[sunny,cloudy,kitchen,pickle,rain])
	var recap:=ME.recap_for(s,"beimen")
	var season:=str(rv.season)
	var season_label:=str(WEATHER.SEASON_LABELS[season])+"季"
	var weather:=str(rv.weather_done_day)
	sr_check(int(recap.day)==int(rv.done_day) and int(recap.order_day)==int(rv.order_day) and str(recap.season)==season and same_canon(recap.order,SR_ORDER_TABLE[season]) and int(recap.sunny)==sunny and int(recap.cloudy)==cloudy and int(recap.kitchen)==kitchen and int(recap.pickle)==pickle and int(recap.rain_packs)==rain and str(recap.weather)==weather,"recap matches what happened %s"%JSON.stringify(recap))
	sr_check(str(recap.reason)==SR.reason_for(season) and str(recap.weather_label)==str(WEATHER.LABELS[weather]) and str(recap.season_label)==season_label,"recap reason / labels")
	sr_check(int(rv.order_day)==int(sr_packs[0].day) and str(sr_packs[0].weather)=="rainy" and int(rv.done_day)==int(sr_info.last_day.day),"order day = first pack day %d (rainy), send day %d"%[int(rv.order_day),int(rv.done_day)])
	var lines:Array=row.lines
	var want:=[SR.BASKET_BLURB,SR.BASKET_SOURCE,SR.BASKET_PROJECT,
		"完成那天：第 %d 日・北門%s"%[int(rv.done_day),str(WEATHER.LABELS[weather])],
		"%s的訂單：料理用 %d 籃／醃漬用 %d 籃"%[season_label,kitchen,pickle],
		"入倉的散鹽：晴天 %d 批、多雲 %d 批；雨天裝籃 %d 籃"%[sunny,cloudy,rain],
		SR.DISCLAIMER]
	sr_check(lines==want,"exhibit lines %s"%JSON.stringify(lines))
	var pages:=ME.recap_pages("beimen",s)
	var p_ok:=pages.size()==4
	if p_ok:
		var order:Dictionary=SR_ORDER_TABLE[season]
		p_ok=str(pages[0].lines[1])=="那張訂單是%s開的，%s"%[season_label,SR.reason_for(season)] \
			and str(pages[1].lines[0])=="第 %d 日裝下第一籃，照的是%s的訂單。"%[int(rv.order_day),season_label] \
			and str(pages[1].lines[1])=="一共 6 籃：料理用 %d 籃、醃漬用 %d 籃。"%[int(order.kitchen),int(order.pickle)] \
			and str(pages[2].lines[0])=="一批散鹽是 3 份海鹽，交給阿曬入倉：晴天入倉 %d 批、多雲入倉 %d 批；下雨天倉棚不收散鹽。"%[sunny,cloudy] \
			and str(pages[2].lines[1])=="在合作社收鹽箱旁裝了料理用 %d 籃、醃漬用 %d 籃；其中 %d 籃是在下雨天、倉棚不收散鹽的日子裝的。"%[kitchen,pickle,rain] \
			and str(pages[2].lines[2])=="第 %d 日・北門%s，在海邊公車站送出，鹽籃批次就完成了。"%[int(rv.done_day),str(WEATHER.LABELS[weather])] \
			and str(pages[2].lines[3])=="展台沒有記錄是誰入倉、誰裝籃、誰送出。" \
			and str(pages[3].lines[0])==SR.BASKET_BLURB and str(pages[3].lines[-1])==SR.DISCLAIMER
	sr_check(p_ok,"4 recap pages %s"%JSON.stringify(pages).left(900))
	var all_text:=JSON.stringify(pages)+JSON.stringify(lines)
	sr_check(not all_text.contains("1818") and not all_text.contains("井仔腳") and not all_text.contains(TOKEN_A),"pages carry no history text and no token")
	sr_check(ME.view_block(s,"beimen",tok)=="","view allowed")
	var me:=ME.personal(s,tok)
	sr_check(me.seen==["lanyang","jinguashi","tea_pottery"] and int(me.unread)==1 and me.raking_done==true and me.basket_claimed==true and str(me.basket_hint)==ME.HINT_SALT_CLAIMED,"A personal before viewing %s"%JSON.stringify(me))
	var others:={}
	for id:String in ["lanyang","jinguashi","tea_pottery"]:others[id]={"row":ME.exhibit(s,id,""),"pages":ME.recap_pages(id,s)}
	ex_view_ok(stand,"beimen","A views the salt basket")
	if failed:return
	sr_check(same_canon(person().get(ME.RECORD_KEY),{"seen":["lanyang","jinguashi","tea_pottery","beimen"]}),"A's record {seen:[lanyang, jinguashi, tea_pottery, beimen]}")
	sr_deny(ME.VIEW_ACTION,stand,"beimen",ME.ALREADY_SEEN,"A views the salt basket again",false)
	sr_check(ME.own(world.state,tok)=={"seen":["lanyang","jinguashi","tea_pottery","beimen"],"first_share_done":true,"plaque_claimed":true,"sorting_done":true,"lantern_claimed":true,"comparison_done":true,"teaware_claimed":true,"raking_done":true,"basket_claimed":true},"own block for A")
	sr_check(int(ME.personal(world.state,tok).unread)==0 and ME.on_display_ids(world.state)==["lanyang","jinguashi","tea_pottery","beimen"],"A has nothing unread; all four exhibits on display")
	for id:String in others:
		sr_check(same_canon(ME.exhibit(world.state,id,""),others[id].row) and same_canon(ME.recap_pages(id,world.state),others[id].pages),"%s row and pages unchanged by the salt story view"%id)

## Brand-new islander C: never raked, cannot reach 北門 yet.
func sr_late_c() -> void:
	var stand:=ME.stand_cell(world.state)
	sr_check(not world.state.players.has(SR_C),"C not in the save yet")
	world.add_player(SR_C,SR_C_NAME)
	var a_bytes:=canon_bytes(world.state.players[TOKEN_A])
	var a_salt:=canon_bytes(world.state.salt_pan.players[TOKEN_A])
	var rec_bytes:=canon_bytes(world.state[SR.STATE_KEY])
	tok=SR_C
	sr_check(world.player_region(tok)=="home" and not person().has(ME.RECORD_KEY) and not SR.player_ready(world.state,tok) and not (world.state.salt_pan.players as Dictionary).has(tok),"C joined at home, no exhibit or salt record")
	walk_to(stand)
	var s:=world.state
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_NOT_READY,"C sees the 補做 hint")
	sr_blocks_all(SR.NOT_READY,"C")
	var row:=ME.exhibit(s,"beimen",tok)
	sr_check(row.on_display==true and row.unread==true and row.lines.size()==7 and ME.recap_pages("beimen",s).size()==4 and int(ME.personal(s,tok).unread)==4,"C sees the salt basket on display, unread, 4 pages (4 unread in total)")
	ex_view_ok(stand,"beimen","C views the salt basket")
	if failed:return
	var me:=ME.personal(world.state,tok)
	sr_check(me.seen==["beimen"] and str(me.basket_hint)==ME.HINT_SALT_NOT_READY and me.raking_done==false and me.basket_claimed==false,"C seen [beimen], hint still NOT_READY %s"%JSON.stringify(me))
	sr_check(not travel_has("home",FERRY,SR.REGION),"北門 is not offered to C at the ferry")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.WRONG_REGION,"C stocks from home",false)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"kitchen",SR.WRONG_REGION,"C packs from home",false)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.WRONG_REGION,"C sends from home",false)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"C claims from home",false)
	sr_check(canon_bytes(world.state.players[TOKEN_A])==a_bytes and canon_bytes(world.state.salt_pan.players[TOKEN_A])==a_salt,"A's player and salt records byte-identical through C's leg")
	sr_check(canon_bytes(world.state[SR.STATE_KEY])==rec_bytes and not SR.claimed_own(world.state,tok),"revisit record byte-identical; C has no basket")
	tok=TOKEN_A

## Flower late joiner B: closed the last gate in the chain, never raked, still in 北門.
## Rejoins (World.add_player), is refused NOT_READY at every point, then catches up with
## one hand rake and claims a basket.
func sr_rejoin_b() -> void:
	tok=TOKEN_B
	sr_check(world.player_region(tok)==SR.REGION and int(S.own_record(world.state,tok).raked)==0 and not SR.player_ready(world.state,tok),"B is in 北門 and never raked")
	world.add_player(TOKEN_B,str(world.state.players[TOKEN_B].name))
	var a_bytes:=canon_bytes(world.state.players[TOKEN_A])
	var a_salt:=canon_bytes(world.state.salt_pan.players[TOKEN_A])
	var rec_bytes:=canon_bytes(world.state[SR.STATE_KEY])
	var s:=world.state
	sr_check(ME.personal_hint_for(s,"beimen",tok)==ME.HINT_SALT_NOT_READY,"B: hint NOT_READY")
	sr_blocks_all(SR.NOT_READY,"B")
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.NOT_READY,"B stocks at 阿曬 without raking",true,true)
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_READY,"B claims at 阿曬 without raking",false,true)
	sr_deny(SR.PACK_ACTION,SR.CHEST,"pickle",SR.NOT_READY,"B packs at the chest without raking",true,true)
	sr_deny(SR.SEND_ACTION,SR.STOP,"",SR.NOT_READY,"B sends at the stop without raking",true,true)
	sr_check(canon_bytes(world.state.players[TOKEN_A])==a_bytes and canon_bytes(world.state.salt_pan.players[TOKEN_A])==a_salt and canon_bytes(world.state[SR.STATE_KEY])==rec_bytes,"A's records and the revisit record byte-identical through B's refusals")
	# Catch-up: one hand rake on the public pool.
	var t0:=now()
	var raked:=int(S.own_record(world.state,tok).raked)
	if not sr_salt_until(int(bag().get("sea_salt",0))+3,now()+3.0*WEATHER.DAY_SECONDS):return
	sr_check(int(S.own_record(world.state,tok).raked)>=raked+1 and SR.player_ready(world.state,tok),"B raked by hand and is ready")
	sr_check(ME.personal_hint_for(world.state,"beimen",tok)==ME.HINT_SALT_UNCLAIMED,"B: hint UNCLAIMED after the catch-up rake")
	sr_info.b_catch_up={"world_seconds":now()-t0,"day":SR.today(world.state)}
	sr_deny(SR.STOCK_ACTION,SR.WORKER,"",SR.ALREADY_DONE,"B stocks after completion",true,true)
	sr_ok(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIM_OK,"B claims a salt basket",["state.%s.claimed"%SR.STATE_KEY,"state.players.%s.inventory.%s"%[tok,SR.BASKET_ITEM]])
	if failed:return
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"B claims again",false,true)
	sr_check(canon_bytes(world.state.players[TOKEN_A])==a_bytes and canon_bytes(world.state.salt_pan.players[TOKEN_A])==a_salt,"A's player and salt records byte-identical through B's whole leg")
	var rec:Dictionary=world.state[SR.STATE_KEY]
	sr_check((rec.claimed as Dictionary).size()==2 and rec.claimed.has(TOKEN_A) and rec.claimed.has(TOKEN_B) and int(rec.done_day)==int(sr_info.revisit.done_day) and same_canon(SR.public(world.state),SR.public(sr_from_bytes(rec_bytes))),"revisit public fields unchanged; claimed = {A, B}")
	tok=TOKEN_A

func sr_from_bytes(bytes:PackedByteArray) -> Dictionary:
	return {SR.STATE_KEY:bytes_to_var(bytes)}

func sr_final() -> void:
	ex_reload("after the late joiners")
	if failed:return
	tok=SR_C
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"C claims after the final reload",false)
	sr_check(not SR.player_ready(world.state,tok) and ME.personal_hint_for(world.state,"beimen",tok)==ME.HINT_SALT_NOT_READY,"C still not ready after the reload")
	tok=TOKEN_B
	sr_deny(SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"B claims after the final reload",true,true)
	tok=TOKEN_A
	sr_check(SR.claimed_own(world.state,TOKEN_A) and SR.claimed_own(world.state,TOKEN_B) and not SR.claimed_own(world.state,SR_C),"final: A and B claimed, C did not")
	var box:Dictionary=world.state.objects.get(World.key(sr_chest),{}).get("items",{})
	sr_check(canon_bytes(box)==sr_info.stash_box,"the stash chest was never touched again")
	sr_info.erase("stash_box")

# ---------------------------------------------------------------- salt + batch steps

## Rake every public pan that holds salt, flood empty ones on dry days, wait in 60 s
## steps, until the bag holds `target` sea salt. Returns false (and fails) at `deadline`.
func sr_salt_until(target:int,deadline:float) -> bool:
	while not failed:
		sr_rake_ready()
		if int(bag().get("sea_salt",0))>=target:return true
		sr_flood_empty()
		if now()>=deadline:
			sr_check(false,"%s: only %d sea salt by world second %.1f (wanted %d)"%[tok,int(bag().get("sea_salt",0)),deadline,target])
			return false
		wait(minf(60.0,maxf(0.5,deadline-now())))
	return false

func sr_rake_ready() -> void:
	for i:int in SR_PANS:
		if failed:return
		var pan:Dictionary=world.state.salt_pan.pans[i]
		if str(pan.s)!="salt":continue
		var b:=bag().duplicate(true)
		var raked:=int(S.own_record(world.state,tok).raked)
		var flood:Dictionary=sr_floods.get(i,{"by":"earlier in the chain","t":float(pan.t)})
		sact("salt_rake",pan_cell(i))
		if failed:return
		var e:=b.duplicate(true)
		e["sea_salt"]=int(b.get("sea_salt",0))+S.YIELD
		expect_same(bag(),e,"SALT_REVISIT_JOURNEY: %s rakes pan %d: whole bag delta sea_salt +%d"%[tok,i,S.YIELD])
		sr_check(int(S.own_record(world.state,tok).raked)==raked+1,"%s raked counter %d -> %d"%[tok,raked,raked+1])
		sr_rakes.append({"who":tok,"pan":i,"day":SR.today(world.state),"weather":SR.weather_today(world.state),"at":snappedf(now(),0.1),"flooded_by":str(flood.get("by","")),"flooded_at":snappedf(float(flood.get("t",0.0)),0.1),"flood_weather":str(flood.get("weather",""))})
		sr_floods.erase(i)

func sr_flood_empty() -> void:
	if raining():return
	for i:int in SR_PANS:
		if failed:return
		var pan:Dictionary=world.state.salt_pan.pans[i]
		if str(pan.s)!="empty" or now()<float(pan.t):continue
		sact("salt_flood",pan_cell(i))
		if failed:return
		sr_floods[i]={"by":tok,"t":now(),"weather":SR.weather_today(world.state)}
		sr_flood_log.append({"who":tok,"pan":i,"day":SR.today(world.state),"weather":SR.weather_today(world.state),"at":snappedf(now(),0.1)})

func sr_next_day() -> void:
	wait(next_midnight()+1.0-now())

func sr_stock() -> void:
	if failed:return
	var s:=world.state
	var n:=SR.stocked_total(s)
	var weather:=SR.weather_today(s)
	var lots0:=SR.stocked(s)
	var packed0:=SR.packed_total(s)
	var b:=bag().duplicate(true)
	var want:=SR.STOCK_OK%[3,str(WEATHER.LABELS[weather]),n+1]
	if n==0:sr_check(want=="阿曬把 3 份海鹽收進倉棚，記成晴天入倉的一批。（已入倉 1／6 批）","STOCK_OK text (first lot, sunny)")
	sr_check(SR.stock_block(s,b,tok)=="","stock_block allows lot %d"%(n+1))
	var rid:=sr_ok(SR.STOCK_ACTION,SR.WORKER,"",want,"stock lot %d (%s)"%[n+1,weather],["state.%s"%SR.STATE_KEY,"state.players.%s.inventory.sea_salt"%tok])
	if failed:return
	consumed_salt+=SR.LOT_SALT
	var e:=b.duplicate(true)
	e["sea_salt"]=int(b.get("sea_salt",0))-SR.LOT_SALT
	expect_same(bag(),e,"SALT_REVISIT_JOURNEY: stock lot %d: whole bag delta exactly sea_salt -3"%(n+1))
	sr_check(SR.stocked_total(world.state)==n+1 and int(SR.stocked(world.state)[weather])==int(lots0[weather])+1 and SR.packed_total(world.state)==packed0,"lot %d recorded as %s"%[n+1,weather])
	if n==0:
		var bytes:=canon_bytes(world.state)
		var again:=world.act(tok,rid,SR.STOCK_ACTION,SR.WORKER,"")
		sr_check(again.ok==true and str(again.message)==want and canon_bytes(world.state)==bytes and SR.stocked_total(world.state)==1,"resend of the first stock %s returns the stored receipt, nothing applied twice"%rid)
		sr_check(same_canon(SR.public(world.state),{"stocked":{"sunny":1 if weather=="sunny" else 0,"cloudy":1 if weather=="cloudy" else 0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0}),"first record %s"%JSON.stringify(SR.public(world.state)))
	sr_stocks.append({"n":n+1,"day":SR.today(world.state),"weather":weather,"at":snappedf(now(),0.1)})

func sr_pack(kind:String) -> void:
	if failed:return
	var s:=world.state
	var done:=SR.packed(s)
	var total:=SR.packed_total(s)
	var rain:=SR.rainy_today(s)
	var rain0:=SR.rain_packs(s)
	var lots0:=SR.stocked(s)
	var b:=bag().duplicate(true)
	done[kind]=int(done[kind])+1
	var want:=SR.PACK_OK%[str(SR.KIND_NAMES[kind]),total+1,int(done.kitchen),int(done.pickle)]
	if rain:want+=SR.PACK_RAIN_NOTE
	sr_check(SR.pack_block(s,kind,b,tok)=="","pack_block allows basket %d (%s)"%[total+1,kind])
	var rid:=sr_ok(SR.PACK_ACTION,SR.CHEST,kind,want,"pack basket %d (%s%s)"%[total+1,kind,", rain" if rain else ""],["state.%s"%SR.STATE_KEY,"state.players.%s.inventory.fiber"%tok])
	if failed:return
	var e:=b.duplicate(true)
	e["fiber"]=int(b.get("fiber",0))-SR.FIBER_PER_BASKET
	expect_same(bag(),e,"SALT_REVISIT_JOURNEY: pack %d: whole bag delta exactly fiber -2"%(total+1))
	sr_check(same_canon(SR.packed(world.state),done) and SR.rain_packs(world.state)==rain0+(1 if rain else 0) and SR.stocked(world.state)==lots0,"packed %s, rain_packs %d"%[JSON.stringify(done),SR.rain_packs(world.state)])
	if total==0:
		var bytes:=canon_bytes(world.state)
		var again:=world.act(tok,rid,SR.PACK_ACTION,SR.CHEST,kind)
		sr_check(again.ok==true and str(again.message)==want and canon_bytes(world.state)==bytes and SR.packed_total(world.state)==1,"resend of the first pack %s returns the stored receipt, nothing applied twice"%rid)
	sr_packs.append({"n":total+1,"kind":kind,"day":SR.today(world.state),"weather":SR.weather_today(world.state),"rain":rain,"at":snappedf(now(),0.1)})

# ---------------------------------------------------------------- report

func finish() -> void:
	if sr_started:
		var earned:=0
		for r:Dictionary in sr_rakes:
			if str(r.who)==TOKEN_A:earned+=S.YIELD
		sr_info.salt_raked_by_a=earned
		sr_info.fiber_gathered=2*sr_trees.filter(func(t):return str(t.label).begins_with("fiber")).size()
		print("SALT_REVISIT_JOURNEY info=%s"%JSON.stringify(sr_info))
		for r in sr_flood_log:print("SALT_REVISIT_JOURNEY flood %s"%JSON.stringify(r))
		for r in sr_rakes:print("SALT_REVISIT_JOURNEY rake %s"%JSON.stringify(r))
		for r in sr_trees:print("SALT_REVISIT_JOURNEY tree %s"%JSON.stringify(r))
		for r in sr_stocks:print("SALT_REVISIT_JOURNEY stock %s"%JSON.stringify(r))
		for r in sr_packs:print("SALT_REVISIT_JOURNEY pack %s"%JSON.stringify(r))
	for i in sr_refusals.size():print("SALT_REVISIT_JOURNEY refusal %d %s"%[i+1,sr_refusals[i]])
	if sr_started:
		var t:=float(world.state.get("time",0.0))
		var order:Dictionary=sr_info.get("revisit",{})
		print("SALT_REVISIT_JOURNEY stats actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f refusals=%d all_refusals_state_unchanged=%s order_day=%s order_season=%s send_day=%s segment_reloads=%d segment_checks=%d segment_ms=%d passed=%s"%[actions,walking,t,actions-sr_actions_start,walking-sr_walk_start,t-sr_time_start,sr_refusals.size(),str(sr_changed==0),str(order.get("order_day","?")),str(order.get("season","?")),str(order.get("done_day","?")),ex_reloads-sr_reloads_start,checks-sr_checks_start,Time.get_ticks_msec()-sr_ms,str(not failed)])
	else:
		print("SALT_REVISIT_JOURNEY did not reach the revisit segment (refusals so far %d, fresh=%s locked=%s not_ready=%s)"%[sr_refusals.size(),str(sr_fresh_done),str(sr_locked_done),str(sr_notready_done)])
	super.finish()

# ---------------------------------------------------------------- helpers

func sr_check(condition:bool,message:String) -> bool:
	return expect(condition,"SALT_REVISIT_JOURNEY: "+message)

func sr_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func sr_held(items:Array=["sea_salt","fiber","wood","salt_basket_kit"]) -> Dictionary:
	var out:={}
	for item in items:out[item]=int(bag().get(item,0))
	return out

## Refused with the exact message; whole World.state unchanged (== and sorted bytes).
## pure: the position-independent *_block function for this action must say the same.
func sr_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true,pure:=false) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	if pure:
		var s:=world.state
		var block:="?"
		if action==SR.STOCK_ACTION:block=SR.stock_block(s,bag(),tok)
		elif action==SR.PACK_ACTION:block=SR.pack_block(s,extra,bag(),tok)
		elif action==SR.SEND_ACTION:block=SR.send_block(s,tok)
		elif action==SR.CLAIM_ACTION:block=SR.claim_block(s,bag(),tok)
		sr_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"sr-journey-%d"%actions,action,target,extra)
	sr_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	sr_check(unchanged,label+": whole world state unchanged")
	if not unchanged:sr_changed+=1
	sr_refusals.append("%s | %s %s %s | %s | day %d %s | state_unchanged=%s"%[label,action,str(target),extra,str(result.message),SR.today(world.state),SR.weather_today(world.state),str(unchanged)])

## A successful action with the exact message; the whole canonical state may differ
## only under `allowed` (plus the actor's receipts and the commit counter).
func sr_ok(action:String,target:Vector2i,extra:String,message:String,label:String,allowed:Array) -> String:
	if failed:return ""
	walk_to(target)
	if failed:return ""
	actions+=1
	var rid:="sr-journey-%d"%actions
	var before:Variant=ex_canon(world.state)
	var result:=world.act(tok,rid,action,target,extra)
	sr_check(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var diffs:=[]
	ex_all_diffs(before,ex_canon(world.state),"state",diffs)
	var prefixes:=allowed.duplicate()
	prefixes.append("state.players.%s.receipts"%tok)
	prefixes.append("state.committed")
	prefixes.append("state.ledger")
	var other:=[]
	for row in diffs:
		var ok:=false
		for prefix:String in prefixes:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):ok=true
		if not ok:other.append(row)
	sr_check(other.is_empty() and not diffs.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(allowed),JSON.stringify(other.slice(0,5))])
	return rid
