extends SceneTree
## Two real ENet clients + server restart validation for automatic roofs.
##
## AUTHORIZED LOCAL FIXTURE: the `seed` step writes a legal home-region room and
## exact test materials straight into a temporary save. It proves the networked
## build/remove/refund/persistence wiring only; it is NOT evidence of natural play
## or of normal starting goods.
##
## Driven by work/house-rooms/network_auto_roof.py. Command args (after `--`):
##   seed  <world.json> <alpha_token> <beta_token>
##         Writes the fixture save and prints `AUTO_ROOF_FIXTURE {json}`.
##   <phase> <port> <role> <room_key> <alpha_token> <beta_token>
##     close   alpha + beta started together. Both wait until both are visible.
##             beta builds the final wall via Session.perform -> auto roofs owned by
##             beta, exact cost. alpha sees them, tries to remove beta's wall
##             (must be rejected), then leaves; beta waits for alpha to leave.
##     open    alpha alone (beta offline, confirmed via snapshot). alpha removes its
##             own wall -> auto roofs removed, refund to offline beta, alpha gets
##             only its own wall back.
##     refund  beta alone first (alpha offline, confirmed via snapshot): sees the
##             refund, prints `AUTO_ROOF_MARK refund_seen`, then stays online until
##             alpha's restored roofs appear (beta must not be charged).
##     restore alpha, started by the runner after beta's mark. Rebuilds its wall ->
##             new auto roofs owned by alpha, alpha pays; waits for beta to leave.
##     persist after a normal server stop + restart. beta first (prints
##             `AUTO_ROOF_MARK joined`), then alpha. Both verify persisted owners,
##             auto flags and inventories; alpha waits for beta to leave.
## Every client checks every snapshot and result text for raw profile tokens.
## Output: `AUTO_ROOF_CHECK ok ...` per check, `AUTO_ROOF_ENET_PASS ...` or
## `AUTO_ROOF_ENET_FAIL ...`. Every wait has a deadline plus a global watchdog.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Enclosure=preload("res://scripts/room_enclosure.gd")

# 2x2 interior on clear home land (x46..51,y22..29 has no base resources).
const INTERIOR:=[Vector2i(48,24),Vector2i(49,24),Vector2i(48,25),Vector2i(49,25)]
const DOOR:=Vector2i(47,25)
const ALPHA_WALLS:=[Vector2i(48,23),Vector2i(49,23),Vector2i(47,24),Vector2i(50,24),Vector2i(48,26),Vector2i(49,26)]
const CLOSE:=Vector2i(50,25)      # final closing wall, built by beta
const ALPHA_WALL:=Vector2i(50,24) # alpha's wall, removed while beta is offline, then restored
const STAND:={"alpha":Vector2(51.5,23.5),"beta":Vector2(51.5,25.5)}
const PHASES:={"close":["alpha","beta"],"open":["alpha"],"refund":["beta"],"restore":["alpha"],"persist":["alpha","beta"]}
const REACH:=3.2
const CLEARANCE:=0.8
const WATCHDOG:=75.0
const JOIN_WAIT:=15.0
const ACTION_WAIT:=8.0
const PEER_WAIT:=45.0

var session:Session
var phase:=""
var role:=""
var tokens:={}
var notices:Array=[]
var snapshots:=0
var seen_both:=false
var first:Dictionary={}
var view:Dictionary={}
var leaked:=""
var checks:=0
var finished:=false

func _initialize() -> void:
	run.call_deferred()

# ---------------------------------------------------------------- helpers

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func hid(token:String) -> String:
	return token.sha256_text().left(16)

static func tracked() -> Array:
	var items:={}
	for recipe:Dictionary in [World.BUILD.wall,World.BUILD.roof]:
		for item in recipe:
			if item!="name":items[item]=true
	var out:=items.keys()
	out.sort()
	return out

