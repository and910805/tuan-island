extends RefCounted

const INTERVAL:=2.0
const BELT_LIMIT:=128
const FILTERS:=["wood","fiber","resin","plank","charcoal","copper_ore","copper_joint","stone","gold_ore","wheat","flour"]
const PROCESS_INPUT_CAP:=32
const PROCESS_OUTPUT_CAP:=32
const DIRECTIONS:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const PROCESSORS:=["sawmill","charcoal_kiln","mill"]
## Generic processing-station mapping for the automatic buffer. `field` is the
## persisted input buffer key: legacy stations keep `input_wood` (never renamed),
## the Q05 flour mill uses `input_wheat`. `output` is the INDUSTRY.PROCESS key
## made by the automatic job and the only item allowed in the output buffer.
const STATION_IO:={
	"sawmill":{"input":"wood","field":"input_wood","output":"plank"},
	"charcoal_kiln":{"input":"wood","field":"input_wood","output":"charcoal"},
	"mill":{"input":"wheat","field":"input_wheat","output":"flour"},
}
## Every persisted processor buffer key (save validation rejects them elsewhere).
const INPUT_FIELDS:=["input_wood","input_wheat"]
## Same-owner devices a conveyor may pull from (rear side).
const SOURCES:=["forester","private_chest","sawmill","charcoal_kiln","mill","waterworks","mine_drill"]

static func fresh() -> Dictionary:
	return {"dir":0,"enabled":false,"filter":"wood"}

static func input_item(station:String) -> String:
	return str(STATION_IO.get(station,{}).get("input",""))

static func input_field(station:String) -> String:
	return str(STATION_IO.get(station,{}).get("field",""))

static func output_item(station:String) -> String:
	return str(STATION_IO.get(station,{}).get("output",""))

static func processor_ready_to_move(device:Dictionary) -> bool:
	return not device.get("auto_enabled",false) and int(device.get(input_field(str(device.get("type",""))),0))==0 and not device.has("job") and processing_idle(device) and device.items.values().all(func(amount):return int(amount)==0)

## T036 manual queue (optional device.processing, CookingQueue shape). True when
## absent or a well-formed empty queue; malformed queues count as busy.
static func processing_idle(device:Dictionary) -> bool:
	if not device.has("processing"):return true
	var queue=device.processing
	if not queue is Dictionary:return false
	var active=queue.get("active")
	var waiting=queue.get("waiting")
	var ready=queue.get("ready")
	return active is Dictionary and active.is_empty() and waiting is Array and waiting.is_empty() and ready is Array and ready.is_empty()

static func edit(objects:Dictionary,planned:Dictionary,key:String) -> Dictionary:
	if not planned.has(key):planned[key]=objects[key].duplicate(true)
	return planned[key]

static func plan(world,now:float,transfer:bool) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var changes:Dictionary={}
	var withdrawals:Dictionary={}
	if transfer:
		var keys:=objects.keys()
		keys.sort()
		for key in keys:
			var belt:Dictionary=objects[key]
			if belt.type!="conveyor" or not belt.enabled:continue
			var offset:Vector2i=DIRECTIONS[int(belt.dir)]
			var tile:Vector2i=world.cell(key)
			var item:String=belt.filter
			if int(belt.items.get(item,0))>0:
				var front:String=world.key(tile+offset)
				var dest:Dictionary=objects.get(front,{})
				if dest.is_empty() or dest.owner!=belt.owner:continue
				var reserved:Dictionary=changes.get(front,dest)
				match dest.type:
					"conveyor":
						if not dest.enabled or dest.filter!=item or not dest.items.is_empty() or not reserved.items.is_empty():continue
						edit(objects,changes,front).items[item]=1
					"private_chest":
						if int(reserved.items.get(item,0))>=1000000000:continue
						edit(objects,changes,front).items[item]=int(reserved.items.get(item,0))+1
					"forester":
						if item!="charcoal" or int(reserved.fuel)>=world.FORESTRY.CAPACITY:continue
						edit(objects,changes,front).fuel=int(reserved.fuel)+1
					"mine_drill":
						if item!="charcoal" or int(reserved.fuel)>=world.MINE_DRILL.FUEL_CAP:continue
						edit(objects,changes,front).fuel=int(reserved.fuel)+1
					"waterworks":
						if not world.WATERWORKS.INPUTS.has(item) or int(reserved.input[item])>=world.WATERWORKS.INPUT_CAP:continue
						edit(objects,changes,front).input[item]=int(reserved.input[item])+1
					"sawmill","charcoal_kiln","mill":
						var field:=input_field(str(dest.type))
						if item!=input_item(str(dest.type)) or int(reserved.get(field,0))>=PROCESS_INPUT_CAP:continue
						var station_edit:=edit(objects,changes,front)
						station_edit[field]=int(reserved.get(field,0))+1
					_:continue
				edit(objects,changes,key).items.erase(item)
			elif changes.get(key,belt).items.is_empty():
				var rear:String=world.key(tile-offset)
				var source:Dictionary=objects.get(rear,{})
				if source.is_empty() or source.owner!=belt.owner or source.type not in SOURCES:continue
				var stock:=int(changes.get(rear,source).items.get(item,0))
				var claim:=[rear,item]
				if int(source.items.get(item,0))<=int(withdrawals.get(claim,0)) or stock<=0:continue
				withdrawals[claim]=int(withdrawals.get(claim,0))+1
				var source_edit:=edit(objects,changes,rear)
				if stock==1:source_edit.items.erase(item)
				else:source_edit.items[item]=stock-1
				edit(objects,changes,key).items[item]=1
	for key in objects:
		var device:Dictionary=objects[key]
		if device.type not in PROCESSORS:continue
		# Manual queue stations are advanced by World.step_processing only; their
		# outputs reach the backpack on claim, never the belt/output buffer here.
		if device.has("processing"):continue
		var kind:=output_item(str(device.type))
		var recipe:Dictionary=world.INDUSTRY.PROCESS.get(kind,{})
		if recipe.is_empty():continue
		var input:=input_item(str(device.type))
		var field:=input_field(str(device.type))
		var batch:=int(recipe.ingredients.get(input,0))
		if batch<=0:continue
		var current:Dictionary=changes.get(key,device)
		if device.has("job"):
			var job:Dictionary=device.job
			if not job.get("auto",false) or float(job.ready)>now:continue
			var amount:=int(current.items.get(kind,0))+int(recipe.yield)
			if amount>PROCESS_OUTPUT_CAP:continue
			edit(objects,changes,key).items[kind]=amount
			changes[key].erase("job")
		elif device.get("auto_enabled",false) and int(device.get(field,0))>=batch and int(current.items.get(kind,0))+int(recipe.yield)<=PROCESS_OUTPUT_CAP:
			var target:=edit(objects,changes,key)
			target[field]=int(target.get(field,0))-batch
			target.job={"kind":kind,"owner":device.owner,"ready":now+float(recipe.time),"ingredients":{input:batch},"yield":int(recipe.yield),"auto":true}
	return changes
