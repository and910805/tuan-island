extends SceneTree
const World=preload("res://scripts/world.gd")
var w
var sequence:=0
var checks:=0
var failures:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func act(action:String,p:Vector2i,extra:String="",who:String="alice") -> Dictionary:
	sequence+=1
	return w.act(who,"life-%d"%sequence,action,p,extra)
func _initialize() -> void:
	w=World.new()
	w.add_player("alice","米米")
	w.add_player("bob","豆豆")
	var p:Dictionary=w.state.players.alice
	p.inventory.stone=30
	p.inventory.wood=60
	p.inventory.wheat=6
	p.inventory.radish=2
	var stove:=Vector2i(38,33)
	expect(act("build",stove,"stove").ok,"stove built")
	expect(act("cook",stove,"soup").ok,"soup ingredients committed")
	expect(p.inventory.radish==0,"soup ingredients deducted")
	expect(not act("cook",stove,"bread").ok,"busy stove rejects second job")
	expect(not act("claim_cook",stove).ok,"cannot claim early")
	expect(not act("remove",stove).ok,"cannot destroy active cooking")
	expect(not act("cancel_cook",stove,"","bob").ok,"only contributor can cancel")
	w.step(11,true)
	expect(act("claim_cook",stove).ok,"completed soup claimed")
	expect(p.inventory.soup==2,"correct soup yield")
	expect(not act("claim_cook",stove,"","bob").ok,"second claim denied")
	expect(act("cook",stove,"bread").ok,"bread starts")
	# Simulate a queued job created under an older three-wheat recipe.
	w.state.objects[World.key(stove)].job.ingredients={"wheat":3}
	p.inventory.wheat-=1
	expect(act("cancel_cook",stove).ok,"own cooking can cancel")
	expect(p.inventory.wheat==6,"cancel refunds all input")
	expect(not act("cancel_cook",stove).ok,"cancel cannot refund twice")
	expect(act("cook",stove,"bread").ok,"bread restarted")
	w.state.objects[World.key(stove)].job["yield"]=2
	w.step(16,true)
	expect(act("claim_cook",stove).ok,"bread claimed")
	expect(p.inventory.bread==2,"queued job preserves original yield across recipe changes")
	expect(act("cook",stove,"feed").ok,"feed starts")
	w.step(6,true)
	expect(act("claim_cook",stove).ok,"feed claimed")
	expect(p.inventory.feed==4,"feed recipe yields four")
	p.x=45.5
	p.y=34.5
	var chicken:=Vector2i(45,34)
	expect(act("pet",chicken).ok,"pet chicken")
	expect(not act("pet",chicken).ok,"pet cooldown stops spam")
	expect(act("feed",chicken).ok,"feed consumes one")
	expect(p.inventory.feed==3,"only one feed deducted")
	expect(not act("feed",chicken).ok,"cannot consume extra feed while full")
	expect(not act("egg",chicken).ok,"egg cannot be claimed early")
	w.step(61,true)
	expect(act("egg",chicken).ok,"egg collected after growth")
	expect(p.inventory.egg==1,"one egg in inventory")
	expect(not act("egg",chicken).ok,"egg cannot be claimed twice")
	p.x=54.5
	p.y=34.5
	var water:=Vector2i(55,34)
	expect(act("fish_start",water).ok,"fish cast at river")
	expect(not act("fish_catch",water).ok,"fish cannot be caught early")
	w.step(3.1,true)
	expect(act("fish_catch",water).ok,"fish ready with no reaction deadline")
	expect(p.inventory.carp==1,"first fish rewarded")
	expect(not act("fish_catch",water).ok,"fish cannot duplicate")
	expect(act("fish_start",water).ok,"second cast")
	w.move_player("alice",Vector2.LEFT,0.1)
	expect(not p.has("fishing"),"moving cancels cast")
	p.x=43.5
	p.y=31.5
	expect(act("sell",Vector2i(43,29),"carp").ok,"fish sells at vendor")
	expect(p.coins==138,"fish sale pays exactly listed price")
	expect(not act("buy",Vector2i(43,29),"carp").ok,"cannot buy fish as seeds")
	p.x=40.5
	p.y=31.5
	expect(not act("picnic",Vector2i(40,29)).ok,"picnic requires repaired board")
	w.state.board=true
	expect(act("picnic",Vector2i(40,29)).ok,"donate recipes to picnic")
	expect(w.state.picnic,"picnic changes world")
	expect(p.inventory.radish_seed==8,"picnic reward issued once")
	expect(not act("picnic",Vector2i(40,29)).ok,"cannot repeat picnic reward")
	expect(w.state.players.bob.inventory.radish_seed==8,"all existing members receive reward")
	test_cooking_capacity()
	print("LIFE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func test_cooking_capacity() -> void:
	# Explicit capacity fixture; no natural-play claim. Preserve historical recipe
	# snapshots and verify all ingredients before refunding any of them.
	w=World.new()
	w.add_player("alice","米米")
	var cell:=Vector2i(38,33)
	var key:=World.key(cell)
	w.state.objects[key]={"type":"stove","owner":"alice","items":{}}
	w.state.players.alice.inventory={"wheat":1,"fiber":2}
	expect(act("cook",cell,"feed").ok,"capacity fixture starts feed")
	w.state.players.alice.inventory={"wheat":0,"fiber":1000000000}
	var original:Dictionary=w.state.objects[key].job.duplicate(true)
	expect(not act("cancel_cook",cell).ok,"refund rejects overflowing second ingredient")
	expect(w.state.players.alice.inventory.wheat==0 and w.state.players.alice.inventory.fiber==1000000000,"failed refund does not partially return first ingredient")
	expect(w.state.objects[key].job==original,"failed refund preserves original job")
	w.state.players.alice.inventory.fiber=999999998
	expect(act("cancel_cook",cell).ok,"refund succeeds at exact item cap")
	expect(w.state.players.alice.inventory.wheat==1 and w.state.players.alice.inventory.fiber==1000000000,"exact original costs refunded once")
	w.state.players.alice.inventory={"radish":2,"soup":999999999}
	expect(act("cook",cell,"soup").ok,"capacity fixture starts soup")
	w.step(11,true)
	original=w.state.objects[key].job.duplicate(true)
	var cooked_before:int=int(w.state.players.alice.get("cooked",0))
	expect(not act("claim_cook",cell).ok,"claim rejects overflowing output")
	expect(w.state.objects[key].job==original and w.state.players.alice.inventory.soup==999999999,"full bag retains complete meal without extra items")
	expect(int(w.state.players.alice.get("cooked",0))==cooked_before,"rejected claim does not increment cooking progress")
	w.state.players.alice.inventory.soup=999999998
	expect(act("claim_cook",cell).ok,"claim succeeds exactly at item cap")
	expect(w.state.players.alice.inventory.soup==1000000000 and not w.state.objects[key].has("job"),"successful claim consumes job and awards exact yield")
	expect(not act("claim_cook",cell).ok,"completed capacity claim cannot duplicate")
	var path:=OS.get_environment("TEMP").path_join("cooking-capacity-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json")
	w.save_path=path
	expect(w.save(),"exact-cap cooking state saves")
	var reopened:=World.new()
	expect(reopened.load_world(path),"exact-cap cooking state passes actual save validation")
	expect(reopened.state.players.alice.inventory.soup==1000000000 and not reopened.state.objects[key].has("job"),"reload keeps exact yield and consumed job")
	for file in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
