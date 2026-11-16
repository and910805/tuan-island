extends SceneTree
## Staged apprentice fix: escrowed kit returns, fair waiting list, disconnect
## handling, save validation/normalisation and privacy. Patched core only.

const SP=preload("res://scripts/salt_pan.gd")
const F=preload("res://tests/salt_apprentice_fixture.gd")
const LATE:=F.LATE
const TENTH:=F.TENTH
const ELEVENTH:=F.ELEVENTH
const TWELFTH:=F.TWELFTH
var checks:=0
var failures:=0

func expect(c:bool,detail:String) -> void:
	checks+=1
	if not c:
		failures+=1
		print("FAIL: "+detail)

func rejects(s:Dictionary,token:String,action:String,p:Vector2i,extra:String,needle:String,detail:String) -> void:
	var before:=s.duplicate(true)
	var r:=F.act(s,token,action,p,extra)
	expect(not r.ok and (needle=="" or str(r.message).contains(needle)) and s==before,"%s (got %s)"%[detail,str(r)])

func accepts(s:Dictionary,token:String,action:String,p:Vector2i,extra:String,detail:String) -> Dictionary:
	var r:=F.act(s,token,action,p,extra)
	expect(r.ok,"%s (got %s)"%[detail,str(r)])
	return r

func broken(s:Dictionary,change:Callable,detail:String) -> void:
	var copy:=s.duplicate(true)
	change.call(copy)
	var verdict=SP.valid(copy)
	expect(verdict is bool and verdict==false,"valid rejects: "+detail)

func app() -> Vector2i:
	return F.pan_cell(18)

func wheel9() -> Vector2i:
	return SP.wheel_socket(9).position

func rake9() -> Vector2i:
	return SP.rake_socket(9).position

