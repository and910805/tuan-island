extends SceneTree
## T039 basic weather: headless World-level integration tests.
##
## AUTOMATED TEST ONLY: this is NOT a human playtest and NOT a network test.
## Nothing here opens sockets, starts a server, or drives a client/UI; it uses
## fresh in-memory World objects whose save_path lives in a unique per-run
## user:// directory that is deleted afterwards (never touches player saves).
##
## Shared contract under test (written independently of weather.gd/world.gd):
## - Weather.at(time, region="home") -> {id, label, raining, day}; day is
##   one-based, one day is 1440 world seconds; 7-day cycle
##   sunny, cloudy, rainy, sunny, sunny, rainy, cloudy; mine_1..mine_5 indoor.
## - World.step(dt, false) freezes everything.
## - Rain wets outdoor, exposed, cultivated plots (planted or not, any owner);
##   a roof over the plot or an indoor (mine) region blocks it.
## - Every midnight (calendar day change of state.time) clears previous
##   watering; on a rainy day exposed plots are rewatered.
## - Growth integrates only wet seconds, exactly across day boundaries; mature
##   crops stay mature.
## - No new save fields / protocol: tests never assume a weather field.
##
## Layouts use the real validated World.act actions (hoe/seed/water/build/
## refill_sprinkler/toggle_sprinkler/harvest). Anything written directly into
## state is explicitly labelled below as a SEEDED ... FIXTURE.
const World=preload("res://scripts/world.gd")
const WEATHER_SCRIPT=preload("res://scripts/weather.gd")
const REGIONS=preload("res://scripts/regions.gd")
const MINES=preload("res://scripts/mine_depths.gd")
const SAVE_SCHEMA=preload("res://scripts/save_schema.gd")

const A:="tok-weather-alice"
const B:="tok-weather-bob"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const MINE:="mine_1"
const DAY:=1440.0
const CYCLE:=["sunny","cloudy","rainy","sunny","sunny","rainy","cloudy"]
const RADISH_TIME:=90.0
const PLOTS:=["pa","ua","pb","ra","lan","mine"]

