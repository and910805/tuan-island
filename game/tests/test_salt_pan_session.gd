extends SceneTree
## Protocol 45 salt-pan snapshot privacy and transport limits. Seeded,
## in-process Session audit (NOT a socket/reconnect test, no host started, no
## save written).
##
## SEEDED FIXTURE (disclosed): salt_pan records, one private lot with machines
## and a configured chest, the apprentice shift and a cooperative compartment
## are written directly into World.state; no gameplay is replayed here (that is
## test_salt_pan_world). The snapshot code under test only projects state.
const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const ACTORS=["salt-alpha-PRIVATE-TOKEN","salt-beta-PRIVATE-TOKEN","salt-offline-PRIVATE-TOKEN"]
const BOX_ID:="0123456789abcdef0123456789abcdef"
class FixtureSession extends "res://scripts/session.gd":
	func _ready()->void:
		name="Session"
		session_nonce="salt-snapshot-audit"
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+label)
func _initialize()->void:run.call_deferred()

func record(intro:bool,raked:int,wheel_raked:int,auto_raked:int) -> Dictionary:
	return {"letter":true,"intro":intro,"raked":raked,"wheel_raked":wheel_raked,"auto_raked":auto_raked,"note":false,"order":false,"complete":false}

func run()->void:
	test_constants()
	test_snapshots()
	test_queue_escrow_privacy()
	print("SALT_PAN_SESSION_TESTS checks=%d failures=%d label=in-process-seeded-no-network"%[checks,failures])
	quit(1 if failures else 0)

func test_constants() -> void:
	var S=load("res://scripts/session.gd")
	expect(int(S.PROTOCOL)>=45,"Session protocol includes salt-pan actions (got %d)"%int(S.PROTOCOL))
	var correlated:=["salt_gate_give","salt_rake","salt_install","salt_uninstall","salt_auto_cfg","salt_order","salt_box_take"]
	for action in correlated:
		expect(action in S.CORRELATED_ACTIONS,"%s is correlated"%action)
		expect(action in Salt.ACTIONS,"%s is a SaltPan action"%action)
	for action in ["salt_letter","salt_intro","salt_flood","salt_claim","salt_release","salt_auto_toggle","salt_note","salt_report"]:
		expect(action not in S.CORRELATED_ACTIONS,"%s keeps the plain notice path"%action)
	for older in ["ship","undo_build","craft","flower_ship","flower_give","kitchen_register"]:
		expect(older in S.CORRELATED_ACTIONS,"older correlated action %s kept"%older)
	for action in Salt.ACTIONS:
		expect(String(action).length()<=24,"%s fits the 24-character action bound"%action)
	# salt_auto_cfg and gate extras use the existing plain 32-character bound.
	expect(S.extra_allowed("salt_auto_cfg","47,23|999"),"short cfg extra allowed")
	expect(S.extra_allowed("salt_auto_cfg","x".repeat(S.PLAIN_EXTRA_MAX)),"32 characters allowed (World checks meaning)")
	expect(not S.extra_allowed("salt_auto_cfg","x".repeat(S.PLAIN_EXTRA_MAX+1)),"33 characters rejected before the world")
	expect(S.extra_allowed("salt_gate_give","plank") and not S.extra_allowed("salt_gate_give","p".repeat(33)),"gate extra bounded")
	expect(int(S.PLAIN_EXTRA_MAX)==32,"plain extra bound unchanged")

