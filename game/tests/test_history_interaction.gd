extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	root.size=Vector2i(1024,640)
	var socket:=PacketPeerUDP.new();socket.bind(0);var port:=socket.get_local_port();socket.close()
	var path:="user://history-ui-isolated-world.json"
	check(app.session.host(port,"記憶測試",path)==OK,"Local authoritative session starts")
	await create_timer(0.1).timeout
	var world:World=app.session.world;var actor:String=app.session.peers[1]
	world.state.players[actor].region="lanyang";world.state.players[actor].x=32.5;world.state.players[actor].y=29.5
	for cell in World.LANYANG_LIFE.BLOCKAGES:world.state.lanyang_life.cleared[World.key(cell)]=true
	world.state.lanyang_life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate();world.state.lanyang_life.repaired=true
	var record:=World.HISTORY_MEMORY.fresh_record();record.seen=["33,22","33,25","33,32"]
	world.state.history_memory.players[actor]=record
	app.session._send_snapshot(1);app.HistoryUI.open(app,"play")
	for i in range(4):await process_frame
	var inventory:Dictionary=world.state.players[actor].inventory.duplicate(true)
	for index in range(3):
		var scene=app.modal.find_child("MemoryScene",true,false)
		check(scene!=null,"Live scene exists in round "+str(index+1))
		# First attempt demonstrates failure without losing progress or materials.
		if index==0:
			for button in scene.find_children("*","Button",true,false):
				if button.text=="試放水":button.pressed.emit()
			check(int(world.state.history_memory.players[actor].round)==0,"Wrong water allocation does not complete round")
			check(app.modal_feedback.text.contains("不符合"),"Failure reason visible in fixed footer")
		var targets:Array=[[2,2],[1,3],[2,1]][index]
		for which in range(2):
			for turn in range(targets[which]):
				scene.gates[which].pressed.emit()
				await create_timer(0.12).timeout
		check(world.state.history_memory.players[actor].gates==targets,"Real gate signals persist server values")
		for button in scene.find_children("*","Button",true,false):
			if button.text=="試放水":button.pressed.emit()
		check(int(world.state.history_memory.players[actor].round)==index+1,"Real flow signal advances once")
		await create_timer(0.15).timeout
	check(app.modal.find_child("MemoryPlaque",true,false)!=null,"Completed play transforms into return journal")
	app.modal.find_child("MemoryPlaque",true,false).pressed.emit()
	check(world.state.history_memory.plaque,"Live plaque signal changes shared world")
	check(app.modal.find_child("MemoryPlaque",true,false).disabled,"Shared plaque cannot be placed twice")
	check(world.state.players[actor].inventory==inventory,"Memory consumes no inventory and cannot grant materials")
	app.HistoryUI.open_replay(app)
	var before:Dictionary=world.state.duplicate(true)
	var replay=app.modal.find_child("MemoryReplay",true,false)
	replay.gates[0].pressed.emit()
	check(world.state==before,"Replay stays local without world mutations")
	app._close_modal();check(not is_instance_valid(app.modal),"Exit restores island")
	var reload:=World.new();check(reload.load_world(world.save_path) and reload.state.history_memory.plaque,"Server UI operations survive save reload")
	app.session.shutdown();await create_timer(0.1).timeout;app.queue_free();await process_frame
	print("HISTORY_INTERACTION_TEST checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
