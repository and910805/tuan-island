extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	var mode:=args[0]
	if mode=="seed":
		var world:=World.new()
		world.save_path=args[1]
		for role in ["alpha","beta"]:
			var token:String="regions-"+role
			world.add_player(token,role)
			var person:Dictionary=world.state.players[token]
			person.x=46.5 if role=="alpha" else 42.5
			person.y=30.5
			person.inventory.wood=21 if role=="alpha" else 34
		world.state.board=true
		world.state.picnic=true
		world.state.crops["20,20"]={"kind":"", "growth":0.0,"wet":false}
		quit(0 if world.save() else 1)
		return
	var session:=Session.new()
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	island.add_child(session)
	session.profile.token="regions-"+args[2]
	var progress:=[0]
	session.changed.connect(func(state:Dictionary, own:String):
		var region:String=state.get("region_id","home")
		var person:Dictionary=state.players[own]
		for key in state.players:
			if key!=own and (state.players[key].has("inventory") or state.players[key].has("coins")):quit(1);return
		if int(person.inventory.wood)!=(21 if args[2]=="alpha" else 34):quit(1);return
		if args[2]=="beta":
			if region!="home" or not state.crops.has("20,20") or state.crops.has("13,20"):quit(1);return
			if state.players.size()==1 and float(state.time)>3.0:
				print("REGIONS_BETA_PASS")
				quit()
			return
		if mode=="travel":
			if progress[0]==0 and region=="home":
				progress[0]=1
				session.perform("travel",Vector2i(47,30),"lanyang")
			elif progress[0]==1 and region=="lanyang":
				progress[0]=2
				if state.crops.has("20,20") or state.players.size()!=1:quit(1);return
				var epoch:=int(person.travel_epoch)
				session.request_action.rpc_id(1,session.counter+10,"hoe",Vector2i(13,20),"",region,epoch-1)
				session.movement.rpc_id(1,Vector2.RIGHT,region,epoch-1)
				session.perform("hoe",Vector2i(13,20))
			elif progress[0]==2 and region=="lanyang" and state.crops.has("13,20"):
				progress[0]=3
				session.perform("seed",Vector2i(13,20),"radish")
				session.perform("water",Vector2i(13,20))
			elif progress[0]==3 and state.crops.get("13,20",{}).get("wet",false):
				if Vector2(person.x,person.y).distance_to(Vector2(12.5,20.5))>0.01:quit(1);return
				print("REGIONS_TRAVEL_PASS")
				quit()
		elif mode=="reconnect":
			if progress[0]==0 and region=="lanyang":
				if not state.crops.has("13,20"):quit(1);return
				if float(state.crops["13,20"].get("growth",0))<=0.3:return
				progress[0]=1
				session.perform("travel",Vector2i(11,20),"home")
			elif progress[0]==1 and region=="home":
				if not state.crops.has("20,20") or state.crops.has("13,20"):quit(1);return
				print("REGIONS_RECONNECT_PASS")
				quit()
	)
	if session.join("127.0.0.1",int(args[1]),args[2],"regions-test")!=OK:quit(1);return
	await create_timer(9).timeout
	quit(1)