## Tracked material counts per stage, derived from the real recipes and room size.
static func expected(who:String,stage:String) -> Dictionary:
	var n:=INTERIOR.size()
	var out:={}
	for item in tracked():
		var wall:=int(World.BUILD.wall.get(item,0))
		var roofs:=int(World.BUILD.roof.get(item,0))*n
		if who=="alpha":out[item]={"start":roofs,"closed":roofs,"opened":roofs+wall,"restored":0}[stage]
		else:out[item]={"start":wall+roofs,"closed":0,"opened":roofs,"restored":roofs}[stage]
	return out

static func same_cells(a:Array,b:Array) -> bool:
	if a.size()!=b.size():return false
	for i in a.size():
		if a[i]!=b[i]:return false
	return true

## Helpers read `view` when set (the first snapshot received), else the latest one.
func snap() -> Dictionary:
	if not view.is_empty():return view
	return session.snapshot if session!=null else {}

func who_is(owner:String) -> String:
	for who in tokens:
		if owner==hid(tokens[who]):return who
	return "unknown" if not owner.is_empty() else ""

func population() -> int:
	return snap().get("players",{}).size()

func inventory() -> Dictionary:
	return snap().get("players",{}).get(session.own_id,{}).get("inventory",{})

func others_of(inv:Dictionary) -> Dictionary:
	var out:=inv.duplicate(true)
	for item in tracked():out.erase(item)
	return out

func inv_is(stage:String) -> bool:
	var want:=expected(role,stage)
	var have:=inventory()
	for item in want:
		if int(have.get(item,0))!=int(want[item]):return false
	return true

func inv_text(stage:String="") -> String:
	var parts:=PackedStringArray()
	var have:Dictionary=inventory() if session!=null else {}
	for item in tracked():
		var text:="%s=%d"%[item,int(have.get(item,0))]
		if not stage.is_empty():text+="/want %d"%int(expected(role,stage)[item])
		parts.append(text)
	return " ".join(parts)

func owner_at(p:Vector2i,kind:String,layer:String="objects") -> String:
	var o=snap().get(layer,{}).get(k(p))
	if not o is Dictionary or str(o.get("type",""))!=kind:return ""
	return who_is(str(o.get("owner","")))

func floors_owned_by_alpha() -> bool:
	for c in INTERIOR:
		if owner_at(c,"floor","ground")!="alpha":return false
	return true

func room() -> Dictionary:
	return Enclosure.analyze(snap(),INTERIOR[0])

func roofed_by(who:String) -> bool:
	var r:=room()
	if not r.sealed or not same_cells(r.cells,INTERIOR):return false
	var roofs:Dictionary=snap().get("roofs",{})
	if roofs.size()!=INTERIOR.size():return false
	for c in INTERIOR:
		var roof=roofs.get(k(c))
		if not roof is Dictionary or str(roof.get("type",""))!="roof":return false
		if typeof(roof.get("auto"))!=TYPE_BOOL or not roof.auto:return false
		if who_is(str(roof.get("owner","")))!=who:return false
	return true

func no_roofs() -> bool:
	return snap().get("roofs",{}).is_empty() and not room().sealed

