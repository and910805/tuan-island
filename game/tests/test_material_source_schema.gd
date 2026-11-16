extends SceneTree
## Save schema 22: optional lazy material-source `box_id` on chest/private_chest
## (docs/material-source-contract.json "identity"/"schema").
## FIXTURES: a real fresh World builds a floor, a shared chest and a private
## chest through World.act (real construction history with a live watch), then
## the state is JSON round-tripped and labelled extra objects are inserted
## (a sawmill at home, a shared chest in lanyang, a private chest in jinguashi).
## Every box_id is a hand-written 32-lowercase-hex value; no World assignment
## path (prepare_material_box) is exercised here, that belongs to World tests.
## No production code is overridden and no stubs are used; World is exercised
## only via act (fixture), load_world and save.
## Run: godot --headless --path game --script res://tests/test_material_source_schema.gd
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const History=preload("res://scripts/construction_history.gd")
const A:="material-schema-owner"
const B:="material-schema-friend"
const FLOOR:=Vector2i(48,24)
const CHEST:=Vector2i(47,26)       # shared chest, built by A through World.act
const PRIVATE:=Vector2i(49,27)     # private chest, built by A (last live history entry)
const SAW_CELL:="49,25"            # sawmill fixture (box_id must never be allowed on it)
const TABLE_CELL:="46,24"          # table fixture (box_id must never be allowed on it)
const LAN:="lanyang"
const LAN_CELL:="60,45"            # shared chest fixture, owner B
const JIN:="jinguashi"
const JIN_CELL:="20,30"            # private chest fixture, owner B
const NOW:=925.0
const FIXED_UTC:=1800000000.0
const WHERES:=["home_chest","home_private","lan_chest","jin_private"]
var checks:=0
var failures:=0
var path:=""

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+message)

func valid(s:Dictionary)->bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func same(a,b)->bool:
	return History.canonical(a)==History.canonical(b)

func hid(n:int)->String:
	return "%032x"%n

func json(s:Dictionary)->Dictionary:
	return JSON.parse_string(JSON.stringify(s))

func write_candidate(candidate:Dictionary)->void:
	# A stale .bak would let load_world recover instead of reporting rejection.
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(candidate));f.close()

func _write_and_path(candidate:Dictionary)->String:
	write_candidate(candidate)
	return path

func fixed_world()->World:
	var w:=World.new()
	w.undo_clock_utc=func():return FIXED_UTC
	w.undo_clock_ticks=func():return 1000
	return w

## Loads a candidate through the real World file path; null when rejected.
func load_real(candidate:Dictionary):
	write_candidate(candidate)
	var w:=fixed_world()
	if not w.load_world(path):return null
	return w

func box(s:Dictionary,where:String)->Dictionary:
	match where:
		"home_chest":return s.objects[World.key(CHEST)]
		"home_private":return s.objects[World.key(PRIVATE)]
		"lan_chest":return s.regions[LAN].objects[LAN_CELL]
	return s.regions[JIN].objects[JIN_CELL]

func with_ids(base:Dictionary,version:int,ids:Dictionary)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.version=version
	if int(s.version)<25:
		s.erase("flower_nursery")
		s.regions.erase("tianwei")
		s.erase("salt_pan")
		s.regions.erase("beimen")
	if version<23:s.erase("public_kitchen")
	for where in ids:box(s,where).box_id=ids[where]
	return s

func layers_of(s:Dictionary)->Array:
	var out:Array=[s]
	for region in s.regions:out.append(s.regions[region])
	return out

func box_id_count(s:Dictionary)->int:
	var n:=0
	for layer in layers_of(s):
		for field in ["objects","ground","roofs"]:
			for obj in layer[field].values():
				if obj is Dictionary and obj.has("box_id"):n+=1
	return n

func live_objects(s:Dictionary)->String:
	var all:Dictionary={"home":s.objects}
	for region in s.regions:all[region]=s.regions[region].objects
	# Migration adds an empty region, not a live chest. Include its expected
	# empty layer before migration; actual post-migration objects remain compared.
	if int(s.version)<25 and not all.has("tianwei"):all.tianwei={}
	if int(s.version)<26 and not all.has("beimen"):all.beimen={}
	return History.canonical(all)

