extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Memory=World.HISTORY_MEMORY

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	var mode:=args[0]
	if mode=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.board=true
		world.state.picnic=true
		var repair:Dictionary=world.state.lanyang_life
		for point in Memory.OBSERVATIONS:
			repair.cleared[Memory.key(point)]=true
		repair.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
		repair.repaired=true
		for role in ["alpha","beta"]:
			var id:String="history-user-"+role
			world.add_player(id,role)
			var person:Dictionary=world.state.players[id]
			person.region="lanyang"
			person.x=32.5
			person.y=27.5
			var record:=Memory.fresh_record()
			record.seen=Memory.OBSERVATIONS.map(Memory.key) if role=="alpha" else ["33,22"]
			repair=world.state.history_memory
			repair.players[id]=record
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="history-user-"+args[2]
	var sent:=[false]
	session.notice.connect(func(message:String,_ok:bool):print(message))
	session.changed.connect(func(snapshot:Dictionary,id:String):
		var memory:Dictionary=snapshot.history_memory
		if not memory.players.is_empty():quit(1);return
		var record:Dictionary=memory.get("own_memory",{})
		var alpha:=args[2]=="alpha"
		if mode=="start":
			if not sent[0]:
				sent[0]=true
				if alpha:
					session.perform("memory_gate",Memory.SERVICE,"a:2")
					session.perform("memory_gate",Memory.SERVICE,"b:2")
					session.perform("memory_flow",Memory.SERVICE)
					session.perform("memory_flow",Memory.SERVICE)
				else:
					session.perform("memory_observe",Vector2i(33,25))
			if not alpha and record.seen.size()==2:
				var player: Dictionary = snapshot.players[id]
				var delta := Vector2(12.5,20.5)-Vector2(player.x,player.y)
				if snapshot.region_id=="lanyang":
					if delta.length()<1.0:
						session.input_direction(Vector2.ZERO)
						session.perform("travel",Vector2i(11,20),"home")
					else:
						session.input_direction(delta.limit_length())
					return
				if float(player.y)<31.4:
					session.input_direction(Vector2.DOWN)
					return
				session.input_direction(Vector2.ZERO)
			if (alpha and record.round==1 and record.seen.size()==3) or (not alpha and snapshot.region_id=="home" and record.round==0 and record.seen.size()==2):
				print("HISTORY_PRIVATE_START_PASS "+args[2])
				quit()
		elif mode=="finish":
			if not sent[0]:
				sent[0]=true
				if alpha:
					if record.round!=1 or record.seen.size()!=3:quit(1);return
					for gates in [[1,3],[2,1]]:
						session.perform("memory_gate",Memory.SERVICE,"a:%d"%gates[0])
						session.perform("memory_gate",Memory.SERVICE,"b:%d"%gates[1])
						session.perform("memory_flow",Memory.SERVICE)
					session.perform("memory_plaque",Memory.SERVICE)
					session.perform("memory_plaque",Memory.SERVICE)
				elif record.round!=0 or record.seen.size()!=2:
					quit(1)
					return
			if memory.plaque and (record.completed==alpha):
				print("HISTORY_SHARED_PLAQUE_PASS "+args[2])
				quit()
	)
	if session.join("127.0.0.1",int(args[1]),args[2],"history-test")!=OK:quit(1);return
	await create_timer(18).timeout
	quit(1)
