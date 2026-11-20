extends SceneTree
## B5 石殼蟹 integration test through the REAL World.act path (headless, in-process).
##
## Fixtures are DISCLOSED:
##  - players are placed by writing region/x/y;
##  - state.picnic, state.world_mode and state.mine_depths are seeded by writing them;
##  - w.active_tokens[token]=true marks the test players as connected (Session does this);
##  - repair materials / a full gold_ore stack / a pick are produced by writing the inventory;
##  - "legacy content on a crab cell" is produced by copying a really-built object into the
##    mine_5 layer (the new protection refuses building there through the normal path);
##  - a failing save is produced by pointing save_path below a file.
## World time is advanced ONLY with the real World.step(dt,true,false) in 0.5 s ticks.
## Everything else goes through World.act, World.move_player, World.add_player, World.save /
## load_world, SaveSchema.validate and Session._send_snapshot.
## The adventure wait cycle is read from host memory with w.get("_crab_watch") (read-only).

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Crab=preload("res://scripts/stone_shelled_crab.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const ALPHA:="crab-world-alpha-token"
const BETA:="crab-world-beta-token"
const FIELD:="stone_crab"
const CAP:=1000000000
## Within REACH 1.8 of the cart, the crab and its resting cell at once.
const SPOT:=Vector2i(46,23)
## Inside the generic 3.2 reach but beyond REACH 1.8 of every crab cell.
const SPOT_FAR:=Vector2i(43,24)
const PENALTY_KEYS:=["damage","hp","health","score","timer","penalty","fail","failed","lives","deadline","attempts"]
var checks:=0
var failures:=0
var serial:=0
var files:Array=[]

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL "+message)

func _initialize() -> void:
	check_fixture_assumptions()
	check_gates()
	for mode in ["life","adventure"]:
		check_life_route(mode)
	check_materials()
	check_reward_cap()
	check_adventure_route()
	check_players_independent()
	check_save_round_trip()
	check_failed_save()
	check_schema()
	check_collision()
	check_legacy_occupied()
	check_legacy_position()
	check_base_mine_actions()
	check_snapshot_privacy()
	for file in files:
		for suffix in ["",".bak",".tmp",".bak.staged"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("STONE_SHELLED_CRAB_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ----------------------------------------------------------------- helpers --

func new_world(mode:String,unlocked:int=5,tokens:Array=[ALPHA,BETA],region:String=Crab.REGION) -> World:
	var w:=World.new()
	var path:String=OS.get_environment("TEMP").path_join("stone-crab-world-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	files.append(path)
	w.save_path=path
	w.state["picnic"]=true
	if mode=="adventure":w.state["world_mode"]="adventure"
	w.state["mine_depths"]={"unlocked":unlocked,"ready":{},"pumped":24 if unlocked>=3 else 0,"hoist":false}
	for token:String in tokens:
		w.add_player(token,token.left(12))
		w.active_tokens[token]=true
		place(w,token,region,SPOT if region==Crab.REGION else Mines.REST+Vector2i.UP)
	return w

func place(w:World,token:String,region:String,cell:Vector2i) -> void:
	var player:Dictionary=w.state.players[token]
	player["region"]=region
	player["x"]=cell.x+0.5
	player["y"]=cell.y+0.5

func pos(w:World,token:String) -> Vector2:
	return Vector2(float(w.state.players[token].x),float(w.state.players[token].y))

func stock(w:World,token:String,plank:int=2,joint:int=1) -> void:
	w.state.players[token].inventory["plank"]=plank
	w.state.players[token].inventory["copper_joint"]=joint

func held(w:World,token:String,item:String) -> int:
	return int(w.state.players[token].inventory.get(item,0))

func act(w:World,token:String,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"crab-test-%d"%serial,action,cell,extra)

func watch(w:World,token:String) -> Dictionary:
	var all=w.get("_crab_watch")
	if not all is Dictionary:return {}
	var mine=all.get(token,{})
	return mine if mine is Dictionary else {}

## Acts once, then replays the same request id: identical result, nothing changes.
func act_twice(w:World,token:String,action:String,cell:Vector2i,label:String,extra:String="") -> Dictionary:
	serial+=1
	var id:="crab-test-%d"%serial
	var first:Dictionary=w.act(token,id,action,cell,extra)
	var copy:Dictionary=first.duplicate(true)
	var after:Dictionary=w.state.duplicate(true)
	var cycle:Dictionary=watch(w,token).duplicate(true)
	var again:Dictionary=w.act(token,id,action,cell,extra)
	expect(again==copy,"%s: same request_id replays the identical result (first=%s replay=%s)"%[label,brief(copy),brief(again)])
	expect(w.state==after and watch(w,token)==cycle,"%s: replay changes no state and no wait cycle (no double spend / reward)"%label)
	var problem:=shape_problem(first)
	expect(problem.is_empty(),"%s: result shape (%s) got %s"%[label,problem,str(first)])
	if first.get("ok",false):expect(w.state.players[token].receipts.get(id)==copy,"%s: receipt stored"%label)
	return first

func brief(result:Dictionary) -> String:
	return "{ok=%s msg=%s crab=%s}"%[str(result.get("ok")),str(result.get("message","")).left(24),str(result.get("crab","<none>"))]

func payload(result:Dictionary) -> Dictionary:
	var c=result.get("crab")
	return c if c is Dictionary else {}

func outcome(result:Dictionary) -> String:
	return str(payload(result).get("outcome","<no crab payload>"))

func cues(result:Dictionary) -> Array:
	var value=payload(result).get("cues")
	return value if value is Array else []

func shape_problem(result:Dictionary) -> String:
	if not result.get("ok") is bool:return "ok is not a bool"
	if not result.get("message") is String or str(result.message).is_empty():return "message missing"
	var c:=payload(result)
	if c.size()!=7:return "crab payload has %d fields"%c.size()
	if not c.get("outcome") is String:return "outcome"
	if not c.get("stage") is int or int(c.stage)<0 or int(c.stage)>2:return "stage"
	if not c.get("claimed") is bool:return "claimed"
	if not c.get("cues") is Array:return "cues"
	if not c.get("missing") is Dictionary:return "missing"
	if not c.get("open_at") is float or not c.get("close_at") is float:return "open_at/close_at"
	for cue in c.cues:
		if not (cue in Crab.CUES or cue in Crab.ADVENTURE_CUES):return "unknown cue %s"%str(cue)
	for field in PENALTY_KEYS:
		if result.has(field) or c.has(field):return "penalty field %s"%field
	return ""

func record(w:World,token:String) -> Dictionary:
	var value=w.state.players[token].get(FIELD)
	return value if value is Dictionary else Crab.fresh()

func rec(stage:int,claimed:bool) -> Dictionary:
	return {"stage":stage,"claimed":claimed}

func mirrors(result:Dictionary,want:Dictionary) -> bool:
	var c:=payload(result)
	return c.get("stage") is int and int(c.stage)==int(want.stage) and c.get("claimed") is bool and c.claimed==want.claimed

func advance(w:World,seconds:float,label:String) -> bool:
	var start:=float(w.state.time)
	var left:=seconds
	while left>0.0001:
		var dt:=minf(0.5,left)
		if not w.step(dt,true,false):
			expect(false,"%s: real World.step failed (%s)"%[label,str(w.step_error)])
			return false
		left-=dt
	var fine:=absf(float(w.state.time)-(start+seconds))<0.0001
	expect(fine,"%s: real World.step advanced state.time by %.1f"%[label,seconds])
	return fine

## A refusal: ok false, the wanted outcome, and nothing at all changes.
func refused(w:World,token:String,action:String,cell:Vector2i,want:String,label:String,extra:String="") -> Dictionary:
	var before:Dictionary=w.state.duplicate(true)
	var cycle:Dictionary=watch(w,token).duplicate(true)
	var result:=act(w,token,action,cell,extra)
	expect(result.get("ok",true)==false and result.get("message") is String,"%s: %s is refused (got %s)"%[label,action,brief(result)])
	if not want.is_empty():expect(outcome(result)==want,"%s: %s outcome %s (got %s)"%[label,action,want,brief(result)])
	expect(w.state==before,"%s: refused %s changes no state (bag, record, receipts, journal)"%[label,action])
	expect(watch(w,token)==cycle,"%s: refused %s leaves the wait cycle alone"%[label,action])
	for field in PENALTY_KEYS:
		if result.has(field) or payload(result).has(field):expect(false,"%s: refused %s carries penalty field %s"%[label,action,field])
	return result

func valid(state:Dictionary) -> bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func on_disk(w:World) -> Dictionary:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	return parsed if parsed is Dictionary else {}

func reopen(w:World,label:String) -> World:
	var again:=World.new()
	var loaded:=again.load_world(w.save_path)
	expect(loaded and not again.recovered_from_backup and again.state.players.has(ALPHA),"%s: save loads cleanly"%label)
	if not loaded or not again.state.players.has(ALPHA):return null
	for token:String in again.state.players:again.active_tokens[token]=true
	return again

func in_region(w:World,region:String,probe:Callable):
	w.switch_region(region)
	var value=probe.call()
	w.switch_region(World.REGIONS.HOME)
	return value

func can_stand_at(w:World,cell:Vector2i) -> bool:
	return in_region(w,Crab.REGION,func():return w.can_stand(Vector2(cell)+Vector2(0.5,0.5)))

func protected_at(w:World,cell:Vector2i) -> bool:
	return in_region(w,Crab.REGION,func():return w.protected(cell))

func walk(w:World,token:String,target:Vector2) -> bool:
	for tick in 500:
		var player:Dictionary=w.state.players[token]
		var delta:Vector2=target-Vector2(player.x,player.y)
		if delta.length()<0.2:break
		w.move_player(token,delta.normalized() if delta.length()>0.18 else delta,0.05)
	w.switch_region(World.REGIONS.HOME)
	return pos(w,token).distance_to(target)<0.3

## Life route to the wanted stage through real actions.
func reach(w:World,token:String,stage:int,claim:bool=false) -> void:
	place(w,token,Crab.REGION,SPOT)
	if stage>=1:act(w,token,Crab.SURVEY_ACTION,Crab.CRAB)
	if stage>=2:
		stock(w,token)
		act(w,token,Crab.REPAIR_ACTION,Crab.CART)
	if claim:act(w,token,Crab.CLAIM_ACTION,Crab.CRAB_REST)

# ------------------------------------------------------------------ checks --

func check_fixture_assumptions() -> void:
	var tag:="[fixture]"
	var w:=new_world("life",5,[ALPHA])
	expect(w.player_region(ALPHA)==Crab.REGION and pos(w,ALPHA)==Vector2(SPOT)+Vector2(0.5,0.5),tag+" alpha stands on (46,23) in mine_5")
	expect(can_stand_at(w,SPOT) and can_stand_at(w,SPOT_FAR),tag+" both test spots are standable")
	for cell:Vector2i in Crab.footprint():
		expect(Crab.near(Vector2(SPOT)+Vector2(0.5,0.5),cell),"%s SPOT is within REACH of %s"%[tag,str(cell)])
		expect(not Crab.near(Vector2(SPOT_FAR)+Vector2(0.5,0.5),cell) and (Vector2(SPOT_FAR)+Vector2(0.5,0.5)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2+1.5,"%s SPOT_FAR is beyond REACH of %s"%[tag,str(cell)])
	expect(not w.state.players[ALPHA].has(FIELD),tag+" a new player has no crab record")
	expect(in_region(w,Crab.REGION,func():return w.crab_available()),tag+" the encounter is available in an opened, empty B5")
	expect(not in_region(w,"mine_4",func():return w.crab_available()) and not w.crab_available(),tag+" not available on B4 or at home")
	expect(w.save() and valid(on_disk(w).duplicate(true)),tag+" the seeded fixture world is a schema-valid save")

func check_gates() -> void:
	var tag:="[gate]"
	# Legal pre-unlock state: B5 closed, player on B4.
	var w:=new_world("life",4,[ALPHA],"mine_4")
	stock(w,ALPHA,5,5)
	expect(w.save() and valid(on_disk(w).duplicate(true)),tag+" legal pre-unlock fixture (B4 open, player on B4)")
	# From a legal B4 position the cells are beyond the ordinary 3.2 reach, so the refusal is the
	# generic one; the "unavailable" outcome is asserted on the in-memory-only state below.
	for action:String in Crab.ACTIONS:
		refused(w,ALPHA,action,Crab.CART if action==Crab.REPAIR_ACTION else Crab.CRAB,"",tag+" on B4 before B5 opens")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"",tag+" on B4 before B5 opens","wait")
	expect(not w.state.players[ALPHA].has(FIELD) and held(w,ALPHA,"plank")==5 and held(w,ALPHA,"copper_joint")==5,tag+" no record written, no material spent")
	place(w,ALPHA,"mine_4",Mines.DOWN+Vector2i.UP)
	var down:=act(w,ALPHA,"mine_travel",Mines.DOWN,Crab.REGION)
	expect(down.get("ok",true)==false and w.player_region(ALPHA)=="mine_4",tag+" mine_travel to the unopened B5 is refused")
	# Impossible-by-schema position (in memory only): standing in mine_5 with B5 closed.
	place(w,ALPHA,Crab.REGION,SPOT)
	for action:String in Crab.ACTIONS:
		refused(w,ALPHA,action,Crab.CART if action==Crab.REPAIR_ACTION else Crab.CRAB,"unavailable",tag+" [in-memory only] inside mine_5 while locked")
	expect(can_stand_at(w,Crab.CART) and not protected_at(w,Crab.CART),tag+" [in-memory only] while locked the cart is neither solid nor reserved")
	# No picnic yet.
	var early:=new_world("life",5,[ALPHA])
	early.state["picnic"]=false
	refused(early,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,"unavailable",tag+" [in-memory only] before the picnic")
	# Opened world: wrong floor with the same cave shape, wrong cells, bad extras, too far.
	var open:=new_world("life",5,[ALPHA])
	stock(open,ALPHA)
	place(open,ALPHA,"mine_2",SPOT)
	refused(open,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,"unavailable",tag+" on B2")
	place(open,ALPHA,Crab.REGION,SPOT)
	refused(open,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,"invalid",tag+" survey with an extra","x")
	refused(open,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"invalid",tag+" repair with an extra","plank")
	refused(open,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB,"invalid",tag+" claim with an extra","1")
	refused(open,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"invalid",tag+" shell with no extra")
	refused(open,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"invalid",tag+" shell with a wrong extra","strike")
	refused(open,ALPHA,Crab.SURVEY_ACTION,Crab.CART,"far",tag+" survey aimed at the cart")
	refused(open,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB_REST,"far",tag+" survey aimed at the resting cell before the repair")
	refused(open,ALPHA,Crab.REPAIR_ACTION,Crab.CRAB,"far",tag+" repair aimed at the crab")
	refused(open,ALPHA,Crab.CLAIM_ACTION,Crab.CART,"far",tag+" claim aimed at the cart")
	place(open,ALPHA,Crab.REGION,SPOT_FAR)
	refused(open,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,"",tag+" survey from beyond REACH")
	refused(open,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"",tag+" repair from beyond REACH")
	expect(not open.state.players[ALPHA].has(FIELD),tag+" none of the refusals wrote a record")

func check_life_route(mode:String) -> void:
	var tag:="[life/%s]"%mode
	var w:=new_world(mode,5,[ALPHA])
	var base_bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	refused(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"too_early",tag+" repair before looking, no materials")
	stock(w,ALPHA,3,2)
	refused(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"too_early",tag+" repair before looking, with materials")
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB,"waiting",tag+" claim before anything")
	expect(not w.state.players[ALPHA].has(FIELD),tag+" refusals wrote no record")
	var look:=act_twice(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,tag+" first look")
	expect(look.get("ok",false)==true and outcome(look)=="look" and mirrors(look,rec(1,false)) and cues(look)==[Crab.CUE_CLACK],"%s first look -> stage 1 with the clack cue (got %s)"%[tag,brief(look)])
	expect(record(w,ALPHA)==rec(1,false) and w.state.players[ALPHA].has(FIELD),tag+" record stage 1 stored")
	var again:=act_twice(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,tag+" second look")
	expect(again.get("ok",false)==true and outcome(again)=="alert" and record(w,ALPHA)==rec(1,false),tag+" looking again is free and changes nothing")
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB,"waiting",tag+" claim at stage 1")
	expect(held(w,ALPHA,"plank")==3 and held(w,ALPHA,"copper_joint")==2,tag+" nothing spent so far")
	var fix:=act_twice(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,tag+" repair")
	expect(fix.get("ok",false)==true and outcome(fix)=="repair" and mirrors(fix,rec(2,false)),"%s repair succeeds (got %s)"%[tag,brief(fix)])
	expect(cues(fix)==[Crab.CUE_HAMMER,Crab.CUE_WHEEL,Crab.CUE_SCUTTLE],tag+" repair carries hammer, wheel and scuttle cues")
	expect(held(w,ALPHA,"plank")==1 and held(w,ALPHA,"copper_joint")==1,"%s exactly plank -2 and copper_joint -1 (plank %d joint %d)"%[tag,held(w,ALPHA,"plank"),held(w,ALPHA,"copper_joint")])
	expect(record(w,ALPHA)==rec(2,false),tag+" record stage 2, unclaimed")
	refused(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"settled",tag+" a second repair")
	expect(held(w,ALPHA,"plank")==1 and held(w,ALPHA,"copper_joint")==1,tag+" the second repair spent nothing")
	refused(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB,"far",tag+" the crab has left its old cell")
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB,"far",tag+" claim aimed at the old cell")
	var rest:=act(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB_REST)
	expect(rest.get("ok",false)==true and outcome(rest)=="settled",tag+" looking at the resting crab")
	var gold:=held(w,ALPHA,Crab.REWARD_ITEM)
	var gift:=act_twice(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,tag+" claim")
	expect(gift.get("ok",false)==true and outcome(gift)=="claim" and mirrors(gift,rec(2,true)) and cues(gift)==[Crab.CUE_CHIME],"%s claim succeeds (got %s)"%[tag,brief(gift)])
	expect(held(w,ALPHA,Crab.REWARD_ITEM)==gold+Crab.REWARD_COUNT and Crab.REWARD_ITEM=="gold_ore" and Crab.REWARD_COUNT==2,tag+" gold_ore +2 exactly once")
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"claimed",tag+" a second claim")
	expect(held(w,ALPHA,Crab.REWARD_ITEM)==gold+Crab.REWARD_COUNT and record(w,ALPHA)==rec(2,true),tag+" still one gift")
	var now_bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	for item in ["plank","copper_joint",Crab.REWARD_ITEM]:
		now_bag.erase(item)
		base_bag.erase(item)
	expect(now_bag==base_bag,tag+" no other item in the bag moved")
	expect(w.state.players[ALPHA].coins==120,tag+" coins untouched")
	expect(watch(w,ALPHA).is_empty(),tag+" the life route never starts a wait cycle")
	expect(valid(on_disk(w).duplicate(true)),tag+" the finished save passes SaveSchema")

