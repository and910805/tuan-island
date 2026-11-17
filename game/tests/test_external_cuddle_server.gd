extends "res://tests/network_egg_basket.gd"
## Windows test clients -> separate exported Linux/Docker server. No in-process host.
const Care=World.CHICKEN_CUDDLE
const KEY:="r20-isolated-room"
const A:="r20-external-one"
const B:="r20-external-two"
func make_session(branch_name:String,token:String)->Session:
	# Match the real scene's root name instead of an in-process test host path.
	# Isolate client APIs under branches while preserving that RPC-relative path.
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(),branch.get_path())
	var main:=Node.new()
	main.name=load("res://main.tscn").get_state().get_node_name(0)
	branch.add_child(main)
	var client:=Session.new()
	main.add_child(client)
	client.profile={"token":token}
	sessions.append(client)
	notices[client]=[]
	client.notice.connect(func(message:String,ok:bool):notices[client].append({"message":message,"ok":ok}))
	return client
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	print("EXPORTED_SERVER_CLIENTS checks=%d exit=%d"%[checks,code])
	quit(code)
func run()->void:
	var port:=int(OS.get_environment("TUAN_R20_PORT"))
	var address:="ws://127.0.0.1:%d"%port
	var first:=make_session("ExternalOne",A)
	if not check(first.join(address,port,"外部照料者",KEY)==OK,"Join exported Linux server from Windows client"):return
	if not check(await wait_for(func():return not first.own_id.is_empty()),"Real WS admission succeeds"):return
	if OS.get_environment("TUAN_R20_MODE")=="reload":
		if not check(Care.holder(first.snapshot).is_empty(),"Restart has no old held pose"):return
		if not check(int(first.snapshot.animal.bond)==2,"Two real care actions survived container restart"):return
		if not check(not await action(first,Care.ACTION,HEN),"Restart retains care cooldown"):return
		finish(0)
		return
	var second:=make_session("ExternalTwo",B)
	if not check(second.join(address,port,"外部旁觀者",KEY)==OK,"Join second independent Windows client API"):return
	if not check(await wait_for(func():return not second.own_id.is_empty()),"Two clients admitted"):return
	if not check(int(first.snapshot.animal.bond)==1,"Prior exported Windows EXE care is present"):return
	# Wait REAL server seconds; do not fast-forward, grant stock or mutate server.
	if not check(await wait_for(func():return float(first.snapshot.time)-float(first.snapshot.animal.last_pet)>30.1,40.0),"Actual thirty-second server cooldown elapses"):return
	var bag:Dictionary=first.snapshot.players[first.own_id].inventory.duplicate(true)
	notices[first].clear()
	notices[second].clear()
	first.perform(Care.ACTION,HEN)
	second.perform(Care.ACTION,HEN)
	if not check(await wait_for(func():return notices[first].size()>0 and notices[second].size()>0),"Simultaneous requests both complete"):return
	if not check(int(notices[first].back().ok)+int(notices[second].back().ok)==1,"Only one wins the shared hen"):return
	if not check(await wait_for(func():return not Care.holder(first.snapshot).is_empty() and Care.holder(first.snapshot)==Care.holder(second.snapshot)),"Both receive one identical public holder"):return
	if not check(int(first.snapshot.animal.bond)==2,"Only one further bond was awarded"):return
	if not check(not JSON.stringify(first.snapshot).contains(A) and not JSON.stringify(first.snapshot).contains(B),"No raw profile tokens in exported server snapshot"):return
	var held:=Care.holder(first.snapshot)
	var winner=first if held==first.own_id else second
	if not check(not await action(winner,"hoe",Vector2i(44,35)),"Exported server rejects tools during cuddle"):return
	var y:float=winner.snapshot.players[winner.own_id].y
	winner.input_direction(Vector2.DOWN)
	await create_timer(0.25).timeout
	winner.input_direction(Vector2.ZERO)
	if not check(await wait_for(func():return float(winner.snapshot.players[winner.own_id].y)>y),"Real input moves the holding player through server collision rules"):return
	if not check(await wait_for(func():return Care.holder(first.snapshot).is_empty() and Care.holder(second.snapshot).is_empty(),10.0),"Real eight-second Linux tick returns hen for both clients"):return
	if not check(first.snapshot.players[first.own_id].inventory==bag and int(first.snapshot.animal.bond)==2,"No duplicate reward or inventory mutation"):return
	finish(0)
