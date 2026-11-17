extends "res://tests/test_corn_chowder_session.gd"
## Two loopback WebSocket clients exercise the production reliable command path.

func position(token:String)->Vector2:
	var player:Dictionary=server.world.state.players[token]
	return Vector2(player.x,player.y)

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("controller-protection-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated fixture directory"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"save two-islander fixture"):return false
	var port:=start_server()
	if not expect(port>0,"host loopback WebSocket room"):return false
	alpha=await join("protected",ALPHA,port)
	beta=await join("neighbour",BETA,port)
	if not expect(joined(alpha) and joined(beta),"two clients join the shared island"):return false
	var alpha_peer:int=alpha.session.multiplayer.get_unique_id()
	alpha.session.input_direction(Vector2.DOWN)
	if not expect(await wait_until(func():return server.directions.get(alpha_peer)==Vector2.DOWN,2.0),"server receives the live stick direction"):return false
	alpha.session.perform("controller_hold",Vector2i.ZERO)
	if not expect(await wait_until(func():return server.controller_holds.has(alpha_peer),2.0),"server receives the reliable hold command"):return false
	var held:=position(ALPHA)
	var neighbour:=position(BETA)
	var clock:=float(server.world.state.time)
	alpha.session.input_direction(Vector2.RIGHT)
	alpha.session.perform("rescue",Vector2i.ZERO)
	beta.session.input_direction(Vector2.DOWN)
	await settle([alpha,beta])
	expect(position(ALPHA)==held,"protected islander ignores stray movement and actions")
	expect(position(BETA)!=neighbour and float(server.world.state.time)>clock,"other islander and world clock continue")
	alpha.session.perform("controller_resume",Vector2i.ZERO)
	if not expect(await wait_until(func():return not server.controller_holds.has(alpha_peer),2.0),"resume releases only the protected peer"):return false
	alpha.session.input_direction(Vector2.DOWN)
	await settle([alpha,beta])
	expect(position(ALPHA)!=held,"fresh direction moves the islander after resume")
	return true
