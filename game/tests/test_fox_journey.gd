extends "res://tests/test_flower_journey.gd"
## Fresh character, normal movement, public travel and fox actions.
## The existing journey clock accelerates time-based prerequisites.

func run() -> void:
	world.add_player(TOKEN_A,"溪谷訪客")
	chapter_one()
	if failed:return
	tea_route()
	if failed:return
	expect(world.player_region(tok)=="home","The tea delivery brings the player back to Wang'an")
	var gate:Vector2i=World.TRANSIT.points(Tea.MAOKONG).transfer.cell
	travel(FERRY,Tea.MAOKONG)
	travel(gate,World.Fox.REGION)
	if failed:return
	act("fox_track",World.Fox.SITE)
	var tracks:Array=World.Fox.TRACKS.keys()
	act("fox_track",tracks[0])
	var first_mark:=int(person().get("fox_tracks",0))
	expect(reload("half of the fox trail"),"A partially explored trail reloads")
	expect(int(person().get("fox_tracks",0))==first_mark and World.Fox.points(person()).size()==2,"Only the remaining trail marker is offered")
	act("fox_track",tracks[1])
	act("fox_adopt",World.Fox.SITE)
	expect(person().get(World.Fox.FIELD,{}).get("following",false),"The fox follows after both observations")
	var bamboo:=World.REGIONS.Bamboo
	expect(not bag().has(bamboo.ITEM),"The fresh traveller reaches the grove without bamboo")
	for index in 3:act("axe",bamboo.CLUMPS[index])
	expect(int(bag().get(bamboo.ITEM,0))==bamboo.YIELD*3,"The traveller walks to the clumps and collects enough bamboo to build a tea table")
	travel(World.REGIONS.exit_cell(World.Fox.REGION),Tea.MAOKONG)
	travel(gate,"home")
	if failed:return
	expect(World.Fox.visible_clues(World,world.state,person()).is_empty(),"The coast map stays clear until the companion searches")
	actions+=1
	var hint:=world.act(tok,"fox-journey-hint","fox_hint",World.Fox.SITE)
	expect(hint.ok and World.Fox.visible_clues(World,world.state,person()).has(World.SEAWEED_CELL),
		"The companion shows a usable shore clue anywhere on the home map")
	var previous:=int(bag().get("seaweed",0))
	act(World.SEAWEED_POINT,World.SEAWEED_CELL)
	expect(int(bag().get("seaweed",0))==previous+1
		and not World.Fox.visible_clues(World,world.state,person()).has(World.SEAWEED_CELL),"Following the clue gives seaweed and removes its marker")
	expect(reload("fox and first seashore haul"),"The fox and shore gather survive reload")
	expect(int(bag().get(bamboo.ITEM,0))==bamboo.YIELD*3,"The harvest survives the return to Wang'an and reload")
	var table:=World.INDUSTRY.BAMBOO_TEA_TABLE
	gather_for_dock("wood","tree","axe",int(World.BUILD[table].wood),3)
	var table_site:=Vector2i(39,37)
	act("build",table_site,table)
	expect(world.state.objects.get(World.key(table_site),{}).get("type")==table and int(bag().get(bamboo.ITEM,0))==0,"The harvested bamboo pays for the built table")
	expect(bool(person().get(World.Fox.FIELD,{}).get("following",false)) and int(person().fox_tracks)==7,
		"The complete trail and companion survive the full trip")

func finish() -> void:
	print("FOX_JOURNEY_TESTS checks=%d failures=%d actions=%d walk_tiles=%d"%[checks,failures,actions,walking])
	quit(int(failures>0))
