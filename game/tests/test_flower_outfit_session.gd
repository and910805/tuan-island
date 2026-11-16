extends "res://tests/test_corn_chowder_session.gd"
## Two WebSocket clients at the dye table in an isolated, unlocked fixture.

const Flower=World.FLOWER_NURSERY
const Tea=World.TEA_CERAMICS
const View=preload("res://scripts/world_view.gd")
var observer_view

func seed_world(path:String)->bool:
	var w:=World.new()
	for token in [ALPHA,BETA]:
		w.add_player(token,"workwear tester")
		var person:Dictionary=w.state.players[token]
		preset(person,"region",Flower.REGION)
		preset(person,"x",Flower.DYE_TABLE.x+(0.5 if token==ALPHA else 2.5))
		preset(person,"y",Flower.DYE_TABLE.y+1.5)
		preset(person.travel_book.visited,Flower.REGION,true)
		var tea:Dictionary=Tea.FRESH.duplicate(true)
		tea.merge({"intro":true,"potter":true,"reused":true,"reuse_count":1,"tea_discussed":true,"potter_story":true,"comparison_complete":true,"trials":{"jar":true,"fiber":true}},true)
		preset(w.state.tea_ceramics.players,token,tea)
		var flower:Dictionary=Flower.FRESH.duplicate(true)
		flower.merge({"letter":true,"intro":true},true)
		preset(w.state.flower_nursery.players,token,flower)
	preset(w.state.players[ALPHA].inventory,"blue_dye",2)
	w.save_path=path
	return w.save()

func sees_blue(observer:Client,subject:Client)->bool:
	return bool(observer.session.snapshot.get("players",{}).get(subject.session.own_id,{}).get("blue_outfit",false))

func capture_observer(name:String)->void:
	var directory:=OS.get_environment("WORKWEAR_NETWORK_QA_OUTPUT")
	if directory.is_empty():return
	if observer_view==null:
		root.size=Vector2i(1024,640)
		observer_view=View.new()
		observer_view.village_art_preview=true
		root.add_child(observer_view)
	observer_view.update_snapshot(beta.session.snapshot,beta.session.own_id)
	await pause(0.35)
	RenderingServer.force_draw()
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"capture observer view "+name)

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("flower-outfit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated save directory"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"seed dye table players"):return false
	var port:=start_server()
	if not expect(port>0,"host WebSocket server"):return false
	alpha=await join("dyer",ALPHA,port)
	beta=await join("observer",BETA,port)
	if not expect(joined(alpha) and joined(beta),"both clients joined"):return false
	await capture_observer("01-original")
	expect(not (await act(beta,"flower_outfit",Flower.DYE_TABLE,"blue")).ok,"observer cannot dye without material")
	expect((await act(alpha,"flower_outfit",Flower.DYE_TABLE,"blue")).ok,"dyer changes clothes")
	expect(await wait_until(func():return sees_blue(beta,alpha),3.0),"observer receives the dyed outfit")
	await capture_observer("02-blue")
	expect(alpha.bag().get("blue_dye")==1 and beta.bag().get("blue_dye",0)==0 and not sees_blue(alpha,beta),"only the dyer pays and changes")
	expect(not (await act(alpha,"flower_outfit",Flower.DYE_TABLE,"blue")).ok and alpha.bag().get("blue_dye")==1,"already blue does not spend again")
	leave(alpha)
	leave(beta)
	if not expect(await stop_server(),"stop server normally"):return false
	port=start_server()
	if not expect(port>0,"reload same save"):return false
	alpha=await join("dyer",ALPHA,port)
	beta=await join("observer",BETA,port)
	if not expect(joined(alpha) and joined(beta),"both reconnect"):return false
	expect(await wait_until(func():return sees_blue(beta,alpha),3.0),"observer sees blue after restart")
	expect((await act(alpha,"flower_outfit",Flower.DYE_TABLE,"original")).ok,"dyer changes back")
	expect(await wait_until(func():return not sees_blue(beta,alpha),3.0),"observer receives original colour")
	expect(alpha.bag().get("blue_dye")==1,"restoring original consumes no dye")
	return true
