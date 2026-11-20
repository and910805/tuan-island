extends SceneTree
## C12/D04 pre-mill flour at Xiaoli's stall. Pure World (no scene, no UI); works with --headless.
## NOT RUN by the author (Claude had no Godot shell here): Codex runs it; a failure is a real finding.
##
## Contract pinned here:
##   - `buy` + extra "flour" at Xiaoli's stall sells 1 flour for FLOUR_PRICE (64), at most FLOUR_DAILY (4)
##     per account per world day, with no mill built. The client cannot choose price, quantity or stock.
##   - refusals (sold out, too poor, wrong item/quantity) change nothing; coins never go negative.
##   - stock is per account, survives save / reload, refills on the next world day, old saves
##     (no `flour_stall` field) validate and start with a full shelf, malformed rows are rejected.
##   - 64 is above the instant bread sale (48) and every market-stall bread price (max 63).
##   - the bought flour is cooked into bread on a real 2x2 C12 kitchen stove (1 flour, 30 s, 1 bread).

const World=preload("res://scripts/world.gd")
const K=World.KITCHEN_STOVE
const SHOP:=Vector2i(43,29)
const HOME:=Vector2i(47,34)
const A:="flour-a"
const B:="flour-b"

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
	return target.act(who,"flour-stall-%d"%serial,verb,tile,extra)

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
	return World.flour_left(target.state.players[who],float(target.state.time))

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FLOUR_STALL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	path="user://flour-stall-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	for who:String in [A,B]:
		world.add_player(who,"麵粉"+who.right(1))
		# FIXTURE: explicit stock, no flour, no mill kit, no mill on the map (wheat is only a control: the C12 bread must not use it).
		world.state.players[who].inventory={"wood":100,"stone":100,"clay":10,"wheat":3}
		world.state.players[who].region=World.REGIONS.HOME
	for x in range(38,51):
		for y in range(33,41):
			var cell:=World.key(Vector2i(x,y))
			world.state.removed[cell]=true
			world.state.objects.erase(cell)
	world.state.time=720.0
	put(A,Vector2(43.5,30.2))
	put(B,Vector2(43.5,30.6))

	# ---- price is above every bread sale loop -------------------------------------------------
	var base:int=World.OTHER_SALES.bread
	var best_market:=0
	for day in range(3):best_market=maxi(best_market,World.MARKET.price_for(base,"dish",day))
	expect(World.FLOUR_PRICE==64 and World.FLOUR_DAILY==4,"documented numbers: 64 coins, 4 per day")
	expect(World.FLOUR_PRICE>base and World.FLOUR_PRICE>best_market,"flour costs more than the instant bread sale (%d) and the best stall price (%d)"%[base,best_market])
	expect(not World.OTHER_SALES.has("flour") and not World.CROPS.has("flour"),"flour itself still cannot be sold back")

	# ---- legitimate purchase before any mill; old save shape ----------------------------------
	expect(not world.state.players[A].has("flour_stall") and left()==4,"an old save (no flour_stall) starts with a full shelf")
	expect(valid(world.state.duplicate(true)),"fixture: the world validates before any purchase")
	for object:Dictionary in world.state.objects.values():expect(object.get("type")!="mill","fixture: there is no mill")
	world.state.players[A].coins=63
	var poor:=act("buy",SHOP,"flour")
	expect(not poor.ok and coins()==63 and bag("flour")==0 and left()==4 and not world.state.players[A].has("flour_stall"),"63 coins buy nothing and charge nothing")
	world.state.players[A].coins=64*4+10
	for n in range(1,5):
		var bought:=act("buy",SHOP,"flour")
		expect(bought.ok and bag("flour")==n and coins()==64*4+10-64*n and left()==4-n,"purchase %d: 1 flour for 64, %d left: %s"%[n,4-n,str(bought.get("message",""))])
	expect(coins()==10 and bag("wheat")==3 and not world.state.players[A].inventory.has("mill_kit"),"4 flour bought without milling; balance is exactly 10")
	# ---- stock cap and client-supplied numbers -------------------------------------------------
	world.state.players[A].coins=1000
	var sold_out:=act("buy",SHOP,"flour")
	expect(not sold_out.ok and bag("flour")==4 and coins()==1000 and left()==0,"the fifth flour is refused: the shelf is empty even with money")
	for extra in ["flour:3","flour:-1","flour:0","Flour","flour "]:
		expect(not act("buy",SHOP,extra).ok and bag("flour")==4 and coins()==1000,"extra '%s' cannot change quantity or price"%extra)
	world.state.players[A].coins=10
	expect(not act("buy",SHOP,"flour").ok and coins()==10 and bag("flour")==4,"sold out and poor: still nothing changes, balance not negative")
	var far:=act("buy",Vector2i(40,29),"flour")
	expect(not far.ok and bag("flour")==4,"flour is only sold at Xiaoli's stall")
	# The receipt of a replayed request never sells twice.
	world.state.players[B].coins=500
	var rid:="flour-receipt"
	var first:Dictionary=world.act(B,rid,"buy",SHOP,"flour")
	var replay:Dictionary=world.act(B,rid,"buy",SHOP,"flour")
	expect(first.ok and replay==first and bag("flour",B)==1 and coins(B)==436 and left(B)==3,"a replayed request id sells once; B's shelf is separate from A's")
	expect(left()==0,"A's shelf is unaffected by B")
	# Ledger records the purchase through the existing shop history.
	var history:Array=World.TRANSACTION_LEDGER.shop_history(world.state,A)
	expect(not history.is_empty() and history[0].action=="buy" and history[0].items=={"flour":1} and int(history[0].coins)==-64,"the existing shop history lists the flour purchase")

	# ---- reconnect: stock survives a save and reload -----------------------------------------
	expect(valid(world.state.duplicate(true)),"the world with a spent shelf validates")
	expect(world.save(),"the world saves")
	var again:=World.new()
	expect(again.load_world(path) and not again.recovered_from_backup,"the world reloads from its primary save")
	again.save_path=path
	expect(left(A,again)==0 and left(B,again)==3 and bag("flour",A,again)==4,"reload keeps both shelves and the bought flour")
	again.state.players[A].coins=500
	put(A,Vector2(43.5,30.2),again)
	var after_reload:=act("buy",SHOP,"flour",A,again)
	expect(not after_reload.ok and bag("flour",A,again)==4 and coins(A,again)==500,"reloading does not refill the shelf")

	# ---- rollover to the next world day -------------------------------------------------------
	again.state.time=float(World.WEATHER.DAY_SECONDS)*1.0
	expect(left(A,again)==4 and left(B,again)==4,"the next world day refills every shelf")
	var fresh_day:=act("buy",SHOP,"flour",A,again)
	expect(fresh_day.ok and bag("flour",A,again)==5 and coins(A,again)==436 and left(A,again)==3,"one more flour on the new day; the row now carries day 1")
	expect(int(again.state.players[A].flour_stall.day)==1 and int(again.state.players[A].flour_stall.bought)==1,"stored row is {day 1, bought 1}")
	expect(valid(again.state.duplicate(true)),"the rolled-over world validates")

	# ---- save validation rejects malformed rows -----------------------------------------------
	var good:=again.state.duplicate(true)
	var cases:={}
	var over:=good.duplicate(true);over.players[A].flour_stall.bought=5;cases["bought above the daily cap"]=over
	var negative:=good.duplicate(true);negative.players[A].flour_stall.bought=-1;cases["negative bought"]=negative
	var future:=good.duplicate(true);future.players[A].flour_stall.day=9;cases["a day in the future"]=future
	var half:=good.duplicate(true);half.players[A].flour_stall.bought=0.5;cases["fractional bought"]=half
	var text:=good.duplicate(true);text.players[A].flour_stall="4";cases["a text row"]=text
	var extra_key:=good.duplicate(true);extra_key.players[A].flour_stall.price=1;cases["an extra key"]=extra_key
	var missing:=good.duplicate(true);missing.players[A].flour_stall.erase("day");missing.players[A].flour_stall.stock=1;cases["a missing key"]=missing
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	var json_row:=good.duplicate(true)
	json_row.players[A].flour_stall={"day":1.0,"bought":1.0}
	expect(valid(json_row) and json_row.players[A].flour_stall.day is int,"JSON-style float counters are accepted and normalised to ints")

	# ---- actual bread on a 2x2 C12 stove from the bought flour ---------------------------------
	var cook:=again
	var cook_id:=A
	put(cook_id,Vector2(46.5,36.4),cook)
	var built:=act("build",HOME,"kitchen_stove",cook_id,cook)
	expect(built.ok and K.KIND=="kitchen_stove","a 2x2 C12 kitchen stove is built: "+str(built.get("message","")))
	var token:String=cook_id
	var flour:=bag("flour",token,cook)
	var wheat:=bag("wheat",token,cook)
	var bread:=bag("bread",token,cook)
	var queued:=act("queue_cook",HOME+Vector2i.ONE,"bread",token,cook)
	expect(queued.ok and bag("flour",token,cook)==flour-1 and bag("wheat",token,cook)==wheat,"bread takes exactly 1 flour and no wheat: "+str(queued.get("message","")))
	var active:Dictionary=cook.state.objects.get(World.key(HOME),{}).get("cooking",{}).get("active",{})
	expect(not active.is_empty() and active.kind=="bread" and float(active.duration)==30.0 and int(active["yield"])==1 and active.ingredients=={"flour":1},"the job is canonical D04: 30 s, 1 flour, 1 bread")
	expect(cook.step(29.0,true) and not act("claim_cook",HOME,"",token,cook).ok and bag("bread",token,cook)==bread,"not ready at 29 s")
	expect(cook.step(2.0,true),"time passes")
	put(token,Vector2(46.5,36.4),cook)
	var claimed:=act("claim_cook",HOME+Vector2i.DOWN,"",token,cook)
	expect(claimed.ok and bag("bread",token,cook)==bread+1 and bag("flour",token,cook)==flour-1,"one bread is claimed from the far side: "+str(claimed.get("message","")))
	expect(not act("claim_cook",HOME,"",token,cook).ok and bag("bread",token,cook)==bread+1,"the bread is not claimed twice")
	expect(coins(token,cook)>=0 and coins(A,cook)==436,"the balance is never negative and the stove cost no coins")
	expect(valid(cook.state.duplicate(true)),"the final world validates")
	finish()
