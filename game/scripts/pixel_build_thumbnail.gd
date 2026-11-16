extends "res://scripts/world_view.gd"

var kind := ""
var thumbnail_art: RefCounted
const CACHE_KEY:=&"tuan_build_thumbnail_art"

func _ready() -> void:
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	data = {"objects": {}}
	var cache_owner:=get_tree().root
	thumbnail_art=cache_owner.get_meta(CACHE_KEY) if cache_owner.has_meta(CACHE_KEY) else null
	if thumbnail_art == null:
		thumbnail_art = VillagePreview.new()
		thumbnail_art.setup()
		cache_owner.set_meta(CACHE_KEY,thumbnail_art)
	village_art = thumbnail_art

func _draw() -> void:
	var origin := Vector2(0, 16)
	camera = Vector2(40, 30) * TILE - origin
	match kind:
		"floor", "path":
			ground_tile(origin, kind)
		"roof", "greenhouse_roof":
			roof_sprite(origin,1.0,kind)
		_:
			object_sprite(origin, kind)
