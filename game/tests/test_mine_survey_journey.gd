extends "res://tests/test_mine_depths_journey.gd"

const Layout=preload("res://scripts/mine_layout.gd")
const Survey=World.MINE_SURVEY

func after_chapter() -> void:
	super.after_chapter()
	if failed:return

	var actions_before:=actions
	var walking_before:=walking
	var sample_before:=int(bag().get("gold_sample",0))
	expect(world.player_region(TOKEN)==World.REGIONS.HOME and world.state.mine_depths.unlocked==5,"Naturally unlocked all floors and returned home")
	expect(Survey.own_record(world.state,TOKEN)==Survey.FRESH,"Start the survey with an empty record")
	checkpoint("survey-start")
	act("transit",World.REGIONS.exit_cell(World.REGIONS.HOME),World.REGIONS.JINGUASHI)
	act("mine_travel",World.MINES.ENTRY,"mine_1")
	for depth in range(1,6):
		var point:Vector2i=Survey.POINTS[depth]
		walk_to(point,1.0)
		if failed:return
		var foot:=Vector2i(int(person().x),int(person().y))
		expect(Layout.land(foot,depth) and not Layout.BASE_RECT.has_point(foot),"Walked into the B%d side cave"%depth)
		act("survey_observe",point)
		var record:=Survey.own_record(world.state,TOKEN)
		expect(record.seen.size()==depth and record.seen.get(str(depth),false) and not record.claimed,"Record only the newly visited observation on B%d"%depth)
		checkpoint("survey-b%d"%depth)
		if depth<5:act("mine_travel",World.MINES.DOWN,"mine_%d"%(depth+1))

	for depth in range(5,1,-1):
		act("mine_travel",World.MINES.UP,"mine_%d"%(depth-1))
	act("mine_travel",World.MINES.UP,World.REGIONS.JINGUASHI)
	var table:Vector2i=world.bobo_sites().table
	walk_to(table)
	checkpoint("survey-ready")
	act("survey_claim",table)
	expect(Survey.own_record(world.state,TOKEN).claimed and int(bag().get("gold_sample",0))==sample_before+1,"Claim exactly one additional sample at the sorting table")
	checkpoint("survey-claimed")
	if failed:return

	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Reload the successfully claimed save")
	if failed:return
	world=reopened
	var record:=Survey.own_record(world.state,TOKEN)
	expect(record.seen.size()==5 and record.claimed and int(bag().get("gold_sample",0))==sample_before+1,"All five observations and the reward survive reload")
	walk_to(table)
	if failed:return
	var before:=world.state.duplicate(true)
	actions+=1
	var retry:=world.act(TOKEN,"journey-%d"%actions,"survey_claim",table)
	expect(not retry.ok and world.state==before,"A new claim request after reload grants nothing and leaves the save untouched")
	checkpoint("survey-reloaded")
	print("MINE_SURVEY_NATURAL_LOOP survey_actions=%d survey_walk_tiles=%d total_actions=%d total_walk_tiles=%d no_fixture_grants=true no_teleport=true headless=true"%[actions-actions_before,walking-walking_before,actions,walking])
