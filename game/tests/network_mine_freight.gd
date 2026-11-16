extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Freight=World.MINE_FREIGHT
const ACTOR="freight-net-alpha"
const OTHER="freight-net-beta"
var session:Session
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->bool:
	if not value:failures+=1;push_error(label)
	return value
func person()->Dictionary:return session.snapshot.get("players",{}).get(session.own_id,{})
func job()->Dictionary:return session.snapshot.get("mine_freight",{}).get("own_job",{})
func until(test:Callable,seconds:float=10.0)->bool:
	var limit:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<limit:await create_timer(.05).timeout
	return check(test.call(),"Timed out waiting for freight network state")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var mode:=args[0]
	if mode=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.mine_depths={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
		for actor in [ACTOR,OTHER]:
			world.add_player(actor,actor)
			var p:Dictionary=world.state.players[actor]
			p.region="mine_4" if actor==ACTOR else "lanyang"
			p.x=34.5 if actor==ACTOR else 12.5
			p.y=20.5
			p.inventory.copper_ore=10
		world.state.regions.lanyang.crops["13,20"]={"kind":"radish","owner":OTHER,"growth":0.0,"wet":true,"remaining":1}
		world.state.objects["41,35"]={"type":"private_chest","owner":ACTOR,"items":{}}
		world.state.objects["42,35"]={"type":"private_chest","owner":OTHER,"items":{"stone":7}}
		world.state.mine_freight.jobs[OTHER]={"status":"transit","items":{"stone":3},"target":{"cell":"42,35","id":"b".repeat(32)},"ready":60.0}
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=ACTOR if args[2]=="alpha" else OTHER
	session.changed.connect(func(snapshot:Dictionary,_id:String):
		var f:Dictionary=snapshot.mine_freight
		check(f.jobs.is_empty(),"Freight actor map is private")
		var own:String="41,35" if args[2]=="alpha" else "42,35"
		check(f.own_home_chests.size()==1 and f.own_home_chests[0].cell==own and f.own_home_chests[0].size()==2,"Only own destination metadata is projected")
	)
	if session.join("127.0.0.1",int(args[1]),args[2],"freight-test")!=OK or not await until(func():return not person().is_empty()):
		quit(1)
		return
	if mode=="start" and args[2]=="alpha":
		session.request_action.rpc_id(1,1,"freight_load",Freight.LOAD_CELL,"copper_ore:9","mine_4",99)
		await create_timer(.3).timeout
		check(job().is_empty() and person().inventory.copper_ore==10,"Wrong epoch cannot load")
		session.perform("freight_load",Freight.LOAD_CELL,"copper_ore:4")
		session.request_action.rpc_id(1,1,"freight_load",Freight.LOAD_CELL,"copper_ore:4","mine_4",0)
		session.perform("freight_target",Freight.LOAD_CELL,"42,35")
		session.perform("freight_target",Freight.LOAD_CELL,"41,35")
		session.perform("freight_dispatch",Freight.LOAD_CELL)
		if not await until(func():return job().get("status")=="transit"):quit(1);return
		check(person().inventory.copper_ore==6 and int(job().items.copper_ore)==4,"Duplicate sequence did not repeat debit")
	elif args[2]=="beta":
		if not await until(func():return int(session.snapshot.region_population.get("mine_4",0))==1):quit(1);return
		session.perform("freight_claim",Freight.CLAIM_CELL)
		session.perform("hoe",Vector2i(14,20))
		if not await until(func():return session.snapshot.crops.has("14,20") and float(session.snapshot.crops["13,20"].growth)>1.0):quit(1);return
		check(job().items.has("stone") and not job().items.has("copper_ore") and person().inventory.copper_ore==10,"Other region cannot claim or see alpha cargo")
	else:
		if not await until(func():return job().get("status")=="delivered",15.0):quit(1);return
		check(int(job().items.copper_ore)==4 and person().inventory.copper_ore==6,"Reconnect shows delivered receipt and same backpack")
		session.perform("freight_claim",Freight.CLAIM_CELL)
		await create_timer(.3).timeout
		check(person().inventory.copper_ore==6,"Delivered cargo cannot be claimed again")
	print("FREIGHT_ENET mode=%s role=%s failures=%d"%[mode,args[2],failures])
	session.shutdown()
	await create_timer(.2).timeout
	quit(int(failures>0))
