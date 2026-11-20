extends SceneTree
## Regression suite for res://scripts/lost_chicks.gd (迷路小雞): picnic / home / reach / online gates,
## fixed contract, atomic refusals, solo vs crew by online home count (fixed afterwards), automatic lure
## (radius, one chick per player), visible 4-direction hops on a bounded schedule with a can_step callback,
## pen scoring (+2 each), early completion, timeout returning everyone without points, mid-round join with a
## loan bucket, leave / disconnect / region loss dropping lures, explicit rejoin, 8-player cap, round limit,
## no economy side effects, token-free views, and strict save validation / JSON round trip.
const Lost=preload("res://scripts/lost_chicks.gd")
const T0:=1000.0
const KEY:="lost_chicks"
const NAMES:=["alice","bob","carol","dave","erin","frank","gina","hugo","ivy"]
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("LOST_CHICKS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func person()->Dictionary:
	return {"x":49.5,"y":40.5,"coins":120,"name":"島民","bag":["seed"],
		"inventory":{"radish":2,"turnip":4,"trout_hotpot":2}}

static func world(time:float=T0,picnic:bool=true,tokens:Array=NAMES)->Dictionary:
	var players:={}
	for t in tokens:players[t]=person()
	return {"picnic":picnic,"time":time,"community":{"table":"39,30"},"crops":{"1,1":{"kind":"turnip"}},"players":players}

static func online(tokens:Array)->Dictionary:
	var result:={}
	for t in tokens:result[t]=true
	return result

static func stand(state:Dictionary,token:String,cell:Vector2i)->void:
	if not state.players.has(token):return
	var c:=center(cell)
	state.players[token].x=c.x
	state.players[token].y=c.y

static func place(state:Dictionary,token:String,x:float,y:float)->void:
	state.players[token].x=x
	state.players[token].y=y

func yes(_token:String,_from:Vector2i,_to:Vector2i)->bool:
	return true

func no(_token:String,_from:Vector2i,_to:Vector2i)->bool:
	return false

func act(state:Dictionary,token:String,extra:String,active:Dictionary,home:bool=true,at:Vector2i=Lost.SIGN)->Dictionary:
	stand(state,token,at)
	return Lost.apply(state,token,at,extra,home,active)

func rid(state:Dictionary)->int:
	return int(state[KEY].round)

func cmd(state:Dictionary,token:String,kind:String,active:Dictionary)->Dictionary:
	return act(state,token,"%s:%d"%[kind,rid(state)],active)

func refused(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool,active:Dictionary,label:String)->void:
	stand(state,token,at)
	var before:=state.duplicate(true)
	var result:=Lost.apply(state,token,at,extra,home,active)
	expect(result.ok==false and result.has("text") and not result.has("message"),label+" refused")
	expect(state==before,label+" leaves state unchanged")

func tick(state:Dictionary,active:Dictionary,dt:float,can:Variant=null)->bool:
	state.time=float(state.time)+dt
	var fn:Callable=yes
	if can is Callable:fn=can
	return Lost.step(state,active,fn)

func chick_cells(state:Dictionary)->Array:
	var cells:=[]
	for c in state[KEY].chicks:cells.append(Vector2i(c.x,c.y))
	return cells

func statuses(state:Dictionary)->Array:
	var out:=[]
	for c in state[KEY].chicks:out.append(c.status)
	return out

func followers(state:Dictionary)->int:
	var n:=0
	for c in state[KEY].chicks:
		if c.status=="follow":n+=1
	return n

## Walk a player to the pen with 0.5s steps until their chick is home (or give up).
func deliver(state:Dictionary,token:String,active:Dictionary)->void:
	stand(state,token,Lost.PEN)
	for i in range(40):
		tick(state,active,0.5)
		if state[KEY].phase=="results":return
		var mine:=false
		for c in state[KEY].chicks:
			if c.status=="follow" and c.by==token:mine=true
		if not mine:return

func _initialize()->void:
	contract()
	gates()
	spawn_safety()
	solo_flow()
	crew_mode_and_lure()
	hopping()
	timeout()
	late_join_and_cap()
	leave_and_disconnect()
	economy_and_privacy()
	save_validation()
	finish()

func contract()->void:
	expect(Lost.KEY=="lost_chicks" and Lost.ACTION=="lost_chicks" and Lost.VIEW_KEY=="own_lost_chicks","keys")
	expect(Lost.SIGN==Vector2i(49,40) and Lost.PEN==Vector2i(51,40),"sign and pen")
	expect(Lost.AREA==Rect2i(47,37,10,9),"area")
	expect(Lost.SOLO_SPOTS==[Vector2i(49,42),Vector2i(52,42)],"solo spots")
	expect(Lost.CREW_SPOTS==[Vector2i(48,43),Vector2i(50,44),Vector2i(53,43),Vector2i(54,39),Vector2i(54,42),Vector2i(52,38)],"crew spots")
	expect(Lost.AREA.has_point(Lost.SIGN) and Lost.AREA.has_point(Lost.PEN),"sign and pen inside area")
	for spot in Lost.SOLO_SPOTS+Lost.CREW_SPOTS:expect(Lost.AREA.has_point(spot),"spot inside area")
	expect(Lost.DURATION==180.0 and Lost.POINTS==2 and Lost.MAX_PLAYERS==8,"limits")
	expect(Lost.STEP_MIN>=0.3 and Lost.STEP_MIN+Lost.STEP_SPAN<=0.45+0.0001,"hop schedule bounds")
	var idle:=Lost.public_view(world())
	expect(idle=={"phase":"idle","round":0,"mode":"","chicks":[],"score":0,"remaining":0,"returned":0,"total":0},"idle public view")
	expect(Lost.valid(world()),"fresh world valid")
	expect(Lost.view(world(),"alice")=={"unlocked":true,"joined":false},"idle own view")
	expect(not Lost.step(world(),online(["alice"]),yes),"no record: step does nothing")

func gates()->void:
	var act_all:=online(NAMES)
	var s:=world(T0,false)
	refused(s,"alice",Lost.SIGN,"start",true,act_all,"locked")
	expect(not s.has(KEY) and Lost.view(s,"alice")=={"unlocked":false,"joined":false},"locked view")
	s=world()
	refused(s,"alice",Lost.SIGN,"start",false,act_all,"away from home")
	refused(s,"zed",Lost.SIGN,"start",true,act_all,"unknown player")
	refused(s,"alice",Lost.SIGN+Vector2i(1,0),"start",true,act_all,"wrong sign cell")
	refused(s,"alice",Lost.SIGN,"start",true,{},"not an active token")
	refused(s,"alice",Lost.SIGN,"start",true,online(["bob"]),"another token active only")
	for bad in ["","begin","start:1","join","join:","join:0","join:01","join:+1","join: 1","join:1.0","join:-1","join:1:2",
			"leave","leave:x","LEAVE:1","START","join:99999999999","leave:1000000001"]:
		refused(s,"alice",Lost.SIGN,bad,true,act_all,"bad extra '%s'"%bad)
	place(s,"alice",60.0,60.0)
	var before:=s.duplicate(true)
	expect(not Lost.apply(s,"alice",Lost.SIGN,"start",true,act_all).ok and s==before,"too far")
	place(s,"alice",Lost.SIGN.x+0.5+3.3,Lost.SIGN.y+0.5)
	before=s.duplicate(true)
	expect(not Lost.apply(s,"alice",Lost.SIGN,"start",true,act_all).ok and s==before,"just beyond reach")
	place(s,"alice",Lost.SIGN.x+0.5+3.1,Lost.SIGN.y+0.5)
	expect(Lost.apply(s,"alice",Lost.SIGN,"start",true,act_all).ok,"within reach")
	s=world()
	s.players.alice.x="x"
	before=s.duplicate(true)
	expect(not Lost.apply(s,"alice",Lost.SIGN,"start",true,act_all).ok and s==before,"non numeric position")
	s=world()
	s[KEY]={"round":1}
	refused(s,"alice",Lost.SIGN,"start",true,act_all,"bad shared record")
	expect(Lost.public_view(s).phase=="idle" and Lost.view(s,"alice").unlocked==false,"corrupt record reads idle / locked")
	# stale and non-member operations
	s=world()
	expect(act(s,"alice","start",online(["alice"])).ok,"start")
	refused(s,"alice",Lost.SIGN,"join:2",true,act_all,"stale join")
	refused(s,"bob",Lost.SIGN,"leave:1",true,act_all,"leave when not a member")
	refused(s,"alice",Lost.SIGN,"start",true,act_all,"start during run")
	refused(s,"alice",Lost.SIGN,"join:1",true,act_all,"join twice")
	refused(s,"bob",Lost.SIGN,"join:1",false,act_all,"join away from home")
	refused(s,"bob",Lost.SIGN,"join:1",true,online(["alice"]),"join while not active")
	refused(s,"bob",Vector2i(0,0),"join:1",true,act_all,"join away from sign")

func solo_flow()->void:
	var s:=world()
	var a:=online(["alice"])
	var r:=act(s,"alice","start",a)
	expect(r.ok and r.has("text") and rid(s)==1,"solo start")
	var pv:=Lost.public_view(s)
	expect(pv.phase=="run" and pv.mode=="solo" and pv.round==1 and pv.total==2 and pv.returned==0 and pv.score==0 and pv.remaining==180,"solo view")
	expect(chick_cells(s)==Lost.SOLO_SPOTS and statuses(s)==["lost","lost"],"two chicks at solo spots")
	expect(s[KEY].members.alice=={"joined":true,"bucket":true} and Lost.view(s,"alice").joined,"starter auto joined with bucket")
	expect(not Lost.view(s,"bob").joined,"others not joined")
	# nobody close enough: nothing happens, no write
	var before:=s.duplicate(true)
	expect(not tick(s,a,0.5) and statuses(s)==["lost","lost"],"too far to lure")
	before=s.duplicate(true)
	expect(not Lost.step(s,a,yes) and s==before,"idle step leaves state untouched")
	# approach lures automatically (radius ~1.5), only one chick
	place(s,"alice",49.5,42.2)
	expect(tick(s,a,0.1),"approach lures")
	expect(statuses(s)==["follow","lost"] and s[KEY].chicks[0].by=="alice","chick follows alice")
	expect(Lost.public_view(s).chicks[0].status=="follow","follow visible publicly")
	# alice stands on the far chick as well: still one chick per player
	place(s,"alice",51.0,42.4)
	tick(s,a,0.6)
	expect(followers(s)==1,"at most one chick per player")
	# bring it home
	deliver(s,"alice",a)
	pv=Lost.public_view(s)
	expect(pv.returned==1 and pv.score==2 and pv.phase=="run" and pv.chicks[0].status=="home","first chick returned +2")
	expect(Vector2i(pv.chicks[0].x,pv.chicks[0].y)==Lost.PEN,"home chick sits at the pen")
	expect(pv.chicks[1].status=="lost","second still lost")
	# free again to lure the next one
	stand(s,"alice",Lost.SOLO_SPOTS[1])
	expect(tick(s,a,0.5) and statuses(s)[1]=="follow","second lured after the first returned")
	deliver(s,"alice",a)
	pv=Lost.public_view(s)
	expect(pv.phase=="results" and pv.returned==2 and pv.score==4 and pv.remaining==0,"early completion when all returned")
	expect(statuses(s)==["home","home"] and s[KEY].members.alice=={"joined":true,"bucket":false},"results: all home, bucket returned")
	expect(not Lost.view(s,"alice").joined,"results: not joined")
	expect(Lost.valid(s),"results valid")
	expect(not Lost.step(s,a,yes),"step idle after results")
	refused(s,"alice",Lost.SIGN,"join:1",true,a,"join after results")
	refused(s,"alice",Lost.SIGN,"leave:1",true,a,"leave after results")
	# replay
	expect(act(s,"alice","start",a).ok and rid(s)==2 and Lost.public_view(s).returned==0,"replay round 2")
	# solo is decided by home players online, not by players merely in the save
	var s2:=world()
	s2.players.bob.region="mine_1"
	expect(act(s2,"alice","start",online(["alice","bob"])).ok,"start with an away player online")
	expect(s2[KEY].mode=="solo" and s2[KEY].chicks.size()==2,"away / offline players do not count: solo")

func crew_mode_and_lure()->void:
	var both:=online(["alice","bob"])
	var s:=world()
	expect(act(s,"alice","start",both).ok,"crew start")
	var pv:=Lost.public_view(s)
	expect(pv.mode=="crew" and pv.total==6 and pv.chicks.size()==6,"crew view")
	expect(chick_cells(s)==Lost.CREW_SPOTS,"six chicks on the crew route")
	expect(s[KEY].members.keys()==["alice"],"only the starter is a member at first")
	# mode is fixed even when everybody else leaves or goes offline
	expect(cmd(s,"bob","join",both).ok,"bob joins")
	expect(s[KEY].members.bob=={"joined":true,"bucket":true},"loan bucket on join")
	expect(cmd(s,"bob","leave",both).ok and s[KEY].mode=="crew","mode stays crew")
	expect(tick(s,online(["alice"]),0.1)==false and s[KEY].mode=="crew" and s[KEY].chicks.size()==6,"fixed after others are gone")
	# one chick per player even with two chicks in range
	place(s,"alice",49.4,44.0)
	expect(tick(s,online(["alice"]),0.1),"lure")
	expect(followers(s)==1 and s[KEY].chicks[0].by=="alice" and s[KEY].chicks[1].status=="lost","nearest chick only")
	# two players, two chicks, each their own
	var t:=world()
	act(t,"alice","start",both)
	cmd(t,"bob","join",both)
	stand(t,"alice",Lost.CREW_SPOTS[0])
	stand(t,"bob",Lost.CREW_SPOTS[1])
	expect(tick(t,both,0.1) and followers(t)==2,"each player lures one chick")
	expect(t[KEY].chicks[0].by=="alice" and t[KEY].chicks[1].by=="bob","chicks matched to the nearest player")
	expect(not JSON.stringify(Lost.public_view(t)).contains("alice"),"public view hides who leads")
	# a player without a bucket never lures
	var u:=world()
	act(u,"alice","start",both)
	stand(u,"bob",Lost.CREW_SPOTS[0])
	expect(not tick(u,both,0.1) and followers(u)==0,"non member cannot lure")
	# lure radius boundary
	var v:=world()
	var a:=online(["alice"])
	act(v,"alice","start",a)
	place(v,"alice",49.5-1.6,42.5)
	expect(not tick(v,a,0.1) and followers(v)==0,"just outside the lure radius")
	place(v,"alice",49.5-1.4,42.5)
	expect(tick(v,a,0.1) and followers(v)==1,"inside the lure radius")
	# six chicks, two players: crew round completes early
	var w:=world()
	act(w,"alice","start",both)
	cmd(w,"bob","join",both)
	for i in range(6):
		var who:="alice" if i%2==0 else "bob"
		stand(w,who,Lost.CREW_SPOTS[i])
		tick(w,both,0.5)
		deliver(w,who,both)
	pv=Lost.public_view(w)
	expect(pv.phase=="results" and pv.returned==6 and pv.score==12,"crew returns six for 12 points")

func spawn_safety()->void:
	var a:=online(["alice"])
	var state:=world()
	var before:=state.duplicate(true)
	expect(not Lost.apply(state,"alice",Lost.SIGN,"start",true,a,no).ok and state==before,"blocked pen leaves the world untouched")
	var sealed:Vector2i=Lost.SOLO_SPOTS[0]
	var healthy_route:=func(_token:String,_from:Vector2i,to:Vector2i)->bool:return to!=sealed
	expect(Lost.apply(state,"alice",Lost.SIGN,"start",true,a,healthy_route).ok,"a legacy obstruction moves the spawn to a reachable tile")
	expect(sealed not in chick_cells(state) and chick_cells(state).size()==2,"keeps the full flock off blocked tiles")
	stand(state,"alice",chick_cells(state)[0])
	tick(state,a,0.5)
	expect(followers(state)==1,"lured a chick before leaving")
	Lost.return_bucket(state,"alice")
	expect(followers(state)==0 and not Lost.view(state,"alice").joined,"disconnect immediately returns bucket and frees chick")

func hopping()->void:
	var a:=online(["alice"])
	var s:=world()
	act(s,"alice","start",a)
	place(s,"alice",49.5,42.5)
	expect(tick(s,a,0.0),"lure at once")
	# move the player away (far from the pen) to watch the chick walk after them
	stand(s,"alice",Vector2i(55,44))
	var calls:=[]
	var recorder:=func(token:String,from:Vector2i,to:Vector2i)->bool:
		calls.append([token,from,to])
		return true
	var advanced:=0
	for i in range(30):
		var before:Vector2i=chick_cells(s)[0]
		var moved:=tick(s,a,0.46,recorder)
		var after:Vector2i=chick_cells(s)[0]
		if moved and after!=before:
			advanced+=1
			expect(absi(after.x-before.x)+absi(after.y-before.y)==1,"hop is one four-direction tile")
			expect(Lost.AREA.has_point(after),"hop stays inside area")
			var gap:=float(s[KEY].next)-float(s.time)
			expect(gap>=Lost.STEP_MIN-0.0001 and gap<=Lost.STEP_MIN+Lost.STEP_SPAN+0.0001,"next hop scheduled within 0.3-0.45s")
		if s[KEY].chicks[0].status!="follow":break
	expect(advanced>=3,"chick actually hops several times")
	expect(calls.size()>=3 and calls[0][0]=="alice" and calls[0][1] is Vector2i and calls[0][2] is Vector2i,"callback signature")
	var last_cell:Vector2i=chick_cells(s)[0]
	expect(s[KEY].chicks[0].status=="follow" and absi(last_cell.x-55)+absi(last_cell.y-44)<=1,"chick ends up next to the player")
	# no instant teleport: between hop times nothing moves and nothing is saved
	var t:=world()
	act(t,"alice","start",a)
	place(t,"alice",49.5,42.5)
	tick(t,a,0.0)
	stand(t,"alice",Vector2i(56,45))
	tick(t,a,0.5)
	var pos:Vector2i=chick_cells(t)[0]
	var snap:=t.duplicate(true)
	expect(not tick(t,a,0.05) and t.time==snap.time+0.05,"early step reports no change")
	snap.time=t.time
	expect(t==snap,"early step does not write anything")
	expect(chick_cells(t)[0]==pos,"no movement before the hop time")
	# blocked by the caller: no move, no save signal, retry later
	var blocked:=world()
	act(blocked,"alice","start",a)
	place(blocked,"alice",49.5,42.5)
	tick(blocked,a,0.0,no)
	stand(blocked,"alice",Vector2i(56,45))
	var start_cell:Vector2i=chick_cells(blocked)[0]
	expect(not tick(blocked,a,0.5,no) and chick_cells(blocked)[0]==start_cell,"blocked hop: no movement, no change reported")
	expect(float(blocked[KEY].next)>float(blocked.time),"blocked hop still advances the schedule")
	expect(tick(blocked,a,0.5,yes) and chick_cells(blocked)[0]!=start_cell,"later hop works once unblocked")
	var invalid:=world()
	act(invalid,"alice","start",a)
	place(invalid,"alice",49.5,42.5)
	tick(invalid,a,0.0,Callable())
	stand(invalid,"alice",Vector2i(56,45))
	var cell0:Vector2i=chick_cells(invalid)[0]
	expect(not tick(invalid,a,0.5,Callable()) and chick_cells(invalid)[0]==cell0,"invalid callable blocks hops")
	# a chick does not hop onto a cell holding another chick
	var crowd:=world()
	var both:=online(["alice","bob"])
	act(crowd,"alice","start",both)
	crowd[KEY].chicks[1].x=49
	crowd[KEY].chicks[1].y=44
	crowd[KEY].chicks[0].x=48
	crowd[KEY].chicks[0].y=44
	stand(crowd,"alice",Vector2i(48,44))
	tick(crowd,both,0.0)
	place(crowd,"alice",52.5,44.5)
	tick(crowd,both,0.5)
	expect(chick_cells(crowd)[0]!=chick_cells(crowd)[1],"chicks never share a tile while walking")
	# the chick keeps its distance from the player instead of stepping on them
	var near:=world()
	act(near,"alice","start",a)
	place(near,"alice",49.5,42.5)
	tick(near,a,0.0)
	for i in range(6):tick(near,a,0.5)
	expect(near[KEY].chicks[0].status=="follow" and chick_cells(near)[0]==Vector2i(49,42),"already adjacent: stays")
	# pen entry needs follow + near the pen: a lost chick near the pen stays lost
	var pen:=world()
	act(pen,"alice","start",a)
	pen[KEY].chicks[0].x=51
	pen[KEY].chicks[0].y=39
	stand(pen,"bob",Vector2i(51,39))
	expect(not tick(pen,a,0.5) and pen[KEY].chicks[0].status=="lost","lost chick next to the pen is not returned")
	# Chick and leader are both near enough for a clear entrance.
	place(pen,"alice",51.5,39.5)
	expect(tick(pen,a,0.5) and pen[KEY].chicks[0].status=="home" and pen[KEY].returned==1,"follow + near pen returns it")
	# A chick cannot return through a blocked fence or before the leader reaches the pen.
	var edge:=world()
	act(edge,"alice","start",a)
	edge[KEY].chicks[0].x=53
	edge[KEY].chicks[0].y=40
	place(edge,"alice",53.5,40.5)
	tick(edge,a,0.0,no)
	expect(edge[KEY].chicks[0].status=="follow","two tiles from the pen is not enough")
	edge[KEY].chicks[0].x=52
	edge[KEY].chicks[0].y=41
	edge.time=float(edge.time)+0.5
	expect(not Lost.step(edge,a,no) and edge[KEY].chicks[0].status=="follow","leader far away and no clear step: no score")
	place(edge,"alice",51.5,40.5)
	edge[KEY].chicks[0].x=51
	edge[KEY].chicks[0].y=41
	expect(not tick(edge,a,0.5,no) and edge[KEY].returned==0,"a blocked last step cannot score through a fence")
	expect(tick(edge,a,0.5,yes) and edge[KEY].returned==1,"the same chick scores once the gate is clear")

func timeout()->void:
	var both:=online(["alice","bob"])
	var s:=world()
	act(s,"alice","start",both)
	cmd(s,"bob","join",both)
	stand(s,"alice",Lost.CREW_SPOTS[0])
	tick(s,both,0.1)
	deliver(s,"alice",both)
	expect(Lost.public_view(s).returned==1,"one returned before the end")
	stand(s,"bob",Lost.CREW_SPOTS[2])
	tick(s,both,0.5)
	expect(followers(s)==1,"bob is leading a chick at the deadline")
	s.time=T0+179.5
	expect(Lost.public_view(s).remaining==1,"remaining rounds up")
	expect(cmd(s,"bob","leave",both).ok,"can still leave just before the end")
	expect(cmd(s,"bob","join",both).ok,"can still join just before the end")
	s.time=T0+180.0
	expect(Lost.public_view(s).remaining==0,"remaining zero at the deadline")
	refused(s,"carol",Lost.SIGN,"join:1",true,online(NAMES),"join at the deadline")
	refused(s,"alice",Lost.SIGN,"start",true,online(NAMES),"start while expired run")
	expect(Lost.step(s,both,yes),"step settles at 180")
	var pv:=Lost.public_view(s)
	expect(pv.phase=="results" and pv.returned==1 and pv.score==2,"timeout gives points only for real returns")
	expect(pv.chicks.size()==6,"six chicks listed")
	for c in pv.chicks:expect(c.status=="home" and Vector2i(c.x,c.y)==Lost.PEN,"timeout returns every chick")
	expect(s[KEY].members.bob.bucket==false and s[KEY].members.alice.bucket==false,"buckets returned at the end")
	expect(not Lost.step(s,both,yes),"step is idempotent")
	expect(Lost.valid(s),"timeout results valid")
	expect(act(s,"alice","start",both).ok and rid(s)==2,"next round can start")
	# nobody delivers anything: zero points
	var z:=world()
	var a:=online(["alice"])
	act(z,"alice","start",a)
	z.time=T0+500.0
	expect(Lost.step(z,a,yes) and Lost.public_view(z).score==0 and Lost.public_view(z).returned==0,"timeout with nothing delivered")
	for c in Lost.public_view(z).chicks:expect(c.status=="home","all returned without points")
	# timeout works even with no members online / nobody joined
	var empty:=world()
	act(empty,"alice","start",a)
	cmd(empty,"alice","leave",a)
	empty.time=T0+180.0
	expect(Lost.step(empty,{},yes) and Lost.public_view(empty).phase=="results","timeout with nobody present")
	# round limit
	var cap:=world()
	act(cap,"alice","start",a)
	cap.time=T0+180.0
	Lost.step(cap,a,yes)
	cap[KEY].round=Lost.MAX_ROUND
	expect(Lost.valid(cap),"max round is valid")
	refused(cap,"alice",Lost.SIGN,"start",true,a,"round limit")

func late_join_and_cap()->void:
	var all:=online(NAMES)
	var s:=world()
	act(s,"alice","start",all)
	# a lone player does not end the round by leaving; late arrivals can still join and finish
	expect(cmd(s,"alice","leave",all).ok,"starter leaves")
	expect(tick(s,all,20.0)==false and s[KEY].phase=="run","round keeps running with nobody joined")
	expect(Lost.public_view(s).remaining<180 and Lost.public_view(s).remaining>0,"clock keeps ticking")
	expect(cmd(s,"bob","join",all).ok and s[KEY].members.bob.bucket==true,"late arrival gets a loan bucket")
	stand(s,"bob",Lost.CREW_SPOTS[0])
	tick(s,all,0.1)
	deliver(s,"bob",all)
	expect(Lost.public_view(s).returned==1,"late arrival returns a chick")
	# up to 8 distinct members; a 9th is refused; leavers can come back
	var t:=world()
	act(t,"alice","start",all)
	for i in range(1,8):expect(cmd(t,NAMES[i],"join",all).ok,"join %s"%NAMES[i])
	expect(t[KEY].members.size()==8,"eight members")
	refused(t,"ivy",Lost.SIGN,"join:1",true,all,"ninth player refused")
	expect(cmd(t,"carol","leave",all).ok and not Lost.view(t,"carol").joined,"carol leaves")
	refused(t,"ivy",Lost.SIGN,"join:1",true,all,"leaver keeps their seat in the cap")
	expect(cmd(t,"carol","join",all).ok and Lost.view(t,"carol").joined,"carol rejoins via explicit join")
	expect(Lost.valid(t),"eight member record valid")

func leave_and_disconnect()->void:
	var both:=online(["alice","bob"])
	var s:=world()
	act(s,"alice","start",both)
	cmd(s,"bob","join",both)
	stand(s,"alice",Lost.CREW_SPOTS[0])
	stand(s,"bob",Lost.CREW_SPOTS[1])
	tick(s,both,0.1)
	expect(followers(s)==2,"both lead a chick")
	stand(s,"alice",Vector2i(50,40))
	tick(s,both,0.5)
	var alice_chick:Vector2i=chick_cells(s)[0]
	# leaving from far away, from another region: lure dropped, bucket returned
	var left:=act(s,"alice","leave:1",both,false,Vector2i(0,0))
	expect(left.ok,"leave from anywhere")
	expect(s[KEY].members.alice=={"joined":false,"bucket":false},"leaver returned the bucket")
	expect(s[KEY].chicks[0].status=="lost" and s[KEY].chicks[0].by=="" and chick_cells(s)[0]==alice_chick,"chick stays where it was, free again")
	expect(s[KEY].chicks[1].status=="follow" and s[KEY].chicks[1].by=="bob","other player's lure untouched")
	refused(s,"alice",Lost.SIGN,"leave:1",true,both,"leave twice")
	expect(not Lost.view(s,"alice").joined,"not joined after leaving")
	# remaining players resume: bob delivers, then picks up alice's dropped chick
	deliver(s,"bob",both)
	expect(Lost.public_view(s).returned==1,"bob keeps playing")
	place(s,"bob",alice_chick.x+0.5,alice_chick.y+0.5)
	tick(s,both,0.5)
	expect(s[KEY].chicks[0].status=="follow" and s[KEY].chicks[0].by=="bob","bob picks up the dropped chick")
	# alice reconnects: nothing happens until she explicitly joins again
	stand(s,"alice",Lost.CREW_SPOTS[2])
	tick(s,both,0.5)
	expect(not Lost.view(s,"alice").joined and s[KEY].chicks[2].status=="lost","reconnect alone does not rejoin")
	expect(cmd(s,"alice","join",both).ok and s[KEY].members.alice=={"joined":true,"bucket":true},"explicit join restores a bucket")
	# disconnect (token no longer active) drops the lure
	var d:=world()
	act(d,"alice","start",both)
	cmd(d,"bob","join",both)
	stand(d,"bob",Lost.CREW_SPOTS[1])
	tick(d,both,0.1)
	expect(followers(d)==1,"bob leads")
	var only_alice:=online(["alice"])
	expect(tick(d,only_alice,0.1),"disconnect is a change")
	expect(followers(d)==0 and d[KEY].members.bob=={"joined":false,"bucket":false},"disconnect drops lure and bucket")
	expect(d[KEY].members.alice.joined==true,"remaining player unaffected")
	expect(not tick(d,only_alice,0.1),"second step is quiet")
	refused(d,"bob",Lost.SIGN,"join:1",true,only_alice,"cannot join while not active")
	expect(cmd(d,"bob","join",both).ok,"bob returns by explicit join")
	# leaving the home region drops the lure as well
	var g:=world()
	act(g,"alice","start",both)
	stand(g,"alice",Lost.CREW_SPOTS[0])
	tick(g,both,0.1)
	expect(followers(g)==1,"alice leads")
	g.players.alice.region="mine_1"
	expect(tick(g,both,0.1) and followers(g)==0 and g[KEY].members.alice.joined==false,"left home: lure dropped")
	# an array of tokens works as active list too
	var arr:=world()
	expect(Lost.apply(arr,"alice",Lost.SIGN,"start",true,["alice"]).ok,"array active list accepted")
	expect(not Lost.step(arr,["alice"],yes) and arr[KEY].members.alice.joined==true,"array active list keeps member")
	# a hop target outside is never used and a non-finite position is ignored
	var nan:=world()
	var a:=online(["alice"])
	act(nan,"alice","start",a)
	nan.players.alice.x=NAN
	expect(not tick(nan,a,0.5) and followers(nan)==0,"non finite position never lures")

func economy_and_privacy()->void:
	var both:=online(["alice","bob"])
	var s:=world()
	var base:=s.duplicate(true)
	act(s,"alice","start",both)
	cmd(s,"bob","join",both)
	stand(s,"alice",Lost.CREW_SPOTS[0])
	tick(s,both,0.1)
	deliver(s,"alice",both)
	s.time=T0+180.0
	Lost.step(s,both,yes)
	for t in s.players:
		for field in ["coins","name","bag","inventory"]:
			expect(s.players[t][field]==base.players[t][field],"%s %s untouched"%[t,field])
		expect(not s.players[t].has(KEY) and not s.players[t].has("chickens"),"no personal reward for "+t)
	expect(s.crops==base.crops and s.community==base.community,"world untouched")
	var keys:=s.keys()
	keys.sort()
	expect(keys==["community","crops","lost_chicks","picnic","players","time"],"only own record added")
	var text:=JSON.stringify(Lost.public_view(s))
	for t in NAMES:expect(not text.contains(t),"public view has no token "+t)
	expect(Lost.public_view(s).keys().size()==8,"public view fields")
	for c in Lost.public_view(s).chicks:expect(c.keys().size()==3 and not c.has("by"),"chick view fields")
	expect(Lost.view(s,"alice").keys().size()==2,"own view fields")
	var before:=s.duplicate(true)
	Lost.public_view(s)
	Lost.view(s,"alice")
	expect(s==before,"views are read only")

func save_validation()->void:
	var both:=online(["alice","bob"])
	var s:=world()
	act(s,"alice","start",both)
	cmd(s,"bob","join",both)
	stand(s,"alice",Lost.CREW_SPOTS[0])
	tick(s,both,0.1)
	stand(s,"bob",Lost.CREW_SPOTS[1])
	tick(s,both,0.5)
	deliver(s,"bob",both)
	stand(s,"alice",Lost.CREW_SPOTS[2])
	tick(s,both,0.5)
	expect(s[KEY].returned==1 and followers(s)>=1,"fixture: one home, one following")
	expect(Lost.valid(s),"fixture valid")
	var back:Variant=JSON.parse_string(JSON.stringify(s))
	expect(back is Dictionary and Lost.valid(back),"JSON round trip valid")
	expect(back[KEY].round is int and back[KEY].chicks[0].x is int and back[KEY].returned is int,"integers normalized after load")
	expect(Lost.valid(world(),s) and not Lost.valid(world(),"nope") and not Lost.valid(s,{"picnic":true}),"optional candidate state")
	var bad_candidate:=s.duplicate(true)
	bad_candidate[KEY].score=3
	expect(Lost.valid(s) and not Lost.valid(s,bad_candidate),"candidate checked instead of state")
	var bad:=func(label:String,mutate:Callable)->void:
		var copy:Dictionary=s.duplicate(true)
		mutate.call(copy)
		expect(not Lost.valid(copy),"invalid: "+label)
	var follow_idx:=-1
	for i in range(6):
		if s[KEY].chicks[i].status=="follow":follow_idx=i
	var lost_idx:=-1
	for i in range(6):
		if s[KEY].chicks[i].status=="lost":lost_idx=i
	var home_idx:=-1
	for i in range(6):
		if s[KEY].chicks[i].status=="home":home_idx=i
	bad.call("no picnic",func(c):c.picnic=false)
	bad.call("extra field",func(c):c[KEY].extra=1)
	bad.call("missing field",func(c):c[KEY].erase("chicks"))
	bad.call("round zero",func(c):c[KEY].round=0)
	bad.call("round fraction",func(c):c[KEY].round=1.5)
	bad.call("round huge",func(c):c[KEY].round=Lost.MAX_ROUND+1)
	bad.call("phase",func(c):c[KEY].phase="done")
	bad.call("mode",func(c):c[KEY].mode="duo")
	bad.call("mode vs chick count",func(c):c[KEY].mode="solo")
	bad.call("chick missing",func(c):c[KEY].chicks.pop_back())
	bad.call("chick extra",func(c):c[KEY].chicks.append({"x":48,"y":43,"status":"lost","by":""}))
	bad.call("chick shape",func(c):c[KEY].chicks[0]={"x":48,"y":43,"status":"lost"})
	bad.call("chick status",func(c):c[KEY].chicks[lost_idx].status="dead")
	bad.call("chick x outside",func(c):c[KEY].chicks[lost_idx].x=Lost.AREA.end.x)
	bad.call("chick y outside",func(c):c[KEY].chicks[lost_idx].y=Lost.AREA.position.y-1)
	bad.call("chick x fraction",func(c):c[KEY].chicks[lost_idx].x=48.5)
	bad.call("lost with owner",func(c):c[KEY].chicks[lost_idx].by="alice")
	bad.call("follow without owner",func(c):c[KEY].chicks[follow_idx].by="")
	bad.call("follow unknown owner",func(c):c[KEY].chicks[follow_idx].by="ghost")
	bad.call("follow by non member",func(c):c[KEY].chicks[follow_idx].by="carol")
	bad.call("follow by departed",func(c):
		var owner:String=c[KEY].chicks[follow_idx].by
		c[KEY].members[owner]={"joined":false,"bucket":false})
	bad.call("two chicks one player",func(c):
		c[KEY].chicks[lost_idx].status="follow"
		c[KEY].chicks[lost_idx].by=c[KEY].chicks[follow_idx].by)
	bad.call("home away from pen",func(c):c[KEY].chicks[home_idx].x=Lost.PEN.x+1)
	bad.call("score",func(c):c[KEY].score=3)
	bad.call("score negative",func(c):c[KEY].score=-2)
	bad.call("returned over total",func(c):c[KEY].returned=7;c[KEY].score=14)
	bad.call("returned vs home chicks",func(c):c[KEY].returned=2;c[KEY].score=4)
	bad.call("run with every chick returned",func(c):
		for chick in c[KEY].chicks:
			chick.status="home"
			chick.by=""
			chick.x=Lost.PEN.x
			chick.y=Lost.PEN.y
		c[KEY].returned=6
		c[KEY].score=12)
	bad.call("bucket without join",func(c):c[KEY].members.bob.bucket=false)
	bad.call("member shape",func(c):c[KEY].members.bob={"joined":true})
	bad.call("member flag type",func(c):c[KEY].members.bob={"joined":1,"bucket":1})
	bad.call("unknown member",func(c):c[KEY].members["ghost"]={"joined":false,"bucket":false})
	bad.call("no members",func(c):c[KEY].members={})
	bad.call("nine members",func(c):
		for t in NAMES:c[KEY].members[t]={"joined":false,"bucket":false})
	bad.call("started in the future",func(c):c[KEY].started=T0+50.0)
	bad.call("next negative",func(c):c[KEY].next=-1.0)
	bad.call("next far in the future",func(c):c[KEY].next=float(c.time)+5.0)
	bad.call("next not a number",func(c):c[KEY].next="soon")
	bad.call("players not a dict",func(c):c.players=[])
	bad.call("results with a lost chick",func(c):
		c[KEY].phase="results"
		c[KEY].next=0.0
		for member in c[KEY].members:c[KEY].members[member].bucket=false
		c[KEY].chicks[lost_idx].status="lost")
	var finished:=s.duplicate(true)
	finished.time=T0+180.0
	Lost.step(finished,both,yes)
	expect(finished[KEY].phase=="results" and Lost.valid(finished),"real results valid")
	var results_bad:=func(label:String,mutate:Callable)->void:
		var copy:Dictionary=finished.duplicate(true)
		mutate.call(copy)
		expect(not Lost.valid(copy),"invalid results: "+label)
	results_bad.call("bucket kept",func(c):c[KEY].members.alice.bucket=true)
	results_bad.call("next left behind",func(c):c[KEY].next=c.time)
	results_bad.call("follower in results",func(c):
		c[KEY].chicks[0].status="follow"
		c[KEY].chicks[0].by="alice")
	# a record without a shared part is fine
	var lone:=world()
	expect(Lost.valid(lone),"no record valid")
	# corrupt shared record makes actions fail without mutating
	var broken:=world()
	broken[KEY]={"round":1,"phase":"run"}
	refused(broken,"alice",Lost.SIGN,"start",true,both,"corrupt record")
	expect(Lost.public_view(broken).phase=="idle","corrupt record reads as idle")
	expect(not Lost.step(broken,both,yes),"corrupt record never steps")
