extends SceneTree
## T071 regression suite for res://scripts/harvest_relay.gd (豐收接力) and its World,
## SaveSchema and Session integration: picnic gate, region/cell/reach gates, stale
## round ids, a full deterministic solo round to GOAL, wrong basket / full hands /
## nobody-to-pass rejections (each leaving the WHOLE world state byte-identical),
## two-player relay bonus, the 8-player cap, leave / rejoin / disconnect / travel
## drops, timeout settlement (also with 0 delivered and offline leavers), exactly-
## once tickets (paid_round), cooldown, inventory + coins equality for every
## participant, save -> reload equality, legacy saves, schema tampering, cell
## terrain/adjacency rules against the real world data and snapshot privacy.
##
## PRESET (written straight into world state, not earned): state.picnic,
## state.time, player positions / regions, inventories, coins, active_tokens
## (to simulate offline players) and, for the schema cases only, tampered copies
## of saved records. Everything else goes through World.act and World.step.
const World=preload("res://scripts/world.gd")
const Harvest=preload("res://scripts/harvest_relay.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Session=preload("res://scripts/session.gd")
const START:=1000.0
const PRIVATE_A:="harvest-private-alpha-token"
const PRIVATE_B:="harvest-private-beta-token"
## Standing spots (player centres) used by the rules tests.
const CRATE_SPOT:=Vector2(31.5,29.0)   # 1.12 from the crate, 1.80 from the sign
const NEAR_CRATE:=Vector2(31.5,30.2)   # 1.20 from CRATE_SPOT (pass partner), 1.04 from the sign
const LOW_SPOT:=Vector2(31.5,33.5)     # 1.0 from the root and the leaf basket
const FRUIT_SPOT:=Vector2(33.5,33.0)   # 1.12 from the fruit and the leaf basket
const FAR_SPOT:=Vector2(39.5,33.5)     # player spawn: far from every activity cell
const VIEW_KEYS:=["active","available","baskets","best","can_start","carry","carry_basket","carry_basket_name","carry_icon","carry_name","carry_relay","cooldown","crate","delivered","goal","joined","joined_count","last","max_players","participants","relays","round","rounds","seconds_left","sign","tickets","unlocked"]
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("HARVEST_RELAY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("harvest-relay-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func stand(w,token:String,at:Vector2)->void:
	var p:Dictionary=pl(w,token)
	p.x=at.x
	p.y=at.y

static func relay_of(w)->Dictionary:
	var r:Variant=w.state.get("harvest_relay")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func entry_of(w,token:String)->Dictionary:
	var e:Variant=relay_of(w).get("participants",{}).get(token)
	if e is Dictionary:
		var copy:Dictionary=e
		return copy
	return {}

static func record_of(w,token:String)->Dictionary:
	var r:Variant=pl(w,token).get("harvest_relay")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.harvest_view(token)
	return v

static func spot_for(basket:String)->Vector2:
	return FRUIT_SPOT if basket=="fruit" else LOW_SPOT

## The other basket reachable from spot_for(right).
static func wrong_for(right:String)->String:
	return {"root":"leaf","leaf":"root","fruit":"leaf"}[right]

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

func act(w,token:String,action:String,cell:Vector2i,extra:String="",request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "harvest-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func ok(w,token:String,action:String,cell:Vector2i,extra:String,label:String)->Dictionary:
	var r:=act(w,token,action,cell,extra)
	expect(bool(r.get("ok",false)),label+" ("+msg(r)+")")
	return r

func write_fixture(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## A rejected action leaves the whole world state byte-identical.
func expect_rejected(w,token:String,action:String,cell:Vector2i,extra:String,label:String,expected:String="")->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	var had_root:bool=w.state.has("harvest_relay")
	var had_record:bool=pl(w,token).has("harvest_relay")
	var r:Dictionary=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself ("+msg(r)+")")
	if not expected.is_empty():expect(msg(r)==expected,label+": message is '%s' (got '%s')"%[expected,msg(r)])
	expect(var_to_bytes(w.state)==before,label+": world state byte-identical")
	expect(w.state.has("harvest_relay")==had_root and pl(w,token).has("harvest_relay")==had_record,label+": no harvest field invented")

## inventory + coins of every token, for before/after equality.
static func bags(w,tokens:Array)->Dictionary:
	var out:={}
	for token:String in tokens:
		out[token]={"inventory":pl(w,token).inventory.duplicate(true),"coins":int(pl(w,token).coins)}
	return out

## A picnic-done world (PRESET) at START with players standing beside the crate.
func make_world(tokens:Array,picnic:bool=true)->World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=START
	for token:String in tokens:
		stand(w,token,CRATE_SPOT)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["radish","carrot","lettuce","tomato","soup"]:inv[item]=5
	return w

## Picks at the crate, walks to the right basket and sorts. Returns the kind.
func pick_and_sort(w,token:String,label:String)->String:
	stand(w,token,CRATE_SPOT)
	var r:=act(w,token,"harvest_pick",Harvest.CRATE)
	expect(bool(r.ok),label+": pick ("+msg(r)+")")
	var kind:=str(entry_of(w,token).get("carry",""))
	var basket:=Harvest.basket_of(kind)
	stand(w,token,spot_for(basket))
	var s:=act(w,token,"harvest_sort",Harvest.BASKETS.get(basket,Vector2i(-1,-1)))
	expect(bool(s.ok),"%s: sort %s into %s (%s)"%[label,kind,basket,msg(s)])
	return kind

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_constants()
	test_cells()
	test_locked()
	test_gates()
	test_solo_round()
	test_two_players()
	test_cap_and_rejoin()
	test_timeout_and_payment()
	test_disconnect_and_travel()
	test_replay()
	test_save_reload_and_schema()
	await test_snapshot_privacy()
	finish()

# 1. Constants, kinds and the deterministic sequence.
func test_constants()->void:
	expect(Harvest.ACTIONS==["harvest_start","harvest_join","harvest_leave","harvest_pick","harvest_pass","harvest_sort"],"Six harvest actions")
	expect(Harvest.GOAL==24 and is_equal_approx(Harvest.DURATION,180.0) and is_equal_approx(Harvest.COOLDOWN,60.0) and Harvest.MAX_PLAYERS==8,"GOAL 24, 180 s, cooldown 60 s, 8 players")
	expect(Harvest.BASKET_NAMES=={"root":"根菜","leaf":"葉菜","fruit":"果菜"} and Harvest.BASKET_ORDER==["root","leaf","fruit"],"Three baskets 根菜/葉菜/果菜")
	expect(Harvest.KINDS.size()==8 and Harvest.ORDER.size()==8,"Eight model vegetables")
	var seen:={}
	for kind:String in Harvest.ORDER:
		expect(Harvest.KINDS.has(kind) and not seen.has(kind),"ORDER entry %s is a unique kind"%kind)
		seen[kind]=true
	for kind:String in Harvest.KINDS:
		var spec:Dictionary=Harvest.KINDS[kind]
		expect(Harvest.BASKETS.has(spec.basket),"%s belongs to a basket"%kind)
		expect(str(spec.name).begins_with("模型"),"%s display name is a model (%s)"%[kind,spec.name])
		expect(World.CROPS.has(spec.icon) and World.NAMES.has(spec.icon),"%s draws with the existing item icon %s"%[kind,spec.icon])
	var roots:=[]
	for kind:String in Harvest.KINDS:
		if Harvest.basket_of(kind)=="root":roots.append(kind)
	roots.sort()
	expect(roots==["carrot","potato","radish"],"根菜 are radish, carrot, potato")
	for round_id in [1,2,3,17]:
		var cycle:={}
		for index in range(8):cycle[Harvest.kind_at(round_id,index)]=true
		expect(cycle.size()==8,"Round %d: every 8 picks show all 8 kinds"%round_id)
		expect(Harvest.kind_at(round_id,3)==Harvest.kind_at(round_id,11),"Round %d sequence repeats every 8"%round_id)
	expect(Harvest.kind_at(1,0)==Harvest.ORDER[5] and Harvest.kind_at(1,1)==Harvest.ORDER[0],"kind_at formula round*5+index*3 mod 8")
	var tickets:={0:1,1:1,7:1,8:2,15:2,16:3,23:3,24:4,100:4}
	for n:int in tickets:expect(Harvest.tickets_for(n)==int(tickets[n]),"tickets_for(%d)==%d"%[n,int(tickets[n])])

## Every fixed home landmark the activity cells must neither stand on nor touch.
static func home_landmarks()->Dictionary:
	var marks:Dictionary={}
	for npc:String in Village.NPCS:
		if str(Village.NPCS[npc].get("region","home"))=="home":marks["npc "+npc]=Village.NPCS[npc].cell
	for npc:String in Village.FESTIVAL_SPOTS:marks["festival spot "+npc]=Village.FESTIVAL_SPOTS[npc]
	for cell:Vector2i in World.Festival.VISITORS:marks["festival visitor "+str(World.Festival.VISITORS[cell])]=cell
	for index in range(World.Festival.STOPS.size()):marks["festival stop %d"%index]=World.Festival.STOPS[index]
	marks["wind-chime tree"]=World.Festival.TREE_CELL
	marks["notice board"]=Vector2i(40,29)
	marks["seed shop"]=Vector2i(43,29)
	marks["chapter starter"]=World.CHAPTER_ONE.STARTER_CELL
	for index in range(World.SHIPPING.CANDIDATES.size()):marks["shipping candidate %d"%index]=World.SHIPPING.CANDIDATES[index]
	for index in range(World.COMMUNITY.CANDIDATES.size()):marks["community table candidate %d"%index]=World.COMMUNITY.CANDIDATES[index]
	for index in range(Market.CANDIDATES.size()):marks["market candidate %d"%index]=Market.CANDIDATES[index]
	for animal:String in World.LIVESTOCK.ANIMALS:
		marks["livestock "+animal]=World.LIVESTOCK.ANIMALS[animal].cell
		marks["livestock collector "+animal]=World.LIVESTOCK.collector_cell(animal)
	for index in range(Bond.RANCH_CELLS.size()):marks["ranch cell %d"%index]=Bond.RANCH_CELLS[index]
	for index in range(Bond.DOCK_CELLS.size()):marks["dock cell %d"%index]=Bond.DOCK_CELLS[index]
	for index in range(Bond.POST_CELLS.size()):marks["post cell %d"%index]=Bond.POST_CELLS[index]
	for index in range(Bond.BELL_CELLS.size()):marks["bell cell %d"%index]=Bond.BELL_CELLS[index]
	var transit:Dictionary=World.TRANSIT.points(World.REGIONS.HOME)
	for point:String in transit:marks["transit "+point]=transit[point].cell
	marks["home exit"]=World.REGIONS.exit_cell(World.REGIONS.HOME)
	marks["home arrival"]=Vector2i(World.REGIONS.spawn(World.REGIONS.HOME))
	marks["player spawn"]=Vector2i(World.SPAWN)
	marks["chicken"]=Vector2i(45,34)
	marks["quarry"]=Vector2i(54,25)
	marks["copper"]=World.COPPER_CELL
	marks["east spawn building lot 40,33"]=Vector2i(40,33)
	marks["east spawn building lot 41,34"]=Vector2i(41,34)
	return marks

# 2. Cell terrain conditions, adjacency, reservation and the occupied fallback.
func test_cells()->void:
	expect(Harvest.SIGN==Vector2i(32,30) and Harvest.CRATE==Vector2i(30,28),"Sign 32,30, crate 30,28")
	expect(Harvest.BASKETS=={"root":Vector2i(30,33),"leaf":Vector2i(32,33),"fruit":Vector2i(34,32)},"Baskets root 30,33 leaf 32,33 fruit 34,32")
	expect(Harvest.CELLS==[Harvest.SIGN,Harvest.CRATE,Vector2i(30,33),Vector2i(32,33),Vector2i(34,32)],"CELLS lists the five cells")
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game plaza (bridge, picnic, festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	var spawn_point:=Vector2(World.SPAWN)
	for cell:Vector2i in Harvest.CELLS:
		var tag:="harvest cell %s"%str(cell)
		for w in [plain,busy]:
			expect(w.is_land(cell) and not w.water(cell),tag+": land, not water")
			expect(w.resource(cell)=="",tag+": no resource (tree/rock/grass) on the cell")
		for spot:Vector2i in [cell,cell+Vector2i.DOWN]:
			var found:=World.base_resource(spot)
			expect(found!="tree" and found!="rock","%s: no fixed tree/rock at %s"%[tag,str(spot)])
		for mark:String in marks:
			var at:Vector2i=marks[mark]
			expect(maxi(absi(cell.x-at.x),absi(cell.y-at.y))>=2,"%s is not on or touching %s %s"%[tag,mark,str(at)])
		for other:Vector2i in Harvest.CELLS:
			if other!=cell:expect(maxi(absi(cell.x-other.x),absi(cell.y-other.y))>=2,"%s does not touch activity cell %s"%[tag,str(other)])
		expect(spawn_point.distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2,tag+": outside interaction range of the spawn point")
		expect(not plain.protected(cell) and not plain.blocked(cell),tag+": ordinary ground before the picnic")
		expect(busy.protected(cell) and busy.blocked(cell),tag+": reserved (protected + blocked) after the picnic")
	for basket:String in Harvest.BASKETS:
		var d:=Vector2(Harvest.BASKETS[basket]).distance_to(Vector2(Harvest.CRATE))
		expect(d>=4.0 and d<=7.0,"%s basket is %.2f tiles from the crate (4..7, passing matters)"%[basket,d])
	# Approach spots used by players (and the session test) are standable and in reach.
	expect(busy.can_stand(CRATE_SPOT) and busy.can_stand(NEAR_CRATE) and busy.can_stand(LOW_SPOT) and busy.can_stand(FRUIT_SPOT),"Approach spots are standable after the picnic")
	expect(CRATE_SPOT.distance_to(Vector2(Harvest.CRATE)+Vector2(0.5,0.5))<=Harvest.HAND_REACH and CRATE_SPOT.distance_to(Vector2(Harvest.SIGN)+Vector2(0.5,0.5))<=Harvest.SIGN_REACH,"Crate spot reaches crate and sign")
	expect(NEAR_CRATE.distance_to(CRATE_SPOT)<=Harvest.PASS_REACH and NEAR_CRATE.distance_to(Vector2(Harvest.SIGN)+Vector2(0.5,0.5))<=Harvest.SIGN_REACH,"Pass partner spot within pass reach and sign reach")
	expect(NEAR_CRATE.distance_to(Vector2(Harvest.CRATE)+Vector2(0.5,0.5))>Harvest.HAND_REACH,"Pass partner spot cannot reach the crate itself")
	for basket:String in Harvest.BASKETS:
		var at:=spot_for(basket)
		expect(at.distance_to(Vector2(Harvest.BASKETS[basket])+Vector2(0.5,0.5))<=Harvest.HAND_REACH,"%s basket reachable from %s"%[basket,str(at)])
		expect(at.distance_to(Vector2(Harvest.CRATE)+Vector2(0.5,0.5))>Harvest.HAND_REACH,"%s basket spot cannot reach the crate"%basket)
	expect(not Harvest.available(plain.state) and Harvest.available(busy.state) and World.harvest_available(busy.state),"available only after the picnic (World.harvest_available wraps)")
	for cell:Vector2i in Market.CANDIDATES:expect(not cell in Harvest.CELLS,"Market candidate %s is not a harvest cell"%str(cell))
	# A pre-picnic build on the crate cell is kept; the activity pauses until cleared.
	var w:=make_world(["bui"],false)
	stand(w,"bui",Vector2(30.5,29.5))
	var built:=act(w,"bui","build",Harvest.CRATE,"lamp")
	expect(bool(built.ok),"Before the picnic a lamp can be built on the crate cell ("+msg(built)+")")
	w.state.picnic=true
	expect(not Harvest.available(w.state) and not w.protected(Harvest.CRATE),"Occupied crate cell: activity unavailable, the lamp cell is not reserved")
	expect(w.protected(Harvest.SIGN) and w.blocked(Harvest.SIGN),"…while the free cells stay reserved")
	# Such a save (picnic done, a build on an activity cell) stays valid on reload.
	var lamp_path:=temp_path("lamp")
	_cleanup.append(lamp_path)
	w.save_path=lamp_path
	expect(w.save(),"Save the world with a lamp on the crate cell")
	var kept:=World.new()
	expect(kept.load_world(lamp_path),"A save with a build on an activity cell loads")
	expect(kept.state.objects.has(World.key(Harvest.CRATE)) and not Harvest.available(kept.state),"The build is kept and the activity stays paused after reload")
	w.save_path=""
	stand(w,"bui",CRATE_SPOT)
	expect_rejected(w,"bui","harvest_start",Harvest.SIGN,"0","Start while the crate cell is occupied",Harvest.UNAVAILABLE)
	expect(not view(w,"bui").available and not view(w,"bui").can_start,"View reports unavailable")
	pl(w,"bui").inventory.wood=20
	stand(w,"bui",Vector2(31.5,30.5))
	expect_rejected(w,"bui","build",Harvest.SIGN,"lamp","Build on the reserved sign cell")
	stand(w,"bui",Vector2(30.5,29.5))
	var removed:=act(w,"bui","remove",Harvest.CRATE)
	expect(bool(removed.ok),"Owner removes the lamp ("+msg(removed)+")")
	expect(Harvest.available(w.state) and w.protected(Harvest.CRATE),"Cleared: activity available and the crate cell reserved again")
	stand(w,"bui",CRATE_SPOT)
	ok(w,"bui","harvest_start",Harvest.SIGN,"0","Start after clearing the cell")

# 3. Picnic gate: every action refused, nothing written.
func test_locked()->void:
	var w:=make_world(["lin"],false)
	var pairs:=[["harvest_start",Harvest.SIGN,"0"],["harvest_join",Harvest.SIGN,"0"],["harvest_leave",Harvest.SIGN,""],["harvest_pick",Harvest.CRATE,""],["harvest_pass",Harvest.CRATE,""],["harvest_sort",Harvest.BASKETS.root,""]]
	for pair:Array in pairs:
		expect_rejected(w,"lin",str(pair[0]),pair[1],str(pair[2]),"Before picnic "+str(pair[0]),Harvest.LOCKED)
	expect(not w.state.has("harvest_relay") and not pl(w,"lin").has("harvest_relay"),"No harvest fields written before the picnic")
	expect(view(w,"lin").unlocked==false and view(w,"lin").available==false,"View says locked")
	expect(Harvest.LOCKED=="完成渡口野餐後，廣場西側的豐收接力才會開放。","Locked message text")

# 4. Region, cell, reach, extra and stale-round gates.
func test_gates()->void:
	var w:=make_world(["gus","hal"])
	var p:Dictionary=pl(w,"gus")
	p.region=World.REGIONS.LANYANG
	for pair:Array in [["harvest_start",Harvest.SIGN,"0"],["harvest_join",Harvest.SIGN,"0"],["harvest_leave",Harvest.SIGN,""],["harvest_pick",Harvest.CRATE,""],["harvest_pass",Harvest.CRATE,""],["harvest_sort",Harvest.BASKETS.root,""]]:
		expect_rejected(w,"gus",str(pair[0]),pair[1],str(pair[2]),"Wrong region "+str(pair[0]),Harvest.WRONG_REGION)
	p.region=World.REGIONS.HOME
	expect_rejected(w,"gus","harvest_start",Harvest.CRATE,"0","Start at the crate",Harvest.WRONG_SIGN)
	expect_rejected(w,"gus","harvest_start",Market.CANDIDATES[0],"0","Start at the market stall",Harvest.WRONG_SIGN)
	expect_rejected(w,"gus","harvest_start",Harvest.SIGN,"1","Stale round id 1 before any round",Harvest.STALE)
	expect_rejected(w,"gus","harvest_start",Harvest.SIGN,"","Empty round id",Harvest.STALE)
	expect_rejected(w,"gus","harvest_start",Harvest.SIGN,"00","Non-canonical round id",Harvest.STALE)
	expect_rejected(w,"gus","harvest_join",Harvest.SIGN,"0","Join with no round",Harvest.NOT_ACTIVE)
	expect_rejected(w,"gus","harvest_leave",Harvest.SIGN,"","Leave with no round",Harvest.NOT_ACTIVE)
	expect_rejected(w,"gus","harvest_pick",Harvest.CRATE,"","Pick with no round",Harvest.NOT_ACTIVE)
	expect_rejected(w,"gus","harvest_pass",Harvest.CRATE,"","Pass with no round",Harvest.NOT_ACTIVE)
	stand(w,"gus",LOW_SPOT)
	expect_rejected(w,"gus","harvest_sort",Harvest.BASKETS.root,"","Sort with no round",Harvest.NOT_ACTIVE)
	stand(w,"gus",FAR_SPOT)
	expect_rejected(w,"gus","harvest_start",Harvest.SIGN,"0","Start from the spawn point",Harvest.TOO_FAR_SIGN)
	expect(not w.state.has("harvest_relay"),"Rejected starts write no round")
	stand(w,"gus",CRATE_SPOT)
	var r:=ok(w,"gus","harvest_start",Harvest.SIGN,"0","Start round 1 at the sign")
	expect(msg(r).contains("第 1 輪"),"Start message names round 1")
	var relay:=relay_of(w)
	expect(int(relay.round)==1 and relay.active==true and is_equal_approx(float(relay.started),START) and is_equal_approx(float(relay.ends),START+180.0),"Round 1 active, ends = started + 180")
	expect(same(relay.participants,{"gus":{"carry":"","relay":false,"sorted":0,"passed":0,"joined":true}}),"Starter auto-joins")
	expect(not pl(w,"gus").has("harvest_relay"),"No personal record before settlement")
	expect_rejected(w,"gus","harvest_start",Harvest.SIGN,"0","Stale double start with round 0",Harvest.ALREADY_ACTIVE)
	expect_rejected(w,"hal","harvest_start",Harvest.SIGN,"1","Second start while active",Harvest.ALREADY_ACTIVE)
	expect_rejected(w,"hal","harvest_join",Harvest.SIGN,"0","Join with a stale round id",Harvest.STALE)
	expect_rejected(w,"hal","harvest_join",Harvest.SIGN,"","Join with an empty round id",Harvest.STALE)
	expect_rejected(w,"hal","harvest_pick",Harvest.CRATE,"","Pick before joining",Harvest.NOT_JOINED)
	expect_rejected(w,"hal","harvest_leave",Harvest.SIGN,"","Leave before joining",Harvest.NOT_JOINED)
	stand(w,"hal",FAR_SPOT)
	expect_rejected(w,"hal","harvest_join",Harvest.SIGN,"1","Join from too far",Harvest.TOO_FAR_SIGN)
	expect_rejected(w,"hal","harvest_join",Harvest.CRATE,"1","Join at the crate",Harvest.WRONG_SIGN)
	expect_rejected(w,"gus","harvest_join",Harvest.SIGN,"1","Starter joins again",Harvest.ALREADY_JOINED)
	for action in ["harvest_leave","harvest_pick","harvest_pass","harvest_sort"]:
		var cell:Vector2i=Harvest.CRATE if action!="harvest_sort" else Harvest.BASKETS.root
		expect_rejected(w,"gus",action,cell,"x","%s with an extra"%action,Harvest.BAD_EXTRA)
	expect_rejected(w,"gus","harvest_pick",Harvest.SIGN,"","Pick at the sign",Harvest.WRONG_CRATE)
	stand(w,"gus",NEAR_CRATE)
	expect_rejected(w,"gus","harvest_pick",Harvest.CRATE,"","Pick from 1.97 tiles",Harvest.TOO_FAR_CRATE)
	stand(w,"gus",CRATE_SPOT)
	expect_rejected(w,"gus","harvest_pass",Harvest.CRATE,"","Pass with empty hands",Harvest.EMPTY_HANDS)
	expect_rejected(w,"gus","harvest_sort",Harvest.CRATE,"","Sort at the crate",Harvest.WRONG_BASKET_CELL)
	expect_rejected(w,"gus","harvest_sort",Harvest.SIGN,"","Sort at the sign",Harvest.WRONG_BASKET_CELL)
	ok(w,"gus","harvest_pick",Harvest.CRATE,"","Pick")
	expect_rejected(w,"gus","harvest_sort",Harvest.BASKETS.root,"","Sort from beside the crate",Harvest.TOO_FAR_BASKET)
	# Time over but not yet stepped: actions wait for the settlement.
	w.state.time=START+180.0
	expect_rejected(w,"gus","harvest_pass",Harvest.CRATE,"","Pass after the deadline",Harvest.ENDING)
	stand(w,"hal",CRATE_SPOT)
	expect_rejected(w,"hal","harvest_start",Harvest.SIGN,"1","Start after the deadline before settlement",Harvest.ENDING)
	expect_rejected(w,"hal","harvest_join",Harvest.SIGN,"1","Join after the deadline",Harvest.ENDING)

# 5. A full deterministic solo round to GOAL, wrong basket, full hands, nobody near.
func test_solo_round()->void:
	var w:=make_world(["sol","obs"])
	stand(w,"obs",FAR_SPOT)
	var before:=bags(w,["sol","obs"])
	ok(w,"sol","harvest_start",Harvest.SIGN,"0","Solo start")
	var sequence:=[]
	for i in range(Harvest.GOAL):
		stand(w,"sol",CRATE_SPOT)
		var r:=act(w,"sol","harvest_pick",Harvest.CRATE)
		expect(bool(r.ok),"Pick %d (%s)"%[i,msg(r)])
		var kind:=str(entry_of(w,"sol").carry)
		sequence.append(kind)
		expect(kind==Harvest.kind_at(1,i),"Pick %d is kind_at(1,%d)=%s (got %s)"%[i,i,Harvest.kind_at(1,i),kind])
		expect(int(relay_of(w).index)==i+1,"index counts picks (%d)"%(i+1))
		var v:=view(w,"sol")
		expect(v.carry==kind and v.carry_name==Harvest.kind_name(kind) and v.carry_basket==Harvest.basket_of(kind) and v.carry_icon==str(Harvest.KINDS[kind].icon) and v.carry_relay==false,"View shows carry %d"%i)
		expect(msg(r)=="拿到%s，送到「%s」籃，或傳給隊友。"%[Harvest.kind_name(kind),Harvest.BASKET_NAMES[Harvest.basket_of(kind)]],"Pick message %d"%i)
		if i==0:
			expect_rejected(w,"sol","harvest_pick",Harvest.CRATE,"","Pick with full hands",Harvest.HANDS_FULL)
			expect_rejected(w,"sol","harvest_pass",Harvest.CRATE,"","Pass with nobody near",Harvest.NO_TARGET)
		var right:=Harvest.basket_of(kind)
		stand(w,"sol",spot_for(right))
		var wrong:=wrong_for(right)
		if i<3:
			var hint:=Harvest.WRONG_BASKET%[Harvest.kind_name(kind),Harvest.BASKET_NAMES[right],Harvest.BASKET_NAMES[right]]
			expect_rejected(w,"sol","harvest_sort",Harvest.BASKETS[wrong],"","Wrong basket %s for %s"%[wrong,kind],hint)
		var s:=act(w,"sol","harvest_sort",Harvest.BASKETS[right])
		expect(bool(s.ok),"Sort %d (%s)"%[i,msg(s)])
		if i<Harvest.GOAL-1:
			expect(msg(s)=="%s放進「%s」籃！大家完成了 %d / %d。"%[Harvest.kind_name(kind),Harvest.BASKET_NAMES[right],i+1,Harvest.GOAL],"Sort message %d"%i)
			expect(relay_of(w).active==true and int(relay_of(w).delivered)==i+1,"Delivered %d"%(i+1))
		else:
			expect(msg(s).contains("全部分類完成") and msg(s).contains("4 張紀念票"),"Final sort message ("+msg(s)+")")
	var relay:=relay_of(w)
	expect(relay.active==false and int(relay.delivered)==24 and int(relay.relays)==0,"Round ended early at GOAL")
	expect(same(relay.last,{"round":1,"delivered":24,"relays":0,"players":1,"tickets":4,"reason":"goal","finished":START}),"Last result summary %s"%str(relay.last))
	expect(is_equal_approx(float(relay.ready),START+60.0),"Cooldown until finished + 60")
	expect(same(record_of(w,"sol"),{"tickets":4,"rounds":1,"best":24,"paid_round":1}),"Solo player paid 1 + 3 tickets once")
	expect(not pl(w,"obs").has("harvest_relay"),"A bystander gets nothing")
	expect(same(bags(w,["sol","obs"]),before),"Inventory and coins of everyone identical after the round")
	var seq_unique:={}
	for kind in sequence.slice(0,8):seq_unique[kind]=true
	expect(seq_unique.size()==8,"First 8 picks are 8 different kinds")
	# A second World running the same actions sees the same sequence.
	var again:=make_world(["sol"])
	ok(again,"sol","harvest_start",Harvest.SIGN,"0","Replica start")
	var replica:=[]
	for i in range(5):replica.append(pick_and_sort(again,"sol","Replica %d"%i))
	expect(replica==sequence.slice(0,5),"Deterministic sequence across worlds")
	# Step after settlement pays nothing more.
	var rec:=record_of(w,"sol").duplicate(true)
	var snap:=var_to_bytes(relay_of(w))
	w.step(0.5,true)
	expect(same(record_of(w,"sol"),rec) and var_to_bytes(relay_of(w))==snap,"A step after settlement changes nothing")
	# Cooldown.
	stand(w,"sol",CRATE_SPOT)
	w.state.time=START+30.0
	expect_rejected(w,"sol","harvest_start",Harvest.SIGN,"1","Start during the cooldown",Harvest.COOLDOWN_MSG%30)
	expect(view(w,"sol").can_start==false and is_equal_approx(float(view(w,"sol").cooldown),30.0),"View shows 30 s cooldown")
	w.state.time=START+60.0
	expect_rejected(w,"sol","harvest_start",Harvest.SIGN,"0","Stale round id after round 1",Harvest.STALE)
	expect(view(w,"sol").can_start==true,"Cooldown over")
	var r2:=ok(w,"sol","harvest_start",Harvest.SIGN,"1","Round 2 starts with id 1")
	expect(int(relay_of(w).round)==2 and same(relay_of(w).participants,{"sol":{"carry":"","relay":false,"sorted":0,"passed":0,"joined":true}}) and int(relay_of(w).delivered)==0 and int(relay_of(w).index)==0,"Round 2 resets the roster and counters ("+msg(r2)+")")
	expect(same(relay_of(w).last,{"round":1,"delivered":24,"relays":0,"players":1,"tickets":4,"reason":"goal","finished":START}),"Round 2 keeps round 1 as last result")

# 6. Two players: pass, relay bonus, pass rules.
func test_two_players()->void:
	var w:=make_world(["ann","bob"])
	var before:=bags(w,["ann","bob"])
	ok(w,"ann","harvest_start",Harvest.SIGN,"0","Ann starts")
	stand(w,"bob",NEAR_CRATE)
	ok(w,"bob","harvest_join",Harvest.SIGN,"1","Bob joins")
	expect(view(w,"ann").joined_count==2 and view(w,"bob").joined==true,"Two joined")
	ok(w,"ann","harvest_pick",Harvest.CRATE,"","Ann picks")
	var kind:=str(entry_of(w,"ann").carry)
	var r:=ok(w,"ann","harvest_pass",Vector2i(0,0),"","Ann passes (p ignored)")
	expect(msg(r)=="把%s傳給%s。"%[Harvest.kind_name(kind),"bob"],"Pass message names the receiver ("+msg(r)+")")
	expect(entry_of(w,"ann").carry=="" and int(entry_of(w,"ann").passed)==1,"Ann empty-handed, passed 1")
	expect(entry_of(w,"bob").carry==kind and entry_of(w,"bob").relay==true and view(w,"bob").carry_relay==true,"Bob carries the relayed vegetable")
	# Bob carrying: Ann picks again and cannot pass to full hands.
	ok(w,"ann","harvest_pick",Harvest.CRATE,"","Ann picks a second one")
	expect_rejected(w,"ann","harvest_pass",Harvest.CRATE,"","Pass to a full-handed partner",Harvest.NO_TARGET)
	var basket:=Harvest.basket_of(kind)
	stand(w,"bob",spot_for(basket))
	var s:=ok(w,"bob","harvest_sort",Harvest.BASKETS[basket],"","Bob sorts the relayed vegetable")
	expect(msg(s).contains("接力加分 +1"),"Sort message shows the relay bonus ("+msg(s)+")")
	var relay:=relay_of(w)
	expect(int(relay.delivered)==1 and int(relay.relays)==1 and int(entry_of(w,"bob").sorted)==1 and entry_of(w,"bob").relay==false,"Delivered 1 with 1 relay")
	# Out of pass reach; offline partner; partner in another region.
	stand(w,"ann",CRATE_SPOT)
	expect_rejected(w,"ann","harvest_pass",Harvest.CRATE,"","Pass to a partner 4 tiles away",Harvest.NO_TARGET)
	stand(w,"bob",NEAR_CRATE)
	w.active_tokens.erase("bob")
	expect_rejected(w,"ann","harvest_pass",Harvest.CRATE,"","Pass to an offline partner",Harvest.NO_TARGET)
	w.active_tokens["bob"]=true
	ok(w,"ann","harvest_pass",Harvest.CRATE,"","Pass to Bob back online and near")
	expect(entry_of(w,"bob").relay==true,"Second relay")
	# Bob passes it back: still a relay, Bob's passed counts.
	ok(w,"bob","harvest_pass",Harvest.CRATE,"","Bob passes back")
	expect(entry_of(w,"ann").relay==true and int(entry_of(w,"bob").passed)==1,"Pass back keeps the relay flag")
	var v:=view(w,"ann")
	var names:=[]
	for e:Dictionary in v.participants:names.append(e.name)
	expect(names==["ann","bob"] and v.participants[0].me==true and v.participants[1].me==false,"View participant list with names and me flag")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==VIEW_KEYS,"View has exactly the documented keys (%s)"%str(keys))
	expect(not JSON.stringify(v).contains("\"ann\":") ,"View is not keyed by token")
	ok(w,"ann","harvest_leave",Harvest.CRATE,"","Ann leaves holding a vegetable")
	ok(w,"bob","harvest_leave",Harvest.CRATE,"","Bob leaves")
	expect(same(bags(w,["ann","bob"]),before),"Both bags and coins unchanged after passing and leaving")

# 7. 8 currently-joined players; 9th refused; leave frees a slot; rejoin keeps counts.
func test_cap_and_rejoin()->void:
	var tokens:=[]
	for i in range(10):tokens.append("cap%d"%i)
	var w:=make_world(tokens)
	ok(w,"cap0","harvest_start",Harvest.SIGN,"0","cap0 starts")
	for i in range(1,8):ok(w,tokens[i],"harvest_join",Harvest.SIGN,"1","%s joins"%tokens[i])
	expect(view(w,"cap0").joined_count==8,"Eight joined")
	expect_rejected(w,"cap8","harvest_join",Harvest.SIGN,"1","9th joiner",Harvest.FULL%8)
	ok(w,"cap1","harvest_pick",Harvest.CRATE,"","cap1 picks")
	var kind:=str(entry_of(w,"cap1").carry)
	stand(w,"cap1",spot_for(Harvest.basket_of(kind)))
	ok(w,"cap1","harvest_sort",Harvest.BASKETS[Harvest.basket_of(kind)],"","cap1 sorts")
	ok(w,"cap1","harvest_leave",Harvest.SIGN,"","cap1 leaves")
	expect(view(w,"cap1").joined==false and int(entry_of(w,"cap1").sorted)==1,"Leaver keeps the sorted count")
	ok(w,"cap8","harvest_join",Harvest.SIGN,"1","9th joins after a leave")
	stand(w,"cap1",CRATE_SPOT)
	expect_rejected(w,"cap1","harvest_join",Harvest.SIGN,"1","Leaver cannot rejoin while 8 are in",Harvest.FULL%8)
	ok(w,"cap2","harvest_leave",Harvest.SIGN,"","cap2 leaves")
	ok(w,"cap1","harvest_join",Harvest.SIGN,"1","cap1 rejoins the same round")
	expect(int(entry_of(w,"cap1").sorted)==1 and entry_of(w,"cap1").joined==true and relay_of(w).participants.size()==9,"Rejoin reuses the entry (sorted 1), roster 9")

# 8. Timeout settlement, leavers and offline players paid exactly once.
func test_timeout_and_payment()->void:
	var tokens:=["ta","tb","tc","td"]
	var w:=make_world(tokens)
	var before:=bags(w,tokens)
	ok(w,"ta","harvest_start",Harvest.SIGN,"0","ta starts")
	for t in ["tb","tc","td"]:ok(w,t,"harvest_join",Harvest.SIGN,"1","%s joins"%t)
	# tb picks then leaves: the vegetable vanishes, never enters the backpack.
	ok(w,"tb","harvest_pick",Harvest.CRATE,"","tb picks")
	var r:=ok(w,"tb","harvest_leave",Harvest.SIGN,"","tb leaves holding it")
	expect(msg(r).contains("背包沒有變動"),"Leave message promises the backpack is untouched")
	expect(entry_of(w,"tb").carry=="" and entry_of(w,"tb").joined==false,"tb dropped the vegetable")
	expect(same(bags(w,["tb"]),{"tb":before.tb}),"tb's bag and coins identical after leaving with a vegetable")
	# tc leaves and rejoins (once paid only).
	ok(w,"tc","harvest_leave",Harvest.SIGN,"","tc leaves")
	ok(w,"tc","harvest_join",Harvest.SIGN,"1","tc rejoins")
	# td goes offline mid-round.
	w.active_tokens.erase("td")
	for i in range(9):pick_and_sort(w,"ta","ta delivery %d"%i)
	expect(int(relay_of(w).delivered)==9,"Nine delivered before the deadline")
	w.state.time=START+179.0
	w.step(0.5,true)
	expect(relay_of(w).active==true,"Still active at 179.5 s")
	expect(entry_of(w,"td").joined==false,"Offline td was dropped from the round by step")
	w.step(0.5,true)
	var relay:=relay_of(w)
	expect(relay.active==false and relay.last.reason=="time" and int(relay.last.delivered)==9 and int(relay.last.tickets)==2 and int(relay.last.players)==4,"Timeout settles: 9 delivered, 2 tickets each, 4 players")
	for t:String in tokens:
		expect(same(record_of(w,t),{"tickets":2,"rounds":1,"best":9,"paid_round":1}),"%s paid exactly once (%s)"%[t,str(record_of(w,t))])
		var e:=entry_of(w,t)
		expect(e.joined==false and e.carry=="","%s is out with empty hands after settlement"%t)
	expect(same(bags(w,tokens),before),"Every participant's bag and coins identical after the timeout")
	# Further steps pay nothing.
	for i in range(3):w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==2 and int(record_of(w,t).rounds)==1,"%s not paid again by later steps"%t)
	# Re-settle guard: force the finished round active again past its end.
	var forced:Dictionary=w.state.harvest_relay
	forced.active=true
	w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==2 and int(record_of(w,t).paid_round)==1,"%s: paid_round blocks a re-settlement of round 1"%t)
	# Round 2 times out with 0 delivered: 1 participation ticket each.
	w.active_tokens["td"]=true
	w.state.time=float(w.state.harvest_relay.ready)
	stand(w,"tc",CRATE_SPOT)
	ok(w,"tc","harvest_start",Harvest.SIGN,"1","Round 2")
	ok(w,"td","harvest_join",Harvest.SIGN,"2","td joins round 2")
	w.state.time=float(w.state.harvest_relay.ends)
	w.step(0.5,true)
	expect(relay_of(w).active==false and int(relay_of(w).last.delivered)==0 and int(relay_of(w).last.tickets)==1,"Zero-delivery timeout")
	expect(same(record_of(w,"tc"),{"tickets":3,"rounds":2,"best":9,"paid_round":2}) and same(record_of(w,"td"),{"tickets":3,"rounds":2,"best":9,"paid_round":2}),"tc and td +1 ticket for round 2")
	expect(same(record_of(w,"ta"),{"tickets":2,"rounds":1,"best":9,"paid_round":1}),"ta (not in round 2) unchanged")
	expect(view(w,"td").tickets==3 and view(w,"td").rounds==2 and view(w,"td").best==9,"View shows own tickets/rounds/best")
	expect(same(bags(w,tokens),before),"Bags and coins still identical after round 2")
	# Ticket counter cap.
	(pl(w,"tc").harvest_relay as Dictionary).tickets=Harvest.MAX_TICKETS
	w.state.time=float(w.state.harvest_relay.ready)
	ok(w,"tc","harvest_start",Harvest.SIGN,"2","Round 3")
	w.state.time=float(w.state.harvest_relay.ends)
	w.step(0.5,true)
	expect(int(record_of(w,"tc").tickets)==Harvest.MAX_TICKETS and int(record_of(w,"tc").rounds)==3,"Tickets saturate at MAX_TICKETS")

# 9. Disconnect and travel drop the carry; the hook is idempotent.
func test_disconnect_and_travel()->void:
	var w:=make_world(["dia","dib"])
	var before:=bags(w,["dia","dib"])
	ok(w,"dia","harvest_start",Harvest.SIGN,"0","dia starts")
	ok(w,"dib","harvest_join",Harvest.SIGN,"1","dib joins")
	ok(w,"dia","harvest_pick",Harvest.CRATE,"","dia picks")
	expect(w.harvest_disconnect("dia"),"Disconnect hook drops dia")
	expect(entry_of(w,"dia").carry=="" and entry_of(w,"dia").joined==false,"dia's vegetable vanished, dia is out")
	expect(not w.harvest_disconnect("dia"),"Second disconnect changes nothing")
	expect(not w.harvest_disconnect("nobody"),"Unknown token changes nothing")
	ok(w,"dia","harvest_join",Harvest.SIGN,"1","dia rejoins after reconnecting")
	ok(w,"dib","harvest_pick",Harvest.CRATE,"","dib picks")
	pl(w,"dib").region=World.REGIONS.LANYANG
	expect(w.step(0.5,true),"Step saves the travel drop")
	expect(entry_of(w,"dib").carry=="" and entry_of(w,"dib").joined==false,"Travelling away drops dib's vegetable")
	pl(w,"dib").region=World.REGIONS.HOME
	ok(w,"dia","harvest_pick",Harvest.CRATE,"","dia picks again")
	w.active_tokens.erase("dia")
	w.step(0.5,true)
	expect(entry_of(w,"dia").carry=="" and entry_of(w,"dia").joined==false,"Offline (no hook) is dropped by step")
	var quiet:=var_to_bytes(w.state.harvest_relay)
	w.step(0.5,true)
	expect(var_to_bytes(w.state.harvest_relay)==quiet,"Dropping is not repeated")
	expect(same(bags(w,["dia","dib"]),before),"Bags and coins identical after disconnect and travel")

# 10. Request replay returns the receipt without a second pick.
func test_replay()->void:
	var w:=make_world(["rep"])
	ok(w,"rep","harvest_start",Harvest.SIGN,"0","Start")
	var r:=act(w,"rep","harvest_pick",Harvest.CRATE,"","replay-pick")
	expect(bool(r.ok),"Pick with a fixed request id")
	var index:=int(relay_of(w).index)
	var kind:=str(entry_of(w,"rep").carry)
	stand(w,"rep",spot_for(Harvest.basket_of(kind)))
	ok(w,"rep","harvest_sort",Harvest.BASKETS[Harvest.basket_of(kind)],"","Sort")
	stand(w,"rep",CRATE_SPOT)
	var again:=act(w,"rep","harvest_pick",Harvest.CRATE,"","replay-pick")
	expect(again==r and int(relay_of(w).index)==index and entry_of(w,"rep").carry=="","Replayed pick returns the receipt and picks nothing")

## `first` = the round's first participant (the carrier in the active fixture);
## record cases always tamper "sam", who holds a paid record in both fixtures.
static func tampered(good:Dictionary,label:String)->Dictionary:
	var s:Dictionary=good.duplicate(true)
	var relay:Dictionary=s.harvest_relay
	var people:Dictionary=relay.participants
	var first:String=people.keys()[0]
	var paid:Dictionary=s.players.sam
	match label:
		"relay is an array":s.harvest_relay=[]
		"relay without picnic":s.picnic=false
		"negative round":relay.round=-1
		"active not bool":relay.active=1
		"delivered over goal":relay.delivered=25
		"relays above delivered":relay.relays=int(relay.delivered)+1
		"ends not started+180":relay.ends=float(relay.started)+90.0
		"started in the future":
			relay.started=float(s.time)+500.0
			relay.ends=float(relay.started)+180.0
		"unknown carry kind":
			people[first].carry="gold_bar"
		"carry while not joined":
			people[first].carry="radish"
			people[first].joined=false
		"relay flag with empty hands":
			people[first].carry=""
			people[first].relay=true
		"sorted sum differs":people[first].sorted=int(people[first].sorted)+1
		"participant not a player":people["ghost-token"]={"carry":"","relay":false,"sorted":0,"passed":0,"joined":false}
		"entry extra field":people[first].mood=1
		"entry missing field":people[first].erase("passed")
		"fractional sorted":people[first].sorted=0.5
		"index below delivered":relay.index=0
		"extra root field":relay.mood=1
		"missing root field":relay.erase("ready")
		"last tickets wrong":relay.last.tickets=4
		"last reason bogus":relay.last.reason="magic"
		"last round mismatch":relay.last.round=int(relay.last.round)+1
		"ready mismatch":relay.ready=float(relay.ready)+5.0
		"joined while inactive":people[first].joined=true
		"paid record while active":
			# sam is in round 2 (active) yet already marked paid for it.
			paid.harvest_relay.paid_round=int(relay.round)
		"record paid_round ahead":paid.harvest_relay.paid_round=int(relay.round)+1
		"record tickets below rounds":paid.harvest_relay.tickets=0
		"record extra field":paid.harvest_relay.bonus=1
		"record missing for a paid participant":paid.erase("harvest_relay")
		"record is a string":paid.harvest_relay="ticket"
		"record without a round":
			s.erase("harvest_relay")
		"record best over goal":paid.harvest_relay.best=25
	return s

# 11. Save -> reload equality, legacy saves, schema tampering.
func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=make_world(["sam","tia","uma"])
	w.save_path=path
	# Round 1 times out with 3 delivered (one relayed); round 2 is active mid-way.
	ok(w,"sam","harvest_start",Harvest.SIGN,"0","sam starts")
	stand(w,"tia",NEAR_CRATE)
	ok(w,"tia","harvest_join",Harvest.SIGN,"1","tia joins")
	ok(w,"sam","harvest_pick",Harvest.CRATE,"","sam picks")
	ok(w,"sam","harvest_pass",Harvest.CRATE,"","sam passes")
	var kind:=str(entry_of(w,"tia").carry)
	stand(w,"tia",spot_for(Harvest.basket_of(kind)))
	ok(w,"tia","harvest_sort",Harvest.BASKETS[Harvest.basket_of(kind)],"","tia sorts")
	pick_and_sort(w,"sam","sam 1")
	pick_and_sort(w,"sam","sam 2")
	w.state.time=START+180.25
	w.step(0.5,true)
	expect(relay_of(w).active==false and int(relay_of(w).last.delivered)==3,"Round 1 finished by time")
	var finished_state:Dictionary=w.state.duplicate(true)
	w.state.time=float(w.state.harvest_relay.ready)+3.5
	stand(w,"uma",CRATE_SPOT)
	ok(w,"uma","harvest_start",Harvest.SIGN,"1","uma starts round 2")
	stand(w,"sam",CRATE_SPOT)
	ok(w,"sam","harvest_join",Harvest.SIGN,"2","sam joins round 2")
	ok(w,"uma","harvest_pick",Harvest.CRATE,"","uma picks")
	stand(w,"sam",NEAR_CRATE)
	ok(w,"uma","harvest_pass",Harvest.CRATE,"","uma passes to sam")
	stand(w,"uma",CRATE_SPOT)
	ok(w,"uma","harvest_pick",Harvest.CRATE,"","uma holds another")
	expect(w.save(),"World saves")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the save")
	if failures>0:return
	expect(same(relay_of(restored),relay_of(w)),"Round state survives reload (canonical bytes)")
	for token in ["sam","tia","uma"]:
		expect(same(record_of(restored,token),record_of(w,token)),"%s record survives reload"%token)
		expect(same(pl(restored,token).inventory,pl(w,token).inventory) and int(pl(restored,token).coins)==int(pl(w,token).coins),"%s inventory and coins survive reload"%token)
		expect(same(view(restored,token),view(w,token)),"%s view identical after reload"%token)
	var rr:=relay_of(restored)
	expect(typeof(rr.round)==TYPE_INT and typeof(rr.delivered)==TYPE_INT and typeof(rr.index)==TYPE_INT and typeof(rr.last.tickets)==TYPE_INT and typeof(record_of(restored,"sam").tickets)==TYPE_INT and typeof(rr.participants.sam.sorted)==TYPE_INT,"Validation normalizes reloaded numbers to ints")
	expect(entry_of(restored,"sam").carry==entry_of(w,"sam").carry and entry_of(restored,"sam").relay==true,"Carried relayed vegetable survives reload")
	# Reloaded active round settles on the next step (players reconnect first).
	restored.active_tokens={"sam":true,"tia":true,"uma":true}
	restored.state.time=float(restored.state.harvest_relay.ends)
	restored.step(0.5,true)
	expect(relay_of(restored).active==false and int(record_of(restored,"uma").paid_round)==2 and int(record_of(restored,"sam").paid_round)==2 and int(record_of(restored,"tia").paid_round)==1,"Reloaded round settles; tia (round 1 only) untouched")
	# Legacy save without the fields.
	var base:Dictionary=w.state.duplicate(true)
	var old:Dictionary=base.duplicate(true)
	old.erase("harvest_relay")
	for token in ["sam","tia","uma"]:(old.players[token] as Dictionary).erase("harvest_relay")
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without harvest fields loads")
	expect(not legacy.state.has("harvest_relay") and not pl(legacy,"sam").has("harvest_relay"),"Loading does not invent harvest fields")
	expect(view(legacy,"sam").round==0 and view(legacy,"sam").can_start==true,"Legacy world starts fresh")
	expect(write_fixture(fixture,base),"Write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(relay_of(control),relay_of(w)),"Control fixture (active round) loads")
	expect(write_fixture(fixture,finished_state),"Write finished control fixture")
	expect(World.new().load_world(fixture),"Control fixture (finished round) loads")
	if failures>0:return
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var active_labels:=["relay is an array","relay without picnic","negative round","active not bool","delivered over goal","relays above delivered",
		"ends not started+180","started in the future","unknown carry kind","carry while not joined","relay flag with empty hands","sorted sum differs",
		"participant not a player","entry extra field","entry missing field","fractional sorted","index below delivered","extra root field","missing root field",
		"last tickets wrong","last reason bogus","last round mismatch","ready mismatch","record paid_round ahead","record tickets below rounds",
		"record extra field","record is a string","record without a round","record best over goal","paid record while active"]
	var finished_labels:=["joined while inactive","record missing for a paid participant","last tickets wrong","sorted sum differs","record paid_round ahead"]
	var count:=0
	for label:String in active_labels:
		var bad:=tampered(base,label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"Schema rejects (active round) "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
		count+=1
	for label:String in finished_labels:
		var bad:=tampered(finished_state,label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"Schema rejects (finished round) "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
		count+=1
	expect(count>=8,"At least eight tamper cases (%d)"%count)

# 12. Snapshot privacy: hashed participants, own view only to the owner.
func test_snapshot_privacy()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=make_world([PRIVATE_A,PRIVATE_B])
	var w=session.world
	ok(w,PRIVATE_A,"harvest_start",Harvest.SIGN,"0","Alpha starts")
	stand(w,PRIVATE_B,NEAR_CRATE)
	ok(w,PRIVATE_B,"harvest_join",Harvest.SIGN,"1","Beta joins")
	ok(w,PRIVATE_A,"harvest_pick",Harvest.CRATE,"","Alpha picks")
	var kind:=str(entry_of(w,PRIVATE_A).carry)
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	var id_a:=PRIVATE_A.sha256_text().left(16)
	var id_b:=PRIVATE_B.sha256_text().left(16)
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains(PRIVATE_A) and not text.contains(PRIVATE_B),"public_state(%s) has no raw token"%region)
		var hr:Dictionary=public.get("harvest_relay",{})
		expect(hr.get("participants",{}).keys().size()==2 and hr.participants.has(id_a) and hr.participants.has(id_b),"public_state(%s) participants keyed by public ids"%region)
		var clean:=true
		for id in public.get("players",{}):
			if (public.players[id] as Dictionary).has("harvest_relay"):clean=false
		expect(clean,"public_state(%s) players carry no harvest record"%region)
	var hr:Dictionary=session.public_state("home").harvest_relay
	expect(same(hr.participants[id_a],{"name":"harves","carry":kind,"joined":true,"sorted":0,"passed":0}),"Alpha's public entry shows name and carried kind (%s)"%str(hr.participants[id_a]))
	expect(int(hr.round)==1 and hr.active==true and int(hr.goal)==24 and int(hr.delivered)==0,"Public round summary")
	var keys:Array=hr.keys()
	keys.sort()
	expect(keys==["active","delivered","ends","goal","last","participants","ready","relays","round","seconds_left","started"],"Public projection keys (%s)"%str(keys))
	expect(w.state.harvest_relay.participants.has(PRIVATE_A),"Publishing does not rewrite the live record")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("own_harvest") and same(snap.own_harvest,w.harvest_view(PRIVATE_A)),"own_harvest equals the recipient's own view")
	expect(snap.own_harvest.carry==kind and snap.own_harvest.joined==true,"own_harvest shows the recipient's carry")
	expect(not JSON.stringify(snap).contains(PRIVATE_A) and not JSON.stringify(snap).contains(PRIVATE_B),"Snapshot carries no raw token")
	session.world=null
	session.queue_free()
	await process_frame
