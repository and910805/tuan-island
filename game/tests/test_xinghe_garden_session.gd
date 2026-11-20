extends "res://tests/network_egg_basket.gd"
## T066 N07-4 over a real loopback WebSocket: 星禾's 〈大家的花園日〉 shared garden.
## Three independent clients: A and C are friends of 星禾 (stage 4), B is not. Friendship is only needed to
## open the garden (first pot) and to personally report; anyone may add a flower once opened. One pot per author,
## the last slot is safe under concurrent and duplicate requests, B cannot report or claim the sign, A and C
## each receive exactly one sign, and everything survives reconnect and a real host restart.
const Goals=World.RESIDENT_GOALS
const TOKEN_A:="xinghe-garden-token-alpha"
const TOKEN_B:="xinghe-garden-token-bravo"
const TOKEN_C:="xinghe-garden-token-charlie"
const TOKENS:=[TOKEN_A,TOKEN_B,TOKEN_C]
const REPORT:="xinghe:4::"
const CLAIM:="xinghe:4"
const MSG_NEED_FRIEND:="先請星禾的好友來開啟共同花園。"
const MSG_DUPLICATE:="這位作者已經選過一盆了。"
const MSG_FULL:="三盆花都選好了，可以向星禾回報。"
const MSG_BAD_FLOWER:="請從三種花裡挑一種。"
const MSG_DONE:="已經一起完成了"
const MSG_CLAIMED:="已經領過了"
var hub:Session

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XINGHE_GARDEN_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func send_all()->void:
	for peer in hub.peers:hub._send_snapshot(peer)

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func person(token:String)->Dictionary:
	return hub.world.state.players[token]

func kit_item()->String:
	return Goals.keepsake_item("keepsake_xinghe_sign")

func kits(token:String)->int:
	return int(person(token).inventory.get(kit_item(),0))

func own_kits(session:Session)->int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}).get(kit_item(),0))

func host_pots()->Array:
	return hub.world.state.get(Goals.GARDEN_KEY,[])

func view_pots(session:Session)->Array:
	return session.snapshot.get(Goals.GARDEN_KEY,[])

func xinghe_cell()->Vector2i:
	return World.bond_place(hub.world.state,"xinghe")[1]

func xinghe_region()->String:
	return str(World.bond_place(hub.world.state,"xinghe")[0])

func to_xinghe(session:Session,token:String)->bool:
	var cell:=xinghe_cell()
	var p:Dictionary=person(token)
	p.region=xinghe_region()
	p.x=cell.x+0.5
	p.y=cell.y+0.5
	send_all()
	return await wait_for(func():return str(session.snapshot.get("region_id","home"))==xinghe_region())

func last_message(session:Session)->String:
	return str(notices[session].back().message)

func goal_entry(session:Session)->Dictionary:
	return session.snapshot.get("resident_goals",{}).get("xinghe",{}).get("4",{})

func quiet(frames:int=30)->void:
	for _i in frames:await process_frame

func pick(session:Session,flower:String)->bool:
	return await action(session,Goals.GARDEN_ACTION,xinghe_cell(),flower)

func report(session:Session)->bool:
	return await action(session,Goals.ACTION,xinghe_cell(),REPORT)

func claim(session:Session)->bool:
	return await action(session,Goals.CLAIM_ACTION,xinghe_cell(),CLAIM)

func total_kits()->int:
	var total:=0
	for token in TOKENS:total+=kits(token)
	return total

func authors_of(pots:Array)->Array:
	var out:Array=[]
	for pot in pots:out.append(str(pot.author))
	return out

func leaks_token(value:Variant)->bool:
	var text:=var_to_str(value)
	for token in TOKENS:
		if token in text:return true
	return false

## Public view rules shared by every client, before and after reconnect/restart.
func public_ok(session:Session,ids:Array,names:Array)->bool:
	var pots:Array=view_pots(session)
	if pots.size()!=3 or leaks_token(pots):return false
	for index in 3:
		var pot:Dictionary=pots[index]
		if pot.get("npc",true)!=false or str(pot.get("author",""))!=str(ids[index]) or str(pot.get("name",""))!=str(names[index]):return false
		if str(pot.get("name","")).is_empty() or str(pot.name) in TOKENS:return false
	return true

