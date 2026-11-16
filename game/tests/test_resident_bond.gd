extends SceneTree
## T066 regression suite for res://scripts/resident_bond.gd and its World,
## SaveSchema and Session integration: catalog integrity, daily talk/gift rules,
## rejections that leave state untouched, request replay, quest-derived points,
## the four stages and the 24-point cap, per-player progress, save/reload,
## legacy saves, schema tampering and snapshot privacy. Covers the four village
## residents and the eight local residents (chacha in maokong, xinghe in lanyang,
## mianmian at the home ranch, achao at the home dock, nuannuan in jiaoxi,
## luoluo beside the home shipping box, lingpopo beside the wind-chime tree,
## diandian on the west bank of the star_garden reflection pool).
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Session=preload("res://scripts/session.gd")
const DAY:=1440.0
const RAISE:="關係來到"
const PRIVATE_A:="bond-private-alpha-token"
const PRIVATE_B:="bond-private-beta-token"
const TWELVE:=["achao","aru","bobo","chacha","diandian","lingpopo","luoluo","mianmian","milu","nuannuan","xiaoli","xinghe"]
const StarGarden=preload("res://scripts/star_garden.gd")
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("RESIDENT_BOND_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("resident-bond-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func rec(points:int,talk:int,gift:int)->Dictionary:
	return {"points":points,"talk_day":talk,"gift_day":gift}

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func bonds_of(w,token:String)->Variant:
	var p:Dictionary=pl(w,token)
	if not p.has("bonds"):return null
	var value:Variant=p.bonds
	if value is Dictionary:
		var copy:Dictionary=value.duplicate(true)
		return copy
	return value

static func cell_of(w,resident:String)->Vector2i:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	var found:Vector2i=place[1]
	return found

static func region_of(w,resident:String)->String:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	return str(place[0])

## Moves a player into `region` (as the jinguashi Bobo test does) and stands
## them just below `cell`.
static func go(w,token:String,region:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p.region=region
	stand(w,token,cell)

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5

static func view_of(w,token:String)->Dictionary:
	var p:Dictionary=pl(w,token)
	return Bond.view(p,float(w.state.time))

static func entry(w,token:String,resident:String)->Dictionary:
	var v:Dictionary=view_of(w,token)
	var e:Dictionary=v.get(resident,{})
	return e

static func today_of(w)->int:
	return Bond.day(float(w.state.time))

static func title(resident:String,stage:int)->String:
	var events:Array=Bond.EVENTS[resident]
	var event:Dictionary=events[stage-1]
	return str(event.title)

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

## Int-tolerant comparison of two bonds dictionaries (JSON turns ints into floats).
static func same_bonds(a:Variant,b:Variant)->bool:
	if not a is Dictionary or not b is Dictionary:return false
	var da:Dictionary=a
	var db:Dictionary=b
	if da.size()!=db.size():return false
	for resident in da:
		if not db.has(resident):return false
		var ra:Variant=da[resident]
		var rb:Variant=db[resident]
		if not ra is Dictionary or not rb is Dictionary:return false
		var x:Dictionary=ra
		var y:Dictionary=rb
		if x.size()!=3 or y.size()!=3:return false
		for field in ["points","talk_day","gift_day"]:
			if not x.has(field) or not y.has(field):return false
			if int(x[field])!=int(y[field]):return false
	return true

func act(w,token:String,action:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "bond-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func write_fixture(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## A rejected action must leave inventory, bonds (including its absence),
## stories, coins and the personal view exactly as they were.
func expect_rejected(w,token:String,action:String,cell:Vector2i,extra:String,label:String)->void:
	var p:Dictionary=pl(w,token)
	var inv_before:Dictionary=p.inventory.duplicate(true)
	var had_bonds:bool=p.has("bonds")
	var bonds_before:Variant=bonds_of(w,token)
	var stories_before:Dictionary=p.stories.duplicate(true)
	var coins_before:int=int(p.coins)
	var view_before:Dictionary=view_of(w,token)
	var r:Dictionary=act(w,token,action,cell,extra)
	var after:Dictionary=pl(w,token)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself")
	expect(after.inventory==inv_before,label+": whole inventory unchanged")
	expect(after.has("bonds")==had_bonds and bonds_of(w,token)==bonds_before,label+": whole bonds unchanged")
	expect(after.stories==stories_before and int(after.coins)==coins_before,label+": stories and coins unchanged")
	expect(view_of(w,token)==view_before,label+": personal view unchanged")

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_catalog()
	test_fresh_and_rejections()
	test_talk()
	test_gift_and_replay()
	test_quest_points()
	test_full_progression()
	test_two_players()
	test_save_reload_and_schema()
	test_local_residents()
	test_ranch_resident()
	test_dock_resident()
	test_spring_resident()
	test_fourth_batch_save_and_players()
	test_plaza_cells()
	test_plaza_resident("luoluo")
	test_plaza_resident("lingpopo")
	test_fifth_batch_save_and_players()
	test_garden_resident()
	test_sixth_batch_save_and_players()
	await test_session_privacy()
	finish()

# 1. Catalog integrity.
func test_catalog()->void:
	var like_keys:Array=Bond.LIKES.keys()
	like_keys.sort()
	var residents:Array=Bond.RESIDENTS.duplicate()
	residents.sort()
	expect(residents==TWELVE,"Exactly the twelve residents have bonds")
	expect(like_keys==residents,"LIKES covers exactly the twelve residents")
	expect(Bond.RESIDENTS.size()==12 and Bond.RESIDENTS.back()=="diandian","RESIDENTS has twelve ids ending with diandian")
	var local_keys:Array=Bond.LOCAL_NAMES.keys()
	local_keys.sort()
	var place_keys:Array=Bond.LOCAL_PLACES.keys()
	place_keys.sort()
	expect(local_keys==["achao","chacha","diandian","lingpopo","luoluo","mianmian","nuannuan","xinghe"] and place_keys==local_keys,"LOCAL_NAMES and LOCAL_PLACES cover exactly achao, chacha, diandian, lingpopo, luoluo, mianmian, nuannuan and xinghe")
	expect(str(Bond.LOCAL_NAMES.get("diandian",""))=="點點" and str(Bond.LOCAL_PLACES.get("diandian",""))=="星芽庭園映星池西岸","diandian is 點點 at 星芽庭園映星池西岸")
	expect(Bond.STORY_FLAGS=={"xinghe":["greenhouse_reported"]},"Only xinghe has flag-derived story points (greenhouse_reported)")
	expect(Bond.WALK_UP==["mianmian","achao","nuannuan","luoluo","lingpopo","diandian"],"WALK_UP lists exactly mianmian, achao, nuannuan, luoluo, lingpopo and diandian")
	var probe_world:=World.new()
	var probe_state:Dictionary=probe_world.state
	var expected_places:Dictionary={"chacha":["maokong",Vector2i(20,20),"茶茶"],"xinghe":["lanyang",Vector2i(33,29),"星禾"],"mianmian":["home",Vector2i(49,33),"棉棉"],"achao":["home",Vector2i(49,30),"阿潮"],"nuannuan":["jiaoxi",Vector2i(20,22),"暖暖"],"luoluo":["home",Vector2i(43,33),"洛洛"],"lingpopo":["home",Vector2i(41,26),"鈴婆婆"],"diandian":["star_garden",Vector2i(20,21),"點點"]}
	expect(World.TEA_CERAMICS.TEA_NPC==Vector2i(20,20) and World.LANYANG_LIFE.SERVICE==Vector2i(33,29),"Local resident anchor cells are the tea host and the Lanyang service point")
	for resident:String in Bond.RESIDENTS:
		var place:Array=World.bond_place(probe_state,resident)
		expect(place.size()==2,"bond_place(%s) returns [region, cell]"%resident)
		if Bond.LOCAL_NAMES.has(resident):
			expect(not Village.NPCS.has(resident) and not Village.QUESTS.has(resident),"%s is a local resident outside Village.NPCS/QUESTS"%resident)
			expect(not str(Bond.LOCAL_NAMES[resident]).strip_edges().is_empty(),"%s has a local name"%resident)
			expect(not str(Bond.LOCAL_PLACES.get(resident,"")).strip_edges().is_empty(),"%s has a local place"%resident)
			var want:Array=expected_places.get(resident,["",Vector2i(-1,-1),""])
			expect(Bond.name_of(resident)==str(want[2]) and Bond.name_of(resident)==str(Bond.LOCAL_NAMES[resident]),"name_of(%s) is the Chinese name"%resident)
			if place.size()==2:
				expect(str(place[0])==str(want[0]) and place[1]==want[1],"bond_place(%s) is %s %s"%[resident,str(want[0]),str(want[1])])
			expect(Bond.stage_up_text(resident,0,1).contains(str(want[2])),"Stage-up text for %s names her"%resident)
		else:
			expect(Village.NPCS.has(resident),"%s is a village NPC"%resident)
			expect(Village.QUESTS.has(resident),"%s has village quests"%resident)
			expect(Bond.name_of(resident)==str(Village.NPCS[resident].name),"name_of(%s) uses the village NPC name"%resident)
			if place.size()==2:
				expect(str(place[0])==Village.npc_region(resident) and place[1]==Village.resident_cell(probe_state,resident),"bond_place(%s) matches the village resident cell"%resident)
		expect(Bond.LIKE_TEXT.has(resident) and not str(Bond.LIKE_TEXT[resident]).is_empty(),"%s has like text"%resident)
		var talk_lines:Array=Bond.TALK_LINES.get(resident,[])
		expect(not talk_lines.is_empty(),"%s has talk lines"%resident)
		var likes:Array=Bond.LIKES.get(resident,[])
		expect(not likes.is_empty(),"%s likes at least one item"%resident)
		for item in likes:
			expect(World.NAMES.has(item),"Liked gift %s for %s exists in World.NAMES"%[item,resident])
			expect(Bond.liked(resident,str(item)) and Bond.giftable(resident,str(item)),"Liked gift %s for %s is giftable"%[item,resident])
		var events:Array=Bond.EVENTS.get(resident,[])
		expect(events.size()==4,"%s has exactly four stage events"%resident)
		for index in range(events.size()):
			var event:Variant=events[index]
			var good:bool=event is Dictionary
			if good:
				var data:Dictionary=event
				good=str(data.get("title","")).strip_edges()!="" and data.get("lines") is Array
				if good:
					var lines:Array=data.lines
					good=not lines.is_empty()
					for line in lines:
						if not line is String or str(line).strip_edges().is_empty():good=false
			expect(good,"%s event %d has a non-empty title and non-empty lines"%[resident,index+1])
		expect(not Bond.giftable(resident,"wood") and not Bond.liked(resident,"wood"),"Wood is not a gift for %s"%resident)
	for item in Bond.COMMON_GIFTS:
		expect(World.NAMES.has(item),"Common gift %s exists in World.NAMES"%item)
		for resident:String in Bond.RESIDENTS:
			expect(Bond.giftable(resident,str(item)),"Common gift %s is accepted by %s"%[item,resident])
	expect(not Bond.giftable("tom","radish"),"Unknown residents accept nothing")
	expect(Bond.STAGES.size()==4 and Bond.THRESHOLDS.size()==4,"Four stage names and four thresholds")
	var increasing:bool=int(Bond.THRESHOLDS[0])>0
	for i in range(1,Bond.THRESHOLDS.size()):
		if int(Bond.THRESHOLDS[i])<=int(Bond.THRESHOLDS[i-1]):increasing=false
	expect(increasing,"Thresholds are positive and strictly increasing")
	expect(int(Bond.THRESHOLDS[Bond.THRESHOLDS.size()-1])==Bond.LIMIT and Bond.LIMIT==24,"Last threshold equals the 24-point limit")
	var cases:Dictionary={0:0,1:1,5:1,6:2,13:2,14:3,23:3,24:4}
	for value in cases:
		expect(Bond.stage_for(int(value))==int(cases[value]),"stage_for(%d)==%d"%[int(value),int(cases[value])])
	expect(Bond.stage_name(0)=="尚未認識" and Bond.stage_name(1)=="認識" and Bond.stage_name(2)=="熟悉" and Bond.stage_name(3)=="信任" and Bond.stage_name(4)=="好友","Stage names in order")
	expect(Bond.day(0.0)==0 and Bond.day(DAY-0.001)==0 and Bond.day(DAY)==1 and Bond.day(3.0*DAY+5.0)==3,"World day boundaries use 1440-second days")
	var derived:Dictionary={"stories":{"aru":4},"bonds":{"aru":rec(20,0,0)}}
	expect(Bond.points(derived,"aru")==24 and Bond.stage(derived,"aru")==4,"Stored plus quest-derived points cap at 24")
	var legacy:Dictionary={"stories":{"milu":2}}
	expect(Bond.points(legacy,"milu")==6 and Bond.points(legacy,"aru")==0,"Quest stories alone derive three points each")

# 2 + 3. Fresh player and rejections.
func test_fresh_and_rejections()->void:
	var w:=World.new()
	w.add_player("alice","甲")
	var p:Dictionary=pl(w,"alice")
	expect(not p.has("bonds"),"Fresh player has no bonds key")
	var v:Dictionary=view_of(w,"alice")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==TWELVE,"View lists exactly the twelve residents")
	for resident:String in Bond.RESIDENTS:
		var e:Dictionary=v.get(resident,{})
		expect(int(e.get("points",-1))==0 and int(e.get("stage",-1))==0 and str(e.get("stage_name",""))=="尚未認識","Fresh view: %s at stage 0"%resident)
		expect(int(e.get("next",-1))==1 and e.get("talked_today")==false and e.get("gifted_today")==false,"Fresh view: %s next threshold 1, nothing done today"%resident)
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	stand(w,"alice",aru)
	p=pl(w,"alice")
	p.inventory.radish=2
	p.inventory.erase("tea_light")
	expect_rejected(w,"alice","resident_talk",aru+Vector2i.RIGHT,"aru","Talk aimed at the tile beside Aru")
	expect_rejected(w,"alice","resident_gift",aru+Vector2i.RIGHT,"aru:radish","Gift aimed at the tile beside Aru")
	stand(w,"alice",milu)
	expect_rejected(w,"alice","resident_talk",milu,"aru","Talk to Aru aimed at Milu's cell")
	stand(w,"alice",aru)
	expect_rejected(w,"alice","resident_talk",aru,"tom","Unknown resident")
	expect_rejected(w,"alice","resident_talk",aru,"","Empty resident")
	expect_rejected(w,"alice","resident_talk",aru,"aru:radish","Talk with an item suffix")
	expect_rejected(w,"alice","resident_gift",aru,"aru","Gift without an item")
	expect_rejected(w,"alice","resident_gift",aru,"aru:radish:x","Gift with three parts")
	expect_rejected(w,"alice","resident_gift",aru,"aru:","Gift with an empty item")
	expect_rejected(w,"alice","resident_gift",aru,"aru:wood","Non-giftable wood")
	expect_rejected(w,"alice","resident_gift",aru,"aru:not_an_item","Unknown item")
	expect_rejected(w,"alice","resident_gift",aru,"aru:tea_light","Liked item not in the bag")
	p=pl(w,"alice")
	p.x=float(aru.x)+0.5
	p.y=float(aru.y)+5.5
	expect_rejected(w,"alice","resident_talk",aru,"aru","Talking from five tiles away")
	expect_rejected(w,"alice","resident_gift",aru,"aru:radish","Gifting from five tiles away")
	var bobo:=cell_of(w,"bobo")
	stand(w,"alice",bobo)
	expect_rejected(w,"alice","resident_talk",bobo,"bobo","Home player cannot talk to Bobo at his jinguashi cell")
	p=pl(w,"alice")
	p.region="jinguashi"
	stand(w,"alice",aru)
	expect_rejected(w,"alice","resident_talk",aru,"aru","Jinguashi player cannot talk to Aru")
	expect_rejected(w,"alice","resident_gift",aru,"aru:radish","Jinguashi player cannot gift Aru")
	expect(not pl(w,"alice").has("bonds"),"No rejected action created a bonds key")
	# Bobo is reachable from jinguashi.
	p=pl(w,"alice")
	p.inventory.crystal_sand=1
	stand(w,"alice",bobo)
	var today:=today_of(w)
	var r:=act(w,"alice","resident_talk",bobo,"bobo")
	expect(bool(r.ok) and msg(r).contains(title("bobo",1)),"Jinguashi player talks to Bobo and meets the first event")
	r=act(w,"alice","resident_gift",bobo,"bobo:crystal_sand")
	expect(bool(r.ok) and int(pl(w,"alice").inventory.crystal_sand)==0,"Bobo accepts his liked crystal sand")
	expect(pl(w,"alice").bonds=={"bobo":rec(4,today,today)},"Bobo record holds talk and liked gift")
	expect_rejected(w,"alice","resident_talk",bobo,"bobo","Second Bobo talk the same day")
	p=pl(w,"alice")
	p.region="home"
	stand(w,"alice",aru)
	r=act(w,"alice","resident_talk",aru,"aru")
	expect(bool(r.ok),"Back home the first Aru talk works")
	expect_rejected(w,"alice","resident_talk",aru,"aru","Second Aru talk the same day")
	expect(pl(w,"alice").bonds=={"bobo":rec(4,today,today),"aru":rec(1,today,-1)},"Exact bonds after the session")

# 4. Talk.
func test_talk()->void:
	var w:=World.new()
	w.add_player("tara","塔")
	var aru:=cell_of(w,"aru")
	stand(w,"tara",aru)
	var today:=today_of(w)
	var inv_before:Dictionary=pl(w,"tara").inventory.duplicate(true)
	var r:=act(w,"tara","resident_talk",aru,"aru")
	expect(bool(r.ok),"First talk succeeds")
	expect(pl(w,"tara").bonds=={"aru":rec(1,today,-1)},"First talk stores exactly one point and today's talk day")
	expect(pl(w,"tara").inventory==inv_before,"Talking changes no inventory")
	var text:=msg(r)
	expect(text.contains(RAISE) and text.contains("認識") and text.contains(title("aru",1)) and text.contains(str(Village.NPCS.aru.name)),"Stage-up sentence names the stage and the first event title")
	expect(text.contains(Bond.stage_up_text("aru",0,1)),"Talk message ends with the exact stage-up sentence")
	var e:=entry(w,"tara","aru")
	expect(int(e.points)==1 and int(e.stage)==1 and str(e.stage_name)=="認識" and int(e.next)==6 and e.talked_today==true and e.gifted_today==false,"View after first talk")
	expect(int(entry(w,"tara","milu").points)==0,"Other residents untouched")
	w.state.time=float(w.state.time)+DAY
	expect(entry(w,"tara","aru").talked_today==false,"Next world day clears talked_today")
	r=act(w,"tara","resident_talk",aru,"aru")
	expect(bool(r.ok) and not msg(r).contains(RAISE),"Next-day talk succeeds without a stage-up")
	expect(pl(w,"tara").bonds=={"aru":rec(2,today+1,-1)},"Next-day talk adds exactly one point")
	expect_rejected(w,"tara","resident_talk",aru,"aru","Repeat talk on the second day")
	w.state.time=float(today+2)*DAY-0.5
	expect_rejected(w,"tara","resident_talk",aru,"aru","Talk half a second before the day boundary")
	w.state.time=float(today+2)*DAY
	r=act(w,"tara","resident_talk",aru,"aru")
	expect(bool(r.ok) and pl(w,"tara").bonds=={"aru":rec(3,today+2,-1)},"Talk exactly at the day boundary counts")

# 5 + 6. Gifts and request replay.
func test_gift_and_replay()->void:
	var w:=World.new()
	w.add_player("gina","吉")
	var milu:=cell_of(w,"milu")
	var xiaoli:=cell_of(w,"xiaoli")
	stand(w,"gina",milu)
	var p:Dictionary=pl(w,"gina")
	p.inventory.soup=3
	p.inventory.radish=3
	var today:=today_of(w)
	var before:Dictionary=pl(w,"gina").inventory.duplicate(true)
	var r:=act(w,"gina","resident_gift",milu,"milu:soup","gift-soup-1")
	var expected:Dictionary=before.duplicate(true)
	expected.soup=2
	expect(bool(r.ok),"Liked gift accepted")
	expect(msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.soup)),"Liked gift message names the item")
	expect(msg(r).contains(Bond.stage_up_text("milu",0,1)) and msg(r).contains(title("milu",1)),"Liked gift raises Milu to the first stage")
	expect(pl(w,"gina").inventory==expected,"Exactly one soup removed and nothing else")
	expect(pl(w,"gina").bonds=={"milu":rec(3,-1,today)},"Liked gift adds three points")
	# 6. Replay with the same request id.
	var bonds_before:Variant=bonds_of(w,"gina")
	var replay:=act(w,"gina","resident_gift",milu,"milu:soup","gift-soup-1")
	expect(replay==r,"Replayed request returns the stored receipt")
	expect(pl(w,"gina").inventory==expected and bonds_of(w,"gina")==bonds_before,"Replayed request takes no second soup and adds no points")
	# Second gift the same day: accepted, consumed, no points.
	before=pl(w,"gina").inventory.duplicate(true)
	r=act(w,"gina","resident_gift",milu,"milu:radish","gift-radish-1")
	expected=before.duplicate(true)
	expected.radish=2
	expect(bool(r.ok) and msg(r).contains("明天") and not msg(r).contains(RAISE),"Second gift the same day is accepted without points")
	expect(pl(w,"gina").inventory==expected,"Second gift removes exactly one radish")
	expect(pl(w,"gina").bonds=={"milu":rec(3,-1,today)},"Second gift the same day adds no points")
	replay=act(w,"gina","resident_gift",milu,"milu:radish","gift-radish-1")
	expect(replay==r and pl(w,"gina").inventory==expected,"Replaying the repeat gift takes nothing")
	before=pl(w,"gina").inventory.duplicate(true)
	r=act(w,"gina","resident_gift",milu,"milu:soup")
	expected=before.duplicate(true)
	expected.soup=1
	expect(bool(r.ok) and pl(w,"gina").inventory==expected and pl(w,"gina").bonds=={"milu":rec(3,-1,today)},"A repeat liked gift is also kept without points")
	r=act(w,"gina","resident_talk",milu,"milu")
	expect(bool(r.ok) and pl(w,"gina").bonds=={"milu":rec(4,today,today)},"Gifting does not use up the daily talk")
	# Next day counts again (common gift +1).
	w.state.time=float(w.state.time)+DAY
	before=pl(w,"gina").inventory.duplicate(true)
	r=act(w,"gina","resident_gift",milu,"milu:radish")
	expected=before.duplicate(true)
	expected.radish=1
	expect(bool(r.ok) and msg(r).contains("向你道謝"),"Next-day common gift accepted")
	expect(pl(w,"gina").inventory==expected and pl(w,"gina").bonds=={"milu":rec(5,today,today+1)},"Next-day common gift adds exactly one point")
	# A common gift to a fresh resident: +1 and stage 1.
	stand(w,"gina",xiaoli)
	before=pl(w,"gina").inventory.duplicate(true)
	r=act(w,"gina","resident_gift",xiaoli,"xiaoli:radish")
	expected=before.duplicate(true)
	expected.radish=0
	expect(bool(r.ok) and msg(r).contains(title("xiaoli",1)),"Common gift to Xiaoli reaches the first stage")
	expect(pl(w,"gina").inventory==expected,"Common gift removes exactly one radish")
	expect(pl(w,"gina").bonds=={"milu":rec(5,today,today+1),"xiaoli":rec(1,-1,today+1)},"Common gift adds exactly one point to Xiaoli only")
	expect_rejected(w,"gina","resident_gift",xiaoli,"xiaoli:radish","Gift after the last radish is gone")

