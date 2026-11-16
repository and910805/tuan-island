extends SceneTree
const World=preload("res://scripts/world.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
var checks:=0
var failures:=0
var path:=""
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func write_candidate(candidate:Dictionary) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(candidate));f.close()
func _initialize() -> void:
	path="user://schema-test-%d.json"%Time.get_ticks_usec()
	var w=World.new()
	w.add_player("alice","米米")
	w.state.players.alice.inventory.wood=100
	w.state.players.alice.inventory.stone=50
	w.state.players.alice.inventory.wheat=3
	w.act("alice","stove","build",Vector2i(38,33),"stove")
	w.act("alice","cook","cook",Vector2i(38,33),"bread")
	w.act("alice","hoe","hoe",Vector2i(37,34))
	w.act("alice","seed","seed",Vector2i(37,34),"radish")
	w.act("alice","tree","plant_tree",Vector2i(38,34))
	var baseline:Dictionary=w.state.duplicate(true)
	write_candidate(baseline)
	var loaded=World.new()
	expect(loaded.load_world(path),"valid full world loads")
	var bad_cases:Array=[]
	var bad:Dictionary=baseline.duplicate(true);bad.time="tomorrow";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.players.alice.x="bad";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.players.alice.inventory.wood=-1;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.players.alice.inventory.wood=1.5;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.players.alice.receipts={"retry":false};bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.players.alice["fishing"]={"x":55,"y":34};bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.crops["37,34"].kind="removed_crop";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.crops["37,34"].growth=200;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.crops["broken"]=bad.crops["37,34"];bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.objects["38,33"].items={"wood":-2};bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.objects["38,33"].type="removed_furniture";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.objects["38,33"].job.kind="removed_recipe";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.objects["38,33"].job["yield"]=0;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.forest["38,34"].mature=true;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.forest["800,700"]={};bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.animal.egg_ready="soon";bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.picnic_materials.soup=3;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.donations.stone=-1;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.removed["38,32"]=1;bad_cases.append(bad)
	bad=baseline.duplicate(true);bad.version=999;bad_cases.append(bad)
	for i in range(bad_cases.size()):
		write_candidate(bad_cases[i])
		var original:=FileAccess.get_file_as_string(path)
		var previous:Dictionary=loaded.state.duplicate(true)
		expect(not loaded.load_world(path),"malformed case %d rejected"%i)
		expect(loaded.state==previous,"rejected case does not replace live state")
		expect(FileAccess.get_file_as_string(path)==original,"rejected case leaves player file untouched")
	bad=baseline.duplicate(true)
	for field in ["animal","forest","roofs","picnic","picnic_materials"]:bad.erase(field)
	bad.crops["37,34"].erase("owner")
	bad.objects["38,33"].job.erase("ingredients")
	bad.objects["38,33"].job.erase("yield")
	write_candidate(bad)
	expect(loaded.load_world(path),"older world with missing additive fields migrates")
	expect(loaded.state.crops["37,34"].kind=="radish" and loaded.state.objects["38,33"].job.kind=="bread","migration preserves crops and pending dish")
	item_catalog_load_path(baseline,loaded)
	# Recovery must never rotate a corrupted primary over a known-good backup.
	w.save_path=path
	expect(w.save(),"create valid primary and backup")
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string("damaged original");f.close()
	var recovery=World.new()
	expect(recovery.load_world(path) and recovery.recovered_from_backup,"backup recovery is observable")
	var backup_before:=FileAccess.get_file_as_string(path+".bak")
	expect(recovery.save(),"recovered state can be committed")
	expect(FileAccess.get_file_as_string(path+".bak")==backup_before,"first save after recovery preserves good backup")
	expect(FileAccess.get_file_as_string(recovery.rejected_path)=="damaged original","damaged original retained separately")
	expect(World.new().load_world(path),"repaired primary validates on next restart")
	if not recovery.rejected_path.is_empty():DirAccess.remove_absolute(recovery.rejected_path)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SAVE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

