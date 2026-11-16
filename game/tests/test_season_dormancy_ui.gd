extends SceneTree
## T048 四季休眠與再生作物 — dormant-crop tool hint (headless) at 1024×640 and 1280×800,
## plus exhaustive pure-function tables for World.crop_season_text, World.plot_dormant,
## World.regrow_start, Main.dormant_crop_hint and the CropSpriteArt dormant constants.
## Same harness as test_water_tower_quota_ui.gd / test_corn_chowder_ui.gd: real Session
## host, real snapshot round trips (Session._send_snapshot -> main._state_changed), then
## main._refresh_hud with `target` written as the reticle cell (app processing is off).
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is
##    set here in code (same as the reference suites), so no extra runner argument;
##  * state.time is WRITTEN to fixed season times: autumn day 1 (+600 s), summer day 1
##    (+600 s), spring day 1 (+600 s); restored to autumn after each size;
##  * cells PLOT (48,26), EMPTY (49,26), OTHER_PLOT (50,26): state.objects / ground /
##    roofs / crops entries on those keys are ERASED, then crop dictionaries are WRITTEN:
##      PLOT: tomato {growth 0, remaining 3, owner me}; later growth 60 / remaining 2;
##            growth 120 (ripe); pumpkin {growth 0, remaining 1};
##      OTHER_PLOT: tomato {growth 0, remaining 3, owner the neighbour};
##  * state.roofs[PLOT] WRITTEN as a greenhouse_roof, then as a plain "roof", then erased;
##  * a neighbour islander is added with World.add_player (not connected);
##  * the local player is teleported by writing x/y next to the plot (no walking);
##  * app.target (the reticle cell) is WRITTEN directly; app._process is off, so nothing
##    else overwrites it;
##  * tools are selected with app._select_tool (what the toolbar buttons / keys call).
## REALLY EXERCISED: Session host + snapshot builder, main._state_changed, main._refresh_hud
## (the T048 hint branch + binding_text), LifeShell layout of the ToolHint label,
## WorldView.crop_dormant on the view's own snapshot.
## NOT COVERED HERE: world pixels of the dormant tint / zz mark; mouse-driven reticle;
## gamepad; the non-preview HUD; a second real client.
const World=preload("res://scripts/world.gd")
const MainScript=preload("res://scripts/main.gd")
const CropArt=preload("res://scripts/crop_sprite_art.gd")
const Forecast=preload("res://scripts/weather_forecast.gd")
const Nursery=preload("res://scripts/flower_nursery.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="dormancy-ui-neighbour-5e21"
const PLOT:=Vector2i(48,26)
const EMPTY:=Vector2i(49,26)
const OTHER_PLOT:=Vector2i(50,26)
const STAND:=Vector2(48.5,27.6)
const SEASON_SECONDS:=20160.0
const SPRING:=0.0
const SUMMER:=20160.0
const AUTUMN:=40320.0
const WINTER:=60480.0
const YEAR:=80640.0
## Hand-written from World.CROP_SEASONS as it is today (T048).
const HAND_SEASONS:={
	"radish":["spring","autumn"],
	"lettuce":["spring","summer"],
	"wheat":["spring","summer","autumn"],
	"carrot":["spring","autumn"],
	"potato":["spring","winter"],
	"tomato":["summer"],
	"pumpkin":["autumn"],
	"cauliflower":["spring","winter"],
	"sweet_corn":["summer","autumn"],
	"strawberry":["spring"],
	"cucumber":["summer"],
	"cabbage":["winter"],
	"sugar_beet":["winter"],
	"sweet_potato":["autumn"],
	"eggplant":["summer","autumn"],
	"rice":["summer","autumn"],
	"watermelon":["summer"],
	"ginger":["winter"],
	"cotton":["spring","summer"],
	"bluebell":["spring"],
	"orange_blossom":["summer","autumn"],
}
const YEAR_ROUND:=["star_mushroom","mist_tea","chime_herb"]
const HAND_SEASON_TEXT:={
	"radish":"春、秋","lettuce":"春、夏","wheat":"春、夏、秋","carrot":"春、秋","potato":"春、冬",
	"tomato":"夏","pumpkin":"秋","cauliflower":"春、冬","sweet_corn":"夏、秋","strawberry":"春",
	"cucumber":"夏","cabbage":"冬","sugar_beet":"冬","star_mushroom":"","sweet_potato":"秋",
	"eggplant":"夏、秋","rice":"夏、秋","watermelon":"夏","ginger":"冬","cotton":"春、夏",
	"mist_tea":"","bluebell":"春","orange_blossom":"夏、秋","chime_herb":"",
	"":"","unknown_crop":"","Tomato":"",
}
const HAND_REGROW:={"tomato":60.0,"strawberry":126.0,"cucumber":40.0,"eggplant":82.5,"mist_tea":126.0}
const SEASON_STARTS:={"spring":SPRING,"summer":SUMMER,"autumn":AUTUMN,"winter":WINTER}
const H_TOMATO_3:="太陽番茄休眠中 · 夏季會接著長（進度保留） · 還能收 3 次 · 蓋溫室玻璃棚可不分季節"
const H_TOMATO_2:="太陽番茄休眠中 · 夏季會接著長（進度保留） · 還能收 2 次 · 蓋溫室玻璃棚可不分季節"
const H_TOMATO_1:="太陽番茄休眠中 · 夏季會接著長（進度保留） · 還能收 1 次 · 蓋溫室玻璃棚可不分季節"
const H_PUMPKIN:="琥珀南瓜休眠中 · 秋季會接著長（進度保留） · 蓋溫室玻璃棚可不分季節"
const H_RADISH:="奶白蘿蔔休眠中 · 春、秋季會接著長（進度保留） · 蓋溫室玻璃棚可不分季節"
const H_STRAWBERRY_3:="蜜香草莓休眠中 · 春季會接著長（進度保留） · 還能收 3 次 · 蓋溫室玻璃棚可不分季節"
const H_EGGPLANT_2:="紫絨茄子休眠中 · 夏、秋季會接著長（進度保留） · 還能收 2 次 · 蓋溫室玻璃棚可不分季節"
const H_CUCUMBER_1:="波點黃瓜休眠中 · 夏季會接著長（進度保留） · 還能收 1 次 · 蓋溫室玻璃棚可不分季節"
const H_BLUEBELL:="鈴蘭藍花休眠中 · 春季會接著長（進度保留） · 蓋溫室玻璃棚可不分季節"
const HARVEST_TEXT:="採收：點成熟作物收入背包"
const HOE_TEXT:="鋤頭：點空地開田"
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SEASON_DORMANCY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE SEASON_DORMANCY_UI "+message)

# ------------------------------------------------------------- pure tables --

func hand_dormant(kind:String,growth:float,roof_type:String,season:String)->bool:
	if not HAND_SEASONS.has(kind):return false
	var need:float=float(World.CROPS[kind].time)
	if growth>=need:return false
	if roof_type=="greenhouse_roof":return false
	var seasons:Array=HAND_SEASONS[kind]
	return not (season in seasons)

func pure_season_text()->void:
	var catalog:Array=World.CROPS.keys()
	check(catalog.size()==24,"World.CROPS has the 24 crops this table was written for: %d"%catalog.size())
	for kind:String in catalog:
		check(HAND_SEASON_TEXT.has(kind),"Hand season-text table covers %s"%kind)
		check(HAND_SEASONS.has(kind) or kind in YEAR_ROUND,"Hand season table covers %s"%kind)
	for kind:String in HAND_SEASON_TEXT:
		var got:String=World.crop_season_text(kind)
		var want:String=HAND_SEASON_TEXT[kind]
		check(got==want,"crop_season_text(%s): got 「%s」 want 「%s」"%[kind,got,want])

func pure_regrow()->void:
	for kind:String in World.CROPS:
		var want:float=float(HAND_REGROW.get(kind,0.0))
		var got:float=World.regrow_start(kind)
		check(is_equal_approx(got,want),"regrow_start(%s): got %.2f want %.2f"%[kind,got,want])
	check(World.regrow_start("")==0.0 and World.regrow_start("unknown_crop")==0.0,"regrow_start of an unknown kind is 0")

func pure_dormant_table()->void:
	var roofs:Array=[{},{"type":"greenhouse_roof","owner":"x","items":{}},{"type":"roof","owner":"x","items":{}}]
	check(World.BUILD.has("roof") and World.BUILD.has("greenhouse_roof"),"Both roof kinds used by the table exist in World.BUILD")
	var count:=0
	for kind:String in World.CROPS:
		var need:float=float(World.CROPS[kind].time)
		for season:String in SEASON_STARTS:
			var t:float=float(SEASON_STARTS[season])
			for roof:Dictionary in roofs:
				var roof_type:String=str(roof.get("type",""))
				for growth:float in [0.0,need*0.5,need-1.0,need]:
					var crop:Dictionary={"kind":kind,"growth":growth,"wet":false,"owner":"x","remaining":1}
					var want:bool=hand_dormant(kind,growth,roof_type,season)
					var got:bool=World.plot_dormant(crop,roof,"home",Vector2i(40,30),t)
					count+=1
					check(got==want,"plot_dormant(%s growth %.1f, roof 「%s」, %s day 1): got %s want %s"%[kind,growth,roof_type,season,got,want])
	check(count==24*4*3*4,"plot_dormant table size: %d"%count)

func dormant_at(kind:String,t:float,region:String="home",tile:=Vector2i(40,30))->bool:
	return World.plot_dormant({"kind":kind,"growth":0.0},{},region,tile,t)

func pure_dormant_edges()->void:
	var autumn:=AUTUMN+600.0
	# Empty / unknown / missing fields.
	check(not World.plot_dormant({},{},"home",PLOT,autumn),"Empty dictionary is never dormant")
	check(not World.plot_dormant({"kind":"","growth":0.0,"wet":false},{},"home",PLOT,autumn),"Tilled empty plot is never dormant")
	check(not World.plot_dormant({"kind":"banana","growth":0.0},{},"home",PLOT,autumn),"Unknown kind is never dormant")
	check(not World.plot_dormant({"kind":5,"growth":0.0},{},"home",PLOT,autumn),"Non-string kind is never dormant")
	check(World.plot_dormant({"kind":"tomato"},{},"home",PLOT,autumn),"Missing growth counts as 0: tomato dormant in autumn")
	check(not World.plot_dormant({"kind":"tomato"},{},"home",PLOT,SUMMER+600.0),"Missing growth: tomato grows in summer")
	check(not World.plot_dormant({"growth":0.0},{},"home",PLOT,autumn),"Missing kind is never dormant")
	check(World.plot_dormant({"kind":"tomato","growth":119.999},{},"home",PLOT,autumn),"Growth just below maturity is still dormant")
	check(not World.plot_dormant({"kind":"tomato","growth":500.0},{},"home",PLOT,autumn),"Overgrown (ripe) tomato is never dormant")
	check(World.plot_dormant({"kind":"tomato","growth":-5.0},{},"home",PLOT,autumn),"Negative growth tomato in autumn is dormant")
	# Garbage roof dictionaries: only type == "greenhouse_roof" protects.
	var garbage:Array=[{"type":5},{"type":"GREENHOUSE_ROOF"},{"kind":"greenhouse_roof"},{"type":["greenhouse_roof"]},{"type":""},{"greenhouse_roof":true},{"type":"greenhouse_rack"}]
	for roof:Dictionary in garbage:
		check(World.plot_dormant({"kind":"tomato","growth":0.0},roof,"home",PLOT,autumn),"Garbage roof %s does not protect a dormant tomato"%str(roof))
	check(not World.plot_dormant({"kind":"tomato","growth":0.0},{"type":&"greenhouse_roof"},"home",PLOT,autumn),"StringName greenhouse_roof type protects (str() of the type)")
	check(not World.plot_dormant({"kind":"tomato","growth":0.0},{"type":"greenhouse_roof","junk":[1,2]},"home",PLOT,autumn),"Greenhouse roof with extra fields protects")
	# Season boundaries (14 days x 1440 s).
	check(dormant_at("tomato",SUMMER-1.0),"Tomato dormant at the last second of spring")
	check(dormant_at("tomato",SUMMER-0.001),"Tomato dormant just before summer starts")
	check(not dormant_at("tomato",SUMMER),"Tomato grows at the first second of summer")
	check(not dormant_at("tomato",AUTUMN-1.0),"Tomato grows at the last second of summer")
	check(dormant_at("tomato",AUTUMN),"Tomato dormant at the first second of autumn")
	check(not dormant_at("pumpkin",WINTER-1.0) and dormant_at("pumpkin",WINTER),"Pumpkin: last second of autumn grows, first second of winter dormant")
	check(not dormant_at("cabbage",YEAR-1.0),"Cabbage grows at the last second of winter (day 56)")
	check(dormant_at("cabbage",YEAR),"Cabbage dormant at year wrap (day index 56 = spring)")
	check(dormant_at("strawberry",YEAR-1.0) and not dormant_at("strawberry",YEAR),"Strawberry: winter dormant, spring again after the year wrap")
	check(not dormant_at("strawberry",YEAR*3.0+600.0) and dormant_at("strawberry",YEAR*3.0+SUMMER),"Strawberry follows the cycle in year 4")
	check(dormant_at("tomato",YEAR+AUTUMN+5.0),"Tomato dormant in the second year's autumn")
	check(dormant_at("tomato",-100.0),"Negative time is day 1 (spring): tomato dormant")
	check(not dormant_at("strawberry",-100.0),"Negative time is day 1 (spring): strawberry grows")
	check(not dormant_at("strawberry",INF) and not dormant_at("strawberry",NAN),"Non-finite time is clamped to day 1 (spring)")
	# Tianwei nursery beds: the three flowers grow year-round there only.
	check(Nursery.REGION=="tianwei" and Nursery.NURSERY_BEDS==Rect2i(18,22,8,3),"Nursery bed rect is the one this table was written for")
	check(Nursery.FLOWERS==["bluebell","orange_blossom","chime_herb"],"Nursery flower list unchanged")
	for tile:Vector2i in [Vector2i(18,22),Vector2i(25,24),Vector2i(21,23)]:
		check(not dormant_at("bluebell",SUMMER+600.0,"tianwei",tile),"Bluebell grows in summer on nursery bed %s"%str(tile))
		check(not dormant_at("orange_blossom",WINTER+600.0,"tianwei",tile),"Orange blossom grows in winter on nursery bed %s"%str(tile))
		check(not dormant_at("chime_herb",WINTER+600.0,"tianwei",tile),"Chime herb never dormant on nursery bed %s"%str(tile))
		check(dormant_at("tomato",AUTUMN+600.0,"tianwei",tile),"Non-flower tomato stays seasonal on nursery bed %s"%str(tile))
		check(dormant_at("bluebell",SUMMER+600.0,"home",tile),"Bluebell outside Tianwei is seasonal at %s"%str(tile))
	for tile:Vector2i in [Vector2i(17,22),Vector2i(26,22),Vector2i(18,21),Vector2i(18,25)]:
		check(dormant_at("bluebell",SUMMER+600.0,"tianwei",tile),"Bluebell off the nursery bed (%s) is seasonal"%str(tile))
	check(not dormant_at("bluebell",SPRING+600.0,"tianwei",Vector2i(30,30)),"Bluebell off-bed in spring grows")
	# Special places: plot_dormant has no indoor exception — only the crop's season list counts.
	for region:String in ["mine_5","mine_1","jinguashi"]:
		for season:String in SEASON_STARTS:
			check(not dormant_at("star_mushroom",float(SEASON_STARTS[season])+600.0,region),"Star mushroom (no season list) never dormant in %s, %s"%[region,season])
	check(dormant_at("tomato",WINTER+600.0,"mine_5"),"Indoor mine_5 does not exempt a seasonal tomato in winter (pinned)")
	check(not dormant_at("rice",AUTUMN+600.0,"lanyang",Vector2i(30,30)),"Rice grows in autumn in Lanyang")
	check(dormant_at("rice",WINTER+600.0,"lanyang",Vector2i(30,30)) and dormant_at("rice",SPRING+600.0,"lanyang",Vector2i(30,30)),"Rice dormant in winter and spring in Lanyang")
	for season:String in SEASON_STARTS:
		check(not dormant_at("mist_tea",float(SEASON_STARTS[season])+600.0,"bamboo"),"Mist tea never dormant (%s)"%season)
	# Ripe crops never dormant, any season / roof.
	for kind:String in HAND_SEASONS:
		var need:float=float(World.CROPS[kind].time)
		for season:String in SEASON_STARTS:
			check(not World.plot_dormant({"kind":kind,"growth":need},{"type":"roof"},"home",PLOT,float(SEASON_STARTS[season])+1.0),"Ripe %s never dormant (%s)"%[kind,season])

func snap(crops:Dictionary,t:float,roofs:Dictionary={},region:String="home")->Dictionary:
	return {"region_id":region,"time":t,"crops":crops,"roofs":roofs,"players":{}}

func tomato(growth:float,remaining:int)->Dictionary:
	return {"kind":"tomato","growth":growth,"wet":false,"owner":"x","remaining":remaining}

func hint_case(s:Dictionary,cell:Vector2i,want:String,label:String)->void:
	var before:Dictionary=s.duplicate(true)
	var before_json:=JSON.stringify(s,"",true)
	var got:String=MainScript.dormant_crop_hint(s,cell)
	check(got==want,"dormant_crop_hint %s: got 「%s」 want 「%s」"%[label,got,want])
	check(s==before and JSON.stringify(s,"",true)==before_json and s.keys()==before.keys(),"dormant_crop_hint does not mutate the snapshot (%s)"%label)

func pure_hint()->void:
	var pk:=World.key(PLOT)
	var autumn:=AUTUMN+600.0
	hint_case(snap({pk:tomato(0.0,3)},autumn),PLOT,H_TOMATO_3,"tomato remaining 3")
	hint_case(snap({pk:tomato(60.0,2)},autumn),PLOT,H_TOMATO_2,"tomato remaining 2 at regrow start")
	hint_case(snap({pk:tomato(119.0,1)},autumn),PLOT,H_TOMATO_1,"tomato remaining 1")
	hint_case(snap({pk:{"kind":"tomato","growth":0.0}},autumn),PLOT,H_TOMATO_1,"tomato without remaining (defaults to 1)")
	hint_case(snap({pk:{"kind":"tomato","growth":0.0,"remaining":2.0}},autumn),PLOT,H_TOMATO_2,"float remaining 2.0")
	hint_case(snap({pk:{"kind":"pumpkin","growth":0.0,"remaining":1}},SPRING+600.0),PLOT,H_PUMPKIN,"single-harvest pumpkin in spring")
	hint_case(snap({pk:{"kind":"pumpkin","growth":0.0,"remaining":5}},SPRING+600.0),PLOT,H_PUMPKIN,"single-harvest pumpkin ignores a stray remaining")
	hint_case(snap({pk:{"kind":"radish","growth":10.0}},SUMMER+600.0),PLOT,H_RADISH,"radish (two seasons) in summer")
	hint_case(snap({pk:{"kind":"strawberry","growth":0.0,"remaining":3}},SUMMER+600.0),PLOT,H_STRAWBERRY_3,"strawberry in summer")
	hint_case(snap({pk:{"kind":"eggplant","growth":82.5,"remaining":2}},WINTER+600.0),PLOT,H_EGGPLANT_2,"eggplant in winter")
	hint_case(snap({pk:{"kind":"cucumber","growth":40.0,"remaining":1}},SPRING+600.0),PLOT,H_CUCUMBER_1,"cucumber in spring")
	hint_case(snap({pk:tomato(0.0,3)},autumn,{pk:{"type":"roof","owner":"x","items":{}}}),PLOT,H_TOMATO_3,"plain roof does not hide the hint")
	hint_case(snap({pk:tomato(0.0,3)},autumn,{World.key(EMPTY):{"type":"greenhouse_roof"}}),PLOT,H_TOMATO_3,"greenhouse on another cell does not protect")
	var no_time:Dictionary={"region_id":"home","crops":{pk:tomato(0.0,3)},"roofs":{}}
	hint_case(no_time,PLOT,H_TOMATO_3,"missing time = day 1 (spring)")
	var no_region:Dictionary={"time":autumn,"crops":{pk:tomato(0.0,3)}}
	hint_case(no_region,PLOT,H_TOMATO_3,"missing region_id and roofs")
	var bk:=World.key(Vector2i(18,22))
	hint_case(snap({bk:{"kind":"bluebell","growth":0.0}},SUMMER+600.0,{},"tianwei"),Vector2i(18,22),"","bluebell on the Tianwei nursery bed")
	var ok:=World.key(Vector2i(30,30))
	hint_case(snap({ok:{"kind":"bluebell","growth":0.0}},SUMMER+600.0,{},"tianwei"),Vector2i(30,30),H_BLUEBELL,"bluebell off the nursery bed")
	# Empty results.
	hint_case(snap({pk:tomato(0.0,3)},SUMMER+600.0),PLOT,"","tomato in season")
	hint_case(snap({pk:tomato(120.0,3)},autumn),PLOT,"","ripe tomato")
	hint_case(snap({pk:tomato(60.0,2)},autumn,{pk:{"type":"greenhouse_roof","owner":"x","items":{}}}),PLOT,"","greenhouse-covered tomato")
	hint_case(snap({pk:{"kind":"","growth":0.0,"wet":false}},autumn),PLOT,"","empty tilled plot")
	hint_case(snap({},autumn),PLOT,"","no crop at the cell")
	hint_case(snap({pk:tomato(0.0,3)},autumn),EMPTY,"","neighbouring empty cell")
	hint_case({"region_id":"home","time":autumn},PLOT,"","snapshot without crops")
	hint_case({},PLOT,"","empty snapshot")
	hint_case(snap({pk:{"growth":0.0}},autumn),PLOT,"","crop without kind")
	hint_case(snap({pk:{"kind":"banana","growth":0.0}},autumn),PLOT,"","unknown kind")
	hint_case(snap({pk:{"kind":"mist_tea","growth":0.0,"remaining":3}},autumn),PLOT,"","year-round regrow crop")
	hint_case(snap({pk:{"kind":"star_mushroom","growth":0.0}},WINTER+600.0,{},"mine_5"),PLOT,"","star mushroom in mine_5")
	for bad:Variant in ["tomato",5,[tomato(0.0,3)],null,1.5,true]:
		hint_case(snap({pk:bad},autumn),PLOT,"","malformed crop entry %s"%str(bad))

func pure_art()->void:
	var seen:Dictionary={}
	var px:Array=CropArt.DORMANT_PIXELS
	check(px.size()>0,"DORMANT_PIXELS is not empty")
	for p:Variant in px:
		check(p is Vector2i,"Dormant pixel is a Vector2i: %s"%str(p))
		if not p is Vector2i:continue
		var v:Vector2i=p
		check(not seen.has(v),"Dormant pixel %s is unique"%str(v))
		seen[v]=true
		check(v.x>=0 and v.y>=0 and v.x<32 and v.y<32,"Dormant pixel %s inside the 32×32 cell"%str(v))
		check(v.x+1<32 and v.y+1<32,"Dormant pixel shade %s inside the 32×32 cell"%str(v+Vector2i.ONE))
	check(CropArt.CELL==Vector2i(32,32),"Crop cell is 32×32")
	check(not CropArt.DORMANT_MARK.is_equal_approx(CropArt.DORMANT_MARK_SHADE),"Dormant mark differs from its shade")
	var tint:Color=CropArt.DORMANT_TINT
	check(not tint.is_equal_approx(Color.WHITE),"Dormant tint is not white")
	check(tint.r<=1.0 and tint.g<=1.0 and tint.b<=1.0 and tint.a<=1.0,"Dormant tint channels <= 1: %s"%str(tint))
	check(tint.r>=0.0 and tint.g>=0.0 and tint.b>=0.0 and tint.a>0.0,"Dormant tint channels >= 0 and visible: %s"%str(tint))
	check(CropArt.stage_for({"kind":"tomato","growth":120.0})==CropArt.HARVESTABLE,"Ripe tomato is drawn at the harvestable stage (never dormant)")
	check(CropArt.stage_for({"kind":"tomato","growth":60.0})<CropArt.HARVESTABLE,"Regrowing tomato is below the harvestable stage")

# ---------------------------------------------------------------- HUD flow --

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	app._refresh_hud()
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func k(c:Vector2i)->String:
	return World.key(c)

func crop_dict(kind:String,growth:float,remaining:int,owner:String)->Dictionary:
	return {"kind":kind,"growth":growth,"wet":false,"owner":owner,"remaining":remaining}

func diff_keys(a:Dictionary,b:Dictionary)->String:
	var out:=PackedStringArray()
	for key_name in a:
		if not b.has(key_name) or var_to_bytes(a[key_name])!=var_to_bytes(b[key_name]):out.append(str(key_name))
	for key_name in b:
		if not a.has(key_name):out.append(str(key_name))
	return ",".join(out)

## Point the reticle at `cell`, run the real HUD refresh, return the tool hint.
## World state and the client snapshot must be byte-identical before/after.
func hover(cell:Vector2i,label:String)->String:
	var state_before:Dictionary=(w.state as Dictionary).duplicate(true)
	var state_bytes:=var_to_bytes(w.state)
	var snap_bytes:=var_to_bytes(app.session.snapshot)
	app.target=cell  # PRESET (reticle cell)
	app._refresh_hud()
	await settle()
	var text:String=str(app.selected_label.text)
	var same_state:bool=var_to_bytes(w.state)==state_bytes
	check(same_state,"Hover leaves server state unchanged (%s) changed keys: %s"%[label,"" if same_state else diff_keys(state_before,w.state)])
	check(var_to_bytes(app.session.snapshot)==snap_bytes,"Hover leaves the client snapshot unchanged (%s)"%label)
	return text

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func label_fits(label:String)->void:
	var l:Label=app.selected_label
	var r:Rect2=l.get_global_rect()
	check(l.is_visible_in_tree(),"Tool hint visible (%s)"%label)
	check(root.get_visible_rect().encloses(r),"Tool hint inside the viewport (%s) rect=%s view=%s"%[label,str(r),str(root.get_visible_rect())])
	check(not_cut(l),"Tool hint not cut (%s): 「%s」"%[label,l.text])
	check(l.get_line_count()==1,"Tool hint on one line (%s): %d lines"%[label,l.get_line_count()])
	var font:Font=l.get_theme_font("font")
	var font_size:int=l.get_theme_font_size("font_size")
	var width:float=font.get_string_size(l.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	check(width<=l.size.x+1.0,"Tool hint text width %.0f fits the label %.0f (%s)"%[width,l.size.x,label])
	var bar:Control=app.preview_toolbar
	if bar!=null and bar.is_visible_in_tree():
		check(not r.grow(-0.5).intersects(bar.get_global_rect().grow(-0.5)),"Tool hint does not overlap the toolbar (%s) hint=%s bar=%s"%[label,str(r),str(bar.get_global_rect())])

func water_usual()->String:
	return app.binding_text(Forecast.water_hint(app.session.snapshot))

func set_time(t:float)->void:
	w.state.time=t  # PRESET (season clock)

func prepare()->void:
	if is_instance_valid(app.modal):app._close_modal()
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居小麥")  # PRESET
	for c:Vector2i in [PLOT,EMPTY,OTHER_PLOT]:
		w.state.objects.erase(k(c))  # PRESET
		w.state.ground.erase(k(c))  # PRESET
		w.state.roofs.erase(k(c))  # PRESET
		w.state.crops.erase(k(c))  # PRESET
	w.state.crops[k(PLOT)]=crop_dict("tomato",0.0,3,id)  # PRESET
	w.state.crops[k(OTHER_PLOT)]=crop_dict("tomato",0.0,3,OTHER)  # PRESET
	set_time(AUTUMN+600.0)
	var p:Dictionary=w.state.players[id]
	p.x=STAND.x;p.y=STAND.y  # PRESET (teleport next to the plot)
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	await settle()

func view_dormant(cell:Vector2i)->bool:
	var crops:Dictionary=app.view.data.get("crops",{})
	var c:Variant=crops.get(k(cell),{})
	if not c is Dictionary:return false
	return bool(app.view.crop_dormant(cell,c))

func tool_round(tool:String,usual:String,tag:String)->void:
	app._select_tool(tool)
	var t1:String=await hover(PLOT,tool+" on dormant tomato "+tag)
	check(t1==H_TOMATO_3 and t1==app.binding_text(H_TOMATO_3),"%s on the dormant tomato shows the hint (%s): 「%s」"%[tool,tag,t1])
	check(t1.contains("還能收 3 次"),"%s hint mentions 還能收 3 次 (%s)"%[tool,tag])
	label_fits(tool+" hint "+tag)
	var t2:String=await hover(EMPTY,tool+" on empty cell "+tag)
	check(t2==usual,"%s on an empty cell shows the usual tool text (%s): got 「%s」 want 「%s」"%[tool,tag,t2,usual])
	check(not t2.contains("休眠"),"%s off the plot has no dormant wording (%s)"%[tool,tag])
	var t3:String=await hover(PLOT,tool+" back on dormant tomato "+tag)
	check(t3==H_TOMATO_3,"%s back on the dormant tomato shows the hint again (%s): 「%s」"%[tool,tag,t3])
	var t4:String=await hover(Vector2i(10,10),tool+" far cell "+tag)
	check(t4==usual,"%s on a far cell shows the usual text (%s): 「%s」"%[tool,tag,t4])

func size_flow(tag:String)->void:
	await prepare()
	check(str(app.session.snapshot.get("region_id","home"))=="home","Player is at home (%s)"%tag)
	check(view_dormant(PLOT),"WorldView.crop_dormant true for the autumn tomato (%s)"%tag)
	check(not view_dormant(EMPTY),"WorldView.crop_dormant false on an empty cell (%s)"%tag)
	# Water then harvest.
	app._select_tool("water")
	await tool_round("water",water_usual(),tag)
	await tool_round("harvest",app.binding_text(HARVEST_TEXT),tag)
	# Other tools never show the dormant hint.
	for tool:String in ["hoe","seed","axe","pick","remove"]:
		app._select_tool(tool)
		var t:String=await hover(PLOT,tool+" on dormant tomato "+tag)
		check(not t.contains("休眠") and not t.contains("還能收"),"%s never shows the dormant hint (%s): 「%s」"%[tool,tag,t])
		if tool=="hoe":check(t==app.binding_text(HOE_TEXT),"Hoe keeps its own text (%s): 「%s」"%[tag,t])
	# Remaining 2 at regrow start.
	w.state.crops[k(PLOT)]=crop_dict("tomato",World.regrow_start("tomato"),2,id)  # PRESET
	await refresh()
	app._select_tool("water")
	var r2:String=await hover(PLOT,"remaining 2 "+tag)
	check(r2==H_TOMATO_2 and r2.contains("還能收 2 次"),"Regrowing tomato shows 還能收 2 次 (%s): 「%s」"%[tag,r2])
	label_fits("remaining 2 "+tag)
	# Ripe: no hint.
	w.state.crops[k(PLOT)]=crop_dict("tomato",120.0,2,id)  # PRESET
	await refresh()
	var ripe:String=await hover(PLOT,"ripe "+tag)
	check(ripe==water_usual(),"Ripe tomato: usual water text (%s): 「%s」"%[tag,ripe])
	check(not view_dormant(PLOT),"WorldView.crop_dormant false for a ripe tomato (%s)"%tag)
	app._select_tool("harvest")
	var ripe_h:String=await hover(PLOT,"ripe harvest "+tag)
	check(not ripe_h.contains("休眠"),"Ripe tomato with the harvest tool: no dormant hint (%s): 「%s」"%[tag,ripe_h])
	# Greenhouse roof: no hint; plain roof: hint.
	w.state.crops[k(PLOT)]=crop_dict("tomato",0.0,3,id)  # PRESET
	w.state.roofs[k(PLOT)]={"type":"greenhouse_roof","owner":id,"items":{}}  # PRESET
	await refresh()
	app._select_tool("water")
	var gh:String=await hover(PLOT,"greenhouse "+tag)
	check(gh==water_usual(),"Greenhouse-covered tomato: usual water text (%s): 「%s」"%[tag,gh])
	check(not view_dormant(PLOT),"WorldView.crop_dormant false under a greenhouse (%s)"%tag)
	w.state.roofs[k(PLOT)]={"type":"roof","owner":id,"items":{}}  # PRESET
	await refresh()
	var plain:String=await hover(PLOT,"plain roof "+tag)
	check(plain==H_TOMATO_3,"Plain roof keeps the dormant hint (%s): 「%s」"%[tag,plain])
	w.state.roofs.erase(k(PLOT))  # PRESET
	# Summer: tomato in season.
	set_time(SUMMER+600.0)
	await refresh()
	var summer:String=await hover(PLOT,"summer "+tag)
	check(summer==water_usual() and not summer.contains("休眠"),"Summer tomato: usual water text (%s): 「%s」"%[tag,summer])
	check(not view_dormant(PLOT),"WorldView.crop_dormant false in summer (%s)"%tag)
	# Single-harvest pumpkin in spring.
	set_time(SPRING+600.0)
	w.state.crops[k(PLOT)]=crop_dict("pumpkin",0.0,1,id)  # PRESET
	await refresh()
	var pump:String=await hover(PLOT,"pumpkin spring "+tag)
	check(pump==H_PUMPKIN and not pump.contains("還能收"),"Dormant pumpkin hint without 還能收 (%s): 「%s」"%[tag,pump])
	label_fits("pumpkin "+tag)
	app._select_tool("harvest")
	var pump_h:String=await hover(PLOT,"pumpkin spring harvest "+tag)
	check(pump_h==H_PUMPKIN,"Dormant pumpkin hint with the harvest tool (%s): 「%s」"%[tag,pump_h])
	# Another islander's dormant plot shows the same read-only hint.
	set_time(AUTUMN+600.0)
	await refresh()
	app._select_tool("water")
	var other:String=await hover(OTHER_PLOT,"neighbour plot water "+tag)
	check(other==H_TOMATO_3,"Neighbour's dormant tomato shows the same hint (%s): 「%s」"%[tag,other])
	label_fits("neighbour "+tag)
	app._select_tool("harvest")
	var other_h:String=await hover(OTHER_PLOT,"neighbour plot harvest "+tag)
	check(other_h==H_TOMATO_3,"Neighbour's dormant tomato with harvest shows the hint (%s): 「%s」"%[tag,other_h])
	check(int(w.state.crops[k(OTHER_PLOT)].remaining)==3 and float(w.state.crops[k(OTHER_PLOT)].growth)==0.0 and str(w.state.crops[k(OTHER_PLOT)].owner)==OTHER,"Neighbour's plot untouched (%s)"%tag)
	app._select_tool("hoe")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_season_text()
	pure_regrow()
	pure_dormant_table()
	pure_dormant_edges()
	pure_hint()
	pure_art()
	note("pure tables done at %.1f s (checks=%d failures=%d)"%[(Time.get_ticks_msec()-started)/1000.0,checks,failures])
	path=OS.get_environment("TEMP").path_join("season-dormancy-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"季節旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	if not app.hud.visible:note("hud hidden after host")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
		if failures>60:break
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
