extends RefCounted

const Forestry=preload("res://scripts/forestry.gd")
const MineDrill=preload("res://scripts/mine_drill.gd")
const Waterworks=preload("res://scripts/waterworks.gd")
const BoxCapacity=preload("res://scripts/box_capacity.gd")
const ChestHistory=preload("res://scripts/chest_history.gd")
## Actor label written to wooden chest history for belt moves (display name, no account token).
const HISTORY_LABEL:="輸送帶"
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

## C13: a belt that touches any cell of a new 3x3 mill talks to its anchor, the only cell that owns the buffers
## (input_wheat / items / job / processing / auto_enabled). Every other key, and a legacy 1x1 mill (no
## `mill_part`), is returned unchanged. Pure: reads only `objects` and World.station_anchor.
static func anchored(world,objects:Dictionary,tile_key:String) -> String:
	var obj:Variant=objects.get(tile_key)
	if not obj is Dictionary or obj.get("type")!="mill" or int(obj.get("mill_part",-1))<=0:return tile_key
	return world.key(world.station_anchor(objects,world.cell(tile_key)))

## True for cells 1..8 of a new mill. They hold no processing state of their own.
static func is_mill_extension(device:Dictionary) -> bool:
	return device.get("type")=="mill" and int(device.get("mill_part",-1))>0

static func edit(objects:Dictionary,planned:Dictionary,key:String) -> Dictionary:
	if not planned.has(key):planned[key]=objects[key].duplicate(true)
	return planned[key]

static func delivery_block(belt:Dictionary,dest:Dictionary,reserved:Dictionary) -> String:
	if dest.is_empty():return "前方未接設備"
	if dest.get("owner","")!=belt.get("owner",""):return "前方是其他島民的設備"
	var item:String=belt.get("filter","wood")
	match dest.type:
		"conveyor":
			if not dest.enabled:return "前方輸送帶已停用"
			if dest.filter!=item:return "前方篩選不同"
			if not dest.items.is_empty() or not reserved.items.is_empty():return "前方輸送帶有貨"
		"private_chest":
			if int(reserved.items.get(item,0))>=1000000000:return "前方儲物箱已滿"
			if not BoxCapacity.slot_ok(reserved.items,{item:1}):return BoxCapacity.BELT_FULL
		"forester","mine_drill":
			if item!="charcoal":return "前方只收木炭"
			var limit:=Forestry.CAPACITY if dest.type=="forester" else MineDrill.FUEL_CAP
			if int(reserved.fuel)>=limit:return "前方燃料槽已滿"
		"waterworks":
			if not Waterworks.INPUTS.has(item):return "前方不收這種材料"
			if int(reserved.input[item])>=Waterworks.INPUT_CAP:return "前方進料槽已滿"
		"sawmill","charcoal_kiln","mill":
			if item!=input_item(str(dest.type)):return "前方不收這種材料"
			if int(reserved.get(input_field(str(dest.type)),0))>=PROCESS_INPUT_CAP:return "前方進料槽已滿"
		_:return "前方設備不收貨"
	return ""

## Writes the chest-side rows of a COMMITTED plan (see `plan`'s `moves`) onto the live
## chests, in plan order, stamped with the authoritative clock. Call only after the
## plan's changes were merged into `objects`; plan itself never mutates anything.
static func record_history(objects:Dictionary,moves:Array,now:float) -> void:
	for row:Dictionary in moves:
		var box:Variant=objects.get(row.box)
		if box is Dictionary:ChestHistory.record(box,HISTORY_LABEL,str(row.item),int(row.amount),bool(row.depositing),now)

## `moves` (optional) receives one {box,item,amount,depositing} row per belt move that
## touches a wooden chest (belt -> chest = deposit, chest -> belt = withdrawal).
static func plan(world,now:float,transfer:bool,moves:Array=[]) -> Dictionary:
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
				var front:String=anchored(world,objects,world.key(tile+offset))
				var dest:Dictionary=objects.get(front,{})
				var reserved:Dictionary=changes.get(front,dest)
				if not delivery_block(belt,dest,reserved).is_empty():continue
				match dest.type:
					"conveyor":
						edit(objects,changes,front).items[item]=1
					"private_chest":
						edit(objects,changes,front).items[item]=int(reserved.items.get(item,0))+1
						moves.append({"box":front,"item":item,"amount":1,"depositing":true})
					"forester":
						edit(objects,changes,front).fuel=int(reserved.fuel)+1
					"mine_drill":
						edit(objects,changes,front).fuel=int(reserved.fuel)+1
					"waterworks":
						edit(objects,changes,front).input[item]=int(reserved.input[item])+1
					"sawmill","charcoal_kiln","mill":
						var field:=input_field(str(dest.type))
						var station_edit:=edit(objects,changes,front)
						station_edit[field]=int(reserved.get(field,0))+1
					_:continue
				edit(objects,changes,key).items.erase(item)
			elif changes.get(key,belt).items.is_empty():
				var rear:String=anchored(world,objects,world.key(tile-offset))
				var source:Dictionary=objects.get(rear,{})
				if source.is_empty() or source.owner!=belt.owner or source.type not in SOURCES:continue
				var stock:=int(changes.get(rear,source).items.get(item,0))
				var claim:=[rear,item]
				if int(source.items.get(item,0))<=int(withdrawals.get(claim,0)) or stock<=0:continue
				withdrawals[claim]=int(withdrawals.get(claim,0))+1
				var source_edit:=edit(objects,changes,rear)
				if stock==1:source_edit.items.erase(item)
				else:source_edit.items[item]=stock-1
				if source.type=="private_chest":moves.append({"box":rear,"item":item,"amount":1,"depositing":false})
				edit(objects,changes,key).items[item]=1
	for key in objects:
		var device:Dictionary=objects[key]
		if device.type not in PROCESSORS or is_mill_extension(device):continue
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
