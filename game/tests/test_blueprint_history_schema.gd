extends SceneTree
## Save schema 19 / construction history "blueprint" action (schema-only; the
## World/Session blueprint integration is covered by test_blueprint_world.gd).
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const History=preload("res://scripts/construction_history.gd")
const A:="blueprint-history-owner"
const AT:=Vector2i(50,26)
var checks:=0
var failures:=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func valid(s:Dictionary)->bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func same(a,b)->bool:
	return History.canonical(a)==History.canonical(b)

func with_entry(base:Dictionary,version:int,action,builds,terminal:bool=false,reason:String="untracked")->Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.version=version
	if version<25:
		s.erase("flower_nursery")
		s.regions.erase("tianwei")
		s.erase("salt_pan")
		s.regions.erase("beimen")
	if version<23:s.erase("public_kitchen")
	var entry:Dictionary=s.construction.last[A]
	entry.action=action
	entry.builds=builds
	if terminal:
		entry.status="invalid" if reason!="consumed" else "consumed"
		entry.reason=reason
		entry.record={}
		entry.watch={}
	return s

func _initialize()->void:run.call_deferred()

func run()->void:
	check(Schema.VERSION==27,"save schema version is 21")
	check(History.MAX_BLUEPRINT_BUILDS==768,"blueprint history limit is 768")
	check(History.MAX_AREA==49 and World.BASIC_BUILD_AREA==25,"History accepts up to 49 tiles while base construction stays at 25")
	check("blueprint" in History.ACTIONS,"blueprint is a whitelisted history action")

	var world:=World.new()
	world.add_player(A,"藍圖紀錄")
	world.undo_clock_utc=func():return 1800000000.0
	world.undo_clock_ticks=func():return 1000
	world.state.players[A].x=48.5
	world.state.players[A].y=26.5
	world.state.players[A].inventory.wood=100
	check(world.act(A,"build","build",AT,"floor").ok,"real construction creates a live history record")
	var baseline:Dictionary=JSON.parse_string(JSON.stringify(world.state))
	check(baseline.construction.last[A].status=="live","fixture entry is live")
	check(valid(baseline.duplicate(true)),"fixture validates")

	# --- blueprint accepted: live record and terminal record --------------------
	for n in [1,26,768]:
		var live:=with_entry(baseline,19,"blueprint",n)
		check(valid(live) and int(live.version)==preload("res://scripts/save_schema.gd").VERSION,"live blueprint builds=%d accepted"%n)
		check(live.construction.last[A].action=="blueprint" and int(live.construction.last[A].builds)==n and live.construction.last[A].status=="live","live blueprint builds=%d preserved"%n)
		var trip:Dictionary=JSON.parse_string(JSON.stringify(live))
		check(valid(trip) and int(trip.construction.last[A].builds)==n,"live blueprint builds=%d survives JSON round-trip"%n)
		for reason in ["untracked","changed","used","expired","clock","consumed"]:
			var done:=with_entry(baseline,19,"blueprint",n,true,reason)
			check(valid(done),"terminal (%s) blueprint builds=%d accepted"%[reason,n])
	check(valid(with_entry(baseline,19,"blueprint",26.0)),"whole JSON float 26.0 accepted for blueprint")
	check(History.builds_valid("blueprint",1) and History.builds_valid("blueprint",26) and History.builds_valid("blueprint",768),"builds_valid blueprint 1/26/768")

	# --- blueprint builds rejected ----------------------------------------------
	var bad_builds:Array=[769,0,-1,1000,true,false,26.5,0.5,768.5,NAN,INF,-INF,"26",null,[26],{"n":26}]
	for b in bad_builds:
		check(not History.builds_valid("blueprint",b),"builds_valid rejects blueprint builds=%s"%str(b))
		check(not valid(with_entry(baseline,19,"blueprint",b)),"live blueprint builds=%s rejected"%str(b))
		check(not valid(with_entry(baseline,19,"blueprint",b,true)),"terminal blueprint builds=%s rejected"%str(b))
		var probe:Dictionary=with_entry(baseline,19,"blueprint",b,true)
		check(not History.entry_basic(probe.construction.last[A]),"entry_basic rejects blueprint builds=%s"%str(b))
	var ok_probe:Dictionary=with_entry(baseline,19,"blueprint",768,true)
	check(History.entry_basic(ok_probe.construction.last[A]),"entry_basic accepts terminal blueprint 768")

	# --- ordinary action limits unchanged ---------------------------------------
	var ordinary:={
		"build":{"ok":[1],"bad":[0,2,25,26,768,1.5,true]},
		"build_area":{"ok":[1,2,25,26,49],"bad":[0,50,768,24.5,true,-1]},
		"remove":{"ok":[0],"bad":[1,25,768,0.5,false]},
		"move_object":{"ok":[0],"bad":[1,25,768,0.5,false]},
	}
	for action in ordinary:
		for b in ordinary[action].ok:
			check(History.builds_valid(action,b),"%s builds=%s still valid"%[action,str(b)])
			check(valid(with_entry(baseline,19,action,b,true)),"terminal %s builds=%s accepted"%[action,str(b)])
			check(valid(with_entry(baseline,18,action,b,true)),"v18 terminal %s builds=%s accepted"%[action,str(b)])
		for b in ordinary[action].bad:
			check(not History.builds_valid(action,b),"%s builds=%s still invalid"%[action,str(b)])
			check(not valid(with_entry(baseline,19,action,b,true)),"terminal %s builds=%s rejected"%[action,str(b)])
			check(not valid(with_entry(baseline,19,action,b)),"live %s builds=%s rejected"%[action,str(b)])

	# --- unknown actions rejected ----------------------------------------------
	for action in ["blueprints","Blueprint","BLUEPRINT","blueprint ","","undo_build","build_blueprint",5,null,true,["blueprint"]]:
		check(not History.builds_valid(action,1),"builds_valid rejects action %s"%str(action))
		check(not valid(with_entry(baseline,19,action,1)),"live action %s rejected"%str(action))
		check(not valid(with_entry(baseline,19,action,1,true)),"terminal action %s rejected"%str(action))
		var probe:Dictionary=with_entry(baseline,19,action,1,true)
		check(not History.entry_basic(probe.construction.last[A]),"entry_basic rejects action %s"%str(action))

	# --- migrations --------------------------------------------------------------
	var v18:Dictionary=baseline.duplicate(true)
	v18.version=18;v18.erase("public_kitchen")
	v18.erase("flower_nursery")
	v18.regions.erase("tianwei")
	v18.erase("salt_pan")
	v18.regions.erase("beimen")
	var v18_history:Dictionary=v18.construction.duplicate(true)
	var v18_players:Dictionary=v18.players.duplicate(true)
	var v18_ground:Dictionary=v18.ground.duplicate(true)
	check(valid(v18) and int(v18.version)==preload("res://scripts/save_schema.gd").VERSION,"v18 live history migrates to 20")
	# Validation normalises whole JSON floats to int, so compare canonically.
	check(same(v18.construction,v18_history),"v18 live history preserved exactly on migration")
	check(v18.construction.last[A].status=="live" and v18.construction.last[A].action=="build","v18 live record still live after migration")
	check(same(v18.players[A].inventory,v18_players[A].inventory) and int(v18.players[A].builds)==int(v18_players[A].builds),"v18 migration keeps inventory and builds counter")
	check(same(v18.ground,v18_ground),"v18 migration keeps construction layers")
	var v18_done:=with_entry(baseline,18,"build",1,true,"expired")
	var v18_done_history:Dictionary=v18_done.construction.duplicate(true)
	check(valid(v18_done) and same(v18_done.construction,v18_done_history),"v18 terminal history preserved on migration")
	var v18_area:=with_entry(baseline,18,"build_area",25)
	check(valid(v18_area) and v18_area.construction.last[A].action=="build_area" and int(v18_area.construction.last[A].builds)==25,"v18 build_area 25 history preserved")
	check(not valid(with_entry(baseline,18,"blueprint",26)),"pre-19 save cannot carry blueprint history")
	check(not valid(with_entry(baseline,18,"blueprint",1,true)),"pre-19 terminal blueprint history rejected")
	var v17:Dictionary=baseline.duplicate(true)
	v17.version=17;v17.erase("public_kitchen")
	v17.erase("flower_nursery")
	v17.regions.erase("tianwei")
	v17.erase("salt_pan")
	v17.regions.erase("beimen")
	v17.erase("construction")
	check(valid(v17) and int(v17.version)==preload("res://scripts/save_schema.gd").VERSION and v17.construction==History.fresh(),"v17 migrates to 20 with fresh (empty) history")
	var v17_with:Dictionary=baseline.duplicate(true)
	v17_with.version=17;v17_with.erase("public_kitchen")
	v17_with.erase("flower_nursery")
	v17_with.regions.erase("tianwei")
	v17_with.erase("salt_pan")
	v17_with.regions.erase("beimen")
	check(valid(v17_with) and v17_with.construction==History.fresh(),"pre-18 cutoff unchanged: stray history replaced, never adopted")
	var future:Dictionary=baseline.duplicate(true)
	future.version=Schema.VERSION+1
	check(not valid(future),"future version rejected")

	check(world.state.construction.last[A].action=="build" and world.state.construction.last[A].status=="live","schema checks never touched live world")
	print("BLUEPRINT_HISTORY_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
