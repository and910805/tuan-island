extends RefCounted
## Deterministic screen-space placement for world interaction labels.
## Pure geometry (no fonts, drawing or world data) so tests can assert exact
## rectangles. All rectangles share WorldView's unscaled draw space.

## Gap kept between a label and whatever it steps around.
const GAP:=3.0
## Blockers are grown by this much before testing overlap (matches the older
## `box.grow(2)` spacing rule in WorldView).
const CLEARANCE:=2.0
## Preferred inset from the viewport edge when the viewport is large enough.
const EDGE_MARGIN:=4.0
## When a label slides sideways it still keeps this much width over its anchor.
const ANCHOR_HOLD:=8.0
## Local player body footprint relative to the drawn foot point.
const BODY_OFFSET:=Vector2(-15,-44)
const BODY_SIZE:=Vector2(30,48)

static func body_rect(foot:Vector2) -> Rect2:
	return Rect2(foot+BODY_OFFSET,BODY_SIZE)

## Area labels should stay inside; falls back to the whole viewport when tiny.
static func safe_area(viewport:Rect2,margin:=EDGE_MARGIN) -> Rect2:
	if viewport.size.x<=margin*2.0+16.0 or viewport.size.y<=margin*2.0+16.0:return viewport
	return viewport.grow(-margin)

static func clamp_into(box:Rect2,area:Rect2) -> Rect2:
	var x:=clampf(box.position.x,area.position.x,maxf(area.position.x,area.end.x-box.size.x))
	var y:=clampf(box.position.y,area.position.y,maxf(area.position.y,area.end.y-box.size.y))
	return Rect2(Vector2(x,y).round(),box.size)

static func distance_to_rect(point:Vector2,box:Rect2) -> float:
	var nearest:=Vector2(clampf(point.x,box.position.x,box.end.x),clampf(point.y,box.position.y,box.end.y))
	return point.distance_to(nearest)

static func overlap(box:Rect2,blockers:Array[Rect2]) -> float:
	var total:=0.0
	for other in blockers:
		var grown:=box.grow(CLEARANCE)
		if grown.intersects(other):total+=maxf(grown.intersection(other).get_area(),1.0)
	return total

## Candidate top-left corners, in a fixed order: the preferred spot, sideways
## slides that keep the anchor covered, then spots stepping around each blocker.
static func candidates(preferred:Rect2,anchor:Vector2,blockers:Array[Rect2]) -> Array[Vector2]:
	var w:=preferred.size.x
	var h:=preferred.size.y
	var top:=preferred.position.y
	var list:Array[Vector2]=[preferred.position,Vector2(anchor.x-ANCHOR_HOLD,top),Vector2(anchor.x-w+ANCHOR_HOLD,top)]
	for other in blockers:
		list.append(Vector2(other.end.x+GAP,top))
		list.append(Vector2(other.position.x-w-GAP,top))
		list.append(Vector2(preferred.position.x,other.position.y-h-GAP))
		list.append(Vector2(preferred.position.x,other.end.y+GAP))
		list.append(Vector2(other.end.x+GAP,other.position.y-h-GAP))
		list.append(Vector2(other.position.x-w-GAP,other.position.y-h-GAP))
	return list

## Returns {"rect":Rect2,"clear":bool}. Picks the clear candidate nearest the
## anchor (earliest wins ties, so an unobstructed label never moves). If no spot
## is clear the label is still returned at the least-overlapping spot: vital
## prompts are never dropped.
static func place(preferred:Rect2,anchor:Vector2,blockers:Array[Rect2],area:Rect2) -> Dictionary:
	var best:=Rect2()
	var best_overlap:=INF
	var best_distance:=INF
	for corner in candidates(preferred,anchor,blockers):
		var box:=clamp_into(Rect2(corner,preferred.size),area)
		var cost:=overlap(box,blockers)
		var distance:=distance_to_rect(anchor,box)
		if cost<best_overlap or (cost==best_overlap and distance<best_distance):
			best=box
			best_overlap=cost
			best_distance=distance
	return {"rect":best,"clear":best_overlap==0.0}
