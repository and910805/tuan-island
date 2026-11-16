extends "res://tests/test_corn_chowder_session.gd"
## Two shore foragers and one miner use ordinary session actions on an isolated save.

const DISH:="star_rice_ball"

func seed_world(path:String)->bool:
	var w:=World.new()
	for token in [ALPHA,BETA,GAMMA]:
		w.add_player(token,"rice ball tester")
		var person:Dictionary=w.state.players[token]
		var spot:=Vector2(World.SEAWEED_CELL)+Vector2(0.5,0.5)
		if token==GAMMA:
			spot=World.REGIONS.spawn("mine_1")
			preset(person,"region","mine_1")
			preset(person,"mine_energy",85)
			preset(person.inventory,DISH,2)
		preset(person,"x",spot.x)
		preset(person,"y",spot.y)
	w.save_path=path
	return w.save()

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("rice-ball-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated test directory"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"seed coast and mine positions and miner inventory"):return false
	var port:=start_server()
	if not expect(port>0,"host WebSocket server"):return false
	alpha=await join("forager_a",ALPHA,port)
	beta=await join("forager_b",BETA,port)
	gamma=await join("miner",GAMMA,port)
	if not expect(joined(alpha) and joined(beta) and joined(gamma),"three clients connected"):return false
	var marks:=[alpha.notices.size(),beta.notices.size()]
	alpha.session.perform("axe",World.SEAWEED_CELL)
	beta.session.perform("axe",World.SEAWEED_CELL)
	if not expect(await wait_until(func():return alpha.notices.size()>marks[0] and beta.notices.size()>marks[1],4.0),"both foragers receive a reply"):return false
	await settle([alpha,beta])
	expect(int(alpha.notices[marks[0]][1])+int(beta.notices[marks[1]][1])==1,"one of the two competing gathers succeeds")
	expect(int(alpha.bag().get("seaweed",0))+int(beta.bag().get("seaweed",0))==1,"only one seaweed enters inventory")
	var due:=float(alpha.session.snapshot.get("seaweed_ready",0.0))
	expect(due>float(alpha.session.snapshot.time) and due==float(beta.session.snapshot.get("seaweed_ready",0.0)),"both foragers see the same regrowth timer")
	expect(gamma.session.snapshot.get("region_id")=="mine_1","miner enters mine")
	var ate:=await act(gamma,"eat_rice_ball",Vector2i.ZERO)
	expect(ate.ok and gamma.me().get("mine_energy")==100 and gamma.bag().get(DISH)==1,"miner restores 15 energy and consumes only one food")
	expect(not (await act(gamma,"eat_rice_ball",Vector2i.ZERO)).ok and gamma.bag().get(DISH)==1,"full energy rejects another meal")
	expect(alpha.me().get("mine_energy")==100 and beta.me().get("mine_energy")==100,"foragers retain their own energy")
	leave(alpha)
	leave(beta)
	leave(gamma)
	if not expect(await stop_server(),"normal server shutdown"):return false
	port=start_server()
	if not expect(port>0,"restart from same save"):return false
	alpha=await join("forager_a",ALPHA,port)
	gamma=await join("miner",GAMMA,port)
	if not expect(joined(alpha) and joined(gamma),"miner and forager reconnect"):return false
	expect(gamma.me().get("mine_energy")==100 and gamma.bag().get(DISH)==1,"food consumption and energy survive restart")
	expect(is_equal_approx(float(alpha.session.snapshot.get("seaweed_ready",0.0)),due),"shared seaweed timestamp survives JSON round trip")
	expect(not (await act(alpha,"axe",World.SEAWEED_CELL)).ok,"shared seaweed remains unavailable after restart")
	return true
