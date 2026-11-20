extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Wire=preload("res://scripts/snapshot_wire.gd")
const PLOT:=Vector2i(13,19)
const PLOT_KEY:="13,19"

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
	var wire_stats:=[0,0,0]
	var require_delta:=args.size()>4 and args[4]=="require-delta"
	session.changed.connect(func(state:Dictionary, own:String):
		if require_delta and session._received_snapshot_frame>0:
			var baseline:=session._received_snapshot_base
			var frame:=session._received_snapshot_frame
			var packet:=Wire.keyframe(state,frame)
			if state!=baseline:
				wire_stats[0]+=1
				packet=Wire.difference(state,baseline,frame)
			wire_stats[1]+=var_to_bytes(Wire.encode(packet)).size()
			wire_stats[2]+=var_to_bytes(Wire.encode(state)).size()
		var region:String=state.get("region_id","home")
		var person:Dictionary=state.players[own]
		for key in state.players:
			if key!=own and (state.players[key].has("inventory") or state.players[key].has("coins")):quit(1);return
		if int(person.inventory.wood)!=(21 if args[2]=="alpha" else 34):quit(1);return
		if args[2]=="beta":
			if region!="home" or not state.crops.has("20,20") or state.crops.has(PLOT_KEY):quit(1);return
			if state.players.size()==1 and float(state.time)>3.0:
				if require_delta:
					if wire_stats[0]<1 or wire_stats[1]>=wire_stats[2]:quit(1);return
					print("REGIONS_DELTA samples=%d payload=%d full_payload=%d"%wire_stats)
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
				session.request_action.rpc_id(1,session.counter+10,"hoe",PLOT,"",region,epoch-1)
				session.movement.rpc_id(1,Vector2.RIGHT,region,epoch-1)
				session.perform("hoe",PLOT)
			elif progress[0]==2 and region=="lanyang" and state.crops.has(PLOT_KEY):
				progress[0]=3
				session.perform("seed",PLOT,"radish")
				session.perform("water",PLOT)
			elif progress[0]==3 and state.crops.get(PLOT_KEY,{}).get("wet",false):
				if Vector2(person.x,person.y).distance_to(Vector2(12.5,20.5))>0.01:quit(1);return
				print("REGIONS_TRAVEL_PASS")
				quit()
		elif mode=="reconnect":
			if progress[0]==0 and region=="lanyang":
				if not state.crops.has(PLOT_KEY):quit(1);return
				if float(state.crops[PLOT_KEY].get("growth",0))<=0.3:return
				progress[0]=1
				session.perform("travel",Vector2i(11,20),"home")
			elif progress[0]==1 and region=="home":
				if not state.crops.has("20,20") or state.crops.has(PLOT_KEY):quit(1);return
				print("REGIONS_RECONNECT_PASS")
				quit()
	)
	var address := "ws://127.0.0.1:" + args[1] if args.size() > 3 and args[3] == "websocket" else "127.0.0.1"
	if session.join(address,int(args[1]),args[2],"regions-test")!=OK:quit(1);return
	await create_timer(9).timeout
	quit(1)
