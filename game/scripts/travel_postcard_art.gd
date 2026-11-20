extends RefCounted

const Postcards=preload("res://scripts/travel_postcards.gd")
const ATLAS=preload("res://assets/ui-life/travel-postcards.png")
const CARD_SIZE:=Vector2i(88,54)
static var cache:Dictionary={}

static func texture(id:String)->Texture2D:
	var index:=Postcards.CARDS.keys().find(id)
	if index<0:return null
	if not cache.has(id):
		var postcard:=AtlasTexture.new()
		postcard.atlas=ATLAS
		postcard.region=Rect2(Vector2(Vector2i(index%3,floori(index/3.0))*CARD_SIZE),Vector2(CARD_SIZE))
		postcard.filter_clip=true
		cache[id]=postcard
	return cache[id]
