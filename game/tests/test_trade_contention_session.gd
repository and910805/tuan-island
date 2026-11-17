extends "res://tests/test_manual_harvest_capacity_session.gd"
## T088: two clients exchange starter wood and bells over local WebSocket.
## Only starting positions are seeded. All offers, edits and confirmations
## use production RPCs with the usual rate and sequence checks enabled.

const ROUNDS:=100

func _initialize()->void:
	create_timer(100.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func run()->void:
	var completed:=await scenario()
	expect(completed,"trade scenario completed")
	await teardown()
	if failures==0:
		expect(remove_folder(),"test save folder removed")
	else:
		print("Trade fixture retained at %s"%folder)
	finished=true
	print("TRADE_CONTENTION_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("trade-contention-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp world directory created"):return false
	save_path=folder.path_join("world.json")
	if not expect(find_layout(),"adjacent standable start positions found"):return false
	var world:=fresh_probe()
	for token in [ALPHA,BETA]:
		var spot:=a_spot if token==ALPHA else b_spot
		world.state.players[token].x=spot.x
		world.state.players[token].y=spot.y
	world.save_path=save_path
	if not expect(world.save() and disk_valid(read_disk()),"initial save validated"):return false
	var port:=start_server()
	if not expect(port>0,"local WebSocket server listening"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"two clients joined"):return false
	var initial:=balances(world)
	for index in ROUNDS:
		if not await trade_round(index):return false
		# Leave room under the production cap of 12 fresh requests per second.
		await pause(0.32)
	expect(balances(server.world)==initial,"100 alternating trades conserve both bags and wallets")
	expect(await wait_until(func():return seen_balance(alpha)==initial.slice(0,2) and seen_balance(beta)==initial.slice(2,4),3.0),"both clients see the final balances")
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	if not expect(await stop_server(),"server saves on shutdown"):return false
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and disk_valid(read_disk()),"main save reloads and validates"):return false
	expect(balances(loaded)==initial,"reloaded item counts and coins match")
	print("TRADE_CONTENTION_SESSION rounds=%d balances=%s"%[ROUNDS,initial])
	return true

func trade_round(index:int)->bool:
	var label:="round %d"%index
	var seller:=alpha if index%2==0 else beta
	var buyer:=beta if seller==alpha else alpha
	var previous_id:=str(trade(seller).get("id",""))
	var mark:=seller.notices.size()
	seller.session.perform("trade_open",Vector2i.ZERO,buyer.session.own_id)
	if not expect(await wait_until(func():
		return seller.notices.size()>mark and not trade(seller).is_empty() and str(trade(seller).get("id",""))!=previous_id
	,3.0) and seller.notices[mark][1],label+" open via public actor ID"):return false
	var offer:String=trade(seller).id
	var marks:=[alpha.notices.size(),beta.notices.size()]
	seller.session.perform("trade_edit",Vector2i.ZERO,JSON.stringify({"offer":offer,"items":[["wood",1]],"coins":0}))
	buyer.session.perform("trade_edit",Vector2i.ZERO,JSON.stringify({"offer":offer,"items":[],"coins":1}))
	if not expect(await both_replied(marks) and alpha.notices[marks[0]][1] and beta.notices[marks[1]][1],label+" both edits accepted"):return false
	if not expect(await wait_until(func():return int(trade(alpha).get("revision",-1))==2 and int(trade(beta).get("revision",-1))==2,3.0),label+" both see revision two"):return false
	var before:=balances(server.world)
	marks=[alpha.notices.size(),beta.notices.size()]
	var confirmation:=JSON.stringify({"offer":offer,"revision":2})
	var order:=[alpha,beta] if index%4<2 else [beta,alpha]
	for client in order:
		var sequence:int=client.session.perform("trade_confirm",Vector2i.ZERO,confirmation)
		client.session.request_action.rpc_id(1,sequence,"trade_confirm",Vector2i.ZERO,confirmation,str(client.session.snapshot.region_id),int(client.me().get("travel_epoch",0)))
	if not expect(await both_replied(marks) and alpha.notices[marks[0]][1] and beta.notices[marks[1]][1],label+" both confirmations accepted"):return false
	var delta:=-1 if seller==alpha else 1
	expect(balances(server.world)==[before[0]+delta,before[1]-delta,before[2]-delta,before[3]+delta],label+" exactly one wood and one bell exchanged")
	if not expect(await wait_until(func():return trade(alpha).is_empty() and trade(beta).is_empty(),3.0),label+" both clients see the offer close"):return false
	expect(alpha.notices.size()==marks[0]+1 and beta.notices.size()==marks[1]+1,label+" exact RPC replays ignored")
	return true

func both_replied(marks:Array)->bool:
	return await wait_until(func():return alpha.notices.size()>marks[0] and beta.notices.size()>marks[1],3.0)

func trade(client:Client)->Dictionary:
	return client.session.snapshot.get("own_trade",{})

func seen_balance(client:Client)->Array:
	return [int(client.bag().get("wood",0)),int(client.me().get("coins",-1))]

func balances(world:World)->Array:
	var a:Dictionary=world.state.players[ALPHA]
	var b:Dictionary=world.state.players[BETA]
	return [int(a.inventory.wood),int(a.coins),int(b.inventory.wood),int(b.coins)]
