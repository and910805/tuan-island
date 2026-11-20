extends "res://scripts/world_view.gd"

var kind := ""
var mill_preview_facing := 0
var thumbnail_art: RefCounted
const CACHE_KEY:=&"tuan_build_thumbnail_art"
## Nominal art cell: one 32px tile with 16px of headroom above it.
const CELL:=Rect2(0,0,32,48)

func _ready() -> void:
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	data = {"objects": {}}
	thumbnail_art = shared_art()
	village_art = thumbnail_art

## The one VillagePreview every thumbnail shares (root metadata; Main removes it).
static func shared_art() -> RefCounted:
	var cache_owner:=(Engine.get_main_loop() as SceneTree).root
	var art:RefCounted=cache_owner.get_meta(CACHE_KEY) if cache_owner.has_meta(CACHE_KEY) else null
	if art == null:
		art = VillagePreview.new()
		art.setup()
		cache_owner.set_meta(CACHE_KEY,art)
	return art

## Extent of what _draw() paints for `id`, in thumbnail pixels. Only art that
## leaves CELL far enough to be cut off on a 3x stage is listed (keep each entry
## in step with its _draw() branch); everything else reports CELL.
static func art_bounds(id:String) -> Rect2:
	match id:
		"waterworks", "ore_display":
			return Rect2(-8,0,48,48)
		"mine_drill":
			return Rect2(-8,8,48,48)
		"small_smelter":
			return Rect2(0,15,32,36)
		Industry.HOLLOW_BED:
			return Rect2(0,12,32,39)
		"long_bench":
			# VillagePreview.draw_prop: prop 11 at its own size, centred on the tile, feet at y=29.
			var art:=shared_art()
			if art.props.size()==16:
				var size:=Vector2(art.props[11].get_size())
				return Rect2((Vector2(0,16)+Vector2(16-size.x/2,29-size.y)).round(),size)
	return CELL

## Whole-pixel placement of `bounds` on a stage whose usable area is `room`,
## centred on the `frame`-sized control that holds the thumbnail: {zoom, position}.
## Art already inside the room at `max_zoom` keeps the shared cell placement
## (position zero). Anything else gets the largest whole-number zoom that fits,
## with the art itself centred in the frame.
static func stage_fit(bounds:Rect2,frame:Vector2,room:Vector2,max_zoom:int) -> Dictionary:
	var zoom:=maxi(max_zoom,1)
	while zoom>1 and (bounds.size.x*zoom>room.x or bounds.size.y*zoom>room.y):zoom-=1
	var allowed:=Rect2(((frame-room)*0.5).floor(),room)
	if zoom==max_zoom and allowed.encloses(Rect2(bounds.position*zoom,bounds.size*zoom)):
		return {"zoom":zoom,"position":Vector2.ZERO}
	return {"zoom":zoom,"position":((frame-bounds.size*zoom)*0.5).floor()-bounds.position*zoom}