var checks:=0
var failures:=0
var serial:=0
var rid:=0
var dir:=""
var wx

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-weather-world-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory created")
	expect(is_equal_approx(float(World.CROPS.radish.time),RADISH_TIME),"radish growth time unchanged (90s)")
	# Instance call works whether at() is static or not.
	wx=WEATHER_SCRIPT.new()
	test_weather_contract()
	test_inactive_freezes()
	test_rain_wets_exposed()
	test_dry_days_do_not_wet()
	test_clock_and_region_authority()
	test_midnight_clear_and_rewater()
	test_split_ticks_match_single()
	test_multi_day_big_dt()
	test_mature_remains()
	test_manual_watering_still_works()
	test_sprinkler_sunny_control()
	test_rain_spares_sprinkler()
	test_roofed_plot_sprinkler_on_rainy_day()
	test_save_load_stable()
	test_save_failure_rollback()
	test_no_new_fields()
	test_expanded_crop_catalog()
	cleanup()
	print("WEATHER_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func test_expanded_crop_catalog() -> void:
	var cases:=[
		["cauliflower",0,14,45,1,1],["sweet_corn",14,0,60,2,1],
		["strawberry",0,14,70,2,3],["cucumber",14,28,40,2,3],
		["cabbage",42,28,44,1,1],["sugar_beet",42,28,30,1,1],
		["sweet_potato",28,14,32,2,1],["eggplant",28,0,48,2,3],
		["watermelon",14,0,65,1,1],["ginger",42,28,45,2,1],["cotton",0,28,40,2,1],
	]
	for spec in cases:
		var w:=World.new()
		w.add_player(A,"Alice")
		var p:Dictionary=w.state.players[A]
		var kind:String=spec[0]
		var seed_id:=kind+"_seed"
		var coins:int=p.coins
		var stall:=Vector2i(43,29)
		p.x=42.5
		p.y=30.5
		expect(w.act(A,"buy-new", "buy",stall,kind).ok and p.coins==coins-int(spec[3]) and p.inventory.get(seed_id,0)==1,kind+": shop provides the right seed and price")
		var cell:=Vector2i(42,34)
		p.x=42.5
		p.y=33.5
		w.state.time=float(spec[2])*DAY+720.0
		expect(w.act(A,"hoe-new","hoe",cell).ok and w.act(A,"seed-new","seed",cell,kind).ok and w.act(A,"water-new","water",cell).ok,kind+": prepare, plant and water")
		var duration:float=World.CROPS[kind].time
		expect(w.step(duration,true) and float(w.state.crops[World.key(cell)].growth)==0.0,kind+": grows only in season")
		w.state.time=float(spec[1])*DAY+720.0
		expect(w.act(A,"water-season","water",cell).ok and w.step(duration,true),kind+": advances after returning to season")
		expect(w.act(A,"harvest-new","harvest",cell).ok and p.inventory.get(kind,0)==spec[4] and p.collection.crops.has(kind),kind+": correct harvest and collection entry")
		for cycle in range(1,int(spec[5])):
			expect(w.state.crops[World.key(cell)].kind==kind and w.state.crops[World.key(cell)].remaining==int(spec[5])-cycle,kind+": plant survives and keeps the rest of its harvests")
			expect(w.act(A,"rewater-%d"%cycle,"water",cell).ok and w.step(duration,true),kind+": regrows after watering")
			expect(w.act(A,"reharvest-%d"%cycle,"harvest",cell).ok and p.inventory.get(kind,0)==int(spec[4])*(cycle+1),kind+": regrowth yields another harvest")
		expect(w.state.crops[World.key(cell)].kind=="",kind+": final harvest clears the plant")
		var recipe:Dictionary=World.SEED_MAKER.recipes(World.CROPS).get(seed_id,{})
		if kind in World.SEED_MAKER.NURSERY_CROPS:
			expect(recipe.is_empty(),kind+": nursery flower uses the nursery seed bench")
		else:
			expect(recipe.ingredients=={kind:int(spec[4])*int(spec[5]),"charcoal":1} and recipe.yield==1,kind+": seed maker consumes the lifetime harvest plus charcoal")
		if kind=="watermelon":
			var stove:=Vector2i(40,33)
			p.inventory.merge({"wood":12,"stone":15},true)
			expect(w.act(A,"build-platter-stove","build",stove,"stove").ok,"Build a stove beside the watermelon farm")
			expect(w.act(A,"cut-watermelon","queue_cook",stove,"watermelon_platter").ok and p.inventory.get("watermelon",0)==0,"Cut up the harvested watermelon")
			expect(w.step(8.1,true) and w.act(A,"collect-platter","claim_cook",stove).ok,"Collect the prepared platter")
			expect(p.inventory.get("watermelon_platter",0)==4 and p.collection.meals.has("watermelon_platter"),"Four portions and a recipe discovery are recorded")

func cleanup() -> void:
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)

# ---------------------------------------------------------------- helpers --

func day_start(day:int) -> float:
	return float(day-1)*DAY

func expected_id(t:float) -> String:
	return CYCLE[int(floor(t/DAY))%CYCLE.size()]

func new_world():
	var w:=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	# SEEDED INVENTORY FIXTURE: extra seeds only, so act("seed") never runs out.
	for t in [A,B]:
		var inv:Dictionary=w.state.players[t].inventory
		inv.radish_seed=20
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	return w

func pose(w,token:String,c:Vector2i) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:Vector2=Vector2(c)+Vector2(0.5,2.5) if t==token else World.SPAWN
		person.x=spot.x;person.y=spot.y

func do(w,token:String,action:String,c:Vector2i,extra:String="") -> Dictionary:
	pose(w,token,c)
	rid+=1
	return w.act(token,"wx-%d"%rid,action,c,extra)

func cell_free(w,c:Vector2i) -> bool:
	var k:=World.key(c)
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	for field in ["objects","ground","roofs","crops","forest"]:
		if w.state[field].has(k):return false
	return true

## First naturally clear HOME rectangle (no resources removed, nothing seeded).
func find_block(w,size:Vector2i) -> Vector2i:
	for oy in range(30,56):
		for ox in range(3,76):
			var ok:=true
			for y in range(oy-1,oy+size.y+1):
				for x in range(ox-1,ox+size.x+1):
					if not cell_free(w,Vector2i(x,y)):ok=false;break
				if not ok:break
			if ok:return Vector2i(ox,oy)
	expect(false,"found a clear home block")
	return Vector2i(-1,-1)

func region_cell(region:String) -> Vector2i:
	for y in range(8,50):
		for x in range(8,60):
			var c:=Vector2i(x,y)
			if World.land(c,region) and not REGIONS.water(c,region) and not REGIONS.protected(c,region) and c not in MINES.NODES:
				return c
	expect(false,"found a land cell in "+region)
	return Vector2i(12,22)

