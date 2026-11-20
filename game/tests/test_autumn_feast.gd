extends SceneTree
## Regression suite for res://scripts/autumn_feast.gd (秋季豐收宴): picnic / table / home /
## distance gates, autumn boundary, ongoing rounds crossing seasons, permanent replays,
## the shared platter (join cap, strict payloads, one item per category, exact bag use),
## serving once, atomic refusals, public view privacy, and strict save validation.
const Feast=preload("res://scripts/autumn_feast.gd")
const AUTUMN:=28.0*1440.0+10.0
const AUTUMN_FIRST:=28.0*1440.0
const AUTUMN_LAST:=42.0*1440.0-0.01
const WINTER:=42.0*1440.0
const SPRING:=100.0
const TABLE:=Vector2i(39,30)
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("AUTUMN_FEAST_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func person()->Dictionary:
	return {"x":40.5,"y":29.5,"coins":120,"name":"島民","bag":["seed"],
		"inventory":{"radish":2,"lettuce":1,"wheat":3,"carrot":1,"pumpkin":1,"trout_hotpot":2,"turnip":4}}

static func world(time:float=AUTUMN,picnic:bool=true,table:String="39,30")->Dictionary:
	return {"picnic":picnic,"time":time,"community":{"table":table,"hotpot":{"portions":3,"claimed":{"b":true}}},
		"board":{"note":1},"crops":{"1,1":{"kind":"turnip"}},
		"players":{"a":person(),"b":person(),"c":person()}}

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

func start(state:Dictionary,token:String="a")->Dictionary:
	stand(state,token,Feast.BOARD)
	return Feast.apply(state,token,Feast.BOARD,"start",true)

func at_table(state:Dictionary,token:String,extra:String)->Dictionary:
	stand(state,token,TABLE)
	return Feast.apply(state,token,TABLE,extra,true)

func fill(state:Dictionary,token:String)->void:
	for item in ["radish","lettuce","wheat"]:
		expect(at_table(state,token,"give:%d:%s"%[int(state.autumn_feast.round),item]).ok==true,"fill "+item)

func _initialize()->void:
	contract()
	gates()
	season()
	flow()
	join_cap()
	strict_payloads()
	slots_and_bag()
	serve_rules()
	atomic_refusals()
	crossing_and_replay()
	public_and_view()
	validation()
	economy_untouched()
	finish()

func contract()->void:
	expect(Feast.ACTION=="autumn_feast" and Feast.KEY=="autumn_feast" and Feast.VIEW_KEY=="own_autumn_feast","names")
	expect(Feast.BOARD==Vector2i(40,29),"board")
	expect(Feast.SLOTS.keys()==["roots","greens","gold"],"slot order")
	expect(Feast.SLOTS.roots.items==["radish","carrot","sweet_potato"] and Feast.SLOTS.greens.items==["lettuce","cabbage","cauliflower"] and Feast.SLOTS.gold.items==["wheat","sweet_corn","pumpkin"],"slot items")
	expect(Feast.SLOTS.roots.title=="根莖" and Feast.SLOTS.greens.title=="青菜" and Feast.SLOTS.gold.title=="金色穀果","slot titles")
	var v:=Feast.view(world(),"a")
	expect(v.keys().size()==5 and v.in_season==true and v.unlocked==true and v.completed==false and v.joined==false and v.can_start==true,"fresh view")
	expect(Feast.public_view(world())=={"round":0,"phase":"idle","entries":{},"count":0,"guests":0},"idle public view")
	expect(Feast.valid(world()),"legacy absence valid")
	expect(Feast.view({},"x").can_start==false and Feast.view(world(),"ghost").can_start==true,"odd views")

func gates()->void:
	var s:=world(AUTUMN,false)
	var before:=s.duplicate(true)
	expect(start(s).ok==false and s==before,"picnic required")
	s=world(AUTUMN,true,"")
	expect(start(s).ok==false and not s.has("autumn_feast"),"actual table required")
	expect(Feast.view(s,"a").unlocked==false and Feast.view(s,"a").can_start==false,"view needs table")
	s=world(AUTUMN,true,"50,50")
	expect(start(s).ok==false,"non-candidate table refused")
	s=world()
	stand(s,"a",Feast.BOARD)
	expect(Feast.apply(s,"a",Feast.BOARD,"start",false).ok==false and not s.has("autumn_feast"),"home required")
	expect(Feast.apply(s,"ghost",Feast.BOARD,"start",true).ok==false,"unknown player")
	expect(Feast.apply(s,"a",Vector2i(41,29),"start",true).ok==false,"wrong board cell")
	expect(Feast.apply(s,"a",TABLE,"start",true).ok==false,"start at table refused")
	stand(s,"a",Vector2i(60,60))
	expect(Feast.apply(s,"a",Feast.BOARD,"start",true).ok==false,"claim board from far away")
	s.players.a.x=40.5+3.19
	s.players.a.y=29.5
	expect(Feast.apply(s,"a",Feast.BOARD,"start",true).ok==true,"3.19 reaches")
	s=world()
	s.players.a.x=40.5+3.25
	s.players.a.y=29.5
	expect(Feast.apply(s,"a",Feast.BOARD,"start",true).ok==false and not s.has("autumn_feast"),"3.25 too far")
	s.players.a.x=NAN
	expect(Feast.apply(s,"a",Feast.BOARD,"start",true).ok==false,"nan position")
	s=world()
	start(s)
	stand(s,"a",Vector2i(20,20))
	expect(Feast.apply(s,"a",TABLE,"serve:1",true).ok==false,"table from far away")
	stand(s,"a",TABLE)
	expect(Feast.apply(s,"a",Vector2i(39,31),"join:1",true).ok==false,"wrong table cell")
	s.players.b.x=center(TABLE).x+3.25
	s.players.b.y=center(TABLE).y
	expect(Feast.apply(s,"b",TABLE,"join:1",true).ok==false and s.autumn_feast.participants==["a"],"b too far from table")
	s.players.b.x=center(TABLE).x+3.19
	expect(Feast.apply(s,"b",TABLE,"join:1",true).ok==true,"b 3.19 from table reaches")
	for cell in [Vector2i(39,31),Vector2i(40,31)]:
		var t:=world(AUTUMN,true,"%d,%d"%[cell.x,cell.y])
		start(t)
		stand(t,"b",cell)
		expect(Feast.apply(t,"b",cell,"join:1",true).ok==true,"other candidate table %s"%cell)

func season()->void:
	for t in [AUTUMN_FIRST,AUTUMN,AUTUMN_LAST,AUTUMN_FIRST+56.0*1440.0]:
		var s:=world(t)
		expect(Feast.view(s,"a").in_season==true and Feast.view(s,"a").can_start==true,"autumn %s"%t)
		expect(start(s).ok==true,"start in autumn %s"%t)
	for t in [SPRING,20160.0,WINTER,AUTUMN_FIRST-1.0,60000.0*2.0]:
		var s:=world(t)
		var before:=s.duplicate(true)
		expect(Feast.view(s,"a").in_season==false and Feast.view(s,"a").can_start==false and Feast.view(s,"a").unlocked==true,"off season %s"%t)
		expect(start(s).ok==false and not s.has("autumn_feast"),"first start refused %s"%t)
		s.players.a.x=before.players.a.x
		s.players.a.y=before.players.a.y
		expect(s==before,"off-season changes nothing")
	expect(Feast.in_season({"time":AUTUMN_LAST}) and not Feast.in_season({"time":WINTER}),"boundary exact")

func flow()->void:
	var s:=world()
	var r:=start(s)
	expect(r.ok==true and r.message is String and not String(r.message).is_empty(),"start message")
	expect(s.autumn_feast=={"round":1,"phase":"collect","entries":{},"participants":["a"]},"started record")
	expect(Feast.view(s,"a").joined==true and Feast.view(s,"b").joined==false and Feast.view(s,"a").can_start==false,"starter auto-enrolled")
	expect(start(s,"b").ok==false,"cannot start while collecting")
	expect(at_table(s,"a","join:1").ok==false,"starter cannot join twice")
	expect(at_table(s,"b","join:1").ok==true,"b joins")
	expect(s.autumn_feast.participants==["a","b"],"participants ordered")
	expect(at_table(s,"a","serve:1").ok==false,"serve too early")
	expect(at_table(s,"a","give:1:radish").ok==true,"a gives radish")
	expect(at_table(s,"b","give:1:lettuce").ok==true,"b gives lettuce")
	expect(at_table(s,"b","serve:1").ok==false and s.autumn_feast.phase=="collect","still missing gold")
	expect(at_table(s,"a","give:1:pumpkin").ok==true,"a gives pumpkin")
	expect(s.autumn_feast.entries=={"roots":"radish","greens":"lettuce","gold":"pumpkin"},"entries by slot")
	expect(Feast.public_view(s).count==3,"count three")
	expect(not s.players.a.has("autumn_feast") and not s.players.b.has("autumn_feast"),"no mark before serve")
	expect(at_table(s,"c","serve:1").ok==false,"non-enrolled cannot serve")
	r=at_table(s,"b","serve:1")
	expect(r.ok==true,"b serves")
	expect(s.autumn_feast.phase=="served" and s.autumn_feast.entries.size()==3 and s.autumn_feast.participants==["a","b"],"served keeps entries")
	expect(s.players.a.autumn_feast==true and s.players.b.autumn_feast==true and not s.players.c.has("autumn_feast"),"enrolled marked")
	expect(at_table(s,"a","serve:1").ok==false,"serve once only")
	expect(at_table(s,"c","join:1").ok==false and at_table(s,"a","give:1:carrot").ok==false,"closed after serve")
	expect(Feast.valid(s),"served state valid")
	# next round after serve: a completed player or autumn starter begins round 2, entries clear
	r=start(s,"c")
	expect(r.ok==true and s.autumn_feast=={"round":2,"phase":"collect","entries":{},"participants":["c"]},"round two fresh")
	expect(s.players.a.autumn_feast==true,"completion persists")
	expect(at_table(s,"a","join:1").ok==false,"old round payload is stale")
	expect(at_table(s,"a","join:2").ok==true,"current round joinable")

func join_cap()->void:
	var s:=world()
	for i in range(12):s.players["p%d"%i]=person()
	start(s)
	for i in range(7):
		expect(at_table(s,"p%d"%i,"join:1").ok==true,"join %d"%i)
	expect(s.autumn_feast.participants.size()==8,"eight enrolled")
	var before:=s.duplicate(true)
	expect(at_table(s,"p9","join:1").ok==false,"ninth refused")
	s.players.p9.x=before.players.p9.x
	s.players.p9.y=before.players.p9.y
	expect(s==before,"full refusal changes nothing")
	expect(Feast.view(s,"p9").joined==false,"ninth not joined")

func strict_payloads()->void:
	var s:=world()
	start(s)
	at_table(s,"b","join:1")
	var before:=s.duplicate(true)
	var bad:=["","join","join:","join:0","join:01","join:+1","join:-1","join: 1","join:1 ","join:1.0","join:1e0","join:١","join:1:","join:1:x",
		"JOIN:1","join:2","join:11","join:4294967297","join:99999999999","give:1","give:1:","give:1:turnip","give:1:trout_hotpot","give:01:radish",
		"give:1:radish:","give:2:radish","give: 1:radish","give:1:Radish","give:1:radish ","serve","serve:","serve:1:x","serve:0","serve:2","start:1","Start","start ","bogus:1"]
	for extra in bad:
		var r:=at_table(s,"c",extra)
		expect(r.ok==false,"refused '%s'"%extra)
	for extra in bad:
		var r:=at_table(s,"a",extra)
		expect(r.ok==false,"refused enrolled '%s'"%extra)
	stand(s,"c",Feast.BOARD)
	expect(Feast.apply(s,"c",Feast.BOARD,"start ",true).ok==false and Feast.apply(s,"c",Feast.BOARD,"start:1",true).ok==false,"start payload exact")
	for token in ["a","b","c"]:
		s.players[token].x=before.players[token].x
		s.players[token].y=before.players[token].y
	expect(s==before,"bad payloads change nothing")
	# a stale round after the next one began cannot be replayed
	expect(at_table(s,"a","give:1:radish").ok==true,"valid give still works")
	var round_text:=str(s.autumn_feast.round)
	expect(round_text=="1","canonical round text")

func slots_and_bag()->void:
	var s:=world()
	start(s)
	var inv:Dictionary=s.players.a.inventory
	var r:=at_table(s,"a","give:1:wheat")
	expect(r.ok==true and s.autumn_feast.entries=={"gold":"wheat"},"gold slot filled")
	expect(inv.wheat==2 and inv.radish==2 and inv.lettuce==1 and inv.turnip==4 and inv.trout_hotpot==2,"exactly one wheat consumed")
	var before:=s.duplicate(true)
	expect(at_table(s,"a","give:1:pumpkin").ok==false,"gold slot already taken")
	expect(at_table(s,"a","give:1:wheat").ok==false,"same item twice refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before and inv.pumpkin==1,"taken slot refusal keeps bag")
	expect(at_table(s,"a","give:1:cauliflower").ok==false and s.autumn_feast.entries.size()==1,"no cauliflower in bag")
	expect(at_table(s,"a","give:1:sweet_potato").ok==false,"no sweet potato in bag")
	expect(not s.players.a.inventory.has("sweet_potato"),"no phantom stock")
	s.players.a.inventory.carrot=0
	expect(at_table(s,"a","give:1:carrot").ok==false,"zero stock refused")
	s.players.a.inventory.carrot=1.0
	expect(at_table(s,"a","give:1:carrot").ok==true and int(s.players.a.inventory.carrot)==0,"float stock accepted")
	s.players.a.inventory=[]
	expect(at_table(s,"a","give:1:lettuce").ok==false,"bad inventory refused")
	s.players.a.inventory={"lettuce":1}
	expect(at_table(s,"b","give:1:lettuce").ok==false and s.players.a.inventory.lettuce==1,"unenrolled cannot give")
	# last stock leaves a zero count and no other change
	expect(at_table(s,"a","give:1:lettuce").ok==true and int(s.players.a.inventory.lettuce)==0,"last lettuce used")
	expect(s.players.b.inventory.lettuce==1,"other bag untouched")
	for slot in Feast.SLOTS:
		for item in Feast.SLOTS[slot].items:
			expect(Feast.slot_of(item)==slot,"slot_of "+item)
	expect(Feast.slot_of("turnip")=="" and Feast.slot_of("")=="","slot_of unknown")

func serve_rules()->void:
	for missing in ["roots","greens","gold"]:
		var s:=world()
		start(s)
		var items={"roots":"radish","greens":"lettuce","gold":"wheat"}
		for slot in items:
			if slot!=missing:at_table(s,"a","give:1:%s"%items[slot])
		var before:=s.duplicate(true)
		expect(at_table(s,"a","serve:1").ok==false,"serve without "+missing)
		s.players.a.x=before.players.a.x
		s.players.a.y=before.players.a.y
		expect(s==before,"incomplete serve changes nothing")
	var s:=world()
	start(s)
	at_table(s,"b","join:1")
	fill(s,"a")
	expect(at_table(s,"b","serve:1").ok==true and s.players.a.autumn_feast==true,"another enrolled can serve")
	expect(Feast.view(s,"a").completed==true and Feast.view(s,"b").completed==true and Feast.view(s,"c").completed==false,"views completed")
	expect(Feast.public_view(s).phase=="served","public served")

func atomic_refusals()->void:
	var s:=world()
	start(s)
	s.players.b.autumn_feast=1
	var before:=s.duplicate(true)
	expect(at_table(s,"b","join:1").ok==false,"non-bool personal flag refused")
	s.players.b.x=before.players.b.x
	s.players.b.y=before.players.b.y
	expect(s==before,"corrupt personal untouched")
	s=world()
	s.autumn_feast={"round":1,"phase":"collect","entries":{"roots":"wheat"},"participants":["a"]}
	before=s.duplicate(true)
	expect(at_table(s,"a","give:1:lettuce").ok==false and start(s,"a").ok==false,"corrupt shared refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before,"corrupt shared untouched")
	expect(Feast.public_view(s)=={"round":0,"phase":"idle","entries":{},"count":0,"guests":0} and Feast.view(s,"a").can_start==false,"corrupt shared views safe")
	# a serve with a participant that vanished must not half-mark anyone
	s=world()
	start(s)
	at_table(s,"b","join:1")
	fill(s,"a")
	s.players.erase("b")
	before=s.duplicate(true)
	expect(at_table(s,"a","serve:1").ok==false,"serve with missing participant refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before and not s.players.a.has("autumn_feast"),"no partial marks")

func crossing_and_replay()->void:
	var s:=world(AUTUMN_LAST)
	start(s)
	at_table(s,"b","join:1")
	at_table(s,"a","give:1:radish")
	s.time=WINTER+5000.0
	var v:=Feast.view(s,"a")
	expect(v.in_season==false and v.joined==true and v.can_start==false and v.completed==false,"ongoing visible after autumn")
	expect(at_table(s,"c","join:1").ok==true,"join after autumn")
	expect(at_table(s,"b","give:1:lettuce").ok==true and at_table(s,"c","give:1:wheat").ok==true,"give after autumn")
	expect(at_table(s,"c","serve:1").ok==true,"serve after autumn")
	expect(s.players.a.autumn_feast==true and s.players.b.autumn_feast==true and s.players.c.autumn_feast==true,"all three completed")
	for t in [SPRING,20160.0,WINTER,AUTUMN_FIRST-1.0]:
		s.time=t
		expect(Feast.view(s,"a").can_start==true,"graduate can start %s"%t)
		expect(start(s,"a").ok==true,"graduate replays %s"%t)
		expect(start(s,"b").ok==false,"no second start midway %s"%t)
		expect(at_table(s,"b","join:%d"%int(s.autumn_feast.round)).ok==true,"join replay")
		fill(s,"a")
		expect(at_table(s,"a","serve:%d"%int(s.autumn_feast.round)).ok==true,"replay served %s"%t)
		for who in ["a","b"]:
			s.players[who].inventory={"radish":2,"lettuce":1,"wheat":3}
	expect(s.autumn_feast.round==5,"rounds advanced")
	# a non-graduate cannot replay off season even while others can
	s.players.c.erase("autumn_feast")
	expect(Feast.view(s,"c").can_start==false and start(s,"c").ok==false,"non-graduate off season refused")
	# round ceiling
	s=world()
	s.autumn_feast={"round":Feast.MAX_ROUND,"phase":"served","entries":{"roots":"radish","greens":"lettuce","gold":"wheat"},"participants":["a"]}
	s.players.a.autumn_feast=true
	expect(Feast.valid(s),"max round valid")
	expect(start(s).ok==false and Feast.view(s,"a").can_start==false,"no round past the ceiling")

func public_and_view()->void:
	var s:=world()
	start(s,"a")
	at_table(s,"b","join:1")
	at_table(s,"a","give:1:wheat")
	var pub:=Feast.public_view(s)
	expect(pub.keys().size()==5 and pub.round==1 and pub.phase=="collect" and pub.entries=={"gold":"wheat"} and pub.count==1 and pub.guests==2,"public display counts only")
	var text:=JSON.stringify(pub)
	expect(not text.contains("\"a\"") and not text.contains("島民") and not text.contains("participants"),"no actor identity")
	for token in s.players:expect(not text.contains(String(token).sha256_text().left(16)),"no hashed identity")
	var loaded:Variant=JSON.parse_string(JSON.stringify(s))
	expect(loaded is Dictionary and Feast.valid(loaded),"json round trip valid")
	expect(Feast.public_view(loaded).round is int and Feast.public_view(loaded).round==1,"integer round after reload")
	stand(loaded,"b",TABLE)
	expect(Feast.apply(loaded,"b",TABLE,"give:1:radish",true).ok==true,"continue after reload")
	expect(Feast.view(s,"b").joined==true and Feast.view(s,"c").joined==false,"own joined only")

func validation()->void:
	var full={"roots":"radish","greens":"cabbage","gold":"sweet_corn"}
	var s:=world()
	s.autumn_feast={"round":3,"phase":"collect","entries":{"greens":"lettuce"},"participants":["a","b"]}
	expect(Feast.valid(s),"collect valid")
	s.autumn_feast={"round":3.0,"phase":"served","entries":full.duplicate(),"participants":["a"]}
	s.players.a.autumn_feast=true
	expect(Feast.valid(s) and s.autumn_feast.round is int,"float round normalised, served valid")
	s=world()
	s.players.a.autumn_feast=true
	expect(Feast.valid(s),"personal without shared valid (legacy)")
	s=world(AUTUMN,false)
	s.autumn_feast={"round":1,"phase":"collect","entries":{},"participants":["a"]}
	expect(not Feast.valid(s),"shared needs picnic")
	s=world(AUTUMN,true,"")
	s.autumn_feast={"round":1,"phase":"collect","entries":{},"participants":["a"]}
	expect(not Feast.valid(s),"shared needs table")
	var shapes:Array=[
		{},[],"x",5,true,null,
		{"round":1,"phase":"collect","entries":{}},
		{"round":1,"phase":"collect","entries":{},"participants":["a"],"extra":1},
		{"round":0,"phase":"collect","entries":{},"participants":["a"]},
		{"round":1000000001,"phase":"collect","entries":{},"participants":["a"]},
		{"round":1.5,"phase":"collect","entries":{},"participants":["a"]},
		{"round":"1","phase":"collect","entries":{},"participants":["a"]},
		{"round":NAN,"phase":"collect","entries":{},"participants":["a"]},
		{"round":1,"phase":"idle","entries":{},"participants":["a"]},
		{"round":1,"phase":1,"entries":{},"participants":["a"]},
		{"round":1,"phase":"collect","entries":[],"participants":["a"]},
		{"round":1,"phase":"collect","entries":{"roots":"lettuce"},"participants":["a"]},
		{"round":1,"phase":"collect","entries":{"roots":"turnip"},"participants":["a"]},
		{"round":1,"phase":"collect","entries":{"snacks":"radish"},"participants":["a"]},
		{"round":1,"phase":"collect","entries":{"roots":5},"participants":["a"]},
		{"round":1,"phase":"collect","entries":{},"participants":[]},
		{"round":1,"phase":"collect","entries":{},"participants":"a"},
		{"round":1,"phase":"collect","entries":{},"participants":["a","a"]},
		{"round":1,"phase":"collect","entries":{},"participants":["ghost"]},
		{"round":1,"phase":"collect","entries":{},"participants":[1]},
		{"round":1,"phase":"collect","entries":{},"participants":["a","b","c","d","e","f","g","h","i"]},
		{"round":1,"phase":"served","entries":{"roots":"radish"},"participants":["a"]},
		{"round":1,"phase":"served","entries":full.duplicate(),"participants":["b"]},
	]
	for i in range(shapes.size()):
		var t:=world()
		for extra_player in ["d","e","f","g","h","i"]:t.players[extra_player]=person()
		t.players.a.autumn_feast=true
		t.autumn_feast=shapes[i]
		expect(not Feast.valid(t),"invalid shared %d"%i)
	var eight:=world()
	var names:=[]
	for i in range(8):
		eight.players["q%d"%i]=person()
		names.append("q%d"%i)
	eight.autumn_feast={"round":1,"phase":"collect","entries":{},"participants":names}
	expect(Feast.valid(eight),"eight participants valid")
	eight.autumn_feast.participants.append("a")
	expect(not Feast.valid(eight),"nine participants invalid")
	for junk in [1,0,"true",false,null,1.0,[],{}]:
		var t:=world()
		t.players.a.autumn_feast=junk
		expect(not Feast.valid(t),"invalid personal %s"%str(junk))
	expect(not Feast.valid({}) and not Feast.valid({"players":5}),"no players invalid")

func economy_untouched()->void:
	var s:=world()
	var rest:=s.duplicate(true)
	start(s)
	at_table(s,"b","join:1")
	at_table(s,"a","give:1:radish")
	at_table(s,"b","give:1:lettuce")
	at_table(s,"a","give:1:wheat")
	at_table(s,"b","serve:1")
	var a:Dictionary=s.players.a
	expect(a.coins==120 and a.bag==["seed"] and a.name=="島民","coins, bag list and name untouched")
	expect(a.inventory.radish==1 and a.inventory.wheat==2 and a.inventory.trout_hotpot==2 and a.inventory.turnip==4 and a.inventory.carrot==1 and a.inventory.pumpkin==1,"only the given crops left the bag")
	expect(s.players.b.inventory.lettuce==0 and s.players.b.inventory.radish==2,"b spent only lettuce")
	expect(s.community==rest.community and s.board==rest.board and s.crops==rest.crops,"meal table and world data untouched")
	expect(s.players.c==rest.players.c,"bystander untouched")
	var keys:=a.keys()
	keys.sort()
	expect(keys==["autumn_feast","bag","coins","inventory","name","x","y"],"only autumn_feast added to player")
	var top:=s.keys()
	top.sort()
	var expected:=rest.keys()
	expected.append("autumn_feast")
	expected.sort()
	expect(top==expected,"only the shared key added")