# 7. Quest-derived points.
func test_quest_points()->void:
	var w:=World.new()
	w.add_player("quinn","昆")
	w.add_player("dora","朵")
	var milu:=cell_of(w,"milu")
	var today:=today_of(w)
	stand(w,"quinn",milu)
	var quinn:Dictionary=pl(w,"quinn")
	quinn.inventory.radish=2
	var r:=act(w,"quinn","quest",milu,"milu:0")
	expect(bool(r.ok) and int(pl(w,"quinn").stories.milu)==1,"Quinn completes Milu's first quest")
	expect(not pl(w,"quinn").has("bonds"),"Quest progress never writes bonds")
	var e:=entry(w,"quinn","milu")
	expect(int(e.points)==3 and int(e.stage)==1,"First quest derives three points")
	expect(msg(r).contains(Bond.stage_up_text("milu",0,1)) and msg(r).contains(title("milu",1)),"Quest message carries the stage-up sentence")
	# Dora already met Milu: the quest adds points without a new stage.
	stand(w,"dora",milu)
	r=act(w,"dora","resident_talk",milu,"milu")
	expect(bool(r.ok) and pl(w,"dora").bonds=={"milu":rec(1,today,-1)},"Dora talks to Milu first")
	var dora:Dictionary=pl(w,"dora")
	dora.inventory.radish=2
	r=act(w,"dora","quest",milu,"milu:0")
	expect(bool(r.ok) and not msg(r).contains(RAISE),"Quest that keeps the stage adds no stage-up sentence")
	expect(pl(w,"dora").bonds=={"milu":rec(1,today,-1)},"Quest leaves stored bonds unchanged")
	e=entry(w,"dora","milu")
	expect(int(e.points)==4 and int(e.stage)==1,"Talk point plus one quest gives four points")
	dora=pl(w,"dora")
	dora.inventory.bread=1
	dora.inventory.salad=2
	r=act(w,"dora","quest",milu,"milu:1")
	expect(bool(r.ok) and int(pl(w,"dora").stories.milu)==2,"Dora completes Milu's second quest")
	expect(msg(r).contains(Bond.stage_up_text("milu",1,2)) and msg(r).contains(title("milu",2)),"Crossing six points through a quest announces the second event")
	e=entry(w,"dora","milu")
	expect(int(e.points)==7 and int(e.stage)==2,"Seven points reach the second stage")
	expect(pl(w,"dora").bonds=={"milu":rec(1,today,-1)},"Second quest also leaves bonds unchanged")
	expect(int(entry(w,"quinn","milu").points)==3,"Dora's quests do not change Quinn")

# 8. All four stages and the cap.
func test_full_progression()->void:
	var w:=World.new()
	w.add_player("erin","艾")
	var xiaoli:=cell_of(w,"xiaoli")
	stand(w,"erin",xiaoli)
	var erin:Dictionary=pl(w,"erin")
	erin.inventory.strawberry_jam=20
	var expected_points:=0
	var reached:Array=[]
	var steps:Array=[["resident_talk","xiaoli",Bond.TALK_POINTS],["resident_gift","xiaoli:strawberry_jam",Bond.LIKED_POINTS]]
	for d in range(7):
		w.state.time=float(d)*DAY+60.0
		for step:Array in steps:
			var before_stage:=Bond.stage_for(expected_points)
			expected_points=mini(Bond.LIMIT,expected_points+int(step[2]))
			var after_stage:=Bond.stage_for(expected_points)
			var jam_before:int=int(pl(w,"erin").inventory.strawberry_jam)
			var r:=act(w,"erin",str(step[0]),xiaoli,str(step[1]))
			expect(bool(r.ok),"Day %d %s succeeds"%[d,str(step[0])])
			var e:=entry(w,"erin","xiaoli")
			expect(int(e.points)==expected_points and int(e.stage)==after_stage,"Day %d %s reaches %d points"%[d,str(step[0]),expected_points])
			var record:Dictionary=pl(w,"erin").bonds.xiaoli
			expect(int(record.points)<=Bond.LIMIT,"Stored points never exceed the limit")
			var jam_after:int=int(pl(w,"erin").inventory.strawberry_jam)
			expect(jam_after==(jam_before-1 if str(step[0])=="resident_gift" else jam_before),"Day %d %s consumes the right amount of jam"%[d,str(step[0])])
			if after_stage>before_stage:
				reached.append(after_stage)
				expect(msg(r).contains(Bond.stage_up_text("xiaoli",before_stage,after_stage)) and msg(r).contains(title("xiaoli",after_stage)) and msg(r).contains(str(Bond.STAGES[after_stage-1])),"Stage %d announced with its event"%after_stage)
			else:
				expect(not msg(r).contains(RAISE),"Day %d %s announces nothing"%[d,str(step[0])])
	expect(reached==[1,2,3,4],"All four stages reached in order through talk and liked gifts")
	expect(pl(w,"erin").bonds=={"xiaoli":rec(24,6,6)},"Final stored record is capped at 24")
	expect(int(pl(w,"erin").inventory.strawberry_jam)==13,"Seven jars given over seven days")
	var top:=entry(w,"erin","xiaoli")
	expect(str(top.stage_name)=="好友" and int(top.next)==Bond.LIMIT,"Top stage reports the limit as next")
	erin=pl(w,"erin")
	erin.stories.xiaoli=4
	expect(int(entry(w,"erin","xiaoli").points)==24,"Quest-derived points do not push past 24")
	w.state.time=7.0*DAY+60.0
	var capped:=act(w,"erin","resident_talk",xiaoli,"xiaoli")
	expect(bool(capped.ok) and not msg(capped).contains(RAISE) and pl(w,"erin").bonds=={"xiaoli":rec(24,7,6)},"Capped talk still succeeds and keeps 24")
	capped=act(w,"erin","resident_gift",xiaoli,"xiaoli:strawberry_jam")
	expect(bool(capped.ok) and int(pl(w,"erin").inventory.strawberry_jam)==12 and pl(w,"erin").bonds=={"xiaoli":rec(24,7,7)},"Capped gift still succeeds, takes the jar and keeps 24")

# 9. Two players.
func test_two_players()->void:
	var w:=World.new()
	w.add_player("ann","安")
	w.add_player("ben","班")
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	stand(w,"ann",aru)
	stand(w,"ben",aru)
	var today:=today_of(w)
	var ann:Dictionary=pl(w,"ann")
	ann.inventory.tea_light=1
	var ben_view:Dictionary=view_of(w,"ben")
	var ben_inv:Dictionary=pl(w,"ben").inventory.duplicate(true)
	expect(bool(act(w,"ann","resident_talk",aru,"aru").ok),"Ann talks to Aru")
	expect(bool(act(w,"ann","resident_gift",aru,"aru:tea_light").ok),"Ann gifts Aru tea")
	expect(pl(w,"ann").bonds=={"aru":rec(4,today,today)},"Ann's record has four points")
	expect(view_of(w,"ben")==ben_view and not pl(w,"ben").has("bonds") and pl(w,"ben").inventory==ben_inv,"Ann's progress does not touch Ben")
	var ann_bonds:Variant=bonds_of(w,"ann")
	var r:=act(w,"ben","resident_talk",aru,"aru")
	expect(bool(r.ok) and msg(r).contains(title("aru",1)),"Ann's talk does not block Ben's own first talk")
	expect(pl(w,"ben").bonds=={"aru":rec(1,today,-1)} and bonds_of(w,"ann")==ann_bonds,"Ben's talk only writes Ben's record")
	w.active_tokens.erase("ben")
	var ben_bonds:Variant=bonds_of(w,"ben")
	stand(w,"ann",milu)
	expect(bool(act(w,"ann","resident_talk",milu,"milu").ok),"Ben being offline does not block Ann")
	expect(bonds_of(w,"ben")==ben_bonds and int(entry(w,"ben","milu").points)==0,"Offline Ben's progress is unchanged")
	expect(int(entry(w,"ann","milu").points)==1 and int(entry(w,"ann","aru").points)==4,"Ann keeps progress for each resident separately")

