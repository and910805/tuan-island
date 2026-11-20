extends "res://tests/test_lingpopo_bell_session.gd"
## T066 N08-2 over a real loopback WebSocket: 鈴婆婆's 〈分不清的節拍〉 (page two of the island history).
## The pattern is △○□ = step indexes "102" (steps are ○=0 △=1 □=2), read from the picture only: no sound, no timer.
## Three independent clients with normal bonds: A and B are at 熟悉 (points 6), C is only 認識 (points 1).
## The real Session and World authority refuse wrong, missing, duplicated and forged payloads and forged network
## sequences, accept 102 only at 鈴婆婆's cell with enough friendship, never touch the bag, keep the result private to
## the player who made it, refuse a second hand-in and still offer page two (to whoever has not done it) after a save
## and a real host restart.
const ORD_TOKEN_A:="lingpopo-order-token-alpha"
const ORD_TOKEN_B:="lingpopo-order-token-bravo"
const ORD_TOKEN_C:="lingpopo-order-token-charlie"
const ORD_TOKENS:=[ORD_TOKEN_A,ORD_TOKEN_B,ORD_TOKEN_C]
const ORD_RIGHT:="102"
const ORD_PAGE:=2
const ORD_BAG:={"wood":3,"fiber":2}
const ORD_BAD_ORDER:="順序不太對"
const ORD_NEED_ALL:="三個步驟都要做過一次"
const ORD_REOPEN:="請重新打開關係事件"
const ORD_NOT_HERE:="請走到這位居民身邊"
const ORD_FRIEND:="關係到「熟悉」之後"

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LINGPOPO_ORDER_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func goal_extra(digits:String,stage:int=ORD_PAGE,choice:String="")->String:
	return "lingpopo:%d:%s:%s"%[stage,choice,digits]

func page_two(token:String)->bool:
	return Goals.done(person(token),"lingpopo").has(ORD_PAGE)

func bag(token:String)->Dictionary:
	return person(token).inventory

## One refused hand-in: the action fails with the expected reason, page two is not recorded, the bag is exactly as before.
func refuse(session:Session,token:String,cell:Vector2i,extra:String,needle:String,label:String,had_page:bool=false)->bool:
	var accepted:=await action(session,Goals.ACTION,cell,extra)
	return check(not accepted and needle in last_message(session) and page_two(token)==had_page and bag(token)==ORD_BAG,"%s: %s"%[label,last_message(session)])

