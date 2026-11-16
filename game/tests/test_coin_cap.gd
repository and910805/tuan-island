extends SceneTree
## T093 coin cap: the seed-stall sell, claim_milestone and the wind-chime festival
## finish never push a player's coins above Shipping.MAX_COINS, which is the most
## save_schema.whole() accepts. Real World objects, isolated temp saves, no network.
##
## Direct state writes in this suite (all intentional fixtures):
## - player.coins (to place the wallet exactly at / around the cap)
## - player.inventory[item] (sell stacks; milestone reward baseline is read, not written)
## - player.collection[category] (milestone progress, which Collections.progress reads)
## - player.x / player.y (standing next to the festival bell, like test_festival.gd)
## - state.picnic / state.board (festival precondition, like test_festival.gd)

const World=preload("res://scripts/world.gd")
const Festival=preload("res://scripts/festival.gd")
const Shipping=preload("res://scripts/shipping.gd")
const Collections=preload("res://scripts/collections.gd")
const Schema=preload("res://scripts/save_schema.gd")
const STALL:=Vector2i(43,29)
const BOARD:=Vector2i(40,29)
const MAX_COINS:int=Shipping.MAX_COINS
const CLAIMED_MSG:="這項里程碑的獎勵已領取"

var w
var checks:=0
var failures:=0
var seq:=0
var dir:=""

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+message)

