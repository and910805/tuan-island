extends SceneTree
const Queue=preload("res://scripts/cooking_queue.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var old:Dictionary=World.RECIPES.duplicate(true)
	old.bread.ingredients={"wheat":3}
	old.bread.yield=2
	old.bread.time=7.0
	var first:=Queue.enqueue(Queue.empty_state(),old,0.0,"alice","bread","a".repeat(32),{"wheat":30})
	check(first.ok,"Historical recipe enqueued")
	var second:=Queue.enqueue(first.state,old,0.0,"alice","bread","b".repeat(32),first.inventory)
	check(second.ok,"Second historical job enqueued")
	check(Queue.validate(second.state,World.RECIPES,0.0),"Updated catalog does not invalidate stored recipe snapshot")
	var cancelled:=Queue.cancel(second.state,World.RECIPES,1.0,"alice","b".repeat(32),second.inventory)
	check(cancelled.ok and cancelled.inventory.wheat==27,"Cancel refunds original three wheat, not current two")
	var advanced:=Queue.advance(second.state,World.RECIPES,14.0)
	check(advanced.ok and advanced.state.ready.size()==2,"Both jobs use stored seven-second durations")
	check(advanced.state.ready[0].completed==7.0 and advanced.state.ready[1].completed==14.0,"Saved durations preserve completion deadlines")
	var claimed:=Queue.claim(advanced.state,World.RECIPES,14.0,second.inventory)
	check(claimed.ok and claimed.inventory.bread==2,"Historical yield stays two after catalog changes")
	var parsed:Dictionary=JSON.parse_string(JSON.stringify(claimed.state))
	var again:=Queue.claim(parsed,World.RECIPES,14.0,claimed.inventory)
	check(again.ok and again.inventory.bread==4 and again.state.ready.is_empty(),"JSON reload preserves second yield without replaying first")
	var legacy:={"kind":"bread","ready":5.0,"owner":"alice","ingredients":{"wheat":3},"yield":2,"recipe_version":1}
	var imported:=Queue.import_legacy(legacy,World.RECIPES,1.0,"c".repeat(32))
	check(imported.ok and imported.state.active.finish==5.0,"Legacy shorter duration preserves deadline")
	var refunded:=Queue.cancel(imported.state,World.RECIPES,1.0,"alice","c".repeat(32),{})
	check(refunded.ok and refunded.inventory.wheat==3,"Legacy cancel preserves stored ingredients")
	var done:=Queue.import_legacy(legacy,World.RECIPES,20.0,"d".repeat(32))
	check(done.ok and done.state.ready.size()==1 and done.state.active.is_empty(),"Already finished legacy work imports once into ready shelf")
	var meal:=Queue.claim(done.state,World.RECIPES,20.0,{})
	check(meal.ok and meal.inventory.bread==2,"Finished legacy record keeps historical yield")
	check(not Queue.claim(meal.state,World.RECIPES,20.0,meal.inventory).ok,"Legacy cannot be claimed twice")
	var q:=Queue.empty_state()
	var bag:={"radish":20}
	for index in 10:
		var added:=Queue.enqueue(q,World.RECIPES,0.0,"alice","soup","%032x"%(index+1),bag)
		check(added.ok,"Original plan accepts job %d of ten"%(index+1))
		if not added.ok:break
		q=added.state;bag=added.inventory
	check(Queue.CAPACITY==10 and q.waiting.size()==9,"Original ten-job station limit retained")
	check(not Queue.enqueue(q,World.RECIPES,0.0,"alice","soup","e".repeat(32),{"radish":2}).ok,"Eleventh job refused")
	var all_done:=Queue.advance(q,World.RECIPES,100.0)
	check(all_done.ok and all_done.state.ready.size()==10,"All ten complete without needing a claim between jobs")
	check(not Queue.enqueue(all_done.state,World.RECIPES,100.0,"alice","soup","e".repeat(32),{"radish":2}).ok,"Unclaimed outputs still occupy bounded station capacity")
	print("COOKING_QUEUE_HISTORY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
