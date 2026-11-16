extends SceneTree
## Save 23 / protocol 41 public kitchen: schema shape, legacy migration, home-only
## site validation, disk roundtrip and Session transport/publish boundaries.
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Community=preload("res://scripts/community.gd")
const Regions=preload("res://scripts/regions.gd")
var checks:=0
var failures:=0
var path:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func write_candidate(candidate:Dictionary) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(candidate));f.close()

## Validate a deep copy exactly as World._load_file does (after a JSON trip so
## integers arrive as floats like a real save).
func accepts(candidate:Dictionary) -> bool:
	var parsed=JSON.parse_string(JSON.stringify(candidate))
	return parsed is Dictionary and SaveSchema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func registered(base:Dictionary,stove:String,seats:Array,meals:Dictionary={}) -> Dictionary:
	if meals.is_empty():meals={"soup":0,"bread":0,"salad":0}
	var out:Dictionary=base.duplicate(true)
	var full:=true
	for meal in SaveSchema.KITCHEN_MEALS:
		if int(meals[meal])!=int(SaveSchema.KITCHEN_MEALS[meal]):full=false
	out.public_kitchen={"stove":stove,"seats":seats.duplicate(),"meals":meals.duplicate(),"opened":full}
	return out

func place(state:Dictionary,cell:String,type:String,who:String) -> void:
	state.objects[cell]={"type":type,"owner":who,"items":{}}

