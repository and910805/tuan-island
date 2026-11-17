extends SceneTree
const Feedback=preload("res://scripts/cooking_feedback.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func expect(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures+=1;push_error(message)
func _initialize()->void:
	var q:Dictionary=Queue.empty_state()
	var bag:Dictionary={"radish":10,"wheat":10}
	var a:Dictionary=Queue.enqueue(q,World.RECIPES,0.0,"a","soup","a".repeat(32),bag)
	expect(a.ok,"first queue job")
	var b:Dictionary=Queue.enqueue(a.state,World.RECIPES,0.0,"b","bread","b".repeat(32),a.inventory)
	expect(b.ok,"second queue job")
	var advanced:Dictionary=Queue.advance(b.state,World.RECIPES,11.0)
	expect(advanced.ok,"real queue advanced")
	var stove:Dictionary={"cooking":advanced.state,"job":{"ready":10.0,"kind":"soup"}}
	var before:=var_to_str(stove)
	var status:=Feedback.state(stove,11.0)
	expect(status.working and status.ready==1,"ready projection must not hide next active cooking")
	expect(Feedback.ready_dish(stove)=="soup","A simmering bread job does not replace the ready soup")
	expect(before==var_to_str(stove),"presentation cannot change queue")
	advanced=Queue.advance(advanced.state,World.RECIPES,26.0)
	status=Feedback.state({"cooking":advanced.state},26.0)
	expect(not status.working and status.ready==2,"all complete stops flame while retaining ready count")
	expect(Feedback.ready_dish({"cooking":advanced.state})=="soup","The visible dish is the first one that can be claimed")
	expect(Feedback.ready_dish({"job":{"kind":"soup"}})=="soup","Legacy ready dish uses the same art")
	expect(Feedback.state({},0.0)=={"working":false,"ready":0},"idle stove has no flame or reward")
	expect(Feedback.state({"job":{"ready":10.0}},9.0).working,"legacy simmer retained")
	expect(Feedback.state({"job":{"ready":10.0}},10.0)=={"working":false,"ready":1},"legacy completion stops flame")
	print("COOKING_FEEDBACK checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
