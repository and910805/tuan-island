extends SceneTree
class SessionFixture extends "res://scripts/session.gd":
	func _ready()->void:session_nonce="cooking-reply-fixture"
class MemoryWorld extends "res://scripts/world.gd":
	func save()->bool:return true
var checks:=0
var failures:=0
var replies:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var session:=SessionFixture.new()
	root.add_child(session)
	session.set_physics_process(false)
	var world:=MemoryWorld.new()
	world.add_player("a","料理試員")
	world.state.players.a.inventory={"radish":20,"wheat":20}
	world.state.players.a.x=34.5
	world.state.players.a.y=28.5
	world.state.objects["35,28"]={"type":"stove","owner":"a","items":{}}
	session.world=world
	session._attach_registered(1,"a")
	session.action_completed.connect(func(sequence:int,action:String,result:Dictionary):replies.append([sequence,action,result.duplicate(true)]))
	session.notice.emit("別的世界通知",true)
	check(replies.is_empty(),"unrelated notices do not acknowledge cooking")
	var seq:int=session.perform("queue_cook",Vector2i(35,28),"soup")
	check(replies.size()==1 and replies[0][0]==seq and replies[0][1]=="queue_cook" and replies[0][2].ok,"enqueue gets correlated success")
	seq=session.perform("claim_cook",Vector2i(35,28))
	check(replies.size()==2 and replies[-1][0]==seq and not replies[-1][2].ok,"early claim gets correlated rejection")
	var id:String=world.state.objects["35,28"].cooking.active.id
	seq=session.perform("cancel_queued_cook",Vector2i(35,28),id)
	check(replies.size()==3 and replies[-1][0]==seq and replies[-1][2].ok,"exact cancellation gets correlated success")
	check(world.state.players.a.inventory.radish==20,"cancel retains full refund")
	var stamps:Array=[]
	for i in 12:stamps.append(Time.get_ticks_msec())
	session.rates[1]=stamps
	seq=session.perform("queue_cook",Vector2i(35,28),"bread")
	check(replies.size()==4 and replies[-1][0]==seq and replies[-1][1]=="queue_cook" and not replies[-1][2].ok,"rate limit returns correlated failure")
	check(world.state.players.a.inventory.wheat==20,"rate limit takes no materials")
	session.world=null
	session.queue_free()
	await process_frame
	print("COOKING_ACTION_REPLY checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