# 10 + 11 + 12. Save/reload, legacy saves and schema tampering.
func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=World.new()
	w.save_path=path
	w.add_player("sam","山")
	var aru:=cell_of(w,"aru")
	var xiaoli:=cell_of(w,"xiaoli")
	stand(w,"sam",aru)
	var p:Dictionary=pl(w,"sam")
	p.inventory.tea_light=2
	p.inventory.radish=2
	var today:=today_of(w)
	expect(bool(act(w,"sam","resident_talk",aru,"aru").ok) and bool(act(w,"sam","resident_gift",aru,"aru:tea_light").ok),"Sam talks to and gifts Aru")
	stand(w,"sam",xiaoli)
	expect(bool(act(w,"sam","resident_gift",xiaoli,"xiaoli:radish").ok),"Sam gifts Xiaoli")
	var live:Variant=bonds_of(w,"sam")
	expect(same_bonds(live,{"aru":rec(4,today,today),"xiaoli":rec(1,-1,today)}),"Live bonds before saving")
	expect(w.save(),"World saves")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the save")
	if failures>0:return
	var loaded:Variant=bonds_of(restored,"sam")
	expect(same_bonds(loaded,live),"Bonds survive reload (int-tolerant)")
	var aru_loaded:Dictionary=pl(restored,"sam").bonds.aru
	expect(typeof(aru_loaded.points)==TYPE_INT and typeof(aru_loaded.talk_day)==TYPE_INT and typeof(aru_loaded.gift_day)==TYPE_INT,"Validation normalizes reloaded bond fields to ints")
	expect(view_of(restored,"sam")==view_of(w,"sam"),"Reloaded view matches the live view")
	var e:=entry(restored,"sam","aru")
	expect(e.talked_today==true and e.gifted_today==true,"Daily flags still set after reload")
	stand(restored,"sam",aru)
	expect_rejected(restored,"sam","resident_talk",aru,"aru","Repeat talk after reload the same day")
	stand(restored,"sam",xiaoli)
	var r:=act(restored,"sam","resident_gift",xiaoli,"xiaoli:radish")
	expect(bool(r.ok) and int(pl(restored,"sam").inventory.radish)==0,"Repeat gift after reload is still taken")
	expect(same_bonds(bonds_of(restored,"sam"),live),"Repeat gift after reload adds no points")
	restored.state.time=float(restored.state.time)+DAY
	stand(restored,"sam",aru)
	r=act(restored,"sam","resident_talk",aru,"aru")
	expect(bool(r.ok) and same_bonds(bonds_of(restored,"sam"),{"aru":rec(5,today+1,today),"xiaoli":rec(1,-1,today)}),"Next-day talk after reload counts")
	# 11. Legacy save without bonds but with stories.
	var base:Dictionary=w.state.duplicate(true)
	var old:Dictionary=base.duplicate(true)
	var old_sam:Dictionary=old.players.sam
	old_sam.erase("bonds")
	old_sam.stories={"aru":2,"milu":3,"xiaoli":0,"bobo":0}
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without bonds loads")
	if failures>0:return
	expect(not pl(legacy,"sam").has("bonds"),"Loading does not invent a bonds key")
	var la:=entry(legacy,"sam","aru")
	var lm:=entry(legacy,"sam","milu")
	expect(int(la.points)==6 and int(la.stage)==2,"Two Aru stories derive six points")
	expect(int(lm.points)==9 and int(lm.stage)==2,"Three Milu stories derive nine points")
	expect(int(entry(legacy,"sam","xiaoli").points)==0 and int(entry(legacy,"sam","bobo").points)==0,"Residents without stories stay at zero")
	# 12. Schema tampering.
	expect(write_fixture(fixture,base),"Write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same_bonds(bonds_of(control,"sam"),live),"Control: the unmodified fixture loads with its bonds")
	if failures>0:return
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var tampers:Array=[
		["unknown resident key",{"aru":rec(4,today,today),"tom":rec(1,today,-1)}],
		["points 25",{"aru":rec(25,today,today)}],
		["negative points",{"aru":rec(-1,today,today)}],
		["fractional points",{"aru":{"points":1.5,"talk_day":today,"gift_day":today}}],
		["string points",{"aru":{"points":"4","talk_day":today,"gift_day":today}}],
		["talk_day in the future",{"aru":rec(4,today+1,today)}],
		["gift_day in the future",{"aru":rec(4,today,today+1)}],
		["day below -1",{"aru":rec(4,-2,today)}],
		["extra field",{"aru":{"points":4,"talk_day":today,"gift_day":today,"mood":1}}],
		["missing field",{"aru":{"points":4,"talk_day":today}}],
		["non-dictionary record",{"aru":4}],
		["non-dictionary bonds (array)",[]],
		["non-dictionary bonds (string)","aru"],
		["null bonds",null],
		["all-default record",{"aru":rec(0,-1,-1)}],
	]
	for tamper:Array in tampers:
		var bad:Dictionary=base.duplicate(true)
		var bad_sam:Dictionary=bad.players.sam
		bad_sam.bonds=tamper[1]
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+str(tamper[0]))
		expect(not probe.load_world(fixture),"Schema rejects "+str(tamper[0]))
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+str(tamper[0]))
	expect(not FileAccess.file_exists(fixture+".bak"),"Fixture never had a backup to fall back to")

# 13. Local residents outside Village.NPCS: chacha (maokong) and xinghe (lanyang).
func test_local_residents()->void:
	# [resident, liked non-common item, another resident's liked non-common item, the other local resident]
	var setups:Array=[["chacha","tea_leaf","crystal_sand","xinghe"],["xinghe","sapling","strawberry_jam","chacha"]]
	for setup:Array in setups:
		var resident:=str(setup[0])
		var liked:=str(setup[1])
		var foreign:=str(setup[2])
		expect(Bond.liked(resident,liked) and liked not in Bond.COMMON_GIFTS,"%s fixture: %s is a liked, non-common gift"%[resident,liked])
		expect(not Bond.giftable(resident,foreign) and foreign not in Bond.COMMON_GIFTS,"%s fixture: %s is not a gift for her"%[resident,foreign])
		local_daily(resident,liked,foreign,str(setup[3]))
		local_progression(resident,liked)
	test_local_story_points()
	test_greenhouse_report()
	test_local_two_players()
	test_local_save_reload()

func local_daily(resident:String,liked:String,foreign:String,other:String)->void:
	var w:=World.new()
	var token:="local-"+resident
	w.add_player(token,"在")
	var region:=region_of(w,resident)
	var cell:=cell_of(w,resident)
	var who:=Bond.name_of(resident)
	var p:Dictionary=pl(w,token)
	p.inventory[liked]=3
	p.inventory.radish=2
	p.inventory.wood=5
	p.inventory[foreign]=1
	var talk_extra:=resident
	var gift_extra:="%s:%s"%[resident,liked]
	# 1. Outside her region (home, the other local region, jinguashi): rejected.
	go(w,token,"home",cell)
	expect_rejected(w,token,"resident_talk",cell,talk_extra,"%s: talk from home aimed at her cell"%resident)
	expect_rejected(w,token,"resident_gift",cell,gift_extra,"%s: gift from home aimed at her cell"%resident)
	go(w,token,region_of(w,other),cell)
	expect_rejected(w,token,"resident_talk",cell,talk_extra,"%s: talk from %s's region"%[resident,other])
	expect_rejected(w,token,"resident_gift",cell,gift_extra,"%s: gift from %s's region"%[resident,other])
	go(w,token,"jinguashi",cell)
	expect_rejected(w,token,"resident_talk",cell,talk_extra,"%s: talk from jinguashi"%resident)
	expect(not pl(w,token).has("bonds"),"%s: rejections outside her region create no bonds key"%resident)
	# 2. Right region, wrong cell or out of reach.
	go(w,token,region,cell)
	expect_rejected(w,token,"resident_talk",cell+Vector2i.RIGHT,talk_extra,"%s: talk aimed at the tile beside her"%resident)
	expect_rejected(w,token,"resident_gift",cell+Vector2i.RIGHT,gift_extra,"%s: gift aimed at the tile beside her"%resident)
	expect_rejected(w,token,"resident_talk",cell+Vector2i.DOWN,talk_extra,"%s: talk aimed at the tile below her"%resident)
	expect_rejected(w,token,"resident_talk",cell,"aru","%s: Aru cannot be talked to at her cell"%resident)
	expect_rejected(w,token,"resident_talk",cell,other,"%s: %s cannot be talked to at her cell"%[resident,other])
	p=pl(w,token)
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+5.5
	expect_rejected(w,token,"resident_talk",cell,talk_extra,"%s: talking from five tiles away"%resident)
	expect_rejected(w,token,"resident_gift",cell,gift_extra,"%s: gifting from five tiles away"%resident)
	expect(not pl(w,token).has("bonds"),"%s: no rejected action created a bonds key"%resident)
	# 3. Right region, right cell.
	stand(w,token,cell)
	var today:=today_of(w)
	var before:Dictionary=pl(w,token).inventory.duplicate(true)
	var r:=act(w,token,"resident_talk",cell,talk_extra)
	expect(bool(r.ok),"%s: first talk succeeds (%s)"%[resident,msg(r)])
	expect(msg(r).contains(who) and msg(r).contains(title(resident,1)) and msg(r).contains(Bond.stage_up_text(resident,0,1)),"%s: first talk names her and announces the first event"%resident)
	expect(pl(w,token).bonds=={resident:rec(1,today,-1)},"%s: first talk stores one point"%resident)
	expect(pl(w,token).inventory==before,"%s: talking changes no inventory"%resident)
	expect_rejected(w,token,"resident_talk",cell,talk_extra,"%s: second talk the same day"%resident)
	before=pl(w,token).inventory.duplicate(true)
	r=act(w,token,"resident_gift",cell,gift_extra)
	var expected:Dictionary=before.duplicate(true)
	expected[liked]=int(before[liked])-1
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.get(liked,"?missing-name?"))) and not msg(r).contains(RAISE),"%s: liked gift accepted without a stage-up"%resident)
	expect(pl(w,token).inventory==expected,"%s: liked gift removes exactly one item"%resident)
	expect(pl(w,token).bonds=={resident:rec(4,today,today)},"%s: liked gift adds three points"%resident)
	before=pl(w,token).inventory.duplicate(true)
	r=act(w,token,"resident_gift",cell,gift_extra)
	expected=before.duplicate(true)
	expected[liked]=int(before[liked])-1
	expect(bool(r.ok) and msg(r).contains("明天") and not msg(r).contains(RAISE),"%s: second gift the same day is accepted"%resident)
	expect(pl(w,token).inventory==expected,"%s: second gift removes exactly one item"%resident)
	expect(pl(w,token).bonds=={resident:rec(4,today,today)},"%s: second gift the same day adds no points"%resident)
	expect_rejected(w,token,"resident_gift",cell,"%s:wood"%resident,"%s: non-giftable wood"%resident)
	expect_rejected(w,token,"resident_gift",cell,"%s:%s"%[resident,foreign],"%s: another resident's liked %s"%[resident,foreign])
	# Next day: common gift +1, then a talk crosses into stage 2.
	w.state.time=float(w.state.time)+DAY
	before=pl(w,token).inventory.duplicate(true)
	r=act(w,token,"resident_gift",cell,"%s:radish"%resident)
	expected=before.duplicate(true)
	expected.radish=int(before.radish)-1
	expect(bool(r.ok) and msg(r).contains("向你道謝") and not msg(r).contains(RAISE),"%s: next-day common gift accepted"%resident)
	expect(pl(w,token).inventory==expected,"%s: common gift removes exactly one radish"%resident)
	expect(pl(w,token).bonds=={resident:rec(5,today,today+1)},"%s: common gift adds exactly one point"%resident)
	r=act(w,token,"resident_talk",cell,talk_extra)
	expect(bool(r.ok) and msg(r).contains(Bond.stage_up_text(resident,1,2)) and msg(r).contains(title(resident,2)),"%s: next-day talk announces the second event"%resident)
	expect(pl(w,token).bonds=={resident:rec(6,today+1,today+1)},"%s: next-day talk adds one point"%resident)
	var e:=entry(w,token,resident)
	expect(int(e.points)==6 and int(e.stage)==2 and str(e.stage_name)=="熟悉" and int(e.next)==14 and e.talked_today==true and e.gifted_today==true,"%s: view after two days"%resident)
	for someone:String in Bond.RESIDENTS:
		if someone!=resident:expect(int(entry(w,token,someone).points)==0,"%s: %s untouched"%[resident,someone])

## `preset` is written straight into world state (PRESET), e.g. {"picnic":true}
## so 棉棉 is at the ranch, {"dock_stage":1} so 阿潮 is at the dock.
func local_progression(resident:String,liked:String,preset:Dictionary={})->void:
	var w:=World.new()
	var token:="climb-"+resident
	w.add_player(token,"攀")
	for field:String in preset:w.state[field]=preset[field]
	expect(Bond.present(w.state,resident),"%s progression fixture: she/he is present"%resident)
	var cell:=cell_of(w,resident)
	go(w,token,region_of(w,resident),cell)
	var p:Dictionary=pl(w,token)
	p.inventory[liked]=20
	var expected_points:=0
	var reached:Array=[]
	var steps:Array=[["resident_talk",resident,Bond.TALK_POINTS],["resident_gift","%s:%s"%[resident,liked],Bond.LIKED_POINTS]]
	for d in range(7):
		w.state.time=float(d)*DAY+60.0
		for step:Array in steps:
			var before_stage:=Bond.stage_for(expected_points)
			expected_points=mini(Bond.LIMIT,expected_points+int(step[2]))
			var after_stage:=Bond.stage_for(expected_points)
			var held_before:int=int(pl(w,token).inventory[liked])
			var r:=act(w,token,str(step[0]),cell,str(step[1]))
			expect(bool(r.ok),"%s day %d %s succeeds"%[resident,d,str(step[0])])
			var e:=entry(w,token,resident)
			expect(int(e.points)==expected_points and int(e.stage)==after_stage,"%s day %d %s reaches %d points"%[resident,d,str(step[0]),expected_points])
			var stored:Dictionary=pl(w,token).bonds[resident]
			expect(int(stored.points)<=Bond.LIMIT,"%s stored points never exceed the limit"%resident)
			var held_after:int=int(pl(w,token).inventory[liked])
			expect(held_after==(held_before-1 if str(step[0])=="resident_gift" else held_before),"%s day %d %s consumes the right amount"%[resident,d,str(step[0])])
			if after_stage>before_stage:
				reached.append(after_stage)
				expect(msg(r).contains(Bond.stage_up_text(resident,before_stage,after_stage)) and msg(r).contains(title(resident,after_stage)) and msg(r).contains(str(Bond.STAGES[after_stage-1])),"%s stage %d announced with its event"%[resident,after_stage])
			else:
				expect(not msg(r).contains(RAISE),"%s day %d %s announces nothing"%[resident,d,str(step[0])])
	expect(reached==[1,2,3,4],"%s: all four stages reached in order"%resident)
	expect(pl(w,token).bonds=={resident:rec(24,6,6)},"%s: final stored record is capped at 24"%resident)
	expect(int(pl(w,token).inventory[liked])==13,"%s: seven liked gifts given over seven days"%resident)
	var top:=entry(w,token,resident)
	expect(str(top.stage_name)=="好友" and int(top.next)==Bond.LIMIT,"%s: top stage reports the limit as next"%resident)
	w.state.time=7.0*DAY+60.0
	var capped:=act(w,token,"resident_talk",cell,resident)
	expect(bool(capped.ok) and not msg(capped).contains(RAISE) and pl(w,token).bonds=={resident:rec(24,7,6)},"%s: capped talk still succeeds and keeps 24"%resident)

func test_local_story_points()->void:
	var w:=World.new()
	w.add_player("flag","旗")
	var p:Dictionary=pl(w,"flag")
	p.greenhouse_reported=true
	var e:=entry(w,"flag","xinghe")
	expect(int(e.points)==Bond.STORY_POINTS and int(e.stage)==Bond.stage_for(Bond.STORY_POINTS),"greenhouse_reported derives three points for xinghe")
	expect(not pl(w,"flag").has("bonds"),"Flag-derived points write no bonds key")
	expect(int(entry(w,"flag","chacha").points)==0 and int(entry(w,"flag","aru").points)==0,"greenhouse_reported gives chacha and aru nothing")
	p=pl(w,"flag")
	var stories:Dictionary=p.stories
	stories["chacha"]=4
	stories["xinghe"]=4
	expect(int(entry(w,"flag","chacha").points)==0,"stories.chacha gives chacha nothing")
	expect(int(entry(w,"flag","xinghe").points)==Bond.STORY_POINTS,"stories.xinghe is ignored; only the flag counts")
	var today:=today_of(w)
	p.bonds={"xinghe":rec(12,today,-1)}
	e=entry(w,"flag","xinghe")
	expect(int(e.points)==15 and int(e.stage)==3,"Stored 12 plus the flag gives 15 points (stage 3)")
	var stored:Dictionary={"bonds":{"xinghe":rec(12,0,0)},"greenhouse_reported":true}
	expect(Bond.points(stored,"xinghe")==15 and Bond.stage(stored,"xinghe")==3,"Pure rule: 12 stored plus flag is 15")
	var near_cap:Dictionary={"bonds":{"xinghe":rec(23,0,0)},"greenhouse_reported":true}
	expect(Bond.points(near_cap,"xinghe")==24,"Stored 23 plus flag caps at 24")
	var at_cap:Dictionary={"bonds":{"xinghe":rec(24,0,0)},"greenhouse_reported":true}
	expect(Bond.points(at_cap,"xinghe")==24 and Bond.stage(at_cap,"xinghe")==4,"Stored 24 plus flag stays 24")
	var unset:Dictionary={"bonds":{"xinghe":rec(12,0,0)},"greenhouse_reported":false}
	expect(Bond.points(unset,"xinghe")==12,"A false flag derives nothing")
	var not_bool:Dictionary={"greenhouse_reported":1}
	expect(Bond.points(not_bool,"xinghe")==0,"A non-bool flag derives nothing")
	var cha:Dictionary={"stories":{"chacha":4},"greenhouse_reported":true,"bonds":{"chacha":rec(2,0,0)}}
	expect(Bond.points(cha,"chacha")==2,"chacha has no derived points from stories or the greenhouse flag")

