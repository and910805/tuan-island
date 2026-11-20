extends SceneTree
## B2 害羞菇 integration test through the REAL World.act path (headless, in-process).
## Written against the server contract while the wiring was landing in world.gd /
## save_schema.gd / session.gd.
##
## Fixtures are DISCLOSED:
##  - players are placed by writing region/x/y (as in test_mine_survey.gd);
##  - state.picnic, state.world_mode and state.mine_depths are seeded by writing them;
##  - w.active_tokens[token]=true marks the test players as connected (Session does this);
##  - "inventory full" is produced by writing the fiber count;
##  - home farm cells are cleared by writing state.removed (as create_world_backup_fixture.gd);
##  - a failing save is produced by pointing save_path below a file.
## World time is advanced ONLY with the real World.step(dt,true,false) in 0.5 s ticks
## (advance()), except one explicitly labelled check that writes state.time directly.
## Everything else goes through World.act, World.move_player, World.save / load_world,
## SaveSchema.validate and Session._send_snapshot.
## The wait anchor is read from host memory with w.get("_shy_watch") (read-only).

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Shy=preload("res://scripts/shy_mushroom.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const ALPHA:="shy-world-alpha-token"
const BETA:="shy-world-beta-token"
const FIELD:="shy_mushroom"
const CAP:=1000000000
## Free nook floor cell next to the mushroom (1.0 from its centre).
const SPOT:=Vector2i(45,23)
## Beyond REACH 1.8 but inside the generic 3.2 reach.
const SPOT_FAR:=Vector2i(44,22)
const NEIGHBOUR:=Vector2i(45,22)
const FARM:=Vector2i(38,34)
const PENALTY_KEYS:=["damage","hp","health","score","timer","penalty","fail","failed","lives","deadline"]
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
	for mode in ["life","adventure"]:
		check_gates(mode)
		check_core(mode)
		check_water_elsewhere(mode)
	check_players_independent()
	check_save_round_trip()
	check_failed_save()
	check_schema()
	check_home_farm()
	check_base_mine_actions()
	check_adventure_mud()
	check_walkable()
	check_snapshot_privacy()
	for file in files:
		for suffix in ["",".bak",".tmp",".bak.staged"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("SHY_MUSHROOM_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ----------------------------------------------------------------- helpers --

func new_world(mode:String,unlocked:int=5,tokens:Array=[ALPHA,BETA]) -> World:
	var w:=World.new()
	var path:String=OS.get_environment("TEMP").path_join("shy-mushroom-world-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	files.append(path)
	w.save_path=path
	w.state["picnic"]=true
	if mode=="adventure":w.state["world_mode"]="adventure"
	w.state["mine_depths"]={"unlocked":unlocked,"ready":{},"pumped":24 if unlocked>=3 else 0,"hoist":false}
	for token:String in tokens:
		w.add_player(token,token.left(12))
		w.active_tokens[token]=true
		place(w,token,Shy.REGION,SPOT)
	return w

func place(w:World,token:String,region:String,cell:Vector2i) -> void:
	var player:Dictionary=w.state.players[token]
	player["region"]=region
	player["x"]=cell.x+0.5
	player["y"]=cell.y+0.5

func pos(w:World,token:String) -> Vector2:
	return Vector2(float(w.state.players[token].x),float(w.state.players[token].y))

func act(w:World,token:String,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"shy-test-%d"%serial,action,cell,extra)

## Acts once, then replays the same request id and checks the replay is identical
## and changes nothing (record, inventory, whole state, wait anchor).
func act_twice(w:World,token:String,action:String,cell:Vector2i,label:String) -> Dictionary:
	serial+=1
	var id:="shy-test-%d"%serial
	var first:Dictionary=w.act(token,id,action,cell,"")
	var copy:Dictionary=first.duplicate(true)
	var after:Dictionary=w.state.duplicate(true)
	var anchor:Dictionary=watch(w,token).duplicate(true)
	var again:Dictionary=w.act(token,id,action,cell,"")
	expect(again==copy,"%s: same request_id replays the identical result (first=%s replay=%s)"%[label,brief(copy),brief(again)])
	expect(w.state==after and watch(w,token)==anchor,"%s: replay changes no state and no wait anchor (no double progress / reward)"%label)
	var problem:=shape_problem(first)
	expect(problem.is_empty(),"%s: result shape (%s) got %s"%[label,problem,str(first)])
	return first

func brief(result:Dictionary) -> String:
	return "{ok=%s msg=%s shy=%s}"%[str(result.get("ok")),str(result.get("message","")).left(24),str(result.get("shy","<none>"))]

func payload(result:Dictionary) -> Dictionary:
	var s=result.get("shy")
	return s if s is Dictionary else {}

func outcome(result:Dictionary) -> String:
	return str(payload(result).get("outcome","<no shy payload>"))

func number(value) -> bool:
	return value is int or value is float

func num(result:Dictionary,field:String) -> float:
	var value=payload(result).get(field)
	return float(value) if number(value) else -999.0

func remaining(result:Dictionary) -> float:
	return num(result,"remaining")

func has_cue(result:Dictionary,cue:String) -> bool:
	var cues=payload(result).get("cues")
	return cues is Array and cue in cues

## "" when the result follows the contract shape, otherwise what is wrong.
func shape_problem(result:Dictionary) -> String:
	if not result.get("ok") is bool:return "ok is not a bool"
	if not result.get("message") is String:return "message is not a String"
	if not result.get("shy") is Dictionary:return "no shy Dictionary"
	var s:Dictionary=result.shy
	for field in ["outcome","stage","claimed","remaining","since","x","y","cues"]:
		if not s.has(field):return "shy."+field+" missing"
	if not s.outcome is String:return "shy.outcome is not a String"
	if not s.stage is int:return "shy.stage is not an int"
	if not s.claimed is bool:return "shy.claimed is not a bool"
	for field in ["remaining","since","x","y"]:
		if not number(s[field]):return "shy."+field+" is not a number"
	if not s.cues is Array:return "shy.cues is not an Array"
	for field in PENALTY_KEYS:
		if s.has(field) or result.has(field):return "penalty field "+field
	return ""

func record(w:World,token:String) -> Dictionary:
	var raw=w.state.players[token].get(FIELD,Shy.fresh())
	if not raw is Dictionary or not Shy.valid(raw):return {"invalid":raw}
	return {"stage":int(raw.stage),"claimed":bool(raw.claimed)}

func rec(stage:int,claimed:bool) -> Dictionary:
	return {"stage":stage,"claimed":claimed}

func fiber(w:World,token:String) -> int:
	return int(w.state.players[token].inventory.get(Shy.REWARD_ITEM,0))

func bag(w:World,token:String) -> Dictionary:
	return w.state.players[token].inventory.duplicate(true)

func player_without(w:World,token:String,drop:Array) -> Dictionary:
	var copy:Dictionary=w.state.players[token].duplicate(true)
	for field in drop:copy.erase(field)
	return copy

## Host-memory wait anchor of this player ({} when none). Read-only.
func watch(w:World,token:String) -> Dictionary:
	var all=w.get("_shy_watch")
	if not all is Dictionary:return {"_shy_watch missing":true}
	var mine=all.get(token,{})
	return mine if mine is Dictionary else {"bad":mine}

## True when the result payload mirrors the durable record.
func mirrors(result:Dictionary,want:Dictionary) -> bool:
	var s:=payload(result)
	return s.get("stage") is int and int(s.stage)==int(want.stage) and s.get("claimed") is bool and s.claimed==want.claimed

## Real server ticks (no save). Returns false when a tick fails.
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
	expect(fine,"%s: real World.step advanced state.time by %.1f (from %.3f to %.3f)"%[label,seconds,start,float(w.state.time)])
	return fine

func refused(w:World,token:String,action:String,cell:Vector2i,label:String,extra:String="") -> Dictionary:
	var before:Dictionary=w.state.duplicate(true)
	var anchor:Dictionary=watch(w,token).duplicate(true)
	var result:=act(w,token,action,cell,extra)
	expect(result.get("ok",true)==false and result.get("message") is String,"%s: %s is refused (got %s)"%[label,action,brief(result)])
	expect(w.state==before,"%s: refused %s changes no state"%[label,action])
	expect(watch(w,token)==anchor,"%s: refused %s leaves the wait anchor alone (before %s after %s)"%[label,action,str(anchor),str(watch(w,token))])
	for field in PENALTY_KEYS:
		if result.has(field) or payload(result).has(field):expect(false,"%s: refused %s carries penalty field %s"%[label,action,field])
	return result

func refuse_all(w:World,token:String,label:String) -> void:
	for action:String in Shy.ACTIONS:
		refused(w,token,action,Shy.MUSHROOM,label)
	expect(not w.state.players[token].has(FIELD),"%s: no mushroom record written"%label)
	expect(watch(w,token).is_empty(),"%s: no wait anchor started (%s)"%[label,str(watch(w,token))])

## Base-game watering (no mushroom routing): refused and no `shy` key.
func base_water(w:World,token:String,cell:Vector2i,label:String) -> Dictionary:
	var result:=refused(w,token,"water",cell,label)
	expect(not result.has("shy"),"%s: plain water result has no shy key (got %s)"%[label,brief(result)])
	return result

## Runs the whole life-mode flow with real ticks. Returns true when the record ends as wanted.
func open_fully(w:World,token:String,label:String,claim:bool=true) -> bool:
	place(w,token,Shy.REGION,SPOT)
	var start:=act(w,token,"shy_wait",Shy.MUSHROOM)
	if outcome(start)!="start":
		expect(false,"%s: flow could not start (got %s)"%[label,brief(start)])
		return false
	advance(w,Shy.WAIT_SECONDS,label+" wait")
	var peek:=act(w,token,"shy_wait",Shy.MUSHROOM)
	var water:=act(w,token,"water",Shy.MUSHROOM)
	var fine:bool=outcome(peek)=="peek" and outcome(water)=="water" and record(w,token)==rec(2,false)
	if claim:
		var gift:=act(w,token,"shy_claim",Shy.MUSHROOM)
		fine=fine and gift.get("ok",false)==true and record(w,token)==rec(2,true)
	expect(fine,"%s: full flow reaches %s (record %s)"%[label,str(rec(2,claim)),str(record(w,token))])
	return fine

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

## Any place in `state` that mentions the mushroom other than the durable per-player record.
func stray_shy_state(state:Dictionary) -> Array:
	var problems:Array=[]
	for key in state:
		if str(key).to_lower().contains("shy"):problems.append("state."+str(key))
	for token in state.get("players",{}):
		var person:Dictionary=state.players[token]
		for key in person:
			if str(key).to_lower().contains("shy") and str(key)!=FIELD:problems.append("player."+str(key))
		if person.has(FIELD) and (not person[FIELD] is Dictionary or person[FIELD].size()!=2 or not Shy.valid(person[FIELD])):problems.append("record "+str(person[FIELD]))
	return problems

# ------------------------------------------------------------------ checks --

func check_fixture_assumptions() -> void:
	var consts:Dictionary=(World as GDScript).get_script_constant_map()
	expect(consts.get("SHY_FIELD")==FIELD,"World.SHY_FIELD is \"shy_mushroom\" (got %s)"%str(consts.get("SHY_FIELD","<missing: not wired>")))
	expect(World.new().get("_shy_watch") is Dictionary,"World keeps a host-memory _shy_watch Dictionary")
	expect(Shy.MUSHROOM==Vector2i(46,23) and Shy.REGION=="mine_2" and Shy.REWARD_ITEM=="fiber" and Shy.REWARD_COUNT==4,"module constants match the contract")
	expect(Shy.near(Vector2(SPOT)+Vector2(0.5,0.5)) and SPOT!=Shy.MUSHROOM,"test spot reaches the mushroom")
	var far:=Vector2(SPOT_FAR)+Vector2(0.5,0.5)
	expect(not Shy.near(far) and far.distance_to(Vector2(Shy.MUSHROOM)+Vector2(0.5,0.5))<=3.2,"far spot is beyond REACH 1.8 but inside the generic 3.2 reach")
	expect(Survey.POINTS[2]==Vector2i(44,21) and not Shy.near(Vector2(Survey.POINTS[2])+Vector2(0.5,0.5)),"standing on the B2 survey point (44,21) is not near the mushroom")
	expect(int(Catalog.entry(7).get("layout_template",0))==2 and int(Catalog.entry(13).get("layout_template",0))==2,"B7 and B13 reuse layout template 2 (same cave shape)")

func check_gates(mode:String) -> void:
	var tag:="[%s gates]"%mode
	# B2 not opened yet (player placed there by fixture).
	var locked:=new_world(mode,1)
	refuse_all(locked,ALPHA,tag+" unlocked=1")
	var plain:=base_water(locked,ALPHA,Shy.MUSHROOM,tag+" unlocked=1 water on the mushroom cell")
	var beside:=base_water(locked,ALPHA,SPOT,tag+" unlocked=1 water beside it")
	expect(plain==beside,"%s unlocked=1: watering (46,23) gives the plain base result (%s vs neighbour %s)"%[tag,brief(plain),brief(beside)])
	# Picnic not done.
	var early:=new_world(mode,5)
	early.state["picnic"]=false
	refuse_all(early,ALPHA,tag+" picnic=false")
	plain=base_water(early,ALPHA,Shy.MUSHROOM,tag+" picnic=false water on the mushroom cell")
	beside=base_water(early,ALPHA,SPOT,tag+" picnic=false water beside it")
	expect(plain==beside,"%s picnic=false: watering (46,23) gives the plain base result (%s vs neighbour %s)"%[tag,brief(plain),brief(beside)])
	# Same cave shape on B7 / B13 and other regions.
	var deep:=new_world(mode,15)
	for region in ["mine_7","mine_13","mine_1","mine_3",World.REGIONS.JINGUASHI,World.REGIONS.HOME]:
		place(deep,ALPHA,region,SPOT)
		refuse_all(deep,ALPHA,"%s region %s"%[tag,region])
	for region in ["mine_7","mine_13"]:
		place(deep,ALPHA,region,SPOT)
		plain=base_water(deep,ALPHA,Shy.MUSHROOM,"%s %s water on (46,23)"%[tag,region])
		beside=base_water(deep,ALPHA,SPOT,"%s %s water beside it"%[tag,region])
		expect(plain==beside,"%s %s: watering (46,23) gives the plain base result (%s vs neighbour %s)"%[tag,region,brief(plain),brief(beside)])
	# Right floor, but too far / wrong target cell / extra payload.
	var w:=new_world(mode,2)
	place(w,ALPHA,Shy.REGION,SPOT_FAR)
	refuse_all(w,ALPHA,tag+" 2.2 tiles from the mushroom")
	var splash:=refused(w,ALPHA,"water",Shy.MUSHROOM,tag+" water from 2.2 tiles")
	expect(outcome(splash)!="too_early" and outcome(splash)!="water","%s water from out of reach never reaches the mushroom (got %s)"%[tag,brief(splash)])
	place(w,ALPHA,Shy.REGION,Mines.REST)
	refuse_all(w,ALPHA,tag+" from the main chamber")
	place(w,ALPHA,Shy.REGION,SPOT)
	for action:String in Shy.ACTIONS:
		refused(w,ALPHA,action,SPOT,"%s %s aimed at an empty cell"%[tag,action])
		refused(w,ALPHA,action,Survey.POINTS[2],"%s %s aimed at the survey point"%[tag,action])
		refused(w,ALPHA,action,Shy.MUSHROOM,"%s %s with a non-empty extra"%[tag,action],"now")
		refused(w,ALPHA,action,Shy.MUSHROOM,"%s %s with a numeric extra"%[tag,action],"4")
	var hidden:=refused(w,ALPHA,"shy_claim",Shy.MUSHROOM,tag+" claim while hidden")
	expect(outcome(hidden)=="hidden","%s early claim reports outcome hidden (got %s)"%[tag,brief(hidden)])
	expect(not w.state.players[ALPHA].has(FIELD) and watch(w,ALPHA).is_empty(),tag+" nothing above made progress or started a wait")
	# unlocked exactly 2 is enough.
	var start:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(start.get("ok",false)==true and outcome(start)=="start",tag+" available as soon as B2 is open (got %s)"%brief(start))

func check_core(mode:String) -> void:
	var tag:="[%s]"%mode
	var w:=new_world(mode,5)
	expect(record(w,ALPHA)==Shy.fresh() and not w.state.players[ALPHA].has(FIELD) and watch(w,ALPHA).is_empty(),tag+" starts hidden: no record, no anchor")
	# Original B2 survey before touching the mushroom.
	place(w,ALPHA,Shy.REGION,Survey.POINTS[2])
	var seen:=act(w,ALPHA,"survey_observe",Survey.POINTS[2])
	expect(seen.get("ok",false)==true and not seen.has("shy") and Survey.own_record(w.state,ALPHA).seen=={"2":true},"%s B2 survey works before the mushroom (got %s)"%[tag,str(seen)])
	refuse_all(w,ALPHA,tag+" standing on the survey point")
	var depths:Dictionary=w.state.mine_depths.duplicate(true)
	var survey:Dictionary=w.state.mine_survey.duplicate(true)
	place(w,ALPHA,Shy.REGION,SPOT)
	var start_bag:=bag(w,ALPHA)
	var start_fiber:=fiber(w,ALPHA)
	# Watering too early: hint only.
	var early:=refused(w,ALPHA,"water",Shy.MUSHROOM,tag+" water at stage 0")
	expect(outcome(early)=="too_early" and mirrors(early,rec(0,false)) and shape_problem(early).is_empty(),"%s too-early water reports too_early (got %s, shape %s)"%[tag,brief(early),shape_problem(early)])
	expect(not w.state.players[ALPHA].has(FIELD) and bag(w,ALPHA)==start_bag,tag+" too-early water writes no record and costs nothing")
	# First press starts the quiet wait.
	var t0:=float(w.state.time)
	var start:=act_twice(w,ALPHA,"shy_wait",Shy.MUSHROOM,tag+" start")
	expect(start.get("ok",false)==true and outcome(start)=="start" and absf(remaining(start)-Shy.WAIT_SECONDS)<0.001 and mirrors(start,rec(0,false)),"%s first press starts a 4.0 s wait (got %s)"%[tag,brief(start)])
	expect(absf(num(start,"since")-t0)<0.001 and absf(num(start,"x")-pos(w,ALPHA).x)<0.001 and absf(num(start,"y")-pos(w,ALPHA).y)<0.001,"%s start result describes the live anchor (since=%.3f x=%.3f y=%.3f, want %.3f %s)"%[tag,num(start,"since"),num(start,"x"),num(start,"y"),t0,str(pos(w,ALPHA))])
	expect(has_cue(start,Shy.CUE_RUSTLE),tag+" start carries the rustle cue")
	expect(not w.state.players[ALPHA].has(FIELD),tag+" no durable record is written while only waiting")
	expect(not watch(w,ALPHA).is_empty() and watch(w,ALPHA).has("since"),"%s the anchor lives in host memory (_shy_watch: %s)"%[tag,str(watch(w,ALPHA))])
	expect(stray_shy_state(w.state).is_empty(),"%s the anchor is not in state: %s"%[tag,str(stray_shy_state(w.state))])
	var soon:=act_twice(w,ALPHA,"shy_wait",Shy.MUSHROOM,tag+" press again at once")
	expect(soon.get("ok",false)==true and outcome(soon)=="waiting" and absf(remaining(soon)-Shy.WAIT_SECONDS)<0.001,"%s pressing again immediately is waiting with 4.0 left (got %s)"%[tag,brief(soon)])
	advance(w,1.5,tag+" 1.5 s")
	var mid:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(mid.get("ok",false)==true and outcome(mid)=="waiting" and absf(remaining(mid)-2.5)<0.001 and absf(num(mid,"since")-t0)<0.001,"%s after 1.5 s: waiting, 2.5 left (got %s)"%[tag,brief(mid)])
	# Small drift keeps the wait.
	var anchor:=pos(w,ALPHA)
	w.move_player(ALPHA,Vector2.LEFT,0.1)
	var drift:=pos(w,ALPHA).distance_to(anchor)
	expect(drift>0.2 and drift<Shy.DRIFT,"%s fixture: real move_player drifted %.2f tiles (<0.75)"%[tag,drift])
	var drifted:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(drifted)=="waiting" and absf(remaining(drifted)-2.5)<0.001 and absf(num(drifted,"since")-t0)<0.001,"%s a %.2f-tile drift keeps the wait (got %s)"%[tag,drift,brief(drifted)])
	# A too-early splash during the wait is still only a hint.
	var splash:=refused(w,ALPHA,"water",Shy.MUSHROOM,tag+" water during the wait")
	expect(outcome(splash)=="too_early",tag+" water during the wait reports too_early")
	var still:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(still)=="waiting" and absf(num(still,"since")-t0)<0.001,"%s the too-early splash did not restart the wait (got %s)"%[tag,brief(still)])
	# Walking away (and back to the same place) restarts the wait, nothing else.
	for tick in 8:w.move_player(ALPHA,Vector2.UP,0.05)
	var away:=pos(w,ALPHA).distance_to(anchor)
	expect(away>Shy.DRIFT,"%s fixture: real move_player walked %.2f tiles away (>0.75)"%[tag,away])
	expect(watch(w,ALPHA).is_empty(),"%s walking %.2f tiles away clears the host-memory anchor (still %s)"%[tag,away,str(watch(w,ALPHA))])
	for tick in 8:w.move_player(ALPHA,Vector2.DOWN,0.05)
	w.move_player(ALPHA,Vector2.RIGHT,0.1)
	expect(pos(w,ALPHA).distance_to(anchor)<0.1 and Shy.near(pos(w,ALPHA)),"%s fixture: walked back to the same spot (%.3f from the anchor)"%[tag,pos(w,ALPHA).distance_to(anchor)])
	advance(w,3.0,tag+" 3.0 s")
	var t1:=float(w.state.time)
	var again:=act_twice(w,ALPHA,"shy_wait",Shy.MUSHROOM,tag+" press after walking away and back")
	expect(again.get("ok",false)==true and outcome(again)=="start" and absf(remaining(again)-Shy.WAIT_SECONDS)<0.001 and absf(num(again,"since")-t1)<0.001,"%s 4.5 s after the first press, but having walked away and back: the wait restarts with 4.0 left, it does not peek (got %s)"%[tag,brief(again)])
	expect(not w.state.players[ALPHA].has(FIELD) and bag(w,ALPHA)==start_bag,tag+" walking away costs nothing and loses nothing")
	# The full quiet wait.
	advance(w,3.5,tag+" 3.5 s")
	var nearly:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(nearly)=="waiting" and absf(remaining(nearly)-0.5)<0.001,"%s 3.5 s in: waiting with 0.5 left (got %s)"%[tag,brief(nearly)])
	expect(not w.state.players[ALPHA].has(FIELD),tag+" still no record before the peek")
	advance(w,0.5,tag+" last 0.5 s")
	var peek:=act_twice(w,ALPHA,"shy_wait",Shy.MUSHROOM,tag+" peek")
	expect(peek.get("ok",false)==true and outcome(peek)=="peek" and mirrors(peek,rec(1,false)) and has_cue(peek,Shy.CUE_PEEK),"%s exactly 4.0 s of real ticks makes it peek (got %s)"%[tag,brief(peek)])
	expect(record(w,ALPHA)==rec(1,false) and w.state.players[ALPHA].has(FIELD),"%s record is stage 1 (got %s)"%[tag,str(record(w,ALPHA))])
	expect(watch(w,ALPHA).is_empty() and absf(num(peek,"since")+1.0)<0.001,"%s the anchor is gone after the peek (since=%.2f, watch %s)"%[tag,num(peek,"since"),str(watch(w,ALPHA))])
	expect(record(w,BETA)==Shy.fresh() and not w.state.players[BETA].has(FIELD),tag+" beta untouched by alpha's peek")
	var idle:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(record(w,ALPHA)==rec(1,false) and watch(w,ALPHA).is_empty() and outcome(idle) not in ["start","waiting","peek"],"%s pressing interact on a peeking mushroom neither restarts nor advances (got %s)"%[tag,brief(idle)])
	var not_yet:=refused(w,ALPHA,"shy_claim",Shy.MUSHROOM,tag+" claim at stage 1")
	expect(outcome(not_yet)=="hidden","%s claim at stage 1 reports hidden (got %s)"%[tag,brief(not_yet)])
	# Ordinary watering can at stage 1.
	var person:=player_without(w,ALPHA,[FIELD,"receipts"])
	var water:=act_twice(w,ALPHA,"water",Shy.MUSHROOM,tag+" water at stage 1")
	expect(water.get("ok",false)==true and outcome(water)=="water" and mirrors(water,rec(2,false)) and has_cue(water,Shy.CUE_SPLASH) and has_cue(water,Shy.CUE_OPEN),"%s the ordinary water action opens it (got %s)"%[tag,brief(water)])
	expect(record(w,ALPHA)==rec(2,false),"%s record is stage 2 (got %s)"%[tag,str(record(w,ALPHA))])
	expect(bag(w,ALPHA)==start_bag,"%s watering the mushroom consumes no item (before %s after %s)"%[tag,str(start_bag),str(bag(w,ALPHA))])
	expect(player_without(w,ALPHA,[FIELD,"receipts"])==person,tag+" watering changes nothing on the player except the record and the receipt")
	for action in ["water","shy_wait"]:
		var done:=refused(w,ALPHA,action,Shy.MUSHROOM,tag+" open mushroom")
		expect(outcome(done)=="open","%s %s on an open mushroom reports open (got %s)"%[tag,action,brief(done)])
	expect(bag(w,ALPHA)==start_bag,tag+" nothing consumed by watering an open mushroom")
	# Inventory full: refused, record unchanged, still claimable later.
	for held in [CAP,CAP-Shy.REWARD_COUNT+1]:
		w.state.players[ALPHA].inventory[Shy.REWARD_ITEM]=held
		var full:=refused(w,ALPHA,"shy_claim",Shy.MUSHROOM,"%s claim with fiber=%d"%[tag,held])
		expect(record(w,ALPHA)==rec(2,false) and fiber(w,ALPHA)==held,"%s a full bag keeps the gift claimable (held %d, got %s)"%[tag,held,brief(full)])
	w.state.players[ALPHA].inventory[Shy.REWARD_ITEM]=start_fiber
	var claim:=act_twice(w,ALPHA,"shy_claim",Shy.MUSHROOM,tag+" claim")
	expect(claim.get("ok",false)==true and outcome(claim)=="claim" and mirrors(claim,rec(2,true)),"%s claim succeeds after freeing space (got %s)"%[tag,brief(claim)])
	expect(fiber(w,ALPHA)==start_fiber+Shy.REWARD_COUNT and record(w,ALPHA)==rec(2,true),"%s claim grants exactly +%d fiber once (%d -> %d)"%[tag,Shy.REWARD_COUNT,start_fiber,fiber(w,ALPHA)])
	var gift_bag:=bag(w,ALPHA)
	gift_bag[Shy.REWARD_ITEM]=start_fiber
	expect(gift_bag==start_bag,tag+" fiber is the only inventory change of the whole flow")
	var twice:=refused(w,ALPHA,"shy_claim",Shy.MUSHROOM,tag+" second claim")
	expect(outcome(twice)=="claimed" and fiber(w,ALPHA)==start_fiber+Shy.REWARD_COUNT,"%s a fresh claim request grants nothing more (got %s)"%[tag,brief(twice)])
	for action in ["water","shy_wait"]:
		var later:=refused(w,ALPHA,action,Shy.MUSHROOM,tag+" claimed mushroom")
		expect(outcome(later)=="open" and record(w,ALPHA)==rec(2,true),"%s %s after claiming changes nothing (got %s)"%[tag,action,brief(later)])
	expect(fiber(w,ALPHA)==start_fiber+Shy.REWARD_COUNT and record(w,BETA)==Shy.fresh() and fiber(w,BETA)==start_fiber,tag+" duplicate actions with new ids never re-grant; beta got nothing")
	# No combat / failure fields anywhere.
	for result:Dictionary in [early,start,soon,mid,again,peek,water,claim,twice]:
		expect(shape_problem(result).is_empty(),"%s result shape / no penalty field: %s in %s"%[tag,shape_problem(result),str(result)])
	for field in PENALTY_KEYS:
		expect(not w.state.players[ALPHA].get(FIELD,{}).has(field),"%s no penalty field %s on the record"%[tag,field])
	# Original B2 untouched.
	expect(w.state.mine_depths==depths,"%s mine_depths untouched by every shy action (before %s after %s)"%[tag,str(depths),str(w.state.mine_depths)])
	expect(w.state.mine_survey==survey,tag+" mine_survey untouched by every shy action")
	place(w,ALPHA,Shy.REGION,Survey.POINTS[2])
	var reread:=act(w,ALPHA,"survey_observe",Survey.POINTS[2])
	expect(reread.get("ok",false)==true and not reread.has("shy") and w.state.mine_survey==survey,"%s B2 survey still works after the mushroom is open (got %s)"%[tag,str(reread)])
	place(w,BETA,Shy.REGION,Survey.POINTS[2])
	var other:=act(w,BETA,"survey_observe",Survey.POINTS[2])
	expect(other.get("ok",false)==true and Survey.own_record(w.state,BETA).seen=={"2":true} and record(w,BETA)==Shy.fresh(),tag+" another player's first B2 survey works next to an open mushroom")
	expect(stray_shy_state(w.state).is_empty(),"%s state only holds durable records: %s"%[tag,str(stray_shy_state(w.state))])
	var disk:=on_disk(w)
	expect(not disk.is_empty() and valid(disk.duplicate(true)),tag+" final save passes SaveSchema")
	expect(stray_shy_state(disk).is_empty() and not JSON.stringify(disk).contains("_shy_watch"),"%s the save file holds no wait anchor: %s"%[tag,str(stray_shy_state(disk))])

## Watering every OTHER cell is the base game's business, whatever the mushroom stage.
func check_water_elsewhere(mode:String) -> void:
	var tag:="[%s water elsewhere]"%mode
	var control:=new_world(mode,15,[ALPHA])
	var peeking:=new_world(mode,15,[ALPHA])
	var opened:=new_world(mode,15,[ALPHA])
	advance(control,Shy.WAIT_SECONDS,tag+" control clock")
	var one:=act(peeking,ALPHA,"shy_wait",Shy.MUSHROOM)
	advance(peeking,Shy.WAIT_SECONDS,tag+" peeking wait")
	one=act(peeking,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(record(peeking,ALPHA)==rec(1,false),"%s fixture world at stage 1 (got %s)"%[tag,brief(one)])
	open_fully(opened,ALPHA,tag+" fixture world")
	var spots:Array=[
		[Shy.REGION,NEIGHBOUR,SPOT],[Shy.REGION,SPOT,SPOT],[Shy.REGION,Vector2i(46,22),SPOT],
		[Shy.REGION,Survey.POINTS[2],SPOT_FAR],[Shy.REGION,Mines.NODES[0],Mines.NODES[0]+Vector2i.UP],[Shy.REGION,Mines.REST,Mines.REST+Vector2i.UP],
		["mine_7",Shy.MUSHROOM,SPOT],["mine_7",NEIGHBOUR,SPOT],["mine_13",Shy.MUSHROOM,SPOT],["mine_13",NEIGHBOUR,SPOT],
		["mine_1",Shy.MUSHROOM,SPOT],["mine_3",Shy.MUSHROOM,SPOT],[World.REGIONS.JINGUASHI,Shy.MUSHROOM,SPOT],[World.REGIONS.HOME,Shy.MUSHROOM,SPOT],
	]
	for spot:Array in spots:
		var label:="%s %s %s"%[tag,spot[0],str(spot[1])]
		var results:Array=[]
		for world:World in [control,peeking,opened]:
			place(world,ALPHA,spot[0],spot[2])
			results.append(base_water(world,ALPHA,spot[1],label))
		expect(results[0]==results[1] and results[0]==results[2],"%s: same result whatever the mushroom stage (control %s, stage1 %s, open %s)"%[label,brief(results[0]),brief(results[1]),brief(results[2])])
	for region in ["mine_7","mine_13"]:
		place(control,ALPHA,region,SPOT)
		var cell:=control.act(ALPHA,"elsewhere-%s-a"%region,"water",Shy.MUSHROOM)
		var beside:=control.act(ALPHA,"elsewhere-%s-b"%region,"water",NEIGHBOUR)
		expect(cell==beside,"%s %s: (46,23) is an ordinary cave cell (%s vs %s)"%[tag,region,brief(cell),brief(beside)])
	expect(record(peeking,ALPHA)==rec(1,false) and record(opened,ALPHA)==rec(2,true) and not control.state.players[ALPHA].has(FIELD),tag+" none of it touched any record")

func check_players_independent() -> void:
	var tag:="[two players]"
	var w:=new_world("life",2)
	var base_fiber:=fiber(w,BETA)
	# Interleaved waits: alpha starts, beta starts 2 s later.
	var a0:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	advance(w,2.0,tag+" 2 s")
	var b0:=act(w,BETA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(a0)=="start" and outcome(b0)=="start" and absf(remaining(b0)-Shy.WAIT_SECONDS)<0.001,"%s each player starts their own wait (%s / %s)"%[tag,brief(a0),brief(b0)])
	advance(w,2.0,tag+" 2 s more")
	var a1:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	var b1:=act(w,BETA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(a1)=="peek" and record(w,ALPHA)==rec(1,false),"%s alpha peeks after their own 4 s (got %s)"%[tag,brief(a1)])
	expect(outcome(b1)=="waiting" and absf(remaining(b1)-2.0)<0.001 and record(w,BETA)==Shy.fresh() and not w.state.players[BETA].has(FIELD),"%s beta is still waiting with 2.0 left (got %s)"%[tag,brief(b1)])
	# Alpha walking off does not cancel beta's wait.
	for tick in 8:w.move_player(ALPHA,Vector2.UP,0.05)
	expect(not watch(w,BETA).is_empty(),tag+" alpha walking away keeps beta's anchor")
	place(w,ALPHA,Shy.REGION,SPOT)
	var beta_early:=refused(w,BETA,"water",Shy.MUSHROOM,tag+" beta water while alpha's is peeking")
	expect(outcome(beta_early)=="too_early",tag+" beta cannot use alpha's progress to water")
	var a2:=act(w,ALPHA,"water",Shy.MUSHROOM)
	var a3:=act(w,ALPHA,"shy_claim",Shy.MUSHROOM)
	expect(outcome(a2)=="water" and outcome(a3)=="claim" and record(w,ALPHA)==rec(2,true) and fiber(w,ALPHA)==base_fiber+Shy.REWARD_COUNT,"%s alpha opens and claims (%s / %s)"%[tag,brief(a2),brief(a3)])
	expect(record(w,BETA)==Shy.fresh() and fiber(w,BETA)==base_fiber,"%s alpha opening and claiming leaves beta at stage 0 with no gift (%s, fiber %d)"%[tag,str(record(w,BETA)),fiber(w,BETA)])
	var beta_claim:=refused(w,BETA,"shy_claim",Shy.MUSHROOM,tag+" beta claim on own hidden mushroom")
	expect(outcome(beta_claim)=="hidden",tag+" beta cannot claim alpha's gift")
	advance(w,2.0,tag+" beta's last 2 s")
	var b2:=act(w,BETA,"shy_wait",Shy.MUSHROOM)
	var b3:=act(w,BETA,"water",Shy.MUSHROOM)
	expect(outcome(b2)=="peek" and outcome(b3)=="water" and record(w,BETA)==rec(2,false),"%s beta completes their own flow (%s / %s)"%[tag,brief(b2),brief(b3)])
	# Boundary: exactly CAP-4 fiber still fits.
	w.state.players[BETA].inventory[Shy.REWARD_ITEM]=CAP-Shy.REWARD_COUNT
	var b4:=act_twice(w,BETA,"shy_claim",Shy.MUSHROOM,tag+" beta claim at CAP-4")
	expect(b4.get("ok",false)==true and fiber(w,BETA)==CAP and record(w,BETA)==rec(2,true),"%s fiber == CAP-4 still fits the gift (got %s, fiber %d)"%[tag,brief(b4),fiber(w,BETA)])
	refused(w,BETA,"shy_claim",Shy.MUSHROOM,tag+" beta second claim")
	refused(w,ALPHA,"shy_claim",Shy.MUSHROOM,tag+" alpha second claim")
	expect(fiber(w,ALPHA)==base_fiber+Shy.REWARD_COUNT and fiber(w,BETA)==CAP,tag+" exactly one gift each")
	expect(valid(on_disk(w).duplicate(true)),tag+" save with two records passes SaveSchema")

func check_save_round_trip() -> void:
	var tag:="[save]"
	var w:=new_world("life",5)
	var start:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	if outcome(start)!="start":
		expect(false,"%s stopped: shy_wait is not available (got %s)"%[tag,brief(start)])
		return
	advance(w,5.0,tag+" 5 s mid-wait")
	expect(w.save(),tag+" mid-wait save succeeds")
	var disk:=on_disk(w)
	expect(not disk.get("players",{}).get(ALPHA,{}).has(FIELD) and stray_shy_state(disk).is_empty(),"%s a mid-wait save holds no record and no anchor (%s)"%[tag,str(stray_shy_state(disk))])
	expect(valid(disk.duplicate(true)),tag+" mid-wait save passes SaveSchema")
	var again:=reopen(w,tag+" reload mid-wait")
	if again==null:return
	expect(float(again.state.time)>=float(w.state.time)-0.001,tag+" fixture: the reloaded clock is past the original 4 s mark")
	expect(watch(again,ALPHA).is_empty() and record(again,ALPHA)==Shy.fresh(),tag+" reload restores no anchor and no progress")
	var restart:=act(again,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(restart)=="start" and absf(remaining(restart)-Shy.WAIT_SECONDS)<0.001,"%s a reload mid-wait starts the wait over, it does not peek (got %s)"%[tag,brief(restart)])
	advance(again,Shy.WAIT_SECONDS,tag+" wait after reload")
	var peek:=act(again,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(peek)=="peek",tag+" peek after reload (got %s)"%brief(peek))
	disk=on_disk(again)
	var saved=disk.get("players",{}).get(ALPHA,{}).get(FIELD)
	expect(saved is Dictionary and Shy.valid(saved) and int(saved.stage)==1 and saved.claimed==false and saved.size()==2,"%s disk holds only the durable {stage,claimed} record (got %s)"%[tag,str(saved)])
	expect(not disk.get("players",{}).get(BETA,{}).has(FIELD),tag+" a player who did nothing gets no record on disk")
	var second:=reopen(again,tag+" reload at stage 1")
	if second==null:return
	expect(record(second,ALPHA)==rec(1,false) and record(second,BETA)==Shy.fresh(),"%s stage 1 survives the reload (%s)"%[tag,str(record(second,ALPHA))])
	var water:=act(second,ALPHA,"water",Shy.MUSHROOM)
	expect(outcome(water)=="water",tag+" water after reload (got %s)"%brief(water))
	var third:=reopen(second,tag+" reload at stage 2")
	if third==null:return
	expect(record(third,ALPHA)==rec(2,false),"%s stage 2 survives the reload (%s)"%[tag,str(record(third,ALPHA))])
	var held:=fiber(third,ALPHA)
	var claim:=act(third,ALPHA,"shy_claim",Shy.MUSHROOM)
	expect(claim.get("ok",false)==true and fiber(third,ALPHA)==held+Shy.REWARD_COUNT,tag+" claim after reload (got %s)"%brief(claim))
	var final:=reopen(third,tag+" reload after claim")
	if final==null:return
	expect(record(final,ALPHA)==rec(2,true) and fiber(final,ALPHA)==held+Shy.REWARD_COUNT,"%s claimed record and gift survive the reload (%s, fiber %d)"%[tag,str(record(final,ALPHA)),fiber(final,ALPHA)])
	var before:Dictionary=final.state.duplicate(true)
	var retry:=act(final,ALPHA,"shy_claim",Shy.MUSHROOM)
	expect(retry.get("ok",true)==false and outcome(retry)=="claimed" and final.state==before,tag+" a new claim after reload grants nothing")
	expect(valid(on_disk(final).duplicate(true)),tag+" final save passes SaveSchema")
	# Old save written before the feature: no field at all.
	var legacy:=on_disk(final)
	for token in legacy.players:legacy.players[token].erase(FIELD)
	expect(valid(legacy.duplicate(true)),tag+" a save without shy_mushroom passes SaveSchema")
	var legacy_path:String=final.save_path+".legacy.json"
	files.append(legacy_path)
	var file:=FileAccess.open(legacy_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var old:=World.new()
	expect(old.load_world(legacy_path) and not old.recovered_from_backup,tag+" old save without the field loads")
	if not old.state.get("players",{}).has(ALPHA):return
	old.active_tokens[ALPHA]=true
	expect(not old.state.players[ALPHA].has(FIELD) and record(old,ALPHA)==Shy.fresh(),tag+" missing field means a fresh, hidden mushroom")
	var early:=act(old,ALPHA,"water",Shy.MUSHROOM)
	expect(early.get("ok",true)==false and outcome(early)=="too_early","%s old save: water is too early (got %s)"%[tag,brief(early)])
	var hidden:=act(old,ALPHA,"shy_claim",Shy.MUSHROOM)
	expect(hidden.get("ok",true)==false and outcome(hidden)=="hidden","%s old save: cannot claim (got %s)"%[tag,brief(hidden)])
	var fresh:=act(old,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(fresh)=="start","%s old save behaves fresh (got %s)"%[tag,brief(fresh)])
	# The ONE check that writes the clock directly instead of ticking.
	old.state.time=float(old.state.time)+Shy.WAIT_SECONDS
	var direct:=act(old,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(direct)=="peek" and record(old,ALPHA)==rec(1,false),"%s (clock written directly) old save can peek (got %s)"%[tag,brief(direct)])

## A commit whose save fails is refused and rolled back (same fixture trick as
## test_mine_survey.gd: point save_path below a file). Nothing may stick.
func check_failed_save() -> void:
	var tag:="[save-fail]"
	var w:=new_world("life",5)
	var good:String=w.save_path
	var bad:String=good.path_join("missing").path_join("world.json")
	expect(w.save(),tag+" fixture file exists")
	var before:Dictionary=w.state.duplicate(true)
	w.save_path=bad
	var lost:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before,"%s a start whose save fails is refused and rolled back (got %s)"%[tag,brief(lost)])
	expect(watch(w,ALPHA).is_empty(),"%s the refused start left no anchor in host memory (%s)"%[tag,str(watch(w,ALPHA))])
	advance(w,5.0,tag+" 5 s")
	var start:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(start)=="start" and absf(remaining(start)-Shy.WAIT_SECONDS)<0.001,"%s 5 s after the refused start, the next press is a real start, not a peek (got %s)"%[tag,brief(start)])
	if outcome(start)!="start":return
	advance(w,Shy.WAIT_SECONDS,tag+" wait")
	before=w.state.duplicate(true)
	var anchor:Dictionary=watch(w,ALPHA).duplicate(true)
	w.save_path=bad
	lost=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and record(w,ALPHA)==Shy.fresh(),"%s a peek whose save fails does not advance the stage (got %s)"%[tag,brief(lost)])
	expect(watch(w,ALPHA)==anchor,"%s the failed peek rolls the host-memory anchor back too (before %s after %s)"%[tag,str(anchor),str(watch(w,ALPHA))])
	var peek:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(peek)=="peek" and record(w,ALPHA)==rec(1,false),"%s the wait survived the failed save, so the retry peeks without waiting again (got %s)"%[tag,brief(peek)])
	if record(w,ALPHA)!=rec(1,false):
		advance(w,Shy.WAIT_SECONDS,tag+" recover")
		act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
		act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	before=w.state.duplicate(true)
	w.save_path=bad
	lost=act(w,ALPHA,"water",Shy.MUSHROOM)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and record(w,ALPHA)==rec(1,false),"%s a watering whose save fails is rolled back (got %s)"%[tag,brief(lost)])
	var water:=act(w,ALPHA,"water",Shy.MUSHROOM)
	expect(outcome(water)=="water" and record(w,ALPHA)==rec(2,false),"%s the watering is still available afterwards (got %s)"%[tag,brief(water)])
	var held:=fiber(w,ALPHA)
	before=w.state.duplicate(true)
	w.save_path=bad
	lost=act(w,ALPHA,"shy_claim",Shy.MUSHROOM)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and fiber(w,ALPHA)==held and record(w,ALPHA)==rec(2,false),"%s a claim whose save fails rolls back both the fiber and the claimed flag (got %s)"%[tag,brief(lost)])
	var claim:=act(w,ALPHA,"shy_claim",Shy.MUSHROOM)
	expect(claim.get("ok",false)==true and fiber(w,ALPHA)==held+Shy.REWARD_COUNT and record(w,ALPHA)==rec(2,true),"%s the claim is still available afterwards and pays once (got %s)"%[tag,brief(claim)])

