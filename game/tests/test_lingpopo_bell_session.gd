extends "res://tests/network_egg_basket.gd"
## T066 N08-1 over a real loopback WebSocket: 鈴婆婆's 〈不響的小鈴〉 (two in-world clues, any order, no audio).
## Two independent clients, each with a normal stage-1 bond: A inspects the tree then the bell, B the bell then the
## tree. The clues are a personal bit mask (tree=1, bell=2); the report and the first island-history page open only
## for whoever finished both. Wrong places and repeats are refused, nothing leaks to the other player's snapshot, and
## everything survives reconnect, a real save and a real host restart. The observer then completes their own.
const Goals=World.RESIDENT_GOALS
const Festival=preload("res://scripts/festival.gd")
const TOKEN_A:="lingpopo-bell-token-alpha"
const TOKEN_B:="lingpopo-bell-token-bravo"
const TOKENS:=[TOKEN_A,TOKEN_B]
const REPORT:="lingpopo:1::"
const MSG_NEED_HELLO:="先到渡口和鈴婆婆說聲你好。"
const MSG_WRONG_PLACE:="請靠近風鈴樹，或到鈴婆婆身邊查看小鈴。"
const MSG_REPEAT:="這處線索已經記下了。"
const MSG_NEED_CLUES:="還不能一起做這件事：要先「查看風鈴樹與裂開的小鈴」。"
const MSG_DONE:="已經一起完成了"
var hub:Session

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LINGPOPO_BELL_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func send_all()->void:
	for peer in hub.peers:hub._send_snapshot(peer)

func quiet(frames:int=30)->void:
	for _i in frames:await process_frame

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func person(token:String)->Dictionary:
	return hub.world.state.players[token]

func mask(token:String)->int:
	return int(person(token).get(Goals.BELL_INSPECT_KEY,0))

func own_mask(session:Session)->int:
	return int(session.snapshot.get("own_lingpopo_bell",0))

func page_state(session:Session,page:int=1)->String:
	return str(session.snapshot.get("resident_goals",{}).get("lingpopo",{}).get(str(page),{}).get("state",""))

func page_open(session:Session)->bool:
	return page_state(session)=="done"

func bell_cell()->Vector2i:
	return World.bond_place(hub.world.state,"lingpopo")[1]

func tree_cell()->Vector2i:
	return Festival.TREE_CELL

func stand(token:String,cell:Vector2i)->void:
	person(token).x=cell.x+0.5
	person(token).y=cell.y+0.5

func last_message(session:Session)->String:
	return str(notices[session].back().message)

func inspect(session:Session,cell:Vector2i,site:String)->bool:
	return await action(session,Goals.BELL_INSPECT_ACTION,cell,site)

func report(session:Session)->bool:
	return await action(session,Goals.ACTION,bell_cell(),REPORT)

func leaks_token(value:Variant)->bool:
	var text:=var_to_str(value)
	for token in TOKENS:
		if token in text:return true
	return false

## Another player's public entry must carry neither the clue mask nor goal/keepsake records.
func public_clean(viewer:Session,other:Session)->bool:
	var entry:Dictionary=viewer.snapshot.get("players",{}).get(other.own_id,{})
	return not entry.is_empty() and not entry.has(Goals.BELL_INSPECT_KEY) and not entry.has(Goals.RECORD_KEY) and not entry.has(Goals.KEEPSAKE_KEY) and not leaks_token(viewer.snapshot.get("players",{}))