func test_greenhouse_report()->void:
	expect(Bond.stage_for(0)<Bond.stage_for(Bond.STORY_POINTS) and Bond.stage_for(3)<Bond.stage_for(3+Bond.STORY_POINTS),"Fixture: 0->3 and 3->6 both cross a threshold")
	var w:=World.new()
	var service:=cell_of(w,"xinghe")
	expect(service==World.LANYANG_LIFE.SERVICE,"xinghe stands at the Lanyang service point")
	var today:=today_of(w)
	var cases:Array=[["gh-three",3],["gh-zero",0],["gh-one",1]]
	for item:Array in cases:
		var token:=str(item[0])
		var stored:=int(item[1])
		w.add_player(token,"溫")
		go(w,token,World.REGIONS.LANYANG,service)
		var p:Dictionary=pl(w,token)
		p.greenhouse_glass_crafted=true
		p.greenhouse_cross_season_crop="radish"
		if stored>0:p.bonds={"xinghe":rec(stored,today,-1)}
	# Prerequisite gate: without glass the report is rejected and gives nothing.
	w.add_player("gh-none","無")
	go(w,"gh-none",World.REGIONS.LANYANG,service)
	expect_rejected(w,"gh-none","greenhouse_report",service,"","Greenhouse report without glass or a cross-season crop")
	expect(not bool(pl(w,"gh-none").get("greenhouse_reported",false)) and int(entry(w,"gh-none","xinghe").points)==0,"Rejected report sets no flag and no points")
	for item:Array in cases:
		var token:=str(item[0])
		var stored:=int(item[1])
		var bonds_before:Variant=bonds_of(w,token)
		var had_bonds:bool=pl(w,token).has("bonds")
		var before_stage:=Bond.stage_for(stored)
		var total:=mini(Bond.LIMIT,stored+Bond.STORY_POINTS)
		var after_stage:=Bond.stage_for(total)
		var r:=act(w,token,"greenhouse_report",service,"")
		expect(bool(r.ok) and bool(pl(w,token).get("greenhouse_reported",false)),"Greenhouse report with %d stored points succeeds"%stored)
		if after_stage>before_stage:
			expect(msg(r).contains(RAISE) and msg(r).contains(Bond.stage_up_text("xinghe",before_stage,after_stage)) and msg(r).contains(title("xinghe",after_stage)),"Report %d->%d announces xinghe stage %d"%[stored,total,after_stage])
		else:
			expect(not msg(r).contains(RAISE),"Report %d->%d announces no stage"%[stored,total])
		expect(pl(w,token).has("bonds")==had_bonds and bonds_of(w,token)==bonds_before,"Report with %d stored points leaves stored bonds unchanged"%stored)
		var e:=entry(w,token,"xinghe")
		expect(int(e.points)==total and int(e.stage)==after_stage,"After the report xinghe shows %d points"%total)
		expect_rejected(w,token,"greenhouse_report",service,"","Second greenhouse report (%d stored)"%stored)
	expect(int(entry(w,"gh-none","xinghe").points)==0,"Other players' reports do not change gh-none")

func test_local_two_players()->void:
	var w:=World.new()
	w.add_player("ann","安")
	w.add_player("ben","班")
	var chacha:=cell_of(w,"chacha")
	var xinghe:=cell_of(w,"xinghe")
	go(w,"ann",region_of(w,"chacha"),chacha)
	go(w,"ben",region_of(w,"chacha"),chacha)
	var today:=today_of(w)
	var ann:Dictionary=pl(w,"ann")
	ann.inventory.tea_leaf=1
	var ben_view:Dictionary=view_of(w,"ben")
	var ben_inv:Dictionary=pl(w,"ben").inventory.duplicate(true)
	expect(bool(act(w,"ann","resident_talk",chacha,"chacha").ok),"Ann talks to chacha")
	expect(bool(act(w,"ann","resident_gift",chacha,"chacha:tea_leaf").ok),"Ann gifts chacha tea leaves")
	expect(pl(w,"ann").bonds=={"chacha":rec(4,today,today)},"Ann's chacha record has four points")
	expect(view_of(w,"ben")==ben_view and not pl(w,"ben").has("bonds") and pl(w,"ben").inventory==ben_inv,"Ann's chacha progress does not touch Ben")
	var ann_bonds:Variant=bonds_of(w,"ann")
	var r:=act(w,"ben","resident_talk",chacha,"chacha")
	expect(bool(r.ok) and msg(r).contains(title("chacha",1)),"Ann's talk does not block Ben's first chacha talk")
	expect(pl(w,"ben").bonds=={"chacha":rec(1,today,-1)} and bonds_of(w,"ann")==ann_bonds,"Ben's chacha talk only writes Ben's record")
	go(w,"ann",region_of(w,"xinghe"),xinghe)
	go(w,"ben",region_of(w,"xinghe"),xinghe)
	ann=pl(w,"ann")
	ann.greenhouse_reported=true
	ben_view=view_of(w,"ben")
	expect(int(entry(w,"ben","xinghe").points)==0,"Ann's greenhouse flag gives Ben nothing")
	expect(bool(act(w,"ann","resident_talk",xinghe,"xinghe").ok),"Ann talks to xinghe")
	expect(int(entry(w,"ann","xinghe").points)==1+Bond.STORY_POINTS,"Ann's xinghe points include her own flag")
	expect(view_of(w,"ben")==ben_view,"Ann's xinghe progress does not change Ben's view")
	var ben_bonds:Variant=bonds_of(w,"ben")
	r=act(w,"ben","resident_talk",xinghe,"xinghe")
	expect(bool(r.ok) and int(entry(w,"ben","xinghe").points)==1,"Ben's own xinghe talk gives him one point")
	expect(same_bonds(bonds_of(w,"ben"),{"chacha":rec(1,today,-1),"xinghe":rec(1,today,-1)}) and ben_bonds!=bonds_of(w,"ben"),"Ben's records hold only his own talks")
	expect(int(entry(w,"ann","chacha").points)==4 and int(entry(w,"ann","xinghe").points)==4,"Ann keeps separate progress per local resident")

func test_local_save_reload()->void:
	var path:=temp_path("local-world")
	var fixture:=temp_path("local-fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=World.new()
	w.save_path=path
	w.add_player("lia","莉")
	var p:Dictionary=pl(w,"lia")
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	p.inventory.tea_leaf=2
	p.inventory.sapling=2
	var chacha:=cell_of(w,"chacha")
	var xinghe:=cell_of(w,"xinghe")
	var today:=today_of(w)
	go(w,"lia",region_of(w,"chacha"),chacha)
	expect(bool(act(w,"lia","resident_talk",chacha,"chacha").ok) and bool(act(w,"lia","resident_gift",chacha,"chacha:tea_leaf").ok),"Lia talks to and gifts chacha")
	go(w,"lia",region_of(w,"xinghe"),xinghe)
	expect(bool(act(w,"lia","resident_gift",xinghe,"xinghe:sapling").ok),"Lia gifts xinghe a sapling")
	var live:Variant=bonds_of(w,"lia")
	expect(same_bonds(live,{"chacha":rec(4,today,today),"xinghe":rec(3,-1,today)}),"Live local bonds before saving")
	# Save from home so the reload does not depend on regional standing spots.
	p=pl(w,"lia")
	p.region="home"
	p.x=home_x
	p.y=home_y
	expect(w.save(),"World with local bonds saves")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the local-bond save")
	if failures>0:return
	expect(same_bonds(bonds_of(restored,"lia"),live),"Local bonds survive reload (int-tolerant)")
	var cha_loaded:Dictionary=pl(restored,"lia").bonds.chacha
	expect(typeof(cha_loaded.points)==TYPE_INT and typeof(cha_loaded.talk_day)==TYPE_INT and typeof(cha_loaded.gift_day)==TYPE_INT,"Reloaded chacha fields are ints")
	expect(view_of(restored,"lia")==view_of(w,"lia"),"Reloaded view matches the live view")
	go(restored,"lia",region_of(restored,"chacha"),chacha)
	expect_rejected(restored,"lia","resident_talk",chacha,"chacha","Repeat chacha talk after reload the same day")
	restored.state.time=float(restored.state.time)+DAY
	var r:=act(restored,"lia","resident_talk",chacha,"chacha")
	expect(bool(r.ok) and same_bonds(bonds_of(restored,"lia"),{"chacha":rec(5,today+1,today),"xinghe":rec(3,-1,today)}),"Next-day chacha talk after reload counts")
	# Schema: a record for every resident loads; unknown ids, one entry more than the list and 25 points do not.
	# (`six`/`seven` are historical names: they hold Bond.RESIDENTS.size() and one more.)
	var base:Dictionary=w.state.duplicate(true)
	var six:Dictionary={}
	for resident:String in Bond.RESIDENTS:six[resident]=rec(1,today,-1)
	var good:Dictionary=base.duplicate(true)
	var good_lia:Dictionary=good.players.lia
	good_lia.bonds=six
	expect(six.size()==12 and six.has("diandian"),"Fixture holds a record for each of the twelve residents (incl. diandian)")
	expect(write_fixture(fixture,good),"Write all-resident fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same_bonds(bonds_of(control,"lia"),six),"Control: a record for each of the twelve residents loads")
	if failures>0:return
	var seven:Dictionary=six.duplicate(true)
	seven["tom"]=rec(1,today,-1)
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var tampers:Array=[
		["unknown resident beside chacha",{"chacha":rec(4,today,today),"tom":rec(1,today,-1)}],
		["one entry more than the resident list",seven],
		["chacha points 25",{"chacha":rec(25,today,today)}],
		["xinghe talk_day in the future",{"xinghe":rec(1,today+1,-1)}],
		["chacha all-default record",{"chacha":rec(0,-1,-1)}],
	]
	for tamper:Array in tampers:
		var bad:Dictionary=base.duplicate(true)
		var bad_lia:Dictionary=bad.players.lia
		bad_lia.bonds=tamper[1]
		expect(write_fixture(fixture,bad),"Write local tampered fixture: "+str(tamper[0]))
		expect(not probe.load_world(fixture),"Schema rejects "+str(tamper[0]))
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+str(tamper[0]))

# 14. 棉棉 (mianmian): third-batch local resident beside the ferry feed stations.
# PRESET everywhere below: state.picnic, player position, inventory, world time.
func test_ranch_resident()->void:
	var first:Vector2i=Bond.RANCH_CELLS[0]
	expect(Bond.RANCH_CELLS.size()==4 and first==Vector2i(49,33),"Ranch has four candidate cells starting at 49,33")
	var probe:=World.new()
	for cell:Vector2i in Bond.RANCH_CELLS:
		expect(probe.is_land(cell) and not probe.water(cell) and not probe.blocked(cell) and probe.resource(cell)=="","Ranch cell %s is open land on a fresh island"%str(cell))
		expect(not probe.protected(cell),"Ranch cell %s is ordinary buildable ground (not reserved)"%str(cell))
		for animal:String in World.LIVESTOCK.ANIMALS:
			var spot:Vector2i=World.LIVESTOCK.ANIMALS[animal].cell
			expect(cell!=spot and cell!=World.LIVESTOCK.collector_cell(animal),"Ranch cell %s is not the %s feed station or its collector"%[str(cell),animal])
			expect(Vector2(cell-spot).length()<=4.0,"Ranch cell %s stays beside the %s feed station"%[str(cell),animal])
	# Picnic gate: before the picnic she is not there.
	var w:=World.new()
	w.add_player("mei","梅")
	var p:Dictionary=pl(w,"mei")
	p.inventory.feed=3
	p.inventory.wool=2
	p.inventory.wool_cloth=1
	p.inventory.radish=2
	p.inventory.wood=4
	p.inventory.tea_leaf=1
	stand(w,"mei",first)
	expect(not bool(w.state.picnic),"Fresh world has no picnic yet")
	var locked:=act(w,"mei","resident_talk",first,"mianmian")
	expect(not bool(locked.ok) and msg(locked)==Bond.RANCH_LOCKED,"Before the picnic the talk is refused with the ranch message")
	expect_rejected(w,"mei","resident_talk",first,"mianmian","mianmian: talk before picnic")
	expect_rejected(w,"mei","resident_gift",first,"mianmian:feed","mianmian: gift before picnic")
	expect(not pl(w,"mei").has("bonds"),"mianmian: pre-picnic rejections write no bonds key")
	w.state.picnic=true
	# Wrong region, wrong cell, out of reach.
	expect_rejected(w,"mei","resident_talk",first+Vector2i.RIGHT,"mianmian","mianmian: talk aimed beside her")
	expect_rejected(w,"mei","resident_talk",first,"chacha","mianmian: chacha cannot be talked to at the ranch")
	expect_rejected(w,"mei","resident_talk",cell_of(w,"aru"),"mianmian","mianmian: not reachable at Aru's cell")
	go(w,"mei","lanyang",first)
	expect_rejected(w,"mei","resident_talk",first,"mianmian","mianmian: talk from lanyang")
	go(w,"mei","home",first)
	p=pl(w,"mei")
	p.y=float(first.y)+5.5
	expect_rejected(w,"mei","resident_talk",first,"mianmian","mianmian: talk from five tiles away")
	expect(not pl(w,"mei").has("bonds"),"mianmian: no rejection created a bonds key")
	# Daily rules at her cell.
	stand(w,"mei",first)
	var today:=today_of(w)
	var before:Dictionary=pl(w,"mei").inventory.duplicate(true)
	var r:=act(w,"mei","resident_talk",first,"mianmian")
	expect(bool(r.ok) and msg(r).contains("棉棉") and msg(r).contains(title("mianmian",1)),"mianmian: first talk names her and announces the first event")
	expect(pl(w,"mei").bonds=={"mianmian":rec(1,today,-1)} and pl(w,"mei").inventory==before,"mianmian: first talk stores one point and moves no items")
	expect_rejected(w,"mei","resident_talk",first,"mianmian","mianmian: second talk the same day")
	for liked:String in ["feed","wool","wool_cloth"]:
		expect(Bond.liked("mianmian",liked) and liked not in Bond.COMMON_GIFTS,"mianmian: %s is a liked, non-common gift"%liked)
	r=act(w,"mei","resident_gift",first,"mianmian:wool_cloth")
	var expected:Dictionary=before.duplicate(true)
	expected.wool_cloth=0
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.wool_cloth)),"mianmian: wool cloth is a favourite")
	expect(pl(w,"mei").inventory==expected and pl(w,"mei").bonds=={"mianmian":rec(4,today,today)},"mianmian: favourite gift takes one item and adds three points")
	r=act(w,"mei","resident_gift",first,"mianmian:feed")
	expected.feed=2
	expect(bool(r.ok) and msg(r).contains("明天") and pl(w,"mei").inventory==expected and pl(w,"mei").bonds=={"mianmian":rec(4,today,today)},"mianmian: second gift the same day is taken without points")
	expect_rejected(w,"mei","resident_gift",first,"mianmian:wood","mianmian: wood is not a gift")
	expect_rejected(w,"mei","resident_gift",first,"mianmian:tea_leaf","mianmian: chacha's tea leaf is not her gift")
	expect_rejected(w,"mei","resident_gift",first,"mianmian:wool_cloth","mianmian: cannot gift cloth she no longer holds")
	w.state.time=float(w.state.time)+DAY
	r=act(w,"mei","resident_gift",first,"mianmian:radish")
	expected.radish=1
	expect(bool(r.ok) and msg(r).contains("向你道謝") and pl(w,"mei").inventory==expected and pl(w,"mei").bonds=={"mianmian":rec(5,today,today+1)},"mianmian: next-day common gift adds one point")
	r=act(w,"mei","resident_talk",first,"mianmian")
	expect(bool(r.ok) and msg(r).contains(title("mianmian",2)) and pl(w,"mei").bonds=={"mianmian":rec(6,today+1,today+1)},"mianmian: next-day talk reaches the second stage")
	for someone:String in Bond.RESIDENTS:
		if someone!="mianmian":expect(int(entry(w,"mei",someone).points)==0,"mianmian: %s untouched"%someone)
	# Livestock petting is island-wide state and gives her no points.
	expect(Bond.story_count(pl(w,"mei"),"mianmian")==0 and not Bond.STORY_FLAGS.has("mianmian"),"mianmian has no commission-derived points")
	# Occupied first cell: she stands at the next free candidate for server and client alike.
	var second:Vector2i=Bond.RANCH_CELLS[1]
	w.state.objects[w.key(first)]={"type":"wall","owner":"mei"}
	expect(cell_of(w,"mianmian")==second,"A building on 49,33 moves her to the second candidate")
	stand(w,"mei",first)
	w.state.time=float(w.state.time)+DAY
	expect_rejected(w,"mei","resident_talk",first,"mianmian","mianmian: talk at the old cell once she has moved")
	stand(w,"mei",second)
	r=act(w,"mei","resident_talk",second,"mianmian")
	expect(bool(r.ok) and int(pl(w,"mei").bonds.mianmian.points)==7,"mianmian: talk works at the fallback cell")
	w.state.crops[w.key(second)]={"type":"radish","owner":"mei"}
	expect(cell_of(w,"mianmian")==Bond.RANCH_CELLS[2],"A crop on the second cell moves her to the third")
	for cell:Vector2i in Bond.RANCH_CELLS:w.state.objects[w.key(cell)]={"type":"wall","owner":"mei"}
	expect(cell_of(w,"mianmian")==first,"With every candidate taken she stays on the first cell")
	expect(Bond.ranch_cell({})==first and Bond.ranch_cell({"objects":7})==first,"ranch_cell tolerates missing or malformed layers")
	# Four stages over seven world days, then save and reload.
	local_progression("mianmian","feed",{"picnic":true})
	var path:=temp_path("ranch-world")
	_cleanup.append(path)
	var saved:=World.new()
	saved.save_path=path
	saved.add_player("nia","妮")
	saved.state.picnic=true
	pl(saved,"nia").inventory.wool=1
	stand(saved,"nia",first)
	var day_saved:=today_of(saved)
	expect(bool(act(saved,"nia","resident_talk",first,"mianmian").ok) and bool(act(saved,"nia","resident_gift",first,"mianmian:wool").ok),"Nia talks to and gifts mianmian")
	expect(saved.save(),"World with a mianmian bond saves")
	var restored:=World.new()
	expect(restored.load_world(path),"World with a mianmian bond reloads")
	if failures>0:return
	expect(same_bonds(bonds_of(restored,"nia"),{"mianmian":rec(4,day_saved,day_saved)}),"mianmian bond survives reload")
	expect(view_of(restored,"nia")==view_of(saved,"nia"),"Reloaded view matches the live view (mianmian)")
	expect_rejected(restored,"nia","resident_talk",first,"mianmian","mianmian: repeat talk after reload the same day")

