extends "res://tests/test_manual_harvest_capacity_session.gd"
## T088: two local WebSocket peers contest a shared chest for 100 rounds.
## Offline fixture supplies 20 building wood and two nearby positions.
## Chest building, deposits, withdrawals and replays use the real actions.

const ROUNDS:=100
const ITEM:="wood"

func run()->void:
	var completed:=await scenario()
	expect(completed,"chest scenario completed")
	await teardown()
	if failures==0:
		expect(remove_folder(),"test save folder removed")
	else:
		print("Chest fixture retained at %s"%folder)
	finished=true
	print("CHEST_CONTENTION_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("chest-contention-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp world directory created"):return false
	save_path=folder.path_join("world.json")
	if not expect(find_layout(),"found a clear cell reachable by both players"):return false
	var world:=fresh_probe()
	for token in [ALPHA,BETA]:
		var spot:=a_spot if token==ALPHA else b_spot
		world.state.players[token].x=spot.x
		world.state.players[token].y=spot.y
	world.state.players[ALPHA].inventory.wood+=40
	var private_cell := Vector2i(-1, -1)
	for y in range(plot.y-2, plot.y+3):
		for x in range(plot.x-2, plot.x+3):
			var tile := Vector2i(x, y)
			if tile == plot or centre(tile).distance_to(a_spot) > 2.9 or centre(tile).distance_to(b_spot) > 2.9:
				continue
			if world.act(ALPHA, "history-private-%d-%d" % [x, y], "build", tile, "private_chest").ok:
				private_cell = tile
				break
		if private_cell.x >= 0:
			break
	if not expect(private_cell.x >= 0, "a real private chest is built next to the same players"):
		return false
	world.save_path=save_path
	if not expect(world.save() and disk_valid(read_disk()),"fixture save validated"):return false
	var port:=start_server()
	if not expect(port>0,"server ready"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"two WebSocket peers joined"):return false
	if not expect((await act(alpha,"build",plot,"floor")).ok,"owner lays the shared chest floor"):return false
	if not expect((await act(alpha,"build",plot,"chest")).ok,"owner builds a shared chest"):return false
	var initial:=wood_totals()
	if not expect((await act(alpha,"deposit",plot,ITEM)).ok,"owner deposits one wood"):return false
	var wins:=[0,0]
	for index in ROUNDS:
		var before:=wood_totals()
		var marks:=[alpha.notices.size(),beta.notices.size()]
		var clients:=[alpha,beta] if index%2==0 else [beta,alpha]
		for client in clients:
			var sequence:int=client.session.perform("withdraw_all",plot,ITEM)
			client.session.request_action.rpc_id(1,sequence,"withdraw_all",plot,ITEM,str(client.session.snapshot.region_id),int(client.me().get("travel_epoch",0)))
		if not expect(await wait_until(func():return alpha.notices.size()>marks[0] and beta.notices.size()>marks[1],3.0),"round %d both peers receive a reply"%index):return false
		var a_won:bool=alpha.notices[marks[0]][1]
		var b_won:bool=beta.notices[marks[1]][1]
		var refusal:String=beta.notices[marks[1]][0] if a_won else alpha.notices[marks[0]][0]
		expect(a_won!=b_won and refusal=="箱子裡沒有這項物品","round %d exactly one withdrawal; loser sees empty box"%index)
		wins[0]+=int(a_won)
		wins[1]+=int(b_won)
		expect(before[2]==1 and wood_totals()==[before[0]+int(a_won),before[1]+int(b_won),0],"round %d exact transfer and conservation"%index)
		await pause(0.095)
		expect(alpha.notices.size()==marks[0]+1 and beta.notices.size()==marks[1]+1,"round %d duplicated sequences ignored"%index)
		var winner:=alpha if a_won else beta
		winner.session.perform("deposit",plot,ITEM)
		if not expect(await wait_until(func():return winner.notices.size()==marks[0 if a_won else 1]+2 and wood_totals()==before,3.0),"round %d winner returns the same wood through gameplay"%index):return false
		await pause(0.095)
	expect(wins[0]+wins[1]==ROUNDS,"100 contested rounds")
	expect((await act(beta,"withdraw",plot,ITEM)).ok,"the visitor can also acquire the shared item")
	expect((await act(beta,"deposit",plot,ITEM)).ok,"the visitor can return the shared item")
	expect(alpha.session.snapshot.get("chest_exact_transfer",false) and beta.session.snapshot.get("chest_exact_transfer",false),"both clients learn exact moves are available")
	expect((await act(alpha,"deposit_exact",plot,ITEM+":4")).ok,"exact deposit leaves five wood in chest")
	var before_exact:=wood_totals()
	var exact_marks:=[alpha.notices.size(),beta.notices.size()]
	alpha.session.perform("withdraw_exact",plot,ITEM+":3")
	beta.session.perform("withdraw_exact",plot,ITEM+":3")
	if not expect(await wait_until(func():return alpha.notices.size()>exact_marks[0] and beta.notices.size()>exact_marks[1],3.0),"both exact withdrawals receive a reply"):return false
	var alpha_won:bool=alpha.notices[exact_marks[0]][1]
	var beta_won:bool=beta.notices[exact_marks[1]][1]
	var exact_refusal:String=beta.notices[exact_marks[1]][0] if alpha_won else alpha.notices[exact_marks[0]][0]
	expect(alpha_won!=beta_won and exact_refusal=="箱子裡的數量不足","second request cannot take a partial stack")
	expect(wood_totals()==[before_exact[0]+3*int(alpha_won),before_exact[1]+3*int(beta_won),2],"exact transfer leaves two in the box and conserves wood")
	var ending:=wood_totals()
	expect(ending[0]+ending[1]+ending[2]==initial[0]+initial[1]+initial[2],"ending bags and chest conserve original stock")
	expect(await wait_until(func():
		return int(alpha.bag().get(ITEM,0))==ending[0] and int(beta.bag().get(ITEM,0))==ending[1] and visible_chest_wood(alpha)==ending[2] and visible_chest_wood(beta)==ending[2]
	,3.0),"both clients see their final bag and the same shared chest")
	var history:=await chest_history(beta, plot)
	var history_field:=World.SAVE_SCHEMA.CHEST_HISTORY.FIELD
	if not expect(history.get("ok",false) and history.get("rows",[]).size()==200,"the visitor can request the latest 200 successful transfers"):return false
	var last: Dictionary=history.rows.back()
	expect(last.item==ITEM and int(last.amount)==3 and not last.depositing,"the last record is the winning exact withdrawal only")
	for client:Client in [alpha,beta]:
		expect(not client.session.snapshot.objects[k1].has(history_field),"routine snapshots omit the transfer history")
	await pause(1.05)
	if not expect((await act(alpha,"box_deposit_access",private_cell,"island")).ok,"owner opens deposit-only permissions"):return false
	if not expect((await act(beta,"deposit_exact",private_cell,"stone:2")).ok,"visitor deposits stone without read permissions"):return false
	var refused:=await chest_history(beta, private_cell)
	expect(not refused.get("ok",true) and not refused.has("rows"),"direct request from deposit-only peer returns no history")
	var beta_id: String = beta.session.own_id
	if not expect((await act(alpha,"box_withdraw_access",private_cell,"friend:"+beta_id)).ok,"owner grants the existing withdrawal permission"):return false
	var granted:=await chest_history(beta, private_cell)
	expect(granted.get("ok",false) and granted.get("rows",[]).size()==1 and int(granted.rows[0].amount)==2,"authorized peer reads the deposit")
	if not expect((await act(alpha,"box_withdraw_access",private_cell,"owner")).ok,"owner revokes the existing withdrawal permission"):return false
	var revoked:=await chest_history(beta, private_cell)
	expect(not revoked.get("ok",true) and not revoked.has("rows"),"revoked peer gets no data from a repeated request")
	if not await restricted_shared_chest(ending):return false
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	if not expect(await stop_server(),"server saves on shutdown"):return false
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and disk_valid(read_disk()),"reload valid main save"):return false
	expect(loaded.state.ground[k1].placement_access=="owner","the floor restriction survives room shutdown and reload")
	expect([int(loaded.state.players[ALPHA].inventory.wood),int(loaded.state.players[BETA].inventory.wood),int(loaded.state.objects[k1].items.wood)]==ending,"reloaded bags and chest match")
	var saved_rows: Array = loaded.state.objects[k1][history_field]
	expect(saved_rows.size() == history.rows.size(), "server restart preserves the full recent history")
	var same: bool =saved_rows.size() == history.rows.size()
	for index in mini(saved_rows.size(),history.rows.size()):
		var saved: Dictionary = saved_rows[index]
		var wire: Dictionary = history.rows[index]
		same = same and saved.actor == wire.actor and saved.item == wire.item and int(saved.amount) == int(wire.amount) and saved.depositing == wire.depositing and is_equal_approx(float(saved.time), float(wire.time))
	expect(same,"reloaded transfers preserve the exact order, actors, directions and amounts")
	print("CHEST_CONTENTION_SESSION rounds=%d wins=%s"%[ROUNDS,wins])
	return true

