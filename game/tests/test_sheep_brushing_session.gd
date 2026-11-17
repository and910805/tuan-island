extends "res://tests/network_egg_basket.gd"
const View=preload("res://scripts/world_view.gd")
const SITE:=Vector2i(50,35)
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHEEP_BRUSH_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func run()->void:
	path=OS.get_environment("TEMP").path_join("sheep-brush-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"照料者")
		fixture.state.players[token].x=50.5
		fixture.state.players[token].y=36.5
	if not check(fixture.save(),"Save isolated picnic/standing fixture with normal inventory"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("BrushHost","brush-host")
	if not check(host.host(port,"牧場",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start dedicated real WebSocket host"):return
	var grower:=make_session("BrushOne",GROWER)
	var friend:=make_session("BrushTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(grower.join(address,port,"照料者",ROOM)==OK and friend.join(address,port,"照料者",ROOM)==OK,"Join two separate client APIs"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both clients enter"):return
	var view:=View.new()
	root.add_child(view)
	view.set_process(false)
	view.update_snapshot(friend.snapshot.duplicate(true),friend.own_id)
	grower.perform("livestock_brush",SITE,"sheep")
	friend.perform("livestock_brush",SITE,"sheep")
	if not check(await wait_for(func():return notices[grower].size()>0 and notices[friend].size()>0),"Both simultaneous care requests get a result"):return
	var successes:=int(notices[grower].back().ok)+int(notices[friend].back().ok)
	if not check(successes==1 and int(host.world.state.livestock.sheep.bond)==1,"Only one simultaneous brush increases shared bond"):return
	if not check(await wait_for(func():return grower.snapshot.get("livestock",{}).get("sheep",{}).get("last_care","")=="brush" and friend.snapshot.get("livestock",{}).get("sheep",{}).get("last_care","")=="brush"),"Both clients receive actual brush marker"):return
	view.update_snapshot(friend.snapshot.duplicate(true),friend.own_id)
	if not check(view.livestock_pet_feedback.has("sheep"),"Observer view detects the authoritative new grooming event"):return
	var stamp:float=view.livestock_pet_feedback.sheep
	view.elapsed+=0.3
	view.update_snapshot(friend.snapshot.duplicate(true),friend.own_id)
	if not check(view.livestock_pet_feedback.sheep==stamp,"Repeated wire snapshot does not restart observer animation"):return
	if not check(not await action(grower,"livestock_pet",SITE,"sheep"),"Petting cannot bypass brush cooldown over wire"):return
	friend.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host observes client disconnect"):return
	var returned:=make_session("BrushReturned",FRIEND)
	if not check(returned.join(address,port,"照料者",ROOM)==OK,"Reconnect original profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and returned.snapshot.get("livestock",{}).get("sheep",{}).get("bond",0)==1),"Reconnect retains same animal bond"):return
	view.data={}
	view.update_snapshot(returned.snapshot.duplicate(true),returned.own_id)
	if not check(view.livestock_pet_feedback.is_empty(),"Reconnect baseline never replays prior grooming"):return
	if not check(not await action(returned,"livestock_brush",SITE,"sheep"),"Reconnect does not reset care cooldown"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and saved.state.livestock.sheep.last_care=="brush" and int(saved.state.livestock.sheep.bond)==1,"Persisted authoritative brush and exactly one bond reload"):return
	view.queue_free()
	finish(0)