func check_materials() -> void:
	var tag:="[materials]"
	var cases:=[[0,0,{"plank":2,"copper_joint":1}],[1,0,{"plank":1,"copper_joint":1}],[2,0,{"copper_joint":1}],[0,1,{"plank":2}],[1,1,{"plank":1}],[1,5,{"plank":1}]]
	for case:Array in cases:
		var w:=new_world("life",5,[ALPHA])
		reach(w,ALPHA,1)
		stock(w,ALPHA,case[0],case[1])
		var short:=refused(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"short","%s plank %d joint %d"%[tag,case[0],case[1]])
		expect(payload(short).get("missing")==case[2],"%s plank %d joint %d reports missing %s (got %s)"%[tag,case[0],case[1],str(case[2]),str(payload(short).get("missing"))])
		expect(held(w,ALPHA,"plank")==case[0] and held(w,ALPHA,"copper_joint")==case[1] and record(w,ALPHA)==rec(1,false),tag+" a short repair spends nothing and loses no progress")
		stock(w,ALPHA,2,1)
		var fix:=act(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART)
		expect(fix.get("ok",false)==true and held(w,ALPHA,"plank")==0 and held(w,ALPHA,"copper_joint")==0,tag+" coming back with the materials repairs and spends exactly the cost")
	# Only the actor's own bag pays: a full private chest / a rich friend do not help.
	var w2:=new_world("life",5)
	reach(w2,ALPHA,1)
	stock(w2,ALPHA,0,0)
	stock(w2,BETA,9,9)
	refused(w2,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"short",tag+" a friend's materials are never used")
	expect(held(w2,BETA,"plank")==9 and held(w2,BETA,"copper_joint")==9,tag+" the friend's bag is untouched")

