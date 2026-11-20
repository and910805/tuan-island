extends SceneTree
## Regression suite for res://scripts/cooking_relay.gd (廚房接力): picnic / home / reach gates,
## fixed contract, atomic refusals, crew lobby (2-4), solo practice, tray / plate / undo / serve,
## recipe rotation, late watchers, leave / reconnect keeping prep, timeout via step(),
## flags only for actors who acted (practice needs a serve), stale / non-canonical rounds,
## no economy side effects, token-free public view, and strict save validation / JSON round trip.
const Relay=preload("res://scripts/cooking_relay.gd")
const T0:=1000.0
const KEY:="cooking_relay"
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("COOKING_RELAY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func person()->Dictionary:
	return {"x":40.5,"y":33.5,"coins":120,"name":"島民","bag":["seed"],
		"inventory":{"radish":2,"turnip":4,"trout_hotpot":2}}

static func world(time:float=T0,picnic:bool=true,tokens:Array=["alice","bob","carol","dave","erin","frank"])->Dictionary:
	var players:={}
	for t in tokens:players[t]=person()
	return {"picnic":picnic,"time":time,"community":{"table":"39,30"},"crops":{"1,1":{"kind":"turnip"}},"players":players}

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	if not state.players.has(token):return
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

func act(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool=true)->Dictionary:
	stand(state,token,at)
	return Relay.apply(state,token,at,extra,home)

func rid(state:Dictionary)->int:
	return int(state[KEY].round)

func sign_act(state:Dictionary,token:String,extra:String)->Dictionary:
	return act(state,token,Relay.SIGN,extra)

func cmd(state:Dictionary,token:String,kind:String,extra_tail:String="",round_id:int=-1)->Dictionary:
	var r:=round_id if round_id>=0 else rid(state)
	match kind:
		"prep":return act(state,token,Relay.STATIONS.prep,"prep:%d:%s"%[r,extra_tail])
		"plate","undo":return act(state,token,Relay.STATIONS.assembly,"%s:%d"%[kind,r])
		"serve":return act(state,token,Relay.STATIONS.serve,"serve:%d"%r)
	return act(state,token,Relay.SIGN,"%s:%d"%[kind,r])

func refused(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool,label:String)->void:
	stand(state,token,at)
	var before:=state.duplicate(true)
	var result:=Relay.apply(state,token,at,extra,home)
	expect(result.ok==false and result.has("message"),label+" refused")
	expect(state==before,label+" leaves state unchanged")

func make_dish(state:Dictionary,token:String)->void:
	var dish:String=Relay.public_view(state).dish
	for item in Relay.RECIPES[dish].items:
		expect(cmd(state,token,"prep",item).ok,"prep "+item)
	expect(cmd(state,token,"plate").ok,"plate "+dish)

func crew_run(state:Dictionary,tokens:Array=["alice","bob"])->void:
	expect(sign_act(state,tokens[0],"crew").ok,"crew lobby")
	for i in range(1,tokens.size()):expect(cmd(state,tokens[i],"join").ok,"join "+tokens[i])
	expect(cmd(state,tokens[0],"begin").ok,"begin")

func _initialize()->void:
	contract()
	gates()
	crew_flow()
	rotation()
	practice()
	lobby_rules()
	online_lobby()
	leave_and_watchers()
	timing()
	economy_and_privacy()
	save_validation()
	finish()

func contract()->void:
	expect(Relay.KEY=="cooking_relay" and Relay.ACTION=="cooking_relay" and Relay.VIEW_KEY=="own_cooking_relay","keys")
	expect(Relay.SIGN==Vector2i(40,33),"sign")
	expect(Relay.STATIONS=={"prep":Vector2i(38,35),"assembly":Vector2i(41,37),"serve":Vector2i(43,38)},"stations")
	expect(Relay.AREA==Rect2i(36,32,11,8),"area")
	expect(Relay.AREA.has_point(Relay.SIGN),"sign inside area")
	for s in Relay.STATIONS.values():expect(Relay.AREA.has_point(s),"station inside area")
	expect(Relay.ITEMS.keys()==["root","green","fruit","grain"],"item ids")
	expect(Relay.RECIPES.keys()==["soup","salad","toast"],"recipe ids")
	for id in Relay.RECIPES:
		var r:Dictionary=Relay.RECIPES[id]
		expect(r.title is String and r.items is Array and r.items.size()==2,"recipe shape "+id)
		for item in r.items:expect(Relay.ITEMS.has(item),"recipe item known")
	expect(Relay.REACH==3.2 and Relay.DURATION==240.0,"reach and duration")
	var idle:=Relay.public_view(world())
	expect(idle.keys().size()==10 and idle.phase=="idle" and idle.mode=="" and idle.round==0,"idle public view")
	expect(Relay.valid(world()),"fresh world valid")
	var v:=Relay.view(world(),"alice")
	expect(v=={"unlocked":true,"joined":false,"practice":false,"crew":false,"can_start":true,"can_begin":false},"idle own view")

func gates()->void:
	var s:=world(T0,false)
	refused(s,"alice",Relay.SIGN,"crew",true,"locked crew")
	refused(s,"alice",Relay.SIGN,"practice",true,"locked practice")
	expect(not s.has(KEY) and Relay.view(s,"alice").unlocked==false and Relay.view(s,"alice").can_start==false,"locked view")
	s=world()
	refused(s,"alice",Relay.SIGN,"crew",false,"away from home")
	refused(s,"zed",Relay.SIGN,"crew",true,"unknown player")
	refused(s,"alice",Relay.SIGN+Vector2i(1,0),"crew",true,"wrong sign cell")
	for bad in ["","start","crew:1","practice:1","join","join:","join:0","join:01","join:+1","join: 1","join:1.0","join:-1","join:1:2",
			"begin","prep:1","prep:1:meat","prep:1:root:x","PREP:1:root","serve","undo:x","plate:99999999999","leave"]:
		refused(s,"alice",Relay.SIGN,bad,true,"bad extra '%s'"%bad)
	s.players.alice.x=60.0
	var before:=s.duplicate(true)
	expect(Relay.apply(s,"alice",Relay.SIGN,"crew",true).ok==false and s==before,"too far")
	s.players.alice.x=Relay.SIGN.x+0.5+3.3
	s.players.alice.y=Relay.SIGN.y+0.5
	before=s.duplicate(true)
	expect(Relay.apply(s,"alice",Relay.SIGN,"crew",true).ok==false and s==before,"just beyond reach")
	s.players.alice.x=Relay.SIGN.x+0.5+3.1
	expect(Relay.apply(s,"alice",Relay.SIGN,"crew",true).ok==true,"within reach")
	s=world()
	s.players.alice.x="x"
	before=s.duplicate(true)
	expect(Relay.apply(s,"alice",Relay.SIGN,"crew",true).ok==false and s==before,"non numeric position")
	s=world()
	s.players.alice[KEY]={"bogus":true}
	refused(s,"alice",Relay.SIGN,"crew",true,"bad personal record")
	s=world()
	s[KEY]={"round":1}
	refused(s,"alice",Relay.SIGN,"crew",true,"bad shared record")

func crew_flow()->void:
	var s:=world()
	expect(sign_act(s,"alice","crew").ok,"crew creates lobby")
	var pub:=Relay.public_view(s)
	expect(pub.phase=="lobby" and pub.mode=="crew" and pub.round==1 and pub.guests==1 and pub.remaining==0,"lobby view")
	expect(Relay.view(s,"alice").joined and not Relay.view(s,"alice").can_start and not Relay.view(s,"bob").joined,"lobby own view")
	refused(s,"bob",Relay.SIGN,"crew",true,"crew during lobby")
	refused(s,"bob",Relay.SIGN,"practice",true,"practice during lobby")
	refused(s,"alice",Relay.SIGN,"begin:1",true,"begin alone")
	refused(s,"alice",Relay.SIGN,"join:1",true,"join twice")
	refused(s,"bob",Relay.SIGN,"join:2",true,"join stale round")
	refused(s,"bob",Relay.SIGN,"begin:1",true,"begin by non member")
	refused(s,"bob",Relay.STATIONS.prep,"prep:1:root",true,"prep during lobby")
	expect(cmd(s,"bob","join").ok,"bob joins")
	expect(cmd(s,"carol","join").ok,"carol joins")
	expect(cmd(s,"dave","join").ok,"dave joins")
	refused(s,"erin",Relay.SIGN,"join:1",true,"fifth player refused")
	expect(Relay.public_view(s).guests==4,"four guests")
	refused(s,"bob",Relay.SIGN,"begin:2",true,"begin stale")
	expect(cmd(s,"bob","begin").ok,"member begins")
	var pv:=Relay.public_view(s)
	expect(pv.phase=="run" and pv.remaining==240 and pv.dish=="soup" and pv.plated==false and pv.tray==[],"run view")
	refused(s,"erin",Relay.SIGN,"join:1",true,"join during run")
	refused(s,"alice",Relay.SIGN,"begin:1",true,"begin twice")
	refused(s,"alice",Relay.SIGN,"crew",true,"crew during run")
	# late watcher cannot work
	refused(s,"erin",Relay.STATIONS.prep,"prep:1:root",true,"watcher prep")
	refused(s,"erin",Relay.STATIONS.assembly,"undo:1",true,"watcher undo")
	# stations and stale
	refused(s,"alice",Relay.SIGN,"prep:1:root",true,"prep at wrong station")
	refused(s,"alice",Relay.STATIONS.prep,"prep:2:root",true,"prep stale")
	refused(s,"alice",Relay.STATIONS.prep,"prep:1:root",false,"prep away from home")
	refused(s,"alice",Relay.STATIONS.assembly,"plate:1",true,"plate empty tray")
	refused(s,"alice",Relay.STATIONS.assembly,"undo:1",true,"undo empty tray")
	refused(s,"alice",Relay.STATIONS.serve,"serve:1",true,"serve unplated")
	# wrong choices allowed, max two
	expect(cmd(s,"alice","prep","grain").ok and cmd(s,"bob","prep","grain").ok,"two wrong items")
	expect(Relay.public_view(s).tray==["grain","grain"],"tray holds wrong items")
	refused(s,"carol",Relay.STATIONS.prep,"prep:1:root",true,"tray full")
	refused(s,"carol",Relay.STATIONS.assembly,"plate:1",true,"wrong plate")
	expect(cmd(s,"carol","undo").ok and Relay.public_view(s).tray==[],"undo empties tray")
	# unordered match, tray retained, plated blocks prep
	expect(cmd(s,"alice","prep","green").ok and cmd(s,"alice","prep","root").ok,"soup items reversed")
	expect(cmd(s,"bob","plate").ok,"plate matches unordered")
	pv=Relay.public_view(s)
	expect(pv.plated and pv.tray==["green","root"] and pv.plates==0,"plated keeps tray")
	refused(s,"alice",Relay.STATIONS.prep,"prep:1:fruit",true,"prep while plated")
	refused(s,"alice",Relay.STATIONS.assembly,"plate:1",true,"plate twice")
	expect(cmd(s,"carol","undo").ok and not Relay.public_view(s).plated and Relay.public_view(s).tray==[],"undo unplates")
	make_dish(s,"dave")
	expect(cmd(s,"alice","serve").ok,"serve")
	pv=Relay.public_view(s)
	expect(pv.plates==1 and pv.score==3 and pv.dish=="salad" and not pv.plated and pv.tray==[],"served")
	expect(not s.players.alice.has(KEY),"no flag before finish")
	# finish: everyone who acted gets crew flag, watcher none
	s.time=T0+240.0
	expect(Relay.step(s),"step settles")
	expect(not Relay.step(s),"step is idempotent")
	expect(Relay.public_view(s).phase=="results" and Relay.public_view(s).remaining==0 and Relay.public_view(s).plates==1,"results")
	for t in ["alice","bob","carol","dave"]:expect(s.players[t].get(KEY)=={"crew":true},"crew flag "+t)
	expect(not s.players.erin.has(KEY),"watcher no flag")
	expect(Relay.view(s,"alice").crew and not Relay.view(s,"alice").practice and Relay.view(s,"alice").can_start,"own view after")
	expect(Relay.valid(s),"results valid")
	refused(s,"alice",Relay.STATIONS.prep,"prep:1:root",true,"prep after results")
	# replay
	expect(sign_act(s,"bob","crew").ok and rid(s)==2,"replay round 2")
	expect(s.players.alice.get(KEY)=={"crew":true},"flag kept across rounds")

func rotation()->void:
	var s:=world()
	crew_run(s)
	var seen:=[]
	for i in range(4):
		seen.append(Relay.public_view(s).dish)
		make_dish(s,"alice" if i%2==0 else "bob")
		expect(cmd(s,"bob","serve").ok,"serve %d"%i)
	expect(seen==["soup","salad","toast","soup"],"rotation order")
	expect(Relay.public_view(s).plates==4 and Relay.public_view(s).score==12,"four plates")
	s.time=T0+240.0
	Relay.step(s)
	expect(sign_act(s,"alice","crew").ok and cmd(s,"bob","join").ok and cmd(s,"alice","begin").ok,"round 2")
	expect(Relay.public_view(s).dish=="salad","round 2 starts at salad")
	for dish in ["toast","soup","salad"]:
		var cur:String=Relay.public_view(s).dish
		for item in Relay.RECIPES[cur].items:cmd(s,"alice","prep",item)
		cmd(s,"alice","plate")
		cmd(s,"alice","serve")
		expect(Relay.public_view(s).dish==dish,"round 2 next "+dish)
	# each recipe accepts only itself
	s=world()
	crew_run(s)
	cmd(s,"alice","prep","green")
	cmd(s,"alice","prep","fruit")
	refused(s,"alice",Relay.STATIONS.assembly,"plate:1",true,"salad when soup requested")

func practice()->void:
	var s:=world()
	expect(sign_act(s,"dave","practice").ok,"practice starts straight away")
	var pv:=Relay.public_view(s)
	expect(pv.phase=="run" and pv.mode=="practice" and pv.guests==1 and pv.remaining==240,"practice view")
	refused(s,"erin",Relay.SIGN,"join:1",true,"no join in practice")
	refused(s,"erin",Relay.SIGN,"begin:1",true,"no begin in practice")
	refused(s,"erin",Relay.STATIONS.prep,"prep:1:root",true,"others cannot work practice")
	make_dish(s,"dave")
	expect(cmd(s,"dave","serve").ok,"practice serve")
	s.time=T0+240.0
	expect(Relay.step(s),"practice ends")
	expect(s.players.dave.get(KEY)=={"practice":true} and Relay.view(s,"dave").practice,"practice memento")
	expect(Relay.valid(s),"practice results valid")
	# practice without a serve earns nothing; acted-only crew flag does not apply to practice
	var s2:=world()
	expect(sign_act(s2,"dave","practice").ok,"practice 2")
	cmd(s2,"dave","prep","root")
	s2.time=T0+240.0
	Relay.step(s2)
	expect(not s2.players.dave.has(KEY),"no serve no practice reward")
	# repeat practice keeps the memento without duplication and can add nothing else
	s.time=T0+300.0
	expect(sign_act(s,"dave","practice").ok and rid(s)==2,"replay practice")
	make_dish(s,"dave")
	cmd(s,"dave","serve")
	s.time=T0+600.0
	Relay.step(s)
	expect(s.players.dave.get(KEY)=={"practice":true},"memento not duplicated")
	# an explicit leave keeps the solo run going with the prep kept
	var s3:=world()
	sign_act(s3,"alice","practice")
	cmd(s3,"alice","prep","fruit")
	expect(cmd(s3,"alice","leave").ok,"practice leave")
	expect(Relay.public_view(s3).tray==["fruit"] and Relay.public_view(s3).guests==0,"leave keeps tray")
	refused(s3,"alice",Relay.SIGN,"practice",true,"no restart while running")

func lobby_rules()->void:
	var s:=world()
	sign_act(s,"alice","crew")
	cmd(s,"bob","join")
	expect(cmd(s,"bob","leave").ok and Relay.public_view(s).guests==1,"lobby leave removes")
	refused(s,"bob",Relay.SIGN,"leave:1",true,"leave when not in lobby")
	refused(s,"alice",Relay.SIGN,"leave:2",true,"leave stale")
	expect(cmd(s,"alice","leave").ok,"last leaves")
	var pv:=Relay.public_view(s)
	expect(pv.phase=="results" and pv.mode=="" and pv.dish=="" and pv.guests==0 and pv.round==1,"reset to results")
	expect(Relay.view(s,"alice").can_start and not Relay.view(s,"alice").joined,"replay allowed")
	expect(Relay.valid(s),"reset record valid")
	expect(sign_act(s,"bob","crew").ok and rid(s)==2,"new lobby round 2")
	# leave works from anywhere / any region
	expect(act(s,"bob",Vector2i(0,0),"leave:2",false).ok,"leave anywhere")
	s.players.alice.x=3.0
	s.players.alice.y=3.0

func online_lobby()->void:
	var s:=world()
	sign_act(s,"alice","crew")
	cmd(s,"bob","join")
	var alone:={"alice":true}
	var both:={"alice":true,"bob":true}
	expect(Relay.public_view(s,alone).guests==1,"Lobby shows the number currently online")
	expect(not Relay.view(s,"alice",alone).can_begin and Relay.view(s,"alice",both).can_begin,"An offline cook does not meet the minimum")
	var before:=s.duplicate(true)
	expect(not Relay.apply(s,"alice",Relay.SIGN,"begin:1",true,alone).ok and s==before,"Refused offline begin leaves the lobby unchanged")
	expect(Relay.apply(s,"alice",Relay.SIGN,"begin:1",true,both).ok,"Crew can begin after reconnecting")

func leave_and_watchers()->void:
	var s:=world()
	crew_run(s,["alice","bob","carol"])
	cmd(s,"alice","prep","root")
	cmd(s,"bob","prep","green")
	expect(act(s,"bob",Vector2i(0,0),"leave:1",false).ok,"leave from afar in run")
	var pv:=Relay.public_view(s)
	expect(pv.tray==["root","green"] and pv.guests==2 and pv.phase=="run","leave keeps prep")
	refused(s,"bob",Relay.STATIONS.assembly,"plate:1",true,"leaver cannot work")
	refused(s,"bob",Relay.SIGN,"join:1",true,"leaver cannot rejoin")
	refused(s,"bob",Relay.SIGN,"leave:1",true,"leave twice")
	var snapshot:=s.duplicate(true)
	# disconnect = nothing changes; carol continues from the kept tray
	expect(s==snapshot and cmd(s,"carol","plate").ok,"prepared work survives for the crew")
	expect(cmd(s,"carol","serve").ok and Relay.public_view(s).plates==1,"carol serves bob's prep")
	s.time=T0+240.0
	Relay.step(s)
	expect(s.players.bob.get(KEY)=={"crew":true},"leaver who prepped keeps credit")
	expect(s.players.carol.get(KEY)=={"crew":true},"carol credit")
	# member who only watched in a crew run gets nothing
	var s2:=world()
	crew_run(s2,["alice","bob"])
	cmd(s2,"alice","prep","root")
	s2.time=T0+240.0
	Relay.step(s2)
	expect(s2.players.alice.get(KEY)=={"crew":true} and not s2.players.bob.has(KEY),"idle member no flag")

func timing()->void:
	var s:=world()
	crew_run(s)
	s.time=T0+239.5
	expect(Relay.public_view(s).remaining==1,"remaining rounds up")
	expect(cmd(s,"alice","prep","root").ok,"works before the end")
	expect(not Relay.step(s),"step before end does nothing")
	s.time=T0+240.0
	refused(s,"alice",Relay.STATIONS.prep,"prep:1:green",true,"prep at the deadline")
	refused(s,"carol",Relay.SIGN,"crew",true,"crew while expired run")
	expect(Relay.public_view(s).remaining==0,"remaining zero")
	expect(Relay.step(s) and Relay.public_view(s).phase=="results","settles at 240")
	# serve exactly at the deadline must not count
	var s2:=world()
	crew_run(s2)
	make_dish(s2,"alice")
	s2.time=T0+240.0
	refused(s2,"alice",Relay.STATIONS.serve,"serve:1",true,"serve at the deadline")
	# step without a record / after results
	expect(not Relay.step(world()),"no record")

func economy_and_privacy()->void:
	var s:=world()
	var base:=s.duplicate(true)
	crew_run(s)
	make_dish(s,"alice")
	cmd(s,"bob","serve")
	s.time=T0+240.0
	Relay.step(s)
	for t in s.players:
		for field in ["coins","name","bag","inventory"]:
			expect(s.players[t][field]==base.players[t][field],"%s %s untouched"%[t,field])
	expect(s.crops==base.crops and s.community==base.community,"world untouched")
	var keys:=s.keys()
	keys.sort()
	expect(keys==["community","cooking_relay","crops","picnic","players","time"],"only own record added")
	var text:=JSON.stringify(Relay.public_view(s))
	for t in ["alice","bob","carol"]:expect(not text.contains(t),"public view has no token "+t)
	expect(Relay.public_view(s).keys().size()==10,"public view fields")
	expect(not Relay.view(s,"alice").has("members") and Relay.view(s,"alice").keys().size()==6,"own view fields")
	# views do not mutate
	var before:=s.duplicate(true)
	Relay.public_view(s)
	Relay.view(s,"alice")
	expect(s==before,"views are read only")

func save_validation()->void:
	var s:=world()
	crew_run(s)
	make_dish(s,"alice")
	var back:Variant=JSON.parse_string(JSON.stringify(s))
	expect(back is Dictionary and Relay.valid(back),"JSON round trip valid")
	expect(back[KEY].round is int and back[KEY].round==1,"round normalized to int")
	var bad:=func(label:String,mutate:Callable)->void:
		var copy:Dictionary=s.duplicate(true)
		mutate.call(copy)
		expect(not Relay.valid(copy),"invalid: "+label)
	bad.call("no picnic",func(c):c.picnic=false)
	bad.call("extra field",func(c):c[KEY].extra=1)
	bad.call("missing field",func(c):c[KEY].erase("tray"))
	bad.call("round zero",func(c):c[KEY].round=0)
	bad.call("round fraction",func(c):c[KEY].round=1.5)
	bad.call("phase",func(c):c[KEY].phase="done")
	bad.call("mode",func(c):c[KEY].mode="solo")
	bad.call("score",func(c):c[KEY].score=5)
	bad.call("plates negative",func(c):c[KEY].plates=-1)
	bad.call("tray three",func(c):c[KEY].tray=["root","root","root"])
	bad.call("tray unknown",func(c):c[KEY].tray=["meat"])
	bad.call("plated mismatch",func(c):c[KEY].tray=["fruit","grain"])
	bad.call("future start",func(c):c[KEY].started=T0+50.0)
	bad.call("unknown member",func(c):c[KEY].members["ghost"]={"joined":true,"acted":false,"served":false})
	bad.call("served not acted",func(c):c[KEY].members.bob={"joined":true,"acted":false,"served":true})
	bad.call("member shape",func(c):c[KEY].members.bob={"joined":true})
	bad.call("crew of one",func(c):c[KEY].members.erase("bob"))
	bad.call("plates without serve",func(c):c[KEY].plates=1;c[KEY].score=3)
	bad.call("personal flag",func(c):c.players.alice[KEY]={"crew":false})
	bad.call("personal empty",func(c):c.players.alice[KEY]={})
	bad.call("personal unknown",func(c):c.players.alice[KEY]={"win":true})
	bad.call("personal not dict",func(c):c.players.alice[KEY]=true)
	bad.call("results without flag",func(c):c[KEY].phase="results")
	# a record without a shared part is fine; flags alone are fine
	var lone:=world()
	lone.players.alice[KEY]={"practice":true,"crew":true}
	expect(Relay.valid(lone),"flags only valid")
	var many:=world()
	crew_run(many,["alice","bob","carol","dave"])
	many[KEY].members["erin"]={"joined":true,"acted":false,"served":false}
	expect(not Relay.valid(many),"more than 4 members invalid")
	# corrupt shared record makes actions fail without mutating
	var broken:=world()
	broken[KEY]={"round":1,"phase":"run"}
	refused(broken,"alice",Relay.SIGN,"crew",true,"corrupt record")
	expect(Relay.public_view(broken).phase=="idle","corrupt record reads as idle")