func test_snapshots() -> void:
	var session:=FixtureSession.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var world=session.world
	for i in ACTORS.size():world.add_player(ACTORS[i],"鹽工%d"%i)
	world.active_tokens.erase(ACTORS[2])
	world.state.time=900.0
	var salt:Dictionary=world.state.salt_pan
	# FIXTURE: alpha holds private lot 0 with both machines and a chest;
	# beta holds the apprentice shift with 6 salt waiting in the cooperative box;
	# the offline player gave gate materials.
	salt.players[ACTORS[0]]=record(true,3,1,1)
	salt.players[ACTORS[1]]=record(true,1,0,0)
	salt.players[ACTORS[2]]=record(true,0,0,0)
	salt.givers[ACTORS[0]]=true
	salt.givers[ACTORS[2]]=true
	var chest_cell:Vector2i=Salt.chest_sockets(0)[0]
	var chest_key:="%d,%d"%[chest_cell.x,chest_cell.y]
	world.state.regions[Salt.REGION].objects[chest_key]={"type":"chest","owner":ACTORS[0],"items":{"sea_salt":6},"box_id":BOX_ID}
	salt.lots[0]={"owner":ACTORS[0],"wheel":true,"rake":true,"chest":chest_key,"box":BOX_ID,"cap":60,"on":true}
	salt.apprentice={"tenant":ACTORS[1],"since":800.0,"wheel":false,"rake":false,"cap":60,"on":false}
	salt.coop_box={ACTORS[1]:6}
	var public_reference:Dictionary=Salt.public(world.state,900.0)
	var seen_public:Array=[]
	for region in ["home",Salt.REGION]:
		for viewer in [ACTORS[0],ACTORS[1]]:
			world.state.players[viewer].region=region
			var expected_before:=var_to_str(world.state)
			session.peers={1:viewer,2:ACTORS[1] if viewer==ACTORS[0] else ACTORS[0]}
			session._send_snapshot(1)
			var snap:Dictionary=session.snapshot
			expect(snap.has("salt_pan"),"snapshot carries salt_pan (%s/%s)"%[region,viewer.left(10)])
			var payload:Dictionary=snap.get("salt_pan",{})
			for forbidden in ["players","givers","coop_box"]:
				expect(not payload.has(forbidden),"%s never sent"%forbidden)
			for actor in ACTORS:
				expect(not var_to_str(snap).contains(actor),"no raw token anywhere in the snapshot")
				expect(not var_to_str(payload).contains(actor.sha256_text().left(16)),"no hashed token inside salt_pan either")
			expect(payload.get("own")==Salt.own_view(world.state,viewer,world.state.regions[Salt.REGION].objects,900.0),"recipient receives exactly SaltPan.own_view")
			var lots:Array=payload.get("lots",[])
			expect(lots.size()==8,"eight private lots published")
			for i in lots.size():
				var lot:Dictionary=lots[i]
				for hidden in ["owner","chest","box","cap","on"]:
					expect(not lot.has(hidden),"public lot %d hides %s"%[i,hidden])
				expect(lot.get("mine")==(viewer==ACTORS[0] and i==0),"lot %d mine flag only for its holder"%i)
			var apprentice:Dictionary=payload.get("apprentice",{})
			expect(not apprentice.has("tenant") and not apprentice.has("since"),"apprentice tenant identity hidden")
			expect(apprentice.get("mine")==(viewer==ACTORS[1]),"apprentice mine flag only for the tenant")
			if viewer==ACTORS[0]:
				var own:Dictionary=payload.own
				expect(int(own.get("lot",-1))==0 and own.get("unit",{}).get("kind")=="lot","alpha sees own lot settings")
				expect(int(own.get("coop_box",-1))==0,"alpha sees no foreign compartment")
				expect(own.get("unit",{}).get("chest")==chest_key and int(own.get("unit",{}).get("cap",0))==60,"own chest/cap visible to the holder")
			else:
				var own_b:Dictionary=payload.own
				expect(int(own_b.get("lot",-1))==-1 and own_b.get("unit",{}).get("kind")=="apprentice","beta sees the apprentice shift as own unit")
				expect(int(own_b.get("coop_box",-1))==6,"beta sees own compartment count")
				expect(not var_to_str(own_b).contains(chest_key),"beta never sees alpha's chest cell")
				expect(not var_to_str(own_b).contains(BOX_ID),"beta never sees alpha's box id")
			# Shared part identical for every region and recipient (mine flags aside).
			var shared:Dictionary=payload.duplicate(true)
			shared.erase("own")
			for lot in shared.lots:lot.erase("mine")
			shared.apprentice.erase("mine")
			seen_public.append(var_to_str(shared))
			var reference:Dictionary=public_reference.duplicate(true)
			for lot in reference.lots:lot.erase("mine")
			reference.apprentice.erase("mine")
			expect(var_to_str(shared)==var_to_str(reference),"shared projection equals SaltPan.public")
			expect(not var_to_str(payload).contains(BOX_ID) or viewer==ACTORS[0],"box id only reaches its holder")
			expect(var_to_str(world.state)==expected_before,"snapshot generation preserves the authoritative world")
			payload.lots[0].mine=not payload.lots[0].mine
			payload.own.record.raked=999
			payload.gates[0].plank=99
			expect(var_to_str(world.state)==expected_before,"mutating the snapshot cannot mutate server records")
			session._send_snapshot(1)
			expect(session.snapshot.salt_pan.lots[0].mine==(viewer==ACTORS[0]),"repeat delivery restores the authoritative mine flag")
	for i in range(1,seen_public.size()):
		expect(seen_public[i]==seen_public[0],"public salt projection identical for all recipients/regions (%d)"%i)
	session.world=null
	session.queue_free()

