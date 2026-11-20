extends SceneTree
const World=preload("res://scripts/world.gd")
const Bobo=World.BOBO_WORKSHOP
var checks:=0
var failures:=0
func expect(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func _initialize()->void:
	var w:=World.new()
	var path:=OS.get_environment("TEMP").path_join("bobo-%d.json"%Time.get_ticks_usec())
	w.save_path=path
	for actor in ["alpha","beta"]:
		w.add_player(actor,actor)
		w.state.players[actor].x=22.5
		w.state.players[actor].y=21.5
	expect(not w.act("alpha","wrong","quest",Bobo.NPC_CELL,"bobo:0").ok,"Wrong region refused")
	for actor in ["alpha","beta"]:w.state.players[actor].region="jinguashi"
	var p:Dictionary=w.state.players.alpha
	p.inventory.merge({"plank":2,"copper_joint":1,"gold_ore":6,"baked_potato":1},true)
	expect(w.act("alpha","first","quest",Bobo.NPC_CELL,"bobo:0").ok and p.stories.bobo==1,"First quest uses actual materials")
	expect(not w.act("alpha","early","quest",Bobo.NPC_CELL,"bobo:1").ok,"Sorting required")
	expect(w.act("alpha","start","bobo_sort_start",Bobo.CELL).ok and p.inventory.gold_ore==3,"Inputs paid")
	expect(not w.act("beta","steal","bobo_sort_claim",Bobo.CELL).ok,"Other actor cannot claim")
	expect(not w.act("alpha","wrong","bobo_sort_answer",Bobo.CELL,"0:small").ok and w.state.bobo_workshop.jobs.alpha.step==0,"Wrong label preserves paid work")
	for i in range(3):
		expect(w.act("alpha","sort-%d"%i,"bobo_sort_answer",Bobo.CELL,"%d:%s"%[i,Bobo.STEPS[i]]).ok,"Correct labelled sort")
		expect(not w.act("alpha","repeat-%d"%i,"bobo_sort_answer",Bobo.CELL,"%d:%s"%[i,Bobo.STEPS[i]]).ok,"Stale step rejected")
	expect(w.load_world(path) and int(w.state.bobo_workshop.jobs.alpha.step)==3,"Unclaimed sample persists")
	var before:=w.state.duplicate(true)
	w.save_path=path.path_join("missing").path_join("world")
	expect(not w.act("alpha","claim","bobo_sort_claim",Bobo.CELL).ok and w.state==before,"Claim save failure rolls back")
	w.save_path=path
	var result:=w.act("alpha","claim","bobo_sort_claim",Bobo.CELL)
	expect(result.ok and w.act("alpha","claim","bobo_sort_claim",Bobo.CELL)==result and w.state.players.alpha.inventory.gold_sample==1,"One claimed sample")
	expect(w.act("alpha","second","quest",Bobo.NPC_CELL,"bobo:1").ok and not w.act("alpha","no-freight","quest",Bobo.NPC_CELL,"bobo:2").ok,"Story requires delivered freight")
	w.state.mine_depths={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	w.state.time=60.0
	w.state.mine_freight.jobs.alpha={"status":"delivered","items":{"stone":1},"target":{"cell":"41,35","id":"a".repeat(32)},"ready":60.0}
	expect(w.act("alpha","third","quest",Bobo.NPC_CELL,"bobo:2").ok,"Delivery unlocks display")
	expect(not w.act("alpha","early-final","quest",Bobo.NPC_CELL,"bobo:3").ok,"Own display required")
	expect(w.act("alpha","display","build",Vector2i(21,21),"ore_display").ok and w.act("alpha","final","quest",Bobo.NPC_CELL,"bobo:3").ok,"Own display and potato complete fourth story")
	expect(w.act("alpha","cancel-start","bobo_sort_start",Bobo.CELL).ok and w.act("alpha","cancel","bobo_sort_cancel",Bobo.CELL).ok and w.state.players.alpha.inventory.gold_ore==3,"Cancellation refunds all inputs")
	w.state.version=7;w.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	w.state.erase("flower_nursery")
	w.state.regions.erase("tianwei")
	w.state.erase("salt_pan")
	w.state.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:w.state.regions.erase(region)
	for region in World.TRANSIT.LOCAL:w.state.regions.erase(region)
	# Historical fixture predates the party-cart gallery region too (same as the other v7 tests).
	w.state.regions.erase(World.PARTY_CART.REGION)
	w.state.erase("bobo_workshop")
	for actor in w.state.players:w.state.players[actor].stories.erase("bobo")
	w.state.regions.jinguashi.objects.erase("21,21")
	for index in range(Bobo.SITE_PAIRS.size()-1):
		for point:Vector2i in Bobo.SITE_PAIRS[index]:
			w.state.regions.jinguashi.objects[World.key(point)]={"type":"wall","owner":"alpha","items":{}}
	expect(w.save() and w.load_world(path) and w.state.version==preload("res://scripts/save_schema.gd").VERSION and w.state.players.alpha.stories.bobo==0 and w.state.mine_freight.jobs.alpha.status=="delivered","Version seven migration preserves freight")
	var fallback:=Bobo.sites(w.state)
	expect(fallback.table==Vector2i(5,20) and w.state.regions.jinguashi.objects.size()==6,"All old walls preserved with a new workshop annex")
	w.switch_region("jinguashi")
	var path_clear:=true
	for x in range(6,13):path_clear=path_clear and w.can_stand(Vector2(x+0.5,20.5))
	expect(path_clear and w.blocked(fallback.table) and w.protected(fallback.table),"Annex accessible on foot, table solid and protected")
	w.switch_region("home")
	w.state.players.alpha.x=6.5
	w.state.players.alpha.y=20.5
	expect(w.act("alpha","annex-sort","bobo_sort_start",fallback.table).ok,"Actual workshop action uses annex from adjacent path")
	for file in [path,path+".bak"]:DirAccess.remove_absolute(file)
	print("BOBO_WORKSHOP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