func check_schema() -> void:
	var tag:="[schema]"
	var w:=new_world("life",5)
	expect(w.save(),tag+" fixture saves")
	var base:=on_disk(w)
	expect(not base.is_empty() and valid(base.duplicate(true)),tag+" baseline save is valid")
	if base.is_empty():return
	for good in [Shy.fresh(),rec(1,false),rec(2,false),rec(2,true),{"stage":2.0,"claimed":true},{"stage":1.0,"claimed":false}]:
		var state:Dictionary=base.duplicate(true)
		state.players[ALPHA][FIELD]=good
		expect(valid(state),"%s accepts record %s"%[tag,str(good)])
	for bad in [null,{},"open",2,[2,true],{"stage":3,"claimed":false},{"stage":3,"claimed":true},{"stage":-1,"claimed":false},{"stage":0.5,"claimed":false},
			{"stage":1,"claimed":true},{"stage":0,"claimed":true},{"stage":0},{"claimed":false},{"stage":0,"claimed":0},{"stage":2,"claimed":"true"},
			{"stage":"2","claimed":true},{"stage":0,"claimed":false,"since":1.0},{"stage":0,"claimed":false,"watch":{}},{"stage":2,"claimed":true,"x":45.5,"y":23.5}]:
		var state:Dictionary=base.duplicate(true)
		state.players[ALPHA][FIELD]=bad
		expect(not valid(state),"%s rejects corrupted record %s"%[tag,str(bad)])
	# A record needs the picnic milestone.
	var plain:=World.new()
	var plain_path:String=w.save_path+".plain.json"
	files.append(plain_path)
	plain.save_path=plain_path
	plain.add_player(ALPHA,"alpha")
	expect(plain.save(),tag+" pre-picnic fixture saves")
	var young:=on_disk(plain)
	expect(not young.is_empty() and young.get("picnic",true)==false and valid(young.duplicate(true)),tag+" pre-picnic baseline is valid")
	for record_value in [Shy.fresh(),rec(1,false),rec(2,true)]:
		var state:Dictionary=young.duplicate(true)
		state.players[ALPHA][FIELD]=record_value
		expect(not valid(state),"%s rejects record %s while picnic is false"%[tag,str(record_value)])
	# A corrupted file must not load as a world.
	var broken:Dictionary=base.duplicate(true)
	broken.players[ALPHA][FIELD]={"stage":1,"claimed":true}
	var path:String=w.save_path+".broken.json"
	files.append(path)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	var loader:=World.new()
	expect(not loader.load_world(path),tag+" World refuses to load a save with a corrupted mushroom record")