func _initialize() -> void:
	shape_checks()
	escrow_checks()
	claim_checks()
	fairness_checks()
	disconnect_checks()
	list_maintenance_checks()
	equivalence_checks()
	atomic_checks()
	validation_checks()
	privacy_checks()
	milestone_checks()
	print("APPRENTICE_FIX_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ---------------------------------------------------------------- shape

func shape_checks() -> void:
	expect(SP.ROOT_KEYS==["players","gates","givers","repaired_at","pans","lots","apprentice","coop_box","kit_box","waitlist"],"root keys")
	var fresh:=SP.fresh()
	expect(fresh.kit_box=={} and fresh.waitlist=={"order":[],"offer_at":0.0},"fresh defaults")
	expect(SP.ACTIONS.size()==15 and SP.ACTIONS[5]=="salt_claim" and SP.ACTIONS[14]=="salt_box_take","no new action, ids unchanged")
	for a in SP.ACTIONS:expect(a.length()<=16,"action length "+a)
	expect(SP.LOT_COUNT==8 and SP.PUBLIC_LOT==8 and SP.APPRENTICE_LOT==9 and SP.PAN_COUNT==20 and SP.SAVE_VERSION==26,"lot layout + version unchanged")
	expect(SP.OFFER_SECONDS>0.0 and SP.OFFER_SECONDS<SP.SHIFT_SECONDS,"offer window bounded")
	var s:=F.saturated()
	expect(SP.valid(s.duplicate(true)),"saturated fixture valid")
	var json:Dictionary=JSON.parse_string(JSON.stringify(s))
	expect(SP.valid(json),"saturated JSON round trip valid")

# ---------------------------------------------------------------- escrow

## LATE tenant with wheel+rake installed; returns time of take.
func tenant_with_kits(s:Dictionary) -> float:
	var t:=float(s.time)
	accepts(s,LATE,"salt_claim",app(),"","take shift")
	F.bag(s,LATE).merge({"salt_wheel_kit":1,"salt_rake_kit":1},true)
	accepts(s,LATE,"salt_install",wheel9(),"wheel","wheel")
	s.salt_pan.players[LATE].wheel_raked=1
	accepts(s,LATE,"salt_install",rake9(),"rake","rake")
	return t

func escrow_checks() -> void:
	# release at LIMIT, both kits
	var s:=F.saturated()
	tenant_with_kits(s)
	F.bag(s,LATE).merge({"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":SP.LIMIT},true)
	var lots_json:=JSON.stringify(s.salt_pan.lots)
	var w:=F.kit_total(s,"salt_wheel_kit")
	var rk:=F.kit_total(s,"salt_rake_kit")
	var rec_before:Dictionary=s.salt_pan.players[LATE].duplicate(true)
	var r:=accepts(s,LATE,"salt_release",app(),"","release at LIMIT")
	expect(s.salt_pan.apprentice==SP.fresh_apprentice(),"station reset")
	expect(s.salt_pan.kit_box.get(LATE)=={"salt_wheel_kit":1,"salt_rake_kit":1},"both kits escrowed")
	expect(r.message.contains("合作社收鹽箱"),"message names the escrow")
	expect(F.kit_total(s,"salt_wheel_kit")==w and F.kit_total(s,"salt_rake_kit")==rk,"release conserves kits")
	expect(s.salt_pan.players[LATE]==rec_before,"release keeps record progress")
	expect(JSON.stringify(s.salt_pan.lots)==lots_json,"private lots untouched")
	expect(SP.valid(s.duplicate(true)),"valid with escrow")
	# mixed: wheel fits, rake does not
	var m:=F.saturated()
	tenant_with_kits(m)
	F.bag(m,LATE).merge({"salt_wheel_kit":3,"salt_rake_kit":SP.LIMIT},true)
	accepts(m,LATE,"salt_release",app(),"","mixed release")
	expect(int(F.bag(m,LATE).salt_wheel_kit)==4 and m.salt_pan.kit_box.get(LATE)=={"salt_wheel_kit":0,"salt_rake_kit":1},"inventory first, only overflow escrowed")
	# expiry at LIMIT inside step: released at the exact expiry instant
	var e:=F.saturated()
	var since:=tenant_with_kits(e)
	F.bag(e,LATE).merge({"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":SP.LIMIT},true)
	accepts(e,TENTH,"salt_claim",app(),"","10th waits")
	var r2:=SP.step(e,float(e.time),since+SP.SHIFT_SECONDS+100.0,F.objs(e))
	e.time=since+SP.SHIFT_SECONDS+100.0
	expect(r2.ok and r2.changed and e.salt_pan.apprentice.tenant=="","expiry releases in step")
	expect(float(e.salt_pan.waitlist.offer_at)==since+SP.SHIFT_SECONDS,"waiter's window opens at the exact expiry instant")
	expect(SP.escrow_of(e,LATE)=={"salt_wheel_kit":1,"salt_rake_kit":1} and int(F.bag(e,LATE).salt_wheel_kit)==SP.LIMIT,"expiry escrows, inventory stays at LIMIT")
	expect(SP.valid(e.duplicate(true)),"valid after expiry at LIMIT")
	accepts(e,TENTH,"salt_claim",app(),"","waiter takes the freed shift")
	# graduation at LIMIT
	var g:=F.saturated()
	tenant_with_kits(g)
	accepts(g,LATE,"salt_auto_cfg",rake9(),"47,23|30","cfg")
	accepts(g,LATE,"salt_auto_toggle",rake9(),"","on")
	F.bag(g,LATE).merge({"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":SP.LIMIT},true)
	var salt0:=F.salt_total(g)
	F.tick(g,float(g.time)+3.0*F.DAY)
	expect(int(g.salt_pan.players[LATE].auto_raked)==1 and g.salt_pan.apprentice.tenant=="","graduation releases at LIMIT")
	expect(SP.escrow_of(g,LATE)=={"salt_wheel_kit":1,"salt_rake_kit":1},"graduation escrows")
	expect(F.salt_total(g)==salt0+3,"exactly one automatic delivery of 3 salt")
	expect(SP.valid(g.duplicate(true)),"valid after graduation at LIMIT")
	# later claim: partial fit, then all fit, salt + kits
	g.salt_pan.kit_box[LATE]={"salt_wheel_kit":3,"salt_rake_kit":2}
	g.salt_pan.coop_box[LATE]=7
	F.bag(g,LATE).merge({"salt_wheel_kit":SP.LIMIT-1,"salt_rake_kit":0,"sea_salt":SP.LIMIT-4},true)
	var w0:=F.kit_total(g,"salt_wheel_kit")
	var r0:=F.kit_total(g,"salt_rake_kit")
	var s0:=F.salt_total(g)
	var part:=accepts(g,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","partial take")
	expect(int(F.bag(g,LATE).salt_wheel_kit)==SP.LIMIT and int(F.bag(g,LATE).salt_rake_kit)==2 and int(F.bag(g,LATE).sea_salt)==SP.LIMIT,"each item filled to LIMIT")
	expect(g.salt_pan.kit_box[LATE]=={"salt_wheel_kit":2,"salt_rake_kit":0} and int(g.salt_pan.coop_box[LATE])==3,"remainder stays in the compartment")
	expect(part.message.contains("先留在箱裡"),"partial message")
	expect(F.kit_total(g,"salt_wheel_kit")==w0 and F.kit_total(g,"salt_rake_kit")==r0 and F.salt_total(g)==s0,"partial take conserves")
	expect(SP.valid(g.duplicate(true)),"valid after partial take")
	rejects(g,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","上限","nothing fits -> refused, unchanged")
	F.bag(g,LATE).merge({"salt_wheel_kit":0,"sea_salt":0},true)
	accepts(g,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","full take")
	expect(not g.salt_pan.kit_box.has(LATE) and not g.salt_pan.coop_box.has(LATE),"compartment emptied")
	expect(int(F.bag(g,LATE).salt_wheel_kit)==2 and int(F.bag(g,LATE).sea_salt)==3,"all fit")
	expect(F.kit_total(g,"salt_wheel_kit")==w0-SP.LIMIT,"conservation after inventory edit (LIMIT removed by fixture)")
	rejects(g,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","沒有你的海鹽","empty compartment")
	# foreign / unknown access
	g.salt_pan.kit_box[LATE]={"salt_wheel_kit":1,"salt_rake_kit":0}
	rejects(g,TENTH,"salt_box_take",SP.APPRENTICE_CHEST,"","沒有你的","others cannot take escrow")
	rejects(g,F.OUTSIDER,"salt_box_take",SP.APPRENTICE_CHEST,"","","player without record refused")
	rejects(g,"ghost-token","salt_box_take",SP.APPRENTICE_CHEST,"","","unknown token refused")
	rejects(g,LATE,"salt_box_take",Vector2i(46,23),"","","take only at the cooperative chest")
	# install guard keeps the shift end total
	var h:=F.saturated()
	accepts(h,LATE,"salt_claim",app(),"","take")
	h.salt_pan.kit_box[LATE]={"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":0}
	F.bag(h,LATE).salt_wheel_kit=1
	rejects(h,LATE,"salt_install",wheel9(),"wheel","已達上限","install refused when escrow has no room")
	h.salt_pan.kit_box[LATE].salt_wheel_kit=SP.LIMIT-1
	accepts(h,LATE,"salt_install",wheel9(),"wheel","install with escrow room")
	F.bag(h,LATE).salt_wheel_kit=SP.LIMIT
	accepts(h,LATE,"salt_release",app(),"","release with escrow at LIMIT-1")
	expect(int(h.salt_pan.kit_box[LATE].salt_wheel_kit)==SP.LIMIT and int(F.bag(h,LATE).salt_wheel_kit)==SP.LIMIT,"escrow reaches LIMIT, never above")
	expect(SP.valid(h.duplicate(true)),"valid with escrow at LIMIT and no shift")
	# missing player inventory (corrupt in-memory) still releases into escrow
	var x:=F.saturated()
	tenant_with_kits(x)
	x.players[LATE].erase("inventory")
	var rx:=SP.step(x,float(x.time),float(x.time)+SP.SHIFT_SECONDS+1.0,F.objs(x))
	expect(rx.ok and x.salt_pan.apprentice.tenant=="" and SP.escrow_of(x,LATE)=={"salt_wheel_kit":1,"salt_rake_kit":1},"no inventory -> escrow, never stuck")

# ---------------------------------------------------------------- claims

func claim_checks() -> void:
	var s:=F.saturated()
	var own:Array=F.owners()
	accepts(s,LATE,"salt_claim",app(),"","direct take when free and nobody waits")
	var j:=accepts(s,TENTH,"salt_claim",app(),"","join while busy")
	expect(j.message.contains("第 1 位") and s.salt_pan.waitlist.order==[{"token":TENTH,"missed":0}] and float(s.salt_pan.waitlist.offer_at)==0.0,"listed, no window while busy")
	rejects(s,TENTH,"salt_claim",app(),"","第 1 位","duplicate join is a no-op")
	rejects(s,own[0],"salt_claim",app(),"","已經有自己的鹽田區","owner cannot join")
	rejects(s,F.OUTSIDER,"salt_claim",app(),"","","player without record cannot join")
	rejects(s,LATE,"salt_claim",app(),"","正在學徒區輪班","tenant cannot join")
	s.salt_pan.players[TWELFTH].auto_raked=1
	rejects(s,TWELFTH,"salt_claim",app(),"","已經會用收鹽台","graduate cannot join")
	s.salt_pan.players[TWELFTH].auto_raked=0
	# a free private lot: no apprentice join, claim own lot instead
	var lot_owner:String=own[3]
	accepts(s,lot_owner,"salt_release",F.pan_cell(6),"","owner 3 returns lot")
	rejects(s,ELEVENTH,"salt_claim",app(),"",SP.FREE_LOT_MESSAGE,"free lot -> no join")
	accepts(s,TENTH,"salt_claim",F.pan_cell(6),"","queued player claims the freed private lot")
	expect(SP.queue_position(s,TENTH)==0 and s.salt_pan.waitlist.order.is_empty(),"lot owner leaves the list")
	expect(SP.valid(s.duplicate(true)),"valid after lot claim")

# ---------------------------------------------------------------- fairness

func fairness_checks() -> void:
	var s:=F.saturated()
	accepts(s,LATE,"salt_claim",app(),"","LATE takes")
	accepts(s,TENTH,"salt_claim",app(),"","TENTH joins")
	accepts(s,ELEVENTH,"salt_claim",app(),"","ELEVENTH joins")
	expect(SP.queue_position(s,TENTH)==1 and SP.queue_position(s,ELEVENTH)==2,"FIFO positions")
	var t:=float(s.time)
	accepts(s,LATE,"salt_release",app(),"","LATE releases")
	expect(float(s.salt_pan.waitlist.offer_at)==t,"head window starts at release")
	var again:=accepts(s,LATE,"salt_claim",app(),"","LATE asks again immediately")
	expect(s.salt_pan.apprentice.tenant=="" and SP.queue_position(s,LATE)==3 and again.message.contains("第 3 位"),"releasing player cannot jump the list")
	rejects(s,ELEVENTH,"salt_claim",app(),"","第 2 位","second in line cannot take the head's turn")
	expect(SP.apprentice_eligible(s,TENTH) and not SP.apprentice_eligible(s,LATE) and not SP.apprentice_eligible(s,ELEVENTH),"only the head is eligible")
	accepts(s,TENTH,"salt_claim",app(),"","head takes")
	expect(s.salt_pan.apprentice.tenant==TENTH and SP.queue_position(s,ELEVENTH)==1 and SP.queue_position(s,LATE)==2,"list advances")
	# round robin over several expiries: each waiter rejoins right after their shift
	var tenants:=[TENTH]
	var joined:={}
	for cycle in 6:
		var since:=float(s.salt_pan.apprentice.since)
		var before:=str(s.salt_pan.apprentice.tenant)
		F.tick(s,since+SP.SHIFT_SECONDS)
		expect(s.salt_pan.apprentice.tenant=="","cycle %d expiry"%cycle)
		accepts(s,before,"salt_claim",app(),"","%s rejoins at the back"%before)
		joined[before]=[float(s.time),SP.queue_position(s,before)]
		var head:=str(s.salt_pan.waitlist.order[0].token)
		accepts(s,head,"salt_claim",app(),"","head takes in cycle %d"%cycle)
		expect(head!=before,"cycle %d: same player never takes twice in a row while others wait"%cycle)
		if joined.has(head):
			var waited:=float(s.time)-float(joined[head][0])
			expect(waited<=float(joined[head][1])*SP.SHIFT_SECONDS,"cycle %d: %s waited %s <= position %d x shift"%[cycle,head,waited,joined[head][1]])
		tenants.append(head)
	expect(tenants==[TENTH,ELEVENTH,LATE,TENTH,ELEVENTH,LATE,TENTH],"strict rotation %s"%[tenants])
	expect(SP.valid(s.duplicate(true)),"valid after rotation")
	# a lone player with nobody waiting may re-take (no artificial lockout)
	var solo:=F.saturated()
	accepts(solo,LATE,"salt_claim",app(),"","solo take")
	F.tick(solo,float(solo.salt_pan.apprentice.since)+SP.SHIFT_SECONDS)
	accepts(solo,LATE,"salt_claim",app(),"","solo re-take when nobody waits")

# ---------------------------------------------------------------- disconnects

func disconnect_checks() -> void:
	var s:=F.saturated()
	accepts(s,LATE,"salt_claim",app(),"","LATE takes")
	for who in [TENTH,ELEVENTH,TWELFTH]:accepts(s,who,"salt_claim",app(),"",who+" joins")
	var t0:=float(s.time)
	accepts(s,LATE,"salt_release",app(),"","LATE releases; TENTH offered")
	var view:=SP.own_view(s,TENTH,F.objs(s),t0)
	expect(view.apprentice.offer and view.apprentice.eligible and view.apprentice.offer_minutes==int(SP.OFFER_SECONDS/60.0),"head view shows the offer")
	# world time pause: no steps -> no lapse, however long the server is empty
	var paused:=s.duplicate(true)
	expect(SP.apprentice_eligible(paused,TENTH),"window holds while time is paused")
	# TENTH disconnected: window lapses at t0+OFFER exactly
	F.tick(s,t0+SP.OFFER_SECONDS-1.0)
	expect(str(s.salt_pan.waitlist.order[0].token)==TENTH,"window still open before lapse")
	F.tick(s,t0+SP.OFFER_SECONDS)
	var order:Array=s.salt_pan.waitlist.order
	expect(str(order[0].token)==ELEVENTH and str(order[2].token)==TENTH and int(order[2].missed)==1,"first miss -> back of the list")
	expect(float(s.salt_pan.waitlist.offer_at)==t0+SP.OFFER_SECONDS,"next head's window opens at the lapse")
	expect(SP.valid(s.duplicate(true)),"valid after a lapse")
	# TENTH comes back while not head: confirms presence, keeps place
	accepts(s,TENTH,"salt_claim",app(),"","returning waiter confirms presence")
	expect(int(s.salt_pan.waitlist.order[2].missed)==0 and SP.queue_position(s,TENTH)==3,"missed cleared, place kept")
	# everyone disconnected: each head lapses twice then is removed -> list empties, station free
	F.tick(s,float(s.time)+SP.OFFER_SECONDS*12.0)
	expect(s.salt_pan.waitlist.order.is_empty() and float(s.salt_pan.waitlist.offer_at)==0.0 and s.salt_pan.apprentice.tenant=="","bounded: absent waiters drop out, no permanent head block")
	expect(SP.valid(s.duplicate(true)),"valid after the list empties")
	accepts(s,TWELFTH,"salt_claim",app(),"","returning player takes the free station directly")
	# bounded number of lapses: each entry lapses at most twice
	var b:=F.saturated()
	accepts(b,LATE,"salt_claim",app(),"","take")
	for who in [TENTH,ELEVENTH,TWELFTH]:accepts(b,who,"salt_claim",app(),"","join")
	accepts(b,LATE,"salt_release",app(),"","release")
	var tb:=float(b.time)
	F.tick(b,tb+SP.OFFER_SECONDS*6.0-1.0)
	expect(b.salt_pan.waitlist.order.size()==1,"after 5 lapses one entry remains (got %d)"%b.salt_pan.waitlist.order.size())
	F.tick(b,tb+SP.OFFER_SECONDS*6.0)
	expect(b.salt_pan.waitlist.order.is_empty(),"3 waiters x 2 misses = 6 windows max")

# ---------------------------------------------------------------- list upkeep

func list_maintenance_checks() -> void:
	var s:=F.saturated()
	accepts(s,LATE,"salt_claim",app(),"","take")
	accepts(s,TENTH,"salt_claim",app(),"","join")
	accepts(s,ELEVENTH,"salt_claim",app(),"","join")
	accepts(s,LATE,"salt_release",app(),"","release")
	s.time=float(s.time)+100.0
	var left:=accepts(s,TENTH,"salt_release",app(),"","head leaves the list")
	expect(left.message.contains("離開"),"leave message")
	expect(SP.queue_position(s,TENTH)==0 and str(s.salt_pan.waitlist.order[0].token)==ELEVENTH and float(s.salt_pan.waitlist.offer_at)==float(s.time),"new head gets a full window from now")
	rejects(s,TENTH,"salt_release",app(),"","沒有在學徒區","not listed, not tenant")
	accepts(s,ELEVENTH,"salt_release",app(),"","last waiter leaves")
	expect(s.salt_pan.waitlist=={"order":[],"offer_at":0.0},"empty list resets the window")
	expect(SP.valid(s.duplicate(true)),"valid after leaving")

# ---------------------------------------------------------------- equivalence

func equivalence_checks() -> void:
	var s:=F.saturated()
	accepts(s,LATE,"salt_claim",app(),"","take")
	F.bag(s,LATE).merge({"salt_wheel_kit":1,"salt_rake_kit":1},true)
	accepts(s,LATE,"salt_install",wheel9(),"wheel","wheel")
	F.bag(s,LATE).salt_wheel_kit=SP.LIMIT
	for who in [TENTH,ELEVENTH]:accepts(s,who,"salt_claim",app(),"","join")
	var t0:=float(s.time)
	var span:=SP.SHIFT_SECONDS+SP.OFFER_SECONDS*4.0+5.0
	var one:=s.duplicate(true)
	var many:=s.duplicate(true)
	var r:=SP.step(one,t0,t0+span,F.objs(one))
	one.time=t0+span
	var all_ok:=true
	for k in int(span):
		if not SP.step(many,t0+float(k),t0+float(k+1),F.objs(many)).ok:all_ok=false
	many.time=t0+span
	expect(r.ok and all_ok,"steps ok")
	expect(var_to_bytes(one.salt_pan)==var_to_bytes(many.salt_pan),"expiry+escrow+lapses bit-identical one vs %d steps"%int(span))
	expect(var_to_bytes(one.players)==var_to_bytes(many.players),"inventories bit-identical")
	expect(one.salt_pan.waitlist.order.is_empty() and SP.escrow_of(one,LATE).salt_wheel_kit==1,"expected end state")
	var json:Dictionary=JSON.parse_string(JSON.stringify(one))
	expect(SP.valid(json),"reload valid")
	var a:=one.duplicate(true)
	var bin:Dictionary=bytes_to_var(var_to_bytes(one))
	SP.step(a,float(a.time),float(a.time)+F.DAY,F.objs(a))
	SP.step(json,float(json.time),float(json.time)+F.DAY,F.objs(json))
	SP.step(bin,float(bin.time),float(bin.time)+F.DAY,F.objs(bin))
	# JSON sorts keys, so compare typed content (order-insensitive) for JSON and bytes for binary.
	expect(same(a.salt_pan,json.salt_pan),"JSON-reloaded copy continues identically (typed deep compare)")
	expect(var_to_bytes(a.salt_pan)==var_to_bytes(bin.salt_pan),"binary-reloaded copy continues bit-identically")

## Typed, key-order-insensitive deep equality (int 1 != float 1.0).
func same(x:Variant,y:Variant) -> bool:
	if typeof(x)!=typeof(y):return false
	if x is Dictionary:
		if x.size()!=y.size():return false
		for k in x:
			if not y.has(k) or not same(x[k],y[k]):return false
		return true
	if x is Array:
		if x.size()!=y.size():return false
		for i in x.size():
			if not same(x[i],y[i]):return false
		return true
	return x==y

# ---------------------------------------------------------------- atomicity

func atomic_checks() -> void:
	var s:=F.saturated()
	var since:=tenant_with_kits(s)
	F.bag(s,LATE).merge({"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":5},true)
	accepts(s,TENTH,"salt_claim",app(),"","join")
	s.salt_pan.pans[0]={"s":"brine","p":NAN,"t":0.0,"f":"hand"}
	var snap:=str(s)
	var r:=SP.step(s,float(s.time),since+SP.SHIFT_SECONDS+1.0,F.objs(s))
	expect(not r.ok and str(s)==snap,"failing step leaves station, escrow, list and inventory untouched")
	var t:=F.saturated()
	tenant_with_kits(t)
	t.salt_pan.kit_box[LATE]={"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":0}
	var snap2:=t.duplicate(true)
	var r2:=SP.step(t,float(t.time),float(t.time)+SP.SHIFT_SECONDS+1.0,F.objs(t))
	expect(not r2.ok and t==snap2,"step refuses a state whose escrow cannot hold the shift's kits")

# ---------------------------------------------------------------- validation

func validation_checks() -> void:
	var s:=F.saturated()
	tenant_with_kits(s)
	for who in [TENTH,ELEVENTH]:accepts(s,who,"salt_claim",app(),"","join")
	s.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":2,"salt_rake_kit":0}
	expect(SP.valid(s.duplicate(true)),"busy list fixture valid")
	var json:Dictionary=JSON.parse_string(JSON.stringify(s))
	expect(SP.valid(json),"JSON round trip valid")
	expect(json.salt_pan.kit_box[TWELFTH].salt_wheel_kit is int and json.salt_pan.waitlist.order[0].missed is int and json.salt_pan.waitlist.offer_at is float,"normalised types")
	var again:Dictionary=JSON.parse_string(JSON.stringify(json))
	SP.valid(again)
	expect(var_to_bytes(again.salt_pan)==var_to_bytes(json.salt_pan),"normalise is idempotent")
	broken(s,func(c):c.salt_pan.erase("kit_box"),"missing kit_box")
	broken(s,func(c):c.salt_pan.erase("waitlist"),"missing waitlist")
	broken(s,func(c):c.salt_pan.kit_box=[],"kit_box not dict")
	broken(s,func(c):c.salt_pan.kit_box["ghost"]={"salt_wheel_kit":1,"salt_rake_kit":0},"escrow of unknown player")
	broken(s,func(c):c.salt_pan.kit_box[F.OUTSIDER]={"salt_wheel_kit":1,"salt_rake_kit":0},"escrow without record")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":0,"salt_rake_kit":0},"empty escrow stored")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":1},"escrow missing id")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":1,"salt_rake_kit":0,"sea_salt":1},"escrow foreign item")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":1.5,"salt_rake_kit":0},"fractional escrow")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":-1,"salt_rake_kit":2},"negative escrow")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":SP.LIMIT+1,"salt_rake_kit":0},"escrow over LIMIT")
	broken(s,func(c):c.salt_pan.kit_box[TWELFTH]=3,"escrow not dict")
	broken(s,func(c):c.salt_pan.kit_box[LATE]={"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":0},"installed kit without escrow room")
	broken(s,func(c):c.salt_pan.waitlist.extra=1,"waitlist extra key")
	broken(s,func(c):c.salt_pan.waitlist.order={},"order not array")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":TENTH,"missed":0}),"duplicate waiter")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":LATE,"missed":0}),"tenant listed")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":F.owners()[0],"missed":0}),"lot owner listed")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":"ghost","missed":0}),"unknown waiter")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":F.OUTSIDER,"missed":0}),"waiter without record")
	broken(s,func(c):c.salt_pan.waitlist.order.append({"token":"","missed":0}),"empty token")
	broken(s,func(c):c.salt_pan.waitlist.order[0].missed=2,"missed above 1")
	broken(s,func(c):c.salt_pan.waitlist.order[0].missed=0.5,"fractional missed")
	broken(s,func(c):c.salt_pan.waitlist.order[0].extra=1,"entry extra key")
	broken(s,func(c):c.salt_pan.waitlist.order[0]=TENTH,"entry not dict")
	broken(s,func(c):c.salt_pan.players[TENTH].auto_raked=1,"graduate listed")
	broken(s,func(c):c.salt_pan.waitlist.offer_at=5.0,"window while busy")
	broken(s,func(c):c.salt_pan.waitlist.offer_at=NAN,"window NaN")
	var free:=s.duplicate(true)
	F.act(free,LATE,"salt_release",app())
	expect(SP.valid(free.duplicate(true)) and float(free.salt_pan.waitlist.offer_at)==float(free.time),"free station with window valid")
	broken(free,func(c):c.salt_pan.waitlist.offer_at=float(c.time)+1.0,"window in the future")
	broken(free,func(c):c.salt_pan.waitlist.offer_at=-1.0,"negative window")
	var fresh:=F.saturated()
	broken(fresh,func(c):c.salt_pan.waitlist.offer_at=1.0,"window with empty list")
	# old saves: migration creates SaltPan.fresh() (new keys included) and
	# legacy_clean still rejects forward ids; nothing new is required of them.
	var old:={"time":5.0,"players":{"p":F.person()},"objects":{},"regions":{}}
	old.players.p.region="home"
	old.players.p.travel_book.visited.erase("beimen")
	expect(SP.legacy_clean(old),"legacy save still clean")
	old.salt_pan=SP.fresh()
	expect(SP.valid(old),"migrated legacy save (fresh salt_pan) valid")