func run()->void:
	path=OS.get_environment("TEMP").path_join("xinghe-garden-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	# ------------------------------------------------------------------ fixture: normal bonds in an isolated save
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in TOKENS:
		fixture.add_player(token,"花園居民")
		if token!=TOKEN_B:
			fixture.state.players[token].bonds={"xinghe":{"points":24,"talk_day":-1,"gift_day":-1}}
	if not check(fixture.save(),"Save the isolated garden fixture"):return
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port"):return
	hub=make_session("GardenHost","garden-host")
	if not check(hub.host(port,"花園",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a real WS dedicated host"):return
	hub.set_physics_process(false)
	var a:=make_session("GardenA",TOKEN_A)
	var b:=make_session("GardenB",TOKEN_B)
	var c:=make_session("GardenC",TOKEN_C)
	var address:="ws://127.0.0.1:%d"%port
	if not check(a.join(address,port,"阿花",ROOM)==OK and b.join(address,port,"小布",ROOM)==OK and c.join(address,port,"小星",ROOM)==OK,"Join three independent clients"):return
	if not check(await wait_for(func():return not a.own_id.is_empty() and not b.own_id.is_empty() and not c.own_id.is_empty()),"All three enter"):return
	if not check(a.own_id!=b.own_id and b.own_id!=c.own_id and a.own_id!=c.own_id and not (a.own_id in TOKENS),"Clients have distinct public ids that are not profile tokens"):return
	var ids:=[a.own_id,b.own_id,c.own_id]
	var names:=[str(person(TOKEN_A).name),str(person(TOKEN_B).name),str(person(TOKEN_C).name)]
	if not check(hub.world.state.get(Goals.GARDEN_KEY,[]).is_empty(),"The garden starts empty"):return
	if not check(await to_xinghe(a,TOKEN_A) and await to_xinghe(b,TOKEN_B) and await to_xinghe(c,TOKEN_C),"All three stand next to 星禾 in her region"):return
	# ------------------------------------------------------------------ opening needs a friend
	if not check(not await pick(b,"bluebell") and last_message(b)==MSG_NEED_FRIEND and host_pots().is_empty(),"Non-friend cannot open the garden: %s"%last_message(b)):return
	if not check(not await report(a) and "還不能一起做這件事" in last_message(a) and Goals.done(person(TOKEN_A),"xinghe").is_empty() and kits(TOKEN_A)==0,"Even a friend cannot report before three pots: %s"%last_message(a)):return
	if not check(await pick(a,"bluebell"),"Friend A opens the garden through the normal place action: %s"%last_message(a)):return
	if not check(host_pots()==[{"npc":false,"author":TOKEN_A,"flower":"bluebell"}],"Host stores exactly A's bluebell pot"):return
	# ------------------------------------------------------------------ one contribution per author
	if not check(not await pick(a,"orange_blossom") and last_message(a)==MSG_DUPLICATE and host_pots().size()==1,"A cannot add a second pot: %s"%last_message(a)):return
	if not check(not await pick(a,"bluebell") and last_message(a)==MSG_DUPLICATE and host_pots().size()==1,"A cannot repeat the same flower either"):return
	# ------------------------------------------------------------------ a non-friend may contribute once it is open
	if not check(not await pick(b,"xinghe") and last_message(b)==MSG_NEED_FRIEND and host_pots().size()==1,"Non-friend cannot ask 星禾 to pick: %s"%last_message(b)):return
	if not check(not await pick(b,"rose") and last_message(b)==MSG_BAD_FLOWER and host_pots().size()==1,"Unknown flower is refused"):return
	if not check(await pick(b,"orange_blossom"),"Non-friend B adds a flower: %s"%last_message(b)):return
	if not check(host_pots().size()==2 and host_pots()[1]=={"npc":false,"author":TOKEN_B,"flower":"orange_blossom"},"Host stores B's pot second"):return
	if not check(not await pick(b,"chime_herb") and last_message(b)==MSG_DUPLICATE and host_pots().size()==2,"B cannot add a second pot"):return
	if not check(not await claim(b) and kits(TOKEN_B)==0,"B cannot claim a sign early: %s"%last_message(b)):return
	if not check(not await pick(c,"rose") and last_message(c)==MSG_BAD_FLOWER and host_pots().size()==2,"C's unknown flower is refused"):return
	# ------------------------------------------------------------------ concurrent and duplicate requests for the last slot
	var seen:={}
	for session in [a,b,c]:seen[session]=notices[session].size()
	c.perform(Goals.GARDEN_ACTION,xinghe_cell(),"chime_herb")
	c.perform(Goals.GARDEN_ACTION,xinghe_cell(),"bluebell")
	a.perform(Goals.GARDEN_ACTION,xinghe_cell(),"orange_blossom")
	b.perform(Goals.GARDEN_ACTION,xinghe_cell(),"bluebell")
	if not check(await wait_for(func():return notices[c].size()>=int(seen[c])+2 and notices[a].size()>=int(seen[a])+1 and notices[b].size()>=int(seen[b])+1),"All racing requests were answered"):return
	var c_new:Array=notices[c].slice(int(seen[c]))
	var oks:=0
	for note in c_new:oks+=int(note.ok)
	if not check(oks==1 and c_new[0].ok and not c_new[1].ok and c_new[1].message==MSG_FULL,"C's two requests: first wins, duplicate is refused as full"):return
	if not check(not notices[a].back().ok and not notices[b].back().ok,"A and B racing duplicates are refused"):return
	if not check(host_pots().size()==3 and authors_of(host_pots())==TOKENS,"Host holds exactly three pots, one per author, in order"):return
	if not check(host_pots()[2]=={"npc":false,"author":TOKEN_C,"flower":"chime_herb"},"C's first request is the one stored"):return
	if not check(not await pick(c,"orange_blossom") and last_message(c)==MSG_FULL and host_pots().size()==3,"A full garden refuses every further pick"):return
	# ------------------------------------------------------------------ public view: names and public ids, no tokens
	send_all()
	await quiet()
	for session in [a,b,c]:
		if not check(await wait_for(func():return view_pots(session).size()==3),"Client sees all three pots"):return
		if not check(public_ok(session,ids,names),"Public pots carry labels and public authors but no profile tokens"):return
	if not check(["bluebell","orange_blossom","chime_herb"]==[view_pots(a)[0].flower,view_pots(a)[1].flower,view_pots(a)[2].flower],"Public flowers match the host"):return
	# ------------------------------------------------------------------ personal reward needs one's own friendship
	if not check(not await report(b) and "關係" in last_message(b) and Goals.done(person(TOKEN_B),"xinghe").is_empty() and kits(TOKEN_B)==0,"B cannot report without friendship: %s"%last_message(b)):return
	if not check(not await claim(b) and kits(TOKEN_B)==0 and not Goals.keepsake_claimed(person(TOKEN_B),"keepsake_xinghe_sign"),"B cannot claim a sign: %s"%last_message(b)):return
	var a_before:=int(person(TOKEN_A).inventory.get("bluebell",0))
	if not check(await report(a),"A reports the finished garden: %s"%last_message(a)):return
	var sent:=a.counter
	if not check(Goals.done(person(TOKEN_A),"xinghe").has(4) and kits(TOKEN_A)==1 and Goals.keepsake_claimed(person(TOKEN_A),"keepsake_xinghe_sign"),"A has the record and exactly one sign"):return
	if not check(int(person(TOKEN_A).inventory.get("bluebell",0))==a_before,"Reporting spends no materials"):return
	if not check(await wait_for(func():return own_kits(a)==1 and goal_entry(a).get("state","")=="done"),"A's own view shows the sign and a done event"):return
	var settled:int=notices[a].size()
	var region:=str(a.snapshot.get("region_id","home"))
	var epoch:=int(a.snapshot.get("players",{}).get(a.own_id,{}).get("travel_epoch",0))
	a.request_action.rpc_id(1,sent,Goals.ACTION,xinghe_cell(),REPORT,region,epoch)
	await quiet(40)
	if not check(notices[a].size()==settled and kits(TOKEN_A)==1,"A retransmit of the same sequence gives no second sign"):return
	if not check(not await report(a) and MSG_DONE in last_message(a) and kits(TOKEN_A)==1,"A fresh repeat report is refused"):return
	if not check(not await claim(a) and MSG_CLAIMED in last_message(a) and kits(TOKEN_A)==1,"A cannot claim a second sign"):return
	# C is eligible too and gets exactly one sign of their own.
	if not check(await report(c),"C reports as their own friend: %s"%last_message(c)):return
	if not check(kits(TOKEN_C)==1 and Goals.done(person(TOKEN_C),"xinghe").has(4) and kits(TOKEN_B)==0 and total_kits()==2,"C holds one sign; B none; two signs exist in total"):return
	await create_timer(1.05).timeout
	if not check(not await report(c) and not await claim(c) and kits(TOKEN_C)==1,"C cannot get a second sign"):return
	send_all()
	await quiet()
	if not check(await wait_for(func():return own_kits(c)==1 and goal_entry(c).get("state","")=="done"),"C's own view shows the sign"):return
	if not check(own_kits(b)==0 and goal_entry(b).get("state","")!="done","B's own view has no sign and no completion"):return
	var a_view:Dictionary=b.snapshot.get("players",{}).get(a.own_id,{})
	if not check(not a_view.has(Goals.RECORD_KEY) and not a_view.has(Goals.KEEPSAKE_KEY),"B receives no goal or keepsake record on A's public entry"):return
	if not check(not leaks_token(b.snapshot.get("players",{})),"B's players view carries no profile tokens"):return
	# ------------------------------------------------------------------ reconnect
	a.shutdown()
	if not check(await wait_for(func():return hub.peers.size()==2),"Host sees A leave"):return
	var returned:=make_session("GardenReturned",TOKEN_A)
	if not check(returned.join(address,port,"回來的阿花",ROOM)==OK,"Reconnect A's profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and view_pots(returned).size()==3 and own_kits(returned)==1 and goal_entry(returned).get("state","")=="done"),"Reconnect restores pots, sign and done event"):return
	if not check(returned.own_id==ids[0] and authors_of(view_pots(returned))==ids,"Reconnected A keeps the same public author id"):return
	if not check(await to_xinghe(returned,TOKEN_A),"Returned A stands next to 星禾"):return
	if not check(not await report(returned) and not await claim(returned) and kits(TOKEN_A)==1,"After reconnect A still cannot get another sign"):return
	if not check(not await pick(returned,"bluebell") and host_pots().size()==3,"After reconnect the garden is still full"):return
	# ------------------------------------------------------------------ durable reload
	if not check(hub.world.save(),"Host saves the room"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path),"The save loads in a fresh World"):return
	var saved_pots:Array=loaded.state.get(Goals.GARDEN_KEY,[])
	if not check(saved_pots.size()==3 and authors_of(saved_pots)==TOKENS and saved_pots[0].flower=="bluebell" and saved_pots[1].flower=="orange_blossom" and saved_pots[2].flower=="chime_herb","Save keeps three pots, authors and flowers"):return
	var saved_kits:=0
	for token in TOKENS:
		saved_kits+=int(loaded.state.players[token].inventory.get(kit_item(),0))
	if not check(saved_kits==2 and int(loaded.state.players[TOKEN_B].inventory.get(kit_item(),0))==0,"Save holds exactly two signs, none for B"):return
	if not check(Goals.done(loaded.state.players[TOKEN_A],"xinghe").has(4) and Goals.done(loaded.state.players[TOKEN_C],"xinghe").has(4) and Goals.done(loaded.state.players[TOKEN_B],"xinghe").is_empty(),"Save keeps A and C done, B not"):return
	# ------------------------------------------------------------------ real restart
	for session in [returned,b,c]:
		if not session.shutting_down:session.shutdown()
	hub.shutdown()
	await quiet(20)
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	hub=make_session("GardenHostTwo","garden-host-two")
	if not check(hub.host(port2,"花園",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Restart the dedicated host from the save"):return
	hub.set_physics_process(false)
	var address2:="ws://127.0.0.1:%d"%port2
	var a2:=make_session("GardenATwo",TOKEN_A)
	var b2:=make_session("GardenBTwo",TOKEN_B)
	var c2:=make_session("GardenCTwo",TOKEN_C)
	if not check(a2.join(address2,port2,"重開阿花",ROOM)==OK and b2.join(address2,port2,"重開小布",ROOM)==OK and c2.join(address2,port2,"重開小星",ROOM)==OK,"All three join the restarted host"):return
	if not check(await wait_for(func():return not a2.own_id.is_empty() and not b2.own_id.is_empty() and not c2.own_id.is_empty() and view_pots(a2).size()==3 and view_pots(b2).size()==3 and view_pots(c2).size()==3),"Restarted clients see the saved garden"):return
	if not check(authors_of(host_pots())==TOKENS and a2.own_id==ids[0] and b2.own_id==ids[1] and c2.own_id==ids[2],"Restarted host keeps authors and public ids"):return
	names=[str(person(TOKEN_A).name),str(person(TOKEN_B).name),str(person(TOKEN_C).name)]
	send_all()
	for session in [a2,b2,c2]:
		if not check(await wait_for(func():return public_ok(session,ids,names)),"Restarted public pots have labels and public authors, no tokens"):return
	if not check(await wait_for(func():return own_kits(a2)==1 and own_kits(c2)==1 and goal_entry(a2).get("state","")=="done" and goal_entry(c2).get("state","")=="done"),"Restarted A and C keep their sign and done event"):return
	if not check(own_kits(b2)==0 and goal_entry(b2).get("state","")!="done" and total_kits()==2,"Restarted B has none; two signs in total"):return
	if not check(await to_xinghe(a2,TOKEN_A) and await to_xinghe(b2,TOKEN_B) and await to_xinghe(c2,TOKEN_C),"All stand next to 星禾 after the restart"):return
	if not check(not await report(a2) and not await claim(a2) and not await report(c2) and not await claim(c2) and kits(TOKEN_A)==1 and kits(TOKEN_C)==1,"After restart A and C cannot get another sign"):return
	if not check(not await report(b2) and not await claim(b2) and not await pick(b2,"bluebell") and kits(TOKEN_B)==0 and host_pots().size()==3 and total_kits()==2,"After restart B still has no sign and the garden is still full"):return
	finish(0)
