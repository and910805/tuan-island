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
	world.state.players[ALPHA].inventory.wood+=20
	world.save_path=save_path
	if not expect(world.save() and disk_valid(read_disk()),"fixture save validated"):return false
	var port:=start_server()
	if not expect(port>0,"server ready"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"two WebSocket peers joined"):return false
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
	var ending:=wood_totals()
	expect(ending==[initial[0]-1,initial[1],1],"ending bags and chest conserve original stock")
	expect(await wait_until(func():
		return int(alpha.bag().get(ITEM,0))==ending[0] and int(beta.bag().get(ITEM,0))==ending[1] and visible_chest_wood(alpha)==1 and visible_chest_wood(beta)==1
	,3.0),"both clients see their final bag and the same shared chest")
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	if not expect(await stop_server(),"server saves on shutdown"):return false
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and disk_valid(read_disk()),"reload valid main save"):return false
	expect([int(loaded.state.players[ALPHA].inventory.wood),int(loaded.state.players[BETA].inventory.wood),int(loaded.state.objects[k1].items.wood)]==ending,"reloaded bags and chest match")
	print("CHEST_CONTENTION_SESSION rounds=%d wins=%s"%[ROUNDS,wins])
	return true

func wood_totals()->Array[int]:
	var box:Dictionary=server.world.state.objects.get(k1,{})
	return [int(srv_player(ALPHA).inventory.get(ITEM,0)),int(srv_player(BETA).inventory.get(ITEM,0)),int(box.get("items",{}).get(ITEM,0))]

func visible_chest_wood(client:Client)->int:
	var box:Dictionary=client.session.snapshot.get("objects",{}).get(k1,{})
	return int(box.get("items",{}).get(ITEM,0))