func fixture()->Dictionary:
	var world:=fixed_world()
	world.add_player(A,"箱子主人")
	world.add_player(B,"箱子朋友")
	world.state.time=NOW
	world.state.players[A].x=48.5
	world.state.players[A].y=26.5
	world.state.players[A].inventory.wood=100
	check(world.act(A,"fixture-floor","build",FLOOR,"floor").ok,"fixture: real floor build")
	check(world.act(A,"fixture-chest","build",CHEST,"chest").ok,"fixture: real shared chest build")
	var priv:=world.act(A,"fixture-private","build",PRIVATE,"private_chest")
	check(priv.ok,"fixture: real private chest build: %s"%priv.get("message",""))
	var s:=json(world.state)
	s.objects[SAW_CELL]={"type":"sawmill","owner":A,"items":{},"input_wood":0,"auto_enabled":false}
	s.objects[TABLE_CELL]={"type":"table","owner":A,"items":{}}
	s.regions[LAN].objects[LAN_CELL]={"type":"chest","owner":B,"items":{"wood":2}}
	s.regions[JIN].objects[JIN_CELL]={"type":"private_chest","owner":B,"items":{"stone":1}}
	s.unrelated_future_note={"keep":["me",1]}
	return json(s)

func _initialize()->void:run.call_deferred()

