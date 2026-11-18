extends "res://tests/test_external_cuddle_server.gd"
const OWNER:="backup-fixture-owner"
const GUEST:="backup-fixture-guest"
func run()->void:
	var port:=int(OS.get_environment("TUAN_BACKUP_QA_PORT"))
	var key:=OS.get_environment("TUAN_BACKUP_QA_KEY")
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("TUAN_BACKUP_QA_EXPECTED")))
	var first:=make_session("RestoredOwner",OWNER)
	if not check(first.join("ws://127.0.0.1:%d"%port,port,"還原屋主",key)==OK,"Join actual restored exported server"):return
	if not check(await wait_for(func():return not first.own_id.is_empty()),"Restored original identity admitted"):return
	var person:Dictionary=first.snapshot.players[first.own_id]
	if not check(JSON.parse_string(JSON.stringify(person.inventory))==expected.inventory and int(person.coins)==int(expected.coins),"Original inventory and coins retained"):return
	if not check(JSON.parse_string(JSON.stringify(person.stories))==expected.stories,"Original personal story retained"):return
	if not check(first.snapshot.objects.get(expected.chest,{}).get("type")=="chest" and int(first.snapshot.objects[expected.chest].get("items",{}).get("wood",0))==3,"Original chest and three stored wood retained"):return
	if not check(first.snapshot.crops.get(expected.plot,{}).get("kind")=="radish","Original planted radish retained"):return
	var second:=make_session("RestoredGuest",GUEST)
	if not check(second.join("ws://127.0.0.1:%d"%port,port,"還原訪客",key)==OK,"Second original profile joins"):return
	if not check(await wait_for(func():return not second.own_id.is_empty()),"Second original identity admitted"):return
	if not check(await wait_for(func():return first.snapshot.players.has(second.own_id)),"Both players see same restored room"):return
	if OS.get_environment("TUAN_BACKUP_QA_MODE")=="reload":
		if not check(first.snapshot.objects.get(expected.new_chair,{}).get("type")=="chair","Post-restore construction survives another restart"):return
		finish(0);return
	var before:int=person.inventory.get("wood",0)
	if not check(await action(first,"build",World.cell(expected.new_chair),"chair"),"Build chair through actual WS action after restore"):return
	if not check(await wait_for(func():return first.snapshot.objects.get(expected.new_chair,{}).get("type")=="chair"),"Restored world accepts persistent new construction"):return
	if not check(int(first.snapshot.players[first.own_id].inventory.wood)==before-6,"Chair consumes original six wood, no free or duplicate build"):return
	if not check(await action(first,"water",World.cell(expected.plot)),"Existing planted crop can still be watered after restore"):return
	if not check(await wait_for(func():return first.snapshot.crops[expected.plot].wet),"Original radish receives real water action"):return
	finish(0)