func _initialize() -> void:
	path="user://public-kitchen-schema-%d.json"%Time.get_ticks_usec()
	expect(SaveSchema.VERSION==26 and SaveSchema.PUBLIC_KITCHEN_VERSION==23,"save version 23")
	expect(SaveSchema.MATERIAL_SOURCE_VERSION==22 and SaveSchema.PROCESSING_QUEUE_VERSION==21 and SaveSchema.COOKING_QUEUE_VERSION==20 and SaveSchema.BLUEPRINT_HISTORY_VERSION==19,"legacy cutoffs unchanged")
	expect(SaveSchema.public_kitchen_fresh()=={"stove":"","seats":[],"meals":{"soup":0,"bread":0,"salad":0},"opened":false},"fresh shape matches contract")

	var w=World.new()
	w.add_player("alice-token-0001","阿米")
	w.add_player("bob-token-000002","小波")
	# Independent of World's own ensure: a version-23 root must carry the field.
	if not w.state.has("public_kitchen"):w.state.public_kitchen=SaveSchema.public_kitchen_fresh()
	var plain:Dictionary=w.state.duplicate(true)
	w.state.picnic=true
	w.state.community={"table":Community.choose_table(w.state)}
	expect(w.state.community.table=="39,30","shared table at first candidate")
	# Table (39,30); stove (37,33) is sqrt(13) away; seats 1 and sqrt(2) from it.
	place(w.state,"37,33","stove","alice-token-0001")
	place(w.state,"36,33","long_bench","alice-token-0001")
	place(w.state,"36,34","long_bench","alice-token-0001")
	var base:Dictionary=w.state.duplicate(true)
	var site:=registered(base,"37,33",["36,33","36,34"])

	expect(accepts(plain),"fresh unregistered v23 world validates")
	expect(accepts(base),"picnic world with own furniture but unregistered validates")
	var missing:Dictionary=base.duplicate(true);missing.erase("public_kitchen")
	expect(not accepts(missing),"v23 without public_kitchen rejected")

	# --- legacy migration: fresh only, never implicit registration ---------
	for old_version in [22,21,18]:
		var legacy:Dictionary=base.duplicate(true)
		legacy.erase("public_kitchen")
		legacy.version=old_version
		legacy.erase("flower_nursery")
		legacy.regions.erase("tianwei")
		legacy.erase("salt_pan")
		legacy.regions.erase("beimen")
		if old_version<22:
			# Keep the candidate legal for its own era (no later-only fields).
			for obj in legacy.objects.values():obj.erase("box_id")
		var parsed=JSON.parse_string(JSON.stringify(legacy))
		var ok:bool=SaveSchema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
		expect(ok,"legacy v%d without field migrates"%old_version)
		if ok:
			expect(parsed.version==26,"legacy v%d stamped 23"%old_version)
			expect(parsed.public_kitchen==SaveSchema.public_kitchen_fresh(),"legacy v%d gets fresh, not the eligible stove/benches"%old_version)
		var carrying:Dictionary=legacy.duplicate(true)
		carrying.public_kitchen=SaveSchema.public_kitchen_fresh()
		expect(not accepts(carrying),"legacy v%d carrying public_kitchen rejected"%old_version)
	var legacy_site:Dictionary=site.duplicate(true);legacy_site.version=22
	legacy_site.erase("flower_nursery")
	legacy_site.regions.erase("tianwei")
	legacy_site.erase("salt_pan")
	legacy_site.regions.erase("beimen")
	expect(not accepts(legacy_site),"legacy v22 carrying a registration rejected")

	# --- registered valid states ------------------------------------------
	expect(accepts(site),"registered site validates")
	expect(accepts(registered(base,"37,33",["36,33","36,34"],{"soup":3,"bread":2,"salad":0})),"partial contribution validates")
	expect(accepts(registered(base,"37,33",["36,33","36,34"],{"soup":4,"bread":2,"salad":2})),"full + opened validates")
	var busy:Dictionary=site.duplicate(true)
	busy.objects["37,33"].job={"kind":"bread","owner":"bob-token-000002","ready":5.0}
	expect(accepts(busy),"donated stove may keep cooking (no idle save invariant)")
	var normalised=JSON.parse_string(JSON.stringify(registered(base,"37,33",["36,33","36,34"],{"soup":1,"bread":0,"salad":2})))
	expect(SaveSchema.validate(normalised,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"float meals validate")
	expect(typeof(normalised.public_kitchen.meals.soup)==TYPE_INT and normalised.public_kitchen.meals.salad==2,"meals normalised to int")

	# Exact range boundaries: stove Euclidean 8 from table, seat 3 from stove.
	var edge:Dictionary=base.duplicate(true)
	for cell in ["37,33","36,33","36,34"]:edge.objects.erase(cell)
	place(edge,"39,38","stove","alice-token-0001")
	place(edge,"39,41","long_bench","alice-token-0001")
	place(edge,"40,38","long_bench","alice-token-0001")
	expect(accepts(registered(edge,"39,38",["39,41","40,38"])),"stove at exactly 8 and seat at exactly 3 accepted")
	var far_stove:Dictionary=base.duplicate(true)
	for cell in ["37,33","36,33","36,34"]:far_stove.objects.erase(cell)
	place(far_stove,"39,39","stove","alice-token-0001")
	place(far_stove,"39,40","long_bench","alice-token-0001")
	place(far_stove,"40,39","long_bench","alice-token-0001")
	expect(not accepts(registered(far_stove,"39,39",["39,40","40,39"])),"stove at 9 rejected")
	var far_seat:Dictionary=edge.duplicate(true)
	far_seat.objects.erase("39,41")
	place(far_seat,"41,41","long_bench","alice-token-0001")
	expect(not accepts(registered(far_seat,"39,38",["40,38","41,41"])),"seat at sqrt(13) rejected")

	# --- malformed cases ---------------------------------------------------
	var bad_cases:Dictionary={}
	var bad:Dictionary
	bad=site.duplicate(true);bad.public_kitchen["owner"]="alice-token-0001";bad_cases["extra key"]=bad
	bad=site.duplicate(true);bad.public_kitchen.erase("opened");bad_cases["missing key"]=bad
	bad=site.duplicate(true);bad.public_kitchen="open";bad_cases["not a dictionary"]=bad
	bad=site.duplicate(true);bad.public_kitchen.stove=37;bad_cases["stove not string"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats="36,33|36,34";bad_cases["seats not array"]=bad
	bad=site.duplicate(true);bad.public_kitchen.opened=0;bad_cases["opened not bool"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals["tea"]=0;bad_cases["extra meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.erase("salad");bad_cases["missing meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.soup=5;bad_cases["soup over cap"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.bread=-1;bad_cases["negative meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.salad=1.5;bad_cases["fractional meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.soup=true;bad_cases["bool meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.meals.soup="1";bad_cases["string meal"]=bad
	bad=site.duplicate(true);bad.public_kitchen.opened=true;bad_cases["opened while not full"]=bad
	bad=registered(base,"37,33",["36,33","36,34"],{"soup":4,"bread":2,"salad":2});bad.public_kitchen.opened=false;bad_cases["full but closed"]=bad
	bad=base.duplicate(true);bad.public_kitchen.seats=["36,33","36,34"];bad_cases["unregistered with seats"]=bad
	bad=base.duplicate(true);bad.public_kitchen.meals.soup=1;bad_cases["unregistered with meals"]=bad
	bad=base.duplicate(true);bad.public_kitchen.meals={"soup":4,"bread":2,"salad":2};bad.public_kitchen.opened=true;bad_cases["unregistered opened"]=bad
	bad=site.duplicate(true);bad.picnic=false;bad.community={"table":""};bad_cases["no picnic"]=bad
	bad=site.duplicate(true);bad.community={"table":""};bad_cases["no shared table"]=bad
	bad=site.duplicate(true);bad.public_kitchen.stove="37,033";bad_cases["non-canonical stove"]=bad
	bad=site.duplicate(true);bad.public_kitchen.stove=" 37,33";bad_cases["spaced stove"]=bad
	bad=site.duplicate(true);bad.public_kitchen.stove="80,0";bad_cases["out of bounds stove"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats=["36,33"];bad_cases["one seat"]=bad
	bad=site.duplicate(true);place(bad,"38,34","long_bench","alice-token-0001");bad.public_kitchen.seats=["36,33","36,34","38,34"];bad_cases["three seats"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats=["36,33","36,33"];bad_cases["duplicate seats"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats=["36,34","36,33"];bad_cases["unsorted seats"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats=["36,33",36];bad_cases["non-string seat"]=bad
	bad=site.duplicate(true);bad.public_kitchen.seats=["36,33","37,33"];bad_cases["seat equals stove"]=bad
	bad=site.duplicate(true);bad.objects.erase("37,33");bad_cases["stove object missing"]=bad
	bad=site.duplicate(true);bad.objects["37,33"].type="sawmill";bad.objects["37,33"].merge({"input_wood":0,"auto_enabled":false});bad_cases["stove cell wrong type"]=bad
	bad=site.duplicate(true);bad.objects["36,34"].type="bench";bad_cases["seat is a short bench"]=bad
	bad=site.duplicate(true);bad.objects.erase("36,33");bad_cases["seat object missing"]=bad
	bad=site.duplicate(true);bad.objects["36,34"].owner="bob-token-000002";bad_cases["seat owned by another member"]=bad
	bad=site.duplicate(true);bad.objects["37,33"].owner="bob-token-000002";bad_cases["stove owned by another member"]=bad
	bad=site.duplicate(true)
	for cell in ["37,33","36,33","36,34"]:bad.objects[cell].owner="ghost-token-0003"
	bad_cases["owner not a persistent player"]=bad
	# Home-layer only: the same furniture in a remote region must not satisfy it.
	# Find a remote region whose layer legally holds furniture at these cells so
	# the rejection is attributable to the kitchen check, not region terrain.
	var remote_tested:=false
	for region in Regions.ALL:
		if region==Regions.HOME or remote_tested:continue
		var moved:Dictionary=site.duplicate(true)
		for cell in ["37,33","36,33","36,34"]:
			moved.regions[region].objects[cell]=moved.objects[cell]
			moved.objects.erase(cell)
		var control:Dictionary=moved.duplicate(true)
		control.public_kitchen=SaveSchema.public_kitchen_fresh()
		if not accepts(control):continue
		remote_tested=true
		bad_cases["site only in remote region "+region]=moved
	if not remote_tested:print("NOTE no remote region accepts furniture at the test cells; remote-only case skipped")
	for label in bad_cases:
		expect(not accepts(bad_cases[label]),"malformed rejected: "+label)
	# Region / history projections shallow-copy the root field; a registered home
	# site must still validate although no remote layer has those objects.
	expect(accepts(site),"registered home site unaffected by region projections")

	# --- disk roundtrip through World --------------------------------------
	var saved=World.new()
	saved.state=registered(base,"37,33",["36,33","36,34"],{"soup":2,"bread":1,"salad":0})
	saved.save_path=path
	expect(saved.save(),"registered world saves")
	var loaded=World.new()
	expect(loaded.load_world(path),"registered world reloads")
	expect(loaded.state.version==26,"reloaded version 23")
	expect(loaded.state.public_kitchen=={"stove":"37,33","seats":["36,33","36,34"],"meals":{"soup":2,"bread":1,"salad":0},"opened":false},"public_kitchen survives disk roundtrip")
	var opened=World.new()
	opened.state=registered(base,"37,33",["36,33","36,34"],{"soup":4,"bread":2,"salad":2})
	opened.save_path=path
	expect(opened.save() and loaded.load_world(path) and loaded.state.public_kitchen.opened==true,"opened kitchen roundtrips")
	var good:Dictionary=loaded.state.duplicate(true)
	# Without removing the backup, load_world would legitimately recover from it.
	if FileAccess.file_exists(path+".bak"):DirAccess.remove_absolute(path+".bak")
	write_candidate(bad_cases["unsorted seats"])
	var rejected_text:=FileAccess.get_file_as_string(path)
	expect(not loaded.load_world(path),"malformed file rejected on load")
	expect(loaded.state==good,"rejected file leaves live state untouched")
	expect(FileAccess.get_file_as_string(path)==rejected_text,"rejected file is not rewritten")
	var legacy_disk:Dictionary=base.duplicate(true);legacy_disk.erase("public_kitchen");legacy_disk.version=22
	legacy_disk.erase("flower_nursery")
	legacy_disk.regions.erase("tianwei")
	legacy_disk.erase("salt_pan")
	legacy_disk.regions.erase("beimen")
	write_candidate(legacy_disk)
	expect(loaded.load_world(path) and loaded.state.public_kitchen==SaveSchema.public_kitchen_fresh(),"legacy disk save loads unregistered")

	# --- Session transport boundaries --------------------------------------
	expect(Session.PROTOCOL==45,"protocol 41")
	for action in [Session.KITCHEN_REGISTER,Session.KITCHEN_CONTRIBUTE]:
		expect(action in Session.CORRELATED_ACTIONS,"%s correlated"%action)
		expect(action.length()<24,"%s within action name bound"%action)
	expect(Session.KITCHEN_REGISTER=="kitchen_register" and Session.KITCHEN_CONTRIBUTE=="kitchen_contribute","action names match contract")
	for extra in ["36,33|36,34","0,0|79,59","10,5|9,5","1,2|1,3"]:
		expect(Session.extra_allowed("kitchen_register",extra),"register extra accepted: "+extra)
	var refused:=["","36,33","36,34|36,33","36,33|36,33","36,33|36,34|37,33","036,33|36,34","-1,0|0,0",
		" 36,33|36,34","36,33 |36,34","36,33|36,34|","+3,3|4,4","3,3|4,4,","a,b|c,d","３,3|4,4",
		"1234567,1|1,2","1234567890,1|1234567890,2","100000,100000|100000,100001x"]
	for extra in refused:
		expect(not Session.extra_allowed("kitchen_register",extra),"register extra refused: "+extra)
	expect(Session.extra_allowed("kitchen_register","999999,999998|999999,999999"),"widest canonical pair (27 chars) passes transport")
	expect(not Session.extra_allowed("kitchen_register","999999,9999980|999999,999999"),"seven-digit coordinate refused")
	expect(not Session.extra_allowed("kitchen_register","1,1|"+"2".repeat(29)),"over 32 chars refused")
	expect(Session.extra_allowed("kitchen_contribute",""),"contribute empty extra accepted")
	for extra in ["soup"," ","37,33","0"]:
		expect(not Session.extra_allowed("kitchen_contribute",extra),"contribute non-empty extra refused: "+extra)
	expect(Session.extra_allowed("cook","bread") and Session.extra_allowed("prepare_material_box","3,4"),"existing extras unchanged")

	# --- published snapshot: shared, identity-free, deep copy --------------
	var host=Session.new()
	host.world=World.new()
	host.world.state=registered(base,"37,33",["36,33","36,34"],{"soup":1,"bread":0,"salad":0})
	var home_view:Dictionary=host.public_state(Regions.HOME)
	var remote_view:Dictionary=host.public_state(Regions.LANYANG)
	expect(home_view.get("public_kitchen")=={"stove":"37,33","seats":["36,33","36,34"],"meals":{"soup":1,"bread":0,"salad":0},"opened":false},"home snapshot carries public_kitchen")
	expect(remote_view.get("public_kitchen")==home_view.get("public_kitchen"),"remote region sees the same shared kitchen")
	var published:=JSON.stringify(home_view.public_kitchen)
	expect(not published.contains("alice") and not published.contains("bob") and not published.contains("token"),"no player identity in public_kitchen")
	expect(home_view.public_kitchen.keys().size()==4,"exact public keys")
	home_view.public_kitchen.seats.append("1,1")
	home_view.public_kitchen.meals.soup=4
	expect(host.world.state.public_kitchen.seats.size()==2 and host.world.state.public_kitchen.meals.soup==1,"snapshot is a deep copy")
	host.world.state.erase("public_kitchen")
	expect(host.public_state(Regions.HOME).public_kitchen==SaveSchema.public_kitchen_fresh(),"missing live field publishes fresh")
	host.free()

	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PUBLIC_KITCHEN_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
