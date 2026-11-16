extends SceneTree
## Q05 public kitchen -> flour mill guidance (public_kitchen.gd mill_guide +
## opening story lines; public_kitchen_ui.gd Query.mill_guide wiring).
## Hand-built state Dictionaries only (no World mutation, no saves). Checks:
##  - no mill guidance before the kitchen opens (none / locked / collect / bad data)
##  - story stays exactly 3 pages with the same ids; opening page has Aru+Milu
##    mill lines without hard-coded quantities
##  - events()/mill_guide() are read-only and stable over repeated replay
##  - guide quantities/yields/times come from World data, not literals
##  - public_kitchen.gd still does not preload World
## Run: godot --headless --path game --script res://tests/test_mill_story.gd
const World=preload("res://scripts/world.gd")
const PK=preload("res://scripts/public_kitchen.gd")
const UI=preload("res://scripts/public_kitchen_ui.gd")
const IDS:=["kitchen_invitation","kitchen_registration","kitchen_opening"]
const REPLAYS:=3
var checks:=0
var failures:=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+message)

func kitchen(meals:Dictionary,opened:bool)->Dictionary:
	return {"stove":"40,30","seats":["41,31","42,31"],"meals":meals,"opened":opened}

func states()->Dictionary:
	return {
		"none":{},
		"no_picnic":{"picnic":false,"public_kitchen":PK.fresh()},
		"locked":{"picnic":true,"public_kitchen":PK.fresh()},
		"collect":{"picnic":true,"public_kitchen":kitchen({"soup":4,"bread":1,"salad":2},false)},
		"bad_opened":{"picnic":true,"public_kitchen":kitchen({"soup":1,"bread":0,"salad":0},true)},
		"open":{"picnic":true,"public_kitchen":kitchen(PK.REQUIREMENTS.duplicate(),true)},
	}

func tables()->Dictionary:
	return UI.Query.mill_tables()

func ids(events:Array)->Array:
	var out:=[]
	for e in events:out.append(str(e.id))
	return out

