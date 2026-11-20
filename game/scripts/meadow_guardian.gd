extends RefCounted
## B15 生活解法。三台各收一份供品，進度與謝禮歸各島民。

const REGION:="mine_15"
const DEPTH:=15
const NAME:="巨大毛球守護者"
const FIELD:="meadow_guardian"
const AVAILABLE:="meadow_guardian_available"
const POINT:="meadow_guardian"
const TABLE_PREFIX:="meadow_offer:"
const OFFER:="meadow_offer"
const CLAIM:="meadow_claim"
const ACTIONS:=[OFFER,CLAIM]
const FACE:=Vector2(23.5,26.15)
const CENTER:=Vector2i(23,26)
const TABLES:=[Vector2i(20,27),Vector2i(23,27),Vector2i(26,27)]
const FOOTPRINT:=[CENTER]+TABLES
const ALL_TABLES:=7
const CLAIMED:=8
const REACH:=1.55
const ITEM:="radish"
const REWARD:={"gold_ore":2,"crystal_sand":2}

static func cell_open(layers:Dictionary,cell:Vector2i)->bool:
	var key:="%d,%d"%[cell.x,cell.y]
	for layer in ["objects","forest","crops"]:
		if layers.get(layer,{}).has(key):return false
	return true

static func site_clear(layers:Dictionary)->bool:
	for cell:Vector2i in FOOTPRINT:
		if not cell_open(layers,cell):return false
	return true

static func valid(record:Variant)->bool:
	return (record is int or record is float) and is_finite(record) and floor(record)==record and record>=0 and record<=CLAIMED

static func table_full(record:int,index:int)->bool:
	return record==CLAIMED or (record & (1<<index))!=0

static func frame(record:int)->int:
	if record==CLAIMED:return 3
	if record==ALL_TABLES:return 2
	return 1 if record!=0 else 0

static func table_feet(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.4)

static func interaction_points(snapshot:Dictionary,person:Dictionary)->Dictionary:
	var points:Dictionary={}
	if not snapshot.get(AVAILABLE,false) or person.is_empty():return points
	var record:=int(person.get(FIELD,0))
	if record==CLAIMED:return points
	var position:=Vector2(person.x,person.y)
	if record==ALL_TABLES:
		if position.distance_to(FACE)<=REACH:points[POINT]=FACE
		return points
	for index in TABLES.size():
		var foot:=table_feet(TABLES[index])
		if not table_full(record,index) and position.distance_to(foot)<=REACH:
			points[TABLE_PREFIX+str(index)]=foot
	return points
