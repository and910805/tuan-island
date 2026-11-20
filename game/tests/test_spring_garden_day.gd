extends SceneTree
## Regression suite for res://scripts/spring_garden_day.gd (春季花園日): picnic / home /
## target / distance gates, spring boundary, in-progress walks surviving the season,
## replays by completed players in any season, solo and side-by-side clients, strict
## saved-record validation and the guarantee that nothing outside player.spring_garden
## is ever touched (no bag, coins, farm, calendar or other players).
const Garden=preload("res://scripts/spring_garden_day.gd")
const SPRING:=1000.0
const SPRING_LAST:=20159.99
const SUMMER:=20160.0
const WINTER:=3.0*14.0*1440.0+10.0
const NEXT_SPRING:=56.0*1440.0
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("SPRING_GARDEN_DAY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func world(time:float=SPRING,picnic:bool=true)->Dictionary:
	return {"picnic":picnic,"time":time,"board":{"note":1},"calendar":{"day":3},"crops":{"1,1":{"kind":"turnip"}},
		"players":{"a":person(),"b":person()}}

static func person()->Dictionary:
	return {"x":40.5,"y":29.5,"coins":120,"inventory":{"turnip":3},"bag":["seed"],"name":"島民"}

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

func go(state:Dictionary,token:String,cell:Vector2i,extra:String,home:bool=true)->Dictionary:
	stand(state,token,cell)
	return Garden.apply(state,token,cell,extra,home)

func spot(id:String)->Vector2i:
	return Garden.SPOTS[id].cell

func collect_all(state:Dictionary,token:String,order:Array)->void:
	for id:String in order:
		var r:=go(state,token,spot(id),id)
		expect(r.ok==true,"collect "+id)

func _initialize()->void:
	contract()
	gates()
	season_boundary()
	full_walk_any_order()
	rejections_leave_state_identical()
	continue_after_spring()
	replays()
	clients()
	validation()
	economy_untouched()
	finish()

func contract()->void:
	expect(Garden.ACTION=="spring_garden" and Garden.KEY=="spring_garden","action/key")
	expect(Garden.BOARD==Vector2i(40,29) and Garden.FULL_MASK==7,"board/mask")
	expect(Garden.SPOTS.keys()==["bluebell","orange","herb"],"spot order")
	expect(Garden.SPOTS.bluebell.cell==Vector2i(34,28) and Garden.SPOTS.orange.cell==Vector2i(43,33) and Garden.SPOTS.herb.cell==Vector2i(39,35),"spot cells")
	expect(Garden.SPOTS.orange.item=="orange_blossom" and Garden.SPOTS.herb.item=="chime_herb" and Garden.SPOTS.bluebell.item=="bluebell","items")
	expect(Garden.has_stamp(1,"bluebell") and not Garden.has_stamp(1,"orange") and Garden.has_stamp(6,"herb") and Garden.has_stamp(2,"orange"),"has_stamp bits")
	expect(not Garden.has_stamp(7,"nope") and not Garden.has_stamp(0,"herb"),"has_stamp unknown/empty")
	var v:=Garden.view(world(),"a")
	expect(v.keys().size()==6 and v.unlocked==true and v.in_season==true and v.active==false and v.mask==0 and v.completed==false and v.can_start==true,"fresh view")
	expect(Garden.view(world(SPRING,false),"a").can_start==false and Garden.view(world(SPRING,false),"a").unlocked==false,"view locked")
	expect(Garden.view(world(),"ghost").can_start==true and Garden.view({},"x").can_start==false,"view unknown token / empty state")

func gates()->void:
	var s:=world(SPRING,false)
	var before:=s.duplicate(true)
	expect(go(s,"a",Garden.BOARD,"start").ok==false and s==before,"picnic required")
	s=world()
	expect(go(s,"a",Garden.BOARD,"start",false).ok==false and not s.players.a.has("spring_garden"),"home required")
	expect(Garden.apply(s,"ghost",Garden.BOARD,"start",true).ok==false,"unknown player")
	expect(go(s,"a",Vector2i(41,29),"start").ok==false,"wrong board cell")
	expect(go(s,"a",Garden.BOARD,"bogus").ok==false,"unknown extra")
	expect(go(s,"a",Garden.BOARD,"").ok==false,"empty extra")
	# distance: 3.2 from the cell centre
	s.players.a.x=40.5+3.19
	s.players.a.y=29.5
	expect(Garden.apply(s,"a",Garden.BOARD,"start",true).ok==true,"3.19 still reaches")
	s=world()
	s.players.a.x=40.5+3.25
	s.players.a.y=29.5
	expect(Garden.apply(s,"a",Garden.BOARD,"start",true).ok==false and not s.players.a.has("spring_garden"),"3.25 too far")
	s.players.a.x=40.5
	s.players.a.y=29.5+3.21
	expect(Garden.apply(s,"a",Garden.BOARD,"start",true).ok==false,"3.21 too far")
	# claimed cell must match actual position, not just the target
	s=world()
	stand(s,"a",Vector2i(60,60))
	expect(Garden.apply(s,"a",Garden.BOARD,"start",true).ok==false,"claim board from far away")
	s=world()
	go(s,"a",Garden.BOARD,"start")
	stand(s,"a",Vector2i(30,20))
	expect(Garden.apply(s,"a",spot("bluebell"),"bluebell",true).ok==false and s.players.a.spring_garden.mask==0,"spot from far away")
	stand(s,"a",spot("bluebell"))
	expect(Garden.apply(s,"a",spot("orange"),"bluebell",true).ok==false,"spot key at another spot")
	expect(Garden.apply(s,"a",spot("bluebell"),"start",true).ok==false,"start at a spot")
	expect(Garden.apply(s,"a",spot("bluebell"),"finish",true).ok==false,"finish at a spot")
	s.players.a.x=NAN
	expect(Garden.apply(s,"a",spot("bluebell"),"bluebell",true).ok==false,"nan position")
	var r:=go(s,"a",spot("bluebell"),"bluebell")
	expect(r.ok==true and r.message is String and not String(r.message).is_empty(),"message")

func season_boundary()->void:
	for t in [0.0,SPRING,SPRING_LAST,NEXT_SPRING,NEXT_SPRING+100.0]:
		var s:=world(t)
		expect(Garden.view(s,"a").in_season==true and Garden.view(s,"a").can_start==true,"spring %s" % t)
		expect(go(s,"a",Garden.BOARD,"start").ok==true,"start in spring %s" % t)
	for t in [SUMMER,SUMMER+1.0,WINTER,NEXT_SPRING-1.0]:
		var s:=world(t)
		var before:=s.duplicate(true)
		expect(Garden.view(s,"a").in_season==false and Garden.view(s,"a").can_start==false and Garden.view(s,"a").unlocked==true,"off season %s" % t)
		expect(go(s,"a",Garden.BOARD,"start").ok==false,"first start refused %s" % t)
		s.players.a.x=before.players.a.x
		s.players.a.y=before.players.a.y
		expect(s==before or not s.players.a.has("spring_garden"),"off-season leaves no record")
	# the last instant: still spring just before the boundary, summer exactly on it
	expect(Garden.in_season({"time":SPRING_LAST}) and not Garden.in_season({"time":SUMMER}),"boundary exact")

func full_walk_any_order()->void:
	for order in [["bluebell","orange","herb"],["herb","bluebell","orange"],["orange","herb","bluebell"]]:
		var s:=world()
		expect(go(s,"a",Garden.BOARD,"start").ok==true,"start")
		expect(Garden.view(s,"a").active==true and Garden.view(s,"a").can_start==false,"active view")
		expect(go(s,"a",Garden.BOARD,"finish").ok==false,"finish too early")
		collect_all(s,"a",order)
		expect(s.players.a.spring_garden=={"active":true,"mask":7,"completed":false},"full mask")
		expect(go(s,"a",spot("herb"),"herb").ok==false,"duplicate stamp refused")
		expect(go(s,"a",Garden.BOARD,"start").ok==false,"duplicate start refused")
		var r:=go(s,"a",Garden.BOARD,"finish")
		expect(r.ok==true,"finish")
		expect(s.players.a.spring_garden=={"active":false,"mask":0,"completed":true},"completed record")
		expect(go(s,"a",Garden.BOARD,"finish").ok==false,"finish twice refused")
		expect(go(s,"a",spot("orange"),"orange").ok==false,"stamp without walk refused")
		expect(Garden.valid(s.players.a.spring_garden),"saved record valid")
	var s:=world()
	expect(go(s,"a",spot("bluebell"),"bluebell").ok==false and not s.players.a.has("spring_garden"),"stamp before signing up")
	expect(go(s,"a",Garden.BOARD,"finish").ok==false,"finish before signing up")

func rejections_leave_state_identical()->void:
	var s:=world()
	go(s,"a",Garden.BOARD,"start")
	go(s,"a",spot("herb"),"herb")
	var before:=s.duplicate(true)
	go(s,"a",spot("herb"),"herb")
	go(s,"a",Garden.BOARD,"finish")
	go(s,"a",Garden.BOARD,"start")
	go(s,"a",Garden.BOARD,"nonsense")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before,"refusals change nothing")