# ---------------------------------------------------------------- privacy

func privacy_checks() -> void:
	var s:=F.saturated()
	tenant_with_kits(s)
	for who in [TENTH,ELEVENTH]:accepts(s,who,"salt_claim",app(),"","join")
	s.salt_pan.kit_box[TWELFTH]={"salt_wheel_kit":2,"salt_rake_kit":1}
	var pub:=SP.public(s,float(s.time))
	expect(pub.keys()==["gates","needs","repaired","giver_count","pans","lots","apprentice","weather"],"public keys unchanged")
	expect(pub.apprentice.keys()==["taken","wheel","rake","active","ends_at"],"public apprentice shape unchanged")
	var text:=var_to_str(pub)
	for token in F.owners()+[LATE,TENTH,ELEVENTH,TWELFTH]:expect(not text.contains(token),"public has no token "+token)
	expect(not text.contains("kit_box") and not text.contains("waitlist") and not text.contains("missed"),"public has no escrow or list")
	var v11:=SP.own_view(s,ELEVENTH,F.objs(s),float(s.time))
	expect(v11.keys()==["record","phase","guidance","lot","unit","apprentice","coop_box","free_lots","can_craft","order"],"own_view root keys unchanged")
	expect(v11.apprentice.queued and v11.apprentice.position==2 and v11.apprentice.waiting==2 and not v11.apprentice.offer and not v11.apprentice.can_join,"waiter view")
	expect(v11.apprentice.kits=={"salt_wheel_kit":0,"salt_rake_kit":0},"no foreign escrow in view")
	var v12:=SP.own_view(s,TWELFTH,F.objs(s),float(s.time))
	expect(v12.apprentice.kits=={"salt_wheel_kit":2,"salt_rake_kit":1} and v12.apprentice.can_join and not v12.apprentice.queued,"own escrow + can join")
	for v in [v11,v12]:
		var vt:=var_to_str(v)
		for token in F.owners()+[LATE,TENTH,ELEVENTH,TWELFTH]:expect(not vt.contains(token),"own_view has no token")
	var vo:=SP.own_view(s,F.owners()[0],F.objs(s),float(s.time))
	expect(not vo.apprentice.can_join and not vo.apprentice.queued,"owner cannot join")