func roof_summary() -> String:
	if session==null:return "no session"
	var roofs:Dictionary=snap().get("roofs",{})
	var parts:=PackedStringArray()
	for key in roofs:
		var roof=roofs[key]
		if roof is Dictionary:parts.append("%s:%s:auto=%s"%[key,who_is(str(roof.get("owner",""))),str(roof.get("auto"))])
	parts.sort()
	var r:=room()
	return "roofs=%d [%s] sealed=%s gaps=%d"%[roofs.size(),", ".join(parts),str(r.sealed),int(r.gap_count)]

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("AUTO_ROOF_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if finished:return false
		if predicate.call():return true
		await create_timer(0.05).timeout
	return not finished and predicate.call()

## Real Session.perform; waits for this action's receipt and then two further
## snapshots so the post-action broadcast has been applied.
func act(action:String,p:Vector2i,extra:String) -> Dictionary:
	var index:=notices.size()
	session.perform(action,p,extra)
	var answered:bool=await until(func():return notices.size()>index,ACTION_WAIT)
	if not answered:return {"ok":false,"message":"<no receipt within %ds>"%int(ACTION_WAIT),"timeout":true}
	var mark:=snapshots
	await until(func():return snapshots>=mark+2,ACTION_WAIT)
	return notices[index]

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	if first.is_empty():first=data.duplicate(true)
	var text:=JSON.stringify(data)+"|"+id
	for who in tokens:
		if text.contains(tokens[who]):leaked="snapshot %d contains raw %s token"%[snapshots,who]
	if data.get("players",{}).size()==2:seen_both=true

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]):leaked="result text contains raw %s token"%who
	print("AUTO_ROOF_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	if ok:print("AUTO_ROOF_ENET_PASS %s %s checks=%d snapshots=%d notices=%d"%[phase,role,checks,snapshots,notices.size()])
	else:push_error("AUTO_ROOF_ENET_FAIL %s %s after %d checks: %s | %s | %s"%[phase,role,checks,step,roof_summary(),inv_text()])
	if session!=null:session.shutdown()
	# Let ENet flush the disconnect so the server sees this player leave promptly.
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=6 or not PHASES.has(args[0]) or not (args[2] in PHASES[args[0]]):
		push_error("AUTO_ROOF_ENET_FAIL usage: <phase> <port> <role> <room_key> <alpha_token> <beta_token>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	tokens={"alpha":args[4],"beta":args[5]}
	create_timer(WATCHDOG).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG)))
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	if session.join("127.0.0.1",int(args[1]),role,args[3])!=OK:
		finish(false,"ENet join request")
		return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined,"registered over ENet with protocol %d and the room key"%Session.PROTOCOL):return
	if not check(session.own_id==hid(tokens[role]),"own id is the hashed stable profile token"):return
	match phase:
		"close":
			if role=="alpha":await close_alpha()
			else:await close_beta()
		"open":await open_alpha()
		"refund":await refund_beta()
		"restore":await restore_alpha()
		"persist":await persist()
	if finished:return
	if not check(leaked.is_empty(),"no raw profile token in %d snapshots or %d result texts"%[snapshots,notices.size()]):return
	finish(true,"")

# ---------------------------------------------------------------- phases

## Judged on the FIRST snapshot this client received: in `close`, beta may build as
## soon as it sees both players, but alpha's registration snapshot is always earlier.
func verify_open_fixture() -> bool:
	view=first
	var ok:=_verify_open_fixture()
	view={}
	return ok

func _verify_open_fixture() -> bool:
	var r:=room()
	if not check(snap().get("roofs",{}).is_empty() and not r.sealed and int(r.gap_count)>0,"fixture room starts open and roofless: %s"%roof_summary()):return false
	if not check(floors_owned_by_alpha(),"all %d interior floors are alpha's"%INTERIOR.size()):return false
	if not check(owner_at(CLOSE,"wall")=="" and owner_at(ALPHA_WALL,"wall")=="alpha" and owner_at(DOOR,"door")=="alpha","ring is alpha's except the missing closing wall"):return false
	return check(inv_is("start"),"%s starts with the fixture materials: %s"%[role,inv_text("start")])

func close_beta() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are connected simultaneously"):return
	if not verify_open_fixture():return
	var others:=others_of(inventory())
	var result:Dictionary=await act("build",CLOSE,"wall")
	if not check(result.ok,"beta closes the room with Session.perform build: \"%s\""%result.message):return
	var roofed:bool=await until(func():return roofed_by("beta"),ACTION_WAIT)
	if not check(roofed,"auto roofs cover exactly the interior, auto=true, owner=hash(beta): %s"%roof_summary()):return
	if not check(owner_at(CLOSE,"wall")=="beta","closing wall recorded as beta's"):return
	if not check(inv_is("closed") and others_of(inventory())==others,"beta paid exactly 1 wall + %d roofs: %s; other items untouched"%[INTERIOR.size(),inv_text("closed")]):return
	var left:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(left,"alpha disconnected after its removal attempt"):return
	check(roofed_by("beta") and owner_at(CLOSE,"wall")=="beta" and inv_is("closed"),"beta's wall, roofs and inventory survive alpha's attempt: %s"%roof_summary())