## Real hoe + seed + water on a home tile, with and without mushroom progress.
func farm(w:World,prefix:String) -> Array:
	for x in range(36,40):
		for y in range(33,36):w.state.removed[World.key(Vector2i(x,y))]=true
	place(w,ALPHA,World.REGIONS.HOME,Vector2i(37,34))
	var results:Array=[]
	var steps:Array=[["water",FARM,""],["hoe",FARM,""],["water",FARM,""],["seed",FARM,"radish"],["water",FARM,""],["water",FARM,""],["water",FARM+Vector2i.RIGHT,""]]
	for i in steps.size():
		var result:Dictionary=w.act(ALPHA,"%s-farm-%d"%[prefix,i],steps[i][0],steps[i][1],steps[i][2])
		expect(not result.has("shy"),"%s farm step %d %s carries no shy payload"%[prefix,i,steps[i][0]])
		results.append(result.duplicate(true))
	return results

func check_home_farm() -> void:
	var tag:="[home farm]"
	var control:=new_world("life",5,[ALPHA])
	var w:=new_world("life",5,[ALPHA])
	advance(control,Shy.WAIT_SECONDS,tag+" control clock")
	open_fully(w,ALPHA,tag+" fixture world")
	var expected:=farm(control,"control")
	var got:=farm(w,"shy")
	expect(expected[0].get("ok",true)==false,tag+" watering untilled home ground is refused as before")
	expect(expected[1].get("ok",false)==true and expected[3].get("ok",false)==true,"%s fixture: hoe and seed succeed (%s / %s)"%[tag,str(expected[1]),str(expected[3])])
	for world:World in [control,w]:
		var plot:Dictionary=world.state.crops.get(World.key(FARM),{})
		expect(plot.get("kind","")=="radish" and plot.get("wet",false)==true and plot.get("owner","")==ALPHA,"%s the home crop is planted and wet==true (%s)"%[tag,str(plot)])
	expect(expected[4].get("ok",false)==true and got[4].get("ok",false)==true,"%s ordinary crop watering still succeeds (control %s, shy %s)"%[tag,str(expected[4]),str(got[4])])
	expect(got==expected,tag+" every farm result is identical with and without mushroom progress")
	for i in mini(got.size(),expected.size()):
		if got[i]!=expected[i]:print("%s step %d differs: control=%s shy=%s"%[tag,i,str(expected[i]),str(got[i])])
	expect(w.state.crops==control.state.crops,tag+" home crops identical to the control world")
	for field in ["crop_care","coins","mine_energy"]:
		expect(w.state.players[ALPHA].get(field)==control.state.players[ALPHA].get(field),"%s player %s identical to the control world"%[tag,field])
	var mine:=bag(w,ALPHA)
	var theirs:=bag(control,ALPHA)
	mine.erase(Shy.REWARD_ITEM)
	theirs.erase(Shy.REWARD_ITEM)
	expect(mine==theirs and fiber(w,ALPHA)-fiber(control,ALPHA)==Shy.REWARD_COUNT,tag+" inventories match apart from the mushroom's +4 fiber")
	expect(record(w,ALPHA)==rec(2,true) and not control.state.players[ALPHA].has(FIELD),tag+" farming never touches the mushroom record")
	expect(valid(on_disk(w).duplicate(true)) and valid(on_disk(control).duplicate(true)),tag+" both saves pass SaveSchema")

