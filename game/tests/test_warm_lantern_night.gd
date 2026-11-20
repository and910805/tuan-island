extends SceneTree
## Regression suite for res://scripts/warm_lantern_night.gd (冬季暖燈夜): picnic / home /
## 3.2 distance gates, winter boundary, ongoing rounds crossing seasons, permanent replays,
## three stations with fixed wishes, strict payloads, stale / duplicate refusal, finishing,
## atomic refusals, no economy side effects, public view privacy, 8-player cap, solo play,
## and strict save validation.
const Night=preload("res://scripts/warm_lantern_night.gd")
const DAY:=1440.0
const WINTER_FIRST:=42.0*DAY
const WINTER:=WINTER_FIRST+10.0
const WINTER_LAST:=56.0*DAY-0.01
const NEXT_SPRING:=56.0*DAY
const SPRING:=100.0
const AUTUMN_LAST:=42.0*DAY-0.01
const GROVE:=Vector2i(34,27)
const LANE:=Vector2i(44,35)
const HARBOR:=Vector2i(49,32)
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("WARM_LANTERN_NIGHT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func person()->Dictionary:
	return {"x":40.5,"y":29.5,"coins":120,"name":"島民","bag":["seed"],
		"inventory":{"radish":2,"turnip":4,"trout_hotpot":2}}

static func world(time:float=WINTER,picnic:bool=true)->Dictionary:
	return {"picnic":picnic,"time":time,"community":{"table":"39,30"},
		"board":{"note":1},"crops":{"1,1":{"kind":"turnip"}},
		"players":{"a":person(),"b":person(),"c":person()}}

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

func start(state:Dictionary,token:String="a")->Dictionary:
	stand(state,token,Night.BOARD)
	return Night.apply(state,token,Night.BOARD,"start",true)

func at_board(state:Dictionary,token:String,extra:String)->Dictionary:
	stand(state,token,Night.BOARD)
	return Night.apply(state,token,Night.BOARD,extra,true)

func light(state:Dictionary,token:String,station:String,wish:String,round_id:int=-1)->Dictionary:
	var cell:Vector2i=Night.STATIONS[station].cell
	var r:=round_id if round_id>=0 else int(state.get("warm_lantern_night",{}).get("round",1))
	stand(state,token,cell)
	return Night.apply(state,token,cell,"light:%d:%s:%s"%[r,station,wish],true)

func light_all(state:Dictionary,token:String)->void:
	expect(light(state,token,"grove","home").ok==true,"light grove")
	expect(light(state,token,"lane","harvest").ok==true,"light lane")
	expect(light(state,token,"harbor","friends").ok==true,"light harbor")

func restore(state:Dictionary,before:Dictionary,tokens:Array=["a","b","c"])->void:
	for t in tokens:
		if before.players.has(t) and state.players.has(t):
			state.players[t].x=before.players[t].x
			state.players[t].y=before.players[t].y

func _initialize()->void:
	contract()
	gates()
	season()
	flow()
	stations_and_wishes()
	strict_payloads()
	stale_and_duplicate()
	finish_rules()
	cap_and_solo()
	atomic_refusals()
	crossing_and_replay()
	public_and_view()
	validation()
	economy_untouched()
	finish()

func contract()->void:
	expect(Night.ACTION=="warm_lantern_night" and Night.KEY=="warm_lantern_night" and Night.VIEW_KEY=="own_warm_lantern_night","names")
	expect(Night.BOARD==Vector2i(40,29),"board")
	expect(Night.STATIONS.keys()==["grove","lane","harbor"],"station order")
	expect(Night.STATIONS.grove=={"cell":GROVE,"title":"林徑燈","hint":"公告板西北・林邊"},"grove")
	expect(Night.STATIONS.lane=={"cell":LANE,"title":"南路燈","hint":"種子攤南邊・海風小徑"},"lane")
	expect(Night.STATIONS.harbor=={"cell":HARBOR,"title":"港路燈","hint":"廣場東邊・往河邊"},"harbor")
	expect(Night.WISHES.keys()==["home","harvest","friends"],"wish order")
	expect(Night.WISHES.home=="願每盞燈都照得到回家的路。" and Night.WISHES.harvest=="願來年田裡也有足夠的收成。" and Night.WISHES.friends=="願下次相聚時，還能聽到大家的笑聲。","wish text")
	for w in Night.WISHES:expect(Night.WISHES[w] is String,"wish string")
	var v:=Night.view(world(),"a")
	expect(v.keys().size()==5 and v.in_season==true and v.unlocked==true and v.completed==false and v.joined==false and v.can_start==true,"fresh view")
	expect(Night.public_view(world())=={"round":0,"phase":"idle","lamps":{},"guests":0},"idle public view")
	expect(Night.valid(world()),"legacy absence valid")
	expect(Night.view({},"x").can_start==false and Night.view(world(),"ghost").can_start==true,"odd views")

func gates()->void:
	var s:=world(WINTER,false)
	var before:=s.duplicate(true)
	expect(start(s).ok==false,"picnic required")
	restore(s,before)
	expect(s==before,"picnic refusal changes nothing")
	expect(Night.view(s,"a").unlocked==false and Night.view(s,"a").can_start==false,"view needs picnic")
	s=world()
	stand(s,"a",Night.BOARD)
	expect(Night.apply(s,"a",Night.BOARD,"start",false).ok==false and not s.has("warm_lantern_night"),"home required")
	expect(Night.apply(s,"ghost",Night.BOARD,"start",true).ok==false,"unknown player")
	expect(Night.apply(s,"a",Vector2i(41,29),"start",true).ok==false,"wrong board cell")
	expect(Night.apply(s,"a",GROVE,"start",true).ok==false,"start at a lamp refused")
	stand(s,"a",Vector2i(60,60))
	expect(Night.apply(s,"a",Night.BOARD,"start",true).ok==false,"board from far away")
	s.players.a.x=40.5+3.19
	s.players.a.y=29.5
	expect(Night.apply(s,"a",Night.BOARD,"start",true).ok==true,"3.19 reaches board")
	s=world()
	s.players.a.x=40.5+3.25
	s.players.a.y=29.5
	expect(Night.apply(s,"a",Night.BOARD,"start",true).ok==false and not s.has("warm_lantern_night"),"3.25 too far")
	s.players.a.x=NAN
	expect(Night.apply(s,"a",Night.BOARD,"start",true).ok==false,"nan position")
	s.players.a.x=INF
	expect(Night.apply(s,"a",Night.BOARD,"start",true).ok==false,"inf position")
	# lamps: wrong cell, far, near
	s=world()
	start(s)
	stand(s,"a",GROVE)
	expect(Night.apply(s,"a",LANE,"light:1:grove:home",true).ok==false,"lamp cell must match station")
	expect(Night.apply(s,"a",Night.BOARD,"light:1:grove:home",true).ok==false,"lamp at board refused")
	expect(Night.apply(s,"a",Vector2i(35,27),"light:1:grove:home",true).ok==false,"neighbour cell refused")
	stand(s,"a",Vector2i(20,20))
	expect(Night.apply(s,"a",GROVE,"light:1:grove:home",true).ok==false,"lamp from far away")
	s.players.a.x=GROVE.x+0.5+3.25
	s.players.a.y=GROVE.y+0.5
	expect(Night.apply(s,"a",GROVE,"light:1:grove:home",true).ok==false,"3.25 from lamp too far")
	s.players.a.x=GROVE.x+0.5+3.19
	expect(Night.apply(s,"a",GROVE,"light:1:grove:home",true).ok==true,"3.19 from lamp reaches")
	expect(Night.apply(s,"b",LANE,"light:1:lane:home",false).ok==false,"lamp needs home")
	# join / finish need the board
	stand(s,"b",GROVE)
	expect(Night.apply(s,"b",GROVE,"join:1",true).ok==false,"join at a lamp refused")
	s.players.b.x=Night.BOARD.x+0.5+3.25
	s.players.b.y=Night.BOARD.y+0.5
	expect(Night.apply(s,"b",Night.BOARD,"join:1",true).ok==false and s.warm_lantern_night.participants==["a"],"join too far")
	s.players.b.x=Night.BOARD.x+0.5+3.19
	expect(Night.apply(s,"b",Night.BOARD,"join:1",true).ok==true,"join at 3.19")
	stand(s,"a",LANE)
	expect(Night.apply(s,"a",LANE,"finish:1",true).ok==false,"finish at a lamp refused")

func season()->void:
	for t in [WINTER_FIRST,WINTER,WINTER_LAST,WINTER_FIRST+56.0*DAY]:
		var s:=world(t)
		expect(Night.view(s,"a").in_season==true and Night.view(s,"a").can_start==true,"winter %s"%t)
		expect(start(s).ok==true,"start in winter %s"%t)
	for t in [SPRING,20160.0,AUTUMN_LAST,NEXT_SPRING,0.0,28.0*DAY]:
		var s:=world(t)
		var before:=s.duplicate(true)
		var v:=Night.view(s,"a")
		expect(v.in_season==false and v.can_start==false and v.unlocked==true,"off season %s"%t)
		expect(start(s).ok==false and not s.has("warm_lantern_night"),"first start refused %s"%t)
		restore(s,before)
		expect(s==before,"off-season changes nothing")
	expect(Night.in_season({"time":WINTER_LAST}) and not Night.in_season({"time":NEXT_SPRING}) and not Night.in_season({"time":AUTUMN_LAST}) and Night.in_season({"time":WINTER_FIRST}),"boundaries exact")
	expect(not Night.in_season({}),"missing time is not winter")

func flow()->void:
	var s:=world()
	var r:=start(s)
	expect(r.ok==true and r.message is String and not String(r.message).is_empty(),"start message")
	expect(s.warm_lantern_night=={"round":1,"phase":"lighting","lamps":{},"participants":["a"]},"started record")
	expect(Night.view(s,"a").joined==true and Night.view(s,"b").joined==false and Night.view(s,"a").can_start==false,"starter auto-enrolled")
	expect(start(s,"b").ok==false,"cannot start while lighting")
	expect(at_board(s,"a","join:1").ok==false,"starter cannot join twice")
	expect(at_board(s,"b","join:1").ok==true,"b joins")
	expect(s.warm_lantern_night.participants==["a","b"],"participants ordered")
	expect(light(s,"c","grove","home").ok==false,"not enrolled cannot light")
	expect(at_board(s,"a","finish:1").ok==false,"finish too early")
	r=light(s,"a","grove","home")
	expect(r.ok==true and String(r.message).begins_with("叮——暖燈"),"first light message")
	expect(s.warm_lantern_night.lamps=={"grove":"home"},"grove lit with wish id")
	expect(Night.public_view(s).lamps=={"grove":"home"},"public shows lamp")
	r=light(s,"b","lane","friends")
	expect(r.ok==true and String(r.message).begins_with("叮——暖燈"),"each newly lit lamp gets the chime")
	expect(at_board(s,"b","finish:1").ok==false and s.warm_lantern_night.phase=="lighting","two lamps are not enough")
	expect(not s.players.a.has("warm_lantern_night"),"no mark before finish")
	expect(light(s,"a","harbor","harvest").ok==true,"third lamp")
	expect(s.warm_lantern_night.lamps=={"grove":"home","lane":"friends","harbor":"harvest"},"all lamps by station")
	expect(at_board(s,"c","finish:1").ok==false,"non-enrolled cannot finish")
	r=at_board(s,"b","finish:1")
	expect(r.ok==true,"b finishes")
	expect(s.warm_lantern_night.phase=="celebrated" and s.warm_lantern_night.lamps.size()==3 and s.warm_lantern_night.participants==["a","b"],"celebrated keeps lamps and guests")
	expect(s.players.a.warm_lantern_night==true and s.players.b.warm_lantern_night==true and not s.players.c.has("warm_lantern_night"),"enrolled marked")
	expect(Night.public_view(s).phase=="celebrated" and Night.public_view(s).lamps.size()==3,"public celebrated keeps lights")
	expect(at_board(s,"a","finish:1").ok==false,"finish once only")
	expect(at_board(s,"c","join:1").ok==false and light(s,"a","grove","friends",1).ok==false,"closed after finish")
	expect(s.warm_lantern_night.lamps.grove=="home","wish unchanged after refused relight")
	expect(Night.valid(s),"celebrated state valid")
	expect(Night.view(s,"a").can_start==true and Night.view(s,"c").can_start==true,"after a finish anyone may start in winter")
	r=start(s,"c")
	expect(r.ok==true and s.warm_lantern_night=={"round":2,"phase":"lighting","lamps":{},"participants":["c"]},"round two fresh clears lamps")
	expect(s.players.a.warm_lantern_night==true,"completion persists")
	expect(Night.public_view(s).lamps=={},"new round dark")
	expect(at_board(s,"a","join:1").ok==false,"old round payload stale")
	expect(at_board(s,"a","join:2").ok==true,"current round joinable")

func stations_and_wishes()->void:
	for station in Night.STATIONS:
		for wish in Night.WISHES:
			var s:=world()
			start(s)
			var r:=light(s,"a",station,wish)
			expect(r.ok==true and s.warm_lantern_night.lamps=={station:wish},"light %s %s"%[station,wish])
			expect(String(r.message).begins_with("叮——暖燈") and String(r.message).contains(String(Night.STATIONS[station].title)) and Night.public_view(s).lamps.get(station)==wish,"Lamp feedback names the station and the public blessing remains readable")
	# same wish may be used on different lamps
	var t:=world()
	start(t)
	expect(light(t,"a","grove","home").ok==true and light(t,"a","lane","home").ok==true and light(t,"a","harbor","home").ok==true,"same wish on all lamps")
	expect(at_board(t,"a","finish:1").ok==true,"finish with repeated wish")
	# free text is never accepted
	t=world()
	start(t)
	var before:=t.duplicate(true)
	for wish in ["願天天開心","Home","HOME","home ","","tea","願每盞燈都照得到回家的路。"]:
		expect(light(t,"a","grove",wish).ok==false,"free text wish refused '%s'"%wish)
	for station in ["Grove","grove ","","harbour","board","34,27"]:
		stand(t,"a",GROVE)
		expect(Night.apply(t,"a",GROVE,"light:1:%s:home"%station,true).ok==false,"unknown station refused '%s'"%station)
		t.warm_lantern_night.lamps={}
	t.warm_lantern_night=before.get("warm_lantern_night",t.warm_lantern_night)
	expect(Night.public_view(t).lamps=={},"free text never lights")

func strict_payloads()->void:
	var s:=world()
	start(s)
	at_board(s,"b","join:1")
	var before:=s.duplicate(true)
	var bad:=["","join","join:","join:0","join:01","join:+1","join:-1","join: 1","join:1 ","join:1.0","join:1e0","join:١","join:1:","join:1:x",
		"JOIN:1","join:2","join:11","join:4294967297","join:99999999999","light","light:1","light:1:grove","light:1:grove:","light:1::home",
		"light:01:grove:home","light:1:grove:home:","light:2:grove:home","light: 1:grove:home","light:1:grove:Home","light:1:grove:home ","light:0:grove:home",
		"light:1:grove:home:x","finish","finish:","finish:1:x","finish:0","finish:2","start:1","Start","start ","bogus:1","START"]
	for extra in bad:
		expect(at_board(s,"c",extra).ok==false,"refused '%s'"%extra)
	for extra in bad:
		expect(at_board(s,"a",extra).ok==false,"refused enrolled '%s'"%extra)
	for extra in bad:
		if extra.begins_with("light"):
			stand(s,"a",GROVE)
			expect(Night.apply(s,"a",GROVE,extra,true).ok==false,"refused at lamp '%s'"%extra)
	expect(start(s,"c").ok==false and Night.apply(s,"c",Night.BOARD,"start ",true).ok==false and Night.apply(s,"c",Night.BOARD,"start:1",true).ok==false,"start payload exact")
	restore(s,before)
	expect(s==before,"bad payloads change nothing")
	expect(light(s,"a","grove","home").ok==true,"valid light still works")

func stale_and_duplicate()->void:
	var s:=world()
	start(s)
	expect(light(s,"a","grove","home").ok==true,"lit once")
	var after:=s.duplicate(true)
	expect(light(s,"a","grove","home").ok==false,"replayed light refused")
	expect(light(s,"a","grove","friends").ok==false,"relight with other wish refused")
	restore(s,after)
	expect(s==after and s.warm_lantern_night.lamps.grove=="home","duplicate keeps first wish")
	at_board(s,"b","join:1")
	after=s.duplicate(true)
	expect(light(s,"b","grove","harvest").ok==false,"other player cannot overwrite a lit lamp")
	expect(at_board(s,"b","join:1").ok==false,"duplicate join refused")
	restore(s,after)
	expect(s==after,"duplicate join/light change nothing")
	light(s,"a","lane","home")
	light(s,"a","harbor","home")
	expect(at_board(s,"a","finish:1").ok==true,"finish round 1")
	after=s.duplicate(true)
	expect(at_board(s,"b","finish:1").ok==false,"replayed finish refused")
	restore(s,after)
	expect(s==after,"replayed finish changes nothing")
	start(s,"b")
	expect(s.warm_lantern_night.round==2,"round two")
	after=s.duplicate(true)
	expect(light(s,"b","grove","home",1).ok==false,"stale light refused")
	expect(at_board(s,"b","finish:1").ok==false and at_board(s,"a","join:1").ok==false,"stale finish/join refused")
	restore(s,after)
	expect(s==after and s.warm_lantern_night.lamps.is_empty(),"stale payloads change nothing")
	expect(light(s,"b","grove","home",3).ok==false,"future round refused")
	# nothing stored for a world that never started
	var t:=world()
	expect(at_board(t,"a","join:1").ok==false and light(t,"a","grove","home",1).ok==false and at_board(t,"a","finish:1").ok==false,"no round yet")
	expect(not t.has("warm_lantern_night"),"nothing written without start")

func finish_rules()->void:
	for lit in [[],["grove"],["lane","harbor"],["grove","harbor"]]:
		var s:=world()
		start(s)
		for st in lit:light(s,"a",st,"home")
		var before:=s.duplicate(true)
		var r:=at_board(s,"a","finish:1")
		expect(r.ok==false,"finish with %d lamps refused"%lit.size())
		restore(s,before)
		expect(s==before,"incomplete finish changes nothing")
	# finish is allowed at any time of day and any season once all are lit
	for t in [WINTER_FIRST,WINTER_FIRST+0.5*DAY,SPRING,NEXT_SPRING]:
		var s:=world(WINTER)
		start(s)
		light_all(s,"a")
		s.time=t
		expect(at_board(s,"a","finish:1").ok==true and s.players.a.warm_lantern_night==true,"finish any time %s"%t)
	# lighting is also possible in any time of day (no dusk gate)
	for clock in [0.0,0.25,0.5,0.75,0.99]:
		var s:=world(WINTER_FIRST+clock*DAY)
		expect(start(s).ok==true and light(s,"a","lane","friends").ok==true,"no dusk gate %s"%clock)
	# a solo finisher marks everyone enrolled, nobody else
	var s:=world()
	start(s)
	at_board(s,"b","join:1")
	light_all(s,"a")
	at_board(s,"b","finish:1")
	expect(Night.view(s,"a").completed and Night.view(s,"b").completed and not Night.view(s,"c").completed,"completion for all participants")
	# someone enrolled who already finished earlier keeps the keepsake and the message differs
	s=world()
	s.players.a.warm_lantern_night=true
	start(s)
	light_all(s,"a")
	var r:=at_board(s,"a","finish:1")
	expect(r.ok==true and s.players.a.warm_lantern_night==true,"repeat finish ok")

func cap_and_solo()->void:
	var s:=world()
	for i in range(12):s.players["p%d"%i]=person()
	start(s)
	for i in range(7):
		expect(at_board(s,"p%d"%i,"join:1").ok==true,"join %d"%i)
	expect(s.warm_lantern_night.participants.size()==8,"eight enrolled")
	expect(Night.public_view(s).guests==8,"eight guests")
	var before:=s.duplicate(true)
	expect(at_board(s,"p9","join:1").ok==false,"ninth refused")
	restore(s,before,["p9"])
	expect(s==before and Night.view(s,"p9").joined==false,"full refusal changes nothing")
	expect(light(s,"p9","grove","home").ok==false,"ninth cannot light")
	expect(light(s,"p5","grove","home").ok==true,"eighth can light")
	light(s,"p6","lane","home")
	expect(light(s,"p7","harbor","friends").ok==false,"p7 never enrolled cannot light")
	light(s,"p4","harbor","friends")
	expect(at_board(s,"p3","finish:1").ok==true,"any of eight finishes")
	var marked:=0
	for t in s.players:
		if s.players[t].has("warm_lantern_night"):marked+=1
	expect(marked==8 and s.players.a.warm_lantern_night==true and not s.players.p9.has("warm_lantern_night") and not s.players.p7.has("warm_lantern_night") and not s.players.b.has("warm_lantern_night"),"exactly the eight enrolled marked")
	expect(Night.valid(s),"eight celebrated valid")
	# solo
	var solo:=world()
	solo.players={"only":person()}
	start(solo,"only")
	light_all(solo,"only")
	expect(at_board(solo,"only","finish:1").ok==true and solo.players.only.warm_lantern_night==true and Night.public_view(solo).guests==1,"solo completes")
	expect(Night.valid(solo),"solo valid")

func atomic_refusals()->void:
	var s:=world()
	start(s)
	s.players.b.warm_lantern_night=1
	var before:=s.duplicate(true)
	expect(at_board(s,"b","join:1").ok==false,"non-bool personal flag refused")
	restore(s,before)
	expect(s==before,"corrupt personal untouched")
	s=world()
	s.warm_lantern_night={"round":1,"phase":"lighting","lamps":{"grove":"cheer"},"participants":["a"]}
	before=s.duplicate(true)
	expect(light(s,"a","lane","home",1).ok==false and start(s,"a").ok==false,"corrupt shared refused")
	restore(s,before)
	expect(s==before,"corrupt shared untouched")
	expect(Night.public_view(s)=={"round":0,"phase":"idle","lamps":{},"guests":0} and Night.view(s,"a").can_start==false,"corrupt shared views safe")
	s=world()
	start(s)
	at_board(s,"b","join:1")
	light_all(s,"a")
	s.players.erase("b")
	before=s.duplicate(true)
	expect(at_board(s,"a","finish:1").ok==false,"finish with missing participant refused")
	restore(s,before,["a"])
	expect(s==before and not s.players.a.has("warm_lantern_night"),"no partial marks")

func crossing_and_replay()->void:
	var s:=world(WINTER_LAST)
	start(s)
	at_board(s,"b","join:1")
	light(s,"a","grove","home")
	s.time=NEXT_SPRING+5000.0
	var v:=Night.view(s,"a")
	expect(v.in_season==false and v.joined==true and v.can_start==false and v.completed==false,"ongoing visible after winter")
	expect(at_board(s,"c","join:1").ok==true,"join after winter")
	expect(light(s,"b","lane","friends").ok==true and light(s,"c","harbor","harvest").ok==true,"light after winter")
	expect(at_board(s,"c","finish:1").ok==true,"finish after winter")
	expect(s.players.a.warm_lantern_night==true and s.players.b.warm_lantern_night==true and s.players.c.warm_lantern_night==true,"all three completed")
	for t in [SPRING,20160.0,AUTUMN_LAST,WINTER_FIRST+3.0*DAY,NEXT_SPRING]:
		s.time=t
		expect(Night.view(s,"a").can_start==true,"graduate can start %s"%t)
		expect(start(s,"a").ok==true,"graduate replays %s"%t)
		expect(start(s,"b").ok==false,"no second start midway %s"%t)
		expect(at_board(s,"b","join:%d"%int(s.warm_lantern_night.round)).ok==true,"join replay")
		light_all(s,"a")
		expect(at_board(s,"a","finish:%d"%int(s.warm_lantern_night.round)).ok==true,"replay finished %s"%t)
	expect(s.warm_lantern_night.round==6,"rounds advanced")
	s.players.c.erase("warm_lantern_night")
	expect(Night.view(s,"c").can_start==false and start(s,"c").ok==false,"non-graduate off season refused")
	s.time=WINTER
	expect(start(s,"c").ok==true,"non-graduate in winter starts")
	# round ceiling
	s=world()
	s.warm_lantern_night={"round":Night.MAX_ROUND,"phase":"celebrated","lamps":{"grove":"home","lane":"home","harbor":"home"},"participants":["a"]}
	s.players.a.warm_lantern_night=true
	expect(Night.valid(s),"max round valid")
	expect(start(s).ok==false and Night.view(s,"a").can_start==false,"no round past the ceiling")

func public_and_view()->void:
	var s:=world()
	start(s,"a")
	at_board(s,"b","join:1")
	light(s,"a","lane","friends")
	var pub:=Night.public_view(s)
	expect(pub.keys().size()==4 and pub.round==1 and pub.phase=="lighting" and pub.lamps=={"lane":"friends"} and pub.guests==2,"public display only")
	var text:=JSON.stringify(pub)
	expect(not text.contains("\"a\"") and not text.contains("島民") and not text.contains("participants") and not text.contains("願"),"no actor identity or free text")
	for token in s.players:expect(not text.contains(String(token).sha256_text().left(16)),"no hashed identity")
	var loaded:Variant=JSON.parse_string(JSON.stringify(s))
	expect(loaded is Dictionary and Night.valid(loaded),"json round trip valid")
	expect(Night.public_view(loaded).round is int and Night.public_view(loaded).round==1,"integer round after reload")
	expect(loaded.warm_lantern_night.round is int,"normalised to int")
	expect(light(loaded,"b","harbor","home").ok==true,"continue after reload")
	expect(Night.view(s,"b").joined==true and Night.view(s,"c").joined==false,"own joined only")
	var ov:=Night.view(s,"c")
	expect(ov.keys().size()==5 and not JSON.stringify(ov).contains("lamps"),"view has no shared detail")
	# the keepsake shows only in the owner's view
	s.players.a.warm_lantern_night=true
	expect(Night.view(s,"a").completed==true and Night.view(s,"b").completed==false,"completion is personal")

func validation()->void:
	var full={"grove":"home","lane":"harvest","harbor":"friends"}
	var s:=world()
	s.warm_lantern_night={"round":3,"phase":"lighting","lamps":{"lane":"home"},"participants":["a","b"]}
	expect(Night.valid(s),"lighting valid")
	s.warm_lantern_night={"round":3.0,"phase":"celebrated","lamps":full.duplicate(),"participants":["a"]}
	s.players.a.warm_lantern_night=true
	expect(Night.valid(s) and s.warm_lantern_night.round is int,"float round normalised, celebrated valid")
	s=world()
	s.players.a.warm_lantern_night=true
	expect(Night.valid(s),"personal without shared valid")
	s=world(WINTER,false)
	s.warm_lantern_night={"round":1,"phase":"lighting","lamps":{},"participants":["a"]}
	expect(not Night.valid(s),"shared needs picnic")
	var shapes:Array=[
		{},[],"x",5,true,null,
		{"round":1,"phase":"lighting","lamps":{}},
		{"round":1,"phase":"lighting","lamps":{},"participants":["a"],"extra":1},
		{"round":0,"phase":"lighting","lamps":{},"participants":["a"]},
		{"round":1000000001,"phase":"lighting","lamps":{},"participants":["a"]},
		{"round":1.5,"phase":"lighting","lamps":{},"participants":["a"]},
		{"round":"1","phase":"lighting","lamps":{},"participants":["a"]},
		{"round":NAN,"phase":"lighting","lamps":{},"participants":["a"]},
		{"round":1,"phase":"idle","lamps":{},"participants":["a"]},
		{"round":1,"phase":"collect","lamps":{},"participants":["a"]},
		{"round":1,"phase":1,"lamps":{},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":[],"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{"grove":"cheer"},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{"grove":"願每盞燈都照得到回家的路。"},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{"cellar":"home"},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{"grove":5},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{"grove":null},"participants":["a"]},
		{"round":1,"phase":"lighting","lamps":{},"participants":[]},
		{"round":1,"phase":"lighting","lamps":{},"participants":"a"},
		{"round":1,"phase":"lighting","lamps":{},"participants":["a","a"]},
		{"round":1,"phase":"lighting","lamps":{},"participants":["ghost"]},
		{"round":1,"phase":"lighting","lamps":{},"participants":[1]},
		{"round":1,"phase":"lighting","lamps":{},"participants":["a","b","c","d","e","f","g","h","i"]},
		{"round":1,"phase":"celebrated","lamps":{"grove":"home"},"participants":["a"]},
		{"round":1,"phase":"celebrated","lamps":full.duplicate(),"participants":["b"]},
	]
	for i in range(shapes.size()):
		var t:=world()
		for extra_player in ["d","e","f","g","h","i"]:t.players[extra_player]=person()
		t.players.a.warm_lantern_night=true
		t.warm_lantern_night=shapes[i]
		expect(not Night.valid(t),"invalid shared %d"%i)
	var eight:=world()
	var names:=[]
	for i in range(8):
		eight.players["q%d"%i]=person()
		names.append("q%d"%i)
	eight.warm_lantern_night={"round":1,"phase":"lighting","lamps":{},"participants":names}
	expect(Night.valid(eight),"eight participants valid")
	eight.warm_lantern_night.participants.append("a")
	expect(not Night.valid(eight),"nine participants invalid")
	for junk in [1,0,"true",false,null,1.0,[],{}]:
		var t:=world()
		t.players.a.warm_lantern_night=junk
		expect(not Night.valid(t),"invalid personal %s"%str(junk))
	expect(not Night.valid({}) and not Night.valid({"players":5}),"no players invalid")
	# save round trip of a celebrated world keeps everything
	var t:=world()
	start(t)
	light_all(t,"a")
	at_board(t,"a","finish:1")
	var back:Variant=JSON.parse_string(JSON.stringify(t))
	expect(back is Dictionary and Night.valid(back) and back.warm_lantern_night.lamps==t.warm_lantern_night.lamps and back.players.a.warm_lantern_night==true,"celebrated save round trip")
	expect(Night.public_view(back)==Night.public_view(t),"public view stable after reload")

func economy_untouched()->void:
	var s:=world()
	var rest:=s.duplicate(true)
	start(s)
	at_board(s,"b","join:1")
	light(s,"a","grove","home")
	light(s,"b","lane","harvest")
	light(s,"a","harbor","friends")
	at_board(s,"b","finish:1")
	var a:Dictionary=s.players.a
	expect(a.coins==120 and a.bag==["seed"] and a.name=="島民","coins, bag list and name untouched")
	expect(a.inventory=={"radish":2,"turnip":4,"trout_hotpot":2} and s.players.b.inventory==a.inventory,"inventory untouched")
	expect(s.time==rest.time and s.community==rest.community and s.board==rest.board and s.crops==rest.crops,"clock and world data untouched")
	expect(s.players.c==rest.players.c,"bystander untouched")
	var keys:=a.keys()
	keys.sort()
	expect(keys==["bag","coins","inventory","name","warm_lantern_night","x","y"],"only warm_lantern_night added to player")
	var top:=s.keys()
	top.sort()
	var expected:=rest.keys()
	expected.append("warm_lantern_night")
	expected.sort()
	expect(top==expected,"only the shared key added")
