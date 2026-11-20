extends SceneTree
## 內容設定集 §11 / D12: limited early sugar at Xiaoli's stall. Pure World (no scene, no UI); works with --headless.
## NOT RUN by the author (no Godot shell here): Codex runs it; a failure is a real finding.
##
## Contract pinned here:
##   - `buy` + extra "sugar" at Xiaoli's stall sells 1 sugar for SUGAR_PRICE (72), at most SUGAR_DAILY (2)
##     per account per world day. The client cannot choose price, quantity or stock.
##   - refusals (sold out, too poor, wrong item/quantity, wrong place) change nothing; coins never go negative.
##   - stock is per account, independent of the flour shelf, survives save / reload, refills on the next world
##     day; old saves (no `sugar_stall` field) validate with a full shelf; malformed rows are rejected.
##   - sugar is not cheaper than farming it (72 > one beet's 66) and never sellable.
##   - untouched: base World.RECIPES.sugar (2 beet -> 2 sugar), the 田尾 market sugar (40, cap 2), flour stall.

const World=preload("res://scripts/world.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const SHOP:=Vector2i(43,29)
const A:="sugar-a"
const B:="sugar-b"

var world:World
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(verb:String,tile:Vector2i,extra:="",who:=A,w:World=null)->Dictionary:
	serial+=1
	var target:World=world if w==null else w
	return target.act(who,"sugar-stall-%d"%serial,verb,tile,extra)

func bag(item:String,who:=A,w:World=null)->int:
	var target:World=world if w==null else w
	return int(target.state.players[who].inventory.get(item,0))

func coins(who:=A,w:World=null)->int:
	var target:World=world if w==null else w
	return int(target.state.players[who].coins)

func put(token:String,at:Vector2,w:World=null)->void:
	var target:World=world if w==null else w
	target.state.players[token].x=at.x
	target.state.players[token].y=at.y

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func left(who:=A,w:World=null)->int:
	var target:World=world if w==null else w
	return World.sugar_left(target.state.players[who],float(target.state.time))

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SUGAR_STALL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	path="user://sugar-stall-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	for who:String in [A,B]:
		world.add_player(who,"糖"+who.right(1))
		world.state.players[who].inventory={"wood":10}
		world.state.players[who].region=World.REGIONS.HOME
	world.state.time=720.0
	put(A,Vector2(43.5,30.2))
	put(B,Vector2(43.5,30.6))

	# ---- numbers and untouched sugar paths ----------------------------------------------------
	expect(World.SUGAR_PRICE==72 and World.SUGAR_DAILY==2,"documented numbers: 72 coins, 2 per day")
	expect(World.SUGAR_PRICE>int(World.CROPS.sugar_beet.price),"stall sugar costs more than one sugar beet (%d)"%int(World.CROPS.sugar_beet.price))
	expect(not World.OTHER_SALES.has("sugar") and not World.CROPS.has("sugar") and not World.FISH.has("sugar"),"sugar still cannot be sold back")
	expect(World.RECIPES.sugar.ingredients=={"sugar_beet":2} and int(World.RECIPES.sugar["yield"])==2,"base sugar recipe is intact (2 beet -> 2 sugar)")
	expect(World.RECIPES.garden_cookie.ingredients=={"flour":1,"sugar":1,"chime_herb":1},"garden_cookie recipe is intact")
	expect(int(Flower.MARKET_PRICES.sugar)==40 and Flower.SUGAR_DAILY==2,"田尾 market sugar is unchanged (40, 2 per day)")
	var cookie_cost:int=World.FLOUR_PRICE+World.SUGAR_PRICE+int(World.CROPS.chime_herb.seed_price)
	expect(cookie_cost>4*int(World.OTHER_SALES.garden_cookie),"stall flour + sugar + herb seed cannot profit from cookies (%d)"%cookie_cost)

	# ---- purchases; old save shape ------------------------------------------------------------
	expect(not world.state.players[A].has("sugar_stall") and left()==2,"an old save (no sugar_stall) starts with a full shelf")
	expect(valid(world.state.duplicate(true)),"fixture: the world validates before any purchase")
	world.state.players[A].coins=71
	var poor:=act("buy",SHOP,"sugar")
	expect(not poor.ok and coins()==71 and bag("sugar")==0 and left()==2 and not world.state.players[A].has("sugar_stall"),"71 coins buy nothing and charge nothing")
	world.state.players[A].coins=72*2+10
	for n in range(1,3):
		var bought:=act("buy",SHOP,"sugar")
		expect(bought.ok and bag("sugar")==n and coins()==72*2+10-72*n and left()==2-n,"purchase %d: 1 sugar for 72, %d left: %s"%[n,2-n,str(bought.get("message",""))])
	expect(coins()==10,"two sugar bought; balance is exactly 10")

	# ---- stock cap and client-supplied numbers -----------------------------------------------
	world.state.players[A].coins=1000
	var sold_out:=act("buy",SHOP,"sugar")
	expect(not sold_out.ok and bag("sugar")==2 and coins()==1000 and left()==0,"the third sugar is refused even with money")
	for extra in ["sugar:3","sugar:-1","sugar:0","Sugar","sugar ","sugar_beet_sugar"]:
		expect(not act("buy",SHOP,extra).ok and bag("sugar")==2 and coins()==1000,"extra '%s' cannot change quantity or price"%extra)
	var far:=act("buy",Vector2i(40,29),"sugar")
	expect(not far.ok and bag("sugar")==2 and coins()==1000,"sugar is only sold at Xiaoli's stall")
	var sell:=act("sell",SHOP,"sugar")
	expect(not sell.ok and bag("sugar")==2 and coins()==1000,"sugar cannot be sold back")
	# flour shelf is independent
	var flour:=act("buy",SHOP,"flour")
	expect(flour.ok and bag("flour")==1 and World.flour_left(world.state.players[A],float(world.state.time))==3 and left()==0,"flour shelf is separate from the sugar shelf")
	# replayed request id sells once; B's shelf is separate
	world.state.players[B].coins=500
	var rid:="sugar-receipt"
	var first:Dictionary=world.act(B,rid,"buy",SHOP,"sugar")
	var replay:Dictionary=world.act(B,rid,"buy",SHOP,"sugar")
	expect(first.ok and replay==first and bag("sugar",B)==1 and coins(B)==428 and left(B)==1,"a replayed request id sells once; B's shelf is separate")
	expect(left()==0,"A's shelf is unaffected by B")
	var history:Array=World.TRANSACTION_LEDGER.shop_history(world.state,A)
	var seen:=false
	for entry:Dictionary in history:
		if entry.action=="buy" and entry.items=={"sugar":1} and int(entry.coins)==-72:seen=true
	expect(seen,"the existing shop history lists the sugar purchase")

	# ---- other players never see someone else's shelf (session privacy strip is covered by key name) --
	expect(World.SAVE_SCHEMA.SUGAR_STALL_KEY=="sugar_stall","stall key is the documented field")

	# ---- reconnect: stock survives save and reload -------------------------------------------
	expect(valid(world.state.duplicate(true)),"the world with a spent shelf validates")
	expect(world.save(),"the world saves")
	var again:=World.new()
	expect(again.load_world(path) and not again.recovered_from_backup,"the world reloads from its primary save")
	again.save_path=path
	expect(left(A,again)==0 and left(B,again)==1 and bag("sugar",A,again)==2,"reload keeps both shelves and the bought sugar")
	again.state.players[A].coins=500
	put(A,Vector2(43.5,30.2),again)
	var after_reload:=act("buy",SHOP,"sugar",A,again)
	expect(not after_reload.ok and bag("sugar",A,again)==2 and coins(A,again)==500,"reloading does not refill the shelf")

	# ---- rollover -----------------------------------------------------------------------------
	again.state.time=float(World.WEATHER.DAY_SECONDS)*1.0
	expect(left(A,again)==2 and left(B,again)==2,"the next world day refills every shelf")
	var fresh_day:=act("buy",SHOP,"sugar",A,again)
	expect(fresh_day.ok and bag("sugar",A,again)==3 and coins(A,again)==428 and left(A,again)==1,"one more sugar on the new day")
	expect(int(again.state.players[A].sugar_stall.day)==1 and int(again.state.players[A].sugar_stall.bought)==1,"stored row is {day 1, bought 1}")
	expect(valid(again.state.duplicate(true)),"the rolled-over world validates")

	# ---- validator rejects malformed rows ----------------------------------------------------
	var good:=again.state.duplicate(true)
	var cases:={}
	var over:=good.duplicate(true);over.players[A].sugar_stall.bought=3;cases["bought above the daily cap"]=over
	var negative:=good.duplicate(true);negative.players[A].sugar_stall.bought=-1;cases["negative bought"]=negative
	var future:=good.duplicate(true);future.players[A].sugar_stall.day=9;cases["a day in the future"]=future
	var half:=good.duplicate(true);half.players[A].sugar_stall.bought=0.5;cases["fractional bought"]=half
	var text:=good.duplicate(true);text.players[A].sugar_stall="2";cases["a text row"]=text
	var extra_key:=good.duplicate(true);extra_key.players[A].sugar_stall.price=1;cases["an extra key"]=extra_key
	var missing:=good.duplicate(true);missing.players[A].sugar_stall.erase("day");missing.players[A].sugar_stall.stock=1;cases["a missing key"]=missing
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	var json_row:=good.duplicate(true)
	json_row.players[A].sugar_stall={"day":1.0,"bought":1.0}
	expect(valid(json_row) and json_row.players[A].sugar_stall.day is int,"JSON-style float counters are accepted and normalised to ints")
	finish()
