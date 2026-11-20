extends SceneTree
## B4 打瞌睡石像 integration test through the REAL World.act path (headless, in-process).
## Written against the server contract BEFORE the wiring landed in world.gd /
## save_schema.gd / session.gd, so it is expected to fail until then.
##
## Fixtures are DISCLOSED: players are placed by writing region/x/y (as in
## test_mine_survey.gd), mine_depths is seeded, and "inventory full" is produced by
## writing the crystal_sand count. Everything else goes through World.act,
## World.move_player, World.save / load_world and SaveSchema.validate.
## The hum order is ALWAYS learned from the guardian_listen result; the test never
## assumes Guardian.phrase(token, ...) is what the server uses.

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const ALPHA:="guardian-world-alpha-token"
const BETA:="guardian-world-beta-token"
const CAP:=1000000000
## Free floor cells to stand on (none is the statue, a bell or the survey point).
const SPOT_GUARDIAN:=Vector2i(34,11)
const SPOT_BELLS:=[Vector2i(33,11),Vector2i(34,11),Vector2i(36,12)]
const SPOT_OUT_OF_REACH:=Vector2i(34,13)
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
	check_players_independent()
	check_save_round_trip()
	check_failed_save()
	check_schema()
	check_base_mine_actions()
	check_walkable()
	check_snapshot_privacy()
	for file in files:
		for suffix in ["",".bak",".tmp",".bak.staged"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("SLEEPY_STONE_GUARDIAN_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ----------------------------------------------------------------- helpers --

## The world under test. Only the *_selfcheck script overrides this (to prove the
## test logic against a reference implementation of the contract).
func make_world() -> World:
	return World.new()

func new_world(mode:String,unlocked:int=5,tokens:Array=[ALPHA,BETA]) -> World:
	var w:=make_world()
	var path:String=OS.get_environment("TEMP").path_join("sleepy-guardian-world-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	files.append(path)
	w.save_path=path
	w.state["picnic"]=true
	if mode=="adventure":w.state["world_mode"]="adventure"
	w.state["mine_depths"]={"unlocked":unlocked,"ready":{},"pumped":24 if unlocked>=3 else 0,"hoist":false}
	for token:String in tokens:
		w.add_player(token,token.left(12))
		place(w,token,Guardian.REGION,SPOT_GUARDIAN)
	return w

func place(w:World,token:String,region:String,cell:Vector2i) -> void:
	var player:Dictionary=w.state.players[token]
	player["region"]=region
	player["x"]=cell.x+0.5
	player["y"]=cell.y+0.5

func stand_for(w:World,token:String,target:Vector2i) -> void:
	var bell:=Guardian.bell_at(target)
	place(w,token,Guardian.REGION,SPOT_GUARDIAN if bell<0 else SPOT_BELLS[bell])

func act(w:World,token:String,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"guardian-test-%d"%serial,action,cell,extra)

## Acts once, then replays the same request id and checks the replay is identical
## and changes nothing (record, inventory, whole state).
func act_twice(w:World,token:String,action:String,cell:Vector2i,label:String) -> Dictionary:
	serial+=1
	var id:="guardian-test-%d"%serial
	var first:Dictionary=w.act(token,id,action,cell,"")
	var copy:Dictionary=first.duplicate(true)
	var after:Dictionary=w.state.duplicate(true)
	var again:Dictionary=w.act(token,id,action,cell,"")
	expect(again==copy,"%s: same request_id replays the identical result (first=%s replay=%s)"%[label,brief(copy),brief(again)])
	expect(w.state==after,"%s: replay changes no state (no double progress / reward)"%label)
	return first

func brief(result:Dictionary) -> String:
	var g:Dictionary=payload(result)
	return "{ok=%s msg=%s guardian=%s}"%[str(result.get("ok")),str(result.get("message","")).left(28),str(g)]

func payload(result:Dictionary) -> Dictionary:
	var g=result.get("guardian")
	return g if g is Dictionary else {}

func outcome(result:Dictionary) -> String:
	return str(payload(result).get("outcome","<no guardian payload>"))

func record(w:World,token:String) -> Dictionary:
	var raw=w.state.players[token].get("sleepy_guardian",Guardian.fresh())
	if not raw is Dictionary or not Guardian.valid(raw):return {"invalid":raw}
	return {"round":int(raw.round),"calm":int(raw.calm),"claimed":bool(raw.claimed)}

func rec(stage:int,calm:int,claimed:bool) -> Dictionary:
	return {"round":stage,"calm":calm,"claimed":claimed}

func sand(w:World,token:String) -> int:
	return int(w.state.players[token].inventory.get(Guardian.REWARD_ITEM,0))

## True when the result payload mirrors the durable record.
func mirrors(result:Dictionary,want:Dictionary) -> bool:
	var g:=payload(result)
	if not g.has("round") or not g.has("calm") or not g.has("claimed") or not g.has("entered"):return false
	return int(g.round)==int(want.round) and int(g.calm)==int(want.calm) and g.claimed is bool and g.claimed==want.claimed

func entered(result:Dictionary) -> int:
	var value=payload(result).get("entered",-1)
	return int(value) if (value is int or value is float) else -1

## Listens and returns the bell indices of the hum ([] when not available).
func learn(w:World,token:String,label:String) -> Array:
	stand_for(w,token,Guardian.GUARDIAN)
	var before:=record(w,token)
	var inventory:Dictionary=w.state.players[token].inventory.duplicate(true)
	var heard:=act_twice(w,token,"guardian_listen",Guardian.GUARDIAN,label+" listen")
	expect(heard.get("ok",false)==true and outcome(heard)=="listen","%s: guardian_listen succeeds with outcome listen (got %s)"%[label,brief(heard)])
	expect(record(w,token)==before and w.state.players[token].inventory==inventory,"%s: listening is free (record and inventory unchanged)"%label)
	var notes=payload(heard).get("notes")
	var bells:Array=[]
	if notes is Array:
		for note in notes:
			var good:bool=note is Dictionary and note.has("bell") and note.has("hz") and note.has("shape") and note.has("name")
			expect(good,"%s: every note carries bell, hz, shape and name (got %s)"%[label,str(note)])
			if not good:return []
			var bell:=int(note.bell)
			expect(bell>=0 and bell<Guardian.BELLS.size() and is_equal_approx(float(note.hz),Guardian.PITCH_HZ[bell]) and note.shape==Guardian.SHAPES[bell] and note.name==Guardian.BELL_NAMES[bell],"%s: note cues match bell %d"%[label,bell])
			bells.append(bell)
	expect(bells.size()==int(before.get("round",0))+2,"%s: hum has round+2 notes (round %s, got %d)"%[label,str(before.get("round")),bells.size()])
	expect(mirrors(heard,before) and entered(heard)>=0,"%s: listen result mirrors the record"%label)
	return bells

func ring(w:World,token:String,bell:int,label:String,twice:bool=true) -> Dictionary:
	stand_for(w,token,Guardian.BELLS[bell])
	if twice:return act_twice(w,token,"guardian_ring",Guardian.BELLS[bell],label)
	return act(w,token,"guardian_ring",Guardian.BELLS[bell])

## Echoes the current hum. Returns true when the round advanced.
func solve_round(w:World,token:String,label:String) -> bool:
	var stage:=int(record(w,token).get("round",0))
	var calm:=int(record(w,token).get("calm",0))
	var bells:=learn(w,token,label)
	if bells.is_empty():return false
	var inventory:Dictionary=w.state.players[token].inventory.duplicate(true)
	for i in bells.size():
		var step:=ring(w,token,bells[i],"%s ring %d/%d"%[label,i+1,bells.size()])
		var last:bool=i==bells.size()-1
		expect(step.get("ok",false)==true and int(payload(step).get("bell",-1))==int(bells[i]),"%s: correct bell %d accepted and echoed in the result (got %s)"%[label,bells[i],brief(step)])
		if not last:
			expect(outcome(step)=="progress" and entered(step)==i+1 and mirrors(step,rec(stage,calm,false)),"%s: note %d is transient progress (got %s)"%[label,i+1,brief(step)])
			expect(record(w,token)==rec(stage,calm,false),"%s: a half-entered phrase is not written to the durable record"%label)
		else:
			var want:="awake" if stage+1>=Guardian.ROUNDS else "round"
			expect(outcome(step)==want and entered(step)==0 and mirrors(step,rec(stage+1,calm,false)),"%s: last note gives outcome %s (got %s)"%[label,want,brief(step)])
	expect(w.state.players[token].inventory==inventory,"%s: ringing costs and grants nothing"%label)
	return record(w,token)==rec(stage+1,calm,false)

func refused(w:World,token:String,action:String,cell:Vector2i,label:String) -> Dictionary:
	var before:Dictionary=w.state.duplicate(true)
	var result:=act(w,token,action,cell)
	expect(result.get("ok",true)==false and result.get("message") is String,"%s: %s is refused (got %s)"%[label,action,brief(result)])
	expect(w.state==before,"%s: refused %s changes no state"%[label,action])
	return result

func refuse_all(w:World,token:String,label:String) -> void:
	for action:String in Guardian.ACTIONS:
		var cell:Vector2i=Guardian.BELLS[1] if action=="guardian_ring" else Guardian.GUARDIAN
		refused(w,token,action,cell,label)
	expect(not w.state.players[token].has("sleepy_guardian") or record(w,token)==Guardian.fresh(),"%s: no guardian progress recorded"%label)

func valid(state:Dictionary) -> bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func on_disk(w:World) -> Dictionary:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	return parsed if parsed is Dictionary else {}

func reopen(w:World,label:String) -> World:
	var again:=make_world()
	var loaded:=again.load_world(w.save_path)
	expect(loaded and not again.recovered_from_backup and again.state.players.has(ALPHA),"%s: save loads cleanly"%label)
	return again if loaded and again.state.players.has(ALPHA) else null

# ------------------------------------------------------------------ checks --

func check_fixture_assumptions() -> void:
	expect(Guardian.near(Vector2(SPOT_GUARDIAN)+Vector2(0.5,0.5),Guardian.GUARDIAN),"test spot reaches the statue")
	for i in Guardian.BELLS.size():
		expect(Guardian.near(Vector2(SPOT_BELLS[i])+Vector2(0.5,0.5),Guardian.BELLS[i]),"test spot reaches bell %d"%i)
		expect(SPOT_BELLS[i] not in Guardian.BELLS and SPOT_BELLS[i]!=Guardian.GUARDIAN and SPOT_BELLS[i]!=Survey.POINTS[4],"bell spot %d is a free floor cell"%i)
	var away:=Vector2(SPOT_OUT_OF_REACH)+Vector2(0.5,0.5)
	expect(not Guardian.near(away,Guardian.GUARDIAN) and away.distance_to(Vector2(Guardian.GUARDIAN)+Vector2(0.5,0.5))<=3.2,"out-of-reach spot is beyond REACH 1.8 but inside the generic 3.2 reach")
	expect(not Guardian.near(Vector2(SPOT_GUARDIAN)+Vector2(0.5,0.5),Guardian.BELLS[0]),"statue spot does not reach the low bell")
	expect(int(Catalog.entry(8).get("layout_template",0))==4 and int(Catalog.entry(14).get("layout_template",0))==4,"B8 and B14 reuse layout template 4")

func check_gates(mode:String) -> void:
	var tag:="[%s gates]"%mode
	# B4 not opened yet (player placed there by fixture).
	var locked:=new_world(mode,3)
	refuse_all(locked,ALPHA,tag+" unlocked=3")
	# Same cave shape on B8 / B14 (layout template 4) and other regions.
	var deep:=new_world(mode,15)
	for region in ["mine_8","mine_14","mine_3","mine_5",World.REGIONS.JINGUASHI,World.REGIONS.HOME]:
		place(deep,ALPHA,region,SPOT_GUARDIAN)
		refuse_all(deep,ALPHA,"%s region %s"%[tag,region])
	# Right floor, but too far / wrong target cell.
	var w:=new_world(mode,4)
	place(w,ALPHA,Guardian.REGION,SPOT_OUT_OF_REACH)
	for action in ["guardian_listen","guardian_sit","guardian_claim"]:
		refused(w,ALPHA,action,Guardian.GUARDIAN,tag+" 3 tiles from the statue")
	place(w,ALPHA,Guardian.REGION,Mines.REST)
	refuse_all(w,ALPHA,tag+" from the main chamber")
	place(w,ALPHA,Guardian.REGION,SPOT_GUARDIAN)
	refused(w,ALPHA,"guardian_ring",Guardian.BELLS[0],tag+" low bell out of reach")
	refused(w,ALPHA,"guardian_ring",Guardian.BELLS[2],tag+" high bell out of reach")
	refused(w,ALPHA,"guardian_ring",Guardian.GUARDIAN,tag+" ring aimed at the statue")
	refused(w,ALPHA,"guardian_ring",SPOT_GUARDIAN,tag+" ring aimed at an empty cell")
	for action in ["guardian_listen","guardian_sit","guardian_claim"]:
		refused(w,ALPHA,action,Guardian.BELLS[1],"%s %s aimed at a bell"%[tag,action])
		refused(w,ALPHA,action,SPOT_GUARDIAN,"%s %s aimed at an empty cell"%[tag,action])
	refused(w,ALPHA,"guardian_claim",Guardian.GUARDIAN,tag+" claim while asleep")
	expect(record(w,ALPHA)==Guardian.fresh(),tag+" nothing above made progress")
	# unlocked exactly 4 is enough.
	var heard:=learn(w,ALPHA,tag+" unlocked=4")
	expect(heard.size()==2,tag+" available as soon as B4 is open")

func check_core(mode:String) -> void:
	var tag:="[%s]"%mode
	var w:=new_world(mode,5)
	expect(record(w,ALPHA)==Guardian.fresh() and sand(w,ALPHA)==0,tag+" starts asleep with no crystal sand")
	# Listen is repeatable and stable.
	var first:=learn(w,ALPHA,tag+" first hum")
	var second:=learn(w,ALPHA,tag+" second hum")
	expect(not first.is_empty() and first==second,"%s hum is stable across repeated listens (%s vs %s)"%[tag,str(first),str(second)])
	if first.is_empty():
		print("%s core scenario stopped: guardian_listen is not available (not wired yet?)"%tag)
		return
	# Round 1 (2 notes).
	expect(solve_round(w,ALPHA,tag+" round 1"),tag+" round 1 advances the record to round 1")
	expect(record(w,BETA)==Guardian.fresh(),tag+" beta untouched by alpha's round 1")
	var longer:=learn(w,ALPHA,tag+" round-2 hum")
	expect(longer.size()==3,tag+" second hum has 3 notes")
	if longer.size()!=3:return
	# Wrong bell in the middle of round 2 resets only the phrase.
	var start:=ring(w,ALPHA,longer[0],tag+" round 2 first note")
	expect(outcome(start)=="progress" and entered(start)==1,"%s first note of round 2 accepted (got %s)"%[tag,brief(start)])
	var bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	var energy:int=int(w.state.players[ALPHA].get("mine_energy",-1))
	var wrong_bell:=(int(longer[1])+1)%Guardian.BELLS.size()
	var wrong:=ring(w,ALPHA,wrong_bell,tag+" wrong bell")
	expect(wrong.get("ok",false)==true and outcome(wrong)=="wrong" and entered(wrong)==0 and mirrors(wrong,rec(1,0,false)),"%s wrong bell only restarts the phrase (got %s)"%[tag,brief(wrong)])
	expect(record(w,ALPHA)==rec(1,0,false) and w.state.players[ALPHA].inventory==bag and int(w.state.players[ALPHA].get("mine_energy",-1))==energy,tag+" wrong bell costs nothing and keeps round 1")
	var restart:=ring(w,ALPHA,longer[0],tag+" restart after wrong bell")
	expect(outcome(restart)=="progress" and entered(restart)==1,"%s phrase restarts from its first note after a wrong bell (got %s)"%[tag,brief(restart)])
	var undo:=ring(w,ALPHA,wrong_bell,tag+" second wrong bell")
	expect(outcome(undo)=="wrong" and entered(undo)==0,tag+" wrong bell again resets")
	expect(learn(w,ALPHA,tag+" hum after mistakes")==longer,tag+" mistakes never change the hum")
	# Claim is refused while asleep.
	var early:=refused(w,ALPHA,"guardian_claim",Guardian.GUARDIAN,tag+" claim before awake")
	expect(outcome(early)=="asleep","%s early claim reports outcome asleep (got %s)"%[tag,brief(early)])
	# Round 2 (3 notes) wakes it.
	expect(solve_round(w,ALPHA,tag+" round 2"),tag+" round 2 wakes the statue")
	expect(record(w,ALPHA)==rec(2,0,false) and Guardian.awake(record(w,ALPHA)),tag+" record is awake, unclaimed")
	stand_for(w,ALPHA,Guardian.GUARDIAN)
	for action in ["guardian_listen","guardian_sit"]:
		var idle:=refused(w,ALPHA,action,Guardian.GUARDIAN,tag+" awake statue")
		expect(outcome(idle)=="awake","%s %s on an awake statue reports outcome awake (got %s)"%[tag,action,brief(idle)])
	var idle_ring:=refused(w,ALPHA,"guardian_ring",Guardian.BELLS[1],tag+" awake statue")
	expect(outcome(idle_ring)=="awake",tag+" ringing an awake statue reports outcome awake")
	# Inventory full: refused, record unchanged, still claimable later.
	for held in [CAP,CAP-1]:
		w.state.players[ALPHA].inventory[Guardian.REWARD_ITEM]=held
		var full:=refused(w,ALPHA,"guardian_claim",Guardian.GUARDIAN,"%s claim with crystal_sand=%d"%[tag,held])
		expect(record(w,ALPHA)==rec(2,0,false) and sand(w,ALPHA)==held,"%s full bag keeps the reward claimable (held %d, got %s)"%[tag,held,brief(full)])
	w.state.players[ALPHA].inventory[Guardian.REWARD_ITEM]=5
	var claim:=act_twice(w,ALPHA,"guardian_claim",Guardian.GUARDIAN,tag+" claim")
	expect(claim.get("ok",false)==true and outcome(claim)=="claim" and mirrors(claim,rec(2,0,true)),"%s claim succeeds after freeing space (got %s)"%[tag,brief(claim)])
	expect(sand(w,ALPHA)==5+Guardian.REWARD_COUNT and record(w,ALPHA)==rec(2,0,true),"%s claim grants exactly +%d crystal_sand once (now %d)"%[tag,Guardian.REWARD_COUNT,sand(w,ALPHA)])
	var again:=refused(w,ALPHA,"guardian_claim",Guardian.GUARDIAN,tag+" second claim")
	expect(outcome(again)=="claimed" and sand(w,ALPHA)==5+Guardian.REWARD_COUNT,"%s a fresh claim request grants nothing more (got %s)"%[tag,brief(again)])
	# No-sound route for beta: sit three times.
	stand_for(w,BETA,Guardian.GUARDIAN)
	expect(record(w,BETA)==Guardian.fresh() and sand(w,BETA)==0,tag+" beta is still asleep after alpha finished")
	for visit in range(1,Guardian.CALM_NEEDED+1):
		var sat:=act_twice(w,BETA,"guardian_sit",Guardian.GUARDIAN,"%s sit %d"%[tag,visit])
		var done:bool=visit==Guardian.CALM_NEEDED
		expect(sat.get("ok",false)==true and outcome(sat)==("awake" if done else "sit") and mirrors(sat,rec(Guardian.ROUNDS if done else 0,visit,false)),"%s sit %d gives calm %d (got %s)"%[tag,visit,visit,brief(sat)])
	expect(record(w,BETA)==rec(2,3,false),tag+" three quiet visits wake the statue")
	var more:=refused(w,BETA,"guardian_sit",Guardian.GUARDIAN,tag+" fourth sit")
	expect(outcome(more)=="awake",tag+" sitting stops once awake")
	var gift:=act_twice(w,BETA,"guardian_claim",Guardian.GUARDIAN,tag+" sit-route claim")
	expect(gift.get("ok",false)==true and outcome(gift)=="claim" and sand(w,BETA)==Guardian.REWARD_COUNT,"%s sit route gives the same +%d crystal_sand (got %s)"%[tag,Guardian.REWARD_COUNT,brief(gift)])
	var a:=record(w,ALPHA)
	var b:=record(w,BETA)
	expect(a.get("round")==b.get("round") and a.get("claimed")==b.get("claimed") and b==rec(2,3,true),"%s both routes end awake + claimed (%s vs %s)"%[tag,str(a),str(b)])
	refused(w,BETA,"guardian_claim",Guardian.GUARDIAN,tag+" sit-route second claim")
	expect(sand(w,ALPHA)==5+Guardian.REWARD_COUNT and sand(w,BETA)==Guardian.REWARD_COUNT,tag+" exactly one reward each")
	for key in ["damage","hp","health","score","timer","penalty"]:
		expect(not payload(claim).has(key) and not w.state.players[ALPHA].get("sleepy_guardian",{}).has(key),"%s no combat / failure field %s"%[tag,key])
	var disk:=on_disk(w)
	expect(not disk.is_empty() and valid(disk.duplicate(true)),tag+" final save passes SaveSchema")

func check_players_independent() -> void:
	var tokens:Array=[]
	for i in 8:tokens.append("guardian-world-crowd-%d"%i)
	var w:=new_world("life",4,tokens)
	var orders:={}
	var heard:={}
	for token:String in tokens:
		heard[token]=learn(w,token,"[crowd] "+token.right(1))
		orders[str(heard[token])]=true
	if (heard[tokens[0]] as Array).is_empty():
		print("[crowd] stopped: guardian_listen is not available (not wired yet?)")
		return
	expect(orders.size()>=2,"[crowd] hum orders are per player (8 players share %d distinct orders)"%orders.size())
	# Interleaved input: player 0 enters one note, player 1 finishes a round, player 0 continues.
	var p0:String=tokens[0]
	var p1:String=tokens[1]
	var half:=ring(w,p0,heard[p0][0],"[crowd] p0 first note")
	expect(outcome(half)=="progress" and entered(half)==1,"[crowd] p0 half-entered")
	expect(solve_round(w,p1,"[crowd] p1 round 1"),"[crowd] p1 completes round 1 on their own")
	expect(record(w,p0)==Guardian.fresh(),"[crowd] p0's record ignores p1's round")
	var finish:=ring(w,p0,heard[p0][1],"[crowd] p0 second note")
	expect(outcome(finish)=="round" and record(w,p0)==rec(1,0,false),"[crowd] p0's half-entered phrase survived p1's ringing (got %s)"%brief(finish))
	for token:String in tokens.slice(2):
		expect(record(w,token)==Guardian.fresh() and sand(w,token)==0,"[crowd] bystander %s still asleep"%token.right(1))
	# Mixed route: one sit, then the puzzle. Calm is kept, record stays valid.
	var p2:String=tokens[2]
	stand_for(w,p2,Guardian.GUARDIAN)
	var sat:=act(w,p2,"guardian_sit",Guardian.GUARDIAN)
	expect(outcome(sat)=="sit" and record(w,p2)==rec(0,1,false),"[crowd] one sit recorded")
	solve_round(w,p2,"[crowd] p2 round 1")
	solve_round(w,p2,"[crowd] p2 round 2")
	expect(record(w,p2)==rec(2,1,false),"[crowd] puzzle after a sit wakes it and keeps calm 1 (got %s)"%str(record(w,p2)))
	expect(valid(on_disk(w).duplicate(true)),"[crowd] save with mixed records passes SaveSchema")

func check_save_round_trip() -> void:
	var w:=new_world("life",5)
	var hum:=learn(w,ALPHA,"[save] hum")
	if hum.is_empty():
		print("[save] stopped: guardian_listen is not available (not wired yet?)")
		return
	solve_round(w,ALPHA,"[save] round 1")
	var hum2:=learn(w,ALPHA,"[save] round-2 hum")
	if hum2.size()!=3:return
	var half:=ring(w,ALPHA,hum2[0],"[save] half phrase")
	expect(entered(half)==1,"[save] one note entered before saving")
	stand_for(w,BETA,Guardian.GUARDIAN)
	act(w,BETA,"guardian_sit",Guardian.GUARDIAN)
	var disk:=on_disk(w)
	var saved=disk.get("players",{}).get(ALPHA,{}).get("sleepy_guardian")
	expect(saved is Dictionary and Guardian.valid(saved) and int(saved.round)==1 and saved.size()==3,"[save] disk holds only the durable {round,calm,claimed} record (got %s)"%str(saved))
	for key in disk.get("players",{}).get(ALPHA,{}).keys():
		expect(not (str(key).contains("guardian") and str(key)!="sleepy_guardian"),"[save] no extra guardian field on the saved player (%s)"%str(key))
	expect(valid(disk.duplicate(true)),"[save] mid-puzzle save passes SaveSchema")
	var again:=reopen(w,"[save] reload")
	if again==null:return
	expect(record(again,ALPHA)==rec(1,0,false) and record(again,BETA)==rec(0,1,false),"[save] records survive the reload (%s / %s)"%[str(record(again,ALPHA)),str(record(again,BETA))])
	# If the half-entered note had been saved, ringing the first note again could
	# never report "progress, 1 entered".
	expect(learn(again,ALPHA,"[save] hum after reload")==hum2,"[save] the hum is the same after a reload")
	var first:=ring(again,ALPHA,hum2[0],"[save] first note after reload",false)
	expect(outcome(first)=="progress" and entered(first)==1,"[save] reload restarts the phrase (transient entry cleared) (got %s)"%brief(first))
	ring(again,ALPHA,hum2[1],"[save] second note after reload")
	var woke:=ring(again,ALPHA,hum2[2],"[save] third note after reload")
	expect(outcome(woke)=="awake" and record(again,ALPHA)==rec(2,0,false),"[save] round 2 completes after the reload (got %s)"%brief(woke))
	stand_for(again,ALPHA,Guardian.GUARDIAN)
	var claim:=act(again,ALPHA,"guardian_claim",Guardian.GUARDIAN)
	expect(claim.get("ok",false)==true and sand(again,ALPHA)==Guardian.REWARD_COUNT,"[save] claim after reload")
	var final:=reopen(again,"[save] reload after claim")
	if final==null:return
	expect(record(final,ALPHA)==rec(2,0,true) and sand(final,ALPHA)==Guardian.REWARD_COUNT,"[save] claimed record and reward survive a second reload")
	stand_for(final,ALPHA,Guardian.GUARDIAN)
	var before:Dictionary=final.state.duplicate(true)
	var retry:=act(final,ALPHA,"guardian_claim",Guardian.GUARDIAN)
	expect(retry.get("ok",true)==false and final.state==before,"[save] a new claim after reload grants nothing")
	# Old save written before the feature: no field at all.
	var legacy:=on_disk(final)
	for token in legacy.players:legacy.players[token].erase("sleepy_guardian")
	expect(valid(legacy.duplicate(true)),"[save] a save without sleepy_guardian passes SaveSchema")
	var legacy_path:String=final.save_path+".legacy.json"
	files.append(legacy_path)
	var file:=FileAccess.open(legacy_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var old:=make_world()
	expect(old.load_world(legacy_path) and not old.recovered_from_backup,"[save] old save without the field loads")
	if not old.state.get("players",{}).has(ALPHA):return
	expect(not old.state.players[ALPHA].has("sleepy_guardian") and record(old,ALPHA)==Guardian.fresh(),"[save] missing field means a fresh, sleeping statue")
	var fresh_hum:=learn(old,ALPHA,"[save] old save hum")
	expect(fresh_hum.size()==2,"[save] old save behaves fresh (2-note hum)")
	stand_for(old,ALPHA,Guardian.GUARDIAN)
	var early:=act(old,ALPHA,"guardian_claim",Guardian.GUARDIAN)
	expect(early.get("ok",true)==false and outcome(early)=="asleep","[save] old save cannot claim before waking it")

## A commit whose save fails is refused and rolled back (same fixture trick as
## test_mine_survey.gd: point save_path below a file). Nothing may stick, including
## the host-memory phrase entry.
func check_failed_save() -> void:
	var w:=new_world("life",5)
	var hum:=learn(w,ALPHA,"[save-fail] hum")
	if hum.is_empty():
		print("[save-fail] stopped: guardian_listen is not available (not wired yet?)")
		return
	var good:String=w.save_path
	var bad:String=good.path_join("missing").path_join("world.json")
	expect(w.save(),"[save-fail] fixture file exists")
	stand_for(w,ALPHA,Guardian.BELLS[hum[0]])
	var before:Dictionary=w.state.duplicate(true)
	w.save_path=bad
	var lost:=act(w,ALPHA,"guardian_ring",Guardian.BELLS[hum[0]])
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before,"[save-fail] a ring whose save fails is refused and rolled back (got %s)"%brief(lost))
	var retry:=ring(w,ALPHA,hum[0],"[save-fail] retry first note",false)
	expect(outcome(retry)=="progress" and entered(retry)==1,"[save-fail] the refused ring did not advance the phrase in host memory: retrying the first note gives 1 entered (got %s)"%brief(retry))
	# Keep the next check independent of the one above: make sure one note is entered.
	if entered(retry)!=1:retry=ring(w,ALPHA,hum[0],"[save-fail] re-enter first note",false)
	stand_for(w,ALPHA,Guardian.BELLS[hum[1]])
	before=w.state.duplicate(true)
	w.save_path=bad
	lost=act(w,ALPHA,"guardian_ring",Guardian.BELLS[hum[1]])
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and record(w,ALPHA)==Guardian.fresh(),"[save-fail] a round-completing ring whose save fails does not advance the round")
	var again:=ring(w,ALPHA,hum[1],"[save-fail] retry second note",false)
	expect(outcome(again)=="round" and record(w,ALPHA)==rec(1,0,false),"[save-fail] the phrase entry survived the failed save, so the retry completes round 1 (got %s)"%brief(again))
	stand_for(w,BETA,Guardian.GUARDIAN)
	before=w.state.duplicate(true)
	w.save_path=bad
	lost=act(w,BETA,"guardian_sit",Guardian.GUARDIAN)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and record(w,BETA)==Guardian.fresh(),"[save-fail] a sit whose save fails is rolled back")
	for visit in Guardian.CALM_NEEDED:act(w,BETA,"guardian_sit",Guardian.GUARDIAN)
	expect(record(w,BETA)==rec(2,3,false),"[save-fail] beta awake after three saved sits")
	before=w.state.duplicate(true)
	w.save_path=bad
	lost=act(w,BETA,"guardian_claim",Guardian.GUARDIAN)
	w.save_path=good
	expect(lost.get("ok",true)==false and w.state==before and sand(w,BETA)==0 and record(w,BETA)==rec(2,3,false),"[save-fail] a claim whose save fails rolls back both the sand and the claimed flag")
	var claim:=act(w,BETA,"guardian_claim",Guardian.GUARDIAN)
	expect(claim.get("ok",false)==true and sand(w,BETA)==Guardian.REWARD_COUNT and record(w,BETA)==rec(2,3,true),"[save-fail] the claim is still available afterwards and pays once")

func check_schema() -> void:
	var w:=new_world("life",5)
	expect(w.save(),"[schema] fixture saves")
	var base:=on_disk(w)
	expect(not base.is_empty() and valid(base.duplicate(true)),"[schema] baseline save is valid")
	if base.is_empty():return
	for good in [Guardian.fresh(),rec(1,0,false),rec(1,2,false),rec(2,0,false),rec(2,3,true),{"round":2.0,"calm":1.0,"claimed":true}]:
		var state:Dictionary=base.duplicate(true)
		state.players[ALPHA]["sleepy_guardian"]=good
		expect(valid(state),"[schema] accepts record %s"%str(good))
	for bad in [null,{},"awake",7,[2,0,true],{"round":3,"calm":0,"claimed":false},{"round":0,"calm":0},{"round":0,"calm":0,"claimed":1},
			{"round":1,"calm":0,"claimed":true},{"round":0,"calm":3,"claimed":false},{"round":-1,"calm":0,"claimed":false},
			{"round":0.5,"calm":0,"claimed":false},{"round":0,"calm":4,"claimed":false},{"round":"2","calm":0,"claimed":true},
			{"round":0,"calm":0,"claimed":false,"entered":[1]},{"round":0,"calm":0,"claimed":false,"notes":[0,1]}]:
		var state:Dictionary=base.duplicate(true)
		state.players[ALPHA]["sleepy_guardian"]=bad
		expect(not valid(state),"[schema] rejects corrupted record %s"%str(bad))
	# A corrupted file must not load as a world.
	var broken:Dictionary=base.duplicate(true)
	broken.players[ALPHA]["sleepy_guardian"]={"round":1,"calm":0,"claimed":true}
	var path:String=w.save_path+".broken.json"
	files.append(path)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	var loader:=make_world()
	expect(not loader.load_world(path),"[schema] World refuses to load a save with a corrupted guardian record")

## The same base mine actions, in the same order, in a world where the statue was
## solved and claimed and in a control world where nobody touched it.
func base_actions(w:World,prefix:String) -> Array:
	var results:Array=[]
	var steps:Array=[
		["survey_observe",Survey.POINTS[4],"",Guardian.REGION,Vector2i(34,13)],
		["survey_observe",Survey.POINTS[4],"",Guardian.REGION,Vector2i(34,13)],
		["pick",Mines.NODES[0],"",Guardian.REGION,Mines.NODES[0]+Vector2i.UP],
		["mine_rest",Mines.REST,"",Guardian.REGION,Mines.REST+Vector2i.UP],
		["mine_travel",Mines.DOWN,"mine_5",Guardian.REGION,Mines.DOWN+Vector2i.UP],
		["pick",Mines.NODES[1],"","mine_5",Mines.NODES[1]+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_4","mine_5",Mines.UP+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_3",Guardian.REGION,Mines.UP+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_2","mine_3",Mines.UP+Vector2i.UP],
		["mine_travel",Mines.UP,"mine_1","mine_2",Mines.UP+Vector2i.UP],
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
		expect(not copy.has("guardian"),"%s base action %d %s carries no guardian payload"%[prefix,i,step[0]])
		results.append(copy)
	return results

func check_base_mine_actions() -> void:
	var control:=new_world("life",5,[ALPHA])
	var w:=new_world("life",5,[ALPHA])
	for world:World in [control,w]:
		world.state.players[ALPHA].inventory["reinforced_pick"]=1
		world.state.players[ALPHA].inventory["radish"]=1
	var solved:bool=solve_round(w,ALPHA,"[base] round 1") and solve_round(w,ALPHA,"[base] round 2")
	stand_for(w,ALPHA,Guardian.GUARDIAN)
	var claim:=act(w,ALPHA,"guardian_claim",Guardian.GUARDIAN)
	expect(solved and claim.get("ok",false)==true,"[base] statue solved and claimed before the base actions (otherwise this section only proves today's baseline)")
	var expected:=base_actions(control,"control")
	var got:=base_actions(w,"guardian")
	expect(got==expected,"[base] every base mine result is identical with and without guardian progress")
	for i in mini(got.size(),expected.size()):
		if got[i]!=expected[i]:print("[base] step %d differs: control=%s guardian=%s"%[i,str(expected[i]),str(got[i])])
	var bag:Dictionary=w.state.players[ALPHA].inventory.duplicate(true)
	var control_bag:Dictionary=control.state.players[ALPHA].inventory.duplicate(true)
	var extra:=int(bag.get(Guardian.REWARD_ITEM,0))-int(control_bag.get(Guardian.REWARD_ITEM,0))
	bag.erase(Guardian.REWARD_ITEM)
	control_bag.erase(Guardian.REWARD_ITEM)
	expect(bag==control_bag,"[base] inventories match apart from the statue's crystal sand")
	expect(extra==(Guardian.REWARD_COUNT if claim.get("ok",false) else 0),"[base] the only difference is the +%d crystal_sand gift (diff %d)"%[Guardian.REWARD_COUNT,extra])
	for field in ["mine_energy","mud_alcove","region","travel_epoch","coins"]:
		expect(w.state.players[ALPHA].get(field)==control.state.players[ALPHA].get(field),"[base] player %s identical to the control world"%field)
	expect(Survey.own_record(w.state,ALPHA)==Survey.own_record(control.state,ALPHA) and Survey.own_record(w.state,ALPHA).seen=={"4":true},"[base] B4 survey page recorded exactly as in the control world")
	expect(w.state.mine_depths==control.state.mine_depths,"[base] shared mine progress identical to the control world")
	if claim.get("ok",false):expect(record(w,ALPHA)==rec(2,0,true),"[base] base mine actions never touch the guardian record")
	expect(not control.state.players[ALPHA].has("sleepy_guardian"),"[base] a player who never visited the statue gets no record written")
	expect(valid(on_disk(w).duplicate(true)) and valid(on_disk(control).duplicate(true)),"[base] both saves pass SaveSchema")

func walk(w:World,token:String,target:Vector2) -> bool:
	for tick in 400:
		var player:Dictionary=w.state.players[token]
		var delta:Vector2=target-Vector2(player.x,player.y)
		if delta.length()<0.2:break
		w.move_player(token,delta.normalized() if delta.length()>0.18 else delta,0.05)
	w.switch_region(World.REGIONS.HOME)
	var player:Dictionary=w.state.players[token]
	return Vector2(player.x,player.y).distance_to(target)<0.3

func check_walkable() -> void:
	var w:=new_world("life",5,[ALPHA])
	place(w,ALPHA,Guardian.REGION,Vector2i(34,18))
	expect(walk(w,ALPHA,Vector2(34.5,14.5)),"[walk] main chamber -> cave mouth by real movement")
	expect(walk(w,ALPHA,Vector2(34.5,13.5)),"[walk] cave mouth -> cave room")
	var here:Dictionary=w.state.players[ALPHA]
	expect(Vector2(here.x,here.y).distance_to(Vector2(Survey.POINTS[4])+Vector2(0.5,0.5))<=3.2,"[walk] survey point within the normal reach from inside the cave")
	var seen:=w.act(ALPHA,"walk-survey","survey_observe",Survey.POINTS[4])
	expect(seen.get("ok",false)==true,"[walk] survey point (34,12) usable after walking in")
	for i in Guardian.BELLS.size():
		expect(walk(w,ALPHA,Vector2(34.5,12.5)) or walk(w,ALPHA,Vector2(34.5,13.5)),"[walk] back to the middle of the cave room")
		var lane:=Vector2(SPOT_BELLS[i].x+0.5,12.5)
		expect(walk(w,ALPHA,lane) and walk(w,ALPHA,Vector2(SPOT_BELLS[i])+Vector2(0.5,0.5)),"[walk] can walk beside bell %d"%i)
		here=w.state.players[ALPHA]
		expect(Guardian.near(Vector2(here.x,here.y),Guardian.BELLS[i]),"[walk] bell %d within REACH after walking"%i)
	expect(walk(w,ALPHA,Vector2(34.5,12.5)) and walk(w,ALPHA,Vector2(SPOT_GUARDIAN)+Vector2(0.5,0.5)),"[walk] can walk in front of the statue")
	here=w.state.players[ALPHA]
	expect(Guardian.near(Vector2(here.x,here.y),Guardian.GUARDIAN),"[walk] statue within REACH after walking")
	var hum:=act(w,ALPHA,"guardian_listen",Guardian.GUARDIAN)
	expect(hum.get("ok",false)==true,"[walk] guardian_listen works from a walked-to position (got %s)"%brief(hum))
	expect(walk(w,ALPHA,Vector2(34.5,13.5)) and walk(w,ALPHA,Vector2(34.5,17.5)),"[walk] can leave the cave again (nothing traps the player)")

## Collects "path=value" strings for anything under a key that mentions the
## guardian and could carry the hum order.
func guardian_leaks(value,path:String,inside:bool,out:Array) -> void:
	if value is Dictionary:
		for key in value:
			var name:=str(key)
			var here:bool=inside or name.to_lower().contains("guardian")
			if here and name in ["notes","phrase","order","hz","seed","token","entered_bells","bells"]:out.append(path+"/"+name)
			guardian_leaks(value[key],path+"/"+name,here,out)
	elif value is Array:
		if inside:out.append(path+"=[array]")
		for i in value.size():guardian_leaks(value[i],"%s[%d]"%[path,i],inside,out)

func snapshot_problems(snapshot:Dictionary,tokens:Array) -> Array:
	var problems:Array=[]
	guardian_leaks(snapshot,"",false,problems)
	var text:=JSON.stringify(snapshot)
	for token:String in tokens:
		if text.contains(token):problems.append("raw token "+token)
	for needle in ["\"notes\"","\"hz\"","\"phrase\""]+Guardian.BELL_NAMES:
		if text.contains(needle):problems.append("text "+needle)
	return problems

func own_view(snapshot:Dictionary,own_id:String):
	var mine=snapshot.get("players",{}).get(own_id,{}).get("sleepy_guardian")
	if mine is Dictionary:return mine
	for key in ["sleepy_guardian","own_sleepy_guardian","guardian"]:
		var block=snapshot.get(key)
		if block is Dictionary and block.get("own_record") is Dictionary:return block.own_record
		if block is Dictionary and block.has("round"):return block
	return null

func check_snapshot_privacy() -> void:
	var w:=new_world("life",5)
	var solved:bool=solve_round(w,ALPHA,"[snapshot] round 1")
	var hum:=learn(w,ALPHA,"[snapshot] round-2 hum")
	if hum.size()==3:ring(w,ALPHA,hum[0],"[snapshot] half phrase")
	expect(solved,"[snapshot] alpha has progress and a half-entered phrase before the snapshots are taken")
	var session:=Session.new()
	session.world=w
	session.peers[1]=BETA
	session.peers[2]=ALPHA
	var alpha_id:String=Session._public_actor(ALPHA)
	var beta_id:String=Session._public_actor(BETA)
	var shared:Dictionary=session.public_state(Guardian.REGION)
	expect(snapshot_problems(shared,[ALPHA,BETA]).is_empty(),"[snapshot] public_state has no hum order / raw tokens: %s"%str(snapshot_problems(shared,[ALPHA,BETA])))
	session._send_snapshot(1)
	var beta_view:Dictionary=session.snapshot
	expect(session.own_id==beta_id and beta_view.get("region_id")==Guardian.REGION,"[snapshot] beta receives a mine_4 snapshot under a public id")
	expect(beta_view.get("players",{}).has(alpha_id) and beta_view.get("players",{}).has(beta_id) and beta_view.players.size()==2,"[snapshot] players are keyed by public ids only")
	var problems:=snapshot_problems(beta_view,[ALPHA,BETA])
	expect(problems.is_empty(),"[snapshot] beta's snapshot holds no notes/order for alpha and no raw tokens: %s"%str(problems))
	var foreign:Dictionary=beta_view.get("players",{}).get(alpha_id,{})
	expect(not foreign.has("receipts") and not foreign.has("inventory"),"[snapshot] alpha's entry in beta's snapshot has no receipts or inventory")
	print("[snapshot] INFO alpha's entry seen by beta %s the sleepy_guardian record (%s); mud_alcove precedent erases per-player progress at session.gd:1742"%["EXPOSES" if foreign.has("sleepy_guardian") else "does not expose",str(foreign.get("sleepy_guardian","-"))])
	var beta_own=own_view(beta_view,beta_id)
	expect(beta_own==null or (Guardian.valid(beta_own) and int(beta_own.round)==0 and int(beta_own.calm)==0),"[snapshot] beta's own view is still asleep (%s)"%str(beta_own))
	session.peers[1]=ALPHA
	session.peers[2]=BETA
	session._send_snapshot(1)
	var alpha_view:Dictionary=session.snapshot
	problems=snapshot_problems(alpha_view,[ALPHA,BETA])
	expect(problems.is_empty(),"[snapshot] even alpha's own snapshot never carries the hum order or raw tokens: %s"%str(problems))
	var alpha_own=own_view(alpha_view,alpha_id)
	expect(alpha_own is Dictionary and Guardian.valid(alpha_own) and int(alpha_own.round)==1,"[snapshot] alpha's own snapshot shows own progress round 1 so the client can draw frame 2 (got %s)"%str(alpha_own))
	expect(not alpha_view.get("players",{}).get(alpha_id,{}).has("receipts"),"[snapshot] receipts (which hold listen results) never leave the server")
	session.free()
