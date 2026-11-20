extends "res://tests/network_egg_basket.gd"
## Beach Treasure over a real loopback dedicated WS room with two clients (alpha/beta).
##
## Contract under test (World.BEACH_TREASURE = B): ACTION/KEY "beach_treasure", VIEW_KEY
## "own_beach_treasure", SIGN (50,55), SPOTS = {a..f: {cell,title}}. Extras: "start" and "join:<round>"
## at SIGN, "mark:<round>" and "dig:<round>" at the exact spot cell. Shared snapshot.beach_treasure =
## {round, phase idle|search|results, remaining, found{id:true}, marks{id:true}, clues[String], score,
## guests, reason}. Private own_beach_treasure = {unlocked, joined, completed, dug, can_start}.
##
## DISCLOSURE (preseeded fixtures, not played through):
##  * Saved fixture: picnic=true. Positions are set by writing x/y on host.world.state.players[token];
##    clients never walk, so this does not prove the walking route to the sign or spots is open. Reach
##    and cell rules are still exercised through the real network action path.
##  * The secret target is never read. The test digs every spot (mark first, then dig) and learns which
##    digs were effective only from the public `found` projection. Wrong digs must change nothing.
##  * The time-loss round advances host.world.state.time directly (forward only) instead of waiting.
##  * Pacing: the server refuses more than 12 actions per 1000 ms; at most MAX_WINDOW sends per 1.1 s.
const B=World.BEACH_TREASURE
const ALPHA:="beach-treasure-alpha"
const BETA:="beach-treasure-beta"
const MAX_WINDOW:=8
const PUBLIC_KEYS:=["round","phase","remaining","found","marks","searched","clues","score","guests","reason"]
const PRIVATE_KEYS:=["unlocked","joined","completed","dug","can_start"]
var host:Session
var address:=""
var sent:Dictionary={}
var completed_by:Dictionary={}

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BEACH_TREASURE_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func make_session(branch_name:String,token:String)->Session:
	var session:=super(branch_name,token)
	sent[session]=[]
	completed_by[session]={}
	session.action_completed.connect(func(sequence:int,_name:String,result:Dictionary):completed_by[session][sequence]=result)
	return session

func own(session:Session)->Dictionary:
	return session.snapshot.get(B.VIEW_KEY,{})

func pub(session:Session)->Dictionary:
	var value:Variant=session.snapshot.get(B.KEY,{})
	return value if value is Dictionary else {}

func spot_ids()->Array:
	var ids:Array=B.SPOTS.keys()
	ids.sort()
	return ids

func spot_cell(id:String)->Vector2i:
	return B.SPOTS[id].cell

func ids_of(value:Variant)->Array:
	var out:=[]
	if value is Dictionary:
		for key in value:
			if value[key]==true:out.append(str(key))
	out.sort()
	return out

func place(token:String,cell:Vector2i)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func deep(value:Variant)->Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func footprint(token:String)->Dictionary:
	var person:Dictionary=host.world.state.players[token]
	return {"inventory":deep(person.get("inventory",{})),"picnic":host.world.state.get("picnic")}

func phase_of(session:Session)->String:
	return str(pub(session).get("phase",""))

## Public projection without the ticking countdown, for cross-client comparison.
func stable(session:Session)->Dictionary:
	var data:=pub(session).duplicate(true)
	data.erase("remaining")
	return data

func same_public(viewers:Array)->bool:
	for viewer in viewers:
		if pub(viewer).is_empty():return false
	for index in range(1,viewers.size()):
		if stable(viewers[index])!=stable(viewers[0]):return false
	return true

func wait_phase(viewers:Array,phase:String)->bool:
	return await wait_for(func():
		for viewer in viewers:
			if phase_of(viewer)!=phase:return false
		return same_public(viewers))

func wait_marks(viewers:Array,expected:Array)->bool:
	return await wait_for(func():
		for viewer in viewers:
			if ids_of(pub(viewer).get("marks"))!=expected:return false
		return same_public(viewers))

func view_is(session:Session,joined:bool)->bool:
	var view:=own(session)
	return not view.is_empty() and bool(view.get("joined",not joined))==joined

func wait_joined(session:Session,joined:bool)->bool:
	return await wait_for(func():return view_is(session,joined))

func pace(session:Session)->void:
	while true:
		var now:=Time.get_ticks_msec()
		var recent:Array=sent[session].filter(func(at:int):return now-at<=1100)
		sent[session]=recent
		if recent.size()+1<=MAX_WINDOW:return
		await process_frame

