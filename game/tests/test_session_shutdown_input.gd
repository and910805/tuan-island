extends SceneTree
class SessionFixture extends "res://scripts/session.gd":
	func _ready()->void:pass
class SaveFixture extends "res://scripts/world.gd":
	var writable:=false
	func save()->bool:return writable
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var session:=SessionFixture.new()
	root.add_child(session)
	session.set_physics_process(false)
	var world:=SaveFixture.new()
	session.world=world
	session.peers={1:"test"}
	check(not session.shutdown(),"injected save failure keeps world open")
	check(not session.shutting_down and session.world==world,"failed shutdown must remain playable")
	session.input_direction(Vector2.RIGHT)
	check(session.directions.get(1)==Vector2.RIGHT,"input remains available after failed save")
	world.writable=true
	check(session.shutdown(),"shutdown after successful save")
	check(session.shutting_down and session.world==null,"successful shutdown closes world")
	var before:=session.counter
	for i in 10:
		session.input_direction(Vector2.LEFT)
		check(session.perform("queue_cook",Vector2i(0,0),"bread")==0,"closing frame cannot submit actions")
	check(session.counter==before,"closing frame does not allocate request sequences")
	check(session.directions.get(1)==Vector2.RIGHT,"closing frame does not change movement")
	session.queue_free()
	await process_frame
	print("SESSION_SHUTDOWN_INPUT checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
