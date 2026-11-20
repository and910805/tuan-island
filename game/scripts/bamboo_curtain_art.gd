extends RefCounted
## Half-transparent bamboo curtain (T04): sprite placement and roof-linked opacity.
##
## The curtain hangs on the window directly north of the cell it is stored in
## (WallFixtures.BAMBOO_CURTAIN). There is no setting of its own: it reads the
## set of faded roof tiles that WorldView already computes every frame from
## RoofVisibility (the local player's roof/cutaway room state).

const TEXTURE:=preload("res://assets/ui-life/bamboo-curtain.png")
const SIZE:=Vector2(28,24)
## Offset from the curtain cell to the pane of the window one row north.
const ORIGIN:=Vector2(5,-30)
const CLASSIC_ORIGIN:=Vector2(5,-42)
const WINDOW_DRAW_SIZE:=Vector2(22,19)
## Thumbnail origin inside the 32x48 build-folio slot.
const THUMB_ORIGIN:=Vector2(2,12)
## The woven sprite is already see-through; this is the extra opacity while the roof
## above the window/curtain is cut away (player indoors), matching the faded roof.
const OUTDOOR_ALPHA:=0.86
const INDOOR_ALPHA:=0.46

static func _key(cell:Vector2i) -> String:
	return "%d,%d"%[cell.x,cell.y]

## `faded` is RoofVisibility.faded(...): {"x,y": true} for roof tiles currently cut away.
## The curtain counts as indoors when its own cell or the window it hangs on is faded.
static func indoor(faded:Dictionary,cell:Vector2i) -> bool:
	return faded.has(_key(cell)) or faded.has(_key(cell+Vector2i.UP))

static func alpha(faded:Dictionary,cell:Vector2i) -> float:
	return INDOOR_ALPHA if indoor(faded,cell) else OUTDOOR_ALPHA

static func draw(canvas:CanvasItem,at:Vector2,opacity:=OUTDOOR_ALPHA,tint:=Color.WHITE,uses_window_art:=true) -> void:
	var origin:=ORIGIN if uses_window_art else CLASSIC_ORIGIN
	canvas.draw_texture_rect(TEXTURE,Rect2(at+origin,WINDOW_DRAW_SIZE),false,Color(tint.r,tint.g,tint.b,tint.a*opacity))

static func draw_thumbnail(canvas:CanvasItem,origin:Vector2) -> void:
	canvas.draw_texture(TEXTURE,origin+THUMB_ORIGIN)