func continue_after_spring()->void:
	var s:=world(SPRING_LAST)
	go(s,"a",Garden.BOARD,"start")
	go(s,"a",spot("bluebell"),"bluebell")
	s.time=SUMMER+5000.0
	var v:=Garden.view(s,"a")
	expect(v.active==true and v.in_season==false and v.mask==1 and v.completed==false and v.can_start==false,"active walk visible after spring")
	expect(go(s,"a",spot("orange"),"orange").ok==true and go(s,"a",spot("herb"),"herb").ok==true,"collect after spring")
	expect(go(s,"a",Garden.BOARD,"finish").ok==true,"finish after spring")
	expect(s.players.a.spring_garden.completed==true,"completed after spring")

func replays()->void:
	var s:=world()
	go(s,"a",Garden.BOARD,"start")
	collect_all(s,"a",Garden.ORDER)
	go(s,"a",Garden.BOARD,"finish")
	for t in [SPRING,SUMMER,WINTER,NEXT_SPRING-1.0]:
		s.time=t
		var v:=Garden.view(s,"a")
		expect(v.completed==true and v.can_start==true and v.active==false,"replayable view %s" % t)
		expect(go(s,"a",Garden.BOARD,"start").ok==true,"replay start %s" % t)
		expect(s.players.a.spring_garden=={"active":true,"mask":0,"completed":true},"replay record")
		expect(go(s,"a",Garden.BOARD,"finish").ok==false,"replay finish early")
		collect_all(s,"a",["herb","orange","bluebell"])
		expect(go(s,"a",Garden.BOARD,"finish").ok==true,"replay finish %s" % t)
		expect(s.players.a.spring_garden=={"active":false,"mask":0,"completed":true},"still one completed page")
	# an unfinished replay can be continued in any season, and cannot be restarted midway
	s.time=WINTER
	go(s,"a",Garden.BOARD,"start")
	go(s,"a",spot("orange"),"orange")
	expect(go(s,"a",Garden.BOARD,"start").ok==false and s.players.a.spring_garden.mask==2,"no restart midway")

