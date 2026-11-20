extends SceneTree
## Regression suite for res://scripts/beach_treasure.gd (海灘尋寶): picnic / home / reach gates,
## fixed contract, atomic refusals, solo and two-player rounds, late join, shared marks,
## clue sharpening (time + wrong digs, once per spot), settlement + keepsake rules,
## quit / reconnect, 8-member cap, timeout via step(), stale ids, no economy side effects,
## public view privacy, and strict save validation / JSON round trip.
const Beach=preload("res://scripts/beach_treasure.gd")
const T0:=1000.0
const KEY:="beach_treasure"
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	print("BEACH_TREASURE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func person()->Dictionary:
	return {"x":50.5,"y":55.5,"coins":120,"name":"島民","bag":["seed"],
		"inventory":{"radish":2,"turnip":4,"trout_hotpot":2}}

static func world(time:float=T0,picnic:bool=true,tokens:Array=["alice","bob","carol"])->Dictionary:
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
	return Beach.apply(state,token,at,extra,home)

func spot(id:String)->Vector2i:
	return Beach.SPOTS[id].cell

func rid(state:Dictionary)->int:
	return int(state[KEY].round)

func start(state:Dictionary,token:String="alice")->Dictionary:
	return act(state,token,Beach.SIGN,"start")

func join(state:Dictionary,token:String,round_id:int=-1)->Dictionary:
	return act(state,token,Beach.SIGN,"join:%d"%(round_id if round_id>=0 else rid(state)))

func dig(state:Dictionary,token:String,id:String,round_id:int=-1)->Dictionary:
	return act(state,token,spot(id),"dig:%d"%(round_id if round_id>=0 else rid(state)))

func mark(state:Dictionary,token:String,id:String,round_id:int=-1)->Dictionary:
	return act(state,token,spot(id),"mark:%d"%(round_id if round_id>=0 else rid(state)))

func targets(state:Dictionary)->Array:
	return Beach.treasures_for(rid(state))

func decoys(state:Dictionary)->Array:
	var result:=[]
	for id in Beach.SPOTS:
		if id not in targets(state):result.append(id)
	return result

## The action must fail and leave the whole state untouched.
func refused(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool,label:String)->void:
	stand(state,token,at)
	var before:=state.duplicate(true)
	var result:=Beach.apply(state,token,at,extra,home)
	expect(result.ok==false and result.has("message"),label+" refused")
	expect(state==before,label+" leaves state unchanged")

func clue_strings(state:Dictionary)->Array:
	var out:=[]
	for c in Beach.public_view(state).clues:out.append(str(c))
	return out

func _initialize()->void:
	contract()
	gates()
	solo_round()
	rounds_and_templates()
	two_players()
	clues_sharpen()
	wrong_dig_rules()
	marks()
	quit_and_reconnect()
	cap()
	timeout()
	stale_ids()
	keepsake_rules()
	privacy()
	economy_untouched()
	validation()
	save_roundtrip()
	finish()

func contract()->void:
	expect(Beach.KEY=="beach_treasure" and Beach.ACTION=="beach_treasure" and Beach.VIEW_KEY=="own_beach_treasure","names")
	expect(Beach.SIGN==Vector2i(50,55) and Beach.AREA==Rect2i(44,51,11,8),"sign and area")
	expect(Beach.SPOTS.keys()==["a","b","c","d","e","f"],"spot ids")
	expect(Beach.SPOTS.a=={"cell":Vector2i(46,56),"title":"貝灘西側"},"spot a")
	expect(Beach.SPOTS.b=={"cell":Vector2i(49,55),"title":"木板道西邊"},"spot b")
	expect(Beach.SPOTS.c=={"cell":Vector2i(52,55),"title":"東邊潮線"},"spot c")
	expect(Beach.SPOTS.d=={"cell":Vector2i(48,57),"title":"石滬旁沙地"},"spot d")
	expect(Beach.SPOTS.e=={"cell":Vector2i(50,57),"title":"木板道南端"},"spot e")
	expect(Beach.SPOTS.f=={"cell":Vector2i(52,57),"title":"沙嘴東端"},"spot f")
	expect(Beach.AREA.has_point(Beach.SIGN),"sign inside area")
	var cells:={}
	for id in Beach.SPOTS:
		expect(Beach.AREA.has_point(Beach.SPOTS[id].cell),"spot %s inside area"%id)
		cells[Beach.SPOTS[id].cell]=true
		expect(Beach.CLUES.has(id) and Beach.CLUES[id].size()==Beach.MAX_LEVEL+1,"four clue levels for %s"%id)
	expect(cells.size()==6 and not cells.has(Beach.SIGN),"six distinct cells, none is the sign")
	expect(Beach.TEMPLATES.size()==3,"three templates")
	var covered:={}
	for t in Beach.TEMPLATES:
		expect(t.size()==3 and t[0]!=t[1] and t[1]!=t[2] and t[0]!=t[2],"template has three distinct spots")
		for id in t:
			expect(Beach.SPOTS.has(id),"template id known")
			covered[id]=true
	expect(covered.size()==6,"every shore cell is a target in some template")
	expect(Beach.DURATION==300.0 and Beach.MAX_PLAYERS==8 and Beach.POINTS==3 and Beach.TREASURES==3 and Beach.REACH==3.2,"constants")
	var v:=Beach.view(world(),"alice")
	expect(v.keys().size()==5 and v.unlocked==true and v.joined==false and v.completed==false and v.dug==false and v.can_start==true,"fresh view")
	var p:=Beach.public_view(world())
	expect(p.keys().size()==10 and p.round==0 and p.phase=="idle" and p.remaining==0 and p.found.is_empty() and p.marks.is_empty() and p.searched.is_empty(),"idle public view")
	expect(p.clues.size()==0 and p.score==0 and p.guests==0 and p.reason=="","idle public view rest")
	expect(Beach.valid(world()),"legacy absence valid")
	expect(Beach.view({},"x").can_start==false and Beach.view(world(),"ghost").can_start==true,"odd views")
	expect(Beach.public_view({}).phase=="idle","public view of empty state")

func gates()->void:
	var s:=world(T0,false)
	refused(s,"alice",Beach.SIGN,"start",true,"picnic required")
	expect(Beach.view(s,"alice").unlocked==false and Beach.view(s,"alice").can_start==false,"view needs picnic")
	s=world()
	refused(s,"alice",Beach.SIGN,"start",false,"home required")
	refused(s,"ghost",Beach.SIGN,"start",true,"unknown player")
	refused(s,"alice",Vector2i(51,55),"start",true,"wrong sign cell")
	refused(s,"alice",spot("a"),"start",true,"start at a spot")
	stand(s,"alice",Vector2i(40,29))
	var before:=s.duplicate(true)
	expect(Beach.apply(s,"alice",Beach.SIGN,"start",true).ok==false and s==before,"sign from far away")
	for extra in ["","START","start ","go","join","join:","dig","dig:x","start:1","mark:1:2","dig:1:a"]:
		refused(s,"alice",Beach.SIGN,extra,true,"bad extra '%s'"%extra)
	s=world()
	s.players.alice[KEY]=false
	refused(s,"alice",Beach.SIGN,"start",true,"bad personal record")
	s=world()
	expect(start(s).ok==true,"baseline start")
	stand(s,"alice",Vector2i(40,29))
	var snap:=s.duplicate(true)
	expect(Beach.apply(s,"alice",spot("a"),"dig:1",true).ok==false and s==snap,"dig from far away")
	expect(Beach.apply(s,"alice",spot("a"),"mark:1",true).ok==false and s==snap,"mark from far away")
	stand(s,"alice",Beach.SIGN)
	expect(Beach.apply(s,"alice",Beach.SIGN,"dig:1",true).ok==false,"dig at the sign")
	expect(Beach.apply(s,"alice",Vector2i(47,56),"dig:1",true).ok==false,"dig on a non-spot cell")
	# reach: a few cells away still works, clearly beyond 3.2 does not (avoids float edge)
	var c:=center(spot("e"))
	s.players.alice.x=c.x
	s.players.alice.y=c.y-3.0
	expect(Beach.apply(s,"alice",spot("e"),"mark:1",true).ok==true,"3 cells is inside reach")
	s.players.alice.y=c.y-3.4
	var edge:=s.duplicate(true)
	expect(Beach.apply(s,"alice",spot("e"),"dig:1",true).ok==false and s==edge,"3.4 cells is out of reach")
	s.players.alice.x=NAN
	expect(Beach.apply(s,"alice",spot("e"),"dig:1",true).ok==false,"non-finite position refused")
	# actions need a home region, but leaving does not
	s=world()
	start(s)
	refused(s,"alice",spot("a"),"dig:1",false,"dig away from home")
	refused(s,"alice",Beach.SIGN,"join:1",false,"join away from home")
	stand(s,"alice",Vector2i(5,5))
	expect(Beach.apply(s,"alice",Vector2i(5,5),"leave:1",false).ok==true,"leave works anywhere, even another region")

func solo_round()->void:
	var s:=world()
	var r:=start(s)
	expect(r.ok==true and rid(s)==1 and s[KEY].phase=="search","start opens round 1")
	var p:=Beach.public_view(s)
	expect(p.round==1 and p.phase=="search" and p.remaining==300 and p.guests==1 and p.score==0 and p.reason=="","search public view")
	expect(p.clues.size()==3 and p.found.is_empty() and p.marks.is_empty(),"one clue per treasure")
	for c in p.clues:expect(c is String and not str(c).is_empty(),"clue is a non-empty string")
	var v:=Beach.view(s,"alice")
	expect(v.joined==true and v.dug==false and v.completed==false and v.can_start==false,"starter auto joined")
	expect(Beach.valid(s),"state valid after start")
	var t:=targets(s)
	var d:=decoys(s)
	# a wrong dig first: no score, no penalty
	expect(dig(s,"alice",d[0]).ok==true,"wrong dig is valid")
	p=Beach.public_view(s)
	expect(p.score==0 and p.found.is_empty() and p.phase=="search","wrong dig scores nothing and finds nothing")
	expect(Beach.view(s,"alice").dug==true,"wrong dig counts as dug")
	expect(p.searched.size()==1 and p.searched.has(d[0]) and not p.found.has(d[0]),"wrong dig is public as searched, not found")
	expect(dig(s,"alice",t[0]).ok==true,"first treasure")
	p=Beach.public_view(s)
	expect(p.score==3 and p.found.has(t[0]) and p.found.size()==1 and p.phase=="search","3 points per treasure")
	expect(dig(s,"alice",t[1]).ok==true and Beach.public_view(s).score==6,"second treasure")
	expect(Beach.valid(s),"valid mid round")
	var last:=dig(s,"alice",t[2])
	expect(last.ok==true,"third treasure")
	p=Beach.public_view(s)
	expect(p.phase=="results" and p.reason=="goal" and p.score==9 and p.remaining==0 and p.found.size()==3,"settled immediately on goal")
	expect(s.players.alice[KEY]==true and Beach.view(s,"alice").completed==true,"solo keepsake")
	expect(Beach.valid(s),"valid after results")
	expect(Beach.step(s)==false,"step does nothing after results")
	refused(s,"alice",spot(t[0]),"dig:1",true,"dig after results")
	refused(s,"alice",spot("a"),"mark:1",true,"mark after results")
	expect(Beach.view(s,"alice").can_start==true,"results can restart")
	# restart immediately
	expect(start(s).ok==true and rid(s)==2,"restart straight from results")
	p=Beach.public_view(s)
	expect(p.phase=="search" and p.score==0 and p.found.is_empty() and p.marks.is_empty() and p.reason=="" and p.remaining==300,"fresh round state")
	refused(s,"alice",Beach.SIGN,"start",true,"cannot start while searching")

func rounds_and_templates()->void:
	for r in range(1,8):
		expect(Beach.treasures_for(r)==Beach.TEMPLATES[r%3],"treasures follow round modulo 3 (%d)"%r)
	expect(Beach.treasures_for(3)==Beach.treasures_for(6) and Beach.treasures_for(1)!=Beach.treasures_for(2),"templates repeat every 3")
	var s:=world()
	for r in range(1,7):
		expect(start(s).ok==true and rid(s)==r,"round %d starts"%r)
		for id in targets(s):expect(dig(s,"alice",id).ok==true,"round %d dig %s"%[r,id])
		expect(Beach.public_view(s).phase=="results" and Beach.public_view(s).score==9,"round %d settled"%r)
	# the server really settles on the template: a decoy never completes the round
	start(s)
	for id in decoys(s):expect(dig(s,"alice",id).ok==true,"decoy dig")
	expect(Beach.public_view(s).phase=="search" and Beach.public_view(s).score==0,"all decoys dug, nothing found")

func two_players()->void:
	var s:=world()
	start(s)
	var t:=targets(s)
	var d:=decoys(s)
	expect(mark(s,"alice",t[0]).ok==true,"alice marks")
	expect(Beach.public_view(s).marks.has(t[0]),"mark visible to everyone")
	refused(s,"bob",spot(t[1]),"dig:1",true,"unjoined player cannot dig")
	refused(s,"bob",spot(t[1]),"mark:1",true,"unjoined player cannot mark")
	expect(dig(s,"alice",t[0]).ok==true,"alice digs a treasure")
	var clues_alice:=clue_strings(s)
	expect(join(s,"bob").ok==true,"bob joins late")
	var pb:=Beach.public_view(s)
	expect(pb.guests==2 and pb.found.has(t[0]) and pb.marks.has(t[0]) and pb.score==3,"late join shares progress")
	expect(clue_strings(s)==clues_alice,"late join sees the same clues")
	expect(Beach.view(s,"bob").joined==true and Beach.view(s,"bob").dug==false,"bob joined, has not dug")
	refused(s,"bob",Beach.SIGN,"join:1",true,"double join")
	expect(dig(s,"bob",d[0]).ok==true,"bob wrong dig")
	expect(Beach.view(s,"bob").dug==true,"bob dug")
	var found_before:Dictionary=Beach.public_view(s).found.duplicate()
	expect(Beach.public_view(s).score==3 and Beach.public_view(s).found==found_before,"bob wrong dig no penalty")
	expect(dig(s,"bob",t[1]).ok==true,"bob finds one")
	expect(Beach.public_view(s).phase=="search" and Beach.public_view(s).score==6,"two found")
	expect(join(s,"carol").ok==true,"carol joins")
	expect(dig(s,"alice",t[2]).ok==true,"alice finishes")
	var p:=Beach.public_view(s)
	expect(p.phase=="results" and p.reason=="goal" and p.score==9 and p.guests==3,"two players settle together")
	expect(s.players.alice[KEY]==true and s.players.bob[KEY]==true,"both diggers get the keepsake")
	expect(not s.players.carol.has(KEY) and Beach.view(s,"carol").completed==false,"joined but never dug: no keepsake")
	expect(Beach.valid(s),"valid after two player round")

func clues_sharpen()->void:
	var s:=world()
	start(s)
	var level0:=clue_strings(s)
	expect(level0.size()==3,"three clues")
	var seen:={}
	for text in level0:seen[text]=true
	expect(seen.size()==3,"clues for three treasures differ")
	s.time=T0+59.0
	expect(clue_strings(s)==level0,"clues unchanged before the first minute")
	var previous:=level0
	for minute in range(1,4):
		s.time=T0+60.0*minute+1.0
		var now:=clue_strings(s)
		expect(now.size()==3,"still one clue per treasure at minute %d"%minute)
		for i in range(3):expect(now[i]!=previous[i],"clue %d sharper at minute %d"%[i,minute])
		previous=now
	s.time=T0+299.0
	expect(clue_strings(s)==previous,"precision caps at the clearest level")
	expect(Beach.public_view(s).remaining==1,"remaining counts down on state.time")
	# solo gets the same automatic sharpening: nobody else is needed
	expect(Beach.public_view(s).guests==1,"sharpened while solo")
	# the clearest clue names the spot title
	var t:=targets(s)
	for i in range(3):expect(previous[i].contains(Beach.SPOTS[t[i]].title),"clearest clue %d names its spot"%i)
	# a wrong dig sharpens at once
	var s2:=world()
	start(s2)
	var base:=clue_strings(s2)
	var d:=decoys(s2)
	dig(s2,"alice",d[0])
	var after:=clue_strings(s2)
	for i in range(3):expect(after[i]!=base[i],"wrong dig sharpens clue %d"%i)
	dig(s2,"alice",d[1])
	var again:=clue_strings(s2)
	for i in range(3):expect(again[i]!=after[i],"second wrong spot sharpens clue %d"%i)
	# a found treasure's clue becomes a found notice and the others keep counting
	var s3:=world()
	start(s3)
	var t3:=targets(s3)
	dig(s3,"alice",t3[0])
	var cs:=clue_strings(s3)
	expect(cs.size()==3 and cs[0].begins_with("已挖到") and cs[0].contains(Beach.SPOTS[t3[0]].title),"found clue is replaced by a notice")
	expect(not cs[1].begins_with("已挖到") and not cs[2].begins_with("已挖到"),"unfound clues stay clues")

func wrong_dig_rules()->void:
	var s:=world()
	start(s)
	var d:=decoys(s)
	var t:=targets(s)
	expect(dig(s,"alice",d[0]).ok==true,"first wrong dig")
	var before:=clue_strings(s)
	refused(s,"alice",spot(d[0]),"dig:1",true,"same wrong spot twice")
	expect(clue_strings(s)==before,"no bonus clue from repeating")
	join(s,"bob")
	refused(s,"bob",spot(d[0]),"dig:1",true,"another player on a dug wrong spot")
	expect(dig(s,"alice",t[0]).ok==true,"treasure")
	refused(s,"bob",spot(t[0]),"dig:1",true,"already found spot")
	expect(Beach.public_view(s).score==3,"score unchanged by refusals")
	# clue spam cannot exceed the cap, and every spot digs once at most
	expect(dig(s,"alice",d[1]).ok==true and dig(s,"alice",d[2]).ok==true,"remaining wrong spots")
	expect(Beach.public_view(s).phase=="search" and Beach.public_view(s).found.size()==1,"wrong digs never end the round")
	expect(Beach.valid(s),"valid with all decoys dug")

func marks()->void:
	var s:=world()
	start(s)
	join(s,"bob")
	expect(mark(s,"alice","a").ok==true and mark(s,"bob","f").ok==true,"two marks")
	var p:=Beach.public_view(s)
	expect(p.marks.size()==2 and p.marks.has("a") and p.marks.has("f"),"marks are shared and keyed by spot id")
	refused(s,"bob",spot("a"),"mark:1",true,"duplicate mark")
	var t:=targets(s)
	expect(mark(s,"alice",t[0]).ok==true or Beach.public_view(s).marks.has(t[0]),"marking a target is fine")
	expect(dig(s,"alice",t[0]).ok==true,"digging a marked spot")
	refused(s,"bob",spot(t[0]),"mark:1",true,"mark a found spot")
	expect(Beach.public_view(s).marks.has("a") and Beach.valid(s),"marks persist")
	# a mark by itself is not a dig
	var s2:=world()
	start(s2)
	mark(s2,"alice","a")
	expect(Beach.view(s2,"alice").dug==false,"mark does not count as dug")

func quit_and_reconnect()->void:
	var s:=world()
	start(s)
	var d:=decoys(s)
	var t:=targets(s)
	expect(dig(s,"alice",d[0]).ok==true and dig(s,"alice",t[0]).ok==true,"alice contributes")
	join(s,"bob")
	expect(act(s,"alice",Vector2i(5,5),"leave:1",false).ok==true,"alice leaves from elsewhere")
	var p:=Beach.public_view(s)
	expect(p.found.has(t[0]) and p.score==3 and p.guests==1,"contribution survives leaving")
	var v:=Beach.view(s,"alice")
	expect(v.joined==false and v.dug==true,"left but remembered")
	refused(s,"alice",spot(t[1]),"dig:1",true,"left player cannot dig")
	refused(s,"alice",Vector2i(5,5),"leave:1",false,"leave twice")
	refused(s,"bob",Vector2i(5,5),"leave:2",false,"stale leave")
	expect(join(s,"alice").ok==true,"alice comes back")
	v=Beach.view(s,"alice")
	expect(v.joined==true and v.dug==true and Beach.public_view(s).guests==2,"rejoin restores")
	# a disconnect changes nothing: state is untouched, joined stays restored
	var before:=s.duplicate(true)
	expect(Beach.view(s,"alice").joined==true and s==before,"reconnect finds joined")
	# someone who left still gets the keepsake at settlement
	act(s,"alice",Vector2i(5,5),"leave:1",false)
	expect(dig(s,"bob",t[1]).ok==true and dig(s,"bob",t[2]).ok==true,"bob finishes alone")
	expect(Beach.public_view(s).phase=="results" and Beach.public_view(s).score==9,"settled")
	expect(s.players.alice[KEY]==true and s.players.bob[KEY]==true,"quitter who dug keeps the keepsake")
	expect(Beach.view(s,"alice").joined==false,"quitter stays out after results")
	refused(s,"alice",Beach.SIGN,"join:1",true,"cannot join a finished round")

func cap()->void:
	var tokens:=[]
	for i in range(10):tokens.append("m%d"%i)
	var s:=world(T0,true,tokens)
	expect(start(s,"m0").ok==true,"m0 starts")
	for i in range(1,8):expect(join(s,"m%d"%i).ok==true,"m%d joins"%i)
	expect(Beach.public_view(s).guests==8,"eight joined")
	refused(s,"m8",Beach.SIGN,"join:1",true,"ninth member refused")
	act(s,"m3",Vector2i(5,5),"leave:1",false)
	expect(Beach.public_view(s).guests==7,"leaving frees a seat in the count")
	refused(s,"m8",Beach.SIGN,"join:1",true,"total members are capped even after a leave")
	expect(join(s,"m3").ok==true,"a leaver may return")
	expect(Beach.valid(s),"eight members valid")
	expect(Beach.view(s,"m8").joined==false,"m8 not joined")
	# next round starts fresh with one member and all seats open again
	for id in targets(s):dig(s,"m0",id)
	expect(Beach.public_view(s).phase=="results","cap round settled")
	expect(start(s,"m9").ok==true and Beach.public_view(s).guests==1,"next round resets membership")
	expect(join(s,"m8").ok==true,"m8 joins the new round")

func timeout()->void:
	var s:=world()
	start(s)
	var d:=decoys(s)
	var t:=targets(s)
	dig(s,"alice",d[0])
	dig(s,"alice",t[0])
	join(s,"bob")
	s.time=T0+299.5
	expect(Beach.step(s)==false and Beach.public_view(s).phase=="search" and Beach.public_view(s).remaining==1,"step before the deadline changes nothing")
	s.time=T0+300.0
	expect(Beach.public_view(s).remaining==0,"remaining reaches 0")
	refused(s,"bob",spot(t[1]),"dig:1",true,"dig at the deadline")
	refused(s,"bob",spot(t[1]),"mark:1",true,"mark at the deadline")
	refused(s,"alice",Beach.SIGN,"start",true,"start before step settles")
	expect(Beach.step(s)==true,"step settles on timeout")
	var p:=Beach.public_view(s)
	expect(p.phase=="results" and p.reason=="time" and p.score==3 and p.found.size()==1 and p.remaining==0,"timeout results")
	expect(s.players.alice[KEY]==true,"digger keeps keepsake on timeout")
	expect(not s.players.bob.has(KEY),"non-digger gets nothing on timeout")
	expect(Beach.step(s)==false,"step is idempotent")
	expect(Beach.valid(s),"valid after timeout")
	s.time=T0+4000.0
	expect(Beach.step(s)==false and Beach.public_view(s).reason=="time","time passing later changes nothing")
	expect(start(s,"bob").ok==true and rid(s)==2 and Beach.public_view(s).remaining==300,"restart after timeout counts from the new time")
	# a loss with no digs gives nothing at all
	var s2:=world()
	start(s2)
	s2.time=T0+301.0
	expect(Beach.step(s2)==true and Beach.public_view(s2).score==0 and not s2.players.alice.has(KEY),"nobody dug: no keepsake")
	expect(Beach.valid(s2),"valid empty loss")
	# step on empty / idle states
	expect(Beach.step(world())==false and Beach.step({})==false,"step without a round")

func stale_ids()->void:
	var s:=world()
	start(s)
	for bad in ["join:0","join:2","join:01","join:+1","join:-1","join:1 ","join: 1","join:1.0","join:99999999999","join:"]:
		refused(s,"bob",Beach.SIGN,bad,true,"bad round '%s'"%bad)
	refused(s,"alice",spot("a"),"dig:2",true,"dig future round")
	refused(s,"alice",spot("a"),"mark:0",true,"mark round 0")
	refused(s,"alice",Beach.SIGN,"leave:2",true,"leave future round")
	for id in targets(s):dig(s,"alice",id)
	expect(start(s).ok==true and rid(s)==2,"round 2")
	refused(s,"alice",spot("a"),"dig:1",true,"dig an old round")
	refused(s,"bob",Beach.SIGN,"join:1",true,"join an old round")
	refused(s,"alice",spot("a"),"mark:1",true,"mark an old round")
	refused(s,"alice",Beach.SIGN,"leave:1",true,"leave an old round")
	expect(join(s,"bob").ok==true and dig(s,"bob","a",2).ok==true,"current round id works")
	# nothing started yet: every id is stale
	var fresh:=world()
	refused(fresh,"alice",spot("a"),"dig:1",true,"dig with no round")
	refused(fresh,"alice",Beach.SIGN,"join:1",true,"join with no round")
	expect(not fresh.has(KEY),"no round was written")

func keepsake_rules()->void:
	# first completion only: the flag is a plain true and a second round adds nothing
	var s:=world()
	start(s)
	var d:=decoys(s)
	dig(s,"alice",d[0])
	join(s,"bob")
	for id in targets(s):dig(s,"bob",id)
	expect(s.players.alice[KEY]==true and s.players.bob[KEY]==true,"wrong digger and finder both rewarded")
	expect(s.players.alice[KEY] is bool and s.players.bob[KEY] is bool,"keepsake is a boolean")
	var before_keys:int=s.players.alice.keys().size()
	start(s)
	for id in targets(s):dig(s,"alice",id)
	expect(s.players.alice[KEY]==true and s.players.alice.keys().size()==before_keys,"no duplicate keepsake")
	expect(not s.players.has("carol") or not s.players.carol.has(KEY),"outsider has none")
	expect(Beach.view(s,"alice").can_start==true and Beach.view(s,"alice").completed==true,"completed player may replay")

func privacy()->void:
	var s:=world()
	start(s)
	join(s,"bob")
	mark(s,"alice","a")
	var t:=targets(s)
	var p:=Beach.public_view(s)
	var text:=JSON.stringify(p)
	for token in ["alice","bob","carol"]:expect(not text.contains(token),"public view hides token %s"%token)
	expect(not p.has("members") and not p.has("wrong") and not p.has("participants") and not p.has("targets"),"no member or secret fields")
	expect(p.found.is_empty(),"unfound targets are not revealed")
	var v:=Beach.view(s,"alice")
	expect(not JSON.stringify(v).contains("bob") and not v.has("targets"),"own view has no secrets")
	expect(Beach.public_view(s)==Beach.public_view(s.duplicate(true)),"public view is deterministic")
	dig(s,"alice",t[0])
	p=Beach.public_view(s)
	expect(p.found.size()==1 and p.found.has(t[0]),"only found ids appear")
	# a decoy dig shows only under searched, never under found
	dig(s,"alice",decoys(s)[0])
	expect(Beach.public_view(s).found.size()==1 and Beach.public_view(s).searched.size()==1,"decoy dig is searched, not found")

func economy_untouched()->void:
	var s:=world()
	var original:=s.duplicate(true)
	start(s)
	join(s,"bob")
	var d:=decoys(s)
	dig(s,"alice",d[0])
	mark(s,"bob","a")
	for id in targets(s):dig(s,"bob",id)
	expect(Beach.public_view(s).phase=="results","economy round finished")
	for token in ["alice","bob","carol"]:
		var p:Dictionary=s.players[token]
		var o:Dictionary=original.players[token]
		expect(p.coins==o.coins and p.bag==o.bag and p.inventory==o.inventory and p.name==o.name,"%s economy untouched"%token)
		for field in p:
			if field not in ["x","y",KEY]:expect(o.has(field),"%s gained no field %s"%[token,field])
	expect(s.crops==original.crops and s.community==original.community,"world data untouched")
	var keys:=s.keys()
	keys.erase(KEY)
	var okeys:=original.keys()
	keys.sort()
	okeys.sort()
	expect(keys==okeys,"only beach_treasure was added to the state")

func mutated(base:Dictionary,label:String,mut:Callable)->void:
	var s:=base.duplicate(true)
	mut.call(s)
	expect(not Beach.valid(s),"invalid: "+label)

func validation()->void:
	var base:=world()
	start(base)
	join(base,"bob")
	mark(base,"alice","b")
	var t:=targets(base)
	var d:=decoys(base)
	dig(base,"alice",d[0])
	dig(base,"alice",t[0])
	expect(Beach.valid(base),"base valid")
	var results:=base.duplicate(true)
	dig(results,"bob",t[1])
	dig(results,"bob",t[2])
	expect(results[KEY].phase=="results" and Beach.valid(results),"results valid")
	var timed:=base.duplicate(true)
	timed.time=T0+400.0
	Beach.step(timed)
	expect(timed[KEY].reason=="time" and Beach.valid(timed),"timed results valid")
	mutated(base,"missing players",func(s):s.erase("players"))
	mutated(base,"no picnic",func(s):s.picnic=false)
	mutated(base,"not a dict",func(s):s[KEY]=[])
	mutated(base,"extra key",func(s):s[KEY]["extra"]=1)
	for field in Beach.SHARED_KEYS:
		mutated(base,"missing "+field,func(s):s[KEY].erase(field))
	mutated(base,"round 0",func(s):s[KEY].round=0)
	mutated(base,"round fraction",func(s):s[KEY].round=1.5)
	mutated(base,"round huge",func(s):s[KEY].round=2000000000)
	mutated(base,"round string",func(s):s[KEY].round="1")
	mutated(base,"phase idle",func(s):s[KEY].phase="idle")
	mutated(base,"phase junk",func(s):s[KEY].phase="done")
	mutated(base,"reason junk",func(s):s[KEY].reason="lost")
	mutated(base,"search with reason",func(s):s[KEY].reason="time")
	mutated(base,"started future",func(s):s[KEY].started=T0+500.0)
	mutated(base,"started negative",func(s):s[KEY].started=-1.0)
	mutated(base,"started string",func(s):s[KEY].started="0")
	mutated(base,"no members",func(s):s[KEY].members={})
	mutated(base,"members not dict",func(s):s[KEY].members=["alice"])
	mutated(base,"unknown member",func(s):s[KEY].members["ghost"]={"joined":true,"dug":false})
	mutated(base,"member bad flag",func(s):s[KEY].members.alice.joined=1)
	mutated(base,"member extra field",func(s):s[KEY].members.alice["x"]=1)
	mutated(base,"member missing field",func(s):s[KEY].members.alice.erase("dug"))
	mutated(base,"nine members",func(s):
		for i in range(9):
			s.players["x%d"%i]=person()
			s[KEY].members["x%d"%i]={"joined":true,"dug":false})
	mutated(base,"found decoy",func(s):s[KEY].found[d[1]]=true)
	mutated(base,"wrong target",func(s):s[KEY].wrong[t[1]]=true)
	mutated(base,"found unknown id",func(s):s[KEY].found["z"]=true)
	mutated(base,"found false",func(s):s[KEY].found[t[0]]=false)
	mutated(base,"marks unknown id",func(s):s[KEY].marks["z"]=true)
	mutated(base,"marks not true",func(s):s[KEY].marks["a"]=1)
	mutated(base,"found without any digger",func(s):
		s[KEY].members.alice.dug=false
		s[KEY].members.bob.dug=false)
	mutated(base,"all found while searching",func(s):
		s[KEY].found[t[1]]=true
		s[KEY].found[t[2]]=true)
	mutated(base,"personal true string",func(s):s.players.alice[KEY]="true")
	mutated(base,"personal int",func(s):s.players.bob[KEY]=1)
	mutated(base,"personal false",func(s):s.players.bob[KEY]=false)
	mutated(results,"goal with missing treasure",func(s):s[KEY].found.erase(t[2]))
	mutated(results,"goal without keepsake",func(s):s.players.alice.erase(KEY))
	mutated(results,"results without reason",func(s):s[KEY].reason="")
	mutated(timed,"time loss with all found",func(s):
		for id in t:s[KEY].found[id]=true)
	mutated(timed,"timed digger lost keepsake",func(s):s.players.alice.erase(KEY))
	var personal_only:=world()
	personal_only.players.alice[KEY]=true
	expect(Beach.valid(personal_only),"personal keepsake alone is valid")
	var stray:=world(T0,false)
	stray.players.alice[KEY]=true
	expect(Beach.valid(stray),"personal true needs no picnic check")
	# corrupted shared record: actions refuse and change nothing
	var broken:=base.duplicate(true)
	broken[KEY].phase="done"
	refused(broken,"alice",spot(t[1]),"dig:1",true,"corrupt record")
	expect(Beach.public_view(broken).phase=="idle" and Beach.view(broken,"alice").can_start==false and Beach.step(broken)==false,"corrupt record is ignored by views and step")

func save_roundtrip()->void:
	var s:=world()
	start(s)
	join(s,"bob")
	mark(s,"alice","c")
	var d:=decoys(s)
	var t:=targets(s)
	dig(s,"alice",d[0])
	dig(s,"bob",t[0])
	s.time=T0+75.0
	var expected_public:=Beach.public_view(s)
	var loaded:Variant=JSON.parse_string(JSON.stringify(s))
	expect(loaded is Dictionary and Beach.valid(loaded),"JSON round trip valid")
	expect(loaded[KEY].round is int,"round normalized to int")
	var lp:=Beach.public_view(loaded)
	expect(lp.round==expected_public.round and lp.phase=="search" and lp.score==3 and lp.guests==2,"loaded public basics")
	expect(lp.found==expected_public.found and lp.marks==expected_public.marks,"loaded found and marks")
	expect(clue_strings(loaded)==clue_strings(s) and lp.remaining==expected_public.remaining,"loaded clues and time")
	expect(Beach.view(loaded,"alice").joined==true and Beach.view(loaded,"alice").dug==true,"loaded private view")
	# play continues after the reload, and a restart of the server never rewinds time
	expect(dig(loaded,"alice",t[1]).ok==true and dig(loaded,"bob",t[2]).ok==true,"keeps playing after load")
	expect(Beach.public_view(loaded).phase=="results" and Beach.valid(loaded),"finishes after load")
	expect(loaded.players.alice[KEY]==true and loaded.players.bob[KEY]==true,"keepsakes saved")
	var again:Variant=JSON.parse_string(JSON.stringify(loaded))
	expect(again is Dictionary and Beach.valid(again) and Beach.public_view(again).reason=="goal","results survive a second round trip")
	# a save written mid-round and loaded after the deadline settles on the next step
	var late:Variant=JSON.parse_string(JSON.stringify(s))
	late.time=T0+999.0
	expect(Beach.valid(late) and Beach.step(late)==true and Beach.public_view(late).reason=="time","overdue save settles by step")
	expect(late.players.alice[KEY]==true and late.players.bob[KEY]==true,"overdue save awards diggers")