func till(w,token:String,c:Vector2i,kind:String) -> void:
	expect(do(w,token,"hoe",c).ok,"validated hoe at %s"%World.key(c))
	if kind!="":expect(do(w,token,"seed",c,kind).ok,"validated seed %s at %s"%[kind,World.key(c)])

## Standard farm. pa/ua/pb/ra are made with validated World.act hoe+seed.
## pa: Alice planted, ua: Alice unplanted, pb: Bob planted, ra: Alice planted
## under a roof. lan/mine are regional plots.
func farm(time:float) -> Dictionary:
	var w=new_world()
	var o:=find_block(w,Vector2i(4,1))
	var f:={"w":w,"cell":{}}
	f.cell.pa=o;f.cell.ua=o+Vector2i(1,0);f.cell.pb=o+Vector2i(2,0);f.cell.ra=o+Vector2i(3,0)
	till(w,A,f.cell.pa,"radish")
	till(w,A,f.cell.ua,"")
	till(w,B,f.cell.pb,"radish")
	till(w,A,f.cell.ra,"radish")
	for name in ["pa","ua","pb","ra"]:f[name]=World.key(f.cell[name])
	# SEEDED ROOF FIXTURE: hoe refuses floors and roofs need floors, so a roof over
	# a plot cannot be produced through validated actions; a manual roof record is
	# written directly over the tilled plot.
	w.state.roofs[f.ra]={"type":"roof","owner":A,"items":{}}
	# SEEDED REGIONAL SOIL FIXTURES: one planted plot in Lanyang (outdoor) and one
	# in mine_1 (indoor), written directly into the regional layers.
	f.lan=World.key(region_cell(LANYANG))
	f.mine=World.key(region_cell(MINE))
	w.state.regions[LANYANG].crops[f.lan]={"kind":"radish","growth":0.0,"wet":false,"owner":A,"remaining":1}
	w.state.regions[MINE].crops[f.mine]={"kind":"radish","growth":0.0,"wet":false,"owner":A,"remaining":1}
	# SEEDED CLOCK FIXTURE: world time jumped directly to the scenario start.
	w.state.time=time
	return f

func plot(f:Dictionary,name:String) -> Dictionary:
	var w=f.w
	if name=="lan":return w.state.regions[LANYANG].crops.get(f.lan,{})
	if name=="mine":return w.state.regions[MINE].crops.get(f.mine,{})
	return w.state.crops.get(f[name],{})

func wet(f:Dictionary,name:String) -> bool:
	return bool(plot(f,name).get("wet",false))

func growth(f:Dictionary,name:String) -> float:
	return float(plot(f,name).get("growth",-1.0))

## SEEDED WET FIXTURE for regional plots (no validated way to reach them here).
func set_wet(f:Dictionary,name:String,value:bool) -> void:
	plot(f,name).wet=value

func water(f:Dictionary,name:String) -> void:
	expect(do(f.w,A,"water",f.cell[name]).ok,"validated manual water on "+name)

func summary(f:Dictionary) -> String:
	var parts:PackedStringArray=["t=%s"%str(float(f.w.state.time))]
	for name in PLOTS:parts.append("%s:%s/%s"%[name,str(wet(f,name)),str(growth(f,name))])
	return ",".join(parts)

func near(a:float,b:float) -> bool:
	return absf(a-b)<0.0001

func read_json(path:String):
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return null
	return parser.data

# ------------------------------------------------------------------ tests --

func test_weather_contract() -> void:
	for day in range(1,16):
		for offset in [0.0,1.0,720.0,DAY-0.5]:
			var t:float=day_start(day)+float(offset)
			var r=wx.at(t)
			expect(r is Dictionary,"at() returns a Dictionary")
			if not r is Dictionary:return
			expect(int(r.get("day",-1))==day,"day is one-based at t=%s"%str(t))
			expect(str(r.get("id",""))==expected_id(t),"cycle id at day %d (%s)"%[day,expected_id(t)])
			expect(bool(r.get("raining",null))==(expected_id(t)=="rainy"),"raining iff rainy at day %d"%day)
			expect(r.get("label") is String and not str(r.label).is_empty(),"non-empty label day %d"%day)
			expect(wx.at(t,HOME)==r,"default region is home")
	expect(wx.at(DAY-0.001).day==1 and wx.at(DAY).day==2,"day boundary is exactly 1440s")
	expect(wx.at(day_start(8)).id=="sunny" and wx.at(day_start(10)).raining,"cycle repeats after seven days")
	var rainy:=day_start(3)+100.0
	for region in [LANYANG,REGIONS.JINGUASHI]:
		expect(wx.at(rainy,region).id==wx.at(rainy).id and wx.at(rainy,region).raining,"same provisional climate outdoors in "+region)
	for region in MINES.IDS:
		var r=wx.at(rainy,region)
		expect(not bool(r.raining),"%s is indoor (no rain)"%region)
		expect(int(r.day)==3,"%s shares the calendar day"%region)
	expect(wx.at(rainy)==wx.at(rainy),"weather is a pure function of time")

