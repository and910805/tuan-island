extends RefCounted
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const TRAY_OFFSET:=Vector2(24,9)

static func display_bounds(at:Vector2)->Rect2:
	return Rect2(at+Vector2(0,-16),Vector2(39,48))
## Presentation only. Public snapshots may contain both queue and legacy projection.
## Prefer the queue so a ready meal never conceals the next simmering pot.
static func state(stove:Dictionary,world_time:float) -> Dictionary:
	if stove.get("cooking") is Dictionary:
		var queue:Dictionary=stove.cooking
		var active:Dictionary=queue.get("active",{})
		return {"working":not active.is_empty() and float(active.get("finish",0))>world_time,
			"ready":(queue.get("ready",[]) as Array).size()}
	var job:Dictionary=stove.get("job",{})
	return {"working":not job.is_empty() and float(job.get("ready",0))>world_time,
		"ready":1 if not job.is_empty() and float(job.get("ready",0))<=world_time else 0}

static func draw(view:CanvasItem,at:Vector2,stove:Dictionary,world_time:float,elapsed:float,reduced:bool) -> Dictionary:
	var status:=state(stove,world_time)
	if status.ready>0:
		var dish:=ItemArt.icon(ready_dish(stove))
		if dish!=null:
			var tray:=at+TRAY_OFFSET
			view.draw_rect(Rect2(tray+Vector2(0,8),Vector2(14,5)),Color("5a3928"))
			view.draw_rect(Rect2(tray+Vector2(1,8),Vector2(12,2)),Color("bd9260"))
			view.draw_texture_rect(dish,Rect2(tray-Vector2(1,5),Vector2(16,16)),false)
	if not status.working:return status
	# Tiny pixel effects overlay the existing stove sprite, never replace it.
	var frame:=0 if reduced else int(elapsed*4.0)%3
	view.draw_rect(Rect2(at+Vector2(13,19),Vector2(6,4)),Color("e59b54"))
	view.draw_rect(Rect2(at+Vector2(14+frame%2,20-frame%2),Vector2(3,3)),Color("ffdc91"))
	for index in 3:
		var phase:=float(index)/3.0 if reduced else fposmod(elapsed*0.35+float(index)/3.0,1.0)
		var rise:=floorf(phase*13.0)
		var drift:=0.0 if reduced else roundf(sin(phase*TAU+float(index))*2.0)
		var point:=at+Vector2(12+index*3+drift,-2-rise)
		var tint:=Color("fff2d4")
		tint.a=0.52*(1.0-phase)
		view.draw_rect(Rect2(point,Vector2(3,2)),tint)
		view.draw_rect(Rect2(point+Vector2(1,-1),Vector2(2,1)),tint)
	return status

static func ready_dish(stove:Dictionary) -> String:
	if stove.get("cooking") is Dictionary:
		var ready:Array=stove.cooking.get("ready",[])
		return "" if ready.is_empty() else str(ready[0].get("kind",""))
	return str(stove.get("job",{}).get("kind",""))
