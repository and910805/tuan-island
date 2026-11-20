extends RefCounted

const KIND:="greenhouse_nursery_box"
const SLOTS:="nursery_slots"
const SLOT_COUNT:=4
const SOW:="nursery_sow"
const WATER:="nursery_water"
const HARVEST:="nursery_harvest"
const ACTIONS:=[SOW,WATER,HARVEST]
const BUSY_MESSAGE:="育苗箱還有作物，請先收完再搬移或拆除。"
const UNLOCK_MESSAGE:="完成星禾的〈不必把冬天趕走〉後可建造。"

static func empty_plot()->Dictionary:
	return {"kind":"","growth":0.0,"wet":false}

static func occupied(box:Dictionary)->bool:
	for plot:Dictionary in box.get(SLOTS,{}).values():
		if not str(plot.kind).is_empty():return true
	return false

# Compartments 1+3 sit over the anchor and 2+4 over the next tile when horizontal.
# With a vertical box, the first row is over the anchor.
static func plot_cell(anchor:Vector2i,slot:int,vertical:bool)->Vector2i:
	return anchor+Vector2i(0,slot>>1) if vertical else anchor+Vector2i(slot%2,0)
