extends SceneTree
## T071 regression suite for res://scripts/fishing_meet.gd (河岸釣魚會) and its World,
## SaveSchema and Session integration: picnic gate, region/cell/reach gates, stale
## round ids, a full deterministic solo round to GOAL through the real fish_start /
## fish_catch actions (easy and standard modes) with the whole player record compared
## before/after, normal fishing outside the rules (joined outside WATERS, not joined
## inside WATERS), the 8-player cap, leave / rejoin / disconnect / travel drops,
## timeout settlement (zero-catch participant, <4 species, all 4 species), exactly-
## once tickets (paid_round), cooldown, refusals leaving the WHOLE world state byte-
## identical, save -> reload equality (mid-round and settled), legacy saves, schema
## tampering, site terrain/adjacency rules against the real world data and snapshot
## privacy.
##
## PRESET (written straight into world state, not earned): state.picnic, state.board
## and festival_story_open (site checks only), state.time, player positions / regions, inventories,
## active_tokens (to simulate offline players), one object written onto the sign cell
## (pause case) and, for the schema cases only, tampered copies of saved records.
## World time is advanced by assignment to reach the fish bite (fishing.ready) and the
## round deadline. Everything else goes through World.act and World.step.
const World=preload("res://scripts/world.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const Harvest=preload("res://scripts/harvest_relay.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Session=preload("res://scripts/session.gd")
const START:=1000.0
const PRIVATE_A:="fishmeet-private-alpha-token"
const PRIVATE_B:="fishmeet-private-beta-token"
## Standing spots (player centres).
const FISH_SPOT:=Vector2(54.5,36.5)    # shore cell 54,36: 2.0 from the sign, 1.0 from water 55,36
const CAST:=Vector2i(55,36)            # a WATERS cell
const NORTH_SPOT:=Vector2(54.5,34.5)   # shore cell 54,34: reaches 55,33 (outside WATERS)
const OUTSIDE:=Vector2i(55,33)         # river water just north of WATERS
const FAR_SPOT:=Vector2(39.5,33.5)     # player spawn: far from the sign
const VIEW_KEYS:=["active","available","best","can_start","caught","cooldown","goal","joined","joined_count","last","max_players","participants","records","round","rounds","seconds_left","shore","sign","species","species_count","species_names","species_total","tickets","unlocked","waters","waters_rect"]
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
	print("FISHING_MEET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("fishing-meet-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func stand(w,token:String,at:Vector2)->void:
	var p:Dictionary=pl(w,token)
	p.x=at.x
	p.y=at.y

static func meet_of(w)->Dictionary:
	var r:Variant=w.state.get("fish_meet")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func entry_of(w,token:String)->Dictionary:
	var e:Variant=meet_of(w).get("participants",{}).get(token)
	if e is Dictionary:
		var copy:Dictionary=e
		return copy
	return {}

static func record_of(w,token:String)->Dictionary:
	var r:Variant=pl(w,token).get("fish_meet")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.fish_meet_view(token)
	return v

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

## The player record minus fields an action legitimately touches outside the
## activity: request receipts, the cast line and the activity record itself.
static func person_core(w,token:String)->Dictionary:
	var p:Dictionary=pl(w,token).duplicate(true)
	for field in ["receipts","fishing","fish_meet"]:p.erase(field)
	return p

static func cores(w,tokens:Array)->Dictionary:
	var out:={}
	for token:String in tokens:out[token]=person_core(w,token)
	return out

func act(w,token:String,action:String,cell:Vector2i,extra:String="",request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "fishmeet-req-%d"%serial
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
	var had_root:bool=w.state.has("fish_meet")
	var had_record:bool=pl(w,token).has("fish_meet")
	var r:Dictionary=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself ("+msg(r)+")")
	if not expected.is_empty():expect(msg(r)==expected,label+": message is '%s' (got '%s')"%[expected,msg(r)])
	expect(var_to_bytes(w.state)==before,label+": world state byte-identical")
	expect(w.state.has("fish_meet")==had_root and pl(w,token).has("fish_meet")==had_record,label+": no fish_meet field invented")

## A picnic-done world (PRESET) at START with players standing on the shore.
func make_world(tokens:Array,picnic:bool=true)->World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=START
	for token:String in tokens:
		stand(w,token,FISH_SPOT)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["carp","radish","wood"]:inv[item]=3
	return w

## Casts at `cell` (mode "" easy / "standard" tracking) and reels in after the bite,
## advancing world time by assignment. Returns the final fish_catch result.
func cast_and_catch(w,token:String,cell:Vector2i,mode:String,label:String)->Dictionary:
	var s:=act(w,token,"fish_start",cell,mode)
	expect(bool(s.ok),label+": cast ("+msg(s)+")")
	if not s.ok:return s
	var cast:Dictionary=pl(w,token).fishing
	w.state.time=float(cast.ready)
	if mode!="standard":
		w.state.time=float(cast.ready)+1.0
		return act(w,token,"fish_catch",cell)
	var r:={}
	for attempt in range(24):
		r=act(w,token,"fish_catch",cell)
		if not r.ok or not pl(w,token).has("fishing"):return r
		w.state.time=float(w.state.time)+0.8
	expect(false,label+": standard tracking never completed")
	return r

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_constants()
	test_site()
	if failures>0:
		finish()
		return
	test_locked()
	test_gates()
	test_solo_round()
	test_normal_fishing()
	test_rod_event_fairness()
	test_cap_and_rejoin()
	test_timeout_and_payment()
	test_disconnect_and_travel()
	test_replay()
	test_save_reload_and_schema()
	await test_snapshot_privacy()
	finish()

# 1. Constants, kinds and the deterministic sequence.
func test_constants()->void:
	expect(Meet.ACTIONS==["fish_meet_start","fish_meet_join","fish_meet_leave"],"Three fish meet actions")
	expect(Meet.GOAL==12 and is_equal_approx(Meet.DURATION,300.0) and is_equal_approx(Meet.COOLDOWN,60.0) and Meet.MAX_PLAYERS==8 and Meet.MAX_ENTRIES==32 and is_equal_approx(Meet.SIGN_REACH,3.2),"GOAL 12, 300 s, cooldown 60 s, 8 players, 32 entries, sign reach 3.2")
	expect(Meet.KINDS==["carp","minnow","redfish","loach"],"Four home river fish")
	expect(Meet.ORDER==["carp","minnow","carp","redfish","minnow","carp","loach","minnow"],"ORDER as designed")
	for kind:String in Meet.KINDS:
		expect(World.Collections.FISH.has(kind) and kind in World.Collections.FRESHWATER_FISH,"%s is a Collections freshwater fish"%kind)
		expect(Meet.kind_name(kind)==str(World.Collections.FISH[kind].name),"%s name from Collections.FISH"%kind)
	for action:String in Meet.ACTIONS:
		expect(not action in ["fish_start","fish_catch"] and not action in Harvest.ACTIONS and not action in Market.ACTIONS,"%s does not collide with an existing action"%action)
	for round_id in [1,2,3,17,1000]:
		for start in [0,3,9]:
			var cycle:={}
			for index in range(start,start+8):cycle[Meet.kind_at(round_id,index)]=true
			expect(cycle.size()==4,"Round %d: 8 consecutive catches from %d cover all four species"%[round_id,start])
		expect(Meet.kind_at(round_id,2)==Meet.kind_at(round_id,10),"Round %d sequence repeats every 8"%round_id)
	expect(Meet.kind_at(1,0)==Meet.ORDER[3] and Meet.kind_at(1,1)==Meet.ORDER[0] and Meet.kind_at(2,3)==Meet.ORDER[posmod(6+15,8)],"kind_at formula round*3+index*5 mod 8")
	var table:=[[0,0,1],[1,1,1],[3,11,1],[4,4,2],[4,11,2],[3,12,2],[4,12,3]]
	for row:Array in table:
		expect(Meet.tickets_for(row[0],row[1])==row[2],"tickets_for(%d species, %d records)==%d"%row)

## Every fixed home landmark the sign must neither stand on nor touch.
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
	for index in range(Harvest.CELLS.size()):marks["harvest relay cell %d"%index]=Harvest.CELLS[index]
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
	for y in range(29,32):
		for x in [55,56]:marks["bridge %d,%d"%[x,y]]=Vector2i(x,y)
	# Plots existing tests / preview fixtures build on near the river.
	marks["pump plot 53,36 (preview fixtures)"]=Vector2i(53,36)
	marks["station plot 53,33 (queue session tests)"]=Vector2i(53,33)
	for y in range(24,29):
		for x in [52,53]:marks["industry plot %d,%d"%[x,y]]=Vector2i(x,y)
	return marks

## Commonly used build plots named in harvest_relay.gd's site comment.
const BUILD_PLOTS:=[Rect2i(41,34,3,4),Rect2i(34,33,4,5),Rect2i(46,22,6,8)]

# 2. Site: terrain, adjacency, fishable water, shore spots, reservation, pause.
func test_site()->void:
	expect(Meet.SIGN==Vector2i(54,38) and Meet.WATERS==Rect2i(55,34,2,6),"Sign 54,38; WATERS x55..56 y34..39")
	expect(Meet.water_cells().size()==12,"Twelve WATERS cells")
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game home (bridge, picnic, festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var sign:=Meet.SIGN
	for w in [plain,busy]:
		expect(w.is_land(sign) and not w.water(sign),"Sign cell is land, not water")
		expect(w.resource(sign)=="","Sign cell has no resource")
	for spot:Vector2i in [sign,sign+Vector2i.DOWN]:
		expect(World.base_resource(spot)=="","No fixed tree/rock/grass at %s"%str(spot))
		expect(World.land(spot),"%s is land"%str(spot))
	var marks:=home_landmarks()
	for mark:String in marks:
		var at:Vector2i=marks[mark]
		expect(maxi(absi(sign.x-at.x),absi(sign.y-at.y))>=2,"Sign is not on or touching %s %s"%[mark,str(at)])
	for rect:Rect2i in BUILD_PLOTS:
		expect(not rect.grow(1).has_point(sign),"Sign does not touch build plot %s"%str(rect))
	expect(Vector2(World.SPAWN).distance_to(Vector2(sign)+Vector2(0.5,0.5))>8.0,"Sign far from the spawn")
	expect(not plain.blocked(sign),"Sign cell walkable before the picnic")
	expect(busy.protected(sign) and busy.blocked(sign),"Sign reserved (protected + blocked) after the picnic")
	for p:Vector2i in [sign+Vector2i.LEFT,sign+Vector2i.DOWN,sign+Vector2i.UP+Vector2i.LEFT]:
		expect(not Meet.reserved(busy.state,p),"Only the sign cell is reserved (%s)"%str(p))
	expect(not Meet.available(plain.state) and Meet.available(busy.state) and World.fish_meet_available(busy.state),"available only after the picnic (World.fish_meet_available wraps)")
	# Every WATERS cell is real river water away from the bridge.
	for cell:Vector2i in Meet.water_cells():
		expect(Meet.in_waters(cell),"%s in_waters"%str(cell))
		expect(busy.water(cell) and plain.water(cell) and World.land(cell),"%s is river water (inside the island) with or without the bridge"%str(cell))
		expect(cell.x in [55,56] and cell.y>=33,"%s is in the river south of the bridge"%str(cell))
	expect(not Meet.in_waters(OUTSIDE) and busy.water(OUTSIDE) and not Meet.in_waters(Vector2i(54,36)) and not Meet.in_waters(Vector2i(55,40)),"in_waters is exactly the rect")
	# Shore cells: distinct land cells a fisher can stand on and cast from.
	var shore:={}
	for cell:Vector2i in Meet.SHORE:
		var centre:=Vector2(cell)+Vector2(0.5,0.5)
		expect(not shore.has(cell),"%s listed once"%str(cell))
		shore[cell]=true
		expect(World.land(cell) and not busy.water(cell) and cell!=sign,"%s is land and not the sign"%str(cell))
		expect(busy.can_stand(centre) and plain.can_stand(centre),"%s is standable (before and after the picnic)"%str(cell))
		expect(centre.distance_to(Vector2(sign)+Vector2(0.5,0.5))<=8.0,"%s within 8 tiles of the sign"%str(cell))
		var reach:=false
		for water:Vector2i in Meet.water_cells():
			if centre.distance_to(Vector2(water)+Vector2(0.5,0.5))<=3.2:reach=true
		expect(reach,"%s reaches a WATERS cell within the fishing reach 3.2"%str(cell))
	expect(shore.size()>=8,"At least eight shore spots (%d)"%shore.size())
	# Real casts from every shore spot and onto every WATERS cell.
	var w:=make_world(["site"])
	w.state.festival_story_open=true
	var casts:=0
	for cell:Vector2i in Meet.SHORE:
		stand(w,"site",Vector2(cell)+Vector2(0.5,0.5))
		var best:=Vector2i(-1,-1)
		for water:Vector2i in Meet.water_cells():
			if best.x<0 or (Vector2(cell)+Vector2(0.5,0.5)).distance_to(Vector2(water)+Vector2(0.5,0.5))<(Vector2(cell)+Vector2(0.5,0.5)).distance_to(Vector2(best)+Vector2(0.5,0.5)):best=water
		var r:=act(w,"site","fish_start",best)
		expect(bool(r.ok),"fish_start from shore %s onto %s (%s)"%[str(cell),str(best),msg(r)])
		if r.ok:casts+=1
		pl(w,"site").erase("fishing")
	for water:Vector2i in Meet.water_cells():
		var from:=Vector2i(-1,-1)
		for cell:Vector2i in Meet.SHORE:
			if from.x<0 and (Vector2(cell)+Vector2(0.5,0.5)).distance_to(Vector2(water)+Vector2(0.5,0.5))<=3.2:from=cell
		expect(from.x>=0,"%s is reachable from a shore spot"%str(water))
		stand(w,"site",Vector2(from)+Vector2(0.5,0.5))
		var r:=act(w,"site","fish_start",water)
		expect(bool(r.ok),"fish_start onto WATERS %s from %s (%s)"%[str(water),str(from),msg(r)])
		pl(w,"site").erase("fishing")
	print("FISHING_MEET_SITE sign=%s waters=%s shore=%s casts_from_shore=%d"%[str(Meet.SIGN),str(Meet.WATERS),str(Meet.SHORE),casts])
	expect(FISH_SPOT.distance_to(Vector2(sign)+Vector2(0.5,0.5))<=Meet.SIGN_REACH and FISH_SPOT.distance_to(Vector2(CAST)+Vector2(0.5,0.5))<=3.2,"Test spot reaches the sign and the cast cell")
	expect(NORTH_SPOT.distance_to(Vector2(OUTSIDE)+Vector2(0.5,0.5))<=3.2,"North spot reaches the water outside WATERS")
	# Occupied sign cell (old save / direct object): activity paused, save stays valid.
	var p:=make_world(["bui","oth"])
	p.state.objects[World.key(sign)]={"type":"lamp","owner":"bui","items":{}}
	expect(not Meet.available(p.state) and not Meet.reserved(p.state,sign),"Occupied sign: unavailable, not reserved")
	expect_rejected(p,"bui","fish_meet_start",sign,"0","Start while the sign cell is occupied",Meet.UNAVAILABLE)
	expect(not view(p,"bui").available and not view(p,"bui").can_start,"View reports unavailable")
	var before:=int(pl(p,"bui").get("fish_caught",0))
	var r:=cast_and_catch(p,"bui",CAST,"","Paused: fishing in WATERS")
	expect(bool(r.ok) and int(pl(p,"bui").get("fish_caught",0))==before+1 and not p.state.has("fish_meet"),"Paused: fishing in WATERS is ordinary fishing ("+msg(r)+")")
	var lamp_path:=temp_path("lamp")
	_cleanup.append(lamp_path)
	p.save_path=lamp_path
	expect(p.save(),"Save the world with an object on the sign cell")
	var kept:=World.new()
	expect(kept.load_world(lamp_path),"A save with an object on the sign cell loads")
	expect(kept.state.objects.has(World.key(sign)) and not Meet.available(kept.state),"Object kept and the activity stays paused after reload")
	p.save_path=""
	p.state.objects.erase(World.key(sign))
	expect(Meet.available(p.state) and p.blocked(sign),"Cleared: activity available and the sign reserved again")
	ok(p,"bui","fish_meet_start",sign,"0","Start after clearing the sign cell")
	# Paused mid-round: start/join refused, leave allowed.
	p.state.objects[World.key(sign)]={"type":"lamp","owner":"bui","items":{}}
	expect_rejected(p,"oth","fish_meet_join",sign,"1","Join while paused",Meet.UNAVAILABLE)
	ok(p,"bui","fish_meet_leave",sign,"","Leave while paused")

# 3. Picnic gate: every action refused, nothing written; the hook does nothing.
func test_locked()->void:
	var w:=make_world(["lin"],false)
	for pair:Array in [["fish_meet_start","0"],["fish_meet_join","0"],["fish_meet_leave",""]]:
		expect_rejected(w,"lin",str(pair[0]),Meet.SIGN,str(pair[1]),"Before picnic "+str(pair[0]),Meet.LOCKED)
	var before:=int(pl(w,"lin").get("fish_caught",0))
	var r:=cast_and_catch(w,"lin",CAST,"","Before picnic: fishing in WATERS")
	expect(bool(r.ok) and int(pl(w,"lin").get("fish_caught",0))==before+1,"Before picnic: fishing in WATERS is ordinary fishing ("+msg(r)+")")
	expect(not w.state.has("fish_meet") and not pl(w,"lin").has("fish_meet"),"No fish_meet fields written before the picnic")
	expect(view(w,"lin").unlocked==false and view(w,"lin").available==false and view(w,"lin").can_start==false,"View says locked")

# 4. Region, cell, reach, extra and stale-round gates; ENDING after the deadline.
func test_gates()->void:
	var w:=make_world(["gus","hal"])
	var S:=Meet.SIGN
	var p:Dictionary=pl(w,"gus")
	p.region=World.REGIONS.LANYANG
	for pair:Array in [["fish_meet_start","0"],["fish_meet_join","0"],["fish_meet_leave",""]]:
		expect_rejected(w,"gus",str(pair[0]),S,str(pair[1]),"Wrong region "+str(pair[0]),Meet.WRONG_REGION)
	p.region=World.REGIONS.HOME
	expect_rejected(w,"gus","fish_meet_start",CAST,"0","Start at the water",Meet.WRONG_SIGN)
	expect_rejected(w,"gus","fish_meet_start",Harvest.SIGN,"0","Start at the harvest sign",Meet.WRONG_SIGN)
	expect_rejected(w,"gus","fish_meet_start",S,"1","Stale round id 1 before any round",Meet.STALE)
	expect_rejected(w,"gus","fish_meet_start",S,"","Empty round id",Meet.STALE)
	expect_rejected(w,"gus","fish_meet_start",S,"00","Non-canonical round id",Meet.STALE)
	expect_rejected(w,"gus","fish_meet_join",S,"0","Join with no round",Meet.NOT_ACTIVE)
	expect_rejected(w,"gus","fish_meet_leave",S,"","Leave with no round",Meet.NOT_ACTIVE)
	expect_rejected(w,"gus","fish_meet_leave",S,"x","Leave with an extra",Meet.BAD_EXTRA)
	stand(w,"gus",FAR_SPOT)
	expect_rejected(w,"gus","fish_meet_start",S,"0","Start from the spawn point",Meet.TOO_FAR_SIGN)
	expect(not w.state.has("fish_meet"),"Rejected starts write no round")
	stand(w,"gus",FISH_SPOT)
	var r:=ok(w,"gus","fish_meet_start",S,"0","Start round 1 at the sign")
	expect(msg(r).contains("第 1 輪") and msg(r).contains("背包不會變動"),"Start message names round 1 and the backpack promise")
	var meet:=meet_of(w)
	expect(int(meet.round)==1 and meet.active==true and is_equal_approx(float(meet.started),START) and is_equal_approx(float(meet.ends),START+300.0),"Round 1 active, ends = started + 300")
	expect(same(meet.participants,{"gus":{"caught":0,"joined":true}}) and same(meet.species,{"carp":0,"minnow":0,"redfish":0,"loach":0}) and int(meet.records)==0 and int(meet.index)==0,"Starter auto-joins; empty species card")
	expect(not pl(w,"gus").has("fish_meet"),"No personal record before settlement")
	expect_rejected(w,"gus","fish_meet_start",S,"0","Stale double start with round 0",Meet.ALREADY_ACTIVE)
	expect_rejected(w,"hal","fish_meet_start",S,"1","Second start while active",Meet.ALREADY_ACTIVE)
	expect_rejected(w,"hal","fish_meet_join",S,"0","Join with a stale round id",Meet.STALE)
	expect_rejected(w,"hal","fish_meet_join",S,"","Join with an empty round id",Meet.STALE)
	expect_rejected(w,"hal","fish_meet_leave",S,"","Leave before joining",Meet.NOT_JOINED)
	stand(w,"hal",FAR_SPOT)
	expect_rejected(w,"hal","fish_meet_join",S,"1","Join from too far",Meet.TOO_FAR_SIGN)
	expect_rejected(w,"hal","fish_meet_join",CAST,"1","Join at the water",Meet.WRONG_SIGN)
	expect_rejected(w,"gus","fish_meet_join",S,"1","Starter joins again",Meet.ALREADY_JOINED)
	# The sign cell is reserved: nobody can stand or build on it.
	expect(w.blocked(S) and w.protected(S),"Sign reserved during the round")
	# Time over but not yet stepped: actions and the catch wait for the settlement.
	ok(w,"gus","fish_start",CAST,"","gus casts before the deadline")
	w.state.time=START+300.0
	expect_rejected(w,"gus","fish_catch",CAST,"","Catch after the deadline",Meet.ENDING)
	expect(pl(w,"gus").has("fishing"),"The cast line survives the ENDING refusal")
	stand(w,"hal",FISH_SPOT)
	expect_rejected(w,"hal","fish_meet_start",S,"1","Start after the deadline before settlement",Meet.ENDING)
	expect_rejected(w,"hal","fish_meet_join",S,"1","Join after the deadline",Meet.ENDING)
	w.step(0.5,true)
	expect(meet_of(w).active==false and same(record_of(w,"gus"),{"tickets":1,"rounds":1,"best":0,"paid_round":1}),"Settled: gus (0 caught) gets exactly one ticket")
	var bag:=int(pl(w,"gus").inventory.get("carp",0))+int(pl(w,"gus").inventory.get("minnow",0))+int(pl(w,"gus").inventory.get("redfish",0))+int(pl(w,"gus").inventory.get("loach",0))
	var caught:=int(pl(w,"gus").get("fish_caught",0))
	var after:=act(w,"gus","fish_catch",CAST)
	var bag2:=int(pl(w,"gus").inventory.get("carp",0))+int(pl(w,"gus").inventory.get("minnow",0))+int(pl(w,"gus").inventory.get("redfish",0))+int(pl(w,"gus").inventory.get("loach",0))
	expect(bool(after.ok) and bag2==bag+1 and int(pl(w,"gus").fish_caught)==caught+1,"After settlement the pending cast lands in the backpack normally ("+msg(after)+")")

# 5. A full deterministic solo round to GOAL via real casts, both modes.
func test_solo_round()->void:
	var w:=make_world(["sol","obs"])
	stand(w,"obs",FAR_SPOT)
	pl(w,"sol").rare_fishing_misses=7 # PRESET pity counter: must stay untouched.
	var before:=cores(w,["sol","obs"])
	ok(w,"sol","fish_meet_start",Meet.SIGN,"0","Solo start")
	var sequence:=[]
	var modes:={}
	for i in range(Meet.GOAL):
		var mode:="standard" if i%3==1 else ""
		modes[mode]=int(modes.get(mode,0))+1
		var cell:Vector2i=Meet.water_cells()[i%4+4]
		var expected:=Meet.kind_at(1,i)
		if mode=="standard" and i==1:
			# One tracking adjustment is not a record yet.
			ok(w,"sol","fish_start",cell,"standard","Standard cast %d"%i)
			w.state.time=float(pl(w,"sol").fishing.ready)
			var adj:=ok(w,"sol","fish_catch",cell,"","First tracking adjustment")
			expect(pl(w,"sol").has("fishing") and int(meet_of(w).records)==i and msg(adj).contains("對準魚影"),"Tracking adjustment does not record (%s)"%msg(adj))
			var r:={}
			for attempt in range(24):
				w.state.time=float(w.state.time)+0.8
				r=act(w,"sol","fish_catch",cell)
				if not r.ok or not pl(w,"sol").has("fishing"):break
			expect(bool(r.ok) and not pl(w,"sol").has("fishing"),"Standard catch %d completes (%s)"%[i,msg(r)])
			sequence.append(expected)
		else:
			var r:=cast_and_catch(w,"sol",cell,mode,"Catch %d (%s)"%[i,"standard" if mode else "easy"])
			expect(bool(r.ok),"Catch %d recorded (%s)"%[i,msg(r)])
			sequence.append(expected)
			if i<Meet.GOAL-1:
				var count:=Meet.species_count(Meet.species_after(1,i+1))
				expect(msg(r)=="釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。大家記錄了 %d / 12 筆、%d / 4 種。"%[Meet.kind_name(expected),i+1,count],"Catch message %d (%s)"%[i,msg(r)])
			else:
				expect(msg(r).contains("12 筆紀錄全部完成") and msg(r).contains("3 張紀念票"),"Final catch message ("+msg(r)+")")
		expect(not pl(w,"sol").has("fishing"),"Line reeled in after catch %d"%i)
		if i<Meet.GOAL-1:
			var meet:=meet_of(w)
			expect(meet.active==true and int(meet.records)==i+1 and int(meet.index)==i+1 and int(entry_of(w,"sol").caught)==i+1,"Records %d"%(i+1))
			expect(same(meet.species,Meet.species_after(1,i+1)),"Species card after %d follows kind_at"%(i+1))
		expect(same(cores(w,["sol","obs"]),before),"Whole player record (bag, coins, fish_caught, pity, collection) unchanged after catch %d"%i)
	expect(modes.size()==2,"Both easy and standard modes were used")
	var meet:=meet_of(w)
	expect(meet.active==false and int(meet.records)==12 and same(meet.species,{"carp":6,"minnow":3,"redfish":2,"loach":1}) and same(meet.species,Meet.species_after(1,12)),"Round ended early at GOAL with the full card %s"%str(meet.species))
	expect(same(meet.last,{"round":1,"records":12,"species":4,"players":1,"tickets":3,"reason":"goal","finished":float(w.state.time)}),"Last result summary %s"%str(meet.last))
	expect(is_equal_approx(float(meet.ready),float(w.state.time)+60.0),"Cooldown until finished + 60")
	expect(same(record_of(w,"sol"),{"tickets":3,"rounds":1,"best":12,"paid_round":1}),"Solo player paid 3 tickets once")
	expect(not pl(w,"obs").has("fish_meet"),"A bystander gets nothing")
	expect(same(cores(w,["sol","obs"]),before),"Every player record identical after the round")
	expect(int(pl(w,"sol").rare_fishing_misses)==7,"Pity counter untouched")
	# Determinism: a second World with the same actions sees the same species.
	var again:=make_world(["sol"])
	ok(again,"sol","fish_meet_start",Meet.SIGN,"0","Replica start")
	for i in range(5):cast_and_catch(again,"sol",CAST,"","Replica %d"%i)
	expect(same(meet_of(again).species,Meet.species_after(1,5)) and sequence.slice(0,5)==[Meet.kind_at(1,0),Meet.kind_at(1,1),Meet.kind_at(1,2),Meet.kind_at(1,3),Meet.kind_at(1,4)],"Deterministic sequence across worlds")
	# Step after settlement pays nothing more.
	var rec:=record_of(w,"sol").duplicate(true)
	var snap:=var_to_bytes(meet_of(w))
	w.step(0.5,true)
	w.step(0.5,true)
	expect(same(record_of(w,"sol"),rec) and var_to_bytes(meet_of(w))==snap,"Steps after settlement change nothing")
	# After settlement, casting in WATERS is ordinary fishing (nobody is joined).
	var fishes:=int(pl(w,"sol").get("fish_caught",0))
	var normal:=cast_and_catch(w,"sol",CAST,"","Cast after settlement")
	expect(bool(normal.ok) and int(pl(w,"sol").fish_caught)==fishes+1 and int(meet_of(w).records)==12,"After settlement fishing in WATERS is ordinary ("+msg(normal)+")")
	# Cooldown.
	var finished:=float(meet_of(w).last.finished)
	w.state.time=finished+30.0
	expect_rejected(w,"sol","fish_meet_start",Meet.SIGN,"1","Start during the cooldown",Meet.COOLDOWN_MSG%30)
	expect(view(w,"sol").can_start==false and is_equal_approx(float(view(w,"sol").cooldown),30.0),"View shows 30 s cooldown")
	w.state.time=finished+60.0
	expect_rejected(w,"sol","fish_meet_start",Meet.SIGN,"0","Stale round id after round 1",Meet.STALE)
	expect(view(w,"sol").can_start==true,"Cooldown over")
	ok(w,"sol","fish_meet_start",Meet.SIGN,"1","Round 2 starts with id 1")
	expect(int(meet_of(w).round)==2 and same(meet_of(w).participants,{"sol":{"caught":0,"joined":true}}) and int(meet_of(w).records)==0 and same(meet_of(w).species,Meet.fresh_species()),"Round 2 resets the roster and the card")
	expect(int(meet_of(w).last.round)==1 and int(meet_of(w).last.records)==12,"Round 2 keeps round 1 as last result")

# 6. Joined but outside WATERS, and not joined inside WATERS: ordinary fishing.
func test_rod_event_fairness()->void:
	var w:=make_world(["leader","guest"])
	pl(w,"leader").inventory.precision_rod=1
	pl(w,"guest").inventory.precision_rod=1
	var start:=float(w.state.time)
	ok(w,"leader","fish_meet_start",Meet.SIGN,"0","Start the regular fishing meet")
	ok(w,"leader","fish_start",CAST,"standard","A participant casts with a precision rod in the bag")
	var standard:Dictionary=pl(w,"leader").fishing
	expect(not standard.has("rod") and is_equal_approx(float(standard.ready)-start,3.0) and is_equal_approx(World.FishingTracking.band_half_width(standard),0.22),"Event casts use the same timer and band as the base rod")
	ok(w,"guest","fish_start",CAST,"","A nonparticipant casts with the upgrade")
	var guest:Dictionary=pl(w,"guest")
	expect(guest.fishing.get("rod")=="precision_rod","Nonparticipants keep their upgrades at the same shore")
	ok(w,"guest","fish_meet_join",Meet.SIGN,"1","Join with a preexisting line")
	w.state.time=float(guest.fishing.ready)
	ok(w,"guest","fish_catch",CAST,"","Normalize the preexisting line on the first event attempt")
	expect(int(meet_of(w).records)==0 and not guest.fishing.has("rod") and is_equal_approx(float(guest.fishing.ready)-float(w.state.time),3.0),"Joining midway cannot carry the old performance advantage into the event")
	w.state.time=float(guest.fishing.ready)
	ok(w,"guest","fish_catch",CAST,"","The normalized cast becomes an ordinary event record")
	expect(int(meet_of(w).records)==1 and not guest.has("fishing"),"Exactly one event record was added")

func test_normal_fishing()->void:
	var w:=make_world(["ina","out"])
	ok(w,"ina","fish_meet_start",Meet.SIGN,"0","ina starts")
	# ina (joined) casts outside WATERS.
	stand(w,"ina",NORTH_SPOT)
	var caught:=int(pl(w,"ina").get("fish_caught",0))
	var inv_before:Dictionary=pl(w,"ina").inventory.duplicate()
	var r:=cast_and_catch(w,"ina",OUTSIDE,"","Joined, outside WATERS")
	expect(bool(r.ok) and msg(r).begins_with("釣到了") and msg(r).contains("種子攤"),"Joined outside WATERS: ordinary catch message ("+msg(r)+")")
	var gained:=0
	for kind:String in Meet.KINDS:gained+=int(pl(w,"ina").inventory.get(kind,0))-int(inv_before.get(kind,0))
	expect(gained==1 and int(pl(w,"ina").fish_caught)==caught+1,"Joined outside WATERS: the fish goes to the backpack and counts")
	expect(int(meet_of(w).records)==0,"…and is not a meet record")
	# out (not joined) casts inside WATERS.
	var caught_b:=int(pl(w,"out").get("fish_caught",0))
	var inv_b:Dictionary=pl(w,"out").inventory.duplicate()
	var r2:=cast_and_catch(w,"out",CAST,"standard","Not joined, inside WATERS (standard)")
	expect(bool(r2.ok) and msg(r2).contains("種子攤"),"Not joined inside WATERS: ordinary catch ("+msg(r2)+")")
	var gained_b:=0
	for kind:String in Meet.KINDS:gained_b+=int(pl(w,"out").inventory.get(kind,0))-int(inv_b.get(kind,0))
	expect(gained_b==1 and int(pl(w,"out").fish_caught)==caught_b+1 and pl(w,"out").collection.fish.size()>=1,"Not joined: fish in the backpack, counted, collected")
	expect(int(meet_of(w).records)==0 and not meet_of(w).participants.has("out"),"…and not a meet record")
	# ina back inside WATERS: recorded.
	stand(w,"ina",FISH_SPOT)
	var core:=person_core(w,"ina")
	var r3:=cast_and_catch(w,"ina",CAST,"","Joined, inside WATERS")
	expect(bool(r3.ok) and int(meet_of(w).records)==1 and same(person_core(w,"ina"),core),"Joined inside WATERS: recorded, player untouched ("+msg(r3)+")")
	# Leaving keeps the cast line; a pending cast after leaving is ordinary.
	ok(w,"ina","fish_start",CAST,"","ina casts")
	var cast:Dictionary=pl(w,"ina").fishing.duplicate()
	ok(w,"ina","fish_meet_leave",Meet.SIGN,"","ina leaves with the line out")
	expect(same(pl(w,"ina").fishing,cast),"Leaving leaves the cast line alone")
	w.state.time=float(cast.ready)+1.0
	var r4:=act(w,"ina","fish_catch",CAST)
	expect(bool(r4.ok) and msg(r4).contains("種子攤") and int(meet_of(w).records)==1,"After leaving, the catch is ordinary ("+msg(r4)+")")

# 7. 8 currently-joined players; 9th refused; leave frees a slot; rejoin keeps counts.
func test_cap_and_rejoin()->void:
	var tokens:=[]
	for i in range(10):tokens.append("cap%d"%i)
	var w:=make_world(tokens)
	ok(w,"cap0","fish_meet_start",Meet.SIGN,"0","cap0 starts")
	for i in range(1,8):ok(w,tokens[i],"fish_meet_join",Meet.SIGN,"1","%s joins"%tokens[i])
	expect(view(w,"cap0").joined_count==8,"Eight joined")
	expect_rejected(w,"cap8","fish_meet_join",Meet.SIGN,"1","9th joiner",Meet.FULL%8)
	cast_and_catch(w,"cap1",CAST,"","cap1 catches")
	expect(int(entry_of(w,"cap1").caught)==1,"cap1 recorded one")
	ok(w,"cap1","fish_meet_leave",Meet.SIGN,"","cap1 leaves")
	expect(view(w,"cap1").joined==false and int(entry_of(w,"cap1").caught)==1 and view(w,"cap1").caught==1,"Leaver keeps the catch count")
	ok(w,"cap8","fish_meet_join",Meet.SIGN,"1","9th joins after a leave")
	expect_rejected(w,"cap1","fish_meet_join",Meet.SIGN,"1","Leaver cannot rejoin while 8 are in",Meet.FULL%8)
	ok(w,"cap2","fish_meet_leave",Meet.SIGN,"","cap2 leaves")
	ok(w,"cap1","fish_meet_join",Meet.SIGN,"1","cap1 rejoins the same round")
	expect(int(entry_of(w,"cap1").caught)==1 and entry_of(w,"cap1").joined==true and meet_of(w).participants.size()==9,"Rejoin reuses the entry (caught 1), roster 9")
	var v:=view(w,"cap1")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==VIEW_KEYS,"View has exactly the documented keys (%s)"%str(keys))
	expect(v.participants.size()==9 and v.species_names.size()==4 and v.species_names[0].id=="carp" and v.species_names[0].name=="圓肚鯽魚","View lists participants and named species in fixed order")
	var mine:=0
	for e:Dictionary in v.participants:
		if e.me:mine+=1
	expect(mine==1 and not JSON.stringify(v).contains("\"cap1\":"),"View marks me once and is not keyed by token")

# 8. Timeout settlement: zero-catch, leavers, rejoiners and offline players paid once.
func test_timeout_and_payment()->void:
	var tokens:=["ta","tb","tc","td","te"]
	var w:=make_world(tokens)
	var before:=cores(w,tokens)
	ok(w,"ta","fish_meet_start",Meet.SIGN,"0","ta starts")
	for t in ["tb","tc","td","te"]:ok(w,t,"fish_meet_join",Meet.SIGN,"1","%s joins"%t)
	cast_and_catch(w,"ta",CAST,"","ta catch 1")
	cast_and_catch(w,"tb",CAST,"standard","tb catch 1")
	ok(w,"tb","fish_meet_leave",Meet.SIGN,"","tb leaves")
	ok(w,"tc","fish_meet_leave",Meet.SIGN,"","tc leaves")
	ok(w,"tc","fish_meet_join",Meet.SIGN,"1","tc rejoins")
	w.active_tokens.erase("td") # td goes offline mid-round
	expect(int(meet_of(w).records)==2 and Meet.species_count(meet_of(w).species)<4,"Two records, fewer than four species")
	w.state.time=float(meet_of(w).ends)-0.5
	w.step(0.25,true)
	expect(meet_of(w).active==true and entry_of(w,"td").joined==false,"Still active just before the deadline; offline td dropped by step")
	w.state.time=float(meet_of(w).ends)
	w.step(0.25,true)
	var meet:=meet_of(w)
	expect(meet.active==false and meet.last.reason=="time" and int(meet.last.records)==2 and int(meet.last.tickets)==1 and int(meet.last.players)==5,"Timeout with <4 species: 1 ticket each, 5 players (%s)"%str(meet.last))
	for t:String in tokens:
		var best:=2
		expect(same(record_of(w,t),{"tickets":1,"rounds":1,"best":best,"paid_round":1}),"%s paid exactly once (%s)"%[t,str(record_of(w,t))])
		expect(entry_of(w,t).joined==false,"%s is out after settlement"%t)
	expect(int(entry_of(w,"te").caught)==0 and int(record_of(w,"te").tickets)==1,"Zero-catch participant te still gets exactly 1 ticket")
	expect(same(cores(w,tokens),before),"Every participant's player record identical after the timeout")
	for i in range(3):w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==1 and int(record_of(w,t).rounds)==1,"%s not paid again by later steps"%t)
	# Re-settle guard: force the finished round active again past its end.
	(w.state.fish_meet as Dictionary).active=true
	w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==1 and int(record_of(w,t).paid_round)==1,"%s: paid_round blocks a re-settlement of round 1"%t)
	# Round 2: 8 records covering all four species, timeout -> 2 tickets.
	w.active_tokens["td"]=true
	w.state.time=float(w.state.fish_meet.ready)
	ok(w,"tc","fish_meet_start",Meet.SIGN,"1","Round 2")
	ok(w,"td","fish_meet_join",Meet.SIGN,"2","td joins round 2 (zero catches)")
	for i in range(8):cast_and_catch(w,"tc",CAST,"","Round 2 catch %d"%i)
	expect(Meet.species_count(meet_of(w).species)==4 and int(meet_of(w).records)==8,"Eight records cover all four species")
	w.state.time=float(w.state.fish_meet.ends)
	w.step(0.5,true)
	expect(meet_of(w).active==false and int(meet_of(w).last.tickets)==2 and int(meet_of(w).last.species)==4,"All-species timeout: 2 tickets")
	expect(same(record_of(w,"tc"),{"tickets":3,"rounds":2,"best":8,"paid_round":2}) and same(record_of(w,"td"),{"tickets":3,"rounds":2,"best":8,"paid_round":2}),"tc and td +2 tickets for round 2")
	expect(same(record_of(w,"ta"),{"tickets":1,"rounds":1,"best":2,"paid_round":1}),"ta (not in round 2) unchanged")
	expect(view(w,"td").tickets==3 and view(w,"td").rounds==2 and view(w,"td").best==8,"View shows own tickets/rounds/best")
	expect(same(cores(w,tokens),before),"Player records still identical after round 2")
	# Separate from harvest relay tickets.
	expect(not pl(w,"tc").has("harvest_relay"),"Fish meet tickets are not harvest relay tickets")
	# Ticket counter cap.
	(pl(w,"tc").fish_meet as Dictionary).tickets=Meet.MAX_TICKETS
	w.state.time=float(w.state.fish_meet.ready)
	ok(w,"tc","fish_meet_start",Meet.SIGN,"2","Round 3")
	w.state.time=float(w.state.fish_meet.ends)
	w.step(0.5,true)
	expect(int(record_of(w,"tc").tickets)==Meet.MAX_TICKETS and int(record_of(w,"tc").rounds)==3,"Tickets saturate at MAX_TICKETS")

# 9. Disconnect and travel drop the entry; the hook is idempotent.
func test_disconnect_and_travel()->void:
	var w:=make_world(["dia","dib"])
	var before:=cores(w,["dia","dib"])
	ok(w,"dia","fish_meet_start",Meet.SIGN,"0","dia starts")
	ok(w,"dib","fish_meet_join",Meet.SIGN,"1","dib joins")
	ok(w,"dia","fish_start",CAST,"","dia casts")
	var cast:Dictionary=pl(w,"dia").fishing.duplicate()
	expect(w.fish_meet_disconnect("dia"),"Disconnect hook drops dia")
	expect(entry_of(w,"dia").joined==false and same(pl(w,"dia").fishing,cast),"dia is out; the cast line is left alone")
	expect(not w.fish_meet_disconnect("dia"),"Second disconnect changes nothing")
	expect(not w.fish_meet_disconnect("nobody"),"Unknown token changes nothing")
	pl(w,"dia").erase("fishing")
	ok(w,"dia","fish_meet_join",Meet.SIGN,"1","dia rejoins after reconnecting")
	pl(w,"dib").region=World.REGIONS.LANYANG
	expect(w.step(0.5,true),"Step reports the travel drop")
	expect(entry_of(w,"dib").joined==false,"Travelling away drops dib")
	pl(w,"dib").region=World.REGIONS.HOME
	w.active_tokens.erase("dia")
	w.step(0.5,true)
	expect(entry_of(w,"dia").joined==false,"Offline (no hook) is dropped by step")
	var quiet:=var_to_bytes(w.state.fish_meet)
	w.step(0.5,true)
	expect(var_to_bytes(w.state.fish_meet)==quiet,"Dropping is not repeated")
	expect(same(cores(w,["dia","dib"]),before),"Player records identical after disconnect and travel")

# 10. Request replay returns the receipt without a second record.
func test_replay()->void:
	var w:=make_world(["rep"])
	ok(w,"rep","fish_meet_start",Meet.SIGN,"0","Start")
	ok(w,"rep","fish_start",CAST,"","Cast")
	w.state.time=float(pl(w,"rep").fishing.ready)+1.0
	var r:=act(w,"rep","fish_catch",CAST,"","replay-catch")
	expect(bool(r.ok) and int(meet_of(w).records)==1,"Catch with a fixed request id records once")
	ok(w,"rep","fish_start",CAST,"","Cast again")
	w.state.time=float(pl(w,"rep").fishing.ready)+1.0
	var again:=act(w,"rep","fish_catch",CAST,"","replay-catch")
	expect(again==r and int(meet_of(w).records)==1 and pl(w,"rep").has("fishing"),"Replayed catch returns the receipt and records nothing")

## Tamper cases. `sam` holds a paid record (round 1) in both fixtures; in the active
## fixture round 2 is running with sam and uma, sam having caught one fish.
static func tampered(good:Dictionary,label:String)->Dictionary:
	var s:Dictionary=good.duplicate(true)
	var meet:Dictionary=s.fish_meet
	var people:Dictionary=meet.participants
	var paid:Dictionary=s.players.sam
	var first:String="sam"
	var k0:=Meet.kind_at(int(meet.round),0)
	match label:
		"meet is an array":s.fish_meet=[]
		"meet without picnic":s.picnic=false
		"negative round":meet.round=-1
		"active not bool":meet.active=1
		"records over goal":meet.records=13
		"index differs from records":meet.index=int(meet.records)+1
		"ends not started+300":meet.ends=float(meet.started)+180.0
		"started in the future":
			meet.started=float(s.time)+500.0
			meet.ends=float(meet.started)+300.0
		"unknown species key":meet.species.trout=0
		"species missing key":meet.species.erase("loach")
		"species count too high":meet.species[k0]=int(meet.species[k0])+1
		"species swapped":
			meet.species[k0]=int(meet.species[k0])-1
			var other:="loach" if k0!="loach" else "carp"
			meet.species[other]=int(meet.species[other])+1
		"species fractional":meet.species[k0]=0.5
		"caught sum differs":people[first].caught=int(people[first].caught)+1
		"negative caught":people[first].caught=-1
		"fractional caught":people[first].caught=0.5
		"joined not bool":people[first].joined=1
		"participant not a player":people["ghost-token"]={"caught":0,"joined":false}
		"entry extra field":people[first].mood=1
		"entry missing field":people[first].erase("joined")
		"extra root field":meet.mood=1
		"missing root field":meet.erase("ready")
		"last tickets wrong":meet.last.tickets=int(meet.last.tickets)+1
		"last species wrong":meet.last.species=int(meet.last.species)+1
		"last reason bogus":meet.last.reason="magic"
		"last round mismatch":meet.last.round=int(meet.last.round)+1
		"goal reason with fewer records":meet.last.reason="goal"
		"ready mismatch":meet.ready=float(meet.ready)+5.0
		"joined while inactive":people[first].joined=true
		"paid record while active":paid.fish_meet.paid_round=int(meet.round)
		"record paid_round ahead":paid.fish_meet.paid_round=int(meet.round)+1
		"record tickets below rounds":paid.fish_meet.tickets=0
		"record tickets above three per round":paid.fish_meet.tickets=int(paid.fish_meet.rounds)*3+1
		"record extra field":paid.fish_meet.bonus=1
		"record missing for a paid participant":paid.erase("fish_meet")
		"record is a string":paid.fish_meet="ticket"
		"record without a round":s.erase("fish_meet")
		"record best over goal":paid.fish_meet.best=13
		"last records differ from the settled round":meet.last.records=int(meet.last.records)+1
	return s

# 11. Save -> reload equality (mid-round and settled), legacy saves, schema tampering.
func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=make_world(["sam","tia","uma"])
	w.save_path=path
	# Round 1 times out with 2 records (sam 1, tia 1); round 2 is active mid-way.
	ok(w,"sam","fish_meet_start",Meet.SIGN,"0","sam starts")
	ok(w,"tia","fish_meet_join",Meet.SIGN,"1","tia joins")
	cast_and_catch(w,"sam",CAST,"","sam catch")
	cast_and_catch(w,"tia",CAST,"standard","tia catch")
	w.state.time=float(meet_of(w).ends)+0.25
	w.step(0.5,true)
	expect(meet_of(w).active==false and int(meet_of(w).last.records)==2,"Round 1 finished by time")
	expect(w.save(),"World saves after settlement")
	var settled:=World.new()
	expect(settled.load_world(path),"Fresh world reloads the settled save")
	if failures>0:return
	expect(same(meet_of(settled),meet_of(w)),"Settled round survives reload (canonical)")
	for token in ["sam","tia","uma"]:
		expect(same(record_of(settled,token),record_of(w,token)),"%s record survives reload (settled)"%token)
		expect(same(view(settled,token),view(w,token)),"%s view identical after reload (settled)"%token)
	var finished_state:Dictionary=w.state.duplicate(true)
	w.state.time=float(w.state.fish_meet.ready)+3.5
	ok(w,"uma","fish_meet_start",Meet.SIGN,"1","uma starts round 2")
	ok(w,"sam","fish_meet_join",Meet.SIGN,"2","sam joins round 2")
	cast_and_catch(w,"sam",CAST,"","sam catch round 2")
	expect(w.save(),"World saves mid-round")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the mid-round save")
	if failures>0:return
	expect(same(meet_of(restored),meet_of(w)),"Round state survives reload (canonical)")
	for token in ["sam","tia","uma"]:
		expect(same(record_of(restored,token),record_of(w,token)),"%s record survives reload"%token)
		expect(same(pl(restored,token).inventory,pl(w,token).inventory) and int(pl(restored,token).coins)==int(pl(w,token).coins) and int(pl(restored,token).get("fish_caught",0))==int(pl(w,token).get("fish_caught",0)),"%s inventory, coins and fish_caught survive reload"%token)
		expect(same(view(restored,token),view(w,token)),"%s view identical after reload"%token)
	var rr:=meet_of(restored)
	expect(typeof(rr.round)==TYPE_INT and typeof(rr.records)==TYPE_INT and typeof(rr.index)==TYPE_INT and typeof(rr.species.carp)==TYPE_INT and typeof(rr.last.tickets)==TYPE_INT and typeof(record_of(restored,"sam").tickets)==TYPE_INT and typeof(rr.participants.sam.caught)==TYPE_INT,"Validation normalizes reloaded numbers to ints")
	# Reloaded active round keeps recording and settles on the next step.
	restored.active_tokens={"sam":true,"tia":true,"uma":true}
	stand(restored,"sam",FISH_SPOT)
	cast_and_catch(restored,"sam",CAST,"","sam catches after reload")
	expect(int(meet_of(restored).records)==2 and same(meet_of(restored).species,Meet.species_after(2,2)),"Reloaded round keeps the deterministic sequence")
	restored.state.time=float(restored.state.fish_meet.ends)
	restored.step(0.5,true)
	expect(meet_of(restored).active==false and int(record_of(restored,"uma").paid_round)==2 and int(record_of(restored,"sam").paid_round)==2 and int(record_of(restored,"tia").paid_round)==1,"Reloaded round settles; tia (round 1 only) untouched")
	# Legacy save without the fields.
	var base:Dictionary=w.state.duplicate(true)
	var old:Dictionary=base.duplicate(true)
	old.erase("fish_meet")
	for token in ["sam","tia","uma"]:(old.players[token] as Dictionary).erase("fish_meet")
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without fish_meet fields loads")
	expect(not legacy.state.has("fish_meet") and not pl(legacy,"sam").has("fish_meet"),"Loading does not invent fish_meet fields")
	expect(view(legacy,"sam").round==0 and view(legacy,"sam").can_start==true,"Legacy world starts fresh")
	expect(write_fixture(fixture,base),"Write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(meet_of(control),meet_of(w)),"Control fixture (active round) loads")
	expect(write_fixture(fixture,finished_state),"Write finished control fixture")
	expect(World.new().load_world(fixture),"Control fixture (finished round) loads")
	if failures>0:return
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var active_labels:=["meet is an array","meet without picnic","negative round","active not bool","records over goal","index differs from records",
		"ends not started+300","started in the future","unknown species key","species missing key","species count too high","species swapped","species fractional",
		"caught sum differs","negative caught","fractional caught","joined not bool","participant not a player","entry extra field","entry missing field",
		"extra root field","missing root field","last tickets wrong","last species wrong","last reason bogus","last round mismatch","goal reason with fewer records","ready mismatch",
		"paid record while active","record paid_round ahead","record tickets below rounds","record tickets above three per round","record extra field",
		"record is a string","record without a round","record best over goal"]
	var finished_labels:=["joined while inactive","record missing for a paid participant","last tickets wrong","caught sum differs","record paid_round ahead","last records differ from the settled round","species count too high"]
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
	expect(count>=25,"At least 25 tamper cases (%d)"%count)

# 12. Snapshot privacy: hashed participants, own view only to the owner.
func test_snapshot_privacy()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=make_world([PRIVATE_A,PRIVATE_B])
	var w=session.world
	ok(w,PRIVATE_A,"fish_meet_start",Meet.SIGN,"0","Alpha starts")
	ok(w,PRIVATE_B,"fish_meet_join",Meet.SIGN,"1","Beta joins")
	cast_and_catch(w,PRIVATE_A,CAST,"","Alpha catches")
	ok(w,PRIVATE_A,"fish_meet_leave",Meet.SIGN,"","Alpha leaves")
	ok(w,PRIVATE_A,"fish_meet_join",Meet.SIGN,"1","Alpha rejoins")
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	var id_a:=PRIVATE_A.sha256_text().left(16)
	var id_b:=PRIVATE_B.sha256_text().left(16)
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains(PRIVATE_A) and not text.contains(PRIVATE_B),"public_state(%s) has no raw token"%region)
		var fm:Dictionary=public.get("fish_meet",{})
		expect(fm.get("participants",{}).keys().size()==2 and fm.participants.has(id_a) and fm.participants.has(id_b),"public_state(%s) participants keyed by public ids"%region)
		var clean:=true
		for id in public.get("players",{}):
			if (public.players[id] as Dictionary).has("fish_meet"):clean=false
		expect(clean,"public_state(%s) players carry no fish_meet record"%region)
	var fm:Dictionary=session.public_state("home").fish_meet
	expect(same(fm.participants[id_a],{"name":"fishme","caught":1,"joined":true}),"Alpha's public entry shows name and catches (%s)"%str(fm.participants[id_a]))
	expect(int(fm.round)==1 and fm.active==true and int(fm.goal)==12 and int(fm.records)==1 and same(fm.species,Meet.species_after(1,1)) and int(fm.species_count)==1,"Public round summary")
	var keys:Array=fm.keys()
	keys.sort()
	expect(keys==["active","ends","goal","last","participants","ready","records","round","seconds_left","species","species_count","started"],"Public projection keys (%s)"%str(keys))
	expect(w.state.fish_meet.participants.has(PRIVATE_A),"Publishing does not rewrite the live record")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("own_fish_meet") and same(snap.own_fish_meet,w.fish_meet_view(PRIVATE_A)),"own_fish_meet equals the recipient's own view")
	expect(snap.own_fish_meet.caught==1 and snap.own_fish_meet.joined==true,"own_fish_meet shows the recipient's catches")
	expect(snap.has("fish_meet") and snap.has("own_harvest") and snap.has("harvest_relay"),"Snapshot still carries the harvest relay fields")
	expect(not JSON.stringify(snap).contains(PRIVATE_A) and not JSON.stringify(snap).contains(PRIVATE_B),"Snapshot carries no raw token")
	session.world=null
	session.queue_free()
	await process_frame
