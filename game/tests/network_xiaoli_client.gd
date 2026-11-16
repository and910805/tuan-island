extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const TOKENS:={"alpha":"xiaoli-network-alpha","beta":"xiaoli-network-beta"}
var role:=""
var port:=28711
var barrier:=""
var island:Node2D
var client:Node
var notices:Array[bool]=[]
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(value:bool,message:String) -> void:
	if not value:
		failures+=1
		push_error(role+" "+message)

func wait_for(check:Callable,message:String) -> bool:
	var deadline:=Time.get_ticks_msec()+7000
	while not check.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	var result:bool=check.call()
	expect(result,message)
	return result

func person(which:String) -> Dictionary:
	return client.snapshot.get("players",{}).get(String(TOKENS[which]).sha256_text().left(16),{})

func story(which:String) -> int:
	return int(person(which).get("stories",{}).get("xiaoli",-1))

func open_client() -> bool:
	client=Session.new()
	island.add_child(client)
	client.notice.connect(func(_message:String,success:bool):notices.append(success))
	if client.join("127.0.0.1",port,role,"integration-key")!=OK:
		expect(false,"cannot initiate connection")
		return false
	return await wait_for(func():return not person(role).is_empty(),"receive own player snapshot")

func close_client() -> void:
	client.shutdown()
	get_multiplayer().multiplayer_peer=null
	island.remove_child(client)
	client.queue_free()
	client=null

func mark(stage:String) -> void:
	var file:=FileAccess.open(barrier+"-"+role+"."+stage,FileAccess.WRITE)
	expect(file!=null,"write coordination marker")
	if file:file.close()

func marked(who:String,stage:String) -> bool:
	return FileAccess.file_exists(barrier+"-"+who+"."+stage)

func exercise() -> void:
	if not await open_client():return
	var other:="beta" if role=="alpha" else "alpha"
	if not await wait_for(func():return not person(other).is_empty(),"both player records visible"):return
	expect(story(role)==0 and story(other)==0,"old two-resident fixture migrates to independent zero progress")
	expect(person(role).stories.aru==(1 if role=="alpha" else 2),"old resident progress is retained")
	mark("ready")
	if not await wait_for(func():return marked(other,"ready"),"both clients read old save"):return
	var q:Dictionary=World.Village.QUESTS.xiaoli[0]
	var cell:Vector2i=World.Village.NPCS.xiaoli.cell
	var coins:int=person(role).coins
	var bag:Dictionary=person(role).inventory.duplicate(true)
	if role=="beta":
		if not await wait_for(func():return story("alpha")==1,"alpha advances first"):return
		expect(story("beta")==0,"alpha does not advance beta")
	notices.clear()
	client.perform("quest",cell,"xiaoli:0")
	client.perform("quest",cell,"xiaoli:0")
	if not await wait_for(func():return notices.size()>=2 and story(role)==1,"receive first advancement and replay response"):return
	expect(notices==[true,false],"duplicate story stage rejects the second request")
	expect(int(person(role).coins)==coins+int(q.coins),"coins pay once")
	for item in q.items:
		expect(int(person(role).inventory.get(item,0))==int(bag.get(item,0))-int(q.items[item])+int(q.reward.get(item,0)),"material is deducted once")
	for item in q.reward:
		expect(int(person(role).inventory.get(item,0))==int(bag.get(item,0))-int(q.items.get(item,0))+int(q.reward[item]),"item reward pays once")
	if not await wait_for(func():return story(other)==1,"other player independently advances"):return
	mark("complete")
	if not await wait_for(func():return marked(other,"complete"),"both clients completed initial stage"):return
	close_client()
	await create_timer(0.6).timeout
	notices.clear()
	if not await open_client():return
	expect(story(role)==1 and int(person(role).coins)==coins+int(q.coins),"reconnect preserves progress and exact reward")
	client.perform("quest",cell,"xiaoli:0")
	if not await wait_for(func():return not notices.is_empty(),"reconnect replay answered"):return
	expect(notices==[false] and story(role)==1 and int(person(role).coins)==coins+int(q.coins),"reconnect replay cannot repeat reward")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			for who in TOKENS:
				if arg.trim_prefix("--profile=")==TOKENS[who]:role=who
		if arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--barrier="):barrier=arg.trim_prefix("--barrier=")
	if role.is_empty() or barrier.is_empty() or not World.Village.NPCS.has("xiaoli"):
		push_error("Expected a test role, barrier path, and the Xiaoli rules")
		quit(1)
		return
	island=Node2D.new()
	island.name="Island"
	root.add_child(island)
	await exercise()
	if is_instance_valid(client):close_client()
	await process_frame
	print("XIAOLI_NETWORK_TEST role=%s failures=%d"%[role,failures])
	quit(0 if failures==0 else 1)
