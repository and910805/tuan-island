extends RefCounted
## Shared short care interaction. The hen is never an inventory item.
const ACTION:="chicken_hug"
const RELEASE:="chicken_release"
const FIELD:="hug_actor"
const SECONDS:=8.0
const COOLDOWN:=30.0
const HAND_ACTIONS:=["hoe","seed","water","harvest","axe","pick","build","build_area","remove","plant_tree","move_object","till_area","seed_area","harvest_area","fish_start","fish_catch"]
const ATLAS=preload("res://assets/life-art/animals.png")

static func holder(state:Dictionary,active:Variant=null) -> String:
	var animal:Dictionary=state.get("animal",{})
	var actor:=str(animal.get(FIELD,""))
	var age:=float(state.get("time",0))-float(animal.get("last_pet",-30))
	if actor.is_empty() or age<0.0 or age>=SECONDS:return ""
	var person:Dictionary=state.get("players",{}).get(actor,{})
	if person.is_empty() or str(person.get("region","home"))!="home":return ""
	if active is Dictionary and not active.has(actor):return ""
	return actor

static func clear(animal:Dictionary)->void:
	animal.erase(FIELD)

static func draw(canvas:CanvasItem,foot:Vector2,elapsed:float,quiet:bool)->void:
	var at:=(foot+Vector2(-11,-37)).round()
	# Formal existing sprite: keep the body intact, animate the original feet.
	canvas.draw_texture_rect_region(ATLAS,Rect2(at,Vector2(32,25)),Rect2(0,0,32,25))
	var kick:=0 if quiet else roundi(sin(elapsed*8.0)*2.0)
	for leg in [[13,3,-kick],[17,4,kick]]:
		canvas.draw_texture_rect_region(ATLAS,Rect2(at+Vector2(leg[0],25+leg[2]),Vector2(leg[1],3)),Rect2(leg[0],25,leg[1],3))
