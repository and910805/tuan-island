extends SceneTree
## D03 菜園沙拉: one meal-buff slot + exact 5% mine-strike discount with a twentieth carry.
## Pure World (no scene); works with --headless.
##
##   - Only mine strikes (the one place stamina is spent) are discounted: 19/20 of the base cost for
##     360 world seconds. Buff-less math is bit-identical to the old whole-number rule.
##   - mine_energy stays an integer 0..100; mine_energy_frac (0..19 twentieths) is the hidden carry.
##   - Eating salad at a full bar starts the effect; a different active effect needs the explicit
##     "salad:replace" confirmation; re-eating refreshes, never stacks.
##   - Every refill/restore helper clears or caps the carry; saves round-trip; legacy ginger saves load.

const World=preload("res://scripts/world.gd")
const MB=World.MEAL_BUFF
const Mines=World.MINES
const Schema=preload("res://scripts/save_schema.gd")
const A:="salad-miner"
var checks:=0
var failures:=0
var request:=0
var world:World
var path:=""

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(action:String,cell:Vector2i=Vector2i.ZERO,extra:String="")->Dictionary:
	request+=1
	return world.act(A,"meal-%d"%request,action,cell,extra)

func me()->Dictionary:
	return world.state.players[A]

func fresh(region:String="mine_1")->void:
	world=World.new()
	world.save_path=path
	world.add_player(A,"Salad")
	me().region=region
	me().inventory.merge({"reinforced_pick":1,"salad":6,World.GINGER_TEA:3},true)
	world.state.picnic=true
	world.state.time=1000.0

func at_node(index:int=0)->Vector2i:
	var node:Vector2i=Mines.NODES[index]
	me().x=node.x-0.5
	me().y=node.y+0.5
	world.state.mine_depths.ready={}
	return node

func strike()->Dictionary:
	return act("mine_extract",at_node())

func exact()->int:
	return MB.twentieths(me())

## The stamina/buff/bag facts an action must leave untouched when it is refused.
func facts()->Array:
	var person:=me()
	return [person.mine_energy,person.get(MB.FRAC_FIELD),person.get(MB.FIELD),person.get(MB.LEGACY_GINGER),person.inventory.duplicate()]

