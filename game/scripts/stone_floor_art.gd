@static_unload
extends RefCounted
## C09 石地板 tile art. Uses the dedicated 32x32 texture once Codex supplies it at PATH; until then
## a code-drawn running-bond flagstone tile stands in so the floor is already readable in game, in the
## build folio and in blueprint ghosts. Distinct from the 石板路 tile and from the wooden plank floor.

const PATH:="res://assets/ui-life/stone-floor.png"
const TILE:=32
const MORTAR:=Color("5d6461")
const STONES:=[Color("a3a89f"),Color("939a93"),Color("aeb2a8")]
const HIGHLIGHT:=Color("cfd2c6")
const SHADE:=Color("7b827d")
## [y, height, joints]: rows of the running bond. Each joint is the x of a one-pixel vertical mortar line.
const ROWS:=[[0,11,[15]],[11,10,[7,23]],[21,11,[15]]]
static var _texture:Texture2D
static var _checked:=false

static func clear_cache() -> void:
	_texture=null
	_checked=false

## The dedicated texture, or null while only the fallback exists. Cached after the first lookup.
## A texture that is not exactly 32x32 is ignored so a wrong-sized drop never stretches in game.
static func texture() -> Texture2D:
	if not _checked:
		_checked=true
		if ResourceLoader.exists(PATH):_texture=load(PATH) as Texture2D
		if _texture!=null and (_texture.get_width()!=TILE or _texture.get_height()!=TILE):_texture=null
	return _texture

static func has_dedicated_texture() -> bool:
	return texture()!=null

static func draw(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	var art:=texture()
	if art!=null:
		canvas.draw_texture_rect(art,Rect2(at,Vector2(TILE,TILE)),false,tint)
		return
	canvas.draw_rect(Rect2(at,Vector2(TILE,TILE)),MORTAR*tint)
	var index:=0
	for row:Array in ROWS:
		var y:int=row[0]
		var height:int=row[1]
		var joints:Array=row[2]
		for i in joints.size()+1:
			var x0:int=1 if i==0 else int(joints[i-1])+1
			var x1:int=TILE if i==joints.size() else int(joints[i])
			var stone:=Rect2(at+Vector2(x0,y+1),Vector2(x1-x0,height-1))
			canvas.draw_rect(stone,STONES[index%STONES.size()]*tint)
			canvas.draw_rect(Rect2(stone.position,Vector2(stone.size.x,1)),HIGHLIGHT*tint)
			canvas.draw_rect(Rect2(stone.position+Vector2(0,stone.size.y-1),Vector2(stone.size.x,1)),SHADE*tint)
			index+=1
