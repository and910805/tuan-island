extends "res://tests/test_bobo_cart_unlock_session.gd"
## Real loopback WebSocket clients. The Windows fixture separately verifies the local PNG.

const OAR:="keepsake_achao_oar_kit"
var dock:=Vector2i.ZERO

func seed_world(path:String)->bool:
	var island:=World.new()
	island.state.dock_stage=2
	island.state[Goals.DOCK_LIGHT]=true
	dock=World.RESIDENT_BOND.dock_cell(island.state)
	for token:String in [REPAIRER,GUEST]:
		island.add_player(token,token,Vector2(dock)+Vector2(0.5,0.5))
		island.state.players[token].bonds={"achao":{"points":24,"talk_day":-1,"gift_day":-1}}
	island.active_tokens.clear()
	island.save_path=path
	return island.save()

func finished_photo(client:Client)->bool:
	return client.session.snapshot.get("resident_goals",{}).get("achao",{}).get("4",{}).get("state")=="done"

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("achao-photo-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"Isolated save folder"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"Seed the dock and both friendships"):return false
	var port:=start_server()
	if not expect(port>0,"Open the loopback room"):return false
	repairer=await join("Captain",REPAIRER,port)
	guest=await join("Passenger",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Connect both live clients"):return false
	var boarded:=await act(repairer,Goals.VOYAGE_ACTION,dock,"depart")
	expect(boarded.replied and boarded.ok,"Captain departs")
	boarded=await act(guest,Goals.VOYAGE_ACTION,dock,"join")
	expect(boarded.replied and boarded.ok,"Passenger joins the visible boat")
	expect(guest.me().get("voyage_captain","")==repairer.session.own_id,"The passenger sees the public captain ID")
	var shot:=await act(repairer,Goals.VOYAGE_ACTION,dock,"photo")
	expect(shot.replied and shot.ok,"The captain's own photo action counts")
	expect(not server.world.state.players[GUEST].get(Goals.VOYAGE_PHOTO,false),"The passenger does not inherit quest credit")
	shot=await act(guest,Goals.VOYAGE_ACTION,dock,"photo")
	expect(shot.replied and shot.ok,"An eligible passenger can count a separate photo action")
	for client:Client in [repairer,guest]:
		for detail:Dictionary in client.session.snapshot.players.values():
			expect(not detail.has(Goals.VOYAGE_PHOTO) and not detail.has(Goals.VOYAGE_CAPTAIN),"Public records omit private photo and profile data")
	var returned:=await act(repairer,Goals.VOYAGE_ACTION,dock,"return")
	expect(returned.replied and returned.ok,"Captain returns to the dock")
	expect(await wait_until(func():return not guest.me().get("at_sea",false),4.0) and not server.world.state.players[GUEST].has(Goals.VOYAGE_START),"Returning also lands the passenger")
	var report:=await act(repairer,Goals.ACTION,dock,"achao:4::")
	expect(report.replied and report.ok and finished_photo(repairer) and int(repairer.bag().get(OAR,0))==1,"Captain reports and receives one oar")
	expect(not finished_photo(guest) and int(guest.bag().get(OAR,0))==0,"Passenger's goal still awaits their own report")
	report=await act(guest,Goals.ACTION,dock,"achao:4::")
	expect(report.replied and report.ok and finished_photo(guest) and int(guest.bag().get(OAR,0))==1,"Passenger reports their own photo")
	leave(repairer)
	leave(guest)
	await pause(0.2)
	if not expect(await stop_server(),"Save and stop the room"):return false
	port=start_server()
	if not expect(port>0,"Reopen the room from disk"):return false
	repairer=await join("Captain",REPAIRER,port)
	guest=await join("Passenger",GUEST,port)
	expect(joined(repairer) and joined(guest) and finished_photo(repairer) and finished_photo(guest),"Restart restores both reports")
	return true

func run()->void:
	var complete:=await scenario()
	expect(complete,"Reach the end of the loopback scenario")
	await teardown()
	if complete and failures==0:expect(remove_folder(),"Remove the isolated fixture")
	finished=true
	print("ACHAO_PHOTO_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