# 15. 阿潮 (achao): fourth-batch local resident at the home dock, present once
# dock_stage>=1. PRESET everywhere below: state.dock_stage, state.picnic,
# objects/crops/forest entries, player position, inventory, world time.
func test_dock_resident()->void:
	var first:Vector2i=Bond.DOCK_CELLS[0]
	expect(Bond.DOCK_CELLS==[Vector2i(49,30),Vector2i(50,30),Vector2i(49,31),Vector2i(50,31)],"Dock has four candidate cells 49,30 50,30 49,31 50,31 in order")
	var probe:=World.new()
	for cell:Vector2i in Bond.DOCK_CELLS:
		expect(probe.is_land(cell) and not probe.water(cell) and not probe.blocked(cell) and probe.resource(cell)=="","Dock cell %s is open land on a fresh island"%str(cell))
		for spot:Vector2i in [cell,cell+Vector2i.DOWN]:
			var found:=World.base_resource(spot)
			expect(found!="tree" and found!="rock","No fixed tree/rock at %s (dock cell %s or the cell below): '%s'"%[str(spot),str(cell),found])
	# Pure gate rules.
	expect(Bond.locked_reason({},"achao")==Bond.DOCK_LOCKED and Bond.locked_reason({"dock_stage":0},"achao")==Bond.DOCK_LOCKED,"locked_reason: no dock_stage or dock_stage 0 gives DOCK_LOCKED")
	expect(Bond.locked_reason({"dock_stage":1},"achao")=="" and Bond.present({"dock_stage":1},"achao") and Bond.present({"dock_stage":2},"achao"),"dock_stage 1 and 2 make achao present")
	expect(Bond.locked_reason({"picnic":true},"achao")==Bond.DOCK_LOCKED and not Bond.present({"picnic":true},"achao"),"The picnic alone does not bring achao")
	expect(Bond.present({"dock_stage":1},"mianmian")==false and Bond.present({"picnic":true},"achao")==false,"Each gate only opens its own resident")
	# Before the dock repair he is not there.
	var w:=World.new()
	w.add_player("kai","凱")
	var p:Dictionary=pl(w,"kai")
	p.inventory.fiber=2
	p.inventory.salt_grilled_fish=1
	p.inventory.radish=2
	p.inventory.wood=4
	p.inventory.feed=1
	stand(w,"kai",first)
	expect(int(w.state.get("dock_stage",0))==0,"Fresh world has no dock repair yet")
	expect(region_of(w,"achao")=="home" and cell_of(w,"achao")==first,"bond_place(achao) is home 49,30 even before the repair")
	var locked:=act(w,"kai","resident_talk",first,"achao")
	expect(not bool(locked.ok) and msg(locked)==Bond.DOCK_LOCKED,"Before the repair the talk is refused with the dock message")
	locked=act(w,"kai","resident_gift",first,"achao:fiber")
	expect(not bool(locked.ok) and msg(locked)==Bond.DOCK_LOCKED,"Before the repair the gift is refused with the dock message")
	expect_rejected(w,"kai","resident_talk",first,"achao","achao: talk before the repair")
	expect_rejected(w,"kai","resident_gift",first,"achao:fiber","achao: liked gift before the repair")
	expect_rejected(w,"kai","resident_gift",first,"achao:radish","achao: common gift before the repair")
	w.state.picnic=true
	locked=act(w,"kai","resident_talk",first,"achao")
	expect(not bool(locked.ok) and msg(locked)==Bond.DOCK_LOCKED,"The picnic does not open the dock gate")
	expect_rejected(w,"kai","resident_talk",first,"achao","achao: talk after the picnic but before the repair")
	w.state.dock_stage=0
	expect_rejected(w,"kai","resident_gift",first,"achao:fiber","achao: gift with dock_stage 0")
	expect(not pl(w,"kai").has("bonds"),"achao: pre-repair rejections write no bonds key")
	w.state.dock_stage=1
	# Wrong cell, wrong resident, wrong region, out of reach.
	expect_rejected(w,"kai","resident_talk",first+Vector2i.RIGHT,"achao","achao: talk aimed at the tile beside him")
	expect_rejected(w,"kai","resident_gift",first+Vector2i.RIGHT,"achao:fiber","achao: gift aimed at the tile beside him")
	expect_rejected(w,"kai","resident_talk",first+Vector2i.DOWN,"achao","achao: talk aimed at the tile below him")
	expect_rejected(w,"kai","resident_talk",first,"mianmian","achao: mianmian cannot be talked to at the dock")
	expect_rejected(w,"kai","resident_talk",first,"nuannuan","achao: nuannuan cannot be talked to at the dock")
	expect_rejected(w,"kai","resident_talk",cell_of(w,"aru"),"achao","achao: not reachable at Aru's cell")
	for region:String in ["lanyang",Bond.SPRING_REGION,"jinguashi","maokong"]:
		go(w,"kai",region,first)
		expect_rejected(w,"kai","resident_talk",first,"achao","achao: talk from %s"%region)
		expect_rejected(w,"kai","resident_gift",first,"achao:fiber","achao: gift from %s"%region)
	go(w,"kai","home",first)
	p=pl(w,"kai")
	p.y=float(first.y)+5.5
	expect_rejected(w,"kai","resident_talk",first,"achao","achao: talk from five tiles away")
	expect_rejected(w,"kai","resident_gift",first,"achao:fiber","achao: gift from five tiles away")
	expect(not pl(w,"kai").has("bonds"),"achao: no rejection created a bonds key")
	# Daily rules at his cell.
	stand(w,"kai",first)
	var today:=today_of(w)
	var before:Dictionary=pl(w,"kai").inventory.duplicate(true)
	var r:=act(w,"kai","resident_talk",first,"achao")
	expect(bool(r.ok) and msg(r).contains("阿潮") and msg(r).contains(title("achao",1)) and msg(r).contains(Bond.stage_up_text("achao",0,1)),"achao: first talk names him and announces the first event")
	expect(pl(w,"kai").bonds=={"achao":rec(1,today,-1)} and pl(w,"kai").inventory==before,"achao: first talk stores one point and moves no items")
	expect_rejected(w,"kai","resident_talk",first,"achao","achao: second talk the same day")
	for liked:String in ["salt_grilled_fish","trout_hotpot","fiber"]:
		expect(Bond.liked("achao",liked) and liked not in Bond.COMMON_GIFTS,"achao: %s is a liked, non-common gift"%liked)
	expect(Bond.liked("achao","grilled_fish") and "grilled_fish" in Bond.COMMON_GIFTS,"achao: grilled_fish is liked and also a common gift")
	r=act(w,"kai","resident_gift",first,"achao:fiber")
	var expected:Dictionary=before.duplicate(true)
	expected.fiber=1
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.fiber)) and not msg(r).contains(RAISE),"achao: fiber is a favourite, no stage-up")
	expect(pl(w,"kai").inventory==expected and pl(w,"kai").bonds=={"achao":rec(4,today,today)},"achao: favourite gift takes one item and adds three points")
	r=act(w,"kai","resident_gift",first,"achao:salt_grilled_fish")
	expected.salt_grilled_fish=0
	expect(bool(r.ok) and msg(r).contains("明天") and not msg(r).contains(RAISE),"achao: second gift the same day is accepted")
	expect(pl(w,"kai").inventory==expected and pl(w,"kai").bonds=={"achao":rec(4,today,today)},"achao: second gift the same day takes the item without points")
	expect_rejected(w,"kai","resident_gift",first,"achao:wood","achao: wood is not a gift")
	expect_rejected(w,"kai","resident_gift",first,"achao:feed","achao: mianmian's feed is not his gift")
	expect_rejected(w,"kai","resident_gift",first,"achao:salt_grilled_fish","achao: cannot gift fish he no longer holds")
	w.state.time=float(w.state.time)+DAY
	r=act(w,"kai","resident_gift",first,"achao:radish")
	expected.radish=1
	expect(bool(r.ok) and msg(r).contains("向你道謝") and pl(w,"kai").inventory==expected and pl(w,"kai").bonds=={"achao":rec(5,today,today+1)},"achao: next-day common gift adds one point")
	r=act(w,"kai","resident_talk",first,"achao")
	expect(bool(r.ok) and msg(r).contains(Bond.stage_up_text("achao",1,2)) and msg(r).contains(title("achao",2)) and pl(w,"kai").bonds=={"achao":rec(6,today+1,today+1)},"achao: next-day talk reaches the second stage")
	var e:=entry(w,"kai","achao")
	expect(int(e.points)==6 and int(e.stage)==2 and str(e.stage_name)=="熟悉" and int(e.next)==14 and e.talked_today==true and e.gifted_today==true,"achao: view after two days")
	for someone:String in Bond.RESIDENTS:
		if someone!="achao":expect(int(entry(w,"kai",someone).points)==0,"achao: %s untouched"%someone)
	# No story-derived points.
	p=pl(w,"kai")
	var stories:Dictionary=p.stories
	stories["achao"]=4
	expect(Bond.story_count(p,"achao")==0 and int(entry(w,"kai","achao").points)==6 and not Bond.STORY_FLAGS.has("achao"),"achao has no commission-derived points")
	stories.erase("achao")
	# Occupied cells: next free candidate, for server and client alike.
	var second:Vector2i=Bond.DOCK_CELLS[1]
	var third:Vector2i=Bond.DOCK_CELLS[2]
	var fourth:Vector2i=Bond.DOCK_CELLS[3]
	w.state.objects[w.key(first)]={"type":"wall","owner":"kai"}
	expect(cell_of(w,"achao")==second and region_of(w,"achao")=="home","A building on 49,30 moves him to 50,30")
	w.state.time=float(w.state.time)+DAY
	stand(w,"kai",first)
	expect_rejected(w,"kai","resident_talk",first,"achao","achao: talk at the old cell once he has moved")
	stand(w,"kai",second)
	r=act(w,"kai","resident_talk",second,"achao")
	expect(bool(r.ok) and int(pl(w,"kai").bonds.achao.points)==7,"achao: talk works at the second cell")
	w.state.crops[w.key(second)]={"type":"radish","owner":"kai"}
	expect(cell_of(w,"achao")==third,"A crop on 50,30 moves him to 49,31")
	w.state.forest[w.key(third)]={"mature":true}
	expect(cell_of(w,"achao")==fourth,"A tree on 49,31 moves him to 50,31")
	w.state.time=float(w.state.time)+DAY
	stand(w,"kai",third)
	expect_rejected(w,"kai","resident_talk",third,"achao","achao: talk at the forested third cell")
	stand(w,"kai",fourth)
	r=act(w,"kai","resident_talk",fourth,"achao")
	expect(bool(r.ok) and int(pl(w,"kai").bonds.achao.points)==8,"achao: talk works at the fourth cell")
	w.state.objects[w.key(fourth)]={"type":"wall","owner":"kai"}
	expect(cell_of(w,"achao")==first and Bond.dock_cell(w.state)==first,"With every candidate taken he stays on the first cell")
	expect(Bond.dock_cell({})==first and Bond.dock_cell({"objects":7})==first,"dock_cell tolerates missing or malformed layers")
	expect(Bond.dock_cell({"forest":{"49,30":{}},"crops":{"50,30":{}}})==third,"dock_cell checks forest and crops layers in candidate order")
	# Four stages over seven world days.
	local_progression("achao","fiber",{"dock_stage":1})

# 16. 暖暖 (nuannuan): fourth-batch local resident at the jiaoxi warm spring, no gate.
func test_spring_resident()->void:
	expect(Bond.SPRING_REGION=="jiaoxi" and Bond.SPRING_CELL==Vector2i(20,22),"nuannuan's spot is jiaoxi 20,22")
	expect(Bond.SPRING_REGION in World.REGIONS.ALL,"jiaoxi is a real region")
	var probe:=World.new()
	expect(region_of(probe,"nuannuan")=="jiaoxi" and cell_of(probe,"nuannuan")==Vector2i(20,22),"bond_place(nuannuan) is jiaoxi 20,22 on a fresh island")
	expect(Bond.present(probe.state,"nuannuan") and Bond.locked_reason(probe.state,"nuannuan")=="","nuannuan is present without picnic or dock repair")
	# Fixed cell: home-layer entries on "20,22" never move her.
	probe.state.objects["20,22"]={"type":"wall","owner":"x"}
	probe.state.crops["20,22"]={"type":"radish","owner":"x"}
	probe.state.forest["20,22"]={"mature":true}
	expect(region_of(probe,"nuannuan")=="jiaoxi" and cell_of(probe,"nuannuan")==Vector2i(20,22),"Home-layer entries on 20,22 do not move nuannuan")
	expect(Bond.liked("nuannuan","ginger") and "ginger" not in Bond.COMMON_GIFTS,"nuannuan fixture: ginger is a liked, non-common gift")
	expect(not Bond.giftable("nuannuan","crystal_sand") and "crystal_sand" not in Bond.COMMON_GIFTS,"nuannuan fixture: crystal_sand is not a gift for her")
	# Region (home, lanyang, jinguashi), wrong cell, reach, daily rules, two days.
	local_daily("nuannuan","ginger","crystal_sand","xinghe")
	# Also refused from the home dock area where achao stands.
	var w:=World.new()
	w.add_player("rin","凜")
	w.state.dock_stage=1
	go(w,"rin","home",Bond.SPRING_CELL)
	expect_rejected(w,"rin","resident_talk",Bond.SPRING_CELL,"nuannuan","nuannuan: talk at home 20,22")
	go(w,"rin","home",Bond.DOCK_CELLS[0])
	expect_rejected(w,"rin","resident_talk",Bond.DOCK_CELLS[0],"nuannuan","nuannuan: talk at achao's dock cell")
	go(w,"rin","jiaoxi",Bond.SPRING_CELL)
	expect_rejected(w,"rin","resident_talk",Bond.SPRING_CELL,"achao","nuannuan: achao cannot be talked to at the spring")
	var p:Dictionary=pl(w,"rin")
	var stories:Dictionary=p.stories
	stories["nuannuan"]=4
	expect(Bond.story_count(p,"nuannuan")==0 and int(entry(w,"rin","nuannuan").points)==0 and not Bond.STORY_FLAGS.has("nuannuan"),"nuannuan has no commission-derived points")
	local_progression("nuannuan","ginger")