func run()->void:
	path=OS.get_environment("TEMP").path_join("lingpopo-bell-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	# ------------------------------------------------------------------ fixture: normal stage-1 bonds, isolated save
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in TOKENS:
		fixture.add_player(token,"聽鈴人")
		fixture.state.players[token].x=Festival.TREE_CELL.x+0.5
		fixture.state.players[token].y=Festival.TREE_CELL.y+0.5
		fixture.state.players[token].bonds={"lingpopo":{"points":1,"talk_day":-1,"gift_day":-1}}
	if not check(fixture.save(),"Save the isolated bell fixture"):return
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port"):return
	hub=make_session("BellHost","bell-host")
	if not check(hub.host(port,"風鈴",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a real WS dedicated host"):return
	hub.set_physics_process(false)
	var a:=make_session("BellA",TOKEN_A)
	var b:=make_session("BellB",TOKEN_B)
	var address:="ws://127.0.0.1:%d"%port
	if not check(a.join(address,port,"阿鈴",ROOM)==OK and b.join(address,port,"小聽",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not a.own_id.is_empty() and not b.own_id.is_empty()),"Both enter"):return
	if not check(a.own_id!=b.own_id and not (a.own_id in TOKENS) and not (b.own_id in TOKENS),"Public ids differ and are not profile tokens"):return
	# ------------------------------------------------------------------ rules as written, no audio requirement
	var entry:Dictionary=Goals.goal("lingpopo",1)
	if not check(entry.needs==["bell_inspected"] and not entry.has("options") and not entry.has("steps") and not entry.has("items") and "不必聽聲音" in str(entry.task),"Stage 1 needs only the two inspections and says no listening is needed"):return
	if not check(Goals.BELL_TREE_BIT==1 and Goals.BELL_CRACK_BIT==2 and Goals.BELL_INSPECT_MASK==3,"Clue bits are tree=1 and bell=2"):return
	if not check(mask(TOKEN_A)==0 and mask(TOKEN_B)==0 and own_mask(a)==0 and own_mask(b)==0 and not page_open(a) and not page_open(b),"Nobody has a clue or the first page at the start"):return
	if not check(tree_cell()==Vector2i(41,28) and bell_cell().distance_to(Vector2(tree_cell()))<3.0,"Tree and 鈴婆婆 are both in the plaza"):return
	# Both players stand between the two sites so every wrong-place request is refused by the rule, not by distance.
	var between:=Vector2i(41,27)
	stand(TOKEN_A,between)
	stand(TOKEN_B,between)
	# ------------------------------------------------------------------ report before any clue
	if not check(not await report(a) and MSG_NEED_CLUES==last_message(a) and Goals.done(person(TOKEN_A),"lingpopo").is_empty() and not page_open(a),"A cannot report with no clue: %s"%last_message(a)):return
	# ------------------------------------------------------------------ A: tree first, with wrong places and repeats refused
	if not check(not await inspect(a,bell_cell(),"tree") and last_message(a)==MSG_WRONG_PLACE and mask(TOKEN_A)==0,"Tree clue at the bell cell is refused: %s"%last_message(a)):return
	if not check(not await inspect(a,tree_cell(),"bell") and last_message(a)==MSG_WRONG_PLACE and mask(TOKEN_A)==0,"Bell clue at the tree cell is refused"):return
	if not check(not await inspect(a,between,"tree") and last_message(a)==MSG_WRONG_PLACE and mask(TOKEN_A)==0,"Tree clue at an arbitrary cell is refused"):return
	if not check(not await inspect(a,tree_cell(),"") and not await inspect(a,tree_cell(),"sound") and last_message(a)==MSG_WRONG_PLACE and mask(TOKEN_A)==0,"No site or a sound-based site never counts"):return
	if not check(await inspect(a,tree_cell(),"tree") and last_message(a)=="粗枝上有一截空繩，繩結還留著。" and mask(TOKEN_A)==Goals.BELL_TREE_BIT,"A records the tree clue: %s"%last_message(a)):return
	if not check(not await inspect(a,tree_cell(),"tree") and last_message(a)==MSG_REPEAT and mask(TOKEN_A)==Goals.BELL_TREE_BIT,"A's repeated tree clue is refused: %s"%last_message(a)):return
	if not check(not await report(a) and last_message(a)==MSG_NEED_CLUES and Goals.done(person(TOKEN_A),"lingpopo").is_empty(),"One clue is not enough to report"):return
	# ------------------------------------------------------------------ B: bell first (the opposite order) is independent of A
	if not check(mask(TOKEN_B)==0,"A's clue did not touch B"):return
	if not check(not await inspect(b,tree_cell(),"bell") and last_message(b)==MSG_WRONG_PLACE and mask(TOKEN_B)==0,"B's bell clue at the tree cell is refused"):return
	if not check(await inspect(b,bell_cell(),"bell") and last_message(b)=="鈴口裂了一道，細繩還和樹上的一樣。" and mask(TOKEN_B)==Goals.BELL_CRACK_BIT,"B records the bell clue first: %s"%last_message(b)):return
	if not check(not await inspect(b,bell_cell(),"bell") and last_message(b)==MSG_REPEAT and mask(TOKEN_B)==Goals.BELL_CRACK_BIT,"B's repeated bell clue is refused"):return
	if not check(not await report(b) and last_message(b)==MSG_NEED_CLUES and Goals.done(person(TOKEN_B),"lingpopo").is_empty(),"B cannot report with only the bell clue"):return
	send_all()
	if not check(await wait_for(func():return own_mask(a)==1 and own_mask(b)==2),"Each client's private view carries only its own mask (A=1, B=2)"):return
	# ------------------------------------------------------------------ A finishes with the second clue; page opens for A only
	await create_timer(1.05).timeout
	if not check(await inspect(a,bell_cell(),"bell") and mask(TOKEN_A)==Goals.BELL_INSPECT_MASK,"A records the bell clue second"):return
	if not check(not await inspect(a,bell_cell(),"bell") and not await inspect(a,tree_cell(),"tree") and mask(TOKEN_A)==3,"A's repeats after finishing are refused and the mask stays 3"):return
	if not check(not page_open(a) and Goals.done(person(TOKEN_A),"lingpopo").is_empty(),"Inspecting alone does not unlock the page"):return
	stand(TOKEN_A,bell_cell())
	if not check(await report(a) and "島史第一頁" in last_message(a),"A reports at 鈴婆婆: %s"%last_message(a)):return
	if not check(Goals.done(person(TOKEN_A),"lingpopo").has(1) and not Goals.done(person(TOKEN_B),"lingpopo").has(1),"Host records page one for A only"):return
	send_all()
	if not check(await wait_for(func():return own_mask(a)==3 and page_open(a)),"A's own view shows mask 3 and the first page unlocked"):return
	await quiet()
	if not check(own_mask(b)==2 and not page_open(b) and page_state(b)=="open","B's own view still shows mask 2 and a locked page"):return
	if not check(public_clean(b,a) and public_clean(a,b),"Neither client sees the other's mask, goal record or profile token"):return
	if not check(not b.snapshot.has(Goals.BELL_INSPECT_KEY) and not a.snapshot.has(Goals.BELL_INSPECT_KEY),"The raw mask key is never a top-level snapshot field"):return
	var sent:=a.counter
	var settled:int=notices[a].size()
	var epoch:=int(a.snapshot.get("players",{}).get(a.own_id,{}).get("travel_epoch",0))
	a.request_action.rpc_id(1,sent,Goals.ACTION,bell_cell(),REPORT,str(a.snapshot.get("region_id","home")),epoch)
	await quiet(40)
	if not check(notices[a].size()==settled and Goals.done(person(TOKEN_A),"lingpopo").size()==1,"A retransmit of the same sequence changes nothing"):return
	if not check(not await report(a) and MSG_DONE in last_message(a),"A fresh repeat report is refused: %s"%last_message(a)):return
	# ------------------------------------------------------------------ reconnect: A keeps everything, B is still partial
	a.shutdown()
	if not check(await wait_for(func():return hub.peers.size()==1),"Host sees A leave"):return
	var returned:=make_session("BellReturned",TOKEN_A)
	if not check(returned.join(address,port,"回來的阿鈴",ROOM)==OK,"Reconnect A's profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and own_mask(returned)==3 and page_open(returned)),"Reconnect restores A's mask and the first page"):return
	if not check(returned.own_id==a.own_id and own_mask(b)==2 and not page_open(b),"A keeps the same public id; B is unchanged"):return
	# ------------------------------------------------------------------ durable reload
	if not check(hub.world.save(),"Host saves the room"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path),"The save loads in a fresh World"):return
	if not check(int(loaded.state.players[TOKEN_A].get(Goals.BELL_INSPECT_KEY,0))==3 and int(loaded.state.players[TOKEN_B].get(Goals.BELL_INSPECT_KEY,0))==2,"Save keeps A's mask 3 and B's mask 2"):return
	if not check(Goals.done(loaded.state.players[TOKEN_A],"lingpopo").has(1) and Goals.done(loaded.state.players[TOKEN_B],"lingpopo").is_empty(),"Save keeps A done and B not"):return
	# ------------------------------------------------------------------ real restart
	for session in [returned,b]:
		if not session.shutting_down:session.shutdown()
	hub.shutdown()
	await quiet(20)
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	hub=make_session("BellHostTwo","bell-host-two")
	if not check(hub.host(port2,"風鈴",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Restart the dedicated host from the save"):return
	hub.set_physics_process(false)
	var address2:="ws://127.0.0.1:%d"%port2
	var a2:=make_session("BellATwo",TOKEN_A)
	var b2:=make_session("BellBTwo",TOKEN_B)
	if not check(a2.join(address2,port2,"重開阿鈴",ROOM)==OK and b2.join(address2,port2,"重開小聽",ROOM)==OK,"Both join the restarted host"):return
	if not check(await wait_for(func():return not a2.own_id.is_empty() and not b2.own_id.is_empty() and own_mask(a2)==3 and own_mask(b2)==2),"Restarted clients see their own masks (3 and 2)"):return
	if not check(await wait_for(func():return page_open(a2) and not page_open(b2)),"After restart only A has the first page"):return
	send_all()
	await quiet()
	if not check(a2.own_id==a.own_id and b2.own_id==b.own_id and public_clean(a2,b2) and public_clean(b2,a2),"Public ids persist and the restarted views stay private"):return
	stand(TOKEN_A,bell_cell())
	stand(TOKEN_B,bell_cell())
	if not check(not await report(a2) and MSG_DONE in last_message(a2),"After restart A still cannot report twice"):return
	if not check(not await report(b2) and last_message(b2)==MSG_NEED_CLUES and Goals.done(person(TOKEN_B),"lingpopo").is_empty(),"After restart B still cannot report with one clue"):return
	# ------------------------------------------------------------------ the observer completes their own afterward (tree second)
	stand(TOKEN_B,between)
	if not check(not await inspect(b2,bell_cell(),"bell") and last_message(b2)==MSG_REPEAT and mask(TOKEN_B)==2,"B's old bell clue is still recorded after restart"):return
	if not check(await inspect(b2,tree_cell(),"tree") and mask(TOKEN_B)==3,"B records the tree clue second"):return
	if not check(not page_open(b2) and Goals.done(person(TOKEN_B),"lingpopo").is_empty(),"B's inspections alone do not unlock the page"):return
	stand(TOKEN_B,bell_cell())
	if not check(await report(b2) and "島史第一頁" in last_message(b2),"B reports on their own: %s"%last_message(b2)):return
	send_all()
	if not check(await wait_for(func():return page_open(b2) and own_mask(b2)==3 and page_open(a2) and own_mask(a2)==3),"Both now see their own mask 3 and first page"):return
	if not check(Goals.done(person(TOKEN_A),"lingpopo").size()==1 and Goals.done(person(TOKEN_B),"lingpopo").size()==1,"Each player holds exactly their own page-one record"):return
	if not check(not await report(b2) and MSG_DONE in last_message(b2),"B's repeat report is refused"):return
	# ------------------------------------------------------------------ final durable state
	if not check(hub.world.save() and loaded.load_world(path),"Save and reload the finished room"):return
	if not check(int(loaded.state.players[TOKEN_A].get(Goals.BELL_INSPECT_KEY,0))==3 and int(loaded.state.players[TOKEN_B].get(Goals.BELL_INSPECT_KEY,0))==3 and Goals.done(loaded.state.players[TOKEN_A],"lingpopo").has(1) and Goals.done(loaded.state.players[TOKEN_B],"lingpopo").has(1),"Final save keeps both masks at 3 and both pages done"):return
	finish(0)