func _initialize()->void:
	path=OS.get_environment("TEMP").path_join("meal-buff-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	pure_math()
	strike_costs()
	eating()
	replacement()
	expiry_and_cooldown()
	refill_helpers()
	persistence()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MEAL_BUFF_TESTS checks=%d failures=%d"%[checks,failures])
	quit(failures)

## Exactly 95% of the base cost for every strike cost in the catalog (10..14), no rounding drift.
func pure_math()->void:
	for cost in range(10,15):
		var person:={"mine_energy":1000}
		MB.apply(person,MB.SALAD,0.0)
		var start:=MB.twentieths(person)
		for strike_index in 20:MB.spend(person,cost,1.0)
		expect(start-MB.twentieths(person)==20*19*cost and int(person.get(MB.FRAC_FIELD,0))<20,"20 buffed strikes at cost %d spend exactly 0.95 x %d points"%[cost,20*cost])
		var plain:={"mine_energy":1000}
		for strike_index in 20:MB.spend(plain,cost,1.0)
		expect(MB.twentieths(plain)==1000*20-20*20*cost and not plain.has(MB.FRAC_FIELD),"buff-less strikes spend exactly the base cost at cost %d"%cost)
	var edge:={"mine_energy":10,MB.FRAC_FIELD:10}
	MB.apply(edge,MB.SALAD,0.0)
	expect(MB.twentieths(edge)==190 and MB.exhausts(edge,10,1.0),"boundary: exactly 19/20 of the cost left exhausts")
	edge.mine_energy=10
	edge.erase(MB.FRAC_FIELD)
	expect(not MB.exhausts(edge,10,1.0),"one twentieth above the boundary does not exhaust")
	edge.erase(MB.FIELD)
	edge.mine_energy=10
	expect(MB.exhausts(edge,10,1.0),"without the buff 10 stamina still exhausts a cost-10 strike (old rule)")

func strike_costs()->void:
	fresh()
	var node:=at_node()
	me().mine_energy=100
	var plain:=strike()
	expect(plain.ok and int(me().mine_energy)==90 and not me().has(MB.FRAC_FIELD),"buff-less strike keeps the old whole-number cost: "+str(plain.get("message","")))
	# Buffed: 100 -> 90.5 shown as 91 with 10 twentieths owed -> 81.
	fresh()
	MB.apply(me(),MB.SALAD,world.state.time)
	var first:=strike()
	expect(first.ok and int(me().mine_energy)==91 and int(me()[MB.FRAC_FIELD])==10 and exact()==1810,"first buffed strike: 100 -> 90.5 (shown 91): "+str(first.get("message","")))
	expect("沙拉效果" in str(first.message),"the strike result names the salad effect")
	var second:=strike()
	expect(second.ok and int(me().mine_energy)==81 and not me().has(MB.FRAC_FIELD),"second buffed strike lands on a whole number again")
	# Strike counts from a full refill: 10 without, 11 with the effect (the last pays out and rests).
	for buffed in [false,true]:
		fresh()
		if buffed:MB.apply(me(),MB.SALAD,world.state.time)
		var count:=0
		var rested:=false
		while not rested and count<30:
			var result:=strike()
			expect(result.ok,"strike %d succeeds"%count)
			count+=1
			rested=result.get("mine_exhausted",false)
		expect(count==(11 if buffed else 10) and int(me().mine_energy)==100 and not me().has(MB.FRAC_FIELD),"%s: %d strikes to exhaustion, then a clean refill"%["buffed" if buffed else "plain",count])
		expect(not me().has(MB.FIELD),"Exhaustion clears a salad buff without changing the strike that caused it")
	# Exhaustion boundary through the real action: exactly 190 twentieths left exhausts.
	fresh()
	MB.apply(me(),MB.SALAD,world.state.time)
	me().mine_energy=10
	me()[MB.FRAC_FIELD]=10
	var rest:=strike()
	expect(rest.ok and rest.get("mine_exhausted",false) and int(me().mine_energy)==100 and not me().has(MB.FRAC_FIELD),"boundary strike rests and clears the carry")
	fresh()
	MB.apply(me(),MB.SALAD,world.state.time)
	me().mine_energy=10
	var near:=strike()
	expect(near.ok and not near.get("mine_exhausted",false) and exact()==10,"10 stamina with the effect survives one cost-10 strike with 0.5 left (carry 10)")
	expect(node==Mines.NODES[0],"fixture sanity")
	check_ginger_exhaustion()

func check_ginger_exhaustion()->void:
	for legacy in [false,true]:
		fresh()
		if legacy:me()[MB.LEGACY_GINGER]=world.state.time+80.0
		else:MB.apply(me(),MB.GINGER,world.state.time)
		me().mine_energy=10
		var p:=me()
		var starting_bag:Dictionary=p.inventory.duplicate(true)
		var arrival:=Vector2(Mines.REST)+Vector2(0.5,0.5)
		var exhausted:=strike()
		expect(exhausted.ok and exhausted.get("mine_exhausted",false) and "餐點效果已結束" in str(exhausted.message),"Exhaustion tells the player why the buff ended")
		expect(not p.has(MB.FIELD) and not p.has(MB.LEGACY_GINGER),"Both current and legacy ginger are cleared at rest")
		expect(Vector2(p.x,p.y).distance_to(arrival)<=1.0 and p.mine_energy==100,"Exhaustion returns to the safe rest spot with full stamina")
		for item:String in starting_bag:
			if item!=Mines.ORES[0]:expect(p.inventory[item]==starting_bag[item],"Exhaustion keeps carried item "+item)
		var saved:=World.new()
		expect(saved.load_world(path) and not saved.recovered_from_backup and not saved.state.players[A].has(MB.LEGACY_GINGER),"Reopen preserves the cleared effect")
	fresh()
	MB.apply(me(),MB.GINGER,world.state.time)
	var effect:=MB.read(me(),world.state.time)
	me().mine_energy=20
	me().x=Mines.REST.x+0.5
	me().y=Mines.REST.y+0.5
	expect(act("mine_rest",Mines.REST).ok and me().mine_energy==100 and MB.read(me(),world.state.time)==effect,"Voluntary rest refills without losing the active meal")

func eating()->void:
	fresh()
	me().mine_energy=40
	var ate:=act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad")
	var slot:Dictionary=me().get(MB.FIELD,{})
	expect(ate.ok and int(me().mine_energy)==60 and me().inventory.salad==5,"salad restores 20: "+str(ate.get("message","")))
	expect(slot.get("id")=="salad" and is_equal_approx(float(slot.until)-float(world.state.time),360.0),"the buff lasts exactly 360 world seconds")
	# Capped restore clears the carry.
	fresh()
	me().mine_energy=90
	me()[MB.FRAC_FIELD]=10
	expect(act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad").ok and int(me().mine_energy)==100 and not me().has(MB.FRAC_FIELD),"a capped restore zeroes the carry")
	# Full stamina starts the effect; the second serving is refused and kept.
	fresh()
	me().mine_energy=100
	var full:=act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad")
	expect(full.ok and MB.has(me(),"salad",world.state.time) and me().inventory.salad==5 and int(me().mine_energy)==100,"salad at a full bar starts the effect with 0 restored")
	var again:=act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad")
	expect(not again.ok and me().inventory.salad==5,"re-eating at a full bar with the effect running is refused and keeps the serving")
	# Other dishes still need room.
	me().inventory.soup=1
	expect(not act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"soup").ok and me().inventory.soup==1,"other dishes still refuse at a full bar")
	# Re-eating with room refreshes from now, never stacks past 360 s.
	world.state.time=1100.0
	me().mine_energy=50
	var until_before:=float(me()[MB.FIELD].until)
	expect(act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad").ok and is_equal_approx(float(me()[MB.FIELD].until),1100.0+360.0) and float(me()[MB.FIELD].until)>until_before,"re-eating refreshes to 360 s from now")
	expect(float(me()[MB.FIELD].until)-1100.0<=360.0,"never stacks beyond one duration")
	# Outside a mine and without the item nothing changes.
	me().region=World.REGIONS.HOME
	expect(not act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad").ok,"salad is a mine meal like the other dishes")
	me().region="mine_1"
	me().inventory.salad=0
	me().erase(MB.FIELD)
	expect(not act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad").ok and not me().has(MB.FIELD),"no serving means no effect")
	expect(not act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad:bogus").ok,"unknown confirmation text is refused")

func replacement()->void:
	# Ginger warmth holds the slot; salad must ask first.
	fresh()
	me().mine_energy=50
	MB.apply(me(),MB.GINGER,world.state.time)
	var snapshot:=facts()
	var asked:=act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad")
	expect(not asked.ok and "取代" in str(asked.message) and facts()==snapshot,"salad over ginger warmth asks first and changes nothing")
	var replaced:=act(World.KITCHEN_STOVE.EAT_ACTION,Vector2i.ZERO,"salad:replace")
	expect(replaced.ok and MB.active_id(me(),world.state.time)=="salad" and not me().has(MB.LEGACY_GINGER) and int(me().mine_energy)==70,"explicit confirmation replaces it (one slot, no stacking)")
	expect(not MB.has(me(),"ginger_tea",world.state.time),"ginger warmth is gone while salad holds the slot")
	# Ginger in the highlands over an active salad asks first too.
	fresh(World.WARM_SPRINGS.REGION)
	me().x=29.5
	me().y=26.5
	MB.apply(me(),MB.SALAD,world.state.time)
	snapshot=facts()
	var drink:=act("drink_ginger_tea")
	expect(not drink.ok and facts()==snapshot,"warm ginger tea over salad asks first and consumes nothing")
	var confirmed:=act("drink_ginger_tea",Vector2i.ZERO,MB.CONFIRM)
	expect(confirmed.ok and MB.active_id(me(),world.state.time)=="ginger_tea" and is_equal_approx(float(me()[MB.LEGACY_GINGER])-world.state.time,480.0) and me().inventory[World.GINGER_TEA]==2,"confirmation replaces salad with ginger warmth (480 s, legacy field kept)")
	# Salad's discount is off while ginger holds the slot.
	fresh()
	MB.apply(me(),MB.GINGER,world.state.time)
	var plain:=strike()
	expect(plain.ok and int(me().mine_energy)==90 and not me().has(MB.FRAC_FIELD),"ginger warmth never discounts a strike")
	# Ginger's old confirm-free behaviors are unchanged.
	fresh(World.WARM_SPRINGS.REGION)
	me().x=29.5
	me().y=26.5
	me().mine_energy=100
	expect(act("drink_ginger_tea").ok and not act("drink_ginger_tea").ok and me().inventory[World.GINGER_TEA]==2,"warm ginger: a second cup at full stamina is refused while warm")
	expect(not act("drink_ginger_tea",Vector2i.ZERO,"bogus").ok,"a stray confirmation is refused")

func expiry_and_cooldown()->void:
	fresh()
	var start:=float(world.state.time)
	MB.apply(me(),MB.SALAD,start)
	var until:=start+360.0
	world.state.time=until-0.5
	expect(strike().ok and exact()==1810,"a strike just before expiry is discounted")
	fresh()
	MB.apply(me(),MB.SALAD,start)
	world.state.time=until
	expect(strike().ok and int(me().mine_energy)==90 and not me().has(MB.FIELD),"a strike at the deadline pays full price and the record is dropped")
	# A rejected strike (cooldown) leaves carry and buff untouched.
	fresh()
	MB.apply(me(),MB.SALAD,world.state.time)
	var node:=at_node()
	expect(act("mine_extract",node).ok,"first strike")
	var carry:=facts()
	var blocked:=act("mine_extract",node)
	expect(not blocked.ok and facts()==carry,"a cooldown rejection spends nothing and keeps the buff")
	me().inventory.erase("reinforced_pick")
	world.state.mine_depths.ready={}
	carry=facts()
	expect(not act("mine_extract",node).ok and facts()==carry,"a missing pick rejection spends nothing")
	# Resting through time: the deadline is a world-clock timestamp.
	fresh()
	MB.apply(me(),MB.SALAD,world.state.time)
	expect(world.step(100.0,true) and MB.seconds_left(me(),"salad",world.state.time)==260,"world seconds count the effect down")
	expect(world.step(260.0,true) and MB.read(me(),world.state.time).is_empty(),"the effect expires on the world clock")

func refill_helpers()->void:
	fresh()
	for refill in ["mine_rest"]:
		me()[MB.FRAC_FIELD]=10
		me().mine_energy=50
		me().x=Mines.REST.x-0.5
		me().y=Mines.REST.y+0.5
		expect(act(refill,Mines.REST).ok and int(me().mine_energy)==100 and not me().has(MB.FRAC_FIELD),"%s clears the carry"%refill)
	var person:={"mine_energy":30,MB.FRAC_FIELD:5}
	expect(MB.restore(person,12)==12 and int(person.mine_energy)==42 and int(person[MB.FRAC_FIELD])==5,"a partial restore keeps the carry")
	person.mine_energy=95
	expect(MB.restore(person,12)==6 and int(person.mine_energy)==100 and not person.has(MB.FRAC_FIELD),"a restore that reaches the cap clears the carry and shows the six-point displayed change")
	var half := {"mine_energy": 80, MB.FRAC_FIELD: 10}
	expect(MB.restore(half, 20)==20 and MB.twentieths(half)==1990 and MB.whole_points(half)==99,"a restore to 99.5 does not silently grant extra stamina")
	expect(MB.restore(half, 1)==1 and MB.twentieths(half)==2000 and not half.has(MB.FRAC_FIELD),"a small fractional remainder can be restored to the true cap")
	MB.refill(person)
	expect(int(person.mine_energy)==100 and not person.has(MB.FRAC_FIELD),"refill sets 100 and clears the carry")

func persistence()->void:
	fresh(World.REGIONS.HOME)
	MB.apply(me(),MB.SALAD,world.state.time)
	me().mine_energy=91
	me()[MB.FRAC_FIELD]=10
	expect(world.save(),"save with an active meal buff")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"reload accepts the buff")
	loaded.save_path=path
	var back:Dictionary=loaded.state.players[A]
	expect(back.get(MB.FIELD,{}).get("id")=="salad" and is_equal_approx(float(back[MB.FIELD].until),float(me()[MB.FIELD].until)) and int(back[MB.FRAC_FIELD])==10 and int(back.mine_energy)==91,"effect, deadline and carry survive reload")
	expect(MB.has(back,"salad",float(loaded.state.time)),"the reloaded buff is still active")
	expect(int(loaded.state.version)==Schema.VERSION,"the save stays on the current schema version (no bump)")
	var good:=loaded.state.duplicate(true)
	expect(validate(good),"baseline state validates")
	var cases:={
		"carry 20":func(p):p[MB.FRAC_FIELD]=20,
		"carry -1":func(p):p[MB.FRAC_FIELD]=-1,
		"carry fractional":func(p):p[MB.FRAC_FIELD]=1.5,
		"carry text":func(p):p[MB.FRAC_FIELD]="3",
		"unknown id":func(p):p[MB.FIELD]={"id":"mystery","until":1.0},
		"too far":func(p):p[MB.FIELD]={"id":"salad","until":float(good.time)+361.0},
		"negative":func(p):p[MB.FIELD]={"id":"salad","until":-1.0},
		"extra key":func(p):p[MB.FIELD]={"id":"salad","until":1.0,"stack":2},
		"not a table":func(p):p[MB.FIELD]="salad",
		"missing until":func(p):p[MB.FIELD]={"id":"salad"},
	}
	for label in cases:
		var bad:=good.duplicate(true)
		cases[label].call(bad.players[A])
		expect(not validate(bad),"schema rejects "+label)
	# Legacy saves: no new fields, and ginger-only saves still read as the ginger effect.
	var legacy:=good.duplicate(true)
	legacy.players[A].erase(MB.FIELD)
	legacy.players[A].erase(MB.FRAC_FIELD)
	expect(validate(legacy) and MB.read(legacy.players[A],float(legacy.time)).is_empty(),"a save without the new fields loads unchanged")
	legacy.players[A][MB.LEGACY_GINGER]=float(legacy.time)+200.0
	expect(validate(legacy) and MB.active_id(legacy.players[A],float(legacy.time))=="ginger_tea" and is_equal_approx(World.WARM_SPRINGS.warmth_left(legacy.players[A],float(legacy.time)),200.0),"an old ginger_warm_until save reads as ginger warmth in the slot")
	# A legacy ginger deadline holds the slot too: salad asks first, confirmation leaves exactly one effect.
	var old:Dictionary=loaded.state.players[A]
	old.erase(MB.FIELD)
	old.erase(MB.FRAC_FIELD)
	old[MB.LEGACY_GINGER]=float(loaded.state.time)+200.0
	old.region="mine_1"
	old.inventory.salad=1
	old.mine_energy=50
	var kind:=World.KITCHEN_STOVE.EAT_ACTION
	expect(not loaded.act(A,"legacy-ask",kind,Vector2i.ZERO,"salad").ok and old.inventory.salad==1 and MB.active_id(old,float(loaded.state.time))=="ginger_tea","legacy ginger warmth asks before being replaced")
	expect(loaded.act(A,"legacy-yes",kind,Vector2i.ZERO,"salad:replace").ok and MB.active_id(old,float(loaded.state.time))=="salad" and not old.has(MB.LEGACY_GINGER),"confirmation leaves exactly one effect")

func validate(state:Dictionary)->bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
