extends RefCounted

const KIND:="wooden_oar_sign"
const ACTION:="oar_sign_mark"
const FIELD:="oar_destination"
const NO_CELL:=Vector2i(-1,-1)

static func cell(value:Variant)->Vector2i:
	if not value is String:return NO_CELL
	var parts:=str(value).split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return NO_CELL
	var marker:=Vector2i(int(parts[0]),int(parts[1]))
	if marker.x<0 or marker.y<0 or value!="%d,%d"%[marker.x,marker.y]:return NO_CELL
	return marker

static func direction(from:Vector2i,to:Vector2i)->Vector2i:
	if to==NO_CELL or from==to:return Vector2i.ZERO
	var angle:=roundf(Vector2(to-from).angle()/(PI/4.0))*PI/4.0
	return Vector2i(roundi(cos(angle)),roundi(sin(angle)))

static func direction_name(from:Vector2i,to:Vector2i)->String:
	if to==NO_CELL:return "尚未標記"
	match direction(from,to):
		Vector2i.RIGHT:return "東"
		Vector2i(1,1):return "東南"
		Vector2i.DOWN:return "南"
		Vector2i(-1,1):return "西南"
		Vector2i.LEFT:return "西"
		Vector2i(-1,-1):return "西北"
		Vector2i.UP:return "北"
		Vector2i(1,-1):return "東北"
	return "就在路標下方"