func run()->void:
	path=OS.get_environment("TEMP").path_join("lingpopo-order-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	# ------------------------------------------------------------------ fixture: A and B at 熟悉, C only 認識, isolated save
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in ORD_TOKENS:
		fixture.add_player(token,"排鈴人")
		fixture.state.players[token].inventory=ORD_BAG.duplicate()
		fixture.state.players[token].bonds={"lingpopo":{"points":1 if token==ORD_TOKEN_C else 6,"talk_day":-1,"gift_day":-1}}
	if not check(fixture.save(),"Save the isolated order fixture"):return
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port"):return
	hub=make_session("OrderHost","order-host")
	if not check(hub.host(port,"節拍",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a real WS dedicated host"):return
	hub.set_physics_process(false)
	var a:=make_session("OrderA",ORD_TOKEN_A)
	var b:=make_session("OrderB",ORD_TOKEN_B)
	var c:=make_session("OrderC",ORD_TOKEN_C)
	var address:="ws://127.0.0.1:%d"%port
	if not check(a.join(address,port,"阿排",ROOM)==OK and b.join(address,port,"小節",ROOM)==OK and c.join(address,port,"新朋友",ROOM)==OK,"Join three independent clients"):return
	if not check(await wait_for(func():return not a.own_id.is_empty() and not b.own_id.is_empty() and not c.own_id.is_empty()),"All three enter"):return
	# ------------------------------------------------------------------ the rule as written: pictures only, no audio, no timer
	var entry:Dictionary=Goals.goal("lingpopo",ORD_PAGE)
	var glyphs:="".join(entry.steps)
	if not check(entry.order==[1,0,2] and "".join(entry.order.map(func(i):return str(i)))==ORD_RIGHT and "△" in entry.steps[1] and "○" in entry.steps[0] and "□" in entry.steps[2],"△○□ is step order 1,0,2"):return
	if not check("不用聽音高" in str(entry.task) and not entry.has("needs") and not entry.has("items") and not entry.has("options") and not entry.has("audio") and not entry.has("sound") and "聽" not in glyphs,"Page two is picture-only: no audio, item, option or prerequisite"):return
	if not check(Goals.done(person(ORD_TOKEN_A),"lingpopo").is_empty() and bag(ORD_TOKEN_A)==ORD_BAG and bag(ORD_TOKEN_B)==ORD_BAG and bag(ORD_TOKEN_C)==ORD_BAG,"Nobody has any page and every bag is the fixture bag"):return
	if not check(page_state(a,ORD_PAGE)=="open" and page_state(b,ORD_PAGE)=="open" and page_state(c,ORD_PAGE)=="locked","Page two is open at 熟悉 and locked at 認識"):return
	var cell:=bell_cell()
	var away:=cell+Vector2i(4,0)
	stand(ORD_TOKEN_A,cell)
	stand(ORD_TOKEN_B,cell)
	stand(ORD_TOKEN_C,cell)
	# ------------------------------------------------------------------ friendship, location
	if not await refuse(c,ORD_TOKEN_C,cell,goal_extra(ORD_RIGHT),ORD_FRIEND,"C stands at 鈴婆婆 with 102 but is only 認識"):return
	if not await refuse(a,ORD_TOKEN_A,Festival.TREE_CELL,goal_extra(ORD_RIGHT),ORD_NOT_HERE,"102 sent for the tree cell"):return
	stand(ORD_TOKEN_A,away)
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(ORD_RIGHT),"靠近一點","102 sent from outside interaction range"):return
	stand(ORD_TOKEN_A,cell)
	# ------------------------------------------------------------------ wrong, missing, duplicated and forged payloads at the right place
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("012"),ORD_BAD_ORDER,"○△□ is the wrong order"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("201"),ORD_BAD_ORDER,"□○△ is the wrong order"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(""),ORD_NEED_ALL,"No steps at all"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("10"),ORD_NEED_ALL,"A missing step"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("112"),ORD_NEED_ALL,"A repeated step"):return
	await create_timer(1.05).timeout
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("1020"),ORD_NEED_ALL,"An extra step"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra("1x2"),ORD_NEED_ALL,"A forged non-digit step"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(ORD_RIGHT,ORD_PAGE,"sound"),ORD_REOPEN,"A forged sound option on a pictures-only page"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(ORD_RIGHT,1),ORD_REOPEN,"102 forged onto page one"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(ORD_RIGHT,3),"「信任」","102 forged onto page three"):return
	if not await refuse(a,ORD_TOKEN_A,cell,goal_extra(ORD_RIGHT,4),"「好友」","102 forged onto page four"):return
	# ------------------------------------------------------------------ forged network sequences (B has made no hand-in yet)
	await create_timer(1.05).timeout
	if not await refuse(b,ORD_TOKEN_B,cell,goal_extra("021"),ORD_BAD_ORDER,"B's first request is a normal refusal"):return
	var epoch:=int(b.snapshot.get("players",{}).get(b.own_id,{}).get("travel_epoch",0))
	var region:=str(b.snapshot.get("region_id","home"))
	var settled:int=notices[b].size()
	var valid:=goal_extra(ORD_RIGHT)
	b.request_action.rpc_id(1,b.counter,Goals.ACTION,cell,valid,region,epoch)
	b.request_action.rpc_id(1,b.counter-1,Goals.ACTION,cell,valid,region,epoch)
	b.request_action.rpc_id(1,b.counter+5000,Goals.ACTION,cell,valid,region,epoch)
	b.request_action.rpc_id(1,b.counter+1,Goals.ACTION,cell,valid,"lanyang",epoch)
	b.request_action.rpc_id(1,b.counter+1,Goals.ACTION,cell,valid,region,epoch+1)
	await quiet(40)
	if not check(notices[b].size()==settled and not page_two(ORD_TOKEN_B) and bag(ORD_TOKEN_B)==ORD_BAG,"A replayed, past, far-future, wrong-region or wrong-epoch sequence with the right 102 changes nothing"):return
	# ------------------------------------------------------------------ the right pattern, at the right place, with enough friendship
	if not check(await action(a,Goals.ACTION,cell,goal_extra(ORD_RIGHT)) and "分不清的節拍" in last_message(a) and "島史第二頁" in last_message(a),"A lays △○□ at 鈴婆婆: %s"%last_message(a)):return
	if not check(page_two(ORD_TOKEN_A) and Goals.done(person(ORD_TOKEN_A),"lingpopo").size()==1 and not Goals.done(person(ORD_TOKEN_A),"lingpopo").has(1),"Host records exactly page two for A"):return
	if not check(bag(ORD_TOKEN_A)==ORD_BAG and int(person(ORD_TOKEN_A).get(Goals.BELL_INSPECT_KEY,0))==0,"Page two cost and gave nothing and needed no bell clue"):return
	send_all()
	if not check(await wait_for(func():return page_state(a,ORD_PAGE)=="done" and a.snapshot.get("players",{}).get(a.own_id,{}).get("inventory",{})==ORD_BAG),"A's own view shows page two done with the bag unchanged"):return
	await quiet()
	# ------------------------------------------------------------------ privacy and duplicate hand-in
	if not check(page_state(b,ORD_PAGE)=="open" and page_state(c,ORD_PAGE)=="locked" and not page_two(ORD_TOKEN_B) and not page_two(ORD_TOKEN_C),"B and C keep their own page-two state"):return
	if not check(public_clean(b,a) and public_clean(c,a) and public_clean(a,b) and not leaks_token(a.snapshot.get("players",{})),"Nobody's snapshot exposes A's goal record or any profile token"):return
	var sent:=a.counter
	var seen:int=notices[a].size()
	var a_epoch:=int(a.snapshot.get("players",{}).get(a.own_id,{}).get("travel_epoch",0))
	a.request_action.rpc_id(1,sent,Goals.ACTION,cell,valid,str(a.snapshot.get("region_id","home")),a_epoch)
	await quiet(40)
	if not check(notices[a].size()==seen and Goals.done(person(ORD_TOKEN_A),"lingpopo").size()==1,"Retransmitting A's accepted sequence does nothing"):return
	if not await refuse(a,ORD_TOKEN_A,cell,valid,MSG_DONE,"A's second hand-in is refused",true):return
	# ------------------------------------------------------------------ durable: reconnect, save, real restart
	if not check(hub.world.save(),"Host saves the room"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path) and Goals.done(loaded.state.players[ORD_TOKEN_A],"lingpopo").has(ORD_PAGE) and Goals.done(loaded.state.players[ORD_TOKEN_B],"lingpopo").is_empty() and loaded.state.players[ORD_TOKEN_A].inventory==ORD_BAG,"The save has page two for A only and an unchanged bag"):return
	for session in [a,b,c]:
		session.shutdown()
	hub.shutdown()
	await quiet(20)
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	hub=make_session("OrderHostTwo","order-host-two")
	if not check(hub.host(port2,"節拍",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Restart the dedicated host from the save"):return
	hub.set_physics_process(false)
	var address2:="ws://127.0.0.1:%d"%port2
	var a2:=make_session("OrderATwo",ORD_TOKEN_A)
	var b2:=make_session("OrderBTwo",ORD_TOKEN_B)
	var c2:=make_session("OrderCTwo",ORD_TOKEN_C)
	if not check(a2.join(address2,port2,"重開阿排",ROOM)==OK and b2.join(address2,port2,"重開小節",ROOM)==OK and c2.join(address2,port2,"重開新朋友",ROOM)==OK,"All three join the restarted host"):return
	if not check(await wait_for(func():return page_state(a2,ORD_PAGE)=="done" and page_state(b2,ORD_PAGE)=="open" and page_state(c2,ORD_PAGE)=="locked"),"After restart page two is done for A, still available for B, locked for C"):return
	send_all()
	await quiet()
	if not check(public_clean(b2,a2) and public_clean(c2,a2),"The restarted views stay private"):return
	stand(ORD_TOKEN_A,cell)
	stand(ORD_TOKEN_B,cell)
	if not await refuse(a2,ORD_TOKEN_A,cell,valid,MSG_DONE,"After restart A still cannot hand in twice",true):return
	if not check(await action(b2,Goals.ACTION,cell,valid) and page_two(ORD_TOKEN_B) and bag(ORD_TOKEN_B)==ORD_BAG and not page_two(ORD_TOKEN_C),"After restart B's own △○□ still opens page two with the bag unchanged"):return
	# ------------------------------------------------------------------ final durable state
	if not check(hub.world.save() and loaded.load_world(path) and page_two_in(loaded,ORD_TOKEN_A) and page_two_in(loaded,ORD_TOKEN_B) and not page_two_in(loaded,ORD_TOKEN_C),"Final save: A and B have page two, C does not"):return
	finish(0)

func page_two_in(world:World,token:String)->bool:
	return Goals.done(world.state.players[token],"lingpopo").has(ORD_PAGE)