func test_inactive_freezes() -> void:
	var f:=farm(DAY-5.0)
	water(f,"pa");water(f,"ra");set_wet(f,"mine",true);set_wet(f,"lan",true)
	var snap:=var_to_str(f.w.state)
	expect(f.w.step(100.0,false),"inactive step returns true")
	expect(var_to_str(f.w.state)==snap,"inactive across midnight: time, wet flags and growth frozen")
	f.w.state.time=day_start(3)+50.0 # SEEDED CLOCK FIXTURE: rainy day
	for name in ["pa","ra","mine","lan"]:set_wet(f,name,false) # SEEDED WET FIXTURE
	snap=var_to_str(f.w.state)
	expect(f.w.step(300.0,false),"inactive rainy step returns true")
	expect(var_to_str(f.w.state)==snap,"inactive on rainy day: nothing wets, nothing grows")
	expect(not wet(f,"pa") and not wet(f,"ua") and not wet(f,"pb"),"frozen plots stay dry")

func test_rain_wets_exposed() -> void:
	var f:=farm(day_start(3)+10.0)
	for name in PLOTS:expect(not wet(f,name),"rain fixture starts dry: "+name)
	expect(f.w.step(1.0,true),"rainy step commits")
	expect(wet(f,"pa"),"rain wets own planted exposed plot")
	expect(wet(f,"ua"),"rain wets unplanted cultivated plot")
	expect(wet(f,"pb"),"rain wets the other owner's plot")
	expect(not wet(f,"ra"),"roof blocks rain")
	expect(wet(f,"lan"),"rain wets outdoor Lanyang plot")
	expect(not wet(f,"mine"),"mine (cave) plot stays dry")
	expect(f.w._region==HOME,"home orientation after step")
	var saved=read_json(f.w.save_path)
	expect(saved is Dictionary and bool(saved.crops[f.pa].wet) and bool(saved.crops[f.ua].wet) and bool(saved.crops[f.pb].wet),"rain wetting was saved in the same step")
	expect(saved is Dictionary and not bool(saved.crops[f.ra].wet),"saved roofed plot still dry")
	# A plot cultivated mid-rain (validated hoe) is wetted on the next tick.
	var extra_cell:Vector2i=f.cell.pa+Vector2i(0,1)
	if cell_free(f.w,extra_cell):
		till(f.w,B,extra_cell,"")
		expect(f.w.step(1.0,true),"second rainy step commits")
		expect(bool(f.w.state.crops[World.key(extra_cell)].wet),"plot tilled during rain gets wet")
	expect(not wet(f,"ra") and not wet(f,"mine"),"protections hold over repeated rainy ticks")

func test_dry_days_do_not_wet() -> void:
	for day in [1,2,4,5,7]:
		var f:=farm(day_start(day)+30.0)
		f.w.step(5.0,true)
		var any:=false
		for name in PLOTS:any=any or wet(f,name)
		expect(not any,"no rain wetting on %s day %d"%[CYCLE[(day-1)%7],day])
		expect(near(growth(f,"pa"),0.0),"dry plot does not grow on day %d"%day)

func test_clock_and_region_authority() -> void:
	# Weather follows World state.time and the plot's region, not players.
	var f:=farm(day_start(6)+10.0)
	# SEEDED PLAYER-LOCATION FIXTURE: Alice stands in mine_1, Bob in Lanyang.
	f.w.state.players[A].region=MINE
	f.w.state.players[B].region=LANYANG
	f.w.step(1.0,true)
	expect(wet(f,"pa") and wet(f,"pb"),"home plots rained on regardless of owners' current regions")
	expect(not wet(f,"mine"),"mine plot dry even with its owner standing there")
	expect(wet(f,"lan"),"Lanyang plot wet on rainy day 6")
	var g:=farm(day_start(6)+10.0+DAY) # day 7 cloudy
	g.w.step(1.0,true)
	expect(not wet(g,"pa") and not wet(g,"lan"),"world clock (cloudy day 7) decides, not wall time")
	expect(str(wx.at(float(g.w.state.time)).id)=="cloudy","weather derived from World time is cloudy")

