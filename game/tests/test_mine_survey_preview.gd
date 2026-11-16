extends SceneTree
const World = preload("res://scripts/world.gd")
const TOKEN := "chapter-journey"
var world := World.new()
var out := ""
var sequence := 0

func arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="): return a.trim_prefix("--" + name + "=")
	return ""

func checkpoint(name: String) -> void:
	assert(world.save())
	assert(DirAccess.copy_absolute(world.save_path, out.path_join(name + ".json")) == OK)

func place(region: String, pos: Vector2) -> void:
	world.switch_region(region)
	assert(world.can_stand(pos), "Scripted position must be walkable")
	world.switch_region(World.REGIONS.HOME)
	var person: Dictionary = world.state.players[TOKEN]
	person.region = region
	person.x = pos.x
	person.y = pos.y

func action(name: String, target: Vector2i) -> Dictionary:
	sequence += 1
	return world.act(TOKEN, "survey-preview-%d" % sequence, name, target)

func run() -> void:
	out = arg("qa-dir")
	assert(not out.is_empty() and world.load_world(arg("qa-save")))
	assert(world.state.players.has(TOKEN))
	var initial: int = int(world.state.players[TOKEN].inventory.get("gold_sample", 0))
	var positions := [Vector2(16.5,12.5), Vector2(44.5,21.5), Vector2(24.5,33.5), Vector2(34.5,11.5), Vector2(44.5,24.5)]
	place("mine_1", positions[0])
	checkpoint("before")
	for depth in range(1, 6):
		place("mine_%d" % depth, positions[depth-1])
		var result := action("survey_observe", World.MINE_SURVEY.POINTS[depth])
		assert(result.get("ok", false), str(result))
		assert(world.state.mine_survey.players[TOKEN].seen.size() == depth)
		if depth == 1: checkpoint("observed")
	var table: Vector2i = world.bobo_sites().table
	world.switch_region(World.REGIONS.JINGUASHI)
	var position := Vector2.ZERO
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var candidate := Vector2(table + Vector2i(dx,dy)) + Vector2(0.5,0.5)
			if candidate.distance_to(Vector2(table)+Vector2(0.5,0.5)) <= 3.0 and world.can_stand(candidate):
				position = candidate
				break
		if position != Vector2.ZERO: break
	world.switch_region(World.REGIONS.HOME)
	assert(position != Vector2.ZERO)
	place(World.REGIONS.JINGUASHI, position)
	checkpoint("completed")
	var claim := action("survey_claim", table)
	assert(claim.get("ok", false), str(claim))
	assert(int(world.state.players[TOKEN].inventory.get("gold_sample",0)) == initial + 1)
	checkpoint("claimed")
	var reloaded := World.new()
	assert(reloaded.load_world(world.save_path))
	assert(reloaded.state.mine_survey.players[TOKEN].claimed and reloaded.state.mine_survey.players[TOKEN].seen.size() == 5)
	assert(int(reloaded.state.players[TOKEN].inventory.get("gold_sample",0)) == initial + 1)
	world = reloaded
	var repeated := action("survey_claim", table)
	assert(not repeated.get("ok", false))
	assert(int(world.state.players[TOKEN].inventory.get("gold_sample",0)) == initial + 1)
	print("SURVEY_SCRIPTED_TRAVERSAL_PASS initial=%d final=%d reload=true repeat_rejected=true" % [initial,initial+1])
	quit(0)

func _initialize() -> void:
	run.call_deferred()