## Escrow (kit_box) and the fair waiting list stay server-side. SEEDED FIXTURE
## (disclosed): 7 filler holders + OWNER fill all 8 private lots so the waiting
## players are real candidates; the shift, list, escrow compartments and the
## cooperative compartment are written directly into World.state.
const OWNER:="salt-q-owner-PRIVATE-TOKEN"
const TENANT:="salt-q-tenant-PRIVATE-TOKEN"
const WAIT1:="salt-q-wait1-PRIVATE-TOKEN"
const WAIT2:="salt-q-wait2-PRIVATE-TOKEN"

func test_queue_escrow_privacy() -> void:
	var session:=FixtureSession.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var world=session.world
	var viewers:Array=[OWNER,TENANT,WAIT1,WAIT2]
	var fillers:Array=[]
	for i in 7:fillers.append("salt-q-filler-%d-PRIVATE-TOKEN"%i)
	var everyone:Array=viewers+fillers
	for i in everyone.size():world.add_player(everyone[i],"鹽友%d"%i)
	world.state.time=900.0
	var salt:Dictionary=world.state.salt_pan
	salt.players[OWNER]=record(true,3,1,1)
	for t in [TENANT,WAIT1,WAIT2]+fillers:salt.players[t]=record(true,1,0,0)
	salt.lots[0].owner=OWNER
	for i in 7:salt.lots[i+1].owner=fillers[i]
	salt.coop_box={TENANT:6}
	salt.kit_box={OWNER:{"salt_wheel_kit":1,"salt_rake_kit":0},TENANT:{"salt_wheel_kit":0,"salt_rake_kit":2},WAIT2:{"salt_wheel_kit":1,"salt_rake_kit":1}}
	var kits:={OWNER:{"salt_wheel_kit":1,"salt_rake_kit":0},TENANT:{"salt_wheel_kit":0,"salt_rake_kit":2},WAIT1:{"salt_wheel_kit":0,"salt_rake_kit":0},WAIT2:{"salt_wheel_kit":1,"salt_rake_kit":1}}
	# Scenario 1: TENANT on shift, WAIT1/WAIT2 queued.
	salt.apprentice={"tenant":TENANT,"since":800.0,"wheel":true,"rake":false,"cap":60,"on":false}
	salt.waitlist={"order":[{"token":WAIT1,"missed":0},{"token":WAIT2,"missed":1}],"offer_at":0.0}
	var busy:={
		OWNER:{"mine":false,"queued":false,"position":0,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
		TENANT:{"mine":true,"queued":false,"position":0,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
		WAIT1:{"mine":false,"queued":true,"position":1,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
		WAIT2:{"mine":false,"queued":true,"position":2,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
	}
	audit_queue(session,"busy",viewers,everyone,busy,kits)
	# Scenario 2: shift ended at 840, WAIT1 holds the 720 s offer window; the ex-tenant may join.
	salt.apprentice={"tenant":"","since":0.0,"wheel":false,"rake":false,"cap":60,"on":false}
	salt.waitlist={"order":[{"token":WAIT1,"missed":0},{"token":WAIT2,"missed":1}],"offer_at":840.0}
	var free:={
		OWNER:{"mine":false,"queued":false,"position":0,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
		TENANT:{"mine":false,"queued":false,"position":0,"waiting":2,"offer":false,"offer_minutes":0,"can_join":true,"eligible":false},
		WAIT1:{"mine":false,"queued":true,"position":1,"waiting":2,"offer":true,"offer_minutes":11,"can_join":false,"eligible":true},
		WAIT2:{"mine":false,"queued":true,"position":2,"waiting":2,"offer":false,"offer_minutes":0,"can_join":false,"eligible":false},
	}
	audit_queue(session,"offer",viewers,everyone,free,kits)
	session.world=null
	session.queue_free()

func audit_queue(session,label:String,viewers:Array,everyone:Array,expected:Dictionary,kits:Dictionary) -> void:
	var world=session.world
	var now:=float(world.state.time)
	var reference:Dictionary=Salt.public(world.state,now).duplicate(true)
	for lot in reference.lots:lot.erase("mine")
	reference.apprentice.erase("mine")
	var seen:Array=[]
	for region in ["home",Salt.REGION]:
		for viewer:String in viewers:
			world.state.players[viewer].region=region
			var state_before:=var_to_str(world.state)
			session.peers={1:viewer}
			session._send_snapshot(1)
			var snap:Dictionary=session.snapshot
			var payload:Dictionary=snap.get("salt_pan",{})
			var tag:="%s/%s/%s"%[label,region,viewer.left(12)]
			for forbidden in ["kit_box","waitlist","players","givers","coop_box"]:
				expect(not payload.has(forbidden),"%s: %s never sent"%[tag,forbidden])
			var shared:Dictionary=payload.duplicate(true)
			shared.erase("own")
			var app_keys:Array=shared.get("apprentice",{}).keys().map(func(x):return str(x))
			app_keys.sort()
			expect(app_keys==["active","ends_at","mine","rake","taken","wheel"],"%s: public apprentice keys only %s"%[tag,str(app_keys)])
			var shared_text:=var_to_str(shared)
			for word in ["kit_box","waitlist","order","offer_at","missed","queued","position","kits","can_join","offer","waiting"]:
				expect(not shared_text.contains("\"%s\""%word),"%s: '%s' absent from the public projection"%[tag,word])
			for lot in shared.lots:lot.erase("mine")
			shared.apprentice.erase("mine")
			expect(var_to_str(shared)==var_to_str(reference),"%s: shared projection equals SaltPan.public"%tag)
			seen.append(var_to_str(shared))
			for token:String in everyone:
				expect(not var_to_str(snap).contains(token),"%s: no raw token anywhere in the snapshot"%tag)
				expect(not var_to_str(payload).contains(token.sha256_text().left(16)),"%s: no hashed token inside salt_pan"%tag)
			var own:Dictionary=payload.get("own",{})
			var app:Dictionary=own.get("apprentice",{})
			expect(own==Salt.own_view(world.state,viewer,world.state.regions[Salt.REGION].objects,now),"%s: own view is exactly SaltPan.own_view"%tag)
			expect(app.get("kits")==kits[viewer],"%s: kits show only the own escrow %s (got %s)"%[tag,str(kits[viewer]),str(app.get("kits"))])
			var want:Dictionary=expected[viewer]
			for field in want:
				expect(app.get(field)==want[field],"%s: own apprentice.%s == %s (got %s)"%[tag,field,str(want[field]),str(app.get(field))])
			expect(payload.apprentice.get("mine")==want.mine,"%s: public mine flag only for the tenant"%tag)
			expect(int(own.get("coop_box",-1))==(6 if viewer==TENANT else 0),"%s: own cooperative compartment only"%tag)
			app.kits.salt_wheel_kit=777
			payload.apprentice.taken=not payload.apprentice.taken
			expect(var_to_str(world.state)==state_before,"%s: snapshot is a copy (world escrow/list untouched)"%tag)
	for i in range(1,seen.size()):
		expect(seen[i]==seen[0],"%s: public projection identical for every recipient/region (%d)"%[label,i])
