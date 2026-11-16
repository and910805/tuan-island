extends SceneTree
## Seeded, in-process Session snapshot audit. NOT a socket/reconnect test.
const World=preload("res://scripts/world.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const ACTORS=["flower-alpha-PRIVATE-TOKEN","flower-beta-PRIVATE-TOKEN","flower-offline-PRIVATE-TOKEN"]
class FixtureSession extends "res://scripts/session.gd":
	func _ready()->void:
		name="Session"
		session_nonce="flower-snapshot-audit"
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var session:=FixtureSession.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var world= session.world
	for i in ACTORS.size():
		world.add_player(ACTORS[i],"島民%d"%i)
		var record:Dictionary=Flower.FRESH.duplicate(true)
		record.letter=i>0
		world.state.flower_nursery.players[ACTORS[i]]=record
		world.state.flower_nursery.garden.contributors[ACTORS[i]]=i+1
	world.active_tokens.erase(ACTORS[2])
	world.state.flower_nursery.garden.given.blue_dye=6
	for region in ["home","tianwei"]:
		for viewer in [ACTORS[0],ACTORS[1]]:
			world.state.players[viewer].region=region
			var expected_before:=var_to_str(world.state)
			session.peers={1:viewer,2:ACTORS[1] if viewer==ACTORS[0] else ACTORS[0]}
			session._send_snapshot(1)
			var snap:Dictionary=session.snapshot
			var payload:Dictionary=snap.flower_nursery
			expect(session.own_id==viewer.sha256_text().left(16),"recipient id hashed")
			expect(not payload.has("players"),"all-player chapter records omitted")
			expect(payload.own==Flower.own_view(world.state,viewer),"recipient receives only own record and contribution")
			expect(payload.garden==Flower.public(world.state).garden,"shared garden projection consistent")
			expect(payload.garden.contributor_count==3 and not payload.garden.has("contributors"),"offline contribution counted without contributor identities")
			for actor in ACTORS:
				expect(not var_to_str(snap).contains(actor),"no raw token anywhere in snapshot")
			for actor in [ACTORS[0],ACTORS[1]]:
				if actor!=viewer and snap.players.has(actor.sha256_text().left(16)):
					expect(not snap.players[actor.sha256_text().left(16)].has("inventory"),"foreign inventory omitted")
			expect(var_to_str(world.state)==expected_before,"snapshot generation preserves authoritative world")
			payload.own.own_record.letter=not payload.own.own_record.letter
			payload.garden.given.blue_dye=999
			expect(var_to_str(world.state)==expected_before,"snapshot mutation cannot mutate server records")
			session._send_snapshot(1)
			expect(session.snapshot.flower_nursery.own==Flower.own_view(world.state,viewer),"repeat delivery restores independent authoritative data")
	# No host/transport was started, no player save was opened or written.
	session.world=null
	session.queue_free()
	print("FLOWER_SNAPSHOT_AUDIT checks=%d failures=%d label=in-process-seeded-no-network"%[checks,failures])
	quit(1 if failures else 0)