func test_midnight_clear_and_rewater() -> void:
	# Day 1 (sunny) -> day 2 (cloudy): every watering is cleared at midnight.
	var f:=farm(DAY-5.0)
	water(f,"pa");water(f,"ua");water(f,"ra")
	set_wet(f,"lan",true);set_wet(f,"mine",true)
	expect(f.w.step(10.0,true),"midnight step commits")
	expect(near(float(f.w.state.time),DAY+5.0),"clock advanced by dt")
	for name in PLOTS:expect(not wet(f,name),"midnight clears previous watering: "+name)
	for name in ["pa","ra","lan","mine"]:expect(near(growth(f,name),5.0),"only the 5 wet seconds before midnight grew: "+name)
	expect(near(growth(f,"pb"),0.0),"dry plot did not grow")
	var saved=read_json(f.w.save_path)
	expect(saved is Dictionary and not bool(saved.crops[f.pa].wet),"midnight clear was saved")
	# Day 2 (cloudy) -> day 3 (rainy): clear, then rain rewaters exposed plots.
	f.w.state.time=day_start(3)-5.0 # SEEDED CLOCK FIXTURE
	water(f,"pa");water(f,"ra");set_wet(f,"mine",true)
	f.w.step(10.0,true)
	expect(wet(f,"pa") and near(growth(f,"pa"),15.0),"watered exposed plot: rewatered by rain, grew all 10s")
	expect(wet(f,"pb") and near(growth(f,"pb"),5.0),"dry exposed plot grew only the 5 rainy seconds")
	expect(wet(f,"ua"),"unplanted plot rewatered by rain")
	expect(not wet(f,"ra") and near(growth(f,"ra"),10.0),"roofed plot cleared at midnight and not rewatered")
	expect(not wet(f,"mine") and near(growth(f,"mine"),10.0),"mine plot cleared at midnight and not rewatered")
	expect(wet(f,"lan") and near(growth(f,"lan"),10.0),"Lanyang plot rewatered by rain")
	# Day 3 (rainy) -> day 4 (sunny): rain-watering is also cleared.
	f.w.state.time=day_start(4)-5.0 # SEEDED CLOCK FIXTURE
	f.w.step(10.0,true)
	expect(not wet(f,"pa") and not wet(f,"pb") and not wet(f,"lan"),"rain watering cleared at next midnight")
	expect(near(growth(f,"pa"),20.0) and near(growth(f,"pb"),10.0),"growth stops at the sunny midnight")

func run_ticks(f:Dictionary,ticks:Array) -> void:
	for dt in ticks:expect(f.w.step(float(dt),true),"tick commits (dt=%s)"%str(dt))

func prepared(time:float) -> Dictionary:
	var f:=farm(time)
	water(f,"pa");water(f,"ra");set_wet(f,"mine",true)
	return f

func test_split_ticks_match_single() -> void:
	for start in [DAY-5.0,day_start(3)-5.0,day_start(4)-5.0,day_start(6)-5.0]:
		var single:=prepared(start)
		run_ticks(single,[10.0])
		for split in [[5.0,5.0],[3.0,7.0],[1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0],[4.5,0.5,5.0]]:
			var other:=prepared(start)
			run_ticks(other,split)
			expect(summary(other)==summary(single),"split ticks %s == single tick at t=%s (%s vs %s)"%[str(split),str(start),summary(other),summary(single)])

func test_multi_day_big_dt() -> void:
	# Day 4 sunny (20s left) -> day 5 sunny -> day 6 rainy (+15s). dt=1475.
	var start:=day_start(5)-20.0
	var dt:=day_start(6)+15.0-start
	var big:=prepared(start)
	set_wet(big,"lan",true)
	expect(big.w.step(dt,true),"multi-day big dt commits")
	expect(near(float(big.w.state.time),day_start(6)+15.0),"big dt reaches day 6")
	expect(wet(big,"pa") and near(growth(big,"pa"),35.0),"watered plot: 20s day 4 + 15s rainy day 6")
	expect(wet(big,"pb") and near(growth(big,"pb"),15.0),"dry plot: only 15s of day 6 rain")
	expect(not wet(big,"ra") and near(growth(big,"ra"),20.0),"roofed plot: only its day-4 watering")
	expect(not wet(big,"mine") and near(growth(big,"mine"),20.0),"mine plot: only its day-4 watering")
	expect(wet(big,"lan") and near(growth(big,"lan"),35.0),"Lanyang plot: day 4 watering + day 6 rain")
	var small:=prepared(start)
	set_wet(small,"lan",true)
	var ticks:=[]
	for i in range(25):ticks.append(59.0)
	run_ticks(small,ticks)
	expect(summary(small)==summary(big),"25 ticks of 59s == one 1475s tick (%s vs %s)"%[summary(small),summary(big)])
	# Seven full days from a rainy start: the wet window is bounded by rain days.
	var week:=farm(day_start(3))
	expect(week.w.step(7.0*DAY,true),"one-week dt commits")
	expect(near(growth(week,"pb"),RADISH_TIME),"crop matured inside the week (capped at its time)")
	expect(near(growth(week,"ra"),0.0) and near(growth(week,"mine"),0.0),"protected unwatered plots never grew during the week")