## T013: World.load_world -> SaveSchema.validate -> SaveSchema.counts ->
## ItemCatalog, on real JSON save files. Malformed stack data is rejected
## atomically (live state and the file untouched); unknown legacy item IDs keep
## loading with the 1,000,000,000 ceiling; an invalid shipped catalog fails closed.
func item_catalog_load_path(baseline:Dictionary,loaded) -> void:
	expect(Catalog.current().ok,"T013 shipped item catalog validates")
	var cap:=Catalog.STACK_CEILING
	var rejects:Array=[]
	var bad:Dictionary=baseline.duplicate(true);bad.players.alice.inventory.wood=cap+1;rejects.append(["inventory known id over stack limit",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory.legacy_mystery=cap+1;rejects.append(["inventory unknown legacy id over 1e9",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory.wood="12";rejects.append(["inventory string count",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory.wood=true;rejects.append(["inventory bool count",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory.wood=2.5;rejects.append(["inventory fractional count",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory["x".repeat(65)]=1;rejects.append(["inventory 65-char key",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory=[["wood",3]];rejects.append(["inventory not a Dictionary",bad])
	bad=baseline.duplicate(true);bad.players.alice.inventory.legacy_mystery=4;bad.players.alice.inventory.stone=-3;rejects.append(["valid legacy key next to a negative count",bad])
	bad=baseline.duplicate(true);bad.objects["38,33"].items={"wood":cap+1};rejects.append(["object items over stack limit",bad])
	bad=baseline.duplicate(true);bad.objects["38,33"].items={"legacy_mystery":1.25};rejects.append(["object items fractional legacy count",bad])
	for entry in rejects:
		write_candidate(entry[1])
		var file_before:=FileAccess.get_file_as_string(path)
		var state_before:Dictionary=loaded.state.duplicate(true)
		expect(not loaded.load_world(path),"T013 load rejects: "+entry[0])
		expect(loaded.state==state_before,"T013 rejected load leaves live state unchanged: "+entry[0])
		expect(FileAccess.get_file_as_string(path)==file_before,"T013 rejected load leaves the save file untouched: "+entry[0])
	# Unknown legacy String IDs keep loading exactly as before, at and below 1e9,
	# and are normalised to int like every other count.
	var legacy:Dictionary=baseline.duplicate(true)
	legacy.players.alice.inventory.legacy_mystery=7
	legacy.players.alice.inventory.legacy_full_stack=cap
	legacy.players.alice.inventory.wood=cap
	legacy.objects["38,33"].items={"legacy_mystery":2}
	write_candidate(legacy)
	expect(loaded.load_world(path),"T013 unknown legacy item IDs (and known IDs at the 1e9 limit) still load")
	var inv:Dictionary=loaded.state.players.alice.get("inventory",{})
	expect(inv.get("legacy_mystery")==7 and typeof(inv.get("legacy_mystery"))==TYPE_INT,"T013 legacy count kept and normalised to int (got %s)"%str(inv.get("legacy_mystery")))
	expect(inv.get("legacy_full_stack")==cap and typeof(inv.get("legacy_full_stack"))==TYPE_INT,"T013 legacy count at 1e9 kept")
	expect(inv.get("wood")==cap and typeof(inv.get("wood"))==TYPE_INT,"T013 known item at its 1e9 stack limit kept")
	expect(loaded.state.objects["38,33"].get("items",{}).get("legacy_mystery")==2,"T013 legacy key in object items kept")
	expect(Catalog.inventory_report(inv).unknown.size()==2,"T013 legacy IDs are reported as unknown, not refused")
	# Fail closed: an invalid shipped catalog must reject even a valid save.
	write_candidate(baseline)
	var original:=FileAccess.get_file_as_string(path)
	var previous:Dictionary=loaded.state.duplicate(true)
	Catalog.override_current(Catalog.load_definitions([{"id":"wood","name":"木材"},{"id":"wood","name":"木材"}]))
	expect(not Catalog.current().ok,"T013 fixture: duplicate-ID catalog is invalid")
	expect(not loaded.load_world(path),"T013 invalid item catalog: valid save is rejected (fail closed)")
	expect(loaded.state==previous,"T013 invalid item catalog: live state unchanged")
	expect(FileAccess.get_file_as_string(path)==original,"T013 invalid item catalog: save file untouched")
	Catalog.reset_current()
	expect(Catalog.current().ok and loaded.load_world(path),"T013 after catalog reset the same save loads again")