# 17. achao + nuannuan: save/reload and two independent players.
func test_fourth_batch_save_and_players()->void:
	var path:=temp_path("batch4-world")
	_cleanup.append(path)
	var w:=World.new()
	w.save_path=path
	w.state.dock_stage=1  # PRESET: dock repaired
	w.add_player("lia","莉")
	var p:Dictionary=pl(w,"lia")
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	p.inventory.fiber=2
	p.inventory.ginger=2
	var dock:=cell_of(w,"achao")
	var spring:=cell_of(w,"nuannuan")
	var today:=today_of(w)
	go(w,"lia","home",dock)
	expect(bool(act(w,"lia","resident_talk",dock,"achao").ok) and bool(act(w,"lia","resident_gift",dock,"achao:fiber").ok),"Lia talks to and gifts achao")
	go(w,"lia",Bond.SPRING_REGION,spring)
	expect(bool(act(w,"lia","resident_talk",spring,"nuannuan").ok) and bool(act(w,"lia","resident_gift",spring,"nuannuan:ginger").ok),"Lia talks to and gifts nuannuan")
	var live:Variant=bonds_of(w,"lia")
	expect(same_bonds(live,{"achao":rec(4,today,today),"nuannuan":rec(4,today,today)}),"Live fourth-batch bonds before saving")
	p=pl(w,"lia")
	p.region="home"
	p.x=home_x
	p.y=home_y
	expect(w.save(),"World with achao and nuannuan bonds saves")
	var restored:=World.new()
	var loaded:bool=restored.load_world(path)
	expect(loaded,"World with achao and nuannuan bonds reloads")
	if not loaded:return
	expect(same_bonds(bonds_of(restored,"lia"),live),"achao and nuannuan bonds survive reload (int-tolerant)")
	var achao_loaded:Dictionary=pl(restored,"lia").bonds.achao
	var nuan_loaded:Dictionary=pl(restored,"lia").bonds.nuannuan
	expect(typeof(achao_loaded.points)==TYPE_INT and typeof(achao_loaded.talk_day)==TYPE_INT and typeof(nuan_loaded.points)==TYPE_INT and typeof(nuan_loaded.gift_day)==TYPE_INT,"Reloaded achao/nuannuan fields are ints")
	expect(int(restored.state.get("dock_stage",0))==1,"dock_stage survives reload")
	expect(view_of(restored,"lia")==view_of(w,"lia"),"Reloaded view matches the live view (achao, nuannuan)")
	go(restored,"lia","home",dock)
	expect_rejected(restored,"lia","resident_talk",dock,"achao","achao: repeat talk after reload the same day")
	var r:=act(restored,"lia","resident_talk",dock,"achao")
	expect(not bool(r.ok) and msg(r)=="今天已經和阿潮聊過了，明天再來坐坐。","achao after reload: refused as already talked, not as locked (%s)"%msg(r))
	go(restored,"lia",Bond.SPRING_REGION,spring)
	expect_rejected(restored,"lia","resident_talk",spring,"nuannuan","nuannuan: repeat talk after reload the same day")
	r=act(restored,"lia","resident_gift",spring,"nuannuan:ginger")
	expect(bool(r.ok) and int(pl(restored,"lia").inventory.ginger)==0 and same_bonds(bonds_of(restored,"lia"),live),"nuannuan: repeat gift after reload is taken without points")
	restored.state.time=float(restored.state.time)+DAY
	r=act(restored,"lia","resident_talk",spring,"nuannuan")
	expect(bool(r.ok),"nuannuan: next-day talk after reload counts")
	go(restored,"lia","home",dock)
	r=act(restored,"lia","resident_talk",dock,"achao")
	expect(bool(r.ok) and same_bonds(bonds_of(restored,"lia"),{"achao":rec(5,today+1,today),"nuannuan":rec(5,today+1,today)}),"achao: next-day talk after reload counts")
	# Two players.
	var v:=World.new()
	v.state.dock_stage=1  # PRESET: dock repaired
	v.add_player("ann","安")
	v.add_player("ben","班")
	var day:=today_of(v)
	go(v,"ann","home",dock)
	go(v,"ben","home",dock)
	var ann:Dictionary=pl(v,"ann")
	ann.inventory.fiber=1
	ann.inventory.ginger=1
	var ben_view:Dictionary=view_of(v,"ben")
	var ben_inv:Dictionary=pl(v,"ben").inventory.duplicate(true)
	expect(bool(act(v,"ann","resident_talk",dock,"achao").ok) and bool(act(v,"ann","resident_gift",dock,"achao:fiber").ok),"Ann talks to and gifts achao")
	expect(pl(v,"ann").bonds=={"achao":rec(4,day,day)},"Ann's achao record has four points")
	expect(view_of(v,"ben")==ben_view and not pl(v,"ben").has("bonds") and pl(v,"ben").inventory==ben_inv,"Ann's achao progress does not touch Ben")
	var ann_bonds:Variant=bonds_of(v,"ann")
	r=act(v,"ben","resident_talk",dock,"achao")
	expect(bool(r.ok) and msg(r).contains(title("achao",1)),"Ann's talk does not block Ben's first achao talk")
	expect(pl(v,"ben").bonds=={"achao":rec(1,day,-1)} and bonds_of(v,"ann")==ann_bonds,"Ben's achao talk only writes Ben's record")
	go(v,"ann",Bond.SPRING_REGION,spring)
	go(v,"ben",Bond.SPRING_REGION,spring)
	ben_view=view_of(v,"ben")
	ben_inv=pl(v,"ben").inventory.duplicate(true)
	expect(bool(act(v,"ann","resident_talk",spring,"nuannuan").ok) and bool(act(v,"ann","resident_gift",spring,"nuannuan:ginger").ok),"Ann talks to and gifts nuannuan")
	expect(view_of(v,"ben")==ben_view and pl(v,"ben").inventory==ben_inv,"Ann's nuannuan progress does not touch Ben")
	ann_bonds=bonds_of(v,"ann")
	r=act(v,"ben","resident_talk",spring,"nuannuan")
	expect(bool(r.ok) and msg(r).contains(title("nuannuan",1)),"Ann's talk does not block Ben's first nuannuan talk")
	expect(same_bonds(bonds_of(v,"ben"),{"achao":rec(1,day,-1),"nuannuan":rec(1,day,-1)}) and bonds_of(v,"ann")==ann_bonds,"Ben's records hold only his own talks")
	expect(int(entry(v,"ann","achao").points)==4 and int(entry(v,"ann","nuannuan").points)==4,"Ann keeps separate progress for achao and nuannuan")
	v.active_tokens.erase("ben")
	var ben_bonds:Variant=bonds_of(v,"ben")
	v.state.time=float(v.state.time)+DAY
	go(v,"ann","home",dock)
	expect(bool(act(v,"ann","resident_talk",dock,"achao").ok),"Ben being offline does not block Ann's achao talk")
	expect(bonds_of(v,"ben")==ben_bonds and int(entry(v,"ben","achao").points)==1,"Offline Ben's achao progress is unchanged")

# 18. Fifth batch: 洛洛 (luoluo, beside the shipping box) and 鈴婆婆 (lingpopo,
# beside the wind-chime tree). Both stand on home ground once the picnic is done.
const PLAZA:={
	"luoluo":{"name":"洛洛","liked":"roasted_sweet_potato","liked_common":"bread","foreign":"tea_leaf"},
	"lingpopo":{"name":"鈴婆婆","liked":"carrot_soup","liked_common":"salad","foreign":"feed"},
}

static func plaza_cells(resident:String)->Array:
	return Bond.POST_CELLS if resident=="luoluo" else Bond.BELL_CELLS

static func plaza_locked(resident:String)->String:
	return Bond.POST_LOCKED if resident=="luoluo" else Bond.BELL_LOCKED

static func plaza_cell_rule(resident:String,state:Dictionary)->Vector2i:
	return Bond.post_cell(state) if resident=="luoluo" else Bond.bell_cell(state)

static func chebyshev(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

## Every fixed home landmark a plaza resident must neither stand on nor touch
## (including diagonally): label -> cell.
static func home_landmarks()->Dictionary:
	var marks:Dictionary={}
	for npc:String in Village.NPCS:marks["npc "+npc]=Village.NPCS[npc].cell
	for npc:String in Village.FESTIVAL_SPOTS:marks["festival spot "+npc]=Village.FESTIVAL_SPOTS[npc]
	for cell:Vector2i in World.Festival.VISITORS:marks["festival visitor "+str(World.Festival.VISITORS[cell])]=cell
	for index in range(World.Festival.STOPS.size()):marks["festival stop %d"%index]=World.Festival.STOPS[index]
	marks["wind-chime tree"]=World.Festival.TREE_CELL
	marks["notice board"]=Vector2i(40,29)
	marks["seed shop"]=Vector2i(43,29)
	for index in range(World.SHIPPING.CANDIDATES.size()):marks["shipping candidate %d"%index]=World.SHIPPING.CANDIDATES[index]
	for index in range(World.COMMUNITY.CANDIDATES.size()):marks["community table candidate %d"%index]=World.COMMUNITY.CANDIDATES[index]
	for animal:String in World.LIVESTOCK.ANIMALS:
		marks["livestock "+animal]=World.LIVESTOCK.ANIMALS[animal].cell
		marks["livestock collector "+animal]=World.LIVESTOCK.collector_cell(animal)
	for index in range(Bond.RANCH_CELLS.size()):marks["ranch cell %d"%index]=Bond.RANCH_CELLS[index]
	for index in range(Bond.DOCK_CELLS.size()):marks["dock cell %d"%index]=Bond.DOCK_CELLS[index]
	var transit:Dictionary=World.TRANSIT.points(World.REGIONS.HOME)
	for point:String in transit:marks["transit "+point]=transit[point].cell
	marks["home exit"]=World.REGIONS.exit_cell(World.REGIONS.HOME)
	marks["home arrival"]=Vector2i(World.REGIONS.spawn(World.REGIONS.HOME))
	marks["player spawn"]=Vector2i(World.SPAWN)
	marks["chicken"]=Vector2i(45,34)
	marks["quarry"]=Vector2i(54,25)
	marks["copper"]=World.COPPER_CELL
	return marks

## Terrain and placement rules for every candidate cell, kept true by assertion.
func test_plaza_cells()->void:
	expect(Bond.POST_CELLS==[Vector2i(43,33),Vector2i(43,34),Vector2i(43,35),Vector2i(42,33)],"luoluo candidates are 43,33 43,34 43,35 42,33 in order")
	expect(Bond.BELL_CELLS==[Vector2i(41,26),Vector2i(42,26),Vector2i(41,25),Vector2i(43,26)],"lingpopo candidates are 41,26 42,26 41,25 43,26 in order")
	expect(World.base_resource(Vector2i(40,26))=="rock","40,26 is a fixed rock (why it is not a lingpopo candidate)")
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game plaza (bridge, picnic and the festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	var spawn_point:=Vector2(World.SPAWN)
	for resident:String in ["luoluo","lingpopo"]:
		var cells:Array=plaza_cells(resident)
		expect(cells.size()==4,"%s has four candidate cells"%resident)
		var anchor:Vector2i=World.SHIPPING.CELL if resident=="luoluo" else World.Festival.TREE_CELL
		var reach:float=3.0 if resident=="luoluo" else 4.0
		var first:Vector2i=cells[0]
		expect(Vector2(first-anchor).length()<=reach,"%s first cell %s is within %.0f tiles of %s"%[resident,str(first),reach,str(anchor)])
		for cell:Vector2i in cells:
			var tag:="%s cell %s"%[resident,str(cell)]
			expect(Vector2(cell-anchor).length()<=4.2,tag+" stays near its landmark")
			for w in [plain,busy]:
				expect(w.is_land(cell) and not w.water(cell),tag+": land, not water")
				expect(not w.blocked(cell),tag+": not blocked, a player can stand there")
				expect(w.resource(cell)=="",tag+": no resource on the cell")
				expect(not w.protected(cell),tag+": ordinary ground (not protected)")
			for spot:Vector2i in [cell,cell+Vector2i.DOWN]:
				var found:=World.base_resource(spot)
				expect(found!="tree" and found!="rock","%s: no fixed tree/rock at %s (cell or the cell below): '%s'"%[tag,str(spot),found])
			for mark:String in marks:
				var at:Vector2i=marks[mark]
				expect(chebyshev(cell,at)>=2,"%s is not on or touching %s %s"%[tag,mark,str(at)])
			var other:Array=plaza_cells("lingpopo" if resident=="luoluo" else "luoluo")
			for spot:Vector2i in other:
				expect(chebyshev(cell,spot)>=2,"%s keeps clear of the other plaza resident's cell %s"%[tag,str(spot)])
		# A player standing on the spawn point cannot reach the first three luoluo
		# cells or any lingpopo cell with the 3.2-tile interaction radius.
		for index in range(cells.size()):
			var cell:Vector2i=cells[index]
			if resident=="luoluo" and index==3:continue
			expect(spawn_point.distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2,"%s cell %s is outside interaction range of the spawn point"%[resident,str(cell)])
	# The bell candidates are not under the tree crown (the tree is two rows below the first one).
	for cell:Vector2i in Bond.BELL_CELLS:
		expect(cell.y<=World.Festival.TREE_CELL.y-2 or absi(cell.x-World.Festival.TREE_CELL.x)>=2,"lingpopo cell %s is not directly above the tree"%str(cell))

func test_plaza_resident(resident:String)->void:
	var setup:Dictionary=PLAZA[resident]
	var who:=str(setup.name)
	var liked:=str(setup.liked)
	var liked_common:=str(setup.liked_common)
	var foreign:=str(setup.foreign)
	var other:="lingpopo" if resident=="luoluo" else "luoluo"
	var cells:Array=plaza_cells(resident)
	var first:Vector2i=cells[0]
	var second:Vector2i=cells[1]
	var third:Vector2i=cells[2]
	var fourth:Vector2i=cells[3]
	var gate:=plaza_locked(resident)
	expect(Bond.name_of(resident)==who and resident in Bond.RESIDENTS and resident in Bond.WALK_UP,"%s is the walk-up resident %s"%[resident,who])
	expect(Bond.liked(resident,liked) and liked not in Bond.COMMON_GIFTS,"%s fixture: %s is a liked, non-common gift"%[resident,liked])
	expect(Bond.liked(resident,liked_common) and liked_common in Bond.COMMON_GIFTS,"%s fixture: %s is liked and also a common gift"%[resident,liked_common])
	expect(not Bond.giftable(resident,foreign) and foreign not in Bond.COMMON_GIFTS,"%s fixture: %s is not a gift for %s"%[resident,foreign,resident])
	for item in Bond.LIKES[resident]:
		expect(World.NAMES.has(item),"%s liked item %s exists in World.NAMES"%[resident,item])
	expect(Bond.STORY_FLAGS.has(resident)==false and not Village.QUESTS.has(resident),"%s has no commission-derived points"%resident)
	# Pure gate rules.
	expect(Bond.locked_reason({},resident)==gate and Bond.locked_reason({"picnic":false},resident)==gate,"%s: no picnic gives the locked message"%resident)
	expect(Bond.locked_reason({"dock_stage":2},resident)==gate,"%s: the dock repair does not bring %s"%[resident,resident])
	expect(Bond.locked_reason({"picnic":true},resident)=="" and Bond.present({"picnic":true},resident),"%s: the picnic makes %s present"%[resident,resident])
	expect(not Bond.present({"picnic":true},"achao") and Bond.present({"picnic":true},"mianmian"),"%s: the picnic gate opens mianmian too but not achao"%resident)
	# Before the picnic: refused with the exact message, nothing written.
	var w:=World.new()
	var token:="plaza-"+resident
	w.add_player(token,"郵")
	var p:Dictionary=pl(w,token)
	p.inventory[liked]=3
	p.inventory[liked_common]=2
	p.inventory.radish=2
	p.inventory.wood=4
	p.inventory[foreign]=1
	stand(w,token,first)
	expect(not bool(w.state.picnic),"%s: fresh world has no picnic yet"%resident)
	expect(region_of(w,resident)=="home" and cell_of(w,resident)==first,"%s: bond_place is home %s even before the picnic"%[resident,str(first)])
	var locked:=act(w,token,"resident_talk",first,resident)
	expect(not bool(locked.ok) and msg(locked)==gate,"%s: talk before the picnic is refused with '%s' (%s)"%[resident,gate,msg(locked)])
	locked=act(w,token,"resident_gift",first,"%s:%s"%[resident,liked])
	expect(not bool(locked.ok) and msg(locked)==gate,"%s: gift before the picnic is refused with the locked message"%resident)
	expect_rejected(w,token,"resident_talk",first,resident,"%s: talk before the picnic"%resident)
	expect_rejected(w,token,"resident_gift",first,"%s:%s"%[resident,liked],"%s: liked gift before the picnic"%resident)
	expect_rejected(w,token,"resident_gift",first,"%s:radish"%resident,"%s: common gift before the picnic"%resident)
	w.state.dock_stage=1
	locked=act(w,token,"resident_talk",first,resident)
	expect(not bool(locked.ok) and msg(locked)==gate,"%s: the dock repair does not open the picnic gate"%resident)
	expect(not pl(w,token).has("bonds"),"%s: pre-picnic rejections write no bonds key"%resident)
	w.state.picnic=true
	# Wrong cell, wrong resident, wrong region, out of reach.
	expect_rejected(w,token,"resident_talk",first+Vector2i.RIGHT,resident,"%s: talk aimed at the tile beside"%resident)
	expect_rejected(w,token,"resident_gift",first+Vector2i.RIGHT,"%s:%s"%[resident,liked],"%s: gift aimed at the tile beside"%resident)
	expect_rejected(w,token,"resident_talk",first+Vector2i.DOWN,resident,"%s: talk aimed at the tile below"%resident)
	expect_rejected(w,token,"resident_talk",first,"mianmian","%s: mianmian cannot be talked to here"%resident)
	expect_rejected(w,token,"resident_talk",first,other,"%s: %s cannot be talked to here"%[resident,other])
	expect_rejected(w,token,"resident_talk",first,"aru","%s: aru cannot be talked to here"%resident)
	var other_cell:Vector2i=cell_of(w,other)
	stand(w,token,other_cell)
	expect_rejected(w,token,"resident_talk",other_cell,resident,"%s: not reachable at %s's cell"%[resident,other])
	stand(w,token,cell_of(w,"aru"))
	expect_rejected(w,token,"resident_talk",cell_of(w,"aru"),resident,"%s: not reachable at Aru's cell"%resident)
	for region:String in ["lanyang",Bond.SPRING_REGION,"jinguashi","maokong"]:
		go(w,token,region,first)
		expect_rejected(w,token,"resident_talk",first,resident,"%s: talk from %s"%[resident,region])
		expect_rejected(w,token,"resident_gift",first,"%s:%s"%[resident,liked],"%s: gift from %s"%[resident,region])
	go(w,token,"home",first)
	p=pl(w,token)
	p.y=float(first.y)+5.5
	expect_rejected(w,token,"resident_talk",first,resident,"%s: talk from five tiles away"%resident)
	expect_rejected(w,token,"resident_gift",first,"%s:%s"%[resident,liked],"%s: gift from five tiles away"%resident)
	expect(not pl(w,token).has("bonds"),"%s: no rejection created a bonds key"%resident)
	# Daily rules at the first cell.
	stand(w,token,first)
	var today:=today_of(w)
	var before:Dictionary=pl(w,token).inventory.duplicate(true)
	var r:=act(w,token,"resident_talk",first,resident)
	expect(bool(r.ok) and msg(r).contains(who) and msg(r).contains(title(resident,1)) and msg(r).contains(Bond.stage_up_text(resident,0,1)),"%s: first talk names %s and announces the first event (%s)"%[resident,who,msg(r)])
	expect(pl(w,token).bonds=={resident:rec(1,today,-1)} and pl(w,token).inventory==before,"%s: first talk stores one point and moves no items"%resident)
	expect_rejected(w,token,"resident_talk",first,resident,"%s: second talk the same day"%resident)
	var refused:=act(w,token,"resident_talk",first,resident)
	expect(not bool(refused.ok) and msg(refused)=="今天已經和%s聊過了，明天再來坐坐。"%who,"%s: repeat talk is refused as already talked"%resident)
	r=act(w,token,"resident_gift",first,"%s:%s"%[resident,liked])
	var expected:Dictionary=before.duplicate(true)
	expected[liked]=2
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES[liked])) and not msg(r).contains(RAISE),"%s: %s is a favourite, no stage-up"%[resident,liked])
	expect(pl(w,token).inventory==expected and pl(w,token).bonds=={resident:rec(4,today,today)},"%s: favourite gift takes one item and adds three points"%resident)
	r=act(w,token,"resident_gift",first,"%s:%s"%[resident,liked_common])
	expected[liked_common]=1
	expect(bool(r.ok) and msg(r).contains("明天") and not msg(r).contains(RAISE),"%s: second gift the same day is accepted"%resident)
	expect(pl(w,token).inventory==expected and pl(w,token).bonds=={resident:rec(4,today,today)},"%s: second gift the same day takes the item without points"%resident)
	expect_rejected(w,token,"resident_gift",first,"%s:wood"%resident,"%s: wood is not a gift"%resident)
	expect_rejected(w,token,"resident_gift",first,"%s:%s"%[resident,foreign],"%s: %s is not a gift"%[resident,foreign])
	# Next day: a liked item that is also a common gift counts as liked (+3).
	w.state.time=float(w.state.time)+DAY
	r=act(w,token,"resident_gift",first,"%s:%s"%[resident,liked_common])
	expected[liked_common]=0
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(Bond.stage_up_text(resident,1,2)) and msg(r).contains(title(resident,2)),"%s: next-day %s is liked and reaches the second stage"%[resident,liked_common])
	expect(pl(w,token).inventory==expected and pl(w,token).bonds=={resident:rec(7,today,today+1)},"%s: liked common gift adds three points"%resident)
	r=act(w,token,"resident_talk",first,resident)
	expect(bool(r.ok) and not msg(r).contains(RAISE) and pl(w,token).bonds=={resident:rec(8,today+1,today+1)},"%s: next-day talk adds one point"%resident)
	var e:=entry(w,token,resident)
	expect(int(e.points)==8 and int(e.stage)==2 and str(e.stage_name)=="熟悉" and int(e.next)==14 and e.talked_today==true and e.gifted_today==true,"%s: view after two days"%resident)
	# Third day: a plain common gift adds one point.
	w.state.time=float(w.state.time)+DAY
	r=act(w,token,"resident_gift",first,"%s:radish"%resident)
	expected.radish=1
	expect(bool(r.ok) and msg(r).contains("向你道謝") and pl(w,token).inventory==expected and pl(w,token).bonds=={resident:rec(9,today+1,today+2)},"%s: common gift adds one point"%resident)
	for someone:String in Bond.RESIDENTS:
		if someone!=resident:expect(int(entry(w,token,someone).points)==0,"%s: %s untouched"%[resident,someone])
	# Occupied cells: next free candidate, for server and client alike.
	w.state.objects[w.key(first)]={"type":"wall","owner":token}
	expect(cell_of(w,resident)==second and region_of(w,resident)=="home","%s: a building on %s moves the resident to %s"%[resident,str(first),str(second)])
	w.state.time=float(w.state.time)+DAY
	stand(w,token,first)
	expect_rejected(w,token,"resident_talk",first,resident,"%s: talk at the old cell once moved"%resident)
	stand(w,token,second)
	r=act(w,token,"resident_talk",second,resident)
	expect(bool(r.ok) and int(pl(w,token).bonds[resident].points)==10,"%s: talk works at the second cell"%resident)
	w.state.crops[w.key(second)]={"type":"radish","owner":token}
	expect(cell_of(w,resident)==third,"%s: a crop on %s moves the resident to %s"%[resident,str(second),str(third)])
	w.state.forest[w.key(third)]={"mature":true}
	expect(cell_of(w,resident)==fourth,"%s: a tree on %s moves the resident to %s"%[resident,str(third),str(fourth)])
	w.state.time=float(w.state.time)+DAY
	stand(w,token,third)
	expect_rejected(w,token,"resident_talk",third,resident,"%s: talk at the forested third cell"%resident)
	stand(w,token,fourth)
	r=act(w,token,"resident_talk",fourth,resident)
	expect(bool(r.ok) and int(pl(w,token).bonds[resident].points)==11,"%s: talk works at the fourth cell"%resident)
	w.state.objects[w.key(fourth)]={"type":"wall","owner":token}
	expect(cell_of(w,resident)==first and plaza_cell_rule(resident,w.state)==first,"%s: with every candidate taken the resident stays on the first cell"%resident)
	w.state.time=float(w.state.time)+DAY
	stand(w,token,first)
	r=act(w,token,"resident_talk",first,resident)
	expect(bool(r.ok) and int(pl(w,token).bonds[resident].points)==12,"%s: talk still works on the walled first cell when all are taken"%resident)
	expect(plaza_cell_rule(resident,{})==first and plaza_cell_rule(resident,{"objects":7})==first,"%s: cell rule tolerates missing or malformed layers"%resident)
	var layered:Dictionary={"forest":{w.key(first):{}},"crops":{w.key(second):{}}}
	expect(plaza_cell_rule(resident,layered)==third,"%s: cell rule checks forest and crops layers in candidate order"%resident)
	# The other plaza resident does not move when this one's cells are taken.
	expect(cell_of(w,other)==plaza_cells(other)[0],"%s: walls on %s's cells leave %s on the first cell"%[resident,resident,other])
	# Four stages over seven world days.
	local_progression(resident,liked,{"picnic":true})