func act_on(world,who:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	seq+=1
	var result:Dictionary=world.act(who,"coin-cap-%d"%seq,action,p,extra)
	return result

func snap(world) -> PackedByteArray:
	var copy:Dictionary=world.state.duplicate(true)
	return var_to_bytes(copy)

func valid(s:Dictionary) -> bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func coins_of(world,who:String) -> int:
	return int(world.state.players[who].coins)

func count_of(world,who:String,item:String) -> int:
	var inv:Dictionary=world.state.players[who].inventory
	return int(inv.get(item,0))

func _initialize() -> void:
	dir=OS.get_environment("TEMP").path_join("tuantuan-coin-cap-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	expect(DirAccess.make_dir_absolute(dir)==OK,"isolated save directory created at "+dir)
	test_sanity()
	test_seed_stall()
	test_milestones()
	test_festival()
	cleanup()
	print("COIN CAP checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- D. sanity
func test_sanity() -> void:
	expect(not str(World.COIN_CAP_MSG).is_empty(),"World.COIN_CAP_MSG is non-empty")
	expect(Shipping.MAX_COINS==1000000000,"Shipping.MAX_COINS is 1000000000, got %d"%Shipping.MAX_COINS)
	expect(World.SHIPPING.MAX_COINS==Shipping.MAX_COINS,"World.SHIPPING is the same shipping script cap")

# ---------------------------------------------------------------- A. seed stall
func sell(item:String) -> Dictionary:
	return act_on(w,"alice","sell",STALL,item)

## Direct write: coins, the item stack, and the position next to the seed stall
## (act() has a general reach check).
func setup_sale(item:String,coins:int,count:int) -> void:
	near(w,"alice",STALL+Vector2i(0,1))
	w.state.players.alice.coins=coins
	w.state.players.alice.inventory[item]=count

func expect_refused(item:String,coins:int,count:int,label:String) -> void:
	setup_sale(item,coins,count)
	var before:PackedByteArray=snap(w)
	var result:Dictionary=sell(item)
	expect(not result.ok,"%s: sell %s x%d with coins %d must be refused"%[label,item,count,coins])
	expect(str(result.get("message",""))==World.COIN_CAP_MSG,"%s: refusal message is COIN_CAP_MSG, got '%s'"%[label,str(result.get("message",""))])
	expect(coins_of(w,"alice")==coins,"%s: coins unchanged after refused sell (want %d got %d)"%[label,coins,coins_of(w,"alice")])
	expect(count_of(w,"alice",item)==count,"%s: %s stack kept after refused sell (want %d got %d)"%[label,item,count,count_of(w,"alice",item)])
	expect(snap(w)==before,"%s: whole state byte-identical after refused sell"%label)

func expect_sold(item:String,coins:int,count:int,price:int,label:String) -> void:
	setup_sale(item,coins,count)
	var result:Dictionary=sell(item)
	expect(result.ok,"%s: sell %s x%d with coins %d succeeds, got '%s'"%[label,item,count,coins,str(result.get("message",""))])
	expect(coins_of(w,"alice")==coins+count*price,"%s: coins == %d + %d*%d (got %d)"%[label,coins,count,price,coins_of(w,"alice")])
	expect(count_of(w,"alice",item)==0,"%s: %s stack emptied after sale (got %d)"%[label,item,count_of(w,"alice",item)])

func reload_check(label:String) -> void:
	var coins:=coins_of(w,"alice")
	expect(w.save(),"%s: world saves (%s)"%[label,str(w.save_error)])
	var fresh=World.new()
	expect(fresh.load_world(w.save_path),"%s: fresh World loads the save (coins %d)"%[label,coins])
	expect(not fresh.recovered_from_backup,"%s: load used the primary file, not the backup"%label)
	if fresh.state.players.has("alice"):
		expect(int(fresh.state.players.alice.coins)==coins,"%s: reloaded coins == %d (got %s)"%[label,coins,str(fresh.state.players.alice.coins)])
	else:
		expect(false,"%s: reloaded state has player alice"%label)

func sell_cases(item:String,price:int) -> void:
	expect(price>0,"price of %s is positive (%d)"%[item,price])
	# 1. Wallet exactly at the cap, one item.
	expect_refused(item,MAX_COINS,1,item+" at cap")
	# 2. Boundary: one coin above the largest fitting wallet is refused, the exact boundary fills to MAX.
	expect_refused(item,MAX_COINS-2*price+1,2,item+" boundary+1")
	expect_sold(item,MAX_COINS-2*price,2,price,item+" boundary")
	expect(coins_of(w,"alice")==MAX_COINS,"%s boundary: coins land exactly on MAX_COINS (got %d)"%[item,coins_of(w,"alice")])
	# 3. Huge stack from an empty wallet.
	var fits:int=MAX_COINS/price
	expect(fits*price<=MAX_COINS and (fits+1)*price>MAX_COINS,"%s: largest fitting stack %d computed correctly"%[item,fits])
	expect_refused(item,0,fits+1,item+" big stack")
	expect_sold(item,0,fits,price,item+" largest fitting stack")
	# 4. Regression: a normal sale far below the cap pays count*price.
	expect_sold(item,120,3,price,item+" normal sale")

func test_seed_stall() -> void:
	w=World.new()
	w.save_path=dir.path_join("stall.json")
	w.add_player("alice","米")
	expect(w.player_region("alice")=="home","alice starts in the home region where the stall is")
	var radish_price:int=int(World.CROPS.radish.price)
	var carp_price:int=int(World.FISH.carp.price)
	var bread_price:int=int(World.OTHER_SALES.bread)
	# Refused sale, then save + reload: coins stay at the cap and the save is accepted.
	expect_refused("radish",MAX_COINS,1,"radish reload probe refused")
	reload_check("after refused sale at cap")
	# Boundary sale, then save + reload: exactly MAX_COINS is accepted by the validator.
	expect_sold("radish",MAX_COINS-radish_price,1,radish_price,"radish reload probe boundary")
	expect(coins_of(w,"alice")==MAX_COINS,"radish reload probe boundary: coins == MAX_COINS")
	reload_check("after boundary sale to cap")
	# Validator premise, directly and through a tampered file.
	var good_world=World.new()
	expect(good_world.load_world(w.save_path),"saved stall world reloads for validator premise")
	var at_cap:Dictionary=good_world.state.duplicate(true)
	at_cap.players.alice.coins=MAX_COINS
	expect(valid(at_cap),"schema accepts coins == MAX_COINS")
	var over_cap:Dictionary=good_world.state.duplicate(true)
	over_cap.players.alice.coins=MAX_COINS+1
	expect(not valid(over_cap),"schema rejects coins == MAX_COINS+1")
	var text:=FileAccess.get_file_as_string(w.save_path)
	var parser:=JSON.new()
	expect(parser.parse(text)==OK and parser.data is Dictionary,"stall save parses as a JSON dictionary")
	if parser.data is Dictionary:
		var raw:Dictionary=parser.data
		raw.players.alice.coins=MAX_COINS+1
		var tampered:=dir.path_join("tampered.json")
		var file:=FileAccess.open(tampered,FileAccess.WRITE)
		expect(file!=null,"tampered save file opens for writing")
		if file!=null:
			file.store_string(JSON.stringify(raw))
			file.close()
			var refused=World.new()
			expect(not refused.load_world(tampered),"World refuses a save with coins MAX_COINS+1")
		raw.players.alice.coins=MAX_COINS
		var control:=dir.path_join("control.json")
		var control_file:=FileAccess.open(control,FileAccess.WRITE)
		expect(control_file!=null,"control save file opens for writing")
		if control_file!=null:
			control_file.store_string(JSON.stringify(raw))
			control_file.close()
			var accepted=World.new()
			expect(accepted.load_world(control),"World accepts the same save with coins == MAX_COINS")
	# One item from each price table.
	sell_cases("radish",radish_price)
	sell_cases("carp",carp_price)
	sell_cases("bread",bread_price)
	reload_check("after all stall cases")

# ---------------------------------------------------------------- B. milestones
func progress_pool(category:String) -> Array:
	var pool:Array=[]
	if category=="crops":
		pool=World.CROPS.keys()
	elif category=="fish":
		pool=Collections.FISH.keys()
	elif category=="meals":
		for recipe_id in World.RECIPES.keys():
			if Collections.is_meal(str(recipe_id)):pool.append(recipe_id)
	return pool

## Direct write: player.collection[category] gets exactly `target` discoveries.
func reach_target(player:Dictionary,milestone_id:String) -> bool:
	var milestone:Dictionary=Collections.MILESTONES[milestone_id]
	var category:String=str(milestone.category)
	var target:int=int(milestone.target)
	var pool:Array=progress_pool(category)
	if pool.size()<target:return false
	var discovered:Dictionary={}
	for i in range(target):discovered[str(pool[i])]=true
	player.collection[category]=discovered
	return Collections.progress(player,milestone_id)>=target

func test_milestones() -> void:
	w=World.new()
	w.save_path=dir.path_join("milestone.json")
	w.add_player("alice","米")
	expect(not Collections.MILESTONES.is_empty(),"there are milestones to test")
	for milestone_id in Collections.MILESTONES:
		var id:String=str(milestone_id)
		var milestone:Dictionary=Collections.MILESTONES[id]
		var reward:int=int(milestone.coins)
		var player:Dictionary=w.state.players.alice
		expect(reach_target(player,id),"%s: progress written up to target %d in %s"%[id,int(milestone.target),str(milestone.category)])
		# Refused: one coin too many to receive the reward.
		player.coins=MAX_COINS-reward+1
		var inv_before:Dictionary=player.inventory.duplicate(true)
		var before:PackedByteArray=snap(w)
		var refused:Dictionary=act_on(w,"alice","claim_milestone",Vector2i.ZERO,id)
		player=w.state.players.alice
		expect(not refused.ok,"%s: claim refused with coins %d (reward %d)"%[id,MAX_COINS-reward+1,reward])
		expect(str(refused.get("message",""))==World.COIN_CAP_MSG,"%s: refusal is COIN_CAP_MSG, got '%s'"%[id,str(refused.get("message",""))])
		expect(not player.collection.claimed.has(id),"%s: refused claim does not mark the milestone claimed"%id)
		expect(int(player.coins)==MAX_COINS-reward+1,"%s: coins unchanged after refused claim (got %d)"%[id,int(player.coins)])
		expect(player.inventory==inv_before,"%s: inventory unchanged after refused claim"%id)
		expect(snap(w)==before,"%s: whole state byte-identical after refused claim"%id)
		# Boundary: exactly fits, lands on MAX_COINS.
		player.coins=MAX_COINS-reward
		var granted:Dictionary=act_on(w,"alice","claim_milestone",Vector2i.ZERO,id)
		player=w.state.players.alice
		expect(granted.ok,"%s: claim succeeds at coins %d, got '%s'"%[id,MAX_COINS-reward,str(granted.get("message",""))])
		expect(int(player.coins)==MAX_COINS,"%s: coins == MAX_COINS after boundary claim (got %d)"%[id,int(player.coins)])
		expect(player.collection.claimed.has(id),"%s: boundary claim marks the milestone claimed"%id)
		var items:Dictionary=milestone.items
		for item in items:
			var want:int=int(inv_before.get(item,0))+int(items[item])
			expect(int(player.inventory.get(item,0))==want,"%s: reward item %s granted (want %d got %d)"%[id,str(item),want,int(player.inventory.get(item,0))])
		var again:Dictionary=act_on(w,"alice","claim_milestone",Vector2i.ZERO,id)
		expect(not again.ok,"%s: second claim refused"%id)
		expect(str(again.get("message",""))==CLAIMED_MSG,"%s: second claim says already claimed, got '%s'"%[id,str(again.get("message",""))])
		expect(int(w.state.players.alice.coins)==MAX_COINS,"%s: second claim pays nothing"%id)

# ---------------------------------------------------------------- C. festival
func near(world,who:String,cell:Vector2i) -> void:
	world.state.players[who].x=cell.x+0.5
	world.state.players[who].y=cell.y+0.5

func collect(world,who:String) -> Dictionary:
	var f:Dictionary=world.state.festival
	var p:Vector2i=Festival.target(f)
	near(world,who,p)
	return act_on(world,who,"festival_collect",p,Festival.ticket(f))

func test_festival() -> void:
	var path:=dir.path_join("festival.json")
	var fw=World.new()
	fw.save_path=path
	fw.add_player("alice","米")
	fw.add_player("bob","豆")
	fw.state.picnic=true
	fw.state.board=true
	near(fw,"alice",BOARD)
	var started:Dictionary=act_on(fw,"alice","festival_start",BOARD,"0")
	expect(started.ok,"round 1 starts, got '%s'"%str(started.get("message","")))
	for i in range(Festival.GOAL-1):
		var who:String="alice" if i%2==0 else "bob"
		var step_result:Dictionary=collect(fw,who)
		expect(step_result.ok,"round 1 collect #%d by %s, got '%s'"%[i+1,who,str(step_result.get("message",""))])
	expect(int(fw.state.festival.collected)==Festival.GOAL-1 and fw.state.festival.active,"round 1 waits on the final bell (collected %d)"%int(fw.state.festival.collected))
	# Direct write: alice is 5 coins under the cap, bob is far below it.
	fw.state.players.alice.coins=MAX_COINS-5
	fw.state.players.bob.coins=100
	var finish:Dictionary=collect(fw,"bob")
	expect(finish.ok,"final bell completes round 1 even though alice is near the cap, got '%s'"%str(finish.get("message","")))
	expect(not fw.state.festival.active and int(fw.state.festival.collected)==Festival.GOAL,"round 1 finished and inactive")
	var alice_n:int=int(fw.state.festival.contributors.get("alice",0))
	var bob_n:int=int(fw.state.festival.contributors.get("bob",0))
	expect(alice_n+bob_n==Festival.GOAL and alice_n>0 and bob_n>0,"round 1 contributions alice %d + bob %d == GOAL"%[alice_n,bob_n])
	expect(coins_of(fw,"alice")==MAX_COINS,"alice clamped to MAX_COINS (got %d)"%coins_of(fw,"alice"))
	expect(coins_of(fw,"bob")==100+20+2*bob_n,"bob paid 100+20+2*%d (got %d)"%[bob_n,coins_of(fw,"bob")])
	expect(fw.save(),"festival world saves after the clamped finish (%s)"%str(fw.save_error))
	var loaded=World.new()
	expect(loaded.load_world(path),"fresh World loads the festival save with alice at MAX_COINS")
	expect(not loaded.recovered_from_backup,"festival reload used the primary file")
	if not loaded.state.players.has("alice") or not loaded.state.players.has("bob"):
		expect(false,"festival reload keeps both players")
		return
	expect(int(loaded.state.players.alice.coins)==MAX_COINS,"reloaded alice coins == MAX_COINS (got %s)"%str(loaded.state.players.alice.coins))
	expect(int(loaded.state.players.bob.coins)==100+20+2*bob_n,"reloaded bob coins kept (got %s)"%str(loaded.state.players.bob.coins))
	# Round 2 (regression): nobody near the cap, normal pay after the cooldown.
	fw=loaded
	fw.add_player("alice","米")
	fw.add_player("bob","豆")
	near(fw,"alice",BOARD)
	var early:Dictionary=act_on(fw,"alice","festival_start",BOARD,"1")
	expect(not early.ok,"round 2 cannot start during the cooldown")
	expect(fw.step(Festival.COOLDOWN+1.0,true),"world steps past the festival cooldown (%s)"%str(fw.step_error))
	# Direct write: alice back to an ordinary wallet.
	fw.state.players.alice.coins=500
	var alice_before:=coins_of(fw,"alice")
	var bob_before:=coins_of(fw,"bob")
	near(fw,"alice",BOARD)
	var second:Dictionary=act_on(fw,"alice","festival_start",BOARD,"1")
	expect(second.ok,"round 2 starts after cooldown, got '%s'"%str(second.get("message","")))
	for i in range(Festival.GOAL):
		var who2:String="bob" if i%2==0 else "alice"
		var r2:Dictionary=collect(fw,who2)
		expect(r2.ok,"round 2 collect #%d by %s, got '%s'"%[i+1,who2,str(r2.get("message",""))])
	expect(not fw.state.festival.active and int(fw.state.festival.round)==2,"round 2 finished (round %d)"%int(fw.state.festival.round))
	var a2:int=int(fw.state.festival.contributors.get("alice",0))
	var b2:int=int(fw.state.festival.contributors.get("bob",0))
	expect(a2+b2==Festival.GOAL,"round 2 contributions sum to GOAL (%d+%d)"%[a2,b2])
	expect(coins_of(fw,"alice")==alice_before+20+2*a2,"round 2 alice paid %d+20+2*%d (got %d)"%[alice_before,a2,coins_of(fw,"alice")])
	expect(coins_of(fw,"bob")==bob_before+20+2*b2,"round 2 bob paid %d+20+2*%d (got %d)"%[bob_before,b2,coins_of(fw,"bob")])

# ---------------------------------------------------------------- cleanup
func cleanup() -> void:
	var access:=DirAccess.open(dir)
	if access!=null:
		for file_name in access.get_files():
			DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)