func restricted_shared_chest(ending:Array[int])->bool:
	await pause(1.05)
	if not expect((await act(alpha,"floor_placement_access",plot,"owner")).ok,"owner limits access to the floor"):return false
	if not expect(await wait_until(func():return beta.session.snapshot.objects[k1].get("locked",false),3.0),"the other client receives the floor lock"):return false
	expect(visible_chest_wood(beta)==0 and visible_chest_wood(alpha)==ending[2],"contents are removed from the restricted client's next snapshot")
	var denied:=await act(beta,"withdraw_exact",plot,"wood:1")
	expect(not denied.ok and denied.message==World.PLOT_PERMISSIONS.MSG_SHARED_CHEST_FLOOR and wood_totals()==ending,"the restricted client cannot take wood and no stock moves")
	var restricted_history:=await chest_history(beta,plot)
	expect(not restricted_history.get("ok",true) and not restricted_history.has("rows"),"past transfers cannot be read while the floor is restricted")
	if not expect((await act(alpha,"floor_placement_access",plot,"island")).ok,"owner reopens the floor"):return false
	if not expect(await wait_until(func():return visible_chest_wood(beta)==ending[2],3.0),"reopening resends the same chest stock"):return false
	return expect((await act(alpha,"floor_placement_access",plot,"owner")).ok,"restrict the floor again before saving")

func chest_history(client: Client, cell: Vector2i) -> Dictionary:
	var received: Dictionary = {}
	var request:=World.SAVE_SCHEMA.CHEST_HISTORY.READ_ACTION
	var sequence: int =client.session.counter+1
	var listener:=func(number:int, action:String, result:Dictionary):
		if number==sequence and action==request:received.merge(result)
	client.session.action_completed.connect(listener)
	client.session.perform(request,cell)
	await wait_until(func():return not received.is_empty(),3.0)
	client.session.action_completed.disconnect(listener)
	return received

func wood_totals()->Array[int]:
	var box:Dictionary=server.world.state.objects.get(k1,{})
	return [int(srv_player(ALPHA).inventory.get(ITEM,0)),int(srv_player(BETA).inventory.get(ITEM,0)),int(box.get("items",{}).get(ITEM,0))]

func visible_chest_wood(client:Client)->int:
	var box:Dictionary=client.session.snapshot.get("objects",{}).get(k1,{})
	return int(box.get("items",{}).get(ITEM,0))