func clients()->void:
	var s:=world()
	# solo: b never participates
	go(s,"a",Garden.BOARD,"start")
	expect(not s.players.b.has("spring_garden") and Garden.view(s,"b").active==false,"solo leaves others untouched")
	# alongside: both walk at once, different orders, independent state
	go(s,"b",Garden.BOARD,"start")
	go(s,"a",spot("bluebell"),"bluebell")
	go(s,"b",spot("herb"),"herb")
	expect(Garden.view(s,"a").mask==1 and Garden.view(s,"b").mask==4,"independent masks")
	collect_all(s,"b",["bluebell","orange"])
	go(s,"b",Garden.BOARD,"finish")
	expect(Garden.view(s,"b").completed==true and Garden.view(s,"a").completed==false and Garden.view(s,"a").mask==1,"b finishing does not affect a")
	s.time=SUMMER
	expect(Garden.view(s,"a").active==true and Garden.view(s,"a").can_start==false,"a keeps walking after spring")
	expect(Garden.view(s,"b").can_start==true,"b replays in summer")
	# JSON round trip keeps the state usable on a "reconnecting" client
	var loaded:Variant=JSON.parse_string(JSON.stringify(s))
	expect(loaded is Dictionary and Garden.valid(loaded.players.a.spring_garden) and Garden.valid(loaded.players.b.spring_garden),"json round trip valid")
	expect(Garden.view(loaded,"a").mask is int,"client mask is an integer after JSON round trip")
	expect(Garden.view(loaded,"a").mask==1 and Garden.view(loaded,"b").completed==true,"views after reload")
	loaded.time=SUMMER
	stand(loaded,"a",spot("orange"))
	expect(Garden.apply(loaded,"a",spot("orange"),"orange",true).ok==true,"continue after reload")

