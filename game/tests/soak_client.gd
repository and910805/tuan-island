extends SceneTree
const Session=preload("res://scripts/session.gd")
var session:Node
var done:=false
var failures:=0
var index:=0
var started:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	started=Time.get_ticks_msec()
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--index="):index=int(arg.trim_prefix("--index="))
	session.connected_world.connect(exercise)
	session.disconnected_world.connect(func():
		if not done:push_error("SOAK_DISCONNECTED");quit(1))
	session.join("127.0.0.1",28562,"長測%d"%index,"soak-key")
	await create_timer(400).timeout
	if not done:push_error("SOAK_TIMEOUT");quit(1)
func expect(value:bool,message:String) -> void:
	if not value:failures+=1;push_error(message)
func exercise() -> void:
	await create_timer(2).timeout
	expect(session.snapshot.players.size()==4,"Four clients joined")
	var plot:=Vector2i(37+index,35)
	var floor_pos:=Vector2i(37+index,34)
	session.perform("hoe",plot)
	await create_timer(0.2).timeout
	session.perform("build",floor_pos,"floor")
	await create_timer(0.2).timeout
	session.perform("remove",floor_pos)
	await create_timer(0.2).timeout
	session.perform("plant_tree",floor_pos)
	await create_timer(0.2).timeout
	for cycle in range(4):
		session.perform("seed",plot,"radish")
		await create_timer(0.2).timeout
		session.perform("water",plot)
		await create_timer(0.2).timeout
		# Real elapsed wall time; no artificial world-clock acceleration.
		await create_timer(92).timeout
		session.perform("harvest",plot)
		await create_timer(0.3).timeout
		var person:Dictionary=session.snapshot.players[session.own_id]
		expect(int(person.inventory.get("radish",0))==cycle+1,"exactly one radish per real growth cycle")
		if cycle in [1,3]:
			expect(session.snapshot.forest.get("%d,%d"%[floor_pos.x,floor_pos.y],{}).get("mature",false),"tree matures in real elapsed world time")
			for hit in range(3):
				session.perform("axe",floor_pos)
				await create_timer(0.2).timeout
			person=session.snapshot.players[session.own_id]
			expect(int(person.inventory.wood)==12+6*((cycle+1)/2),"each real growth tree yields exactly six wood")
			expect(int(person.inventory.sapling)==2,"replacement sapling conserves supply")
			if cycle==1:
				session.perform("plant_tree",floor_pos)
				await create_timer(0.2).timeout
		print("SOAK_CYCLE index=%d cycle=%d players=%d memory=%d elapsed=%.1f"%[index,cycle+1,session.snapshot.players.size(),Performance.get_monitor(Performance.MEMORY_STATIC),(Time.get_ticks_msec()-started)/1000.0])
	done=true
	print("SOAK_COMPLETE index=%d failures=%d elapsed=%.1f"%[index,failures,(Time.get_ticks_msec()-started)/1000.0])
	session.shutdown()
	quit(0 if failures==0 else 1)
