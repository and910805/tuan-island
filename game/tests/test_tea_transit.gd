extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=World.TRANSIT
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func near(w:World,cell:Vector2i)->void:
	w.state.players.alpha.x=cell.x+0.5
	w.state.players.alpha.y=cell.y+0.5
func _initialize()->void:
	var w:=World.new()
	var path:=OS.get_environment("TEMP").path_join("tea-transit-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	w.save_path=path
	w.add_player("alpha","旅行者")
	w.state.picnic=true
	var person:Dictionary=w.state.players.alpha
	person.region="ruifang"
	person.travel_book.visited.ruifang=true
	near(w,Vector2i(14,19))
	check(not w.act("alpha","locked","transit",Vector2i(14,19),"maokong").ok,"Tea branch requires first chapter, not only picnic flag")
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state.board=true
	check(w.act("alpha","tea","transit",Vector2i(14,19),"maokong").ok,"Rail point offers Taipei combined transfer to Maokong")
	check(w.player_region("alpha")=="maokong" and w.state.players.alpha.travel_book.visited.maokong,"Maokong visit recorded")
	near(w,Vector2i(25,23))
	check(not w.act("alpha","distant","transit",Vector2i(12,25),"yingge").ok,"Cannot depart from tea garden instead of transfer point")
	near(w,Vector2i(12,25))
	check(w.act("alpha","pottery","transit",Vector2i(12,25),"yingge").ok,"Workshop transfer reaches Yingge")
	check(Transit.intermediate("jinguashi","yingge")==["jiufen","ruifang","maokong"],"Branch graph never treats pottery as a stop beyond the mine")
	check(Transit.intermediate("yingge","toucheng")==["maokong","ruifang"],"Reverse route follows same branch")
	check(Transit.intermediate("missing","maokong").is_empty(),"Unknown route has no fabricated itinerary")
	for region in Transit.TEA_STOPS:
		w.switch_region(region)
		check(w.blocked(Vector2i(7,20)) and w.blocked(Vector2i(38,20)) and not w.blocked(Vector2i(13,25)),"Mountain boundary blocks walking without pretending it is water "+region)
		check(w.blocked(Vector2i(19,17)) and w.blocked(Vector2i(23,20)) and not w.blocked(Vector2i(23,21)),"Building base and production furniture collide, approach stays open "+region)
		w.switch_region("home")
		check(World.REGIONS.land(Vector2i(13,25),region) and not World.REGIONS.water(Vector2i(13,25),region),"Safe workshop arrival "+region)
		check(World.REGIONS.protected(Vector2i(23,20),region),"Public production station protected "+region)
		check(World.REGIONS.resource(Vector2i(25,23),region)=="","No random forest resource replaces tea node "+region)
	var reopened:=World.new()
	check(reopened.load_world(path) and reopened.player_region("alpha")=="yingge" and reopened.state.players.alpha.travel_book.visited.maokong,"Both branches survive reload")
	w.state.players.alpha.region="home"
	var ferry:Vector2i=Transit.STATIONS.home.cell
	near(w,ferry)
	check(not w.act("alpha","boat-before","transit",ferry,Transit.Bamboo.REGION).ok,"Unvisited bamboo route requires the boat")
	var board:=Vector2i(40,29)
	near(w,board)
	check(not w.act("alpha","dock-locked","dock_repair",board,"0").ok,"Dock waits for the public garden")
	var flower_fixture:=ProjectSettings.globalize_path("res://").path_join("../work/salt/network/runs/20261114T054823Z/world-final.json")
	check(w.load_world(flower_fixture),"Load the completed public garden fixture")
	w.save_path=path
	w.add_player("alpha","旅行者")
	near(w,board)
	check(not w.act("alpha","dock-short","dock_repair",board,"0").ok,"Missing materials refuse the dock repair")
	w.state.players.alpha.inventory.merge({"plank":20,"stone":8,"fiber":10,"copper_joint":2},true)
	check(w.act("alpha","dock-built","dock_repair",board,"0").ok and int(w.state.dock_stage)==1,"First delivery repairs the dock")
	check(not w.act("alpha","dock-stale","dock_repair",board,"0").ok,"Stale stage cannot debit the boat materials")
	check(w.act("alpha","boat-built","dock_repair",board,"1").ok and int(w.state.dock_stage)==2,"Second delivery unlocks the boat")
	var bag:Dictionary=w.state.players.alpha.inventory
	check(bag.plank==0 and bag.stone==0 and bag.fiber==0 and bag.copper_joint==0,"Both projects debit the exact materials")
	check(reopened.load_world(path) and not reopened.recovered_from_backup and int(reopened.state.dock_stage)==2,"Completed project loads from the primary save before first departure")
	w=reopened
	for destination:String in [Transit.Bamboo.REGION,Transit.Springs.REGION]:
		near(w,ferry)
		var routes:=Transit.route_options(w.state,"alpha","ferry")
		check(routes.any(func(row):return row.region==destination and row.mode=="合作小船"),"Repaired boat advertises "+destination)
		check(w.act("alpha","boat-out-"+destination,"transit",ferry,destination).ok,"Boat reaches "+destination)
		check(w.state.players.alpha.get("outlying_boat_arrival",false),"Server records the actual outbound boat arrival")
		w.switch_region(destination)
		check(w.can_stand(Vector2(w.state.players.alpha.x,w.state.players.alpha.y)),"Boat arrival is walkable")
		w.switch_region("home")
		var station:Vector2i=Transit.STATIONS[destination].cell
		var id:="bamboo_tea_rest" if destination==Transit.Bamboo.REGION else "springs_footbath"
		check(not w.act("alpha","wrong-counter-"+id,"outlying_deliver",station+Vector2i.RIGHT,id).ok,"A different tile cannot take delivery")
		near(w,station)
		check(not w.act("alpha","missing-supplies-"+id,"outlying_deliver",station,id).ok,"The local commission requires materials")
		var definition:Dictionary=World.OUTLYING_COMMISSIONS.DEFS[id]
		w.state.players.alpha.inventory.merge(definition.needs,true)
		var coins_before:=int(w.state.players.alpha.coins)
		var receipt:Dictionary=w.act("alpha","deliver-"+id,"outlying_deliver",station,id)
		check(receipt.ok,"The local station accepts its commission")
		check(int(w.state.players.alpha.coins)==coins_before+definition.reward_coins,"The exact reward is given")
		for item:String in definition.needs:
			check(int(w.state.players.alpha.inventory[item])==0,"Delivery consumes "+item)
		check(w.act("alpha","deliver-"+id,"outlying_deliver",station,id)==receipt and int(w.state.players.alpha.coins)==coins_before+definition.reward_coins,"Retry returns the same receipt without a second reward")
		check(w.load_world(path) and World.OUTLYING_COMMISSIONS.done(w.state,"alpha",id),"Completion persists in the primary save")
		check(not w.act("alpha","repeat-"+id,"outlying_deliver",station,id).ok,"The reloaded world refuses duplicate delivery")
		check(w.act("alpha","boat-home-"+destination,"transit",station,"home").ok,"Return boat reaches the ferry")
		check(not w.state.players.alpha.has("outlying_boat_arrival"),"Returning home clears the outbound arrival context")
	check(reopened.load_world(path) and int(reopened.state.dock_stage)==2,"Boat unlock survives reload")
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("TEA_TRANSIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
