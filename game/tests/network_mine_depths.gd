extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Mine=World.MINES
var session
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var w:=World.new()
		w.save_path=args[1]
		w.state.picnic=true
		w.state.mine_depths={"unlocked":3,"ready":{},"pumped":0,"hoist":false}
		for actor in ["depth-user-alpha","depth-user-beta"]:
			w.add_player(actor,actor)
			var p:Dictionary=w.state.players[actor]
			p.region="mine_2"
			p.x=19.5
			p.y=20.5
			p.inventory.reinforced_pick=1
		quit(0 if w.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token="depth-user-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"depths-test")!=OK:
		quit(1)
		return
	var deadline:=Time.get_ticks_msec()+5000
	while session.own_id.is_empty() and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	if session.own_id.is_empty():quit(1);return
	var alpha:=args[2]=="alpha"
	if args[0]=="start":
		if not alpha:await create_timer(.5).timeout
		session.perform("pick",Mine.NODES[0])
		session.request_action.rpc_id(1,session.counter,"pick",Mine.NODES[0],"","mine_2",0)
		await create_timer(.4).timeout
		var bag:Dictionary=session.snapshot.players[session.own_id].inventory
		if int(bag.get("copper_ore",0))!=(4 if alpha else 0):quit(1);return
		if alpha:
			if not await walk(Vector2(35.5,20.5)):quit(1);return
			session.perform("mine_travel",Mine.DOWN,"mine_3")
			await create_timer(.4).timeout
			session.request_action.rpc_id(1,session.counter+1,"mine_travel",Mine.UP,"mine_2","mine_3",0)
			await create_timer(.4).timeout
			if session.snapshot.region_id!="mine_3" or session.snapshot.players.size()!=1:quit(1);return
		else:
			await create_timer(7).timeout
			if session.snapshot.region_id!="mine_2" or session.snapshot.players.size()!=1:quit(1);return
	else:
		if session.snapshot.region_id!="mine_3" or int(session.snapshot.players[session.own_id].inventory.copper_ore)!=4:quit(1);return
		session.perform("mine_travel",Mine.UP,"mine_2")
		await create_timer(.4).timeout
		if session.snapshot.region_id!="mine_2":quit(1);return
	print("MINE_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()

func walk(target:Vector2)->bool:
	var deadline:=Time.get_ticks_msec()+11000
	while Time.get_ticks_msec()<deadline:
		var p:Dictionary=session.snapshot.players[session.own_id]
		var delta:=target-Vector2(p.x,p.y)
		if delta.length()<.5:
			session.input_direction(Vector2.ZERO)
			return true
		var direction:=Vector2.DOWN if p.x<20.5 and p.y<21.5 else delta.limit_length()
		session.input_direction(direction)
		await create_timer(.05).timeout
	return false