func close_alpha() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are connected simultaneously"):return
	if not verify_open_fixture():return
	var baseline:=inventory().duplicate(true)
	var roofed:bool=await until(func():return roofed_by("beta"),PEER_WAIT)
	if not check(roofed,"alpha sees beta's auto roofs (owner=hash(beta), auto=true): %s"%roof_summary()):return
	if not check(inventory()==baseline,"alpha was not charged for beta's closure: %s"%inv_text("closed")):return
	var result:Dictionary=await act("remove",CLOSE,"")
	if not check(not result.ok and not result.has("timeout"),"alpha cannot remove beta's closing wall: rejected \"%s\""%result.message):return
	check(roofed_by("beta") and owner_at(CLOSE,"wall")=="beta" and owner_at(ALPHA_WALL,"wall")=="alpha" and inventory()==baseline,"rejected removal changed nothing: %s %s"%[roof_summary(),inv_text()])

func open_alpha() -> void:
	var alone:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(alone,"beta is offline (snapshot lists only alpha)"):return
	if not check(roofed_by("beta"),"beta's auto roofs persisted on the live server: %s"%roof_summary()):return
	if not check(inv_is("closed"),"alpha inventory before opening: %s"%inv_text("closed")):return
	var others:=others_of(inventory())
	var result:Dictionary=await act("remove",ALPHA_WALL,"")
	if not check(result.ok,"alpha removes its own wall: \"%s\""%result.message):return
	var opened:bool=await until(func():return no_roofs(),ACTION_WAIT)
	if not check(opened,"opening the room removes every auto roof: %s"%roof_summary()):return
	if not check(owner_at(ALPHA_WALL,"wall")=="" and owner_at(CLOSE,"wall")=="beta","only alpha's wall is gone; beta's wall stays"):return
	if not check(inv_is("opened") and others_of(inventory())==others,"alpha got only its own wall refund: %s"%inv_text("opened")):return
	check(population()==1,"beta stayed offline throughout the refund")

func refund_beta() -> void:
	var alone:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(alone,"alpha is offline when beta reconnects"):return
	if not check(no_roofs() and owner_at(CLOSE,"wall")=="beta" and owner_at(ALPHA_WALL,"wall")=="","beta sees the opened, roofless room: %s"%roof_summary()):return
	if not check(inv_is("opened"),"offline roof refund reached beta: %s"%inv_text("opened")):return
	print("AUTO_ROOF_MARK refund_seen")
	var baseline:=inventory().duplicate(true)
	var roofed:bool=await until(func():return roofed_by("alpha"),PEER_WAIT)
	if not check(roofed,"beta sees alpha's restored auto roofs (owner=hash(alpha)): %s"%roof_summary()):return
	if not check(seen_both,"alpha and beta were online together during the restore"):return
	check(inventory()==baseline,"beta was not charged for alpha's roofs: %s"%inv_text("restored"))

func restore_alpha() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are connected simultaneously"):return
	if not check(no_roofs() and inv_is("opened"),"alpha starts restore with an open room: %s %s"%[roof_summary(),inv_text("opened")]):return
	var others:=others_of(inventory())
	var result:Dictionary=await act("build",ALPHA_WALL,"wall")
	if not check(result.ok,"alpha rebuilds its wall with Session.perform build: \"%s\""%result.message):return
	var roofed:bool=await until(func():return roofed_by("alpha"),ACTION_WAIT)
	if not check(roofed,"new auto roofs owned by alpha: %s"%roof_summary()):return
	if not check(owner_at(ALPHA_WALL,"wall")=="alpha" and owner_at(CLOSE,"wall")=="beta","wall owners after restore"):return
	if not check(inv_is("restored") and others_of(inventory())==others,"alpha paid exactly 1 wall + %d roofs: %s"%[INTERIOR.size(),inv_text("restored")]):return
	var left:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(left,"beta disconnected after confirming the restore"):return
	check(roofed_by("alpha"),"roofs unchanged after beta left: %s"%roof_summary())

