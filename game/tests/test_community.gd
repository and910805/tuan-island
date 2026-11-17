extends SceneTree
const World = preload("res://scripts/world.gd")
const Community = preload("res://scripts/community.gd")
var checks := 0
var failures := 0

class FestivalWorld extends World:
	var project_fixture := 0
	func island_project_mask() -> int:
		return project_fixture

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var path := OS.get_environment("TEMP").path_join("community-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	var world := World.new()
	var token := "community-player"
	world.add_player(token, "Player")
	var p: Dictionary = world.state.players[token]
	p.x = 39.5
	p.y = 30.5
	p.inventory.soup = 2
	p.inventory.bread = 1
	world.state.board = true
	world.state.objects["39,31"] = {"type":"chair","owner":token,"items":{}}
	var before := world.state.duplicate(true)
	world.save_path = path.path_join("missing").path_join("world.json")
	expect(not world.act(token,"picnic","picnic",Vector2i(40,29)).ok and world.state == before, "Failed picnic rolls back table, meal and rewards")
	world.save_path = path
	var result := world.act(token,"picnic","picnic",Vector2i(40,29))
	var table := Community.table_cell(world.state)
	expect(result.ok and table == Vector2i(40,31), "Standing player and legacy chair skipped")
	expect(world.blocked(table) and world.protected(table), "Public table collides and cannot be built over")
	expect(not world.can_stand(Vector2(table) + Vector2(0.5,0.5)), "Player cannot stand inside the table")
	expect(world.state.objects["39,31"] == before.objects["39,31"], "Old chair preserved")
	expect(world.act(token,"picnic","picnic",Vector2i(40,29)) == result and not world.act(token,"another","picnic",Vector2i(40,29)).ok and world.state.players[token].inventory.radish_seed == 8, "Existing reward settles once")
	world.move_player(token, Vector2.LEFT, 0.25)
	expect(Community.table_cell(world.state) == table and world.save() and world.load_world(path) and Community.table_cell(world.state) == table, "Table remains fixed through movement and reload")
	expect(not Community.resident_line(world.state,"milu").is_empty() and Community.resident_line(World.new().state,"milu").is_empty(), "Milestone greeting preserves pre-meal fallback")
	p=world.state.players[token]
	p.inventory["trout_hotpot"]=8
	expect(world.act(token,"serve","serve_hotpot",table).ok and p.inventory.trout_hotpot==4,"Serve exactly four cooked portions")
	expect(not world.act(token,"replace","serve_hotpot",table).ok and p.inventory.trout_hotpot==4,"Cannot overwrite portions already on the table")
	var first:=world.act(token,"first","claim_hotpot",table)
	expect(first.ok and world.act(token,"first","claim_hotpot",table)==first and world.state.community.hotpot.portions==3,"Retry removes only one portion")
	expect(not world.act(token,"repeat","claim_hotpot",table).ok,"One portion per member per hotpot")
	expect(world.load_world(path) and world.state.community.hotpot.portions==3,"Leftovers survive reopening the world")
	expect(not world.act(token,"repeat-reopen","claim_hotpot",table).ok,"Reload preserves the claim")
	world.state.players[token].inventory["watermelon_platter"]=4
	expect(world.act(token,"serve-fruit","serve_watermelon",table).ok,"Watermelon can be served beside the remaining hotpot")
	expect(world.act(token,"claim-fruit","claim_watermelon",table).ok and world.state.community.watermelon.portions==3 and world.state.community.hotpot.portions==3,"The same member can take one of each dish")
	expect(world.load_world(path) and not world.act(token,"fruit-repeat","claim_watermelon",table).ok,"Reload preserves the independent watermelon claim")
	for index in range(3):
		var guest:="guest-%d"%index
		world.add_player(guest,guest)
		var late:Dictionary=world.state.players[guest]
		late.x=41.5
		late.y=31.5
		expect(world.act(guest,"claim","claim_hotpot",table).ok and late.inventory.trout_hotpot==1,"A later arrival can claim one portion")
		expect(world.act(guest,"claim-fruit","claim_watermelon",table).ok and late.inventory.watermelon_platter==1,"A later arrival can also take watermelon")
	expect(world.state.community.hotpot.portions==0,"Four different members empty the pot")
	for id in World.LIVESTOCK.ANIMALS:
		var spec:Dictionary=World.LIVESTOCK.ANIMALS[id]
		p=world.state.players[token]
		p.x=spec.cell.x+0.5
		p.y=spec.cell.y+1.5
		p.inventory["feed"]=1
		expect(world.act(token,"feed-"+id,"livestock_feed",spec.cell,id).ok and p.inventory.feed==0,"Feed one animal")
		expect(not world.act(token,"early-"+id,"livestock_collect",spec.cell,id).ok,"Cannot collect before production")
		expect(world.step(World.LIVESTOCK.DAY*int(spec.days),false) and world.state.livestock[id].ready==0,"An empty world does not produce")
		expect(world.step(World.LIVESTOCK.DAY*int(spec.days),true) and world.state.livestock[id].ready==1,"An active world produces after the species interval")
		expect(world.load_world(path) and world.state.livestock[id].ready==1,"Uncollected product survives restart")
		expect(world.act(token,"collect-"+id,"livestock_collect",spec.cell,id).ok and world.state.players[token].inventory.get(spec.item,0)==1,"Collect one animal product")
		expect(not world.act(token,"repeat-"+id,"livestock_collect",spec.cell,id).ok,"No duplicate animal product")
		p=world.state.players[token]
		p.y=spec.cell.y+2.5
		p.inventory["feed"]=1
		p.inventory["wood"]=20
		var collector:=World.LIVESTOCK.collector_cell(id)
		var built:=world.act(token,"box-"+id,"build",collector,"chest")
		expect(built.ok,"Build the regional collector chest for %s (%s)"%[id,built.message])
		expect(world.act(token,"refill-"+id,"livestock_feed",spec.cell,id).ok,"Feed an animal with a collector")
		expect(world.step(World.LIVESTOCK.DAY*int(spec.days),true),"Advance livestock production")
		expect(world.state.livestock[id].ready==0 and world.state.objects.get(World.key(collector),{}).get("items",{}).get(spec.item,0)==1,"The product is in the box only")
		expect(not world.act(token,"collect-from-pen-"+id,"livestock_collect",spec.cell,id).ok,"Cannot claim the same product from the pen")
		expect(world.load_world(path),"Reload collector contents")
		expect(world.act(token,"retrieve-"+id,"withdraw",collector,spec.item).ok and world.state.players[token].inventory.get(spec.item,0)==2,"Withdraw one stored product after reload")
	world.state.erase("community")
	for cell in Community.CANDIDATES:
		world.state.ground[World.key(cell)] = {"type":"path","owner":token,"items":{}}
	expect(world.save() and world.load_world(path) and Community.table_cell(world.state) == Community.NO_CELL and world.state.picnic, "Occupied legacy plaza keeps completed picnic and existing paths")
	world.state.ground.erase("39,30")
	world.state.erase("community")
	expect(world.save() and world.load_world(path) and Community.table_cell(world.state) == Vector2i(39,30), "Legacy picnic gets a free reserved table spot")
	world.state.community.table = "41,31"
	expect(not Community.valid(world.state), "Unexpected table location rejected")
	var shared:=World.new()
	for actor in ["first","second"]:
		shared.add_player(actor,actor)
		shared.state.players[actor].x=40.5
		shared.state.players[actor].y=30.5
	shared.save_path=path+".fund"
	var board:=Vector2i(40,29)
	var gift:=shared.act("first","gift","fund_donate",board,"50")
	expect(gift.ok and shared.act("first","gift","fund_donate",board,"50")==gift and shared.state.public_fund.balance==50,"Donation replay charges once")
	expect(shared.act("second","gift","fund_donate",board,"25").ok,"Another member contributes")
	expect(not shared.act("first","insufficient","fund_bridge",board).ok,"Insufficient funds cannot partially spend")
	expect(not shared.act("first","take","fund_withdraw",board,"50").ok and shared.state.players.first.coins==70,"The fund cannot be withdrawn into a wallet")
	shared.state.donations={"wood":30,"stone":5}
	expect(shared.act("second","build-bridge","fund_bridge",board).ok and shared.state.board and shared.state.public_fund.balance==35,"Fund pays only the remaining five stones")
	expect(shared.load_world(shared.save_path) and not shared.recovered_from_backup,"Primary fund save reopens")
	var fund:Dictionary=shared.state.get("public_fund",{})
	var gifts:Dictionary=fund.get("contributors",{})
	expect(int(fund.get("balance",0))==35 and gifts.size()==2 and int(gifts.get("first",0))==50 and int(gifts.get("second",0))==25,"Fund survives reopening: "+str(fund))
	expect(not shared.act("first","again","fund_bridge",board).ok and shared.state.public_fund.balance==35,"Bridge payment cannot settle twice")
	for file in [path+".fund",path+".fund.bak"]:DirAccess.remove_absolute(file)
	check_festival(path+".festival")
	for file in [path,path+".bak"]:
		DirAccess.remove_absolute(file)
	print("COMMUNITY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

func check_festival(path:String) -> void:
	var world:=FestivalWorld.new()
	world.save_path=path
	world.add_player("host","Host")
	world.add_player("guest","Guest")
	var host:Dictionary=world.state.players.host
	host.x=40.5
	host.y=30.5
	host.inventory.soup=2
	host.inventory.bread=1
	host.inventory.trout_hotpot=4
	world.state.board=true
	var board:=Vector2i(40,29)
	expect(world.act("host","picnic","picnic",board).ok,"Festival fixture establishes a real picnic")
	world.state.dock_stage=2
	expect(not world.act("host","festival-missing","festival_story_open",board).ok,"Incomplete festival refuses opening")
	world.project_fixture=World.ISLAND_NOTES.project_mask()
	expect(not world.act("host","festival-no-food","festival_story_open",board).ok,"Six projects alone cannot open the festival")
	var table:=Community.table_cell(world.state)
	expect(world.act("host","serving","serve_hotpot",table).ok,"Festival fixture serves an actual shared dish")
	expect(not world.act("host","festival-no-lamps","festival_story_open",board).ok,"A shared dish alone does not meet the lighting condition")
	for tile in [Vector2i(38,30),Vector2i(41,31)]:
		world.state.objects[World.key(tile)]={"type":"lamp","owner":"host","items":{}}
	world.state.dock_stage=1
	expect(not world.act("host","festival-no-boat","festival_story_open",board).ok,"An unfinished boat blocks opening even when all other conditions are met")
	world.state.dock_stage=2
	var before_opening:=World.ISLAND_STORY_RECAP.marker(world.state)
	expect(world.act("host","read-pier","ferry_news_read",Vector2i.ZERO,str(before_opening)).ok,"Host acknowledges the current dock recap")
	expect(world.act("host","festival-open","festival_story_open",board).ok,"All conditions allow opening")
	var reopened:=World.new()
	expect(reopened.load_world(path) and reopened.festival_story_view().opened,"Festival memory stays open after reload")
	var host_seen:=int(reopened.state.players.host.get("ferry_recap_seen",-1))
	var host_recap:=World.ISLAND_STORY_RECAP.build(reopened.state,host_seen)
	var guest_recap:=World.ISLAND_STORY_RECAP.build(reopened.state)
	expect(host_seen==before_opening and host_recap.has_news and host_recap.entries.filter(func(entry):return entry.new).size()==1,"Returning host sees only the opening as new")
	expect(guest_recap.entries.filter(func(entry):return entry.new).size()>1,"The guest retains their own unread dock history")
	expect(not reopened.act("host","read-stale","ferry_news_read",Vector2i.ZERO,str(before_opening)).ok,"A stale acknowledgment cannot mark the unseen opening")
	expect(reopened.act("host","read-opening","ferry_news_read",Vector2i.ZERO,str(host_recap.marker)).ok,"The host can acknowledge the current opening")
	expect(reopened.load_world(path) and not World.ISLAND_STORY_RECAP.build(reopened.state,reopened.state.players.host.ferry_recap_seen).has_news,"Acknowledgment survives restart")
	expect(not reopened.state.players.guest.has("ferry_recap_seen"),"The host does not acknowledge anything for other players")
	reopened.state.players.guest.x=40.5
	reopened.state.players.guest.y=30.5
	expect(not reopened.act("guest","festival-repeat","festival_story_open",board).ok,"Other players cannot repeat the opening")
	expect(reopened.state.community.hotpot.portions==4,"Opening and replay leave servings available to guests")
	var guest:Dictionary=reopened.state.players.guest
	guest.x=42.5
	guest.y=29.5
	guest.inventory.radish=2
	expect(not reopened.act("guest","milu-old","quest",World.Village.NPCS.milu.cell,"milu:0").ok,"Old resident position no longer accepts post-opening requests")
	expect(reopened.act("guest","milu-party","quest",World.Village.resident_cell(reopened.state,"milu"),"milu:0").ok,"Milu accepts quest delivery by the festival tree")
	for file in [path,path+".bak"]:DirAccess.remove_absolute(file)
