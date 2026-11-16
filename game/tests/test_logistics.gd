extends SceneTree
const World=preload("res://scripts/world.gd")
var w:=World.new()
var checks:=0
var failures:=0
func check(value:bool,note:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+note)
func obj(key:String,kind:String,items:Dictionary={},extra:Dictionary={}) -> void:
	w.state.objects[key]={"owner":"a","type":kind,"items":items}
	w.state.objects[key].merge(extra,true)
func belt(key:String,direction:int,items:Dictionary={}) -> void:
	obj(key,"conveyor",items,{"enabled":true,"dir":direction,"filter":"wood"})
func _initialize() -> void:
	w.add_player("a","甲")
	w.add_player("b","乙")
	obj("38,34","private_chest",{"wood":2})
	belt("39,34",1)
	belt("40,34",2)
	obj("40,35","sawmill",{},{"auto_enabled":false,"input_wood":0})
	var objects:Dictionary=w.state.objects
	check(w.step(2,false) and objects["39,34"].items.is_empty(),"offline pauses")
	check(w.step(2,true) and objects["39,34"].items.wood==1 and objects["40,34"].items.is_empty(),"pull only one hop")
	check(w.step(2,true) and objects["39,34"].items.is_empty() and objects["40,34"].items.wood==1,"turn accepts one hop")
	check(w.step(2,true) and objects["40,35"].input_wood==1 and objects["39,34"].items.wood==1,"mill buffer receives wood")
	check(w.step(2,true) and w.step(2,true) and objects["40,35"].input_wood==2,"entire chain conserves two wood")
	objects["40,35"].input_wood=32
	objects["40,34"].items.wood=1
	check(w.step(2,true) and objects["40,34"].items.wood==1,"backpressure retains item")
	belt("44,33",1,{"wood":1})
	belt("45,33",2)
	belt("45,34",3)
	belt("44,34",0)
	for tick in range(8):w.step(2,true)
	var loop_stock:=0
	for key in ["44,33","45,33","45,34","44,34"]:loop_stock+=int(objects[key].items.get("wood",0))
	check(loop_stock==1 and objects["44,33"].items.wood==1,"loop retains one item and advances exactly one edge each tick")
	objects["39,34"].filter="fiber"
	objects["40,34"].items.clear()
	objects["38,34"].items.wood=2
	check(w.step(2,true) and objects["39,34"].items.is_empty() and objects["38,34"].items.wood==2,"filter denies other item")
	objects["39,34"].filter="wood"
	objects["38,34"].type="chest"
	check(w.step(2,true) and objects["39,34"].items.is_empty(),"shared chest cannot be pulled")
	objects["38,34"].type="private_chest"
	objects["38,34"].owner="b"
	check(w.step(2,true) and objects["39,34"].items.is_empty(),"foreign private chest cannot be pulled")
	for player in w.state.players.values():
		player.x=39.5
		player.y=35.5
	check(not w.act("b","foreign","toggle_conveyor",Vector2i(39,34)).ok,"nonowner cannot toggle")
	check(not w.act("a","live","configure_conveyor",Vector2i(39,34),"dir:2").ok,"enabled belt cannot be configured")
	check(w.act("a","stop","toggle_conveyor",Vector2i(39,34)).ok and not w.act("a","bad","configure_conveyor",Vector2i(39,34),"dir:4").ok,"invalid direction denied")
	var mill:=Vector2i(40,35)
	objects["40,35"].input_wood=4
	check(w.act("a","auto","toggle_auto_processing",mill).ok,"enable mill")
	check(not w.act("a","manual","start_processing",mill,"plank").ok,"manual disabled in auto mode")
	var before:=w.state.duplicate(true)
	w.save_path="user://missing-logistics-folder/state.json"
	check(not w.step(2,true) and w.state==before,"save failure rolls back whole tick")
	var path:="user://logistics-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	check(w.step(2,true) and w.state.objects["40,35"].job.auto,"auto consumes buffered wood")
	check(w.act("a","stop-auto","toggle_auto_processing",mill).ok,"stop auto while running")
	check(not w.act("a","manual-claim","claim_processing",mill).ok,"manual cannot claim auto job")
	var loaded:=World.new()
	check(loaded.load_world(path) and loaded.state.objects["40,35"].job.auto,"auto job survives reload")
	check(loaded.step(12,true) and loaded.state.objects["40,35"].items.plank==2,"stopped auto job still completes")
	check(loaded.step(12,true) and loaded.state.objects["40,35"].items.plank==2,"completion cannot duplicate")
	var legacy:Dictionary=loaded.state.duplicate(true)
	legacy.erase("next_logistics_check")
	var prior:Dictionary=legacy.objects["40,35"]
	prior.erase("auto_enabled")
	prior.erase("input_wood")
	prior.items.clear()
	var legacy_path:=path+".legacy"
	var fixture_file:=FileAccess.open(legacy_path,FileAccess.WRITE)
	fixture_file.store_string(JSON.stringify(legacy))
	fixture_file.close()
	check(loaded.load_world(legacy_path) and loaded.state.objects["40,35"].input_wood==0
		and not loaded.state.objects["40,35"].auto_enabled,"0.9 processors migrate with empty disabled buffer")
	DirAccess.remove_absolute(legacy_path)
	check_edges(path)
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("LOGISTICS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func check_edges(path:String) -> void:
	w=World.new()
	w.add_player("a","甲")
	w.state.players.a.x=42.5
	w.state.players.a.y=34.5
	belt("41,34",1,{"wood":1})
	belt("42,33",2,{"wood":1})
	belt("42,34",2)
	var objects:Dictionary=w.state.objects
	check(w.step(2,true) and objects["42,34"].items.wood==1
		and int(objects["41,34"].items.get("wood",0))+int(objects["42,33"].items.get("wood",0))==1,"contested destination accepts one")
	obj("44,34","private_chest",{"wood":1})
	belt("43,34",3)
	belt("45,34",1)
	check(w.step(2,true) and objects["44,34"].items.is_empty()
		and int(objects["43,34"].items.get("wood",0))+int(objects["45,34"].items.get("wood",0))==1,"two belts cannot pull a single unit twice")
	obj("43,35","forester",{},World.FORESTRY.fresh(w.state.time))
	objects["43,35"].fuel=7
	obj("43,36","conveyor",{"charcoal":1},{"filter":"charcoal","enabled":true,"dir":0})
	check(w.step(2,true) and objects["43,35"].fuel==8,"forester accepts eighth fuel")
	objects["43,36"].items.charcoal=1
	check(w.step(2,true) and objects["43,35"].fuel==8 and objects["43,36"].items.charcoal==1,"forester cap retains belt item")
	obj("42,35","sawmill",{"plank":32},{"auto_enabled":true,"input_wood":4})
	objects["42,34"].dir=1
	check(w.step(2,true) and objects["42,35"].input_wood==4 and not objects["42,35"].has("job"),"full output prevents input consumption")
	objects["42,35"].items.plank=31
	check(w.step(2,true) and objects["42,35"].input_wood==4 and not objects["42,35"].has("job"),"one slot is insufficient for two outputs")
	w.state.players.a.inventory.plank=1000000000
	check(not w.act("a","overflow","collect_processing_output",Vector2i(42,35)).ok
		and objects["42,35"].items.plank==31 and w.state.players.a.inventory.plank==1000000000,"collection overflow leaves all inventory untouched")
	check(not w.act("a","move-mill","move_object",Vector2i(42,35),"41,35").ok
		and not w.act("a","remove-belt","remove",Vector2i(42,34)).ok,"cannot move supplied processor or remove enabled belt")
	var corrupt:=path+".corrupt"
	for mutation in [["42,34","dir",4],["42,34","filter","stone"],["42,34","items",{"wood":2}],
			["42,35","input_wood",33],["42,35","job",{"kind":"plank","owner":"a","ready":w.state.time,"ingredients":{"wood":4},"yield":2,"auto":"yes"}]]:
		var damaged:=w.state.duplicate(true)
		damaged.objects[mutation[0]][mutation[1]]=mutation[2]
		var stream:=FileAccess.open(corrupt,FileAccess.WRITE)
		stream.store_string(JSON.stringify(damaged))
		stream.close()
		check(not World.new().load_world(corrupt),"malformed save rejects "+mutation[1])
	DirAccess.remove_absolute(corrupt)
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--legacy="):
		var prior_path:=args[0].trim_prefix("--legacy=")
		var original:=FileAccess.get_file_as_string(prior_path)
		var prior_world:=World.new()
		check(FileAccess.file_exists(prior_path) and prior_world.load_world(prior_path) and prior_world.state.version==26
			and prior_world.state.next_logistics_check==0.0 and FileAccess.get_file_as_string(prior_path)==original,
			"actual 0.9 preview save migrates additively without changing file")

