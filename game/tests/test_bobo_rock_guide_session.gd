extends "res://tests/test_bobo_cart_unlock_session.gd"
## Two loopback WebSocket clients. The fixture places one player near Bobo with the requisite
## friendship. The refused and successful hand-ins, private snapshots, and reload use Session.

const RockGuide=preload("res://scripts/bobo_rock_guide.gd")
const STONE_GOAL:="bobo:1::"
const STONE_DISPLAY:="keepsake_bobo_kit"

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("bobo-rock-guide-net-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"Isolated save folder"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"Create the resident fixture"):return false
	var port:=start_server()
	if not expect(port>0,"Start loopback WebSocket server"):return false
	server.world.state.players[REPAIRER].inventory.stone=7
	repairer=await join("island builder",REPAIRER,port)
	guest=await join("neighbor",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Two residents joined"):return false
	expect(not RockGuide.available(repairer.session.snapshot) and not RockGuide.available(guest.session.snapshot),"Neither resident has the guide initially")
	var denied:=await act(repairer,Goals.ACTION,bobo_cell,STONE_GOAL)
	expect(denied.replied and not denied.ok and int(repairer.bag().get("stone",0))==7,"Seven stones are refused without a debit")
	expect(not RockGuide.available(repairer.session.snapshot),"An unsuccessful hand-in does not unlock the guide")
	server.world.state.players[REPAIRER].inventory.stone=8
	var earned:=await act(repairer,Goals.ACTION,bobo_cell,STONE_GOAL)
	expect(earned.replied and earned.ok,"The host accepts the eight stones")
	expect(await wait_until(func():return RockGuide.available(repairer.session.snapshot),4.0),"The guide unlock reaches the owner")
	expect(int(repairer.bag().get("stone",0))==0 and int(repairer.bag().get(STONE_DISPLAY,0))==1,"Eight stones are paid and the original display is granted once")
	expect(not RockGuide.available(guest.session.snapshot),"The guide remains locked for the neighbor")
	for person:Dictionary in guest.session.snapshot.get("players",{}).values():
		expect(not person.has(Goals.RECORD_KEY),"Public players contain no private relationship progress")
	var repeated:=await act(repairer,Goals.ACTION,bobo_cell,STONE_GOAL)
	expect(repeated.replied and not repeated.ok and int(repairer.bag().get(STONE_DISPLAY,0))==1,"The same goal cannot grant a second display")
	leave(repairer)
	leave(guest)
	await pause(0.2)
	if not expect(await stop_server(),"Save and stop the server"):return false
	port=start_server()
	if not expect(port>0,"Start again from the same save"):return false
	repairer=await join("island builder",REPAIRER,port)
	guest=await join("neighbor",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Both residents rejoined"):return false
	expect(await wait_until(func():return RockGuide.available(repairer.session.snapshot),4.0),"Guide access persists after restart")
	expect(not RockGuide.available(guest.session.snapshot),"The neighbor is still locked after restart")
	return true

func run()->void:
	var complete:=await scenario()
	expect(complete,"Reach the end of the same-host WebSocket scenario")
	await teardown()
	if complete and failures==0:expect(remove_folder(),"Remove the isolated test save")
	finished=true
	print("BOBO_ROCK_GUIDE_SESSION checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
