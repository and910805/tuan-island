extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Tea=World.TEA_CERAMICS
const ALPHA="tea-test-alpha"
const BETA="tea-test-beta"
var world:=World.new()
var checks:=0
var failures:=0
var seq:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func act(action:String,region:String,cell:Vector2i,extra:String="",actor:String=ALPHA,distance:int=1) -> Dictionary:
	var player:Dictionary=world.state.players[actor]
	player.region=region
	player.x=cell.x+0.5+distance
	player.y=cell.y+0.5
	if region in World.TRANSIT.ROUTE:player.travel_book.visited[region]=true
	seq+=1
	return world.act(actor,"tea-test-%d"%seq,action,cell,extra)

func bag() -> Dictionary:
	return world.state.players[ALPHA].inventory

func own() -> Dictionary:
	return Tea.own_record(world.state,ALPHA)

func valid(state:Dictionary) -> bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize() -> void:
	var path:=OS.get_environment("TEMP").path_join("tea-ceramics-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	world.save_path=path
	world.add_player(ALPHA,"Alpha")
	world.add_player(BETA,"Beta")
	var leaf:Vector2i=Tea.TEA_NODES[0]
	expect(not act("tea_intro","home",Tea.RECEIVER).ok,"Chapter one completion required")
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	expect(not act("tea_potter",Tea.YINGGE,Tea.POTTER).ok,"Introduction required before pottery")
	expect(not act("tea_intro","home",Tea.RECEIVER,"",ALPHA,4).ok,"Introduction proximity enforced")
	expect(act("tea_intro","home",Tea.RECEIVER).ok,"Read invitation")
	expect(not act("tea_potter",Tea.MAOKONG,Tea.POTTER).ok,"Same coordinate in wrong region is rejected")
	expect(act("tea_potter",Tea.YINGGE,Tea.POTTER).ok and bag().clay==2,"First clay grant is two units")
	expect(not act("tea_potter",Tea.YINGGE,Tea.POTTER).ok,"Free clay cannot be claimed twice")
	expect(act("tea_fire",Tea.YINGGE,Tea.KILN).ok and bag().clay==0,"Start kiln with two clay")
	expect(not act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok,"Cannot take uncured jar")
	expect(world.step(Tea.KILN_SECONDS,true) and act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok and bag().tea_jar==1,"Take first ceramic jar when kiln is ready")
	var stone:=int(bag().stone)
	expect(act("tea_clay",Tea.YINGGE,Tea.CLAY).ok and bag().clay==1 and bag().stone==stone-2,"Replacement clay costs two stone")
	expect(not act("tea_clay",Tea.YINGGE,Tea.CLAY).ok,"Clay exchange has a cooldown")

	expect(act("tea_pick",Tea.MAOKONG,leaf).ok and bag().tea_leaf==2,"Harvest the first two leaves")
	expect(not act("tea_pick",Tea.MAOKONG,leaf).ok,"Tea plant cooldown cannot be bypassed")
	expect(not act("tea_roast",Tea.MAOKONG,Tea.ROASTER,"invalid").ok,"Invalid roast style rejected")
	expect(act("tea_roast",Tea.MAOKONG,Tea.ROASTER,"light").ok and not act("tea_take",Tea.MAOKONG,Tea.ROASTER).ok,"Light roast cannot be collected early")
	expect(world.step(Tea.ROAST_SECONDS.light,true) and act("tea_take",Tea.MAOKONG,Tea.ROASTER).ok,"Collect light roast")
	expect(act("tea_pack",Tea.MAOKONG,Tea.PACKER,"light:jar").ok and bag().tea_jar==0 and not own().packed.reused_jar,"First packet uses the kiln jar")
	expect(act("tea_ship",Tea.MAOKONG,Tea.PACKER).ok,"Ship first tea packet")
	expect(not act("tea_sell","home",Tea.RECEIVER).ok,"No payment before delivery")
	expect(world.step(Tea.SHIPPING_SECONDS,true),"Outbound shipment reaches deadline")
	expect(act("tea_intro","home",Tea.RECEIVER,"",BETA).ok and not act("tea_sell","home",Tea.RECEIVER,"",BETA).ok,"Second player cannot settle first player's freight")
	var coins:=int(world.state.players[ALPHA].coins)
	var receipt_id:="first-packet-sale"
	world.state.players[ALPHA].coins=Tea.LIMIT
	expect(not world.act(ALPHA,"overflow","tea_sell",Tea.RECEIVER).ok and not own().outbound.is_empty(),"Coin overflow keeps the delivery pending")
	world.state.players[ALPHA].coins=coins
	var before:=world.state.duplicate(true)
	world.save_path=path.path_join("missing").path_join("world.json")
	expect(not world.act(ALPHA,receipt_id,"tea_sell",Tea.RECEIVER).ok and world.state==before,"Failed save restores payment and shipment")
	world.save_path=path
	var paid:=world.act(ALPHA,receipt_id,"tea_sell",Tea.RECEIVER)
	expect(paid.ok and world.act(ALPHA,receipt_id,"tea_sell",Tea.RECEIVER)==paid and own().empties==1,"Retried sale receipt cannot issue a duplicate jar")
	expect(int(world.state.players[ALPHA].coins)==coins+Tea.price_for("light","jar") and not act("tea_sell","home",Tea.RECEIVER).ok,"First payment occurs exactly once")
	expect(not act("tea_auto","home",Tea.RECEIVER,"on").ok and act("tea_return","home",Tea.RECEIVER).ok,"Manually dispatch first return before automation")
	expect(not act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok,"Return cannot be claimed before arrival")
	expect(world.step(Tea.RETURN_SECONDS,true) and act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and bag().tea_returned_jar==1,"Reclaim exactly the returned jar")
	expect(act("tea_auto","home",Tea.RECEIVER,"on").ok,"First completed return unlocks automatic returns")

	expect(act("tea_pick",Tea.MAOKONG,leaf).ok and act("tea_roast",Tea.MAOKONG,Tea.ROASTER,"deep").ok,"Start second batch with deep roast")
	expect(world.step(Tea.ROAST_SECONDS.deep,true) and act("tea_take",Tea.MAOKONG,Tea.ROASTER).ok,"Take deep roast")
	expect(act("tea_pack",Tea.MAOKONG,Tea.PACKER,"deep:jar").ok and own().packed.reused_jar and bag().tea_returned_jar==0,"Second batch uses the returned jar")
	expect(act("tea_ship",Tea.MAOKONG,Tea.PACKER).ok and world.step(Tea.SHIPPING_SECONDS,true),"Second batch ships")
	expect(act("tea_sell","home",Tea.RECEIVER).ok and own().reuse_count==1 and own().returning.count==1 and own().empties==0,"Second sale counts reuse and starts auto return")
	expect(Tea.price_for("deep","jar")>Tea.price_for("light","jar") and Tea.price_for("deep","jar")>Tea.price_for("deep","fiber"),"Roast and reusable packaging affect the price")
	var reopened:=World.new()
	expect(reopened.load_world(path) and not reopened.recovered_from_backup and reopened.state.version==26,"Reload v16 with automatic return in flight")
	world=reopened
	expect(own().reuse_count==1 and not act("tea_sell","home",Tea.RECEIVER).ok,"Reload preserves reuse and prevents duplicate settlement")
	expect(world.step(Tea.RETURN_SECONDS,true) and act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and not act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok,"Automatic return can be claimed only once")

	expect(act("tea_pick",Tea.MAOKONG,leaf).ok and act("tea_roast",Tea.MAOKONG,Tea.ROASTER,"light").ok,"Start fiber comparison batch")
	expect(world.step(Tea.ROAST_SECONDS.light,true) and act("tea_take",Tea.MAOKONG,Tea.ROASTER).ok,"Take roast for fiber packaging")
	var fiber:=int(bag().fiber)
	expect(act("tea_pack",Tea.MAOKONG,Tea.PACKER,"light:fiber").ok and bag().fiber==fiber-1 and bag().tea_worn_jar==1,"Fiber package consumes no jar")
	expect(act("tea_ship",Tea.MAOKONG,Tea.PACKER).ok and world.step(Tea.SHIPPING_SECONDS,true),"Fiber packet reaches the receiver")
	coins=int(world.state.players[ALPHA].coins)
	expect(act("tea_sell","home",Tea.RECEIVER).ok and int(world.state.players[ALPHA].coins)==coins+Tea.price_for("light","fiber") and own().returning.is_empty() and own().empties==0,"Fiber earns the lower price and sends no empty container")
	expect(act("tea_auto","home",Tea.RECEIVER,"off").ok and not own().auto,"Automatic return can be disabled")

	bag().clay=3 # FIXTURE: test kiln job boundaries.
	expect(not act("tea_fire_pot",Tea.YINGGE,Tea.KILN).ok and bag().clay==3,"Flower pot requires four clay")
	bag().clay=4
	expect(act("tea_fire_pot",Tea.YINGGE,Tea.KILN).ok and bag().clay==0,"Start one flower pot and debit four clay")
	expect(not act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok and not act("tea_fire",Tea.YINGGE,Tea.KILN).ok,"Pot reserves kiln until ready and collected")
	var pot_reload:=World.new()
	expect(pot_reload.load_world(path) and Tea.own_record(pot_reload.state,ALPHA).kiln.get("kind")=="flower_pot","Active flower pot survives save load")
	expect(world.step(60.0,true) and act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok and bag().flower_pot==1,"Claim exactly one pot after 60 seconds")
	expect(not act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok,"Cannot claim the flower pot twice")
	var pot_cell:=Vector2i(41,35)
	var pot_destination:=Vector2i(41,36)
	expect(act("build","home",pot_cell,"flower_pot").ok and bag().get("flower_pot",0)==0,"Place the fired pot from inventory")
	expect(world.blocked(pot_cell),"Placed pot has furniture collision")
	expect(not act("remove","home",pot_cell,"",BETA).ok,"Another player cannot remove the pot")
	expect(act("move_object","home",pot_cell,World.key(pot_destination)).ok and not world.state.objects.has(World.key(pot_cell)),"Owner moves the pot without consuming another")
	expect(pot_reload.load_world(path) and pot_reload.state.objects.get(World.key(pot_destination),{}).get("type")=="flower_pot","Placed pot persists in the primary save")
	expect(act("remove","home",pot_destination).ok and bag().get("flower_pot",0)==1,"Dismantling returns the same ceramic pot")

	var malformed:=world.state.duplicate(true)
	malformed.tea_ceramics.players[ALPHA].returning={"count":-1,"ready":world.state.time}
	expect(not valid(malformed),"Schema rejects a negative return batch")
	var legacy:=world.state.duplicate(true)
	legacy.version=14;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	legacy.erase("tea_ceramics")
	for region in [Tea.MAOKONG,Tea.YINGGE]:legacy.regions.erase(region)
	legacy.players[ALPHA].region="home"
	expect(valid(legacy) and legacy.version==26 and legacy.tea_ceramics==Tea.fresh() and legacy.regions.has(Tea.MAOKONG),"v14 saves migrate with both regions and empty progress")
	var session:=Session.new()
	session.world=world
	session.peers[1]=BETA
	expect(not session.public_state("home").has("tea_ceramics"),"No raw tea records in public snapshots")
	session._send_snapshot(1)
	expect(session.snapshot.get("tea_ceramics",{})=={"own_record":Tea.own_record(world.state,BETA)},"Recipient sees only own tea record")
	session.free()
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("TEA_CERAMICS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
