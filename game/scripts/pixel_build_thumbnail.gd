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
		"floor", "path", "spring_pebble_path":
			ground_tile(origin, kind)
		"roof", "greenhouse_roof":
			roof_sprite(origin,1.0,kind)
		"assembly_table":
			draw_texture(preload("res://assets/automation/assembly-table-icon.png"),origin+Vector2(0,5))
		"inn_fabric_screen":
			draw_texture_rect(preload("res://assets/ui-life/inn-fabric-screen.png"),Rect2(origin+Vector2(0,5),Vector2(32,23)),false)
		"inn_quilt_bed":
			quilt_bed_sprite(origin+Vector2(7,-12),true,"",0.58)
		"inn_stone_footbath":
			draw_texture_rect(preload("res://assets/ui-life/inn-stone-footbath.png"),Rect2(origin+Vector2(0,5),Vector2(32,22)),false)
		"inn_luggage_rack":
			draw_texture_rect(preload("res://assets/ui-life/inn-luggage-rack.png"),Rect2(origin+Vector2(0,5),Vector2(32,22)),false)
		"dye_table":
			draw_texture(preload("res://assets/bakery/dye-table-icon.png"),origin+Vector2(0,5))
		"clay_kiln":
			draw_texture_rect(preload("res://assets/bakery/clay-kiln.png"),Rect2(origin+Vector2(0,-7),Vector2(32,40)),false)
		"small_smelter":
			draw_texture_rect(preload("res://assets/industry/small-smelter.png"),Rect2(origin+Vector2(0,-1),Vector2(32,36)),false)
		"master_bench":
			draw_texture_rect(preload("res://assets/ui-life/master-bench.png"),Rect2(origin+Vector2(0,5),Vector2(32,19)),false)
		"spring_stone_bench":
			draw_texture_rect(preload("res://assets/ui-life/spring-stone-bench.png"),Rect2(origin+Vector2(0,5),Vector2(32,23)),false)
		_:
			object_sprite(origin, kind)