# 19. luoluo + lingpopo: save/reload and two independent players.
func test_fifth_batch_save_and_players()->void:
	var path:=temp_path("batch5-world")
	_cleanup.append(path)
	var w:=World.new()
	w.save_path=path
	w.state.picnic=true  # PRESET: picnic done
	w.add_player("lia","莉")
	var p:Dictionary=pl(w,"lia")
	p.inventory.roasted_sweet_potato=2
	p.inventory.carrot_soup=2
	var post:=cell_of(w,"luoluo")
	var bell:=cell_of(w,"lingpopo")
	var today:=today_of(w)
	stand(w,"lia",post)
	expect(bool(act(w,"lia","resident_talk",post,"luoluo").ok) and bool(act(w,"lia","resident_gift",post,"luoluo:roasted_sweet_potato").ok),"Lia talks to and gifts luoluo")
	stand(w,"lia",bell)
	expect(bool(act(w,"lia","resident_talk",bell,"lingpopo").ok) and bool(act(w,"lia","resident_gift",bell,"lingpopo:carrot_soup").ok),"Lia talks to and gifts lingpopo")
	var live:Variant=bonds_of(w,"lia")
	expect(same_bonds(live,{"luoluo":rec(4,today,today),"lingpopo":rec(4,today,today)}),"Live fifth-batch bonds before saving")
	expect(w.save(),"World with luoluo and lingpopo bonds saves")
	var restored:=World.new()
	var loaded:bool=restored.load_world(path)
	expect(loaded,"World with luoluo and lingpopo bonds reloads")
	if not loaded:return
	expect(same_bonds(bonds_of(restored,"lia"),live),"luoluo and lingpopo bonds survive reload (int-tolerant)")
	var luo_loaded:Dictionary=pl(restored,"lia").bonds.luoluo
	var ling_loaded:Dictionary=pl(restored,"lia").bonds.lingpopo
	expect(typeof(luo_loaded.points)==TYPE_INT and typeof(luo_loaded.talk_day)==TYPE_INT and typeof(ling_loaded.points)==TYPE_INT and typeof(ling_loaded.gift_day)==TYPE_INT,"Reloaded luoluo/lingpopo fields are ints")
	expect(bool(restored.state.get("picnic",false)),"picnic survives reload")
	expect(cell_of(restored,"luoluo")==post and cell_of(restored,"lingpopo")==bell,"Reloaded world places luoluo and lingpopo on the same cells")
	expect(view_of(restored,"lia")==view_of(w,"lia"),"Reloaded view matches the live view (luoluo, lingpopo)")
	stand(restored,"lia",post)
	expect_rejected(restored,"lia","resident_talk",post,"luoluo","luoluo: repeat talk after reload the same day")
	var r:=act(restored,"lia","resident_talk",post,"luoluo")
	expect(not bool(r.ok) and msg(r)=="今天已經和洛洛聊過了，明天再來坐坐。","luoluo after reload: refused as already talked, not as locked (%s)"%msg(r))
	stand(restored,"lia",bell)
	expect_rejected(restored,"lia","resident_talk",bell,"lingpopo","lingpopo: repeat talk after reload the same day")
	r=act(restored,"lia","resident_gift",bell,"lingpopo:carrot_soup")
	expect(bool(r.ok) and int(pl(restored,"lia").inventory.carrot_soup)==0 and same_bonds(bonds_of(restored,"lia"),live),"lingpopo: repeat gift after reload is taken without points")
	restored.state.time=float(restored.state.time)+DAY
	r=act(restored,"lia","resident_talk",bell,"lingpopo")
	expect(bool(r.ok),"lingpopo: next-day talk after reload counts")
	stand(restored,"lia",post)
	r=act(restored,"lia","resident_talk",post,"luoluo")
	expect(bool(r.ok) and same_bonds(bonds_of(restored,"lia"),{"luoluo":rec(5,today+1,today),"lingpopo":rec(5,today+1,today)}),"luoluo: next-day talk after reload counts")
	# A pre-picnic save with a stored luoluo record still loads; the record stays and
	# the gate keeps him away until the picnic.
	var base:Dictionary=w.state.duplicate(true)
	base.picnic=false
	var fixture:=temp_path("batch5-fixture")
	_cleanup.append(fixture)
	expect(write_fixture(fixture,base),"Write pre-picnic fixture with fifth-batch bonds")
	var early:=World.new()
	expect(early.load_world(fixture) and same_bonds(bonds_of(early,"lia"),live),"Pre-picnic save with luoluo/lingpopo records loads")
	stand(early,"lia",post)
	r=act(early,"lia","resident_talk",post,"luoluo")
	expect(not bool(r.ok) and msg(r)==Bond.POST_LOCKED,"Pre-picnic reload: luoluo is locked again")
	# Two players.
	var v:=World.new()
	v.state.picnic=true  # PRESET: picnic done
	v.add_player("ann","安")
	v.add_player("ben","班")
	var day:=today_of(v)
	stand(v,"ann",post)
	stand(v,"ben",post)
	var ann:Dictionary=pl(v,"ann")
	ann.inventory.bread=1
	ann.inventory.soup=1
	var ben_view:Dictionary=view_of(v,"ben")
	var ben_inv:Dictionary=pl(v,"ben").inventory.duplicate(true)
	expect(bool(act(v,"ann","resident_talk",post,"luoluo").ok) and bool(act(v,"ann","resident_gift",post,"luoluo:bread").ok),"Ann talks to and gifts luoluo")
	expect(pl(v,"ann").bonds=={"luoluo":rec(4,day,day)},"Ann's luoluo record has four points")
	expect(view_of(v,"ben")==ben_view and not pl(v,"ben").has("bonds") and pl(v,"ben").inventory==ben_inv,"Ann's luoluo progress does not touch Ben")
	var ann_bonds:Variant=bonds_of(v,"ann")
	r=act(v,"ben","resident_talk",post,"luoluo")
	expect(bool(r.ok) and msg(r).contains(title("luoluo",1)),"Ann's talk does not block Ben's first luoluo talk")
	expect(pl(v,"ben").bonds=={"luoluo":rec(1,day,-1)} and bonds_of(v,"ann")==ann_bonds,"Ben's luoluo talk only writes Ben's record")
	stand(v,"ann",bell)
	stand(v,"ben",bell)
	ben_view=view_of(v,"ben")
	ben_inv=pl(v,"ben").inventory.duplicate(true)
	expect(bool(act(v,"ann","resident_talk",bell,"lingpopo").ok) and bool(act(v,"ann","resident_gift",bell,"lingpopo:soup").ok),"Ann talks to and gifts lingpopo")
	expect(view_of(v,"ben")==ben_view and pl(v,"ben").inventory==ben_inv,"Ann's lingpopo progress does not touch Ben")
	ann_bonds=bonds_of(v,"ann")
	r=act(v,"ben","resident_talk",bell,"lingpopo")
	expect(bool(r.ok) and msg(r).contains(title("lingpopo",1)),"Ann's talk does not block Ben's first lingpopo talk")
	expect(same_bonds(bonds_of(v,"ben"),{"luoluo":rec(1,day,-1),"lingpopo":rec(1,day,-1)}) and bonds_of(v,"ann")==ann_bonds,"Ben's records hold only his own talks")
	expect(int(entry(v,"ann","luoluo").points)==4 and int(entry(v,"ann","lingpopo").points)==4,"Ann keeps separate progress for luoluo and lingpopo")
	v.active_tokens.erase("ben")
	var ben_bonds:Variant=bonds_of(v,"ben")
	v.state.time=float(v.state.time)+DAY
	stand(v,"ann",post)
	expect(bool(act(v,"ann","resident_talk",post,"luoluo").ok),"Ben being offline does not block Ann's luoluo talk")
	expect(bonds_of(v,"ben")==ben_bonds and int(entry(v,"ben","luoluo").points)==1,"Offline Ben's luoluo progress is unchanged")

