extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var world:World=session.world
	world.add_player("secret-alpha-token","甲")
	world.add_player("secret-beta-token","乙")
	session.peers={1:"secret-alpha-token",2:"secret-beta-token"}
	world.state.players["secret-beta-token"].region="lanyang"
	world.state.lanyang_life.jobs={"secret-alpha-token":{"ready":60.0},"secret-beta-token":{"ready":70.0}}
	for region in ["home","lanyang"]:
		var public:Dictionary=session.public_state(region)
		check(public.lanyang_life.jobs.is_empty() and not public.lanyang_life.has("own_job"),"Public view has no nursery deadlines or owners")
		check(not JSON.stringify(public).contains("secret-alpha-token") and not JSON.stringify(public).contains("secret-beta-token"),"Public view strips raw actor tokens")
	session._send_snapshot(1)
	check(session.snapshot.lanyang_life.own_job=={"ready":60.0} and session.snapshot.lanyang_life.jobs.is_empty(),"Recipient gets only own queue even from home")
	check(session.snapshot.players.size()==1,"Other region player omitted")
	world.state.lanyang_life.jobs.erase("secret-alpha-token")
	session._send_snapshot(1)
	check(session.snapshot.lanyang_life.own_job.is_empty(),"Claimed queue removed from recipient view")
	session.world=null;session.queue_free();await process_frame
	print("GARDEN_PRIVACY_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
