extends "res://tests/test_bakery_journey.gd"
## Follow the earned kitchen journey with rice farming, shoreline gathering,
## cooking and a first-layer mining trip. Only the world clock is accelerated.

func after_chapter()->void:
	super.after_chapter()
	if failed:return
	var weather=World.WEATHER
	var day:=int(weather.day_index(world.state.time))
	var season_day:=posmod(day,weather.DAYS_PER_SEASON*4)
	if season_day<weather.DAYS_PER_SEASON or season_day>=weather.DAYS_PER_SEASON*3:
		var until_summer:=posmod(weather.DAYS_PER_SEASON-season_day,weather.DAYS_PER_SEASON*4)
		bk_step(float(until_summer)*weather.DAY_SECONDS,"wait for rice season")
	bk_buy("rice",1)
	bk_run("travel",World.REGIONS.exit_cell("home"),"lanyang")
	var paddy:=Vector2i(32,26)
	bk_run("hoe",paddy)
	bk_run("seed",paddy,"rice")
	bk_run("water",paddy)
	bk_step(float(World.CROPS.rice.time),"grow rice in Lanyang")
	bk_run("harvest",paddy)
	expect(held("rice")==2,"one earned rice crop yields two rice")
	bk_run("travel",World.REGIONS.exit_cell("lanyang"),"home")
	bk_run("axe",World.SEAWEED_CELL)
	expect(held("seaweed")==1,"gather seaweed from the south coast")
	bk_run("queue_cook",stove,"star_rice_ball")
	bk_step(60.0,"cook rice balls")
	bk_run("claim_cook",stove)
	expect(held("star_rice_ball")==3,"cooking earns three rice balls")
	bk_run("transit",World.REGIONS.exit_cell("home"),"toucheng")
	bk_run("transit",World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	bk_run("transit",World.TRANSIT.points("ruifang").bus.cell,"jiufen")
	bk_run("transit",World.TRANSIT.points("jiufen").shuttle.cell,"jinguashi")
	bk_run("mine_travel",World.MINES.ENTRY,"mine_1")
	bk_run("mine_extract",World.MINES.NODES[0])
	var tired:=int(person().mine_energy)
	expect(tired<100,"mining consumes energy")
	if failed:return
	actions+=1
	expect(world.act(TOKEN,"journey-%d"%actions,"eat_rice_ball",Vector2i.ZERO).ok,"eat the earned rice ball in the mine")
	expect(held("star_rice_ball")==2 and int(person().mine_energy)==mini(100,tired+World.RICE_BALL_ENERGY),"one rice ball restores the expected amount")
	var reopened:=World.new()
	if expect_saved(reopened):
		var miner:Dictionary=reopened.state.players[TOKEN]
		expect(miner.region=="mine_1" and miner.mine_energy==100 and miner.inventory.star_rice_ball==2,"primary save retains location, restored energy, and remaining portions")
	print("STAR_RICE_BALL_JOURNEY checks=%d failures=%d energy=%d->%d"%[checks,failures,tired,int(person().mine_energy)])

func expect_saved(reopened:World)->bool:
	var loaded:=reopened.load_world(world.save_path) and not reopened.recovered_from_backup
	expect(loaded,"reload primary save after eating")
	return loaded
