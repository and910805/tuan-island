extends SceneTree
const World=preload("res://scripts/world.gd")
const A:="backup-fixture-owner"
const B:="backup-fixture-guest"
func _initialize()->void:run.call_deferred()
func run()->void:
	var directory:=OS.get_environment("TUAN_BACKUP_QA_SOURCE")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	var w:=World.new()
	w.save_path=directory.path_join("world.json")
	w.state.time=100.0
	for token in [A,B]:
		w.add_player(token,"QA原島民")
		w.state.players[token].x=37.5
		w.state.players[token].y=34.5
	w.state.players[B].y=33.5
	var person:Dictionary=w.state.players[A]
	person.inventory.wood=80
	person.coins=257
	person.stories.aru=1
	for x in range(36,40):
		for y in range(33,36):w.state.removed[World.key(Vector2i(x,y))]=true
	var sequence:=0
	for step in [["build",Vector2i(36,34),"chest"],["deposit",Vector2i(36,34),"wood"],["deposit",Vector2i(36,34),"wood"],["deposit",Vector2i(36,34),"wood"],["hoe",Vector2i(38,34),""],["seed",Vector2i(38,34),"radish"]]:
		sequence+=1
		var result:=w.act(A,"backup-fixture-%d"%sequence,step[0],step[1],step[2])
		if not result.ok:push_error(str(result));quit(1);return
	assert(w.save())
	var loaded:=World.new()
	assert(loaded.load_world(w.save_path))
	var evidence:=FileAccess.open(directory.path_join("fixture-expected.json"),FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"inventory":person.inventory,"coins":person.coins,"stories":person.stories,"players":[A,B],"chest":"36,34","plot":"38,34","new_chair":"38,35"},"\t"))
	print("BACKUP_FIXTURE_VALIDATED players=2 stored_wood=3 coins=257 story=aru1 planted=radish")
	quit(0)