func test_mature_remains() -> void:
	var f:=farm(DAY-100.0)
	f.w.state.crops[f.pa].growth=RADISH_TIME-10.0 # SEEDED GROWTH FIXTURE
	water(f,"pa")
	f.w.step(300.0,true)
	expect(near(growth(f,"pa"),RADISH_TIME),"growth capped at maturity")
	expect(not wet(f,"pa"),"mature plot's watering cleared at midnight")
	f.w.step(3.0*DAY,true)
	expect(near(growth(f,"pa"),RADISH_TIME),"mature crop remains mature over dry and rainy days")
	var r:Dictionary=do(f.w,A,"harvest",f.cell.pa)
	expect(r.ok,"mature crop still harvestable after weather days")

func test_manual_watering_still_works() -> void:
	var f:=farm(day_start(1)+30.0)
	water(f,"pa");water(f,"ua")
	expect(wet(f,"pa") and wet(f,"ua"),"manual water on a sunny day wets planted and unplanted plots")
	expect(f.w.step(10.0,true),"sunny step commits")
	expect(wet(f,"pa") and near(growth(f,"pa"),10.0),"manually watered crop grows on a sunny day")
	expect(near(growth(f,"pb"),0.0),"unwatered sunny crop does not grow")
	f.w.state.time=day_start(3)+30.0 # SEEDED CLOCK FIXTURE
	f.w.step(1.0,true)
	water(f,"pb")
	expect(wet(f,"pb"),"manual water on an already rain-wet plot still succeeds")
	expect(do(f.w,A,"water",f.cell.ra).ok and wet(f,"ra"),"manual water reaches the roofed plot on a rainy day")
	var good:String=f.w.save_path
	f.w.state.time=day_start(4)+30.0 # SEEDED CLOCK FIXTURE
	f.w.step(1.0,true)
	set_wet(f,"pa",false) # SEEDED WET FIXTURE: dry plot so the rollback is observable
	f.w.save_path=dir+"/missing-subdir/world.json"
	pose(f.w,A,f.cell.pa)
	var snap:=var_to_str(f.w.state)
	rid+=1
	var r:Dictionary=f.w.act(A,"wx-%d"%rid,"water",f.cell.pa)
	expect(not r.ok and str(r.message).contains("保存失敗"),"manual water save failure reported")
	expect(var_to_str(f.w.state)==snap,"manual water save failure rolls back (plot dry, no receipt/commit)")
	f.w.save_path=good
	expect(f.w.act(A,"wx-%d"%rid,"water",f.cell.pa).ok and wet(f,"pa"),"manual water retry after storage recovers")

## Builds an own sprinkler through validated actions with an Alice plot above it.
## Returns {"w","s","e","r"} keys; r (roofed, left of the sprinkler) only if asked.
func sprinkler_farm(time:float,with_roof:bool) -> Dictionary:
	var w=new_world()
	var o:=find_block(w,Vector2i(3,3))
	var s:=o+Vector2i(1,1)
	var e:=s+Vector2i.UP
	var r:=s+Vector2i.LEFT
	till(w,A,e,"radish")
	if with_roof:till(w,A,r,"radish")
	# SEEDED INVENTORY FIXTURE: one sprinkler kit (the craft chain is covered elsewhere).
	w.state.players[A].inventory.sprinkler_kit=1
	expect(do(w,A,"build",s,"sprinkler").ok,"validated sprinkler build")
	expect(do(w,A,"refill_sprinkler",s).ok,"validated sprinkler refill")
	expect(do(w,A,"toggle_sprinkler",s).ok,"validated sprinkler enable")
	var device:Dictionary=w.state.objects[World.key(s)]
	# SEEDED NETWORK-WATER + CHAPTER FIXTURE: makes irrigation credit observable.
	device.network_water=int(device.water)
	w.state.chapter_one.shipped=true
	w.state.board=true
	if with_roof:
		# SEEDED ROOF FIXTURE (see farm()).
		w.state.roofs[World.key(r)]={"type":"roof","owner":A,"items":{}}
	w.state.time=time # SEEDED CLOCK FIXTURE
	device.next_water=time
	return {"w":w,"s":World.key(s),"e":World.key(e),"r":World.key(r)}