func run()->void:
	path="user://material-source-schema-%d.json"%Time.get_ticks_usec()

	# --- constants / literal cutoffs ---------------------------------------------
	check(Schema.VERSION==26,"save schema version is 22")
	check(Schema.MATERIAL_SOURCE_VERSION==22,"material source cutoff literal is 22")
	check(Schema.PROCESSING_QUEUE_VERSION==21,"processing queue cutoff literal stays 21")
	check(Schema.COOKING_QUEUE_VERSION==20,"cooking queue cutoff literal stays 20")
	check(Schema.BLUEPRINT_HISTORY_VERSION==19,"blueprint cutoff literal stays 19")
	check(Schema.BOX_TYPES==["chest","private_chest"],"box_id only on chest/private_chest")
	check(Schema.valid_box_id(hid(1)) and not Schema.valid_box_id(hid(1).to_upper().replace("0","A")),"valid_box_id helper: lowercase hex only")

	# --- baseline: real builds never inject an id ---------------------------------
	var base:=fixture()
	check(int(base.version)==26,"fresh World writes version 22")
	for where in WHERES:
		check(box(base,where).type in Schema.BOX_TYPES and not box(base,where).has("box_id"),"%s: no box_id injected by build/fixture"%where)
	check(base.construction.last.has(A) and base.construction.last[A].status=="live","fixture: A has a live history entry")
	var base_watch:Dictionary=base.construction.last.get(A,{}).get("watch",{})
	check(History.watch_matches(base,base_watch),"fixture: live watch matches the fixture state (precondition)")
	var plain:Dictionary=base.duplicate(true)
	check(valid(plain) and int(plain.version)==26,"v22 chests without box_id accepted")
	check(box_id_count(plain)==0,"validation never invents box_id")
	check(live_objects(plain)==live_objects(base),"v22 live objects unchanged by validation")
	var live=load_real(base)
	check(live!=null,"real World loads the baseline file")
	if live==null:
		print("MATERIAL_SOURCE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures]);quit(1);return

	# --- v22 ids accepted, preserved and round-tripped ----------------------------
	var ids:={"home_chest":hid(1),"home_private":hid(2),"lan_chest":hid(3),"jin_private":"0123456789abcdef0123456789abcdef"}
	var full:=with_ids(base,22,ids)
	var full_input:Dictionary=full.duplicate(true)
	check(valid(full) and int(full.version)==26,"v22 box_ids on home + regional chests accepted")
	for where in WHERES:check(box(full,where).get("box_id")==ids[where],"%s: box_id preserved exactly"%where)
	check(live_objects(full)==live_objects(full_input),"validated v22 live objects byte-identical")
	var partial:=with_ids(base,22,{"lan_chest":hid(9)})
	check(valid(partial) and box_id_count(partial)==1,"some chests with id, others lazily without: accepted, nothing added")
	check(valid(json(full_input)),"JSON round-trip of box_ids accepted")
	var real=load_real(full_input)
	check(real!=null,"real World loads v22 box_id file")
	if real!=null:
		for where in WHERES:check(box(real.state,where).get("box_id")==ids[where],"real load keeps %s box_id"%where)
		check(real.save(),"real World saves box_ids")
		var text:=FileAccess.get_file_as_string(path)
		var parsed=JSON.parse_string(text)
		check(parsed is Dictionary and int(parsed.get("version",0))==Schema.VERSION,"saved document uses current schema")
		var again:=fixed_world()
		check(again.load_world(path),"saved box_id file reloads")
		for where in WHERES:check(box(again.state,where).get("box_id")==ids[where],"disk round-trip keeps %s box_id"%where)
		check(live_objects(again.state)==live_objects(real.state),"disk round-trip live objects identical")

	# --- malformed / typed / length: rejected, kept as-is, live World untouched ---
	var bad:={"upper":"0123456789ABCDEF0123456789abcdef","short31":"a".repeat(31),"long33":"a".repeat(33),
		"nonhex":"g"+"a".repeat(31),"prefix0x":"0x"+"a".repeat(30),"space":" "+"a".repeat(31),"empty":"",
		"fullwidth":"ａ"+"a".repeat(31),"number":12345,"float":1.5,"null":null,"bool":true,
		"array":[hid(9)],"dict":{"id":hid(9)}}
	for where in WHERES:
		for name in bad:
			var s:=with_ids(base,22,{})
			box(s,where).box_id=bad[name]
			var copy:Dictionary=s.duplicate(true)
			check(not valid(copy),"%s: %s box_id rejected"%[where,name])
			check(box(copy,where).has("box_id") and same(box(copy,where).box_id,bad[name]),"%s: %s rejected id kept for inspection, not stripped"%[where,name])
			var before:String=History.canonical(live.state)
			check(not live.load_world(_write_and_path(s)),"%s: %s rejected by real World load"%[where,name])
			check(History.canonical(live.state)==before,"%s: %s rejection leaves live World untouched"%[where,name])
	# Wrong owner object types / layers.
	var on_saw:=with_ids(base,22,{});on_saw.objects[SAW_CELL].box_id=hid(20)
	check(not valid(on_saw),"box_id on sawmill rejected")
	var on_table:=with_ids(base,22,{});on_table.objects[TABLE_CELL].box_id=hid(21)
	check(not valid(on_table),"box_id on table rejected")
	var on_floor:=with_ids(base,22,{});on_floor.ground[World.key(FLOOR)].box_id=hid(22)
	check(not valid(on_floor),"box_id on floor (ground layer) rejected")
	var roofed:=with_ids(base,22,{});roofed.roofs[World.key(FLOOR)]={"type":"roof","owner":A,"items":{}}
	check(valid(roofed.duplicate(true)),"control: manual roof without box_id accepted")
	roofed.roofs[World.key(FLOOR)].box_id=hid(23)
	check(not valid(roofed),"box_id on roof rejected")
	var regional_saw:=with_ids(base,22,{})
	regional_saw.regions[LAN].objects[LAN_CELL]={"type":"sawmill","owner":B,"items":{},"input_wood":0,"auto_enabled":false,"box_id":hid(24)}
	check(not valid(regional_saw),"box_id on regional sawmill rejected")
	check(not live.load_world(_write_and_path(on_saw)),"real World rejects box_id on sawmill")

	# --- global live uniqueness ---------------------------------------------------
	for pair in [["home_chest","home_private"],["home_chest","lan_chest"],["lan_chest","jin_private"],["home_private","jin_private"]]:
		var dup:=with_ids(base,22,{pair[0]:hid(30),pair[1]:hid(30)})
		check(not valid(dup),"duplicate box_id %s/%s rejected"%pair)
		check(box(dup,pair[0]).box_id==hid(30) and box(dup,pair[1]).box_id==hid(30),"duplicate ids kept as-is on rejection")
		check(not live.load_world(_write_and_path(dup)),"real World rejects duplicate %s/%s"%pair)
		var distinct:=with_ids(base,22,{pair[0]:hid(31),pair[1]:hid(32)})
		check(valid(distinct),"control: distinct ids %s/%s accepted"%pair)

	# --- older versions carrying box_id: rejected, never stripped or stamped ------
	for version in [21,20,19,18,17]:
		for where in ["home_private","lan_chest"]:
			var s:=with_ids(base,version,{where:hid(40)})
			if version<18:s.erase("construction")
			var copy:Dictionary=s.duplicate(true)
			check(not valid(copy),"v%d %s box_id rejected"%[version,where])
			check(int(copy.version)==version,"v%d rejection did not stamp version"%version)
			check(box(copy,where).get("box_id")==hid(40),"v%d forward box_id kept, not stripped"%version)
		var v_bad:=with_ids(base,version,{"jin_private":hid(41)})
		if version<18:v_bad.erase("construction")
		check(not live.load_world(_write_and_path(v_bad)),"real World rejects v%d box_id"%version)
	var future:=with_ids(base,Schema.VERSION+1,{})
	check(not valid(future),"future version rejected")

	# --- old saves: no eager migration, history digests preserved ----------------
	for version in [21,20,19,18]:
		var s:=with_ids(base,version,{})
		var objects_before:=live_objects(s)
		var history_before:=History.fingerprint(s.construction)
		check(valid(s) and int(s.version)==26,"v%d save without box_id accepted -> 22"%version)
		check(box_id_count(s)==0,"v%d: no box_id assigned on load"%version)
		check(live_objects(s)==objects_before,"v%d: every live object unchanged (no eager migration)"%version)
		check(History.fingerprint(s.construction)==history_before,"v%d: construction history canonical digest unchanged"%version)
		check(History.watch_matches(s,s.construction.last.get(A,{}).get("watch",{})),"v%d: live undo watch still matches (chest tiles untouched)"%version)
		check(same(s.unrelated_future_note,{"keep":["me",1]}),"v%d: unrelated state kept"%version)
	# Real World: a v21 file loads, saves as 22 and reloads with nothing injected.
	var v21:=with_ids(base,21,{})
	var v21_objects:=live_objects(v21)
	var v21_history:=History.fingerprint(v21.construction)
	var w21=load_real(v21)
	check(w21!=null and int(w21.state.version)==26,"real World loads v21 file as 22")
	if w21!=null:
		check(box_id_count(w21.state)==0 and live_objects(w21.state)==v21_objects,"real v21 load: live chests unchanged, no box_id")
		check(History.fingerprint(w21.state.construction)==v21_history,"real v21 load: history digest unchanged")
		check(w21.save(),"migrated v21 world saves")
		check(not FileAccess.get_file_as_string(path).contains("box_id"),"saved migrated file contains no box_id")
		var re:=fixed_world()
		check(re.load_world(path) and int(re.state.version)==26,"migrated file reloads at 22")
		check(live_objects(re.state)==v21_objects and History.fingerprint(re.state.construction)==v21_history,"disk round-trip keeps objects and history digest")

	# --- prior migrations keep their literal cutoffs -------------------------------
	var proc20:=with_ids(base,20,{});proc20.objects[SAW_CELL].processing=Queue.empty_state()
	check(not valid(proc20),"processing cutoff unchanged: v20 processing rejected")
	var proc21:=with_ids(base,21,{});proc21.objects[SAW_CELL].processing=Queue.empty_state()
	check(valid(proc21) and int(proc21.version)==26,"v21 processing migrates to 22")
	var cook19:=with_ids(base,19,{});cook19.regions[JIN].objects[JIN_CELL]={"type":"stove","owner":B,"items":{},"cooking":Queue.empty_state()}
	check(not valid(cook19),"cooking cutoff unchanged: v19 cooking rejected")
	var cook20:=with_ids(base,20,{});cook20.regions[JIN].objects[JIN_CELL]={"type":"stove","owner":B,"items":{},"cooking":Queue.empty_state()}
	check(valid(cook20) and int(cook20.version)==26,"v20 cooking migrates to 22")
	var v18:=with_ids(base,18,{})
	var v18_history:Dictionary=v18.construction.duplicate(true)
	check(valid(v18) and same(v18.construction,v18_history),"v18 undo history preserved to 22")
	var v17:=with_ids(base,17,{})
	check(valid(v17) and v17.construction==History.fresh(),"pre-18 cutoff unchanged: history replaced with fresh")
	var bp:Dictionary=base.duplicate(true)
	bp.construction.last[A].action="blueprint"
	bp.construction.last[A].builds=26
	var bp19:Dictionary=bp.duplicate(true);bp19.version=19;bp19.erase("public_kitchen")
	if int(bp19.version)<25:
		bp19.erase("flower_nursery")
		bp19.regions.erase("tianwei")
		bp19.erase("salt_pan")
		bp19.regions.erase("beimen")
	check(valid(bp19) and bp19.construction.last[A].action=="blueprint","v19 blueprint history migrates intact")
	var bp18:Dictionary=bp.duplicate(true);bp18.version=18;bp18.erase("public_kitchen")
	if int(bp18.version)<25:
		bp18.erase("flower_nursery")
		bp18.regions.erase("tianwei")
		bp18.erase("salt_pan")
		bp18.regions.erase("beimen")
	check(not valid(bp18),"pre-19 cutoff unchanged: v18 blueprint history rejected")
	var auto_roof:Dictionary=base.duplicate(true)
	auto_roof.roofs[World.key(FLOOR)]={"type":"roof","owner":A,"items":{},"auto":true}
	var r17:Dictionary=auto_roof.duplicate(true);r17.version=17;r17.erase("public_kitchen");r17.erase("construction")
	if int(r17.version)<25:
		r17.erase("flower_nursery")
		r17.regions.erase("tianwei")
		r17.erase("salt_pan")
		r17.regions.erase("beimen")
	check(valid(r17),"v17 auto roof accepted")
	var r16:Dictionary=auto_roof.duplicate(true);r16.version=16;r16.erase("public_kitchen");r16.erase("construction")
	if int(r16.version)<25:
		r16.erase("flower_nursery")
		r16.regions.erase("tianwei")
		r16.erase("salt_pan")
		r16.regions.erase("beimen")
	check(not valid(r16),"pre-17 cutoff unchanged: v16 auto roof rejected")

	check(box_id_count(live.state)==0,"live World never adopted a rejected box_id")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MATERIAL_SOURCE_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
