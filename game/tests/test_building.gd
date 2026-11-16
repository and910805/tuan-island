extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
var seq:=0
var w
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func act(action:String,p:Vector2i,extra:String="",who:String="alice") -> Dictionary:
	seq+=1
	return w.act(who,"build-%d"%seq,action,p,extra)
func _initialize() -> void:
	w=World.new();w.add_player("alice","米");w.add_player("bob","豆")
	var p:Dictionary=w.state.players.alice
	p.inventory.wood=100;p.inventory.fiber=100
	var a:=Vector2i(37,34)
	expect(act("build_area",a,"floor|38|35").ok,"batch places four floor cells")
	expect(w.state.ground.size()==4 and p.inventory.wood==92,"all four tiles cost exactly eight wood")
	var count:int=w.state.ground.size()
	expect(not act("build_area",Vector2i(38,34),"floor|40|35").ok,"overlapping batch denied")
	expect(w.state.ground.size()==count and p.inventory.wood==92,"failed batch makes no partial placement or charge")
	expect(not act("build_area",Vector2i(37,34),"roof|38|35","bob").ok,"roof batch requires floor ownership")
	expect(act("build_area",a,"roof|38|35").ok,"roof layer batch succeeds")
	expect(w.state.roofs.size()==4 and p.inventory.wood==88 and p.inventory.fiber==88,"roof batch deducts exact materials")
	expect(not act("build_area",Vector2i(36,32),"floor|41|37").ok,"large batch exceeds cap")
	expect(not act("build_area",Vector2i(39,32),"floor|40|33").ok,"protected spawn stays clear")
	expect(not act("build_area",Vector2i(40,34),"floor|45|34").ok,"whole range must be nearby")
	expect(not act("build_area",Vector2i(40,34),"wall|41|35").ok,"batch limited to supported layers")
	p.inventory.stone=0
	expect(not act("build_area",Vector2i(40,34),"path|41|35").ok,"insufficient full batch materials denied")
	# Move a filled private box without duplicating contents or changing owner.
	var box:=Vector2i(38,33)
	expect(act("build",box,"private_chest").ok,"private chest created")
	expect(act("deposit",box,"wood").ok,"box holds a real item")
	var wood:int=p.inventory.wood
	expect(not act("move_object",box,"40,33","bob").ok,"neighbor cannot relocate private box")
	expect(act("move_object",box,"40,33").ok,"owner moves filled box")
	expect(not w.state.objects.has("38,33") and w.state.objects["40,33"].items.wood==1,"exactly one box retains its contents")
	expect(p.inventory.wood==wood and w.state.objects["40,33"].owner=="alice","move is free and preserves ownership")
	expect(not act("move_object",Vector2i(40,33),"39,33").ok,"cannot move onto protected spawn")
	w.state.players.bob.x=41.5;w.state.players.bob.y=33.5
	expect(not act("move_object",Vector2i(40,33),"41,33").ok,"cannot trap active player")
	var before:Dictionary=w.state.duplicate(true)
	w.save_path="user://missing-batch-save-test/world.json"
	expect(not act("build_area",Vector2i(40,34),"floor|41|35").ok,"failed save rejects batch")
	expect(w.state.ground==before.ground and w.state.players.alice.inventory==before.players.alice.inventory,"failed batch save rolls back everything")
	expect(not act("move_object",Vector2i(40,33),"38,33").ok,"failed save rejects furniture movement")
	expect(w.state.objects==before.objects,"failed move save retains original box location and contents")
	var path:="user://styled-build-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	var tile:=Vector2i(40,34)
	expect(not act("build",tile,"floor@unknown").ok,"Unknown styles are rejected")
	expect(act("build",tile,"floor@coast").ok,"Coastal floor can be placed")
	expect(act("build",tile,"roof@tea_house").ok,"Tea house roof can be placed over owned floor")
	expect(act("build_area",Vector2i(41,34),"floor|41|35@coast").ok,"Coastal flooring supports drag placement")
	expect(act("build_area",Vector2i(41,34),"roof|41|35@tea_house").ok,"Tea house roofing supports drag placement")
	var styled_before: Dictionary = w.state.duplicate(true)
	expect(not act("build_area",Vector2i(41,34),"floor|42|35@coast").ok,"Overlap rejects styled batch")
	expect(w.state==styled_before,"Rejected styled batch changes neither layers nor materials")
	var reopened:=World.new()
	expect(reopened.load_world(path),"Styled build loads from disk")
	var snapshot:Dictionary=reopened.region_snapshot(World.REGIONS.HOME)
	expect(snapshot.ground.get("40,34",{}).get("style")=="coast","Snapshot retains floor style")
	expect(snapshot.roofs.get("40,34",{}).get("style")=="tea_house","Snapshot retains roof style")
	for cell in ["41,34","41,35"]:
		expect(snapshot.ground.get(cell,{}).get("style")=="coast","Snapshot retains every styled floor cell")
		expect(snapshot.roofs.get(cell,{}).get("style")=="tea_house","Snapshot retains every styled roof cell")
	for suffix in ["",".bak"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BUILDING_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
