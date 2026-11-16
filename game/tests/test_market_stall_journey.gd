extends "res://tests/test_flower_journey.gd"
## T071 natural market-stall journey (市集攤位): a FRESH single-player World plays
## from a brand-new save to a settled, collected market day.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## One player, one process. Everything goes through World.act (after walking cell
## by cell with World.move_player along passable tiles, inherited walk_to) and
## World.step(dt,true). World time only advances through explicit waits: the
## reused chapter_one() and grow() call World.step directly, this file's wait()
## steps in chunks of at most 240 world seconds. Walking consumes no world time.
##
## Prerequisite (reused parent logic, unmodified): test_flower_journey.chapter_one()
## — chapter one earned on a fresh world (crops, ship, donate, irrigation, stove,
## soup + bread, ferry picnic 渡口野餐). Its act() calls are intercepted here only
## to insert stall refusals right before the picnic action (holding soup).
## SKIPPED on purpose: chapters two to five (not needed for the stall).
##
## Market leg (all via World.act at the stall cell MARKET.cell_for(state)):
##  * radishes grown on the player's own chapter-one plots (seeds from the picnic
##    gift and, when short, bought from 小栗 with earned coins), watered, waited,
##    harvested — exact whole-bag deltas;
##  * one soup cooked at the own stove (2 radish → 2 soup), exact deltas;
##  * stock radish + soup (exact deltas), take one back, restock, open on the
##    current world day; save + in-process reload into a fresh World while the
##    stall is open with stock; continue on the reloaded world; wait past
##    midnight; walk back; collect exactly the revenue computed here from the
##    catalog prices and the published rule (×1.1 / themed ×1.3, integer ceil;
##    1 stall → 8 visitors; themed items first, then by id, one piece per item per
##    round); take the unsold pieces back.
## Refusals (exact message, whole World.state unchanged, bag compared): stock /
## open / collect before the picnic, collect with an empty cashbox, open an empty
## stall, stock seeds and wood, stock more soup than held, act on the wrong cell,
## stock into a full stall (12 pieces), open twice the same day (before and after
## the reload), collect before midnight, and a second collect after the payout.
## NOT preset: this file writes no state field (inventory, coins, flags, market,
## position, time). Prints MARKET_JOURNEY lines and
## MARKET_STALL_JOURNEY_TESTS checks=N failures=M.

const MARKET=preload("res://scripts/market_stall.gd")
const STOVE:=Vector2i(40,34)
const BOARD:=Vector2i(40,29)
## Radishes: 10 for the stall, 2 for one soup, 1 kept to try a full stall.
const STALL_RADISH:=10
const STALL_SOUP:=2
const SPARE_RADISH:=1
const EMPTY_TILL:="錢箱裡還沒有鈴幣，開張營業、換日結算後再來收。"