func test_sprinkler_sunny_control() -> void:
	var f:=sprinkler_farm(day_start(1)+30.0,false)
	var device:Dictionary=f.w.state.objects[f.s]
	expect(int(device.water)==World.SPRINKLER_CAPACITY and not bool(f.w.state.chapter_one.watered),"sunny control starts full, no credit")
	expect(f.w.step(1.0,true),"sunny sprinkler step commits")
	device=f.w.state.objects[f.s]
	expect(bool(f.w.state.crops[f.e].wet),"sunny: sprinkler still waters the dry own crop")
	expect(int(device.water)==World.SPRINKLER_CAPACITY-1,"sunny: sprinkler spends one water")
	expect(int(device.get("network_water",0))==World.SPRINKLER_CAPACITY-1,"sunny: network water spent")
	expect(bool(f.w.state.chapter_one.watered),"sunny: irrigation credit still granted by the sprinkler")

func test_rain_spares_sprinkler() -> void:
	var f:=sprinkler_farm(day_start(3)+30.0,false)
	expect(not bool(f.w.state.crops[f.e].wet),"rainy sprinkler fixture starts dry")
	expect(f.w.step(1.0,true),"rainy sprinkler step commits")
	var device:Dictionary=f.w.state.objects[f.s]
	expect(bool(f.w.state.crops[f.e].wet),"rainy: plot wet")
	expect(int(device.water)==World.SPRINKLER_CAPACITY,"rain does NOT consume sprinkler water")
	expect(int(device.get("network_water",0))==World.SPRINKLER_CAPACITY,"rain does NOT consume network water")
	expect(near(float(device.last_water),-1.0),"rain does not stamp sprinkler last_water")
	expect(not bool(f.w.state.chapter_one.watered),"rain does NOT grant irrigation credit")
	# Midnight crossing into a rainy day: rain rewaters first, sprinkler untouched.
	var g:=sprinkler_farm(day_start(6)-4.0,false)
	expect(do(g.w,A,"water",World.cell(g.e)).ok,"validated manual water before rainy midnight")
	g.w.state.objects[g.s].next_water=day_start(6)+100.0 # SEEDED FIXTURE: sprinkler idle until after midnight
	g.w.step(8.0,true)
	g.w.state.objects[g.s].next_water=float(g.w.state.time)
	g.w.step(1.0,true)
	expect(bool(g.w.state.crops[g.e].wet),"rainy midnight: plot rewatered")
	expect(int(g.w.state.objects[g.s].water)==World.SPRINKLER_CAPACITY and not bool(g.w.state.chapter_one.watered),"rainy midnight: sprinkler water and credit untouched")

func test_roofed_plot_sprinkler_on_rainy_day() -> void:
	var f:=sprinkler_farm(day_start(3)+30.0,true)
	f.w.step(1.0,true)
	var device:Dictionary=f.w.state.objects[f.s]
	expect(bool(f.w.state.crops[f.e].wet),"exposed plot wet by rain")
	expect(bool(f.w.state.crops[f.r].wet),"roofed plot still served by the sprinkler on a rainy day")
	expect(int(device.water)==World.SPRINKLER_CAPACITY-1,"only the roofed plot cost sprinkler water")

