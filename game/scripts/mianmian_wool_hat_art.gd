extends RefCounted
## T066 N06-4: the 羊毛帽 reward, a small pixel wool cap. Drawn over the player's head in the
## world (only when the player's own wool-hat flag is on) and enlarged on the care journal.

const WIDTH:=26
const HEIGHT:=16
const WOOL:=Color("f1e6cf")
const WOOL_SHADE:=Color("d4c3a2")
const BAND:=Color("c9704f")
const OUTLINE:=Color("6b4f3a")
static var cache:Texture2D

## Wide enough to cover the farmer's straw hat, so it reads as a different hat, not a stack.
static func texture() -> Texture2D:
	if cache==null:
		var art:=Image.create_empty(WIDTH,HEIGHT,false,Image.FORMAT_RGBA8)
		var mid:=WIDTH/2
		# pom-pom
		for y in range(0,3):
			for x in range(mid-2,mid+2):
				art.set_pixel(x,y,OUTLINE if (y==0 or x==mid-2 or x==mid+1) and not (y==0 and (x==mid-2 or x==mid+1)) else WOOL)
		# dome with soft ribs
		for y in range(3,12):
			var half:=maxi(4,int(round(float(WIDTH/2-1)*sqrt(1.0-pow(float(11-y)/9.0,2.0)))))
			for x in range(mid-half,mid+half):
				var edge:=x==mid-half or x==mid+half-1 or y==3
				art.set_pixel(x,y,OUTLINE if edge else (WOOL_SHADE if (x-mid)%3==0 else WOOL))
		# folded band with a crooked stitch
		for x in range(1,WIDTH-1):
			art.set_pixel(x,12,OUTLINE)
			art.set_pixel(x,13,BAND)
			art.set_pixel(x,14,BAND)
			art.set_pixel(x,15,OUTLINE)
		for x in [5,9,14,19]:art.set_pixel(x,13,WOOL)
		for x in [7,12,17]:art.set_pixel(x,14,WOOL)
		cache=ImageTexture.create_from_image(art)
	return cache

## foot = the character's foot point (same anchor person_sprite uses).
static func draw(canvas:CanvasItem,foot:Vector2) -> void:
	canvas.draw_texture(texture(),(foot+Vector2(-WIDTH/2.0,-45.0)).round())