func act(session:Session,cell:Vector2i,extra:String)->bool:
	await pace(session)
	var seen:int=notices[session].size()
	sent[session].append(Time.get_ticks_msec())
	var sequence:=session.perform(B.ACTION,cell,extra)
	if not check(await wait_for(func():return notices[session].size()>seen),"Every request got an authoritative notice"):return false
	var ok:bool=notices[session].back().ok
	if completed_by[session].has(sequence):
		if not check(bool(completed_by[session][sequence].get("ok",false))==ok,"Sequence-correlated result matches the notice"):return false
	return ok

func at_sign(session:Session,token:String,extra:String)->bool:
	place(token,B.SIGN)
	return await act(session,B.SIGN,extra)

func at_spot(session:Session,token:String,id:String,extra:String)->bool:
	place(token,spot_cell(id))
	return await act(session,spot_cell(id),extra)

func start_room(port:int)->bool:
	host=make_session("BeachHost%d"%sessions.size(),"beach-treasure-host")
	var result:=host.host(port,"海灘尋寶",path,ROOM,"127.0.0.1",true,"websocket")
	if result!=OK:print("Host restart failed: ",error_string(result)," ",notices[host])
	return result==OK

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

## Saves, restarts the dedicated room, and moves the server clock to `time` (never backwards).
func restart(time:float,tag:String)->Array:
	if not check(host.world.save(),"Save the room before restart"):return []
	for session in sessions.duplicate():
		if not session.shutting_down and not check(session.shutdown(),"The previous session closes and releases its save"):return []
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port for restart"):return []
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Restart the dedicated room from the save"):return []
	host.world.state.time=maxf(float(host.world.state.time),time)
	sent={}
	var alpha:=make_session("Alpha"+tag,ALPHA)
	var beta:=make_session("Beta"+tag,BETA)
	if not check(alpha.join(address,port,"尋寶客",ROOM)==OK and beta.join(address,port,"尋寶客",ROOM)==OK,"Rejoin after restart"):return []
	if not check(await wait_for(func():return not own(alpha).is_empty() and not own(beta).is_empty() and not pub(alpha).is_empty() and not pub(beta).is_empty()),"Both clients re-entered with private views and a public treasure state"):return []
	return [alpha,beta]

## Public projection holds only the documented keys, no secret or raw token, and no private data leaks.
func privacy_ok(viewers:Array)->bool:
	for viewer in viewers:
		for key in pub(viewer).keys():
			if not PUBLIC_KEYS.has(key):return false
		for key in own(viewer).keys():
			if not PRIVATE_KEYS.has(key):return false
		for id in ids_of(pub(viewer).get("found"))+ids_of(pub(viewer).get("marks"))+ids_of(pub(viewer).get("searched")):
			if not B.SPOTS.has(id):return false
		var text:=JSON.stringify(pub(viewer)).to_lower()
		if text.contains("target") or text.contains("secret"):return false
		var private_text:=JSON.stringify(own(viewer))
		for token in [ALPHA,BETA]:
			if text.contains(token) or private_text.contains(token):return false
		for row:Dictionary in viewer.snapshot.get("players",{}).values():
			if row.has(B.KEY) or row.has(B.VIEW_KEY):return false
			var row_text:=JSON.stringify(row)
			for token in [ALPHA,BETA]:
				if row_text.contains(token):return false
	return true

func clues_ok(session:Session)->bool:
	var clues:Variant=pub(session).get("clues")
	if not clues is Array or clues.is_empty():return false
	for clue in clues:
		if not clue is String or clue.is_empty():return false
	return true

