extends SceneTree
const Feedback=preload("res://scripts/processing_finish_feedback.gd")
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func snap(time:float,ready:Array=[],buffered:int=0,active:Dictionary={})->Dictionary:
	return {"time":time,"region_id":"home","objects":{"40,35":{"type":"sawmill","items":{"plank":buffered},"processing":{"active":active,"waiting":[],"ready":ready}}}}
func _initialize()->void:
	var feedback:=Feedback.new()
	var a:={"id":"a","kind":"plank","completed":2.0,"yield":2}
	var b:={"id":"b","kind":"plank","completed":3.0,"yield":2}
	var baseline:=snap(1.0)
	var first:=snap(2.0,[a])
	var original:=first.duplicate(true)
	feedback.observe({},first,10.0)
	expect(feedback.age("40,35",first.objects["40,35"],10.1)<0,"First snapshot does not replay ready output")
	feedback.observe(baseline,first,11.0)
	expect(feedback.age("40,35",first.objects["40,35"],11.1)>0,"New completed record triggers")
	expect(first==original,"Observer never modifies source snapshot")
	feedback.observe(first,first,11.2)
	expect(is_equal_approx(feedback.age("40,35",first.objects["40,35"],11.3),0.3),"Duplicate does not restart clock")
	expect(feedback.age("40,35",first.objects["40,35"],11.7)<0,"Effect expires with local time even when server pauses")
	expect(feedback.age("40,35",first.objects["40,35"],11.1,true)<0,"Quiet mode suppresses motion")
	var second:=snap(3.0,[b])
	feedback.observe(first,second,12.0)
	expect(feedback.age("40,35",second.objects["40,35"],12.1)>0,"New batch detected with unchanged ready count")
	feedback.observe(second,snap(3.1),12.2)
	expect(is_equal_approx(feedback.age("40,35",second.objects["40,35"],12.3),0.3),"Claim does not retrigger completion")
	feedback.observe(snap(3.1),snap(3.2,[],2),13.0)
	expect(feedback.age("40,35",first.objects["40,35"],13.1)>0,"Real auto buffer increase triggers")
	feedback.observe(first,first,14.0,true)
	expect(feedback.events.is_empty(),"Reconnect baseline clears events")
	feedback.observe(baseline,first,15.0)
	feedback.observe(first,baseline,15.1)
	expect(feedback.events.is_empty(),"Time rollback clears events")
	var away:=first.duplicate(true)
	away.region_id="toucheng"
	feedback.observe(baseline,away,16.0)
	expect(feedback.events.is_empty(),"Region change does not replay output")
	var active:={"id":"a","kind":"plank","finish":2.0,"yield":2}
	var due:=snap(2.0,[],0,active)
	feedback.observe(baseline,due,17.0)
	feedback.observe(due,first,17.2)
	expect(is_equal_approx(feedback.age("40,35",first.objects["40,35"],17.3),0.3),"Due active to ready keeps same event identity")
	feedback.observe(baseline,first,18.0)
	feedback.observe(first,{"time":3,"objects":{}},18.1)
	expect(feedback.events.is_empty(),"Demolished device clears its effect")
	var legacy_before:={"type":"sawmill","job":{"kind":"plank","ready":2.0}}
	expect(Feedback.finished(legacy_before,1.0).is_empty() and Feedback.finished(legacy_before,2.0).size()==1,"Legacy job respects actual completion time")
	legacy_before.job.auto=true
	expect(Feedback.finished(legacy_before,2.0).is_empty(),"Due auto job alone does not invent deposited output")
	legacy_before.job.auto=false
	var legacy_snapshot:={"time":2.0,"objects":{"40,35":legacy_before}}
	feedback.reset()
	feedback.observe({},legacy_snapshot,18.9)
	feedback.observe(legacy_snapshot,first,19.0)
	expect(feedback.events.is_empty(),"Converting an old ready legacy job does not replay completion")
	feedback.reset()
	feedback.observe(baseline,first,19.1)
	expect(feedback.events.is_empty(),"Reset suppresses first snapshot even if view kept old data")
	var many_before:={"time":1,"objects":{}}
	var many_after:={"time":2,"objects":{}}
	for i in 100:
		many_before.objects[str(i)]=baseline.objects["40,35"].duplicate(true)
		many_after.objects[str(i)]=first.objects["40,35"].duplicate(true)
	feedback.observe(many_before,many_after,20.0)
	expect(feedback.events.size()==Feedback.LIMIT,"Presentation event storage is bounded")
	for value in [-1.0,Feedback.DURATION,1.0]:
		expect(Feedback.output_offset(value)==Vector2.ZERO,"No movement outside effect lifetime")
	var positions:Dictionary={}
	for i in 20:
		var offset:=Feedback.output_offset(float(i)*Feedback.DURATION/20.0)
		positions[offset]=true
		expect(offset.x==0 and offset.y>=-7 and offset.y<=0 and offset.y==roundf(offset.y),"Bounded whole-pixel output with fixed shelf")
	expect(positions.size()>3,"Output passes through multiple settling positions")
	print("PROCESSING_FINISH_FEEDBACK checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
