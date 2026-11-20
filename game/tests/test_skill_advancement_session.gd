extends "res://tests/network_egg_basket.gd"

const Book=preload("res://scripts/island_skill_book.gd")
const PLOT:=Vector2i(48,27)

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SKILL_ADVANCEMENT_SESSION_TESTS checks=%d failures=%d"%[checks,code])
	quit(code)

func stand(world:World,tile:Vector2i)->void:
	var player:Dictionary=world.state.players[GROWER]
	player.x=tile.x+0.5
	player.y=tile.y+0.5

func run()->void:
	path="user://skill-advancement-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=path
	fixture.add_player(GROWER,"島民")
	fixture.add_player(FRIEND,"鄰居")
	var farmer:Dictionary=fixture.state.players[GROWER]
	farmer.harvests=9
	farmer.gathering_points=9
	farmer.crafting_points=9
	stand(fixture,PLOT)
	fixture.state.crops[World.key(PLOT)]={"kind":"radish","growth":World.CROPS.radish.time,"wet":true,"owner":GROWER}
	fixture.state.objects[World.key(BENCH)]={"type":"bench","owner":GROWER,"items":{}}
	var rock:=Vector2i(-1,-1)
	for y in range(PLOT.y-8,PLOT.y+9):
		for x in range(PLOT.x-8,PLOT.x+9):
			var tile:=Vector2i(x,y)
			if fixture.resource(tile)=="rock" and fixture.can_stand(Vector2(tile+Vector2i.DOWN)+Vector2(0.5,0.5)):
				rock=tile
				break
		if rock.x>=0:break
	if not check(rock.x>=0 and fixture.save(),"Save a fixture with a ready crop, a bench and nearby stone"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate local port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","skill-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start dedicated WebSocket room"):return
	var farmer_client:=make_session("Farmer",GROWER)
	var neighbor:=make_session("Neighbor",FRIEND)
	if not check(farmer_client.join(address,port,"Farmer",ROOM)==OK and neighbor.join(address,port,"Neighbor",ROOM)==OK,"Connect farmer and neighbor"):return
	if not check(await wait_for(func():return not farmer_client.own_id.is_empty() and not neighbor.own_id.is_empty()),"Both players enter"):return
	var neighbor_notices:int=notices[neighbor].size()
	if not check(await action(farmer_client,"harvest",PLOT),"Harvest over the network"):return
	if not check(notices[farmer_client].back().message.ends_with("農耕升到 3 級・解鎖「種子機」"),"Harvest feedback includes the new seed maker unlock"):return
	if not check(not await action(farmer_client,"harvest",PLOT),"Harvesting an empty plot fails"):return
	if not check(not notices[farmer_client].back().message.contains("升到"),"A rejected action does not announce advancement"):return
	stand(host.world,rock+Vector2i.DOWN)
	if not check(await action(farmer_client,"pick",rock) and not notices[farmer_client].back().message.contains("升到"),"The first strike alone does not award XP"):return
	if not check(await action(farmer_client,"pick",rock),"Gather the rock on the second strike"):return
	if not check(notices[farmer_client].back().message.ends_with("採集升到 3 級・解鎖「回收自種的成熟樹苗」"),"Gathering feedback includes the new sapling unlock"):return
	stand(host.world,BENCH+Vector2i.DOWN)
	if not check(await action(farmer_client,"craft",BENCH,"reinforced_pick"),"Craft an owned reinforced pick through the workbench"):return
	if not check(notices[farmer_client].back().message.ends_with("手作升到 3 級・解鎖「16×16 格藍圖」"),"Crafting feedback includes the new blueprint capacity"):return
	if not check(notices[neighbor].size()==neighbor_notices,"Another player does not receive private advancement messages"):return
	var reloaded:=World.new()
	if not check(reloaded.load_world(path) and not reloaded.recovered_from_backup,"Load the committed progress from the primary save"):return
	var restored:Dictionary=reloaded.state.players[GROWER]
	if not check(Book.core_levels(restored)==Vector3i(3,3,3) and int(restored.inventory.get("reinforced_pick",0))==1,"All three personal levels and the upgraded tool survived save reload"):return
	if not check(Book.core_levels(reloaded.state.players[FRIEND])==Vector3i.ONE,"Neighbor kept their original levels"):return
	finish(0)