func _draw() -> void:
	var origin := Vector2(0, 16)
	camera = Vector2(40, 30) * TILE - origin
	match kind:
		"floor", "stone_floor", "path", "spring_pebble_path":
			ground_tile(origin, kind)
		"roof", "greenhouse_roof", World.GREENHOUSE_GLASS.XINGHE_ROOF, World.TERRACOTTA_ROOF.KIND:
			roof_sprite(origin,1.0,kind)
		"assembly_table":
			draw_texture(preload("res://assets/automation/assembly-table-icon.png"),origin+Vector2(0,5))
		"mill":
			var mill := BakeryArt.village_mill_texture(mill_preview_facing) if mill_preview_facing >= 0 else BakeryArt.mill_texture()
			if mill != null:draw_texture_rect(mill,Rect2(origin+Vector2(0,-5),Vector2(32,37)),false)
		"inn_fabric_screen":
			draw_texture_rect(preload("res://assets/ui-life/inn-fabric-screen.png"),Rect2(origin+Vector2(0,5),Vector2(32,23)),false)
		"inn_quilt_bed":
			quilt_bed_sprite(origin+Vector2(7,-12),true,"",0.58)
		"inn_stone_footbath":
			draw_texture_rect(preload("res://assets/ui-life/inn-stone-footbath.png"),Rect2(origin+Vector2(0,5),Vector2(32,22)),false)
		"inn_luggage_rack":
			draw_texture_rect(preload("res://assets/ui-life/inn-luggage-rack.png"),Rect2(origin+Vector2(0,5),Vector2(32,22)),false)
		Industry.QUIET_BIRDHOUSE:
			draw_texture_rect(BirdhouseArt.HOUSE,Rect2(origin+Vector2(3,-2),Vector2(26,36)),false)
		Industry.LEAF_DESK:
			draw_texture_rect(LEAF_DESK_WIDE,Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		Industry.GRID_BOOKCASE:
			draw_texture_rect(GRID_BOOKCASE_TALL,Rect2(origin+Vector2(9,-2),Vector2(14,34)),false)
		World.RESIDENT_GOALS.FOREST_WARDROBE:
			draw_texture_rect(FOREST_WARDROBE_ART,Rect2(origin+Vector2(4,-2),Vector2(24,33)),false)
		Industry.OBSERVATION_DESK:
			draw_texture_rect(preload("res://assets/ui-life/crop-observation-desk.png"),Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		Industry.SEED_CABINET:
			draw_texture_rect(preload("res://assets/ui-life/seed-specimen-cabinet.png"),Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		Industry.AQUARIUM:
			draw_texture_rect(preload("res://assets/ui-life/small-aquarium.png"),Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		Industry.GLASS_FLOWER_TABLE:
			draw_texture_rect(preload("res://assets/ui-life/glass-flower-table.png"),Rect2(origin+Vector2(0,7),Vector2(32,24)),false)
		Industry.FOREST_ARCH:
			draw_texture_rect(ForestArchArt.WIDE,Rect2(origin+Vector2(0,3),Vector2(32,26)),false)
		Industry.VINE_ARCH:
			draw_texture_rect_region(VineArchArt.WIDE,Rect2(origin,Vector2(32,26)),VineArchArt.region("pink",false))
		Industry.POT_RACK:
			draw_texture_rect(preload("res://assets/ui-life/copper-flower-rack.png"),Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		World.ROOF_FIXTURES.HANGING_POT:
			draw_texture(HANGING_POT_ART,Vector2(5,12))
		Industry.NURSERY_BOX:
			draw_texture_rect(NURSERY_WIDE,Rect2(origin+Vector2(0,8),Vector2(32,16)),false)
		Industry.COAST_FISH_COUNTER:
			draw_texture_rect(FISH_COUNTER_WIDE,Rect2(origin+Vector2(0,8),Vector2(32,16)),false)
		Industry.TEA_DISPLAY_CABINET:
			draw_texture_rect(TEA_CABINET_WIDE,Rect2(origin+Vector2(0,7),Vector2(32,22)),false)
		Industry.TEA_SNACK_SHELF:
			draw_texture_rect(preload("res://assets/ui-life/tea-snack-shelf.png"),Rect2(origin,Vector2(32,32)),false)
		Industry.COAST_AWNING:
			draw_texture_rect(CoastAwningArt.WIDE,Rect2(origin+Vector2(0,5),Vector2(32,24)),false)
		Industry.IMPERFECT_TEA_PAVILION:
			# Both 96×96 layers (base, then canopy) scaled 3:1 into the thumbnail cell.
			PavilionArt.draw_thumbnail(self,origin)
		Industry.LEAF_MAT:
			draw_texture_rect(preload("res://scripts/leaf_mat_art.gd").TEXTURE,Rect2(origin,Vector2(32,32)),false)
		Industry.BRAIDED_RUG:
			draw_texture_rect(preload("res://assets/ui-life/braided-round-rug.png"),Rect2(origin,Vector2(32,32)),false)
		Industry.MUSHROOM_STOOL:
			draw_texture_rect(preload("res://assets/ui-life/mushroom-cap-stool.png"),Rect2(origin+Vector2(4,11),Vector2(24,20)),false)
		Industry.INDIGO_CUSHION:
			draw_texture(preload("res://assets/ui-life/indigo-cushion.png"),origin+Vector2(2,5))
		Industry.WOOD_CHAIR:
			draw_texture(WOOD_CHAIR_ART,origin+Vector2(4,2))
		Industry.MUSHROOM_TABLE:
			draw_texture_rect(preload("res://assets/ui-life/mushroom-cap-table.png"),Rect2(origin+Vector2(0,5),Vector2(32,25)),false)
		Industry.BAMBOO_TEA_TABLE:
			draw_texture_rect(BAMBOO_TABLE_WIDE,Rect2(origin+Vector2(0,7),Vector2(32,16)),false)
		Industry.PAPER_TEA_LAMP:
			draw_texture(PAPER_TEA_LAMP_ART,origin+Vector2(3,-1))
		Industry.CEDAR_BED:
			draw_texture_rect(CEDAR_BED_LONG,Rect2(origin+Vector2(8,-2),Vector2(16,35)),false)
		Industry.HOLLOW_BED:
			draw_texture_rect(preload("res://assets/ui-life/tree-hollow-bed.png"),Rect2(origin+Vector2(0,-4),Vector2(32,39)),false)
		Industry.COAST_CART:
			draw_texture_rect(preload("res://assets/ui-life/xiaoli-market-cart.png"),Rect2(origin+Vector2(0,-2),Vector2(32,35)),false)
		Industry.COAST_REGISTER:
			draw_texture_rect(REGISTER_WIDE,Rect2(origin+Vector2(0,5),Vector2(32,20)),false)
		Industry.SHELL_TABLE:
			draw_texture_rect(preload("res://assets/ui-life/shell-round-table.png"),Rect2(origin+Vector2(0,3),Vector2(32,28)),false)
		Industry.ROUNDED_TABLE:
			draw_texture_rect(ROUNDED_TABLE_WIDE,Rect2(origin+Vector2(0,8),Vector2(32,19)),false)
		Industry.BEACH_CHAIR:
			draw_texture_rect(BEACH_LONG,Rect2(origin+Vector2(8,-2),Vector2(16,34)),false)
		Industry.BAMBOO_LOUNGER:
			draw_texture_rect(preload("res://assets/ui-life/bamboo-lounger-long.png"),Rect2(origin+Vector2(8,-2),Vector2(16,34)),false)
		Industry.RIVERSIDE_SCREEN:
			draw_texture_rect(preload("res://assets/ui-life/riverside-screen-wide.png"),Rect2(origin+Vector2(0,4),Vector2(32,25)),false)
		World.WALL_FIXTURES.BARK_FRAME:
			BarkFrameArt.draw(self,Vector2(0,11))
		World.WALL_FIXTURES.HOME_SIGN:
			draw_texture(HOME_SIGN_ART,origin+Vector2(0,6))
		World.WALL_FIXTURES.TOOL_BOARD:
			draw_texture_rect(TOOL_BOARD_ART,Rect2(origin+Vector2(0,8),Vector2(32,14)),false)
		World.WALL_FIXTURES.BAMBOO_CURTAIN:
			BambooCurtainArt.draw_thumbnail(self,Vector2.ZERO)
		World.WALL_FIXTURES.WATER_LISTENING_CHIME:
			preload("res://scripts/water_listening_chime_art.gd").draw_thumbnail(self,Vector2.ZERO)
		World.WALL_FIXTURES.LIFEBUOY:
			draw_texture(LIFEBUOY_ART,Vector2(4,8))
		"dye_table":
			draw_texture(preload("res://assets/bakery/dye-table-icon.png"),origin+Vector2(0,5))
		"clay_kiln":
			draw_texture_rect(preload("res://assets/bakery/clay-kiln.png"),Rect2(origin+Vector2(0,-7),Vector2(32,40)),false)
		"small_smelter":
			draw_texture_rect(preload("res://assets/industry/small-smelter.png"),Rect2(origin+Vector2(0,-1),Vector2(32,36)),false)
		Industry.KITCHEN_STOVE:
			draw_texture_rect(KITCHEN_STOVE_ART,Rect2(origin,Vector2(32,32)),false)
		Industry.WORKBENCH:
			# C08: the catalog icon shows the new 2x1 worktop (squeezed to the 32px badge) when its texture exists.
			var worktop:=workbench_texture(false)
			if worktop!=null:draw_texture_rect(worktop,Rect2(origin+Vector2(0,8),Vector2(32,16)),false)
			else:object_sprite(origin,kind)
		Industry.STONE_WORKBENCH:
			# C11: same squeeze as the C08 worktop; plain stone rectangles without the texture.
			var stone_top:=stone_workbench_texture(false)
			if stone_top!=null:draw_texture_rect(stone_top,Rect2(origin+Vector2(0,8),Vector2(32,16)),false)
			else:draw_stone_bench_rects(origin)
		"master_bench":
			draw_texture_rect(preload("res://assets/ui-life/master-bench.png"),Rect2(origin+Vector2(0,5),Vector2(32,19)),false)
		World.RESIDENT_GOALS.COTTON_SOFA:
			draw_texture_rect(COTTON_SOFA_WIDE,Rect2(origin+Vector2(0,6),Vector2(32,21)),false)
		World.RESIDENT_GOALS.BAMBOO_BENCH:
			draw_texture_rect(independent_seat_art(kind,false),Rect2(origin+Vector2(0,7),Vector2(32,18)),false)
		"spring_stone_bench":
			draw_texture_rect(preload("res://assets/ui-life/spring-stone-bench.png"),Rect2(origin+Vector2(0,5),Vector2(32,23)),false)
		_:
			object_sprite(origin, kind)
