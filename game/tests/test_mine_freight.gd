extends SceneTree
const World=preload("res://scripts/world.gd")
const Freight=World.MINE_FREIGHT
const Actor="freight-actor"
const Other="freight-other"
const BOX:="41,35"
var checks:=0
var failures:=0

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func put(world:World,actor:String,region:String,cell:Vector2i)->void:
	var person:Dictionary=world.state.players[actor]
	person.region=region
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("freight-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var w:=World.new()
	w.save_path=path
	for actor in [Actor,Other]:
		w.add_player(actor,actor)
		put(w,actor,"mine_4",Freight.LOAD_CELL)
	w.state.mine_depths={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	w.state.players[Actor].inventory.copper_ore=40
	w.state.players[Actor].inventory.gold_ore=5
	w.state.objects[BOX]={"type":"private_chest","owner":Actor,"items":{}}
	w.state.objects["42,35"]={"type":"private_chest","owner":Other,"items":{}}
	expect(not w.act(Actor,"bad-load","freight_load",Freight.LOAD_CELL,"gold_ore:+2").ok,"Noncanonical quantity refused")
	var first:=w.act(Actor,"load","freight_load",Freight.LOAD_CELL,"copper_ore:32")
	expect(first.ok and w.act(Actor,"load","freight_load",Freight.LOAD_CELL,"copper_ore:32")==first and w.state.players[Actor].inventory.copper_ore==8,"Load is capped and replay does not debit twice")
	expect(not w.act(Actor,"overflow","freight_load",Freight.LOAD_CELL,"gold_ore:1").ok,"Capacity enforced across items")
	expect(w.act(Actor,"unload","freight_unload",Freight.LOAD_CELL,"copper_ore:2").ok and w.act(Actor,"add","freight_load",Freight.LOAD_CELL,"gold_ore:2").ok,"Draft can unload and add an existing ore ID")
	expect(not w.act(Actor,"foreign","freight_target",Freight.LOAD_CELL,"42,35").ok,"Foreign chest refused")
	expect(w.act(Actor,"target","freight_target",Freight.LOAD_CELL,BOX).ok and Freight.valid_id(w.state.objects[BOX].freight_id),"Binding persists chest ID")
	expect(w.act(Actor,"dispatch","freight_dispatch",Freight.LOAD_CELL).ok and not w.act(Actor,"mutate","freight_unload",Freight.LOAD_CELL,"gold_ore:1").ok,"Dispatch locks manifest")
	expect(w.step(60,false) and w.state.time==0.0 and w.state.mine_freight.jobs[Actor].status=="transit","Idle world does not advance shipping")
	var before:=w.state.duplicate(true)
	w.save_path=path.path_join("missing").path_join("world.json")
	expect(not w.step(60,true) and w.state==before,"Delivery rolls back chest, job and clock on failed write")
	w.save_path=path
	expect(w.step(60,true) and w.state.objects[BOX].items=={"copper_ore":30,"gold_ore":2} and w.state.mine_freight.jobs[Actor].status=="delivered","Whole manifest delivered exactly once")
	var reopened:=World.new()
	expect(reopened.load_world(path) and reopened.step(60,true) and reopened.state.objects[BOX].items.copper_ore==30,"Restart does not duplicate delivery")
	expect(reopened.act(Actor,"new","freight_load",Freight.LOAD_CELL,"copper_ore:4").ok and reopened.state.mine_freight.jobs[Actor].status=="draft","Next load replaces delivered receipt")
	expect(reopened.act(Actor,"retarget","freight_target",Freight.LOAD_CELL,BOX).ok and reopened.act(Actor,"again","freight_dispatch",Freight.LOAD_CELL).ok,"Second consignment")
	reopened.state.objects[BOX]={"type":"private_chest","owner":Actor,"items":{}}
	expect(reopened.step(60,true) and reopened.state.mine_freight.jobs[Actor].status=="held" and reopened.state.objects[BOX].items.is_empty(),"Replacement at same tile cannot inherit cargo")
	expect(reopened.load_world(path) and not reopened.recovered_from_backup and reopened.state.mine_freight.jobs[Actor].status=="held" and int(reopened.state.mine_freight.jobs[Actor].items.copper_ore)==4,"Held cargo reloads from primary save")
	put(reopened,Actor,"home",Freight.CLAIM_CELL)
	put(reopened,Other,"home",Freight.CLAIM_CELL)
	expect(not reopened.act(Other,"steal","freight_claim",Freight.CLAIM_CELL).ok,"Other player cannot claim")
	var bag:Dictionary=reopened.state.players[Actor].inventory
	bag.copper_ore=1000000000
	expect(not reopened.act(Actor,"full","freight_claim",Freight.CLAIM_CELL).ok and reopened.state.mine_freight.jobs[Actor].status=="held","Claim preserves held cargo if whole manifest won't fit")
	bag.copper_ore=6
	var claim:=reopened.act(Actor,"claim","freight_claim",Freight.CLAIM_CELL)
	expect(claim.ok and bag.copper_ore==10 and reopened.act(Actor,"claim","freight_claim",Freight.CLAIM_CELL)==claim and not reopened.act(Actor,"claim-again","freight_claim",Freight.CLAIM_CELL).ok,"Held cargo claimed all at once and not replayable")
	for reason in ["full","moved","owner"]:
		var fixture := World.new()
		fixture.state = reopened.state.duplicate(true)
		var items := {"copper_ore":2,"gold_ore":2}
		var box := {"type":"private_chest","owner":Actor,"freight_id":"a".repeat(32),"items":{}}
		fixture.state.objects[BOX]=box
		fixture.state.mine_freight.jobs[Actor]={"status":"transit","items":items,"target":{"cell":BOX,"id":box.freight_id},"ready":float(fixture.state.time)+1}
		match reason:
			"full":box.items.gold_ore=999999999
			"moved":
				fixture.state.objects["43,35"]=box
				fixture.state.objects.erase(BOX)
			"owner":box.owner=Other
		var original: Dictionary=box.items.duplicate()
		expect(fixture.step(1,true) and fixture.state.mine_freight.jobs[Actor].status=="held" and box.items==original,"Whole load held, no partial credit: " + reason)
	var draft := World.new()
	draft.state=reopened.state.duplicate(true)
	put(draft,Actor,"mine_4",Freight.LOAD_CELL)
	for request in [["freight_load","copper_ore:2"],["freight_target",BOX],["freight_dispatch",""]]:
		var original:=draft.state.duplicate(true)
		draft.save_path=path.path_join("missing").path_join("world.json")
		expect(not draft.act(Actor,"rollback",request[0],Freight.LOAD_CELL,request[1]).ok and draft.state==original,"Action save failure rolls back " + request[0])
		draft.save_path=""
		expect(draft.act(Actor,request[0],request[0],Freight.LOAD_CELL,request[1]).ok,"Valid retry " + request[0])
	var job: Dictionary=draft.state.mine_freight.jobs[Actor]
	job.ready=draft.state.time
	job.status="held"
	put(draft,Actor,"home",Freight.CLAIM_CELL)
	var held:=draft.state.duplicate(true)
	draft.save_path=path.path_join("missing").path_join("world.json")
	expect(not draft.act(Actor,"claim-fail","freight_claim",Freight.CLAIM_CELL).ok and draft.state==held,"Failed claim leaves cargo and backpack unchanged")
	for bad in [["items",{"gold_ore":33}],["items",{"copper_ore":16,"gold_ore":17}],["items",{"wood":1}],["target",{"cell":"80,35","id":"a".repeat(32)}],["target",{"cell":BOX,"id":"invalid"}],["status","lost"],["ready",NAN],["ready",float(draft.state.time)+61.0]]:
		var invalid:=held.duplicate(true)
		invalid.mine_freight.jobs[Actor][bad[0]]=bad[1]
		expect(not Freight.valid(invalid),"Malformed freight field rejected: " + bad[0])
	reopened.state.version=6;reopened.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	reopened.state.erase("flower_nursery")
	reopened.state.regions.erase("tianwei")
	reopened.state.erase("salt_pan")
	reopened.state.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:reopened.state.regions.erase(region)
	for region in World.TRANSIT.LOCAL:reopened.state.regions.erase(region)
	reopened.state.erase("mine_freight")
	expect(reopened.save() and w.load_world(path) and w.state.version==26 and w.state.mine_freight==Freight.fresh() and w.state.players[Actor].inventory.copper_ore==10,"V6 migration preserves inventory with no fabricated freight")
	for file in [path,path+".bak"]:DirAccess.remove_absolute(file)
	print("MINE_FREIGHT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