## One dig at `id` by actor=[session,token,other_session]. Returns -1 on failure, 0 for a wrong dig, 1 for an effective one.
func dig_step(rid:int,actor:Array,id:String)->int:
	var session:Session=actor[0]
	var token:String=actor[1]
	var other:Session=actor[2]
	var before_found:=ids_of(pub(session).get("found"))
	var before_score:=int(pub(session).get("score",0))
	var before_bag:=footprint(token)
	var other_dug:=bool(own(other).get("dug",false))
	var ok:=await at_spot(session,token,id,"dig:%d"%rid)
	if not check(ok,"An unexplored spot accepts one dig"):return -1
	var grew:=false
	if ok:
		grew=await wait_for(func():return ids_of(pub(session).get("found")).size()>before_found.size(),1.5)
	if grew:
		var after:=ids_of(pub(session).get("found"))
		var gained:=after.filter(func(item:String):return not before_found.has(item))
		if not check(after.size()==before_found.size()+1 and gained==[id],"An effective dig at %s found exactly that spot"%id):return -1
		if not check(await wait_for(func():return own(session).get("dug")==true),"The digger has participated"):return -1
		if not check(bool(own(other).get("dug",false))==other_dug,"The dig does not change the other player's private participation"):return -1
		if not check(footprint(token)==before_bag,"An effective dig changed the normal inventory"):return -1
		return 1
	await process_frame
	if not check(ids_of(pub(session).get("found"))==before_found and int(pub(session).get("score",0))==before_score and footprint(token)==before_bag,"A wrong dig at %s gave no point, found spot, penalty or item"%id):return -1
	return 0

