extends RefCounted

const Weather=preload("res://scripts/weather.gd")
const KEY:="woodland_stock"
const GROVE:=Rect2i(12,10,15,17)
const PERIOD_DAYS:=3
const TREES_PER_CYCLE:=4

static func cycle_at(time:float)->int:
	return floori(Weather.day_index(time)/float(PERIOD_DAYS))

static func stumps(state:Dictionary)->Dictionary:
	return state.get(KEY,{}).get("stumps",{})

static func record_felling(state:Dictionary,tile:String)->void:
	var cycle:=cycle_at(float(state.time))
	if not state.has(KEY):state[KEY]={"cycle":cycle,"grown":0,"stumps":{}}
	state[KEY].stumps[tile]=cycle+1

static func advance(world)->bool:
	var stock:Dictionary=world.state.get(KEY,{})
	if stock.is_empty() or stock.stumps.is_empty():return false
	var cycle:=cycle_at(float(world.state.time))
	var remaining:=TREES_PER_CYCLE-(int(stock.grown) if int(stock.cycle)==cycle else 0)
	if remaining<=0:return false
	var queue:Array=[]
	for tile:String in stock.stumps:
		if int(stock.stumps[tile])<=cycle:queue.append(tile)
	if queue.is_empty():return false
	queue.sort_custom(func(a:String,b:String):
		var first:=int(stock.stumps[a])
		var second:=int(stock.stumps[b])
		return a<b if first==second else first<second)
	var grown:=0
	for tile:String in queue:
		if not world.can_restore_woodland_tree(tile):continue
		world.state.removed.erase(tile)
		stock.stumps.erase(tile)
		grown+=1
		if grown>=remaining:break
	if grown==0:return false
	stock.grown=TREES_PER_CYCLE-remaining+grown
	stock.cycle=cycle
	return true