var pre_picnic_done:=false
var refusals:=0
var revenue:=0
var market_walk_start:=0
var market_time_start:=0.0
var stall:=Vector2i(-1,-1)
var grown:={}
var cooked:={}
var seeds_bought:=0
var started_ms:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("MARKET_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	print("MARKET_JOURNEY label=\"%s\" actions=%d walk_tiles=%d market_walk_tiles=%d world_seconds=%.1f market_world_seconds=%.1f waters=%d reloads=%d refusals=%d seeds_bought=%d grown=%s cooked=%s revenue=%d runtime_ms=%d"%[LABEL,actions,walking,walking-market_walk_start,float(world.state.get("time",0.0)),float(world.state.get("time",0.0))-market_time_start,waters,reloads,refusals,seeds_bought,JSON.stringify(grown),JSON.stringify(cooked),revenue,Time.get_ticks_msec()-started_ms])
	print("MARKET_STALL_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	started_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	expect(not person().has("market") and not MARKET.unlocked(world.state),"fresh world: no stall record, stall locked")
	chapter_one()
	if failed:return
	if not expect(pre_picnic_done,"pre-picnic stall refusals ran"):return
	expect(world.state.picnic==true and MARKET.unlocked(world.state),"picnic done: stall unlocked")
	stall=MARKET.active_cell(world.state)
	if not expect(stall in MARKET.CANDIDATES and stall==World.market_cell(world.state),"active stall cell %s is a candidate"%str(stall)):return
	print("MARKET_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, walk_tiles %d)"%[checks,actions,now(),walking])
	market_walk_start=walking
	market_time_start=now()
	grow_radishes()
	if failed:return
	cook_soup()
	if failed:return
	market_day()

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not pre_picnic_done and not failed:
		pre_picnic_done=true
		pre_picnic()
	return super.act(action,target,extra)

func pre_picnic() -> void:
	var at:=MARKET.cell_for(world.state)
	expect(not world.state.picnic and int(bag().get("soup",0))>=1,"before the picnic: picnic false, holding soup %d"%int(bag().get("soup",0)))
	stall_refuse("market_stock",at,"soup:1",MARKET.LOCKED,"stock soup before the picnic")
	stall_refuse("market_open",at,"",MARKET.LOCKED,"open before the picnic")
	stall_refuse("market_collect",at,"",MARKET.LOCKED,"collect before the picnic")
	expect(not person().has("market"),"no stall record written before the picnic")

# ---------------------------------------------------------------- produce

func own_plots() -> Array:
	var out:=[]
	for k in world.state.crops:
		if str(world.state.crops[k].get("owner",""))==tok:out.append(World.cell(k))
	out.sort()
	return out

func growing_radish() -> int:
	var n:=0
	for c in own_plots():
		if str(world.state.crops[World.key(c)].get("kind",""))=="radish":n+=int(World.CROPS.radish.yield)
	return n

func grow_radishes() -> void:
	var need:=STALL_RADISH+int(World.RECIPES.soup.ingredients.radish)*ceili(float(STALL_SOUP)/float(World.RECIPES.soup.yield))+SPARE_RADISH
	expect(own_plots().size()>=3,"own chapter-one plots: %d"%own_plots().size())
	for pass_index in 8:
		if failed:return
		var short:=need-int(bag().get("radish",0))-growing_radish()
		for c in own_plots():
			if failed or short<=0:break
			if str(world.state.crops[World.key(c)].get("kind",""))!="":continue
			if not expect(World.crop_grows_in_season("radish","home",c,now()),"radish is in season at %.1f"%now()):return
			if int(bag().get("radish_seed",0))<=0:buy_seed("radish")
			var before:=bag().duplicate(true)
			act("seed",c,"radish")
			expect_bag_delta(before,{"radish_seed":-1},"seed radish at %s"%str(c))
			act("water",c)
			waters+=1
			short-=int(World.CROPS.radish.yield)
		var planted:=[]
		for c in own_plots():
			if str(world.state.crops[World.key(c)].get("kind",""))!="":planted.append(c)
		if planted.is_empty():break
		grow(planted)
		for c in planted:
			if failed:return
			var kind:=str(world.state.crops[World.key(c)].kind)
			var before:=bag().duplicate(true)
			act("harvest",c)
			var yield_n:=int(World.CROPS[kind].yield)
			expect_bag_delta(before,{kind:yield_n},"harvest %s at %s"%[kind,str(c)])
			grown[kind]=int(grown.get(kind,0))+yield_n
		if int(bag().get("radish",0))>=need:break
	expect(int(bag().get("radish",0))>=need,"grew radish %d >= %d"%[int(bag().get("radish",0)),need])
	print("MARKET_JOURNEY grown=%s seeds_bought=%d radish=%d time=%.1f"%[JSON.stringify(grown),seeds_bought,int(bag().get("radish",0)),now()])

func buy_seed(kind:String) -> void:
	var price:=int(World.CROPS[kind].seed_price)
	if not expect(int(person().coins)>=price,"earned coins %d cover a %s seed (%d)"%[int(person().coins),kind,price]):return
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	act("buy",RECEIVER,kind)
	expect_bag_delta(before,{kind+"_seed":1},"buy %s seed"%kind)
	expect(int(person().coins)==coins-price,"seed costs exactly %d"%price)
	seeds_bought+=1

func cook_soup() -> void:
	var recipe:Dictionary=World.RECIPES.soup
	var before:=bag().duplicate(true)
	act("cook",STOVE,"soup")
	var delta:={}
	for item in recipe.ingredients:delta[item]=-int(recipe.ingredients[item])
	expect_bag_delta(before,delta,"cook soup debits %s"%JSON.stringify(recipe.ingredients))
	wait(float(recipe.time))
	before=bag().duplicate(true)
	act("claim_cook",STOVE)
	expect_bag_delta(before,{"soup":int(recipe.yield)},"claim soup +%d"%int(recipe.yield))
	cooked["soup"]=int(cooked.get("soup",0))+int(recipe.yield)
	expect(int(bag().get("soup",0))>=STALL_SOUP,"holding soup %d"%int(bag().get("soup",0)))

# ---------------------------------------------------------------- market day

func market_day() -> void:
	var coins_start:=int(person().coins)
	var names:=World.NAMES
	# Empty stall, empty cashbox, non-sellable items, more than held, wrong cell.
	stall_refuse("market_collect",stall,"",EMPTY_TILL,"collect with an empty cashbox")
	stall_refuse("market_open",stall,"","攤位上還沒有東西，先上架再開張。","open an empty stall")
	for item in ["radish_seed","wood"]:
		stall_refuse("market_stock",stall,item+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%str(names[item]),"stock non-sellable "+item)
	var soup_held:=int(bag().get("soup",0))
	stall_refuse("market_stock",stall,"soup:%d"%(soup_held+1),"背包裡的%s不夠，先去收成或料理再來上架。"%str(names.soup),"stock more soup than held")
	stall_refuse("market_stock",stall+Vector2i(1,0),"radish:1",MARKET.WRONG_CELL,"stock on the cell beside the stall")
	if failed:return
	expect(not person().has("market"),"refusals wrote no stall record")
	# Stock: radish in two lots, soup, take one radish back, restock it.
	stock("radish",6)
	stock("soup",STALL_SOUP)
	stock("radish",STALL_RADISH-6)
	take("radish",1)
	stock("radish",1)
	if failed:return
	var expected_stock:={"radish":STALL_RADISH,"soup":STALL_SOUP}
	expect_same(MARKET.record(person()).stock,expected_stock,"stall stock after stocking")
	expect(MARKET.stock_count(expected_stock)==MARKET.MAX_STOCK,"stall holds the max %d pieces"%MARKET.MAX_STOCK)
	stall_refuse("market_stock",stall,"radish:1","攤位已經擺滿 %d 件了，先收回一些再上架。"%MARKET.MAX_STOCK,"stock into a full stall")
	# Open on today's world day.
	var today:=MARKET.day(now())
	var theme:=MARKET.theme_of(today)
	expect(MARKET.visitors_for(1)==8,"one open stall draws 8 visitors")
	var before:=bag().duplicate(true)
	var result:=act("market_open",stall)
	if failed:return
	expect(str(result.message)=="攤位開張了！今天的主題是「%s」，預計有 %d 位客人來逛，換日時結算。"%[str(MARKET.CATEGORY_NAMES[theme]),8],"open message: "+str(result.message))
	expect_same(bag(),before,"opening moves no items")
	var rec:=MARKET.record(person())
	expect(int(rec.open_day)==today and rec.pending==true and int(rec.till)==0,"record open_day=%d pending till=0"%today)
	var view:=world.market_view(tok)
	expect(view.open==true and int(view.stalls_today)==1 and int(view.visitors_estimate)==8 and int(view.stock_count)==MARKET.MAX_STOCK,"view: open, 1 stall, 8 visitors, 12 pieces")
	print("MARKET_JOURNEY opened day=%d theme=%s stock=%s time=%.1f next_midnight=%.1f"%[today,theme,JSON.stringify(rec.stock),now(),next_midnight()])
	stall_refuse("market_open",stall,"","今天已經開張了，明天再來開下一輪。","open twice the same day")
	stall_refuse("market_collect",stall,"",EMPTY_TILL,"collect before midnight")
	if failed:return
	# Save + in-process reload while open with stock; continue on the reloaded world.
	persistence(today)
	if failed:return
	expect(MARKET.day(now())==today,"still day %d after the reload"%today)
	stall_refuse("market_open",stall,"","今天已經開張了，明天再來開下一輪。","reloaded: open twice the same day")
	stall_refuse("market_collect",stall,"",EMPTY_TILL,"reloaded: collect before midnight")
	if failed:return
	# Expected settlement from catalog prices and the published rule.
	var plan:=expected_settlement(expected_stock,today,MARKET.visitors_for(1))
	print("MARKET_JOURNEY expected prices=%s sold=%s left=%s revenue=%d"%[JSON.stringify(plan.prices),JSON.stringify(plan.sold),JSON.stringify(plan.left),int(plan.coins)])
	# Walk away (to the stove), wait past midnight, come back.
	walk_to(STOVE)
	var bag_before_wait:=bag().duplicate(true)
	var coins_before_wait:=int(person().coins)
	var midnight:=next_midnight()
	wait(midnight-now()+1.0)
	if failed:return
	expect(MARKET.day(now())==today+1,"crossed midnight: day %d -> %d"%[today,MARKET.day(now())])
	expect_same(bag(),bag_before_wait,"waiting past midnight changes no backpack item")
	expect(int(person().coins)==coins_before_wait,"settlement does not pay coins directly")
	rec=MARKET.record(person())
	expect(rec.pending==false,"settled: pending false")
	expect_same(rec.stock,plan.left,"unsold pieces remain on the stall")
	expect(int(rec.till)==int(plan.coins) and int(rec.total)==int(plan.coins),"till %d == total %d == expected %d"%[int(rec.till),int(rec.total),int(plan.coins)])
	expect_same(rec.report,{"day":today,"visitors":8,"stalls":1,"theme":theme,"sold":plan.sold,"coins":int(plan.coins)},"settlement report")
	walk_to(stall)
	var coins:=int(person().coins)
	before=bag().duplicate(true)
	result=act("market_collect",stall)
	if failed:return
	revenue=int(person().coins)-coins
	expect(str(result.message)=="從錢箱收下 %d 鈴幣。"%int(plan.coins),"collect message: "+str(result.message))
	expect(revenue==int(plan.coins),"coins +%d == expected revenue %d"%[revenue,int(plan.coins)])
	expect_same(bag(),before,"collecting moves no items")
	expect(int(MARKET.record(person()).till)==0,"cashbox empty after collecting")
	stall_refuse("market_collect",stall,"",EMPTY_TILL,"second collect after the payout")
	for item in plan.left:take(item,int(plan.left[item]))
	if failed:return
	expect(MARKET.record(person()).stock.is_empty(),"all unsold pieces taken back")
	expect(int(person().coins)==coins_start+int(plan.coins),"market leg coins %d == start %d + revenue %d"%[int(person().coins),coins_start,int(plan.coins)])
	print("MARKET_JOURNEY settled day=%d theme=%s sold=%s left=%s revenue=%d coins=%d time=%.1f"%[today,theme,JSON.stringify(plan.sold),JSON.stringify(plan.left),revenue,int(person().coins),now()])

func base_price(item:String) -> int:
	return int(World.CROPS[item].price) if World.CROPS.has(item) else int(World.OTHER_SALES[item])

func ceil_div(a:int,b:int) -> int:
	return (a+b-1)/b

## Independent settlement: themed category first, then by id; one piece of each
## item per round until the visitors or the stock run out.
func expected_settlement(stock_in:Dictionary,day_index:int,visitors:int) -> Dictionary:
	var theme:=MARKET.theme_of(day_index)
	var themed:=[]
	var other:=[]
	var prices:={}
	for item in stock_in:
		var category:=MARKET.category_of(item)
		var base:=base_price(item)
		expect(base==int(MARKET.sale_prices().get(item,-1)),"%s catalog price %d == market price table"%[item,base])
		var price:=ceil_div(base*13,10) if category==theme else ceil_div(base*11,10)
		expect(price==MARKET.price_for(base,category,day_index),"%s price %d (base %d, %s, theme %s)"%[item,price,base,category,theme])
		expect(price==int(world.market_view(tok).prices[item].price),"%s price matches the stall view"%item)
		prices[item]=price
		if category==theme:themed.append(item)
		else:other.append(item)
	themed.sort()
	other.sort()
	var order:=themed+other
	var left:=stock_in.duplicate(true)
	var sold:={}
	var coins:=0
	var remaining:=visitors
	while remaining>0:
		var any:=false
		for item in order:
			if remaining<=0:break
			if int(left.get(item,0))<=0:continue
			left[item]=int(left[item])-1
			sold[item]=int(sold.get(item,0))+1
			coins+=int(prices[item])
			remaining-=1
			any=true
		if not any:break
	for item in left.keys():
		if int(left[item])<=0:left.erase(item)
	return {"prices":prices,"sold":sold,"left":left,"coins":coins}

func persistence(today:int) -> void:
	expect(world.save(),"explicit save while the stall is open")
	var expected:Dictionary=person().duplicate(true)
	var view:=world.market_view(tok)
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,"open-stall save loads in a plain in-process World"):return
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field in ["region","x","y","inventory","coins","market"]:
		expect_same(person().get(field),expected.get(field),"reload: player %s preserved"%field)
	expect_same(world.market_view(tok),view,"reload: stall view preserved")
	var rec:=MARKET.record(person())
	expect(int(rec.open_day)==today and rec.pending==true and MARKET.stock_count(rec.stock)==MARKET.MAX_STOCK,"reload: open on day %d with 12 pieces"%today)
	print("MARKET_JOURNEY reload in-process World.new().load_world stock=%s open_day=%d pending=%s time=%.1f"%[JSON.stringify(rec.stock),int(rec.open_day),str(rec.pending),now()])