func test_save_load_stable() -> void:
	var f:=farm(day_start(3)+10.0)
	expect(f.w.step(1.0,true),"rainy step saved")
	var loaded:=World.new()
	expect(loaded.load_world(f.w.save_path),"saved rainy world loads and validates")
	expect(near(float(loaded.state.time),float(f.w.state.time)),"loaded clock equals saved clock (no real-time catch-up)")
	expect(str(wx.at(float(loaded.state.time)).id)==str(wx.at(float(f.w.state.time)).id),"loaded weather identical (still rainy)")
	var g:={"w":loaded,"cell":f.cell,"pa":f.pa,"ua":f.ua,"pb":f.pb,"ra":f.ra,"lan":f.lan,"mine":f.mine}
	expect(summary(g)==summary(f),"wet fields and growth stable across save/load (%s vs %s)"%[summary(g),summary(f)])
	# Existing Community migration adds its default on load, even before weather.
	var expected_keys:Array=f.w.state.keys()
	if not expected_keys.has("community"):expected_keys.append("community")
	expect(loaded.state.size()==expected_keys.size() and loaded.state.keys().all(func(k):return expected_keys.has(k)),"only the pre-existing community default may be added on load; no weather fields")
	# A second load, later in real time, still restores the exact saved state.
	OS.delay_msec(30)
	var again:=World.new()
	expect(again.load_world(f.w.save_path) and near(float(again.state.time),float(f.w.state.time)),"reload later: clock unchanged by wall time")
	# Offline period (nobody active) never advances weather/watering.
	loaded.save_path=dir+"/loaded-%d.json"%serial
	var snap:=var_to_str(loaded.state)
	loaded.step(5.0*DAY,false)
	expect(var_to_str(loaded.state)==snap,"offline (inactive) time does not catch up weather")
	# Continuing the live and the loaded worlds stays deterministic across midnights.
	f.w.step(2.0*DAY,true)
	loaded.step(2.0*DAY,true)
	expect(summary(g)==summary(f),"live and reloaded worlds agree after two more days (%s vs %s)"%[summary(g),summary(f)])
	var third:=World.new()
	expect(third.load_world(loaded.save_path),"post-midnight save loads")
	var h:={"w":third,"cell":f.cell,"pa":f.pa,"ua":f.ua,"pb":f.pb,"ra":f.ra,"lan":f.lan,"mine":f.mine}
	expect(summary(h)==summary(g),"post-midnight wet fields stable across save/load")

func test_save_failure_rollback() -> void:
	# Rain wetting fails to save -> entire tick rolled back.
	var f:=farm(day_start(3)+10.0)
	var good:String=f.w.save_path
	f.w.save_path=dir+"/missing-subdir/world.json"
	var snap:=var_to_str(f.w.state)
	expect(not f.w.step(1.0,true),"rain step reports save failure")
	expect(var_to_str(f.w.state)==snap,"rain save failure: no wetting, time and growth unchanged")
	expect(f.w._region==HOME,"rain save failure: home orientation")
	f.w.save_path=good
	expect(f.w.step(1.0,true) and wet(f,"pa") and wet(f,"lan"),"retry after storage recovers wets plots")
	# Midnight clear fails to save -> watering, growth and clock unchanged.
	var g:=farm(DAY-5.0)
	water(g,"pa");set_wet(g,"mine",true)
	good=g.w.save_path
	g.w.save_path=dir+"/missing-subdir/world.json"
	snap=var_to_str(g.w.state)
	expect(not g.w.step(10.0,true),"midnight step reports save failure")
	expect(var_to_str(g.w.state)==snap,"midnight save failure: still watered, same growth and clock")
	expect(g.w._region==HOME and not is_same(g.w.state.crops,g.w.state.regions[MINE].crops),"midnight save failure: layers not aliased")
	g.w.save_path=good
	expect(g.w.step(10.0,true) and not wet(g,"pa") and near(growth(g,"pa"),5.0),"midnight retry clears and integrates 5s")

func test_no_new_fields() -> void:
	var fresh:=World.new()
	var f:=farm(day_start(3)-5.0)
	water(f,"pa")
	var crop_fields:Dictionary={}
	for name in PLOTS:
		var fields:Array=plot(f,name).keys()
		fields.sort()
		crop_fields[name]=fields
	var root_before:Array=f.w.state.keys()
	root_before.sort()
	f.w.step(DAY+20.0,true)
	var root_after:Array=f.w.state.keys()
	root_after.sort()
	expect(root_after==root_before,"weather adds no root save fields")
	expect(f.w.state.version==fresh.state.version and int(fresh.state.version)==int(SAVE_SCHEMA.VERSION),"save version untouched by weather")
	for name in PLOTS:
		var fields:Array=plot(f,name).keys()
		fields.sort()
		expect(fields==crop_fields[name],"weather preserves existing crop record fields (%s)"%name)
	for region in [LANYANG,MINE]:
		var layer_keys:Array=f.w.state.regions[region].keys()
		layer_keys.sort()
		var expected:Array=REGIONS.LAYERS.duplicate()
		expected.sort()
		expect(layer_keys==expected,"regional layers unchanged in "+region)
	var snapshot:Dictionary=f.w.region_snapshot(HOME)
	expect(not snapshot.has("weather"),"region snapshot carries no weather protocol field")
