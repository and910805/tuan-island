extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Bobo=World.BOBO_WORKSHOP
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		for role in ["alpha","beta"]:
			var actor:String="bobo-net-"+role
			world.add_player(actor,role)
			var p:Dictionary=world.state.players[actor]
			p.region="jinguashi" if role=="alpha" else "home"
			p.x=23.5
			p.y=21.5
			p.inventory.gold_ore=3
			p.inventory.plank=2
			p.inventory.copper_joint=1
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="bobo-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"bobo-test")!=OK:quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while session.own_id.is_empty() and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	if session.own_id.is_empty():quit(1);return
	var alpha:=args[2]=="alpha"
	if args[0]=="start":
		session.perform("quest",Bobo.NPC_CELL,"bobo:0")
		session.perform("bobo_sort_start",Bobo.CELL)
		if alpha:
			session.perform("bobo_sort_answer",Bobo.CELL,"0:large")
		else:
			session.perform("bobo_sort_claim",Bobo.CELL)
		await create_timer(.7).timeout
		var d:Dictionary=session.snapshot.bobo_workshop
		var p:Dictionary=session.snapshot.players[session.own_id]
		if not d.jobs.is_empty() or not d.done.is_empty() or d.own_done:quit(1);return
		if alpha and (d.own_job.get("step")!=1 or p.stories.bobo!=1 or p.inventory.gold_ore!=0):quit(1);return
		if not alpha and (not d.own_job.is_empty() or p.stories.bobo!=0 or p.inventory.gold_ore!=3):quit(1);return
	else:
		if session.snapshot.bobo_workshop.own_job.get("step")!=1:quit(1);return
		session.perform("bobo_sort_answer",Bobo.CELL,"0:large")
		session.perform("bobo_sort_answer",Bobo.CELL,"1:medium")
		session.perform("bobo_sort_answer",Bobo.CELL,"2:small")
		session.perform("bobo_sort_claim",Bobo.CELL)
		session.perform("bobo_sort_claim",Bobo.CELL)
		await create_timer(.7).timeout
		if not session.snapshot.bobo_workshop.own_done or session.snapshot.players[session.own_id].inventory.gold_sample!=1:quit(1);return
	print("BOBO_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