func _init()->void:
	var all:=states()
	# --- dependency: pure core must not preload World ---------------------------
	var source:=FileAccess.get_file_as_string("res://scripts/public_kitchen.gd")
	check(not source.is_empty(),"public_kitchen.gd readable")
	check(not source.contains("scripts/world.gd"),"public_kitchen.gd does not reference/preload World")
	# --- no guidance before opened ----------------------------------------------
	for id in ["none","no_picnic","locked","collect","bad_opened"]:
		check(PK.mill_guide(all[id],tables()).is_empty(),"no mill guide in state '%s'"%id)
		check(UI.Query.mill_guide(all[id]).is_empty(),"UI Query: no mill guide in state '%s'"%id)
	check(PK.stage(all.collect)=="collect" and PK.stage(all.open)=="open","fixture stages collect/open")
	# --- story pages: same count and ids ----------------------------------------
	check(PK.events(all.none).is_empty() and PK.events(all.no_picnic).is_empty(),"no pages before picnic")
	check(ids(PK.events(all.locked))==IDS.slice(0,1),"1 page after picnic")
	check(ids(PK.events(all.collect))==IDS.slice(0,2),"2 pages after registration")
	check(ids(PK.events(all.open))==IDS,"exactly 3 pages with same ids after opening: %s"%str(ids(PK.events(all.open))))
	check(ids(UI.Query.events(all.open))==IDS,"UI uses core events (same 3 ids)")
	var opening:Dictionary=PK.events(all.open)[2]
	var mill_npcs:={}
	var digits:=RegEx.create_from_string("[0-9０-９]")
	for line in opening.lines:
		if str(line.text).contains("磨坊"):
			mill_npcs[str(line.npc)]=true
			check(digits.search(str(line.text))==null,"mill story line has no hard-coded quantity: "+str(line.text))
	check(mill_npcs.has("aru") and mill_npcs.has("milu"),"opening page has Aru and Milu mill lines")
	# --- read-only, repeated replay ---------------------------------------------
	var before:=JSON.stringify(all.open)
	var first_events:=JSON.stringify(PK.events(all.open))
	var first_guide:=JSON.stringify(PK.mill_guide(all.open,tables()))
	for i in REPLAYS:
		var ev:=PK.events(all.open)
		check(ev.size()==3 and JSON.stringify(ev)==first_events,"replay %d: identical 3 pages"%i)
		ev[2].lines.clear() # mutating a returned copy must not leak
		var guide:=PK.mill_guide(all.open,tables())
		check(JSON.stringify(guide)==first_guide,"replay %d: identical guide"%i)
		guide[0].inputs.clear()
	check(JSON.stringify(all.open)==before,"state untouched by events/mill_guide")
	check(JSON.stringify(PK.events(all.open))==first_events,"returned pages are deep copies")
	check(JSON.stringify(PK.mill_guide(all.open,tables()))==first_guide,"returned guide is fresh each call")
	# --- guide data comes from World tables ---------------------------------------
	var guide:=PK.mill_guide(all.open,tables())
	check(ids(guide)==["mill_kit","mill","flour","pumpkin_pie"],"guide order kit -> build -> flour -> pie: %s"%str(ids(guide)))
	if guide.size()==4:
		var expected:=[
			[World.CRAFT.mill_kit.ingredients,int(World.CRAFT.mill_kit.get("yield",1)),0],
			[{"mill_kit":int(World.BUILD.mill.mill_kit)},1,0],
			[World.INDUSTRY.PROCESS.flour.ingredients,int(World.INDUSTRY.PROCESS.flour["yield"]),int(World.INDUSTRY.PROCESS.flour.time)],
			[World.RECIPES.pumpkin_pie.ingredients,int(World.RECIPES.pumpkin_pie["yield"]),int(World.RECIPES.pumpkin_pie.time)],
		]
		for i in 4:
			var step:Dictionary=guide[i]
			var want:Dictionary={}
			for item in expected[i][0]:want[item]=int(expected[i][0][item])
			check(JSON.stringify(step.inputs)==JSON.stringify(want),"%s inputs match World data %s"%[step.id,JSON.stringify(want)])
			check(int(step["yield"])==int(expected[i][1]) and int(step.time)==int(expected[i][2]),"%s yield/time match World data"%step.id)
			for item in want:
				check(str(step.text).contains("%s×%d"%[World.NAMES.get(item,item),want[item]]),"%s text cites %s×%d"%[step.id,item,want[item]])
		check(World.INDUSTRY.PROCESS.flour.station=="mill","flour is processed at the mill")
		check(str(guide[1].text).contains("麵粉磨坊") and not str(guide[1].text).contains("mill"),"building step uses player-facing station name")
	check(JSON.stringify(UI.Query.mill_guide(all.open))==JSON.stringify(guide),"UI Query wires World tables into core")
	# --- not hard-coded: altered tables change the text; missing tables -> [] -----
	var altered:=tables().duplicate()
	var craft:Dictionary=World.CRAFT.duplicate(true)
	craft.mill_kit.ingredients={"plank":3}
	altered.craft=craft
	var alt:=PK.mill_guide(all.open,altered)
	check(alt.size()==4 and str(alt[0].text).contains("×3") and JSON.stringify(alt[0].inputs)==JSON.stringify({"plank":3}),"guide follows supplied data")
	for missing in ["craft","build","process","recipes"]:
		var partial:=tables().duplicate()
		partial.erase(missing)
		check(PK.mill_guide(all.open,partial).is_empty(),"missing '%s' table -> no stale guidance"%missing)
	for bad_yield in [0,-1,1.5,"one"]:
		var malformed:=tables().duplicate(true)
		malformed.recipes.pumpkin_pie["yield"]=bad_yield
		check(PK.mill_guide(all.open,malformed).is_empty(),"malformed yield cannot produce misleading guide")
	print("MILL_STORY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