func validation()->void:
	expect(Garden.valid(null),"absent record valid")
	expect(Garden.valid({"active":false,"mask":0,"completed":false}),"default valid")
	expect(Garden.valid({"active":true,"mask":7,"completed":false}),"full pending valid")
	expect(Garden.valid({"active":true,"mask":3.0,"completed":true}),"float whole mask valid")
	expect(Garden.valid({"active":false,"mask":0,"completed":true}),"completed idle valid")
	var bad:Array=[
		{},[],"x",5,true,
		{"active":false,"mask":0},
		{"active":false,"mask":0,"completed":false,"extra":1},
		{"active":false,"mask":0,"completed":false,"bonus":1},
		{"active":"no","mask":0,"completed":false},
		{"active":false,"mask":0,"completed":1},
		{"active":true,"mask":8,"completed":false},
		{"active":true,"mask":-1,"completed":false},
		{"active":true,"mask":1.5,"completed":false},
		{"active":true,"mask":"1","completed":false},
		{"active":true,"mask":NAN,"completed":false},
		{"active":true,"mask":INF,"completed":false},
		{"active":true,"mask":null,"completed":false},
		{"active":false,"mask":1,"completed":false},
		{"active":false,"mask":7,"completed":true},
	]
	for i in range(bad.size()):
		expect(not Garden.valid(bad[i]),"invalid record %d"%i)
	# a corrupt saved record is refused by apply and left alone
	var s:=world()
	s.players.a.spring_garden={"active":false,"mask":5,"completed":false}
	var before:=s.duplicate(true)
	expect(go(s,"a",Garden.BOARD,"start").ok==false,"corrupt record refused")
	s.players.a.x=before.players.a.x
	s.players.a.y=before.players.a.y
	expect(s==before,"corrupt record untouched")
	s.players.a.spring_garden="junk"
	expect(go(s,"a",Garden.BOARD,"start").ok==false,"non-dict record refused")
	expect(Garden.view(s,"a").active==false and Garden.view(s,"a").mask==0,"view falls back to default")

func economy_untouched()->void:
	var s:=world()
	var rest:=s.duplicate(true)
	go(s,"a",Garden.BOARD,"start")
	collect_all(s,"a",Garden.ORDER)
	go(s,"a",Garden.BOARD,"finish")
	s.time=SUMMER
	go(s,"a",Garden.BOARD,"start")
	var a:Dictionary=s.players.a
	expect(a.coins==120 and a.inventory=={"turnip":3} and a.bag==["seed"] and a.name=="島民","player economy fields unchanged")
	expect(s.board==rest.board and s.calendar==rest.calendar and s.crops==rest.crops,"world data unchanged")
	expect(s.players.b==rest.players.b,"other player unchanged")
	var keys:=a.keys()
	keys.sort()
	expect(keys==["bag","coins","inventory","name","spring_garden","x","y"],"only spring_garden added")
	var top:=s.keys()
	top.sort()
	var expected:=rest.keys()
	expected.sort()
	expect(top==expected,"no new world keys")
