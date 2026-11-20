extends "res://tests/test_bobo_cart_unlock_session.gd"
## A real loopback WebSocket host and two clients verify the tea memory is private and durable.

const Gathering=preload("res://scripts/chacha_tea_gathering.gd")
const TEA_REGION:=World.TEA_CERAMICS.MAOKONG
const TEA_NPC:=World.TEA_CERAMICS.TEA_NPC

func seed_world(path:String)->bool:
	var island:=World.new()
	for token:String in [REPAIRER,GUEST]:
		island.add_player(token,token)
		var person:Dictionary=island.state.players[token]
		person.region=TEA_REGION
		person.x=TEA_NPC.x+0.5
		person.y=TEA_NPC.y+1.5
		person.bonds={"chacha":{"points":14,"talk_day":-1,"gift_day":-1}}
	island.active_tokens.clear()
	island.save_path=path
	return island.save()

func topics(client:Client)->String:
	return str(client.session.snapshot.get("resident_goals",{}).get("chacha",{}).get("3",{}).get("topics",""))

func check_orders()->void:
	var names:Dictionary=World.NAMES
	for order:String in ["012","021","102","120","201","210"]:
		var person:Dictionary={"bonds":{"chacha":{"points":14,"talk_day":-1,"gift_day":-1}}}
		var result:=Goals.apply(person,{},PackedStringArray(["chacha","3","",order]),names)
		expect(result.ok and person.get(Goals.TEA_TOPICS_KEY,"")==order and Goals.done(person,"chacha").get(3,null)=="","Every permutation is equally accepted: "+order)
	for order:String in ["","002","013","a12"]:
		var person:Dictionary={"bonds":{"chacha":{"points":14,"talk_day":-1,"gift_day":-1}}}
		var result:=Goals.apply(person,{},PackedStringArray(["chacha","3","",order]),names)
		expect(not result.ok and not person.has(Goals.TEA_TOPICS_KEY),"Invalid order leaves no record: "+order)

func check_save()->void:
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(Schema.validate(saved,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Saved topic records pass the schema")
	var old:=saved.duplicate(true)
	old.players[REPAIRER].erase(Goals.TEA_TOPICS_KEY)
	expect(Schema.validate(old,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A completed older save can omit the topic order")
	var bad:=saved.duplicate(true)
	bad.players[REPAIRER][Goals.TEA_TOPICS_KEY]="200"
	expect(not Schema.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Malformed saved orders are rejected")
	bad.players[REPAIRER][Goals.TEA_TOPICS_KEY]="201"
	bad.players[REPAIRER].erase(Goals.RECORD_KEY)
	expect(not Schema.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"An order cannot be stored without completing the story")

func scenario()->bool:
	check_orders()
	folder=OS.get_environment("TEMP").path_join("chacha-gathering-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"Isolated save folder"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"Create the tea house fixture"):return false
	var port:=start_server()
	if not expect(port>0,"Start the loopback server"):return false
	repairer=await join("tea host",REPAIRER,port)
	guest=await join("neighbor",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Both players joined"):return false
	var accepted:=await act(repairer,Goals.ACTION,TEA_NPC,"chacha:3::201")
	expect(accepted.replied and accepted.ok,"First player reports the actual tea topic order")
	expect(await wait_until(func():return topics(repairer)=="201",4.0),"First player receives the chosen order")
	expect(topics(guest).is_empty() and not Gathering.available(guest.session.snapshot),"Second player sees no first-player tea memory")
	var accepted_guest:=await act(guest,Goals.ACTION,TEA_NPC,"chacha:3::120")
	expect(accepted_guest.replied and accepted_guest.ok,"Second player may finish independently")
	expect(await wait_until(func():return topics(guest)=="120",4.0) and topics(repairer)=="201","Private tea topic orders remain distinct")
	for client:Client in [repairer,guest]:
		for person:Dictionary in client.session.snapshot.players.values():
			expect(not person.has(Goals.TEA_TOPICS_KEY),"No private topic order in the public player records")
	var replay:=await act(repairer,Goals.ACTION,TEA_NPC,"chacha:3::012")
	expect(replay.replied and not replay.ok and topics(repairer)=="201","Re-reporting cannot replace the chosen order")
	leave(repairer)
	leave(guest)
	await pause(0.2)
	if not expect(await stop_server(),"Save and stop the server"):return false
	check_save()
	port=start_server()
	if not expect(port>0,"Start again from the same save"):return false
	repairer=await join("tea host",REPAIRER,port)
	guest=await join("neighbor",GUEST,port)
	expect(joined(repairer) and joined(guest) and topics(repairer)=="201" and topics(guest)=="120","Restart restores each player's own order")
	return true

func run()->void:
	var complete:=await scenario()
	expect(complete,"Reach the end of the loopback scenario")
	await teardown()
	if complete and failures==0:expect(remove_folder(),"Remove the isolated fixture")
	finished=true
	print("CHACHA_TEA_GATHERING_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