func check_reward_cap() -> void:
	var tag:="[cap]"
	var w:=new_world("life",5,[ALPHA])
	reach(w,ALPHA,2)
	w.state.players[ALPHA].inventory[Crab.REWARD_ITEM]=CAP-1
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"full",tag+" a full gold_ore stack")
	expect(record(w,ALPHA)==rec(2,false) and held(w,ALPHA,Crab.REWARD_ITEM)==CAP-1,tag+" the gift is kept for later, record unclaimed")
	w.state.players[ALPHA].inventory[Crab.REWARD_ITEM]=CAP-2
	var gift:=act(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST)
	expect(gift.get("ok",false)==true and held(w,ALPHA,Crab.REWARD_ITEM)==CAP and record(w,ALPHA)==rec(2,true),tag+" once there is room the claim pays exactly to the cap")

func check_adventure_route() -> void:
	var tag:="[adventure]"
	var life:=new_world("life",5,[ALPHA])
	reach(life,ALPHA,1)
	refused(life,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"life_mode",tag+" life world, wait","wait")
	refused(life,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"life_mode",tag+" life world, tap","tap")
	var w:=new_world("adventure",5,[ALPHA])
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"too_early",tag+" wait before looking","wait")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"too_early",tag+" tap before looking","tap")
	act(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB)
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"late",tag+" tap with no cycle","tap")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CART,"far",tag+" wait aimed at the cart","wait")
	var bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	var start:=float(w.state.time)
	var wait:=act_twice(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,tag+" wait","wait")
	expect(wait.get("ok",false)==true and outcome(wait)=="windup" and cues(wait)==[Crab.CUE_RUMBLE] and mirrors(wait,rec(1,false)),"%s wait starts the telegraph (got %s)"%[tag,brief(wait)])
	expect(absf(float(payload(wait).get("open_at",-9))-(start+Crab.SHELL_WINDUP))<0.001 and absf(float(payload(wait).get("close_at",-9))-(start+Crab.SHELL_WINDUP+Crab.SHELL_WINDOW))<0.001,tag+" the reply tells the client when the shell opens and closes (ground ring + sound)")
	expect(watch(w,ALPHA).get("open_at")==start+Crab.SHELL_WINDUP,tag+" the cycle lives in host memory")
	expect(not JSON.stringify(on_disk(w).get("players",{}).get(ALPHA,{}).get(FIELD,{})).contains("open_at") and on_disk(w).get("players",{}).get(ALPHA,{}).get(FIELD)==({"stage":1.0,"claimed":false} as Dictionary),tag+" the saved record is still just stage/claimed")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"watching",tag+" a second wait during the cycle","wait")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"early",tag+" tap during the telegraph","tap")
	advance(w,Crab.SHELL_WINDUP-0.5,tag+" almost open")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"early",tag+" tap half a second early","tap")
	expect(record(w,ALPHA)==rec(1,false),tag+" early taps cost nothing")
	advance(w,0.5+Crab.SHELL_WINDOW,tag+" window closes")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"late",tag+" tap after the shell closed","tap")
	# Missing the window is free: wait again and land it.
	var second:=act(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	expect(outcome(second)=="windup",tag+" after a miss the player simply waits again")
	advance(w,Crab.SHELL_WINDUP+1.0,tag+" inside the window")
	var tap:=act_twice(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,tag+" tap","tap")
	expect(tap.get("ok",false)==true and outcome(tap)=="soft" and mirrors(tap,rec(2,false)) and Crab.CUE_SOFT in cues(tap),"%s a tap inside the window settles the crab (got %s)"%[tag,brief(tap)])
	expect(float(payload(tap).get("open_at",0))==-1.0 and watch(w,ALPHA).is_empty(),tag+" the cycle is over")
	expect(w.state.players[ALPHA].inventory==bag,tag+" the adventure route spends no materials")
	refused(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB_REST,"settled",tag+" wait after settling","wait")
	var gold:=held(w,ALPHA,Crab.REWARD_ITEM)
	var gift:=act(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST)
	expect(gift.get("ok",false)==true and held(w,ALPHA,Crab.REWARD_ITEM)==gold+Crab.REWARD_COUNT and record(w,ALPHA)==rec(2,true),tag+" same gift as the life route, once")
	refused(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"claimed",tag+" second claim")
	stock(w,ALPHA)
	refused(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"settled",tag+" repair after the adventure route")
	expect(held(w,ALPHA,"plank")==2,tag+" no material taken afterwards")
	# Walking away or disconnecting drops the cycle; nothing else is lost.
	var away:=new_world("adventure",5,[ALPHA])
	reach(away,ALPHA,1)
	act(away,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	expect(not watch(away,ALPHA).is_empty(),tag+" fixture: cycle running")
	expect(walk(away,ALPHA,Vector2(43.5,24.5)) and watch(away,ALPHA).is_empty(),tag+" walking out of reach drops the cycle")
	expect(walk(away,ALPHA,Vector2(SPOT)+Vector2(0.5,0.5)),tag+" walk back")
	advance(away,Crab.SHELL_WINDUP+0.5,tag+" would-be window")
	refused(away,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"late",tag+" tap after walking away","tap")
	act(away,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	away.crab_forget(ALPHA)
	expect(watch(away,ALPHA).is_empty() and record(away,ALPHA)==rec(1,false),tag+" crab_forget (disconnect) drops only the cycle")
	# Adventure worlds keep the repair route too.
	var both:=new_world("adventure",5,[ALPHA])
	reach(both,ALPHA,2)
	expect(record(both,ALPHA)==rec(2,false) and held(both,ALPHA,"plank")==0,tag+" the repair route still works in an adventure world")

func check_players_independent() -> void:
	var tag:="[coop]"
	var w:=new_world("life",5)
	stock(w,BETA,4,3)
	reach(w,ALPHA,2,true)
	expect(record(w,ALPHA)==rec(2,true) and not w.state.players[BETA].has(FIELD),tag+" alpha finishing writes nothing for beta")
	expect(held(w,BETA,"plank")==4 and held(w,BETA,"copper_joint")==3 and held(w,BETA,Crab.REWARD_ITEM)==0,tag+" beta's bag untouched by alpha's run")
	refused(w,BETA,Crab.CLAIM_ACTION,Crab.CRAB,"waiting",tag+" beta cannot claim on alpha's progress")
	refused(w,BETA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"far",tag+" beta's crab is still on its own cell")
	refused(w,BETA,Crab.REPAIR_ACTION,Crab.CART,"too_early",tag+" beta has not looked yet")
	var alpha_bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	expect(act(w,BETA,Crab.SURVEY_ACTION,Crab.CRAB).get("ok",false)==true,tag+" beta looks at its own crab")
	expect(act(w,BETA,Crab.REPAIR_ACTION,Crab.CART).get("ok",false)==true and held(w,BETA,"plank")==2 and held(w,BETA,"copper_joint")==2,tag+" beta pays its own materials")
	expect(act(w,BETA,Crab.CLAIM_ACTION,Crab.CRAB_REST).get("ok",false)==true and held(w,BETA,Crab.REWARD_ITEM)==Crab.REWARD_COUNT,tag+" beta gets its own gift")
	expect(w.state.players[ALPHA].inventory==alpha_bag and record(w,ALPHA)==rec(2,true),tag+" alpha is untouched by beta's run")
	# Same request id used by two players does not collide.
	var x:=new_world("life",5)
	var a:Dictionary=x.act(ALPHA,"shared-id",Crab.SURVEY_ACTION,Crab.CRAB)
	var b:Dictionary=x.act(BETA,"shared-id",Crab.SURVEY_ACTION,Crab.CRAB)
	expect(outcome(a)=="look" and outcome(b)=="look" and record(x,ALPHA)==rec(1,false) and record(x,BETA)==rec(1,false),tag+" receipts are per player")

func check_save_round_trip() -> void:
	var tag:="[save]"
	var old:=new_world("life",5)
	expect(old.save(),tag+" old-style save written")
	var disk:=on_disk(old)
	expect(not disk.players[ALPHA].has(FIELD) and not disk.players[BETA].has(FIELD) and valid(disk.duplicate(true)),tag+" a save without the field is valid (old save)")
	var from_old:=reopen(old,tag+" old save")
	if from_old!=null:
		expect(not from_old.state.players[ALPHA].has(FIELD),tag+" loading an old save invents no record")
		place(from_old,ALPHA,Crab.REGION,SPOT)
		expect(outcome(act(from_old,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB))=="look",tag+" a player from an old save starts fresh")
	for stage in [[1,false],[2,false],[2,true]]:
		var label:="%s stage %d claimed %s"%[tag,stage[0],str(stage[1])]
		var w:=new_world("life",5)
		reach(w,ALPHA,stage[0],stage[1])
		var bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
		var saved:=on_disk(w)
		expect(valid(saved.duplicate(true)),label+": JSON form of the save passes SaveSchema")
		expect(saved.players[ALPHA].get(FIELD,{}).size()==2 and int(saved.players[ALPHA][FIELD].stage)==stage[0] and saved.players[ALPHA][FIELD].claimed==stage[1],label+": on disk exactly {stage,claimed}")
		expect(not saved.players[BETA].has(FIELD),label+": the untouched player has no field on disk")
		expect(not JSON.stringify(saved).contains("_crab_watch") and not saved.has(FIELD),label+": nothing else about the crab is saved")
		var again:=reopen(w,label)
		if again==null:continue
		expect(record(again,ALPHA)==rec(stage[0],stage[1]) and again.state.players[ALPHA][FIELD].stage is int,label+": record restored and normalised to ints")
		var restored:Dictionary={}
		for item in bag:restored[item]=int(again.state.players[ALPHA].inventory.get(item,0))
		var want:Dictionary={}
		for item in bag:want[item]=int(bag[item])
		expect(restored==want,label+": bag restored")
		again.add_player(ALPHA,"alpha")
		expect(record(again,ALPHA)==rec(stage[0],stage[1]),label+": rejoining keeps the record")
		place(again,ALPHA,Crab.REGION,SPOT)
		var gold:=held(again,ALPHA,Crab.REWARD_ITEM)
		if stage[0]==1:
			refused(again,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB,"waiting",label+" after restart")
			stock(again,ALPHA)
			expect(act(again,ALPHA,Crab.REPAIR_ACTION,Crab.CART).get("ok",false)==true,label+": repair continues after restart without looking again")
		elif not stage[1]:
			refused(again,ALPHA,Crab.REPAIR_ACTION,Crab.CART,"settled",label+" after restart")
			expect(act(again,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST).get("ok",false)==true and held(again,ALPHA,Crab.REWARD_ITEM)==gold+Crab.REWARD_COUNT,label+": the unclaimed gift is still there after restart, once")
			refused(again,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"claimed",label+" second claim after restart")
		else:
			refused(again,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST,"claimed",label+" after restart")
			expect(held(again,ALPHA,Crab.REWARD_ITEM)==gold,label+": no second gift after restart")
	# A receipt survives the restart: the same request id still does not pay twice.
	var r:=new_world("life",5,[ALPHA])
	reach(r,ALPHA,2)
	var first:Dictionary=r.act(ALPHA,"crab-claim-once",Crab.CLAIM_ACTION,Crab.CRAB_REST)
	var after:=reopen(r,tag+" receipt")
	if after!=null:
		var gold:=held(after,ALPHA,Crab.REWARD_ITEM)
		var replay:Dictionary=after.act(ALPHA,"crab-claim-once",Crab.CLAIM_ACTION,Crab.CRAB_REST)
		expect(first.get("ok",false)==true and replay.get("ok",false)==true and outcome(replay)=="claim" and held(after,ALPHA,Crab.REWARD_ITEM)==gold,tag+" replaying the claim request id after a restart returns the receipt and pays nothing")
	# Adventure wait cycle is not persisted.
	var adv:=new_world("adventure",5,[ALPHA])
	reach(adv,ALPHA,1)
	act(adv,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	var adv_again:=reopen(adv,tag+" adventure")
	if adv_again!=null:
		expect(watch(adv_again,ALPHA).is_empty() and record(adv_again,ALPHA)==rec(1,false) and adv_again.state.get("world_mode")=="adventure",tag+" a restart drops the wait cycle and keeps stage 1")
		place(adv_again,ALPHA,Crab.REGION,SPOT)
		refused(adv_again,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"late",tag+" tap after restart","tap")

func check_failed_save() -> void:
	var tag:="[save-fail]"
	var w:=new_world("adventure",5,[ALPHA])
	var good:String=w.save_path
	var bad:String=good.path_join("missing").path_join("world.json")
	expect(w.save(),tag+" fixture file exists")
	var fail_once:=func(action:String,cell:Vector2i,extra:String,label:String) -> void:
		var before:Dictionary=w.state.duplicate(true)
		var cycle:Dictionary=watch(w,ALPHA).duplicate(true)
		var disk:=FileAccess.get_file_as_string(good)
		w.save_path=bad
		var lost:=act(w,ALPHA,action,cell,extra)
		w.save_path=good
		expect(lost.get("ok",true)==false and lost.get("message")==World.SAVE_FAILED_MSG and not lost.has("crab"),"%s %s: a failed save refuses the action (got %s)"%[tag,label,brief(lost)])
		expect(w.state==before,"%s %s: state rolled back (bag, record, receipts, journal)"%[tag,label])
		expect(watch(w,ALPHA)==cycle,"%s %s: host-memory wait cycle rolled back"%[tag,label])
		expect(FileAccess.get_file_as_string(good)==disk,"%s %s: the file on disk is untouched"%[tag,label])
	fail_once.call(Crab.SURVEY_ACTION,Crab.CRAB,"","look")
	expect(not w.state.players[ALPHA].has(FIELD),tag+" no record after the failed look")
	expect(outcome(act(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB))=="look",tag+" the look works once saving works")
	fail_once.call(Crab.SHELL_ACTION,Crab.CRAB,"wait","shell wait")
	expect(watch(w,ALPHA).is_empty(),tag+" the failed wait left no cycle behind")
	stock(w,ALPHA,2,1)
	fail_once.call(Crab.REPAIR_ACTION,Crab.CART,"","repair")
	expect(held(w,ALPHA,"plank")==2 and held(w,ALPHA,"copper_joint")==1 and record(w,ALPHA)==rec(1,false),tag+" the failed repair kept the materials and stage 1")
	# Adventure tap whose save fails: the stage stays 1 and the cycle is still running.
	act(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	advance(w,Crab.SHELL_WINDUP+0.5,tag+" window")
	fail_once.call(Crab.SHELL_ACTION,Crab.CRAB,"tap","shell tap")
	expect(record(w,ALPHA)==rec(1,false) and not watch(w,ALPHA).is_empty(),tag+" the failed tap kept stage 1 and the running cycle")
	var fix:=act(w,ALPHA,Crab.REPAIR_ACTION,Crab.CART)
	expect(fix.get("ok",false)==true and held(w,ALPHA,"plank")==0 and held(w,ALPHA,"copper_joint")==0 and record(w,ALPHA)==rec(2,false),tag+" the repair then succeeds and spends once")
	expect(watch(w,ALPHA).is_empty(),tag+" settling by repair ends any running cycle")
	var gold:=held(w,ALPHA,Crab.REWARD_ITEM)
	fail_once.call(Crab.CLAIM_ACTION,Crab.CRAB_REST,"","claim")
	expect(held(w,ALPHA,Crab.REWARD_ITEM)==gold and record(w,ALPHA)==rec(2,false),tag+" the failed claim paid nothing and is not marked claimed")
	var gift:=act(w,ALPHA,Crab.CLAIM_ACTION,Crab.CRAB_REST)
	expect(gift.get("ok",false)==true and held(w,ALPHA,Crab.REWARD_ITEM)==gold+Crab.REWARD_COUNT and record(w,ALPHA)==rec(2,true),tag+" the claim then pays exactly once")
	var saved:=on_disk(w)
	expect(valid(saved.duplicate(true)) and int(saved.players[ALPHA].inventory.get(Crab.REWARD_ITEM,0))==gold+Crab.REWARD_COUNT,tag+" the final save is valid and holds one gift")

func check_schema() -> void:
	var tag:="[schema]"
	var w:=new_world("life",5,[ALPHA])
	reach(w,ALPHA,2,true)
	var good:=on_disk(w)
	expect(valid(good.duplicate(true)),tag+" baseline save is valid")
	var bad_records:Array=[{},{"stage":1},{"claimed":false},{"stage":3,"claimed":false},{"stage":-1,"claimed":false},{"stage":1.5,"claimed":false},
		{"stage":"1","claimed":false},{"stage":1,"claimed":1},{"stage":1,"claimed":"no"},{"stage":0,"claimed":true},{"stage":1,"claimed":true},
		{"stage":2,"claimed":true,"open_at":3.0},{"stage":2,"claimed":false,"watch":{}},[2,true],"done",7,null]
	for bad in bad_records:
		var copy:Dictionary=good.duplicate(true)
		copy.players[ALPHA][FIELD]=bad
		expect(not valid(copy),"%s rejects record %s"%[tag,str(bad)])
	for fine in [{"stage":0,"claimed":false},{"stage":1.0,"claimed":false},{"stage":2,"claimed":false},{"stage":2.0,"claimed":true}]:
		var copy:Dictionary=good.duplicate(true)
		copy.players[ALPHA][FIELD]=fine
		expect(valid(copy) and copy.players[ALPHA][FIELD].stage is int,"%s accepts and normalises %s"%[tag,str(fine)])
	var no_picnic:Dictionary=good.duplicate(true)
	no_picnic["picnic"]=false
	expect(not valid(no_picnic),tag+" a record without the picnic is rejected")
	# B5 closed but a record present. The player is moved to B4 so only the record is at fault.
	var locked:Dictionary=good.duplicate(true)
	locked.mine_depths.unlocked=4
	locked.players[ALPHA].region="mine_4"
	locked.players[ALPHA].x=Mines.REST.x+0.5
	locked.players[ALPHA].y=Mines.REST.y-0.5
	var control:Dictionary=locked.duplicate(true)
	control.players[ALPHA].erase(FIELD)
	expect(valid(control),tag+" control: the same B4 save without the record is valid")
	expect(not valid(locked),tag+" a record while B5 is still closed is rejected")
	var absent:Dictionary=good.duplicate(true)
	absent.players[ALPHA].erase(FIELD)
	expect(valid(absent),tag+" removing the field keeps the save valid")

func check_collision() -> void:
	var tag:="[collision]"
	var w:=new_world("life",5,[ALPHA])
	expect(not can_stand_at(w,Crab.CART),tag+" the cart cell is solid")
	expect(can_stand_at(w,Crab.CRAB) and can_stand_at(w,Crab.CRAB_REST),tag+" both crab cells can be walked over")
	for cell:Vector2i in Crab.footprint():
		expect(protected_at(w,cell),"%s %s takes no new builds"%[tag,str(cell)])
	expect(not protected_at(w,SPOT) and not protected_at(w,Survey.POINTS[5]),tag+" neighbouring cells are not reserved")
	# Same cave shape on other floors is unaffected.
	for other in ["mine_2","mine_4"]:
		expect(in_region(w,other,func():return not w.protected(Crab.CART) and not w.blocked(Crab.CART) if w.is_land(Crab.CART) else true),"%s %s is unaffected"%[tag,other])
	# Real movement: main chamber -> cave -> survey point -> dead-end nook -> out again.
	place(w,ALPHA,Crab.REGION,Vector2i(38,24))
	expect(walk(w,ALPHA,Vector2(40.5,24.5)),tag+" main chamber -> cave mouth")
	expect(walk(w,ALPHA,Vector2(43.5,24.5)),tag+" cave mouth -> cave room")
	expect(walk(w,ALPHA,Vector2(46.5,24.5)),tag+" cave room -> survey point cell (46,24)")
	var seen:=w.act(ALPHA,"crab-walk-survey","survey_observe",Survey.POINTS[5])
	expect(seen.get("ok",false)==true and not seen.has("crab"),tag+" the B5 survey point still works and carries no crab payload")
	expect(walk(w,ALPHA,Vector2(46.5,26.5)) and walk(w,ALPHA,Vector2(46.5,28.5)) and walk(w,ALPHA,Vector2(47.5,28.5)),tag+" the dead-end nook stays reachable")
	expect(walk(w,ALPHA,Vector2(46.5,26.5)) and walk(w,ALPHA,Vector2(46.5,23.5)),tag+" back up to the cell below the resting crab")
	expect(walk(w,ALPHA,Vector2(46.5,22.5)),tag+" can step onto the resting cell (46,22)")
	expect(walk(w,ALPHA,Vector2(47.5,22.5)),tag+" can step onto the crab cell (47,22)")
	expect(walk(w,ALPHA,Vector2(46.5,22.5)),tag+" and back")
	# Pushing into the cart from the right and from below never ends inside its cell.
	for tick in 60:w.move_player(ALPHA,Vector2.LEFT,0.05)
	w.switch_region(World.REGIONS.HOME)
	expect(Vector2i(pos(w,ALPHA).floor())!=Crab.CART and pos(w,ALPHA).x>46.0,"%s pushing left from (46,22) stops at the cart (at %s)"%[tag,str(pos(w,ALPHA))])
	expect(walk(w,ALPHA,Vector2(45.5,23.5)),tag+" can stand right below the cart")
	for tick in 60:w.move_player(ALPHA,Vector2.UP,0.05)
	w.switch_region(World.REGIONS.HOME)
	expect(Vector2i(pos(w,ALPHA).floor())!=Crab.CART and pos(w,ALPHA).y>23.0,"%s pushing up from (45,23) stops at the cart (at %s)"%[tag,str(pos(w,ALPHA))])
	expect(Crab.near(pos(w,ALPHA),Crab.CART),tag+" the cart is within REACH from below")
	expect(walk(w,ALPHA,Vector2(44.5,22.5)) and Crab.near(pos(w,ALPHA),Crab.CART),tag+" the cell left of the cart is standable and within REACH")
	expect(walk(w,ALPHA,Vector2(43.5,24.5)) and walk(w,ALPHA,Vector2(40.5,24.5)) and walk(w,ALPHA,Vector2(38.5,24.5)),tag+" can leave the cave again")
	# New player content is refused on the three cells and still allowed next to them.
	var builder:=new_world("life",5,[ALPHA])
	builder.state.players[ALPHA].inventory["stone"]=40
	builder.state.players[ALPHA].inventory["wood"]=80
	var probe:=act(builder,ALPHA,"build",Vector2i(47,23),"path")
	if probe.get("ok",false):
		for cell:Vector2i in Crab.footprint():
			for kind in ["path","chest"]:
				var before:Dictionary=builder.state.duplicate(true)
				var built:=act(builder,ALPHA,"build",cell,kind)
				expect(built.get("ok",true)==false and builder.state==before,"%s building %s on %s is refused and costs nothing (got %s)"%[tag,kind,str(cell),str(built.get("message",""))])
			var hoed:=act(builder,ALPHA,"hoe",cell)
			expect(hoed.get("ok",true)==false,"%s hoeing %s is refused"%[tag,str(cell)])
			var tree:=act(builder,ALPHA,"plant_tree",cell)
			expect(tree.get("ok",true)==false,"%s planting a tree on %s is refused"%[tag,str(cell)])
		expect(in_region(builder,Crab.REGION,func():return builder.crab_available()),tag+" the encounter is still available after the refused builds")
	else:
		print("%s INFO building a path next to the crab was refused (%s); footprint build refusals not compared"%[tag,str(probe.get("message",""))])

func check_legacy_occupied() -> void:
	var tag:="[legacy-built]"
	var w:=new_world("life",5,[ALPHA])
	w.state.players[ALPHA].inventory["wood"]=80
	var donor:=Vector2i(47,24)
	var built:=act(w,ALPHA,"build",donor,"chest")
	if not built.get("ok",false):
		print("%s INFO could not build a chest in the cave (%s); legacy-occupied checks skipped"%[tag,str(built.get("message",""))])
		return
	# Fixture: an older save already had this chest on the crab's resting cell.
	var layer:Dictionary=w.state.regions[Crab.REGION].objects
	layer[World.key(Crab.CRAB_REST)]=layer[World.key(donor)]
	layer.erase(World.key(donor))
	expect(w.save() and valid(on_disk(w).duplicate(true)),tag+" a save with a chest on (46,22) is still valid")
	var again:=reopen(w,tag)
	if again==null:return
	w=again
	place(w,ALPHA,Crab.REGION,SPOT)
	expect(not in_region(w,Crab.REGION,func():return w.crab_available()),tag+" the encounter is hidden while a crab cell is occupied")
	expect(can_stand_at(w,Crab.CART),tag+" the hidden cart is not solid")
	expect(not protected_at(w,Crab.CRAB_REST),tag+" the occupied cell stays the owner's (not reserved)")
	expect(protected_at(w,Crab.CART) and protected_at(w,Crab.CRAB),tag+" the two empty cells are already reserved")
	stock(w,ALPHA)
	for step in [[Crab.SURVEY_ACTION,Crab.CRAB,""],[Crab.REPAIR_ACTION,Crab.CART,""],[Crab.CLAIM_ACTION,Crab.CRAB,""]]:
		refused(w,ALPHA,step[0],step[1],"occupied",tag+" while occupied",step[2])
	expect(not w.state.players[ALPHA].has(FIELD) and held(w,ALPHA,"plank")==2,tag+" nothing written or spent while occupied")
	var wood:=held(w,ALPHA,"wood")
	var removed:=act(w,ALPHA,"remove",Crab.CRAB_REST)
	expect(removed.get("ok",false)==true and not w.state.regions[Crab.REGION].objects.has(World.key(Crab.CRAB_REST)),"%s the owner can still remove the legacy chest (%s)"%[tag,str(removed.get("message",""))])
	expect(held(w,ALPHA,"wood")>=wood,tag+" removing it does not cost materials")
	expect(in_region(w,Crab.REGION,func():return w.crab_available()) and protected_at(w,Crab.CRAB_REST) and not can_stand_at(w,Crab.CART),tag+" once cleared the encounter appears, the cell is reserved and the cart is solid")
	var before:Dictionary=w.state.duplicate(true)
	var rebuilt:=act(w,ALPHA,"build",Crab.CRAB_REST,"chest")
	expect(rebuilt.get("ok",true)==false and w.state==before,tag+" the cleared cell takes no new chest")
	expect(outcome(act(w,ALPHA,Crab.SURVEY_ACTION,Crab.CRAB))=="look",tag+" and the encounter can be played")

func check_legacy_position() -> void:
	var tag:="[legacy-position]"
	var w:=new_world("life",5,[ALPHA])
	# Fixture: an older save left the player standing exactly on the cart cell.
	place(w,ALPHA,Crab.REGION,Crab.CART)
	expect(w.save() and valid(on_disk(w).duplicate(true)),tag+" a save with the player on (45,22) is still valid")
	var again:=reopen(w,tag)
	if again==null:return
	again.add_player(ALPHA,"alpha")
	var at:=pos(again,ALPHA)
	expect(again.player_region(ALPHA)==Crab.REGION and Vector2i(at.floor())!=Crab.CART,"%s rejoining moves the player off the solid cart (at %s)"%[tag,str(at)])
	expect(in_region(again,Crab.REGION,func():return again.can_stand(at)),tag+" the new position is standable")
	var out:=act(again,ALPHA,"rescue",Vector2i(at.floor()))
	expect(out.get("ok",false)==true,tag+" the ordinary rescue action still works on B5")

func base_actions(w:World,prefix:String) -> Array:
	var results:Array=[]
	var steps:Array=[
		["survey_observe",Survey.POINTS[5],"",Crab.REGION,SPOT],
		["survey_observe",Survey.POINTS[5],"",Crab.REGION,SPOT],
		["pick",Mines.NODES[0],"",Crab.REGION,Mines.NODES[0]+Vector2i.UP],
		["mine_rest",Mines.REST,"",Crab.REGION,Mines.REST+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_4",Crab.REGION,Mines.UP+Vector2i.UP],
		["pick",Mines.NODES[1],"","mine_4",Mines.NODES[1]+Vector2i.UP],
		["mine_travel",Mines.DOWN,Crab.REGION,"mine_4",Mines.DOWN+Vector2i.UP],
		["pick",Mines.NODES[2],"",Crab.REGION,Mines.NODES[2]+Vector2i.UP],
	]
	for i in steps.size():
		var step:Array=steps[i]
		expect(w.player_region(ALPHA)==step[3],"%s step %d (%s) starts in %s (in %s)"%[prefix,i,step[0],step[3],w.player_region(ALPHA)])
		place(w,ALPHA,step[3],step[4])
		var id:="%s-base-%d"%[prefix,i]
		var result:Dictionary=w.act(ALPHA,id,step[0],step[1],step[2])
		var copy:Dictionary=result.duplicate(true)
		expect(result.get("ok",false)==true,"%s base action %d %s succeeds (%s)"%[prefix,i,step[0],str(result.get("message",""))])
		expect(not copy.has("crab"),"%s base action %d %s carries no crab payload"%[prefix,i,step[0]])
		results.append(copy)
	return results

## The same base B5 actions give identical results with and without crab progress.
func check_base_mine_actions() -> void:
	var tag:="[base]"
	var control:=new_world("life",5,[ALPHA])
	var w:=new_world("life",5,[ALPHA])
	for world:World in [control,w]:world.state.players[ALPHA].inventory["reinforced_pick"]=1
	reach(w,ALPHA,2,true)
	expect(record(w,ALPHA)==rec(2,true),tag+" crab finished before the base actions")
	var expected:=base_actions(control,"control")
	var got:=base_actions(w,"crab")
	expect(got==expected,tag+" every base mine result is identical with and without crab progress")
	for i in mini(got.size(),expected.size()):
		if got[i]!=expected[i]:print("%s step %d differs: control=%s crab=%s"%[tag,i,str(expected[i]),str(got[i])])
	var mine:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	var theirs:Dictionary=control.state.players[ALPHA].inventory.duplicate(true)
	var extra:=int(mine.get(Crab.REWARD_ITEM,0))-int(theirs.get(Crab.REWARD_ITEM,0))
	for item in [Crab.REWARD_ITEM,"plank","copper_joint"]:
		mine.erase(item)
		theirs.erase(item)
	expect(mine==theirs and extra==Crab.REWARD_COUNT and held(w,ALPHA,"plank")==0 and held(w,ALPHA,"copper_joint")==0,"%s bags differ only by the repair cost and the +%d gift (diff %d)"%[tag,Crab.REWARD_COUNT,extra])
	for field in ["mine_energy","region","travel_epoch","coins","x","y"]:
		expect(w.state.players[ALPHA].get(field)==control.state.players[ALPHA].get(field),"%s player %s identical to the control world"%[tag,field])
	expect(w.state.mine_survey==control.state.mine_survey and Survey.own_record(w.state,ALPHA).seen=={"5":true},tag+" B5 survey page recorded exactly as in the control world")
	expect(w.state.mine_depths==control.state.mine_depths,tag+" shared mine progress identical to the control world")
	expect(record(w,ALPHA)==rec(2,true) and not control.state.players[ALPHA].has(FIELD),tag+" base actions never touch or create a crab record")
	expect(valid(on_disk(w).duplicate(true)) and valid(on_disk(control).duplicate(true)),tag+" both saves pass SaveSchema")

func check_snapshot_privacy() -> void:
	var tag:="[snapshot]"
	var w:=new_world("adventure",5)
	reach(w,ALPHA,1)
	act(w,ALPHA,Crab.SHELL_ACTION,Crab.CRAB,"wait")
	var session:=Session.new()
	session.world=w
	session.peers[1]=BETA
	session.peers[2]=ALPHA
	var alpha_id:String=Session._public_actor(ALPHA)
	var beta_id:String=Session._public_actor(BETA)
	session._send_snapshot(1)
	var beta_view:Dictionary=session.snapshot
	expect(session.own_id==beta_id and beta_view.get("region_id")==Crab.REGION,tag+" beta receives a mine_5 snapshot under a public id")
	var foreign:Dictionary=beta_view.get("players",{}).get(alpha_id,{})
	expect(not foreign.is_empty() and not foreign.has(FIELD),tag+" alpha's stone_crab record is not visible to beta")
	for key in foreign:
		expect(not str(key).to_lower().contains("crab"),"%s alpha's entry seen by beta has no crab field (%s)"%[tag,str(key)])
	expect(not beta_view.get("players",{}).get(beta_id,{}).has(FIELD),tag+" beta (not started) has no field: the client treats absence as fresh")
	var text:=JSON.stringify(beta_view)
	expect(not text.contains("_crab_watch") and not text.contains("open_at") and not text.contains(ALPHA) and not text.contains(BETA),tag+" no wait cycle and no raw token in beta's snapshot")
	expect(beta_view.get("picnic")==true and int(beta_view.get("mine_depths",{}).get("unlocked",0))==5 and beta_view.get("world_mode")=="adventure",tag+" the snapshot carries picnic, mine_depths.unlocked and world_mode for the client's availability rule")
	expect(Crab.site_clear(beta_view),tag+" the client can evaluate site_clear() on the region snapshot")
	session.peers[1]=ALPHA
	session.peers[2]=BETA
	session._send_snapshot(1)
	var alpha_view:Dictionary=session.snapshot
	var own=alpha_view.get("players",{}).get(alpha_id,{}).get(FIELD)
	expect(own is Dictionary and Crab.valid(own) and int(own.stage)==1 and own.claimed==false,"%s alpha's own snapshot shows its own stage 1 (got %s)"%[tag,str(own)])
	expect(not alpha_view.get("players",{}).get(beta_id,{}).has(FIELD),tag+" beta's (absent) record is not invented in alpha's snapshot")
	expect(not JSON.stringify(alpha_view).contains("open_at") and not alpha_view.get("players",{}).get(alpha_id,{}).has("receipts"),tag+" the wait cycle and receipts never leave the server")
	session.free()
