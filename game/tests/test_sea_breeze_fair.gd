extends SceneTree
## Regression suite for res://scripts/sea_breeze_fair.gd (夏季海風市集): contract, gates,
## summer boundary, day-rotated guest order, wrong/duplicate/remote serves that change
## nothing, independent players, JSON save round trip, reach and off-season behaviour.
const Fair=preload("res://scripts/sea_breeze_fair.gd")
const Market=preload("res://scripts/market_stall.gd")
const SPRING:=1000.0
const SUMMER:=20160.0
const SUMMER_LAST:=40319.99
const AUTUMN:=40320.0
const WINTER:=3.0*14.0*1440.0+10.0
const DAY:=1440.0
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("SEA_BREEZE_FAIR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func world(time:float=SUMMER,picnic:bool=true)->Dictionary:
	return {"picnic":picnic,"time":time,"board":{"note":1},"calendar":{"day":3},"crops":{"1,1":{"kind":"turnip"}},
		"players":{"a":person(),"b":person()}}

static func person()->Dictionary:
	return {"x":40.5,"y":29.5,"coins":120,"inventory":{"turnip":3,"watermelon_platter":2},"bag":["seed"],"name":"島民"}

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

func go(state:Dictionary,token:String,cell:Vector2i,extra:String,home:bool=true)->Dictionary:
	stand(state,token,cell)
	return Fair.apply(state,token,cell,extra,home)

func counter(state:Dictionary)->Vector2i:
	return Market.active_cell(state)

func serve(state:Dictionary,token:String,dish:String)->Dictionary:
	return go(state,token,counter(state),Fair.SERVE_PREFIX+dish)

func answer(state:Dictionary,token:String,index:int)->String:
	return Fair.order_for(int(state.players[token][Fair.KEY].offset))[index]

func _initialize()->void:
	contract()
	gates()
	season_boundary()
	rotation_and_order()
	full_shift()
	wrong_duplicate_remote_change_nothing()
	counter_follows_market_cell()
	continue_after_summer()
	replays()
	independent_players()
	save_round_trip()
	validation()
	economy_untouched()
	finish()

func contract()->void:
	expect(Fair.KEY=="sea_breeze_fair" and Fair.ACTION=="sea_breeze_fair" and Fair.VIEW_KEY=="own_sea_breeze_fair","keys")
	expect(Fair.BOARD==Vector2i(40,29) and Fair.DURATION_GUESTS==3,"board/guests")
	expect(Fair.DISHES.keys()==["watermelon_platter","baked_potato","strawberry_jam"],"dish insertion order")
	expect(Fair.DISHES.watermelon_platter.title=="夏日西瓜盤" and not Fair.DISHES.watermelon_platter.hint.is_empty(),"watermelon text")
	expect(Fair.DISHES.baked_potato.title=="烤馬鈴薯" and not Fair.DISHES.baked_potato.hint.is_empty(),"potato text")
	expect(Fair.DISHES.strawberry_jam.title=="草莓果醬" and not Fair.DISHES.strawberry_jam.hint.is_empty(),"jam text")
	var names:={}
	var clues:={}
	for dish in Fair.DISHES:
		expect(Fair.GUESTS.has(dish) and not String(Fair.GUESTS[dish].name).is_empty() and not String(Fair.GUESTS[dish].clue).is_empty(),"guest "+dish)
		names[Fair.GUESTS[dish].name]=true
		clues[Fair.GUESTS[dish].clue]=true
		expect(not String(Fair.GUESTS[dish].clue).contains(Fair.DISHES[dish].title),"clue does not name "+dish)
	expect(names.size()==3 and clues.size()==3,"distinct guests and clues")
	var v:=Fair.view(world(),"a")
	expect(v.keys().size()==7 and v.unlocked==true and v.in_season==true and v.active==false and v.completed==false and v.can_start==true,"fresh view")
	expect(v.served==0 and v.served is int and v.phase=="idle" and not v.has("guest"),"fresh idle view")
	expect(not Fair.view(world(SUMMER,false),"a").can_start and not Fair.view(world(SUMMER,false),"a").unlocked,"view locked")
	expect(not Fair.view({},"x").can_start and Fair.view(world(),"ghost").can_start,"view empty state / unknown token")

func gates()->void:
	var s:=world(SUMMER,false)
	var before:=s.duplicate(true)
	expect(go(s,"a",Fair.BOARD,"start").ok==false and s==before,"picnic required")
	s=world()
	expect(go(s,"a",Fair.BOARD,"start",false).ok==false and not s.players.a.has(Fair.KEY),"home required")
	expect(Fair.apply(s,"ghost",Fair.BOARD,"start",true).ok==false,"unknown player")
	expect(go(s,"a",Vector2i(41,29),"start").ok==false,"wrong board cell")
	for bad in ["","bogus","serve:","serve:nope","serve","Serve:baked_potato","start ","serve:baked_potato:1"]:
		expect(go(s,"a",Fair.BOARD,bad).ok==false,"bad extra '%s'"%bad)
	expect(not s.players.a.has(Fair.KEY),"bad extras leave no record")
	s.players.a.x=40.5+3.19
	expect(Fair.apply(s,"a",Fair.BOARD,"start",true).ok==true,"3.19 reaches board")
	s=world()
	s.players.a.x=40.5+3.25
	expect(Fair.apply(s,"a",Fair.BOARD,"start",true).ok==false and not s.players.a.has(Fair.KEY),"3.25 too far")
	s.players.a.x=40.5
	s.players.a.y=29.5+3.21
	expect(Fair.apply(s,"a",Fair.BOARD,"start",true).ok==false,"3.21 too far")
	s.players.a.x=NAN
	expect(Fair.apply(s,"a",Fair.BOARD,"start",true).ok==false,"nan position")
	s=world()
	stand(s,"a",Vector2i(60,60))
	expect(Fair.apply(s,"a",Fair.BOARD,"start",true).ok==false,"claim board from far away")
	var r:=go(s,"a",Fair.BOARD,"start")
	expect(r.ok==true and r.message is String and not String(r.message).is_empty(),"start message")
	expect(go(s,"a",Fair.BOARD,"start").ok==false,"no double start")
	expect(go(s,"a",counter(s),"start").ok==false and go(s,"a",counter(s),"finish").ok==false,"board actions at the counter refused")
	expect(go(s,"a",Fair.BOARD,"serve:"+answer(s,"a",0)).ok==false,"serving at the board refused")
	s=world()
	expect(serve(s,"a","baked_potato").ok==false and not s.players.a.has(Fair.KEY),"serve before signing up")
	expect(go(s,"a",Fair.BOARD,"finish").ok==false and not s.players.a.has(Fair.KEY),"finish before signing up")

func season_boundary()->void:
	for t in [SUMMER,SUMMER+1.0,SUMMER_LAST,SUMMER+56.0*DAY]:
		var s:=world(t)
		expect(Fair.view(s,"a").in_season==true and Fair.view(s,"a").can_start==true,"summer %s"%t)
		expect(go(s,"a",Fair.BOARD,"start").ok==true,"start in summer %s"%t)
	for t in [0.0,SPRING,SUMMER-0.01,AUTUMN,WINTER,56.0*DAY-1.0]:
		var s:=world(t)
		var v:=Fair.view(s,"a")
		expect(v.in_season==false and v.can_start==false and v.unlocked==true,"off season %s"%t)
		expect(go(s,"a",Fair.BOARD,"start").ok==false and not s.players.a.has(Fair.KEY),"first start refused %s"%t)
	expect(Fair.in_season({"time":SUMMER_LAST}) and not Fair.in_season({"time":AUTUMN}) and not Fair.in_season({"time":SUMMER-0.01}),"boundary exact")

func rotation_and_order()->void:
	var firsts:={}
	for d in range(14,20):
		var s:=world(float(d)*DAY+5.0)
		go(s,"a",Fair.BOARD,"start")
		var rec:Dictionary=s.players.a[Fair.KEY]
		expect(rec.offset==d%3 and rec.active==true and rec.served==0,"offset day %d"%d)
		var order:=Fair.order_for(rec.offset)
		expect(order.size()==3 and order[0]==Fair.DISHES.keys()[d%3],"first guest day %d"%d)
		var sorted:=order.duplicate()
		sorted.sort()
		var keys:=Fair.DISHES.keys()
		keys.sort()
		expect(sorted==keys,"order is a permutation day %d"%d)
		firsts[order[0]]=true
		# time passing does not change the stored order
		s.time+=DAY
		expect(Fair.view(s,"a").guest.name==Fair.GUESTS[order[0]].name,"guest fixed after day change %d"%d)
	expect(firsts.size()==3,"all three dishes lead on some day")
	expect(Fair.order_for(0)==["watermelon_platter","baked_potato","strawberry_jam"],"offset 0 order")
	expect(Fair.order_for(1)==["baked_potato","strawberry_jam","watermelon_platter"],"offset 1 order")
	expect(Fair.order_for(2)==["strawberry_jam","watermelon_platter","baked_potato"],"offset 2 order")

func full_shift()->void:
	for d in [14,15,16]:
		var s:=world(float(d)*DAY)
		expect(go(s,"a",Fair.BOARD,"start").ok==true,"start")
		expect(go(s,"a",Fair.BOARD,"finish").ok==false,"finish too early")
		for i in range(3):
			var v:=Fair.view(s,"a")
			var dish:=answer(s,"a",i)
			expect(v.phase=="visit" and v.served==i and v.active==true and v.can_start==false,"visit phase %d"%i)
			expect(v.guest.keys().size()==2 and v.guest.name==Fair.GUESTS[dish].name and v.guest.clue==Fair.GUESTS[dish].clue,"guest %d matches clue"%i)
			expect(not v.has("solution") and not v.has("answer") and not v.has("dish") and not v.guest.has("dish"),"no solution leak")
			var r:=serve(s,"a",dish)
			expect(r.ok==true and not String(r.message).is_empty(),"serve %d"%i)
		var v2:=Fair.view(s,"a")
		expect(v2.phase=="return" and v2.served==3 and not v2.has("guest") and v2.active==true,"return phase")
		expect(serve(s,"a","baked_potato").ok==false and s.players.a[Fair.KEY].served==3,"no fourth serve")
		stand(s,"a",Fair.BOARD)
		var r2:=Fair.apply(s,"a",Fair.BOARD,"finish",true)
		expect(r2.ok==true,"finish")
		expect(s.players.a[Fair.KEY]=={"active":false,"served":0,"offset":0,"completed":true},"completed record")
		var v3:=Fair.view(s,"a")
		expect(v3.phase=="idle" and v3.completed==true and v3.served==0 and not v3.has("guest"),"idle after finish")
		expect(go(s,"a",Fair.BOARD,"finish").ok==false,"finish twice refused")
		expect(Fair.valid(s.players.a[Fair.KEY]),"saved record valid")

func wrong_duplicate_remote_change_nothing()->void:
	var s:=world(SUMMER+DAY)
	go(s,"a",Fair.BOARD,"start")
	var first:=answer(s,"a",0)
	var second:=answer(s,"a",1)
	var third:=answer(s,"a",2)
	stand(s,"a",counter(s))
	var snapshot:=s.duplicate(true)
	# wrong dishes (both of the other two) for guest 0
	expect(serve(s,"a",second).ok==false and serve(s,"a",third).ok==false,"wrong dish refused")
	expect(s==snapshot,"wrong dish changes nothing")
	# remote: right dish from far away, from the board, from a wrong cell
	stand(s,"a",Vector2i(30,20))
	expect(Fair.apply(s,"a",counter(s),Fair.SERVE_PREFIX+first,true).ok==false,"remote serve refused")
	stand(s,"a",counter(s))
	expect(Fair.apply(s,"a",Fair.BOARD,Fair.SERVE_PREFIX+first,true).ok==false,"claimed board cell for serve refused")
	expect(Fair.apply(s,"a",counter(s),Fair.SERVE_PREFIX+first,false).ok==false,"other region refused")
	s.players.a.x=center(counter(s)).x+3.25
	expect(Fair.apply(s,"a",counter(s),Fair.SERVE_PREFIX+first,true).ok==false,"3.25 from counter refused")
	stand(s,"a",counter(s))
	s.players.a.x+=3.19
	expect(Fair.apply(s,"a",counter(s),Fair.SERVE_PREFIX+first,true).ok==true,"3.19 from counter reaches")
	# restore for duplicate check
	s=world(SUMMER+DAY)
	go(s,"a",Fair.BOARD,"start")
	expect(serve(s,"a",first).ok==true,"serve first")
	snapshot=s.duplicate(true)
	expect(serve(s,"a",first).ok==false,"duplicate refused")
	expect(serve(s,"a",third).ok==false,"skipping ahead refused")
	expect(s==snapshot,"duplicate and skipped samples change nothing")
	stand(s,"a",Fair.BOARD)
	snapshot=s.duplicate(true)
	expect(go(s,"a",Fair.BOARD,"finish").ok==false,"finish early refused")
	expect(go(s,"a",Fair.BOARD,"start").ok==false,"restart midway refused")
	expect(s==snapshot,"early finish and restart change nothing")
	expect(s.players.a[Fair.KEY].served==1,"still one served")
	# a refusal never spends items, with a bag that holds every dish
	var t:=world(SUMMER)
	t.players.a.inventory={"watermelon_platter":1,"baked_potato":1,"strawberry_jam":1}
	go(t,"a",Fair.BOARD,"start")
	var inv:Dictionary=t.players.a.inventory.duplicate(true)
	for dish in Fair.DISHES:
		if dish!=answer(t,"a",0):serve(t,"a",dish)
	expect(t.players.a.inventory==inv and t.players.a[Fair.KEY].served==0,"wrong serves leave identical inventory")
	# the same inventory with or without the dish gives the same result (answer is by string only)
	var poor:=world(SUMMER)
	poor.players.a.inventory={}
	go(poor,"a",Fair.BOARD,"start")
	expect(serve(poor,"a",answer(poor,"a",0)).ok==true and poor.players.a.inventory=={},"serving needs no items and spends none")

func counter_follows_market_cell()->void:
	var s:=world()
	expect(counter(s)==Vector2i(36,30),"default counter cell")
	go(s,"a",Fair.BOARD,"start")
	var dish:=answer(s,"a",0)
	# standing at the default cell while the real stall moved elsewhere is refused
	s.objects={"36,30":{"kind":"crate"}}
	expect(counter(s)==Vector2i(36,29),"stall moved to next candidate")
	expect(go(s,"a",Vector2i(36,30),Fair.SERVE_PREFIX+dish).ok==false,"old cell refused")
	expect(go(s,"a",Vector2i(36,29),Fair.SERVE_PREFIX+dish).ok==true,"actual active cell accepted")
	# no free candidate: no counter, nothing to serve
	s.objects={"36,30":1,"36,29":1,"36,31":1,"35,30":1}
	expect(counter(s)==Market.NO_CELL,"no counter cell")
	var before:=s.duplicate(true)
	expect(go(s,"a",Vector2i(36,30),Fair.SERVE_PREFIX+answer(s,"a",1)).ok==false,"serve without a counter refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before,"no counter changes nothing")
	# market stall state is never touched
	expect(not s.players.a.has("market") and not s.has("market"),"no market coupling")

func continue_after_summer()->void:
	var s:=world(SUMMER_LAST)
	go(s,"a",Fair.BOARD,"start")
	serve(s,"a",answer(s,"a",0))
	s.time=AUTUMN+5000.0
	var v:=Fair.view(s,"a")
	expect(v.active==true and v.in_season==false and v.served==1 and v.completed==false and v.can_start==false and v.phase=="visit","active shift visible after summer")
	expect(serve(s,"a",answer(s,"a",1)).ok==true and serve(s,"a",answer(s,"a",2)).ok==true,"serve after summer")
	s.time=WINTER
	expect(go(s,"a",Fair.BOARD,"finish").ok==true and s.players.a[Fair.KEY].completed==true,"finish in winter")
	expect(not Fair.view(world(WINTER),"a").can_start,"fresh winter player still gated")

func replays()->void:
	var s:=world()
	go(s,"a",Fair.BOARD,"start")
	for i in range(3):serve(s,"a",answer(s,"a",i))
	go(s,"a",Fair.BOARD,"finish")
	for t in [SPRING,SUMMER+3.0*DAY,AUTUMN,WINTER]:
		s.time=t
		var v:=Fair.view(s,"a")
		expect(v.completed==true and v.can_start==true and v.active==false and v.phase=="idle","replayable view %s"%t)
		expect(go(s,"a",Fair.BOARD,"start").ok==true,"replay start %s"%t)
		var rec:Dictionary=s.players.a[Fair.KEY]
		expect(rec.active==true and rec.served==0 and rec.completed==true and rec.offset==posmod(int(t/DAY),3),"replay record %s"%t)
		expect(go(s,"a",Fair.BOARD,"finish").ok==false,"replay finish early")
		for i in range(3):expect(serve(s,"a",answer(s,"a",i)).ok==true,"replay serve %d"%i)
		expect(go(s,"a",Fair.BOARD,"finish").ok==true,"replay finish %s"%t)
		expect(s.players.a[Fair.KEY]=={"active":false,"served":0,"offset":0,"completed":true},"still one completed card")

func independent_players()->void:
	var s:=world(SUMMER+DAY)
	go(s,"a",Fair.BOARD,"start")
	expect(not s.players.b.has(Fair.KEY) and Fair.view(s,"b").active==false,"solo leaves b untouched")
	s.time+=DAY
	go(s,"b",Fair.BOARD,"start")
	expect(s.players.a[Fair.KEY].offset!=s.players.b[Fair.KEY].offset,"each player keeps their own offset")
	serve(s,"a",answer(s,"a",0))
	# a's answer is wrong for b if their guests differ
	var a_first:=answer(s,"a",0)
	var b_first:=answer(s,"b",0)
	expect(a_first!=b_first,"different guests")
	expect(serve(s,"b",a_first).ok==false and s.players.b[Fair.KEY].served==0,"b cannot use a's guest")
	expect(Fair.view(s,"a").served==1 and Fair.view(s,"b").served==0,"independent progress")
	for i in range(3):serve(s,"b",answer(s,"b",i))
	go(s,"b",Fair.BOARD,"finish")
	expect(Fair.view(s,"b").completed==true and Fair.view(s,"a").completed==false and Fair.view(s,"a").served==1,"b finishing does not affect a")
	s.time=AUTUMN
	expect(Fair.view(s,"a").active==true and Fair.view(s,"a").can_start==false and Fair.view(s,"b").can_start==true,"season rules per player")

func save_round_trip()->void:
	var s:=world(SUMMER+2.0*DAY)
	go(s,"a",Fair.BOARD,"start")
	serve(s,"a",answer(s,"a",0))
	go(s,"b",Fair.BOARD,"start")
	for i in range(3):serve(s,"b",answer(s,"b",i))
	go(s,"b",Fair.BOARD,"finish")
	var loaded:Variant=JSON.parse_string(JSON.stringify(s))
	expect(loaded is Dictionary and Fair.valid(loaded.players.a[Fair.KEY]) and Fair.valid(loaded.players.b[Fair.KEY]),"json round trip valid")
	expect(loaded.players.a[Fair.KEY].served is float,"json yields floats")
	var v:=Fair.view(loaded,"a")
	expect(v.served is int and v.served==1 and v.phase=="visit" and v.active==true,"view after reload uses integers")
	expect(v.guest.name==Fair.GUESTS[answer(s,"a",1)].name,"same guest after reload")
	expect(Fair.view(loaded,"b").completed==true,"completed card survives reload")
	loaded.time=AUTUMN
	expect(serve(loaded,"a",answer(s,"a",1)).ok==true,"continue after reload")
	expect(loaded.players.a[Fair.KEY].served is int and Fair.valid(loaded.players.a[Fair.KEY]),"saved back as int")
	expect(go(loaded,"b",Fair.BOARD,"start").ok==true,"replay after reload")

func validation()->void:
	expect(Fair.valid(null),"absent record valid")
	expect(Fair.valid({"active":false,"served":0,"offset":0,"completed":false}),"default valid")
	expect(Fair.valid({"active":true,"served":3,"offset":2,"completed":false}),"return phase valid")
	expect(Fair.valid({"active":true,"served":1.0,"offset":2.0,"completed":true}),"whole floats valid")
	expect(Fair.valid({"active":false,"served":0.0,"offset":0.0,"completed":true}),"completed idle valid")
	var bad:Array=[
		{},[],"x",5,true,
		{"active":false,"served":0,"offset":0},
		{"active":false,"served":0,"offset":0,"completed":false,"extra":1},
		{"active":"no","served":0,"offset":0,"completed":false},
		{"active":false,"served":0,"offset":0,"completed":1},
		{"active":true,"served":4,"offset":0,"completed":false},
		{"active":true,"served":-1,"offset":0,"completed":false},
		{"active":true,"served":1.5,"offset":0,"completed":false},
		{"active":true,"served":"1","offset":0,"completed":false},
		{"active":true,"served":NAN,"offset":0,"completed":false},
		{"active":true,"served":INF,"offset":0,"completed":false},
		{"active":true,"served":null,"offset":0,"completed":false},
		{"active":true,"served":0,"offset":3,"completed":false},
		{"active":true,"served":0,"offset":-1,"completed":false},
		{"active":true,"served":0,"offset":0.5,"completed":false},
		{"active":true,"served":0,"offset":"0","completed":false},
		{"active":false,"served":1,"offset":0,"completed":false},
		{"active":false,"served":0,"offset":1,"completed":false},
		{"active":false,"served":3,"offset":2,"completed":true},
	]
	for i in range(bad.size()):
		expect(not Fair.valid(bad[i]),"invalid record %d"%i)
	var s:=world()
	s.players.a[Fair.KEY]={"active":false,"served":2,"offset":0,"completed":false}
	var before:=s.duplicate(true)
	expect(go(s,"a",Fair.BOARD,"start").ok==false,"corrupt record refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before,"corrupt record untouched")
	s.players.a[Fair.KEY]="junk"
	expect(go(s,"a",Fair.BOARD,"start").ok==false,"non-dict record refused")
	expect(Fair.view(s,"a").active==false and Fair.view(s,"a").served==0 and Fair.view(s,"a").phase=="idle","view falls back to default")

func economy_untouched()->void:
	var s:=world()
	var rest:=s.duplicate(true)
	go(s,"a",Fair.BOARD,"start")
	for i in range(3):serve(s,"a",answer(s,"a",i))
	go(s,"a",Fair.BOARD,"finish")
	s.time=AUTUMN
	go(s,"a",Fair.BOARD,"start")
	var a:Dictionary=s.players.a
	expect(a.coins==120 and a.inventory=={"turnip":3,"watermelon_platter":2} and a.bag==["seed"] and a.name=="島民","player economy fields unchanged")
	expect(s.board==rest.board and s.calendar==rest.calendar and s.crops==rest.crops,"world data unchanged")
	expect(s.players.b==rest.players.b,"other player unchanged")
	var keys:=a.keys()
	keys.sort()
	expect(keys==["bag","coins","inventory","name","sea_breeze_fair","x","y"],"only sea_breeze_fair added")
	var top:=s.keys()
	top.sort()
	var expected:=rest.keys()
	expected.sort()
	expect(top==expected,"no new world keys")
