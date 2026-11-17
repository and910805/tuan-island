extends SceneTree
## T066 batch 3: res://scripts/resident_keepsake_art.gd — the twelve resident keepsakes
## (one per resident) are painted procedurally into 32×32 RGBA images, no new PNGs.
## Checks: KINDS mirrors ResidentGoals.KEEPSAKE_ORDER; every piece is a cached 32×32
## ImageTexture that is also the "<kind>_kit" inventory icon (directly and through
## InventoryItemArt); unknown kinds / items give false / null; each picture is a real
## little object (enough opaque pixels and colours, no flat block, transparent top
## corners, feet/shadow on the bottom rows, a reasonable bounding box); all twelve differ
## from each other and from the seven souvenir_art pieces; World.BUILD / World.NAMES
## carry every keepsake; FurnitureSpriteArt routes the kinds to this module.
## Prints one JSON line "KEEPSAKE_ART_MEASURE {...}" with per-piece measurements.
const Art=preload("res://scripts/resident_keepsake_art.gd")
const Souvenir=preload("res://scripts/souvenir_art.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const World=preload("res://scripts/world.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const MIN_OPAQUE:=120
const MIN_COLOURS:=8
const MIN_WIDTH:=14
const MIN_HEIGHT:=16
const MAX_SHARE:=0.6
const MIN_DIFF:=80
var checks:=0
var failures:=0
var measure:={}

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	measure["checks"]=checks
	measure["failures"]=failures
	print("KEEPSAKE_ART_MEASURE "+JSON.stringify(measure))
	print("RESIDENT_KEEPSAKE_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func _initialize()->void:
	run.call_deferred()

static func rgba(tex:Texture2D)->Image:
	if tex==null:return null
	var img:Image=tex.get_image()
	if img==null:return null
	if img.is_compressed():img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Opaque = alpha >= 128 (the 0.3-alpha ground shadow is not counted as opaque, but it
## does count as "something on the bottom rows").
static func stats(img:Image)->Dictionary:
	var opaque:=0
	var colours:={}
	var mn:=Vector2i(1<<20,1<<20)
	var mx:=Vector2i(-1,-1)
	var bottom:=false
	var h:=img.get_height()
	for y in h:
		for x in img.get_width():
			var c:=img.get_pixel(x,y)
			if c.a8>0 and y>=h-3:bottom=true
			if c.a8<128:continue
			opaque+=1
			var key:=c.to_rgba32()
			colours[key]=int(colours.get(key,0))+1
			mn=mn.min(Vector2i(x,y))
			mx=mx.max(Vector2i(x,y))
	var top:=0
	for key in colours:top=maxi(top,int(colours[key]))
	var width:int=mx.x-mn.x+1 if mx.x>=0 else 0
	var height:int=mx.y-mn.y+1 if mx.y>=0 else 0
	var corners:bool=img.get_pixel(0,0).a8==0 and img.get_pixel(img.get_width()-1,0).a8==0
	return {"opaque":opaque,"colours":colours.size(),"top_share":snappedf(float(top)/float(maxi(opaque,1)),0.001),"width":width,"height":height,"bottom":bottom,"corners":corners}

## Number of pixels whose RGBA differs between two same-sized images.
static func diff(a:Image,b:Image)->int:
	if a.get_size()!=b.get_size():return a.get_width()*a.get_height()
	var n:=0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y).to_rgba32()!=b.get_pixel(x,y).to_rgba32():n+=1
	return n

func run()->void:
	test_catalogue()
	var images:=test_pieces()
	test_unknown()
	test_distinct(images)
	test_routing()
	finish()

# 1. Kinds mirror the rules; build recipes and names exist.
func test_catalogue()->void:
	expect(Art.KINDS==Goals.KEEPSAKE_ORDER,"KINDS equals ResidentGoals.KEEPSAKE_ORDER")
	expect(Art.KINDS.size()==17,"Seventeen keepsake kinds (%d)"%Art.KINDS.size())
	expect(Art.KIT_SUFFIX=="_kit","Kit suffix is _kit")
	for kind:String in Art.KINDS:
		var kit:=kind+Art.KIT_SUFFIX
		expect(Goals.KEEPSAKES.has(kind),"%s is a ResidentGoals keepsake"%kind)
		expect(World.BUILD.has(kind),"%s is in World.BUILD"%kind)
		if World.BUILD.has(kind) and Goals.KEEPSAKES.has(kind):
			var recipe:Dictionary=World.BUILD[kind]
			var want_name:=str(Goals.KEEPSAKES[kind].name)
			expect(recipe.size()==2 and str(recipe.get("name",""))==want_name and int(recipe.get(kit,0))==1,"%s recipe is {name:%s, %s:1} (%s)"%[kind,want_name,kit,str(recipe)])
		expect(World.NAMES.has(kit),"%s has a name in World.NAMES"%kit)
		expect(not Souvenir.has_kind(kind) and not kind in Furniture.KINDS,"%s is not claimed by souvenir art or the furniture atlas"%kind)

# 2. Every piece: cached 32×32 texture, same picture as its icon, and a real little object.
func test_pieces()->Dictionary:
	var images:={}
	for kind:String in Art.KINDS:
		var kit:=kind+Art.KIT_SUFFIX
		expect(Art.has_kind(kind),"has_kind(%s)"%kind)
		expect(Art.has_item(kit),"has_item(%s)"%kit)
		expect(not Art.has_item(kind) and not Art.has_kind(kit),"%s / %s not confused"%[kind,kit])
		var tex:Texture2D=Art.piece(kind)
		expect(tex!=null and tex is ImageTexture,"%s piece is an ImageTexture"%kind)
		if tex==null:continue
		expect(Vector2i(tex.get_size())==Vector2i(32,32),"%s piece is 32x32"%kind)
		expect(Art.piece(kind)==tex,"%s piece is cached (same object)"%kind)
		expect(Art.icon(kit)==tex,"%s icon is the same picture as the piece"%kit)
		var img:=rgba(tex)
		expect(img!=null and img.get_size()==Vector2i(32,32),"%s image is 32x32"%kind)
		if img==null:continue
		images[kind]=img
		var s:=stats(img)
		measure[kind]=s
		expect(int(s.opaque)>=MIN_OPAQUE,"%s has >=%d opaque pixels (%d)"%[kind,MIN_OPAQUE,int(s.opaque)])
		expect(int(s.colours)>=MIN_COLOURS,"%s has >=%d distinct opaque colours (%d)"%[kind,MIN_COLOURS,int(s.colours)])
		expect(bool(s.corners),"%s top corners (0,0) and (31,0) are transparent"%kind)
		expect(bool(s.bottom),"%s has feet/shadow on the bottom 3 rows"%kind)
		expect(int(s.width)>=MIN_WIDTH and int(s.height)>=MIN_HEIGHT,"%s opaque bounds >= %dx%d (%dx%d)"%[kind,MIN_WIDTH,MIN_HEIGHT,int(s.width),int(s.height)])
		expect(float(s.top_share)<=MAX_SHARE,"%s no colour covers more than 60%% of opaque pixels (%.3f)"%[kind,float(s.top_share)])
	expect(images.size()==17,"All seventeen pieces painted (%d)"%images.size())
	expect(Art.cache.size()==17,"Cache holds exactly the seventeen pieces (%d)"%Art.cache.size())
	return images

# 3. Unknown kinds and items.
func test_unknown()->void:
	for bad:String in ["","keepsake","keepsake_aru_kit","keepsake_bogus","Keepsake_aru","keepsake_aru ","veg_basket_rack","lamp"]:
		expect(not Art.has_kind(bad) and Art.piece(bad)==null,"unknown kind '%s' -> false / null"%bad)
	for bad:String in ["","keepsake_aru","keepsake_bogus_kit","keepsake_aru_kit_kit","keepsake_aru_KIT","veg_basket_rack_kit","wood"]:
		expect(not Art.has_item(bad) and Art.icon(bad)==null,"unknown item '%s' -> false / null"%bad)
	expect(not Art.draw(null,Vector2.ZERO,"keepsake_bogus"),"draw() of an unknown kind returns false")
	expect(Art.cache.size()==17,"Unknown lookups never populate the cache")

# 4. All twelve differ from each other and from the seven souvenir pieces.
func test_distinct(images:Dictionary)->void:
	var kinds:Array=images.keys()
	var min_pair:=1024
	for i in kinds.size():
		for j in range(i+1,kinds.size()):
			var d:=diff(images[kinds[i]],images[kinds[j]])
			min_pair=mini(min_pair,d)
			expect(d>=MIN_DIFF,"%s and %s differ by >=%d pixels (%d)"%[kinds[i],kinds[j],MIN_DIFF,d])
	measure["min_pair_diff"]=min_pair
	var min_souvenir:=1024
	for s:String in Souvenir.KINDS:
		var simg:=rgba(Souvenir.piece(s))
		expect(simg!=null,"souvenir piece %s loads"%s)
		if simg==null:continue
		for kind:String in kinds:
			var d:=diff(images[kind],simg)
			min_souvenir=mini(min_souvenir,d)
			expect(d>=MIN_DIFF,"%s differs from souvenir %s by >=%d pixels (%d)"%[kind,s,MIN_DIFF,d])
	measure["min_souvenir_diff"]=min_souvenir

# 5. Callers route to this module.
func test_routing()->void:
	for kind:String in Art.KINDS:
		var kit:=kind+Art.KIT_SUFFIX
		var tex:Texture2D=ItemArt.icon(kit)
		expect(tex!=null and tex==Art.piece(kind),"InventoryItemArt.icon(%s) is the keepsake piece"%kit)
	var src:=FileAccess.get_file_as_string("res://scripts/furniture_sprite_art.gd")
	expect(src.contains("resident_keepsake_art.gd\").has_kind(kind)") and src.contains("resident_keepsake_art.gd\").draw(canvas,at,kind,tint)"),"FurnitureSpriteArt.draw_sprite routes keepsake kinds to resident_keepsake_art.draw")