func persist() -> void:
	if role=="beta":print("AUTO_ROOF_MARK joined")
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"both reconnect to the restarted server simultaneously"):return
	if not check(roofed_by("alpha"),"restart kept auto roofs, auto=true, owner=hash(alpha): %s"%roof_summary()):return
	if not check(owner_at(CLOSE,"wall")=="beta" and owner_at(ALPHA_WALL,"wall")=="alpha" and owner_at(DOOR,"door")=="alpha" and floors_owned_by_alpha(),"restart kept wall/door/floor owners"):return
	if not check(inv_is("restored"),"restart kept %s inventory: %s"%[role,inv_text("restored")]):return
	if role=="alpha":
		var left:bool=await until(func():return population()==1,PEER_WAIT)
		check(left,"beta disconnected after verifying")

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("AUTO_ROOF_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	for p:Vector2i in INTERIOR+ALPHA_WALLS+[DOOR,CLOSE]:
		if not world.is_land(p) or world.water(p) or world.protected(p) or world.blocked(p) or world.resource(p)!="":
			problems.append("cell %s is not buildable home land"%k(p))
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(k(p)):problems.append("cell %s already used in %s"%[k(p),layer])
	var alpha:String=tokens.alpha
	for c:Vector2i in INTERIOR:world.state.ground[k(c)]={"type":"floor","owner":alpha,"items":{}}
	for c:Vector2i in ALPHA_WALLS:world.state.objects[k(c)]={"type":"wall","owner":alpha,"items":{}}
	world.state.objects[k(DOOR)]={"type":"door","owner":alpha,"items":{},"open":false}
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var spot:Vector2=STAND[who]
		person.x=spot.x
		person.y=spot.y
		var start:=expected(who,"start")
		for item in start:person.inventory[item]=int(start[item])
		if not world.can_stand(spot):problems.append("%s cannot stand at %s"%[who,spot])
		for target:Vector2i in [CLOSE,ALPHA_WALL]:
			var d:=spot.distance_to(Vector2(target)+Vector2(0.5,0.5))
			if d>REACH:problems.append("%s is %.2f from %s (reach %.1f)"%[who,d,k(target),REACH])
			if d<CLEARANCE:problems.append("%s would occupy new wall %s"%[who,k(target)])
	if world.blocked(CLOSE):problems.append("closing wall cell is blocked")
	var before:=Enclosure.analyze(world.state,INTERIOR[0])
	if before.sealed or int(before.gap_count)!=1:problems.append("fixture should be open by exactly one gap: %s"%str(before))
	var closed:Dictionary=world.state.duplicate(true)
	closed.objects[k(CLOSE)]={"type":"wall","owner":tokens.beta,"items":{}}
	var after:=Enclosure.analyze(closed,INTERIOR[0])
	if not after.sealed or not same_cells(after.cells,INTERIOR):problems.append("closing wall should seal exactly the interior: %s"%str(after))
	if not world.state.roofs.is_empty():problems.append("fixture must start without roofs")
	for o in world.state.objects.values():
		if o.type=="bed":problems.append("fixture must not need a bed")
	if not problems.is_empty():
		for problem in problems:push_error("AUTO_ROOF_SEED_FAIL "+problem)
		quit(1)
		return
	var fixture:={"interior":INTERIOR.map(func(c):return k(c)),"close":k(CLOSE),"alpha_wall":k(ALPHA_WALL),"door":k(DOOR),
		"roof_count":INTERIOR.size(),"tracked":tracked(),"roof_recipe":World.BUILD.roof,"wall_recipe":World.BUILD.wall,
		"start":{"alpha":expected("alpha","start"),"beta":expected("beta","start")},
		"final":{"alpha":expected("alpha","restored"),"beta":expected("beta","restored")},
		"seed_version":int(world.state.version)}
	print("AUTO_ROOF_FIXTURE "+JSON.stringify(fixture))
	quit(0 if world.save() else 1)