# ---------------------------------------------------------------- stall helpers

func stock(item:String,count:int) -> void:
	if failed:return
	var before:=bag().duplicate(true)
	var stock_before:Dictionary=MARKET.record(person()).stock.duplicate(true)
	var result:=act("market_stock",stall,"%s:%d"%[item,count])
	if failed:return
	expect(str(result.message)=="%s ×%d 擺上攤位了。"%[str(World.NAMES[item]),count],"stock message: "+str(result.message))
	expect_bag_delta(before,{item:-count},"stock %s ×%d moves exactly that from the bag"%[item,count])
	stock_before[item]=int(stock_before.get(item,0))+count
	expect_same(MARKET.record(person()).stock,stock_before,"stall stock after stocking %s ×%d"%[item,count])

func take(item:String,count:int) -> void:
	if failed:return
	var before:=bag().duplicate(true)
	var stock_before:Dictionary=MARKET.record(person()).stock.duplicate(true)
	var result:=act("market_take",stall,"%s:%d"%[item,count])
	if failed:return
	expect(str(result.message)=="收回%s ×%d，放回背包了。"%[str(World.NAMES[item]),count],"take message: "+str(result.message))
	expect_bag_delta(before,{item:count},"take %s ×%d returns exactly that to the bag"%[item,count])
	stock_before[item]=int(stock_before.get(item,0))-count
	if int(stock_before[item])<=0:stock_before.erase(item)
	expect_same(MARKET.record(person()).stock,stock_before,"stall stock after taking %s ×%d"%[item,count])

## Exact message, whole World.state unchanged (inherited refuse), bag compared.
func stall_refuse(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	walk_to(target)
	if failed:return
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	var state_before:=world.state.duplicate(true)
	actions+=1
	var result:=world.act(tok,"market-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(world.state==state_before,label+": state unchanged")
	expect_same(bag(),before,label+": backpack unchanged")
	expect(int(person().coins)==coins,label+": coins unchanged")
	refusals+=1

## Whole-bag compare (zero-count stacks ignored on both sides).
func expect_bag_delta(before:Dictionary,delta:Dictionary,label:String) -> void:
	if failed:return
	var expected:={}
	for item in before:expected[str(item)]=int(before[item])
	for item in delta:expected[str(item)]=int(expected.get(str(item),0))+int(delta[item])
	expect_same(nonzero(bag()),nonzero(expected),label)

func nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func now() -> float:
	return float(world.state.time)

func next_midnight() -> float:
	return (WEATHER.day_index(now())+1.0)*WEATHER.DAY_SECONDS

func wait(seconds:float,chunk:float=240.0) -> void:
	var left:=seconds
	while left>0.000001 and not failed:
		var dt:=minf(chunk,left)
		expect(world.step(dt,true),"world step %.1f"%dt)
		left-=dt
