extends "res://tests/test_garden_journey.gd"

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	var memory = World.HISTORY_MEMORY
	checkpoint("observe")
	for point: Vector2i in memory.OBSERVATIONS:
		act("memory_observe",point)
	expect(world.state.history_memory.players[TOKEN].seen.size()==3,"Three observations reached through normal movement")
	var pairings := [[2,2],[1,3],[2,1]]
	for index in pairings.size():
		var gates: Array = pairings[index]
		act("memory_gate",memory.SERVICE,"a:%d"%gates[0])
		act("memory_gate",memory.SERVICE,"b:%d"%gates[1])
		if index==0:checkpoint("play")
		if index==1:checkpoint("round2")
		act("memory_flow",memory.SERVICE)
	expect(world.state.history_memory.players[TOKEN].completed,"Three rounds solved")
	checkpoint("memory-complete")
	act("memory_plaque",memory.SERVICE)
	checkpoint("plaque")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and reopened.state.history_memory.plaque and reopened.state.history_memory.players[TOKEN].completed,"History and plaque persist through reload")
	print("HISTORY_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f"%[actions,walking,world.state.time])