# ---------------------------------------------------------------- milestones

func milestone_checks() -> void:
	var s:=F.saturated()
	accepts(s,LATE,"salt_claim",app(),"","take")
	expect(SP.phase(s,LATE)=="wheel","new tenant starts at wheel")
	rejects(s,LATE,"salt_install",rake9(),"rake","先裝好水車","rake needs wheel")
	F.bag(s,LATE).salt_wheel_kit=1
	accepts(s,LATE,"salt_install",wheel9(),"wheel","wheel")
	F.bag(s,LATE).salt_wheel_kit=SP.LIMIT
	var rec_before:Dictionary=s.salt_pan.players[LATE].duplicate(true)
	accepts(s,TENTH,"salt_claim",app(),"","join")
	F.tick(s,float(s.salt_pan.apprentice.since)+SP.SHIFT_SECONDS)
	var rec_after:Dictionary=s.salt_pan.players[LATE]
	expect(int(rec_after.auto_raked)==0 and int(rec_after.raked)>=int(rec_before.raked),"expiry/escrow grants no automation credit")
	expect(SP.phase(s,LATE)=="claim","ex-tenant back to claim, no bypass")
	F.bag(s,LATE).salt_wheel_kit=0
	accepts(s,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","take escrowed wheel")
	expect(s.salt_pan.players[LATE]==rec_after,"taking escrow changes no record")
	expect(s.salt_pan.pans[18].f in ["","hand"] and s.salt_pan.pans[19].f in ["","hand"],"no inherited wheel credit")
	accepts(s,TENTH,"salt_claim",app(),"","next tenant")
	expect(SP.phase(s,TENTH)=="wheel","next tenant must install its own wheel")
	expect(SP.unit_status(s,SP.PUBLIC_LOT,F.objs(s),float(s.time)).id=="reserve","public pool stays manual")
