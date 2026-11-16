extends RefCounted

const BASE_RECT := Rect2i(9,16,31,13)

# Each entry is a connected series of floor spans, starting at the base edge.
const SIDE_CAVES := [
	[Rect2i(15,14,3,2),Rect2i(13,12,7,2),Rect2i(14,11,5,1)],
	[Rect2i(40,20,2,3),Rect2i(42,18,3,7),Rect2i(45,19,2,5)],
	[Rect2i(23,29,3,2),Rect2i(21,31,7,3),Rect2i(22,34,5,1)],
	[Rect2i(33,14,3,2),Rect2i(31,11,7,3),Rect2i(32,10,4,1)],
	[Rect2i(40,23,2,3),Rect2i(42,21,3,7),Rect2i(45,22,3,5),Rect2i(46,27,2,2)],
]

static func side_caves(depth:int) -> Array:
	# B6–B15 reuse the shallow cave shapes named by the T067 catalog.
	if depth>SIDE_CAVES.size():
		return SIDE_CAVES[int(preload("res://scripts/mine_expansion_catalog.gd").entry(depth).get("layout_template",1))-1]
	return SIDE_CAVES[depth-1]

static func land(p:Vector2i,depth:int) -> bool:
	if BASE_RECT.has_point(p):return true
	for span:Rect2i in side_caves(depth):
		if span.has_point(p):return true
	return false

static func bounds(depth:int) -> Rect2i:
	var extent:=BASE_RECT
	for span:Rect2i in side_caves(depth):
		extent=extent.merge(span)
	return extent