## The same base mine actions, in the same order, in a world where the mushroom was
## opened and claimed and in a control world where nobody touched it.
func base_actions(w:World,prefix:String) -> Array:
	var results:Array=[]
	var steps:Array=[
		["survey_observe",Survey.POINTS[2],"",Shy.REGION,SPOT_FAR],
		["survey_observe",Survey.POINTS[2],"",Shy.REGION,SPOT_FAR],
		["pick",Mines.NODES[0],"",Shy.REGION,Mines.NODES[0]+Vector2i.UP],
		["mine_rest",Mines.REST,"",Shy.REGION,Mines.REST+Vector2i.UP],
		["mine_travel",Mines.DOWN,"mine_3",Shy.REGION,Mines.DOWN+Vector2i.UP],
		["pick",Mines.NODES[1],"","mine_3",Mines.NODES[1]+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_2","mine_3",Mines.UP+Vector2i.UP],
		["pick",Mines.NODES[2],"",Shy.REGION,Mines.NODES[2]+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_1",Shy.REGION,Mines.UP+Vector2i.UP],
		["mine_mud_lure",Mines.MUD_GATE,"","mine_1",Mines.MUD_GATE+Vector2i.DOWN],
		["mine_mud_claim",Mines.MUD_REWARD,"","mine_1",Mines.MUD_REWARD],
		["mine_travel",Mines.DOWN,"mine_2","mine_1",Mines.DOWN+Vector2i.UP],
	]
	for i in steps.size():
		var step:Array=steps[i]
		expect(w.player_region(ALPHA)==step[3],"%s step %d (%s) starts in %s (in %s)"%[prefix,i,step[0],step[3],w.player_region(ALPHA)])
		place(w,ALPHA,step[3],step[4])
		var id:="%s-base-%d"%[prefix,i]
		var result:Dictionary=w.act(ALPHA,id,step[0],step[1],step[2])
		var copy:Dictionary=result.duplicate(true)
		expect(result.get("ok",false)==true,"%s base action %d %s succeeds (%s)"%[prefix,i,step[0],str(result.get("message",""))])
		if result.get("ok",false) and not result.get("unchanged",false):
			var after:Dictionary=w.state.duplicate(true)
			expect(w.act(ALPHA,id,step[0],step[1],step[2])==copy and w.state==after,"%s base action %d %s replays its receipt unchanged"%[prefix,i,step[0]])
			expect(w.state.players[ALPHA].receipts.get(id)==copy,"%s base action %d %s stored its receipt"%[prefix,i,step[0]])
		expect(not copy.has("shy"),"%s base action %d %s carries no shy payload"%[prefix,i,step[0]])
		results.append(copy)
	return results

func check_base_mine_actions() -> void:
	var tag:="[base]"
	var control:=new_world("life",5,[ALPHA])
	var w:=new_world("life",5,[ALPHA])
	for world:World in [control,w]:
		world.state.players[ALPHA].inventory["reinforced_pick"]=1
		world.state.players[ALPHA].inventory["radish"]=1
	# Same clock in both worlds, so node cooldown stamps are comparable.
	advance(control,Shy.WAIT_SECONDS,tag+" control clock")
	var opened:=open_fully(w,ALPHA,tag+" fixture world")
	expect(opened,tag+" mushroom opened and claimed before the base actions (otherwise this section only proves today's baseline)")
	var expected:=base_actions(control,"control")
	var got:=base_actions(w,"shy")
	expect(got==expected,tag+" every base mine result is identical with and without mushroom progress")
	for i in mini(got.size(),expected.size()):
		if got[i]!=expected[i]:print("%s step %d differs: control=%s shy=%s"%[tag,i,str(expected[i]),str(got[i])])
	var mine:=bag(w,ALPHA)
	var theirs:=bag(control,ALPHA)
	var extra:=int(mine.get(Shy.REWARD_ITEM,0))-int(theirs.get(Shy.REWARD_ITEM,0))
	mine.erase(Shy.REWARD_ITEM)
	theirs.erase(Shy.REWARD_ITEM)
	expect(mine==theirs,tag+" inventories match apart from the mushroom's fiber")
	expect(extra==(Shy.REWARD_COUNT if opened else 0),"%s the only difference is the +%d fiber gift (diff %d)"%[tag,Shy.REWARD_COUNT,extra])
	for field in ["mine_energy","mud_alcove","region","travel_epoch","coins","x","y"]:
		expect(w.state.players[ALPHA].get(field)==control.state.players[ALPHA].get(field),"%s player %s identical to the control world"%[tag,field])
	expect(Survey.own_record(w.state,ALPHA)==Survey.own_record(control.state,ALPHA) and Survey.own_record(w.state,ALPHA).seen=={"2":true},tag+" B2 survey page recorded exactly as in the control world")
	expect(w.state.mine_survey==control.state.mine_survey,tag+" mine_survey identical to the control world")
	expect(w.state.mine_depths==control.state.mine_depths,"%s shared mine progress identical to the control world (%s vs %s)"%[tag,str(w.state.mine_depths),str(control.state.mine_depths)])
	if opened:expect(record(w,ALPHA)==rec(2,true),tag+" base mine actions never touch the mushroom record")
	expect(not control.state.players[ALPHA].has(FIELD),tag+" a player who never visited the mushroom gets no record written")
	expect(valid(on_disk(w).duplicate(true)) and valid(on_disk(control).duplicate(true)),tag+" both saves pass SaveSchema")

## Adventure mode keeps its B1 mud duel exactly as it is.
func check_adventure_mud() -> void:
	var tag:="[adventure mud]"
	var control:=new_world("adventure",5,[ALPHA])
	var w:=new_world("adventure",5,[ALPHA])
	advance(control,Shy.WAIT_SECONDS,tag+" control clock")
	open_fully(w,ALPHA,tag+" fixture world")
	var steps:Array=[["mine_mud_lure",""],["mine_mud_duel",""],["mine_mud_duel","start"],["mine_mud_duel","strike"],["mine_mud_duel","dodge"],["mine_mud_claim",""],["shy_wait",""],["water",""]]
	var logs:Array=[]
	for world:World in [control,w]:
		world.state.players[ALPHA].inventory["radish"]=1
		place(world,ALPHA,Mines.MUD_REGION,Mines.MUD_GATE+Vector2i.DOWN)
		var results:Array=[]
		for i in steps.size():
			var target:Vector2i=Mines.MUD_REWARD if steps[i][0]=="mine_mud_claim" else Mines.MUD_GATE
			var result:Dictionary=world.act(ALPHA,"mud-%d"%i,steps[i][0],target,steps[i][1])
			if steps[i][0].begins_with("mine_mud"):expect(not result.has("shy"),"%s %s(%s) carries no shy payload"%[tag,steps[i][0],steps[i][1]])
			else:expect(result.get("ok",true)==false,"%s %s aimed at the B1 mud gate is refused (got %s)"%[tag,steps[i][0],brief(result)])
			results.append(result.duplicate(true))
		logs.append(results)
	for i in steps.size():
		if not steps[i][0].begins_with("mine_mud"):continue
		expect(logs[0][i]==logs[1][i],"%s %s(%s) identical with and without mushroom progress (control %s, shy %s)"%[tag,steps[i][0],steps[i][1],str(logs[0][i]),str(logs[1][i])])
	expect(logs[0][0].get("ok",true)==false,tag+" fixture: adventure mode still refuses the life-mode lure")
	expect(w.state.players[ALPHA].get("mud_duel")==control.state.players[ALPHA].get("mud_duel") and w.state.players[ALPHA].get("mud_alcove")==control.state.players[ALPHA].get("mud_alcove"),tag+" mud duel / alcove state identical to the control world")
	expect(record(w,ALPHA)==rec(2,true),tag+" mud actions never touch the mushroom record")

func walk(w:World,token:String,target:Vector2) -> bool:
	for tick in 400:
		var player:Dictionary=w.state.players[token]
		var delta:Vector2=target-Vector2(player.x,player.y)
		if delta.length()<0.2:break
		w.move_player(token,delta.normalized() if delta.length()>0.18 else delta,0.05)
	w.switch_region(World.REGIONS.HOME)
	return pos(w,token).distance_to(target)<0.3

func check_walkable() -> void:
	var tag:="[walk]"
	var w:=new_world("life",5,[ALPHA])
	place(w,ALPHA,Shy.REGION,Vector2i(38,21))
	expect(walk(w,ALPHA,Vector2(40.5,21.5)),tag+" main chamber -> cave mouth by real movement")
	expect(walk(w,ALPHA,Vector2(43.5,21.5)),tag+" cave mouth -> cave room")
	var seen:=w.act(ALPHA,"walk-survey","survey_observe",Survey.POINTS[2])
	expect(seen.get("ok",false)==true,tag+" survey point (44,21) usable after walking in")
	expect(walk(w,ALPHA,Vector2(44.5,21.5)),tag+" can stand on the survey point cell")
	expect(not Shy.near(pos(w,ALPHA)),tag+" standing at the survey point is not near the mushroom")
	refused(w,ALPHA,"shy_wait",Shy.MUSHROOM,tag+" from the survey point")
	for target in [Vector2(45.5,21.5),Vector2(45.5,19.5),Vector2(46.5,19.5),Vector2(46.5,22.5),Vector2(45.5,22.5),Vector2(45.5,23.5)]:
		expect(walk(w,ALPHA,target),"%s can walk through the nook to %s (at %s)"%[tag,str(target),str(pos(w,ALPHA))])
	expect(Shy.near(pos(w,ALPHA)),tag+" the mushroom is within REACH after walking to (45,23)")
	var start:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(start.get("ok",false)==true and outcome(start)=="start","%s shy_wait works from a walked-to position (got %s)"%[tag,brief(start)])
	expect(walk(w,ALPHA,Vector2(46.5,22.5)) and Shy.near(pos(w,ALPHA)),tag+" the cell above the mushroom is reachable and near")
	w.switch_region(Shy.REGION)
	var solid:bool=not w.can_stand(Vector2(Shy.MUSHROOM)+Vector2(0.5,0.5))
	w.switch_region(World.REGIONS.HOME)
	print("%s INFO the mushroom cell (46,23) %s"%[tag,"is solid (cannot be stood on)" if solid else "can be walked over"])
	expect(walk(w,ALPHA,Vector2(45.5,21.5)) and walk(w,ALPHA,Vector2(41.5,21.5)) and walk(w,ALPHA,Vector2(38.5,21.5)),tag+" can leave the cave again (nothing traps the player)")
	expect(watch(w,ALPHA).is_empty(),tag+" leaving the cave dropped the wait anchor")

func snapshot_problems(snapshot:Dictionary,tokens:Array) -> Array:
	var problems:Array=[]
	var text:=JSON.stringify(snapshot)
	for token:String in tokens:
		if text.contains(token):problems.append("raw token "+token)
	if text.contains("_shy_watch"):problems.append("text _shy_watch")
	return problems

func own_view(snapshot:Dictionary,own_id:String):
	var mine=snapshot.get("players",{}).get(own_id,{}).get(FIELD)
	if mine is Dictionary:return mine
	for key in [FIELD,"own_shy_mushroom","shy"]:
		var block=snapshot.get(key)
		if block is Dictionary and block.get("own_record") is Dictionary:return block.own_record
		if block is Dictionary and block.has("stage"):return block
	return null

func check_snapshot_privacy() -> void:
	var tag:="[snapshot]"
	var w:=new_world("life",5)
	act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	advance(w,Shy.WAIT_SECONDS,tag+" wait")
	var peek:=act(w,ALPHA,"shy_wait",Shy.MUSHROOM)
	expect(outcome(peek)=="peek" and record(w,ALPHA)==rec(1,false),tag+" alpha has progress before the snapshots are taken")
	var session:=Session.new()
	session.world=w
	session.peers[1]=BETA
	session.peers[2]=ALPHA
	var alpha_id:String=Session._public_actor(ALPHA)
	var beta_id:String=Session._public_actor(BETA)
	var shared:Dictionary=session.public_state(Shy.REGION)
	expect(snapshot_problems(shared,[ALPHA,BETA]).is_empty(),"%s public_state has no raw tokens / anchors: %s"%[tag,str(snapshot_problems(shared,[ALPHA,BETA]))])
	session._send_snapshot(1)
	var beta_view:Dictionary=session.snapshot
	expect(session.own_id==beta_id and beta_view.get("region_id")==Shy.REGION,tag+" beta receives a mine_2 snapshot under a public id")
	expect(beta_view.get("players",{}).has(alpha_id) and beta_view.get("players",{}).has(beta_id),tag+" players are keyed by public ids")
	expect(snapshot_problems(beta_view,[ALPHA,BETA]).is_empty(),"%s beta's snapshot holds no raw tokens / anchors: %s"%[tag,str(snapshot_problems(beta_view,[ALPHA,BETA]))])
	var foreign:Dictionary=beta_view.get("players",{}).get(alpha_id,{})
	expect(not foreign.is_empty() and not foreign.has(FIELD),"%s alpha's shy_mushroom record is not visible in beta's snapshot (got %s)"%[tag,str(foreign.get(FIELD,"-"))])
	for key in foreign:
		expect(not str(key).to_lower().contains("shy"),"%s alpha's entry seen by beta has no shy field (%s)"%[tag,str(key)])
	var beta_own=own_view(beta_view,beta_id)
	expect(beta_own==null or (Shy.valid(beta_own) and int(beta_own.stage)==0),"%s beta's own view is still hidden (%s)"%[tag,str(beta_own)])
	session.peers[1]=ALPHA
	session.peers[2]=BETA
	session._send_snapshot(1)
	var alpha_view:Dictionary=session.snapshot
	expect(snapshot_problems(alpha_view,[ALPHA,BETA]).is_empty(),"%s alpha's own snapshot holds no raw tokens: %s"%[tag,str(snapshot_problems(alpha_view,[ALPHA,BETA]))])
	var alpha_own=own_view(alpha_view,alpha_id)
	expect(alpha_own is Dictionary and Shy.valid(alpha_own) and int(alpha_own.stage)==1,"%s alpha's own snapshot shows own stage 1 so the client can draw the peeking frame (got %s)"%[tag,str(alpha_own)])
	expect(not alpha_view.get("players",{}).get(beta_id,{}).has(FIELD),tag+" beta's (absent) record is not invented in alpha's snapshot")
	expect(not alpha_view.get("players",{}).get(alpha_id,{}).has("receipts"),tag+" receipts never leave the server")
	session.free()
