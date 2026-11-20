extends "res://tests/test_lost_chicks_session.gd"

const Stroll=World.LANTERN_STROLL

func seeded_world()->bool:
	var saved:=World.new()
	saved.save_path=path
	saved.state.picnic=true
	saved.state.time=1120.0
	for actor:String in [ALPHA,BETA,GAMMA]:
		saved.add_player(actor,"夜間旅人")
		put_record(saved,actor,Stroll.SIGN)
	return saved.save()

func shared(session:Session)->Dictionary:
	return session.snapshot.get(Stroll.KEY,{})

func mine(session:Session)->Dictionary:
	return session.snapshot.get(Stroll.VIEW_KEY,{})

func send(session:Session,cell:Vector2i,extra:String)->bool:
	await create_timer(0.10).timeout
	var size:int=notices[session].size()
	session.perform(Stroll.ACTION,cell,extra)
	if not await wait_for(func():return notices[session].size()>size):return false
	return notices[session].back().ok

func stamps_at(session:Session,token:String,id:String,rid:int,wish:String)->bool:
	var cell:Vector2i=Stroll.SITES[id].cell
	if not await place(session,token,cell):return false
	if not await send(session,cell,"stamp:%d:%s:%s"%[rid,id,wish]):return false
	return await wait_for(func():return mine(session).get("stamps",{}).get(id)==wish)

func run()->void:
	path="user://lantern-stroll-session-%d.json"%OS.get_process_id()
	create_timer(75.0).timeout.connect(func():check(false,"WebSocket suite watchdog"))
	if not check(seeded_world() and start_room(),"Start isolated WebSocket room"):return
	alpha=await connect_client("Alpha",ALPHA)
	beta=await connect_client("Beta",BETA)
	if not check(alpha!=null and beta!=null and not mine(alpha).is_empty() and not mine(beta).is_empty(),"Two clients receive private walk summary"):return
	var prior:=economy(alpha)
	if not check(await send(alpha,Stroll.SIGN,"start"),"Alpha starts at the sign"):return
	if not check(await wait_for(func():return shared(beta).get("phase")=="run"),"Shared round reaches Beta"):return
	var rid:int=shared(beta).round
	var route:Array=shared(beta).route
	if not check(Stroll._valid_route(route) and JSON.stringify(route)==JSON.stringify(shared(alpha).route),"Both clients receive the same connected route"):return
	if not check(await send(alpha,Stroll.SIGN,"companion:%d"%rid),"Select solo guide"):return
	var tile:Vector2i=Stroll.SITES.grove.cell
	if not check(await place(beta,BETA,tile) and await send(beta,tile,"join:%d"%rid),"Beta joins at a stop"):return
	if not check(await stamps_at(alpha,ALPHA,"grove",rid,"safe"),"Alpha leaves a blessing"):return
	if not check(await wait_for(func():return shared(beta).get("blessings",{}).get("grove")=="safe"),"Beta sees Alpha's blessing"):return
	if not check(mine(beta).stamps.is_empty(),"Beta gets no stamp for Alpha's visit"):return
	if not check(await stamps_at(beta,BETA,"grove",rid,"growth"),"Beta can stamp the same stop personally"):return
	if not check(mine(alpha).stamps.grove=="safe","Private selected blessing stays the same"):return
	if not check(not await send(beta,tile,"stamp:%d:grove:friends"%rid),"An individual cannot stamp the same spot twice"):return
	beta.shutdown()
	if not check(await wait_for(func():return shared(alpha).get("count")==1),"Disconnected client returns the lantern"):return
	beta=await connect_client("BetaAgain",BETA)
	if not check(beta!=null and await wait_for(func():return mine(beta).get("stamps",{}).get("grove")=="growth"),"Reconnected client keeps personal stamp"):return
	if not check(not mine(beta).joined and await place(beta,BETA,tile) and await send(beta,tile,"join:%d"%rid),"Explicit rejoin reissues lantern"):return
	if not check(await stamps_at(alpha,ALPHA,"river",rid,"growth") and await stamps_at(alpha,ALPHA,"meadow",rid,"friends"),"Stops can be visited in either order"):return
	if not check(mine(alpha).tickets==1 and mine(beta).tickets==0 and economy(alpha)==prior,"Only completion grants a private ticket"):return
	if not check(await send(alpha,Vector2i(51,36),"leave:%d"%rid) and await wait_for(func():return mine(alpha).get("joined")==false),"Leave can be requested away from the board"):return
	if not check(mine(alpha).stamps.size()==3 and mine(alpha).tickets==1,"Leaving preserves stamps and ticket"):return

	if not check(host.world.save(),"Save the live event"):return
	var resumed:=World.new()
	if not check(resumed.load_world(path),"Read the running event through the save schema"):return
	if not check(not Stroll.view(resumed.state,ALPHA).joined and Stroll.view(resumed.state,ALPHA).tickets==1 and Stroll.view(resumed.state,BETA).stamps.size()==1,"Saved credits and both paths survive restart"):return

	for client:Session in [alpha,beta]:
		var dump:=JSON.stringify(client.snapshot)
		if not check(not dump.contains(ALPHA) and not dump.contains(BETA),"Snapshot hides both raw tokens"):return
		for visible:Dictionary in client.snapshot.players.values():
			if not check(not visible.has(Stroll.KEY),"No player record exposes ticket data"):return
	host.world.state.time=float(host.world.state.time)+Stroll.DURATION+0.1
	if not check(await wait_for(func():return shared(alpha).get("phase")=="results" and shared(beta).get("phase")=="results"),"Timeout reaches both clients"):return
	if not check(mine(alpha).tickets==1 and mine(beta).tickets==0 and not mine(beta).joined,"Only earned credits persist"):return
	if not check(await place(alpha,ALPHA,Stroll.SIGN) and await send(alpha,Stroll.SIGN,"redeem"),"Redeem one ticket after results"):return
	if not check(await wait_for(func():return int(bag(alpha).get(Stroll.PRIZE,0))==1 and mine(alpha).tickets==0),"Redemption grants exactly one real lantern kit"):return
	if not check(not await send(alpha,Stroll.SIGN,"redeem"),"Replaying redemption cannot create another item"):return
	if not check(await send(alpha,Stroll.SIGN,"start") and await wait_for(func():return int(shared(alpha).get("round",0))==rid+1),"Second round resets route marks"):return
	if not check(mine(alpha).stamps.is_empty() and not await send(alpha,tile,"stamp:%d:grove:safe"%rid),"Old round actions stay stale"):return
	print("LANTERN_STROLL_SESSION checks=%d failures=0"%checks)
	finish(0)