# 20. 點點 (diandian): sixth-batch local resident on the west bank of the
# star_garden reflection pool, fixed cell, no gate (like 暖暖 in jiaoxi).
func test_garden_resident()->void:
	var cell:=Bond.GARDEN_CELL
	expect(Bond.GARDEN_REGION=="star_garden" and cell==Vector2i(20,21),"diandian's spot is star_garden 20,21")
	expect(Bond.GARDEN_REGION==StarGarden.REGION and Bond.GARDEN_REGION in World.REGIONS.ALL,"star_garden is a real region")
	expect(Bond.GARDEN_REGION in World.REGIONS.ANGLING_RESERVES,"star_garden is an angling reserve (bond actions must bypass the build refusal)")
	# Terrain: walkable land, off the pool, off the path rows, clear of the trail head.
	var trail:Vector2i=World.TRANSIT.STATIONS[StarGarden.REGION].cell
	expect(trail==Vector2i(13,25),"star_garden trail head is 13,25")
	for spot:Vector2i in [cell,cell+Vector2i.DOWN]:
		var tag:="diandian %s %s"%["cell" if spot==cell else "stand cell below",str(spot)]
		expect(StarGarden.LAND.has_point(spot),tag+" is inside StarGarden.LAND")
		expect(not StarGarden.POOL.has_point(spot),tag+" is outside the reflection POOL")
		expect(spot.y not in [25,26],tag+" is not on path rows 25/26")
		expect(World.REGIONS.land(spot,StarGarden.REGION),tag+" is walkable star_garden land per Regions.land")
	expect(chebyshev(cell,trail)>=2,"diandian's cell %s neither is nor touches the trail cell %s"%[str(cell),str(trail)])
	expect(Vector2(cell-trail).length()>3.2,"Standing on the trail head does not put diandian within interaction reach")
	expect(cell.x<StarGarden.POOL.position.x and cell.y>=StarGarden.POOL.position.y and cell.y<StarGarden.POOL.end.y,"diandian stands west of the pool, level with it (west bank)")
	# Events.
	var titles:Array=[]
	for event:Dictionary in Bond.EVENTS.diandian:titles.append(str(event.title))
	expect(titles==["帽沿底下的顏色","沒畫好的手","畫面外的位置","把空白留給下一位"],"diandian's four event titles in order (%s)"%str(titles))
	expect(Bond.TALK_LINES.diandian.size()==3,"diandian has three talk lines")
	expect(Bond.LIKES.diandian==["bluebell","orange_blossom","chime_herb","star_mushroom"],"diandian likes bluebell, orange_blossom, chime_herb, star_mushroom")
	for item:String in ["bluebell","orange_blossom","chime_herb"]:
		expect(Bond.liked("diandian",item) and item in Bond.COMMON_GIFTS,"diandian: %s is liked and also a common gift"%item)
	expect(Bond.liked("diandian","star_mushroom") and "star_mushroom" not in Bond.COMMON_GIFTS,"diandian fixture: star_mushroom is a liked, non-common gift")
	expect(not Bond.giftable("diandian","crystal_sand") and "crystal_sand" not in Bond.COMMON_GIFTS,"diandian fixture: crystal_sand is not a gift for her")
	expect(not Bond.liked("diandian","radish") and Bond.giftable("diandian","radish"),"diandian fixture: radish is a plain common gift")
	# No gate, fixed cell.
	var probe:=World.new()
	expect(region_of(probe,"diandian")=="star_garden" and cell_of(probe,"diandian")==cell,"bond_place(diandian) is star_garden 20,21 on a fresh island")
	expect(Bond.present(probe.state,"diandian") and Bond.locked_reason(probe.state,"diandian")=="","diandian is present without picnic, dock repair or any route")
	expect(Bond.present({},"diandian") and Bond.present({"picnic":false,"dock_stage":0},"diandian"),"diandian's presence needs no state at all")
	probe.state.objects["20,21"]={"type":"wall","owner":"x"}
	probe.state.crops["20,21"]={"type":"radish","owner":"x"}
	probe.state.forest["20,21"]={"mature":true}
	expect(region_of(probe,"diandian")=="star_garden" and cell_of(probe,"diandian")==cell,"Home-layer entries on 20,21 do not move diandian")
	# Region (home, jiaoxi, jinguashi), wrong cell, reach, daily rules, two days.
	local_daily("diandian","star_mushroom","crystal_sand","nuannuan")
	# Extra refusals and the reserve rule.
	var w:=World.new()
	w.add_player("dot","點")
	w.state.dock_stage=1
	w.state.picnic=true
	var p:Dictionary=pl(w,"dot")
	p.inventory.bluebell=2
	p.inventory.radish=2
	p.inventory.star_mushroom=1
	for region:String in ["home",Bond.SPRING_REGION,"lanyang","maokong",World.REGIONS.Bamboo.REGION,"tianwei"]:
		go(w,"dot",region,cell)
		expect_rejected(w,"dot","resident_talk",cell,"diandian","diandian: talk from %s at 20,21"%region)
		expect_rejected(w,"dot","resident_gift",cell,"diandian:bluebell","diandian: gift from %s at 20,21"%region)
	go(w,"dot",Bond.SPRING_REGION,Bond.SPRING_CELL)
	expect_rejected(w,"dot","resident_talk",Bond.SPRING_CELL,"diandian","diandian: talk at nuannuan's jiaoxi cell")
	go(w,"dot","star_garden",Bond.SPRING_CELL)
	expect_rejected(w,"dot","resident_talk",Bond.SPRING_CELL,"diandian","diandian: talk at star_garden 20,22 (the tile below her)")
	go(w,"dot","star_garden",cell)
	expect_rejected(w,"dot","resident_talk",cell,"nuannuan","diandian: nuannuan cannot be talked to at the garden")
	expect_rejected(w,"dot","resident_talk",cell,"achao","diandian: achao cannot be talked to at the garden")
	expect_rejected(w,"dot","resident_talk",cell+Vector2i.LEFT,"diandian","diandian: talk aimed at the tile west of her")
	expect_rejected(w,"dot","resident_talk",cell+Vector2i.UP,"diandian","diandian: talk aimed at the tile above her")
	expect_rejected(w,"dot","hoe",cell+Vector2i.LEFT,"","diandian: hoeing beside her is still refused in the reserve")
	stand(w,"dot",trail)
	expect_rejected(w,"dot","resident_talk",cell,"diandian","diandian: talk from the trail head is out of reach")
	expect(not pl(w,"dot").has("bonds"),"diandian: no rejection created a bonds key")
	# Liked flower that is also a common gift counts as liked (+3); plain common +1.
	go(w,"dot","star_garden",cell)
	var today:=today_of(w)
	var r:=act(w,"dot","resident_gift",cell,"diandian:bluebell")
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.bluebell)) and msg(r).contains(Bond.stage_up_text("diandian",0,1)) and msg(r).contains("帽沿底下的顏色"),"diandian: bluebell is a favourite and reaches 帽沿底下的顏色 (%s)"%msg(r))
	expect(pl(w,"dot").bonds=={"diandian":rec(3,-1,today)} and int(pl(w,"dot").inventory.bluebell)==1,"diandian: bluebell takes one flower and adds three points")
	w.state.time=float(w.state.time)+DAY
	r=act(w,"dot","resident_gift",cell,"diandian:radish")
	expect(bool(r.ok) and msg(r).contains("向你道謝") and not msg(r).contains("很喜歡") and not msg(r).contains(RAISE),"diandian: radish is a plain common gift (%s)"%msg(r))
	expect(pl(w,"dot").bonds=={"diandian":rec(4,-1,today+1)} and int(pl(w,"dot").inventory.radish)==1,"diandian: common gift takes one radish and adds one point")
	w.state.time=float(w.state.time)+DAY
	r=act(w,"dot","resident_gift",cell,"diandian:star_mushroom")
	expect(bool(r.ok) and msg(r).contains("很喜歡") and msg(r).contains(str(World.NAMES.star_mushroom)),"diandian: star_mushroom is a favourite")
	expect(pl(w,"dot").bonds=={"diandian":rec(7,-1,today+2)} and int(pl(w,"dot").inventory.get("star_mushroom",0))==0,"diandian: star_mushroom adds three points")
	expect(msg(r).contains(Bond.stage_up_text("diandian",1,2)) and msg(r).contains("沒畫好的手"),"diandian: crossing six points announces 沒畫好的手")
	for someone:String in Bond.RESIDENTS:
		if someone!="diandian":expect(int(entry(w,"dot",someone).points)==0,"diandian: %s untouched"%someone)
	# No story-derived points.
	p=pl(w,"dot")
	var stories:Dictionary=p.stories
	stories["diandian"]=4
	expect(Bond.story_count(p,"diandian")==0 and int(entry(w,"dot","diandian").points)==7 and not Bond.STORY_FLAGS.has("diandian") and not Village.QUESTS.has("diandian"),"diandian has no commission-derived points")
	stories.erase("diandian")
	# Four stages over seven world days, each stage-up naming its event title.
	local_progression("diandian","star_mushroom")
	local_progression("diandian","bluebell")

# 21. diandian: save/reload, tampering and two independent players.
func test_sixth_batch_save_and_players()->void:
	var path:=temp_path("batch6-world")
	var fixture:=temp_path("batch6-fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=World.new()
	w.save_path=path
	w.add_player("lia","莉")
	var p:Dictionary=pl(w,"lia")
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	p.inventory.star_mushroom=2
	var garden:=cell_of(w,"diandian")
	var today:=today_of(w)
	go(w,"lia","star_garden",garden)
	expect(bool(act(w,"lia","resident_talk",garden,"diandian").ok) and bool(act(w,"lia","resident_gift",garden,"diandian:star_mushroom").ok),"Lia talks to and gifts diandian")
	var live:Variant=bonds_of(w,"lia")
	expect(same_bonds(live,{"diandian":rec(4,today,today)}),"Live diandian bond before saving")
	# Save from home so the reload does not depend on regional standing spots.
	p=pl(w,"lia")
	p.region="home"
	p.x=home_x
	p.y=home_y
	expect(w.save(),"World with a diandian bond saves")
	var restored:=World.new()
	var loaded:bool=restored.load_world(path)
	expect(loaded,"World with a diandian bond reloads")
	if not loaded:return
	expect(same_bonds(bonds_of(restored,"lia"),live),"diandian bond survives reload (int-tolerant)")
	var dian_loaded:Dictionary=pl(restored,"lia").bonds.diandian
	expect(typeof(dian_loaded.points)==TYPE_INT and typeof(dian_loaded.talk_day)==TYPE_INT and typeof(dian_loaded.gift_day)==TYPE_INT,"Reloaded diandian fields are ints")
	expect(view_of(restored,"lia")==view_of(w,"lia"),"Reloaded view matches the live view (diandian)")
	expect(region_of(restored,"diandian")=="star_garden" and cell_of(restored,"diandian")==garden,"Reloaded world places diandian on the same cell")
	go(restored,"lia","star_garden",garden)
	expect_rejected(restored,"lia","resident_talk",garden,"diandian","diandian: repeat talk after reload the same day")
	var r:=act(restored,"lia","resident_talk",garden,"diandian")
	expect(not bool(r.ok) and msg(r)=="今天已經和點點聊過了，明天再來坐坐。","diandian after reload: refused as already talked (%s)"%msg(r))
	r=act(restored,"lia","resident_gift",garden,"diandian:star_mushroom")
	expect(bool(r.ok) and int(pl(restored,"lia").inventory.get("star_mushroom",0))==0 and same_bonds(bonds_of(restored,"lia"),live),"diandian: repeat gift after reload is taken without points")
	restored.state.time=float(restored.state.time)+DAY
	r=act(restored,"lia","resident_talk",garden,"diandian")
	expect(bool(r.ok) and same_bonds(bonds_of(restored,"lia"),{"diandian":rec(5,today+1,today)}),"diandian: next-day talk after reload counts")
	# Schema tampering on a diandian record.
	var base:Dictionary=w.state.duplicate(true)
	expect(write_fixture(fixture,base),"Write diandian control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same_bonds(bonds_of(control,"lia"),live),"Control: the unmodified diandian fixture loads")
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var tampers:Array=[
		["diandian points 25",{"diandian":rec(25,today,today)}],
		["diandian negative points",{"diandian":rec(-1,today,today)}],
		["diandian talk_day in the future",{"diandian":rec(4,today+1,today)}],
		["diandian gift_day in the future",{"diandian":rec(4,today,today+1)}],
		["diandian extra field",{"diandian":{"points":4,"talk_day":today,"gift_day":today,"palette":1}}],
		["diandian missing field",{"diandian":{"points":4,"talk_day":today}}],
		["diandian all-default record",{"diandian":rec(0,-1,-1)}],
		["misspelled dianDian key",{"dianDian":rec(4,today,today)}],
	]
	for tamper:Array in tampers:
		var bad:Dictionary=base.duplicate(true)
		var bad_lia:Dictionary=bad.players.lia
		bad_lia.bonds=tamper[1]
		expect(write_fixture(fixture,bad),"Write diandian tampered fixture: "+str(tamper[0]))
		expect(not probe.load_world(fixture),"Schema rejects "+str(tamper[0]))
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+str(tamper[0]))
	# Two players.
	var v:=World.new()
	v.add_player("ann","安")
	v.add_player("ben","班")
	var day:=today_of(v)
	go(v,"ann","star_garden",garden)
	go(v,"ben","star_garden",garden)
	var ann:Dictionary=pl(v,"ann")
	ann.inventory.bluebell=1
	var ben_view:Dictionary=view_of(v,"ben")
	var ben_inv:Dictionary=pl(v,"ben").inventory.duplicate(true)
	expect(bool(act(v,"ann","resident_talk",garden,"diandian").ok) and bool(act(v,"ann","resident_gift",garden,"diandian:bluebell").ok),"Ann talks to and gifts diandian a bluebell")
	expect(pl(v,"ann").bonds=={"diandian":rec(4,day,day)},"Ann's diandian record has four points")
	expect(view_of(v,"ben")==ben_view and not pl(v,"ben").has("bonds") and pl(v,"ben").inventory==ben_inv,"Ann's diandian progress does not touch Ben")
	var ann_bonds:Variant=bonds_of(v,"ann")
	r=act(v,"ben","resident_talk",garden,"diandian")
	expect(bool(r.ok) and msg(r).contains(title("diandian",1)) and msg(r).contains("點點"),"Ann's talk does not block Ben's first diandian talk")
	expect(pl(v,"ben").bonds=={"diandian":rec(1,day,-1)} and bonds_of(v,"ann")==ann_bonds,"Ben's diandian talk only writes Ben's record")
	expect(int(entry(v,"ann","diandian").points)==4 and int(entry(v,"ben","diandian").points)==1,"Ann and Ben keep separate diandian progress")
	v.active_tokens.erase("ben")
	var ben_bonds:Variant=bonds_of(v,"ben")
	v.state.time=float(v.state.time)+DAY
	expect(bool(act(v,"ann","resident_talk",garden,"diandian").ok),"Ben being offline does not block Ann's diandian talk")
	expect(bonds_of(v,"ben")==ben_bonds and int(entry(v,"ben","diandian").points)==1,"Offline Ben's diandian progress is unchanged")

# Session privacy: public_state strips bonds, the snapshot carries only the
# recipient's own view.
func test_session_privacy()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var w=session.world
	w.add_player(PRIVATE_A,"甲")
	w.add_player(PRIVATE_B,"乙")
	var aru:=cell_of(w,"aru")
	stand(w,PRIVATE_A,aru)
	stand(w,PRIVATE_B,aru)
	expect(bool(act(w,PRIVATE_A,"resident_talk",aru,"aru").ok),"Session world: alpha talks to Aru")
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var players:Dictionary=public.get("players",{})
		var clean:bool=true
		for id in players:
			var person:Dictionary=players[id]
			if person.has("bonds"):clean=false
		expect(clean,"public_state(%s) has no player bonds"%region)
		expect(not JSON.stringify(public).contains("talk_day"),"public_state(%s) carries no bond records"%region)
	expect(pl(w,PRIVATE_A).has("bonds"),"Publishing does not strip the live record")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("resident_bonds"),"Recipient snapshot has resident_bonds")
	var own:Dictionary=snap.get("resident_bonds",{})
	expect(own==Bond.view(pl(w,PRIVATE_A),float(w.state.time)),"resident_bonds equals the recipient's own view")
	expect(own!=Bond.view(pl(w,PRIVATE_B),float(w.state.time)),"resident_bonds is not the other player's view")
	var own_keys:Array=own.keys()
	own_keys.sort()
	expect(own_keys==TWELVE,"resident_bonds lists all twelve residents")
	expect(own.has("diandian") and int(own.diandian.get("points",-1))==0 and int(own.diandian.get("stage",-1))==0,"resident_bonds shows diandian fresh at 0")
	var own_aru:Dictionary=own.get("aru",{})
	expect(int(own_aru.get("points",-1))==1 and own_aru.get("talked_today")==true,"Own snapshot shows the recipient's talk")
	var snap_players:Dictionary=snap.get("players",{})
	expect(not JSON.stringify(snap_players).contains("talk_day"),"Snapshot players carry no bond records")
	session.world=null
	session.queue_free()
	await process_frame
