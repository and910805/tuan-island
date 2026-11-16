extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
var session
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->bool:
	if not value:failures+=1;push_error(message)
	return value
func person()->Dictionary:return session.snapshot.get("players",{}).get(session.own_id,{})
func wait_until(test:Callable,seconds:float=6.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	return check(test.call(),"Network condition timed out")
func walk_to(target:Vector2i)->bool:
	var w:=World.new()
	w.state=session.snapshot.duplicate(true);w._region=str(session.snapshot.region_id)
	var start:=Vector2i(int(person().x),int(person().y))
	var queue:=[start];var previous:={start:start};var cursor:=0;var found:=Vector2i(-1,-1)
	while cursor<queue.size():
		var cell:Vector2i=queue[cursor];cursor+=1
		if cell!=target and Vector2(cell-target).length()<=1.5:found=cell;break
		for delta in World.INDUSTRY.NEIGHBORS:
			var next:Vector2i=cell+delta
			if not previous.has(next) and w.can_stand(Vector2(next)+Vector2(0.5,0.5)):previous[next]=cell;queue.append(next)
	if not check(found!=Vector2i(-1,-1),"Reachable network walking route"):return false
	var path:=[found]
	while found!=start:found=previous[found];path.push_front(found)
	for cell:Vector2i in path:
		var deadline:=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			var delta:=Vector2(cell)+Vector2(0.5,0.5)-Vector2(person().x,person().y)
			if delta.length()<0.16:break
			session.input_direction(delta.normalized() if delta.length()>0.45 else delta*2.0)
			await create_timer(0.04).timeout
		session.input_direction(Vector2.ZERO)
		if not check(Time.get_ticks_msec()<deadline,"Server movement reached path cell"):return false
	return true
func run()->void:
	var args:=OS.get_cmdline_user_args();var mode:=args[0]
	if mode=="seed":
		var w:=World.new();w.save_path=args[1];w.state.board=true;w.state.picnic=true
		for role in ["alpha","beta"]:
			w.add_player("jinguashi-user-"+role,role)
			var p:Dictionary=w.state.players["jinguashi-user-"+role]
			p.region="home" if role=="alpha" else "lanyang"
			p.x=46.5 if role=="alpha" else 12.5;p.y=30.5 if role=="alpha" else 20.5
			p.inventory.reinforced_pick=1
			# This fixture isolates mining and concurrent Lanyang growth after a known route.
			p.travel_book.visited.jinguashi=true
		w.state.regions.lanyang.crops["14,22"]={"kind":"radish","owner":"jinguashi-user-beta","growth":0.0,"wet":true,"remaining":1}
		quit(0 if w.save() else 1);return
	var island:=Node.new();island.name="Island";root.add_child(island)
	session=Session.new();island.add_child(session);session.profile.token="jinguashi-user-"+args[2]
	session.notice.connect(func(message:String,_ok:bool):print(message))
	session.changed.connect(func(s:Dictionary,id:String):
		for key in s.players:
			if key!=id:check(not s.players[key].has("inventory") and not s.players[key].has("coins"),"Peer inventory private")
	)
	if session.join("127.0.0.1",int(args[1]),args[2],"jinguashi-test")!=OK:quit(1);return
	if not await wait_until(func():return not person().is_empty()):quit(1);return
	if args[2]=="beta":
		var ok:=await wait_until(func():return int(session.snapshot.get("region_population",{}).get("jinguashi",0))==1,20.0)
		check(ok and session.snapshot.region_id=="lanyang" and session.snapshot.crops.has("14,22"),"Split region remains isolated")
		await create_timer(2).timeout
		check(float(session.snapshot.crops["14,22"].growth)>1.0,"Farm grows while friend travels")
	elif mode=="start":
		session.perform("transit",Vector2i(47,30),"jinguashi")
		if not await wait_until(func():return session.snapshot.region_id=="jinguashi"):quit(1);return
		check(not session.snapshot.crops.has("14,22"),"Lanyang field absent from mine")
		if not await walk_to(Vector2i(28,20)):quit(1);return
		session.perform("pick",Vector2i(28,20))
		if not await wait_until(func():return int(person().inventory.get("copper_ore",0))==4):quit(1);return
		var sequence:int=session.counter
		session.request_action.rpc_id(1,sequence,"pick",Vector2i(28,20),"","jinguashi",int(person().travel_epoch))
		await create_timer(0.3).timeout
		check(int(person().inventory.copper_ore)==4,"Repeated request does not duplicate ore")
	else:
		check(session.snapshot.region_id=="jinguashi" and int(person().inventory.get("copper_ore",0))==4,"Reconnect restores region and ore")
		if not await walk_to(Vector2i(11,20)):quit(1);return
		session.perform("transit",Vector2i(11,20),"home")
		await wait_until(func():return session.snapshot.region_id=="home")
		check(int(person().inventory.copper_ore)==4,"Return carries same ore")
	print("JINGUASHI_ENET_PASS mode=%s role=%s failures=%d"%[mode,args[2],failures])
	session.shutdown();await create_timer(0.2).timeout;island.queue_free();await process_frame;quit(int(failures>0))
