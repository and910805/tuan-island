extends RefCounted
## Client-only transitions from authoritative forestry output. Never advances jobs.
const DURATION:=0.65
const LIMIT:=64
const PRODUCTS:={"sawmill":"plank","charcoal_kiln":"charcoal"}
var events:Dictionary={}
var initialized:=false

func reset()->void:
	events.clear()
	initialized=false

static func finished(obj:Dictionary,now:float)->Dictionary:
	var kind:=str(obj.get("type",""))
	if not PRODUCTS.has(kind):return {}
	var records:Dictionary={}
	var queue=obj.get("processing")
	if queue is Dictionary:
		for record in queue.get("ready",[]):
			if record is Dictionary:_record(records,record,kind)
		var active:Dictionary=queue.get("active",{})
		if not active.is_empty() and float(active.get("finish",INF))<=now:
			_record(records,active,kind)
	else:
		var job:Dictionary=obj.get("job",{})
		if not job.is_empty() and not job.get("auto",false) and float(job.get("ready",INF))<=now:
			if job.get("kind","")==PRODUCTS[kind]:records["legacy:%s:%s"%[job.kind,job.ready]]=float(job.ready)
	return records

static func _record(records:Dictionary,record:Dictionary,station:String)->void:
	if record.get("kind","")!=PRODUCTS[station]:return
	# Canonical queue IDs survive the active -> ready projection unchanged.
	var id:=str(record.get("id",""))
	if not id.is_empty():records[id]=float(record.get("completed",record.get("finish",INF)))

func observe(before:Dictionary,after:Dictionary,elapsed:float,baseline:bool=false)->void:
	if not initialized or baseline or before.is_empty() or str(before.get("region_id","home"))!=str(after.get("region_id","home")) or float(after.get("time",0))<float(before.get("time",0)):
		reset()
		initialized=true
		return
	var objects:Dictionary=after.get("objects",{})
	for cell in events.keys():
		if not objects.has(cell) or elapsed-float(events[cell].started)>=DURATION:events.erase(cell)
	for cell in objects:
		var obj:Dictionary=objects[cell]
		var kind:=str(obj.get("type",""))
		var prior:Dictionary=before.get("objects",{}).get(cell,{})
		if not PRODUCTS.has(kind) or prior.get("type","")!=kind:
			events.erase(cell)
			continue
		var current:=finished(obj,float(after.get("time",0)))
		var previous:=finished(prior,float(before.get("time",0)))
		var arrived:=false
		for id in current:
			if previous.has(id):continue
			# Lazy conversion of an already-finished legacy job isn't new work.
			var legacy:Dictionary=prior.get("job",{})
			if not prior.has("processing") and not legacy.get("auto",false) and legacy.get("kind","")==PRODUCTS[kind] and float(legacy.get("ready",INF))<=float(before.get("time",0)):
				if absf(float(current[id])-float(legacy.ready))<0.000001:continue
			arrived=true
		var item:String=PRODUCTS[kind]
		# Auto processing deposits real units into the shared output buffer.
		if int(obj.get("items",{}).get(item,0))>int(prior.get("items",{}).get(item,0)):arrived=true
		if arrived:
			events.erase(cell)
			events[cell]={"started":elapsed,"type":kind}
			if events.size()>LIMIT:events.erase(events.keys()[0])

func age(cell:String,obj:Dictionary,elapsed:float,quiet:bool=false)->float:
	if quiet or not events.has(cell) or events[cell].type!=obj.get("type",""):return -1.0
	var value:=elapsed-float(events[cell].started)
	return value if value>=0.0 and value<DURATION else -1.0

static func output_offset(age:float)->Vector2:
	if age<0.0 or age>=DURATION:return Vector2.ZERO
	var progress:=age/DURATION
	# Settle onto the anchored shelf with two successively smaller hops.
	var height:=absf(cos(progress*PI*1.5))*7.0*pow(1.0-progress,2.0)
	return Vector2(0,-roundf(height))
