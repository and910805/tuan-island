extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var session:=Session.new();root.add_child(session);session.set_physics_process(false)
	session.world=World.new();var world:World=session.world
	for actor in ["private-alpha-token","private-beta-token"]:world.add_player(actor,actor)
	session.peers={1:"private-alpha-token",2:"private-beta-token"}
	world.state.players["private-beta-token"].region="lanyang"
	world.state.history_memory.players={"private-alpha-token":{"seen":["33,22"],"gates":[0,0],"round":0,"completed":false},"private-beta-token":{"seen":["33,22","33,25","33,32"],"gates":[2,1],"round":2,"completed":false}}
	for region in ["home","lanyang"]:
		var public:Dictionary=session.public_state(region)
		check(public.history_memory.players.is_empty() and not public.history_memory.has("own_memory"),"Public snapshot carries no private memory records")
		check(not JSON.stringify(public).contains("private-alpha-token") and not JSON.stringify(public).contains("private-beta-token"),"Snapshot hides raw actor tokens")
	session._send_snapshot(1)
	check(session.snapshot.history_memory.own_memory.seen==["33,22"],"Recipient reads only own observations across regions")
	check(session.snapshot.history_memory.own_memory.round==0 and session.snapshot.history_memory.players.is_empty(),"Other player's advanced round hidden")
	world.state.history_memory.players.erase("private-alpha-token");session._send_snapshot(1)
	check(session.snapshot.history_memory.own_memory==World.HISTORY_MEMORY.fresh_record(),"Late joiner has independent fresh record")
	session.world=null;session.queue_free();await process_frame
	print("HISTORY_PRIVACY_TEST checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