func run()->void:
	path=OS.get_environment("TEMP").path_join("beach-treasure-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	if not check(B.ACTION=="beach_treasure" and B.KEY=="beach_treasure" and B.VIEW_KEY=="own_beach_treasure" and B.SIGN==Vector2i(50,55),"Rules constants match the contract"):return
	var ids:=spot_ids()
	if not check(ids==["a","b","c","d","e","f"],"Six spots a..f exist"):return
	var cells:={}
	for id in ids:
		if not check(B.SPOTS[id].get("cell") is Vector2i and not str(B.SPOTS[id].get("title","")).is_empty(),"Spot %s has a cell and title"%id):return
		cells[spot_cell(id)]=true
	if not check(cells.size()==6 and not cells.has(B.SIGN),"Spot cells are distinct and apart from the sign"):return
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"尋寶客")
		var person:Dictionary=fixture.state.players[token]
		person.x=B.SIGN.x+0.5
		person.y=B.SIGN.y+0.5
		person.coins=123
		person.inventory.wood=5
		person.inventory.fiber=3
	if not check(fixture.save(),"Save a world with the picnic done"):return
	var port:=free_port()
	if not check(port>0,"Allocate loopback port"):return
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Start real dedicated WS room"):return
	var alpha:=make_session("Alpha",ALPHA)
	var beta:=make_session("Beta",BETA)
	if not check(alpha.join(address,port,"尋寶客",ROOM)==OK and beta.join(address,port,"尋寶客",ROOM)==OK,"Join alpha and beta"):return
	if not check(await wait_for(func():return not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not own(alpha).is_empty() and not own(beta).is_empty() and not pub(alpha).is_empty() and not pub(beta).is_empty()),"Both clients entered with private views and a public treasure state"):return
	for viewer in [alpha,beta]:
		var first:=own(viewer)
		if not check(first.get("unlocked")==true and first.get("joined")==false and first.get("completed")==false and first.get("can_start")==true,"Fresh view is unlocked, not joined and may start"):return
	if not check(await wait_phase([alpha,beta],"idle") and ids_of(pub(alpha).get("found")).is_empty() and ids_of(pub(alpha).get("marks")).is_empty() and int(pub(alpha).get("score",-1))==0,"Public treasure starts idle, empty, score 0"):return
	if not check(privacy_ok([alpha,beta]),"Idle projections are private-safe"):return
	var alpha_before:=footprint(ALPHA)
	var beta_before:=footprint(BETA)
	var rid:=int(pub(alpha).get("round",0))
	# Refusals while idle.
	if not check(not await at_sign(beta,BETA,"join:%d"%rid) and not await at_spot(alpha,ALPHA,"a","mark:%d"%rid) and not await at_spot(alpha,ALPHA,"a","dig:%d"%rid),"Nothing can be joined, marked or dug while idle"):return
	place(ALPHA,B.SIGN+Vector2i(10,0))
	if not check(not await act(alpha,B.SIGN,"start") and phase_of(alpha)=="idle","Cannot start from a distance"):return
	if not check(not await at_spot(alpha,ALPHA,"a","start") and phase_of(alpha)=="idle","Cannot start at a spot"):return
	if not check(footprint(ALPHA)==alpha_before,"Idle refusals changed nothing"):return
	# Alpha starts.
	if not check(await at_sign(alpha,ALPHA,"start"),"Alpha starts at the sign"):return
	if not check(await wait_phase([alpha,beta],"search"),"Both clients see the search phase"):return
	rid=int(pub(alpha).get("round",-1))
	if not check(rid>=1 and int(pub(alpha).get("remaining",0))>0,"A started round has a number and time left"):return
	if not check(await wait_joined(alpha,true) and view_is(beta,false),"Alpha is joined, beta is not"):return
	if not check(ids_of(pub(alpha).get("found")).is_empty() and ids_of(pub(alpha).get("marks")).is_empty() and int(pub(alpha).get("score",-1))==0,"A new round has nothing found, marked or scored"):return
	if not check(clues_ok(alpha) and same_public([alpha,beta]),"Clues are shared strings"):return
	var clues:Array=pub(alpha).clues.duplicate()
	var guests_before:Variant=pub(alpha).get("guests")
	if not check(not await at_sign(alpha,ALPHA,"start") and not await at_sign(beta,BETA,"start"),"Starting during a search is refused"):return
	# Bad requests change nothing.
	if not check(not await at_spot(beta,BETA,"a","mark:%d"%rid) and not await at_spot(beta,BETA,"a","dig:%d"%rid),"A player who has not joined cannot mark or dig"):return
	if not check(not await at_sign(beta,BETA,"join:%d"%(rid-1)) and not await at_sign(beta,BETA,"join:%d"%(rid+1)) and view_is(beta,false),"Joining a stale or future round is refused"):return
	place(BETA,spot_cell("a"))
	if not check(not await act(beta,spot_cell("a"),"join:%d"%rid) and view_is(beta,false),"Joining is only possible at the sign"):return
	if not check(not await at_spot(alpha,ALPHA,"a","mark:%d"%(rid+1)) and not await at_spot(alpha,ALPHA,"a","mark:%d"%(rid-1)),"Stale and future marks are refused"):return
	if not check(not await at_spot(alpha,ALPHA,"a","dig:%d"%(rid+1)) and not await at_spot(alpha,ALPHA,"a","dig:%d"%(rid-1)),"Stale and future digs are refused"):return
	place(ALPHA,spot_cell("a"))
	if not check(not await act(alpha,spot_cell("a"),"mark") and not await act(alpha,spot_cell("a"),"mark:x") and not await act(alpha,spot_cell("a"),"dig:") and not await act(alpha,spot_cell("a"),"nonsense"),"Malformed extras are refused"):return
	if not check(not await act(alpha,spot_cell("f"),"mark:%d"%rid) and not await act(alpha,spot_cell("f"),"dig:%d"%rid),"Acting on a distant spot is refused"):return
	place(ALPHA,spot_cell("a")+Vector2i(1,0))
	if not check(not await act(alpha,spot_cell("a")+Vector2i(1,0),"mark:%d"%rid) and not await act(alpha,spot_cell("a")+Vector2i(1,0),"dig:%d"%rid),"A cell beside a spot is not a spot"):return
	place(ALPHA,spot_cell("a")+Vector2i(10,0))
	if not check(not await act(alpha,spot_cell("a"),"mark:%d"%rid) and not await act(alpha,spot_cell("a"),"dig:%d"%rid),"Cannot mark or dig from a distance"):return
	place(ALPHA,B.SIGN)
	if not check(not await act(alpha,B.SIGN,"mark:%d"%rid) and not await act(alpha,B.SIGN,"dig:%d"%rid),"Cannot mark or dig at the sign"):return
	if not check(ids_of(pub(alpha).get("found")).is_empty() and ids_of(pub(alpha).get("marks")).is_empty() and footprint(ALPHA)==alpha_before and phase_of(alpha)=="search","Refusals marked and dug nothing"):return
	# Alpha marks two spots; everyone sees them.
	if not check(await at_spot(alpha,ALPHA,"a","mark:%d"%rid) and await at_spot(alpha,ALPHA,"b","mark:%d"%rid),"Alpha marks spots a and b"):return
	if not check(await wait_marks([alpha,beta],["a","b"]),"Both clients see the shared marks"):return
	if not check(not await at_spot(alpha,ALPHA,"a","mark:%d"%rid) and not await at_spot(alpha,ALPHA,"b","mark:%d"%rid),"Repeated marks are refused"):return
	if not check(ids_of(pub(beta).get("marks"))==["a","b"],"Repeats kept the marks"):return
	# Beta joins late and gets the same clues.
	if not check(await at_sign(beta,BETA,"join:%d"%rid) and await wait_joined(beta,true),"Beta joins late at the sign"):return
	if not check(not await at_sign(beta,BETA,"join:%d"%rid) and not await at_sign(alpha,ALPHA,"join:%d"%rid),"Joining twice is refused"):return
	if not check(await wait_for(func():return same_public([alpha,beta])) and pub(beta).clues==clues and pub(alpha).clues==clues,"The late joiner sees the same clues"):return
	if not check(pub(alpha).get("guests")!=guests_before and ids_of(pub(beta).get("marks"))==["a","b"],"Guests changed on joining and marks are shared with the late joiner"):return
	if not check(not await at_spot(beta,BETA,"a","mark:%d"%rid),"Beta cannot re-mark alpha's spot"):return
	for id in ["c","d","e","f"]:
		if not check(await at_spot(beta,BETA,id,"mark:%d"%rid),"Beta marks spot %s"%id):return
	if not check(await wait_marks([alpha,beta],ids),"Both clients see all six marks"):return
	if not check(ids_of(pub(alpha).get("found")).is_empty() and int(pub(alpha).get("score",-1))==0 and phase_of(alpha)=="search","Marking alone finds and scores nothing"):return
	if not check(privacy_ok([alpha,beta]) and view_is(alpha,true) and view_is(beta,true),"Private views stay safe during shared marking"):return
	# Restart in the middle of the search (the clock only moves forward).
	var remaining_before:=int(pub(alpha).get("remaining",0))
	var again:=await restart(float(host.world.state.time)+5.0,"2")
	if again.is_empty():return
	alpha=again[0]
	beta=again[1]
	if not check(await wait_phase([alpha,beta],"search") and int(pub(alpha).get("round",-1))==rid,"The search round survived the restart"):return
	if not check(ids_of(pub(alpha).get("marks"))==ids and pub(alpha).clues==clues and clues_ok(beta),"Marks and clues survived the restart"):return
	if not check(int(pub(alpha).get("remaining",0))>0 and int(pub(alpha).get("remaining",0))<=remaining_before,"Time left survived and only moved forward"):return
	if not check(view_is(alpha,true) and view_is(beta,true),"Both players are still joined"):return
	if not check(not await at_spot(alpha,ALPHA,"a","mark:%d"%rid) and privacy_ok([alpha,beta]),"Repeated marks stay refused after the restart"):return
	# Traverse every spot (alpha first, then alternating) to guarantee an effective dig.
	var actors:=[[alpha,ALPHA,beta],[beta,BETA,alpha]]
	var effective:Array=[]
	var tried:Array=[]
	var restarted:=false
	var turn:=0
	for id in ids:
		if phase_of(alpha)!="search":break
		var result:=await dig_step(rid,actors[turn%2],id)
		if not check(result>=0,"Dig step at %s completed its checks"%id):return
		tried.append(id)
		turn+=1
		if result==1:effective.append(id)
		if not restarted and phase_of(alpha)=="search" and not effective.is_empty():
			# Restart once with a dig on record, if the round is still going.
			restarted=true
			var kept:=ids_of(pub(alpha).get("found"))
			var again2:=await restart(float(host.world.state.time)+5.0,"3")
			if again2.is_empty():return
			alpha=again2[0]
			beta=again2[1]
			actors=[[alpha,ALPHA,beta],[beta,BETA,alpha]]
			if not check(await wait_phase([alpha,beta],"search") and ids_of(pub(alpha).get("found"))==kept and int(pub(alpha).get("round",-1))==rid,"Found spots survived a restart mid-search"):return
	if not check(await wait_phase([alpha,beta],"results"),"Digging every spot finishes the round for both clients"):return
	var found:=ids_of(pub(alpha).get("found"))
	if not check(found.size()>=1 and found==ids_of(pub(beta).get("found")) and found.size()==effective.size(),"At least one spot was found, and exactly the effective digs"):return
	for id in found:
		if not check(effective.has(id) and ids.has(id),"Found spot %s came from an effective dig"%id):return
	var score:=int(pub(alpha).get("score",-1))
	var reason:=str(pub(alpha).get("reason",""))
	if not check(score==3*found.size() and int(pub(beta).get("score",-2))==score,"One settlement: three points per true spot"):return
	if not check(not reason.is_empty() and str(pub(beta).get("reason",""))==reason,"A reason is shown for the finished round"):return
	if not check(await wait_for(func():return own(alpha).get("completed")==true and own(beta).get("completed")==true),"Both participants completed the round"):return
	# No second settlement, and nothing more can be done.
	for id in ids:
		if not check(not await at_spot(alpha,ALPHA,id,"dig:%d"%rid) and not await at_spot(beta,BETA,id,"mark:%d"%rid),"After the results %s cannot be dug or marked"%id):return
	if not check(not await at_sign(alpha,ALPHA,"join:%d"%rid),"A finished round cannot be joined"):return
	for i in 20:await process_frame
	if not check(int(pub(alpha).get("score",-1))==score and int(pub(beta).get("score",-1))==score and ids_of(pub(alpha).get("found"))==found,"The score was settled once and did not change"):return
	if not check(footprint(ALPHA)==alpha_before and footprint(BETA)==beta_before,"Normal inventory is unchanged after round one"):return
	if not check(privacy_ok([alpha,beta]),"Results projections are private-safe"):return
	# Restart after the results: the settlement is persisted and not repeated.
	var settled:=await restart(float(host.world.state.time)+5.0,"4")
	if settled.is_empty():return
	alpha=settled[0]
	beta=settled[1]
	if not check(await wait_phase([alpha,beta],"results") and int(pub(alpha).get("score",-1))==score and ids_of(pub(alpha).get("found"))==found and str(pub(alpha).get("reason",""))==reason and int(pub(alpha).get("round",-1))==rid,"The finished round and its score survived the restart"):return
	if not check(own(alpha).get("completed")==true and own(beta).get("completed")==true and own(alpha).get("can_start")==true,"Completion survived and a new start is allowed"):return
	for i in 20:await process_frame
	if not check(int(pub(alpha).get("score",-1))==score,"The restart did not settle a second time"):return
	# Round two: nobody finds anything and the time runs out.
	if not check(await at_sign(alpha,ALPHA,"start"),"Alpha starts a second round"):return
	if not check(await wait_phase([alpha,beta],"search"),"Both clients see the new search"):return
	var rid2:=int(pub(alpha).get("round",-1))
	if not check(rid2>rid,"The new round has a higher number"):return
	if not check(ids_of(pub(alpha).get("found")).is_empty() and ids_of(pub(alpha).get("marks")).is_empty() and int(pub(alpha).get("score",-1))==0,"A fresh round clears found spots, marks and score"):return
	if not check(not await at_sign(beta,BETA,"join:%d"%rid) and not await at_spot(alpha,ALPHA,"a","dig:%d"%rid),"The old round's requests are stale"):return
	if not check(await at_sign(beta,BETA,"join:%d"%rid2) and await wait_joined(beta,true),"Beta joins the second round"):return
	if not check(await at_spot(beta,BETA,"c","mark:%d"%rid2) and await wait_marks([alpha,beta],["c"]),"A mark in the second round is shared"):return
	var time_before:=float(host.world.state.time)
	host.world.state.time=time_before+301.0
	if not check(await wait_phase([alpha,beta],"results"),"Time running out ends the round for both clients"):return
	if not check(ids_of(pub(alpha).get("found")).is_empty() and int(pub(alpha).get("score",-1))==0 and int(pub(alpha).get("remaining",1))<=0,"Time loss scores nothing and shows no time left"):return
	var reason2:=str(pub(alpha).get("reason",""))
	if not check(not reason2.is_empty() and reason2!=reason,"Time loss has its own reason"):return
	for id in ids:
		if not check(not await at_spot(alpha,ALPHA,id,"dig:%d"%rid2),"A timed-out round cannot be dug at %s"%id):return
	if not check(footprint(ALPHA)==alpha_before and footprint(BETA)==beta_before,"Time loss took nothing from the bag"):return
	var lost:=await restart(float(host.world.state.time)+5.0,"5")
	if lost.is_empty():return
	alpha=lost[0]
	beta=lost[1]
	if not check(await wait_phase([alpha,beta],"results") and int(pub(alpha).get("score",-1))==0 and str(pub(alpha).get("reason",""))==reason2 and int(pub(alpha).get("round",-1))==rid2,"The time-loss result survived the restart"):return
	if not check(float(host.world.state.time)>=time_before+301.0,"The server clock never moved backwards"):return
	if not check(privacy_ok([alpha,beta]) and footprint(ALPHA)==alpha_before and footprint(BETA)==beta_before,"Final state is private-safe with the normal inventory unchanged"):return
	finish(0)
