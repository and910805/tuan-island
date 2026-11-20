extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SERVICE:=Vector2i(33,29)
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var mode:=args[0]
	if mode=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.board=true
		world.state.picnic=true
		for role in ["alpha","beta"]:
			var id:String="garden-user-"+role
			world.add_player(id,role)
			var person:Dictionary=world.state.players[id]
			person.region="lanyang"
			person.x=32.5
			person.y=27.5 if role=="alpha" else 30.5
			person.inventory.merge({"plank":6} if role=="alpha" else {"stone":8,"resin":2},true)
		world.state.lanyang_life.cleared={"33,22":true}
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="garden-user-"+args[2]
	var progress:=[0]
	session.notice.connect(func(message:String,_ok:bool):print(message))
	session.changed.connect(func(snapshot:Dictionary,id:String):
		var region:String=snapshot.region_id
		var life:Dictionary=snapshot.lanyang_life
		var person:Dictionary=snapshot.players[id]
		if not life.jobs.is_empty():quit(1);return
		var job:Dictionary=life.get("own_job",{})
		if not job.is_empty() and (job.size()!=1 or not job.has("ready")):quit(1);return
		if mode=="start":
			if progress[0]==0:
				progress[0]=1
				session.perform("lanyang_clear",Vector2i(33,25) if args[2]=="alpha" else Vector2i(33,32))
			if progress[0]==1 and life.cleared.size()==3:
				progress[0]=2
				session.perform("lanyang_donate",SERVICE)
			if progress[0]==2 and life.repaired:
				progress[0]=3
				session.perform("nursery_start",SERVICE)
			if progress[0]==3 and not job.is_empty():
				if int(person.inventory.sapling)!=1:quit(1);return
				print("GARDEN_START_PASS "+args[2])
				quit()
		elif mode=="claim" and progress[0]!=99:
			if args[2]=="alpha" and progress[0]>=0 and progress[0]<5:
				if job.is_empty():quit(1);return
				var pos:=Vector2(person.x,person.y)
				var route:=[Vector2(24.5,27.5),Vector2(12.5,20.5),Vector2.ZERO,Vector2(12.5,27.5),Vector2(32.5,27.5)]
				if region=="home":
					if progress[0]!=2 or snapshot.time<job.ready:return
					progress[0]=3
					print("GARDEN_HOME_PRIVATE_PASS")
					session.perform("travel",Vector2i(47,30),"lanyang")
					return
				if progress[0]==2:return
				var delta:Vector2=route[progress[0]]-pos
				if delta.length()<0.7:
					session.input_direction(Vector2.ZERO)
					progress[0]+=1
					if progress[0]==2:session.perform("travel",Vector2i(11,20),"home")
				else:session.input_direction(delta.limit_length())
				return
			if progress[0]==0:
				if job.is_empty():quit(1);return
				if snapshot.time<job.ready:return
				progress[0]=1
				session.perform("nursery_claim",SERVICE)
				session.perform("nursery_claim",SERVICE)
			elif progress[0]==5:
				progress[0]=-1
				session.perform("nursery_claim",SERVICE)
				session.perform("nursery_claim",SERVICE)
			elif progress[0] in [-1,1] and job.is_empty():
				if int(person.inventory.sapling)!=4:quit(1);return
				progress[0]=99
				print("GARDEN_CLAIM_PASS "+args[2])
				quit()
	)
	if session.join("127.0.0.1",int(args[1]),args[2],"garden-test")!=OK:quit(1);return
	await create_timer(45).timeout
	quit(1)
