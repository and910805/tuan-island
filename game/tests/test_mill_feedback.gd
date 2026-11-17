extends SceneTree
## Pure MillFeedback checks: state classification, deterministic samples,
## snapshot immutability and static reduced-motion output. No rendering.
const Feedback=preload("res://scripts/mill_feedback.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0

func expect(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures+=1;push_error(message)

func mill(extra:Dictionary={}) -> Dictionary:
	var obj:={"type":"mill","owner":"0123456789abcdef","items":{}}
	obj.merge(extra,true)
	return obj

## Classifies and samples without being allowed to change the input.
func look(obj,now,clock:float=0.0,reduced:bool=false) -> Dictionary:
	var before:=var_to_str(obj)
	var status:=Feedback.classify(obj,now)
	var drawn:=Feedback.sample(status,clock,reduced)
	expect(before==var_to_str(obj),"helper must never mutate the snapshot: "+before)
	return {"status":status,"sample":drawn}

func quiet(result:Dictionary,label:String) -> void:
	var s:Dictionary=result.sample
	expect(not result.status.working,label+": not working")
	expect(not s.motion and s.pixels.is_empty() and s.progress.is_empty(),label+": no processing overlay")

func phantom_free(obj,now,label:String) -> void:
	var r:=look(obj,now,1.7)
	expect(r.status.phase=="invalid" and not r.status.valid,label+": classified invalid, got "+str(r.status.phase))
	quiet(r,label)
	expect(r.sample.badges.is_empty(),label+": no badges")

func within_sprite(drawn:Dictionary) -> bool:
	for pixel in drawn.pixels:
		if not Rect2(0,0,32,48).encloses(pixel.rect):return false
	return true

func _initialize()->void:
	var recipes:Dictionary=World.processing_recipes("mill")
	expect(recipes.keys()==["flour","feed"],"mill catalog includes flour and corn feed")
	var owner:="0123456789abcdef"

	# --- idle / paused / starved: never animated
	var r:=look(mill(),10.0)
	expect(r.status.phase=="idle" and r.status.valid,"empty mill idle")
	quiet(r,"empty");expect(r.sample.badges.is_empty(),"empty mill has no badge")
	r=look(mill({"auto_enabled":false,"input_wheat":8}),10.0)
	expect(r.status.phase=="idle" and r.status.wheat==8,"paused auto with wheat stays idle")
	quiet(r,"paused");expect(r.sample.badges.is_empty(),"paused has no badge")
	r=look(mill({"auto_enabled":true,"input_wheat":1}),10.0)
	expect(r.status.phase=="idle" and r.status.mode=="auto","starved auto stays idle")
	quiet(r,"starved")
	expect(Feedback.caption(r.status)==" · 小麥 1／%d"%World.LOGISTICS.PROCESS_INPUT_CAP,"starved caption shows buffer")

	# --- legacy manual job
	var job:={"kind":"flour","owner":owner,"ready":60.0,"ingredients":{"wheat":2},"yield":1}
	r=look(mill({"job":job}),30.0,0.0)
	expect(r.status.phase=="working" and r.status.mode=="manual","manual job working")
	expect(is_equal_approx(r.status.progress,0.5),"manual progress from recipe duration")
	expect(r.sample.motion and within_sprite(r.sample),"working animates inside the sprite")
	expect(r.sample.progress.fill.size.x==7.0,"progress fill quantised to whole pixels")
	var again:=look(mill({"job":job}),30.0,0.0)
	expect(var_to_str(r.sample)==var_to_str(again.sample),"same clock -> identical sample")
	var later:=look(mill({"job":job}),30.0,0.5)
	expect(var_to_str(r.sample.pixels)!=var_to_str(later.sample.pixels),"presentation clock moves dust/grain")
	expect(var_to_str(Feedback.sample(r.status,3600.0,false))==var_to_str(Feedback.sample(r.status,0.0,false)),"sample wraps deterministically")
	# reduced motion: static and readable, no decorative motion
	var calm:=look(mill({"job":job}),30.0,0.0,true)
	var calm_later:=look(mill({"job":job}),30.0,123.456,true)
	expect(not calm.sample.motion,"reduced reports no motion")
	expect(var_to_str(calm.sample)==var_to_str(calm_later.sample),"reduced is independent of presentation clock")
	expect(calm.sample.pixels.size()==2 and not calm.sample.progress.is_empty(),"reduced keeps static stream + progress")
	expect(calm.sample.pixels.size()<r.sample.pixels.size(),"reduced drops dust particles")
	# finished manual job: ready cue, nothing animated
	r=look(mill({"job":job}),60.0,0.0)
	expect(r.status.phase=="ready" and r.status.ready==1,"due manual job is ready")
	quiet(r,"manual ready")
	expect(r.sample.badges.size()==1 and r.sample.badges[0].kind=="manual_ready","manual ready badge")
	expect(var_to_str(Feedback.sample(r.status,0.0,false))==var_to_str(Feedback.sample(r.status,9.3,false)),"ready cue is static")
	# manual job left alone while auto was toggled on is still the player's to claim
	r=look(mill({"job":job,"auto_enabled":true}),61.0)
	expect(r.status.mode=="manual" and r.status.phase=="ready","manual job beside auto flag stays manual ready")

	# --- automatic job and output buffer
	var auto_job:={"kind":"flour","owner":owner,"ready":100.0,"ingredients":{"wheat":2},"yield":1,"auto":true}
	r=look(mill({"auto_enabled":true,"input_wheat":4,"job":auto_job}),70.0)
	expect(r.status.phase=="working" and r.status.mode=="auto","auto job working")
	expect(r.sample.badges.is_empty(),"auto work is not a manual ready cue")
	r=look(mill({"auto_enabled":false,"job":auto_job}),70.0)
	expect(r.status.working,"in-flight auto job still runs after pausing (Logistics completes it)")
	r=look(mill({"auto_enabled":true,"items":{"flour":3}}),70.0)
	expect(r.status.phase=="buffered" and r.status.buffered==3,"auto output buffered")
	quiet(r,"buffered")
	expect(r.sample.badges.size()==1 and r.sample.badges[0].kind=="auto_output" and r.sample.badges[0].count==3 and not r.sample.badges[0].full,"auto output badge distinct from manual")
	r=look(mill({"auto_enabled":true,"job":auto_job,"items":{"flour":World.LOGISTICS.PROCESS_OUTPUT_CAP}}),100.0)
	expect(r.status.phase=="blocked" and r.status.blocked,"due auto job with full output is blocked")
	quiet(r,"blocked")
	expect(r.sample.badges[0].kind=="auto_output" and r.sample.badges[0].full,"blocked output flagged full")
	r=look(mill({"auto_enabled":true,"job":auto_job,"items":{"flour":2}}),100.0)
	expect(r.status.phase=="buffered" and r.status.ready==0,"due auto job awaiting logistics is never manual-claimable")
	quiet(r,"auto due")
	r=look(mill({"auto_enabled":true,"input_wheat":6,"job":auto_job,"items":{"flour":5}}),80.0)
	expect(r.status.working and r.sample.badges.size()==1 and r.sample.badges[0].kind=="auto_output","working + buffered coexist")

	# --- real manual processing queue (+ Session-like projected job)
	var made:Dictionary=Queue.enqueue(Queue.empty_state(),recipes,0.0,owner,"flour","a".repeat(32),{"wheat":10})
	expect(made.ok,"queue first flour")
	made=Queue.enqueue(made.state,recipes,0.0,owner,"flour","b".repeat(32),made.inventory)
	expect(made.ok,"queue second flour")
	var running:=mill({"processing":made.state})
	r=look(running,15.0)
	expect(r.status.phase=="working" and r.status.queued==1 and is_equal_approx(r.status.progress,0.25),"queue active working")
	var advanced:Dictionary=Queue.advance(made.state,recipes,61.0)
	expect(advanced.ok and advanced.state.ready.size()==1,"queue advanced one")
	var projected:=mill({"processing":advanced.state,"job":{"kind":"flour","owner":owner,"ready":60.0,"ingredients":{"wheat":2},"yield":1}})
	r=look(projected,61.0)
	expect(r.status.working and r.status.ready==1,"ready projection never hides the next active job")
	expect(r.sample.motion and r.sample.badges[0].kind=="manual_ready","work motion plus manual ready cue")
	var mixed:=projected.duplicate(true)
	mixed.processing.active.kind="feed"
	var mixed_status:=Feedback.classify(mixed,61.0)
	expect(mixed_status.working and mixed_status.active_kind=="feed" and mixed_status.ready_kind=="flour","Mixed queue shows running feed and ready flour")
	expect(Feedback.caption(mixed_status).contains("加工中") and Feedback.caption(mixed_status).contains("1 批待領"),"Mixed queue caption shows both states")
	# Overdue active not yet advanced by World: finished work, not animated.
	r=look(running,61.0)
	expect(not r.status.working and r.status.ready==1 and r.status.queued==1,"due active counts as ready, no motion")
	quiet(r,"overdue active")
	var finished:Dictionary=Queue.advance(advanced.state,recipes,200.0)
	r=look(mill({"processing":finished.state}),200.0)
	expect(r.status.phase=="ready" and r.status.ready==2,"all finished: ready only")
	quiet(r,"queue finished")
	r=look(mill({"processing":Queue.empty_state()}),5.0)
	expect(r.status.phase=="idle","empty queue idle");quiet(r,"empty queue")

	# --- malformed / wrong recipe / wrong station: no phantom processing
	phantom_free(null,10.0,"null object")
	phantom_free(mill({"type":"sawmill","job":job}),30.0,"sawmill not a mill")
	phantom_free(mill({"job":job}),NAN,"non-finite clock")
	phantom_free(mill({"job":job}),-1.0,"negative world clock")
	var future_queue:Dictionary=made.state.duplicate(true)
	future_queue.active.started=99.0
	future_queue.active.finish=159.0
	phantom_free(mill({"processing":future_queue}),30.0,"future-started queue cannot animate early")
	phantom_free(mill({"job":{"kind":"plank","owner":owner,"ready":60.0,"yield":2}}),30.0,"wrong recipe job")
	phantom_free(mill({"job":{"kind":"flour","owner":owner,"ready":"soon"}}),30.0,"job ready not a number")
	phantom_free(mill({"job":{"kind":"flour","owner":owner,"ready":INF}}),30.0,"job ready infinite")
	phantom_free(mill({"job":{"kind":"flour","owner":owner,"ready":60.0,"auto":"yes"}}),30.0,"auto flag not bool")
	phantom_free(mill({"job":"flour"}),30.0,"job not a dictionary")
	phantom_free(mill({"processing":"busy"}),30.0,"queue not a dictionary")
	phantom_free(mill({"processing":made.state,"auto_enabled":true}),15.0,"queue beside auto mode")
	phantom_free(mill({"processing":made.state,"job":auto_job}),15.0,"queue beside auto job")
	var wrong:Dictionary=made.state.duplicate(true);wrong.active.kind="plank"
	phantom_free(mill({"processing":wrong}),15.0,"queue wrong recipe")
	var broken:Dictionary=made.state.duplicate(true);broken.erase("waiting")
	phantom_free(mill({"processing":broken}),15.0,"queue missing lane (Session drops malformed)")
	var orphan:Dictionary=made.state.duplicate(true);orphan.active={}
	phantom_free(mill({"processing":orphan}),15.0,"waiting without active")
	var inverted:Dictionary=made.state.duplicate(true);inverted.active.finish=-1.0
	phantom_free(mill({"processing":inverted}),15.0,"finish before start")
	phantom_free(mill({"items":"flour"}),10.0,"items not a dictionary")
	phantom_free(mill({"items":{"plank":2}}),10.0,"foreign output item")
	phantom_free(mill({"items":{"flour":-1}}),10.0,"negative output")
	phantom_free(mill({"input_wheat":-1}),10.0,"negative wheat buffer")
	phantom_free(mill({"input_wheat":2.5}),10.0,"fractional wheat buffer")
	phantom_free(mill({"auto_enabled":"on"}),10.0,"auto flag not bool")
	expect(Feedback.sample({},0.0,false)=={"motion":false,"pixels":[],"progress":{},"badges":[]},"empty status draws nothing")
	expect(Feedback.caption(Feedback.invalid())=="","invalid has no caption")

	print("MILL_FEEDBACK checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
