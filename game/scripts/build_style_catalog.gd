extends RefCounted
## T051 / T069 — standalone two-style build catalog (茶屋 tea_house, 海邊 coast).
##
## STANDALONE DATA + HELPERS. Nothing in the game preloads this file yet, and it
## never reads or writes a World, a save, a snapshot or a network message.
##
## Contract (keeps item IDs and placement semantics):
## * Every entry names an EXISTING World.BUILD key in `kind`. No new item IDs,
##   recipes, layers, unlock gates or collision rules are introduced. Placing a
##   style entry is exactly `world.act(token, request_id, "build", tile, kind)`;
##   see placement_request(). The stored object is identical to placing `kind`
##   from the normal build catalog — a style is NOT persisted per piece.
## * `layer`, `solid` and `footprint` are declared for UI consumers and are
##   checked against world.gd / blueprint_design.gd by validate() and by
##   tests/test_build_style_catalog.gd (including live placement).
##   Every current World.BUILD piece occupies exactly one 32px tile.
## * `materials` are REFERENCES to regions of PNGs that already exist in
##   res://assets (via the art script that owns each sheet). They are mood /
##   swatch references for preview and for future re-skin art. They do not
##   change runtime rendering, and a reference's own drawing size (e.g. the 6x3
##   salt shed) never becomes a placement footprint.
## * Preview: the existing res://scripts/pixel_build_thumbnail.gd draws `kind`
##   (32x48 frame). Style-specific sprites do not exist yet; the preview shows
##   the current base art plus the style's material swatches and palette.
##
## T069 status: this covers 2 of 6 styles and 15 distinct existing kinds, far
## from the 96-item target. coverage() reports this honestly.

const VERSION := 1
const FOOTPRINT := Vector2i(1, 1)
const TILE_PX := 32
const PREVIEW_SCRIPT := "res://scripts/pixel_build_thumbnail.gd"
## Same frame HouseUI uses for BuildThumbnail (one tile wide, object height).
const PREVIEW_SIZE := Vector2i(32, 48)
const TARGET_STYLES := 6
const TARGET_ITEMS := 96
## House structure kinds every style must keep so rooms, doors and automatic
## roofs keep working (World.AUTO_ROOF_BUILDS + roof + path to the door).
const STRUCTURE_KINDS := ["floor", "stone_floor", "path", "wall", "window", "door", "roof"]

const WORLD_SCRIPT := "res://scripts/world.gd"
const BLUEPRINT_DESIGN_SCRIPT := "res://scripts/blueprint_design.gd"

## Material reference providers -> the art script that defines the sheet.
## Region formulas mirror the owning script exactly (see resolve_material()).
const PROVIDERS := {
	"village_tile": {"script": "res://scripts/village_preview_art.gd", "path": "res://assets/village-preview/terrain.png"},
	"village_prop": {"script": "res://scripts/village_preview_art.gd", "path": "res://assets/village-preview/props.png"},
	"furniture": {"script": "res://scripts/furniture_sprite_art.gd", "path": "res://assets/ui-life/furniture.png"},
	"stone_floor": {"path": "res://assets/ui-life/stone-floor.png"},
	"tea_icon": {"script": "res://scripts/tea_ceramics_art.gd", "path": "res://assets/tea-ceramics/items.png"},
	"tea_building": {"script": "res://scripts/tea_ceramics_art.gd", "path": "res://assets/tea-ceramics/buildings.png"},
	"salt_terrain": {"script": "res://scripts/salt_art.gd", "sheet": "terrain"},
	"salt_structure": {"script": "res://scripts/salt_art.gd", "sheet": "structures"},
	"salt_item": {"script": "res://scripts/salt_art.gd", "sheet": "items"},
}
## Building indices actually drawn by TeaCeramicsArt.draw_backdrop (0 maokong, 1-2 the other tea stop).
const TEA_BUILDING_INDICES := [0, 1, 2]

const STYLES := {
	"tea_house": {
		"name": "茶屋",
		"summary": "貓空茶屋的木棧前庭、茶園土徑與陶罐茶具。",
		"art_reference": "tea_ceramics_art.gd (maokong backdrop, items.png, buildings.png)",
		# Tints passed by TeaCeramicsArt.ground() for the maokong lane, floor rows, field and edge.
		"palette": ["ccb292", "b5a181", "a2b481", "566d57"],
		"palette_source": "tea_ceramics_art.gd ground() maokong tints",
	},
	"coast": {
		"name": "海邊",
		"summary": "鹽田海岸的木棧、老鹽埕地坪、圍籬與鹽寮。",
		"art_reference": "salt_art.gd (salt-terrain.png, salt-structures.png, salt-items.png)",
		# world_view.gd water_tile() shallow/foam and ground_tile() stone path colours.
		"palette": ["76b9b4", "a8d9ca", "d5d1b7", "b6b7a3"],
		"palette_source": "world_view.gd water_tile() and ground_tile() path colours",
	},
}

## One row per (style, existing kind). `id` = "<style>.<kind>".
## `solid` = blocks movement when placed (door: while closed; "toggle" notes it).
const ENTRIES := [
	# ---------------------------------------------------------------- 茶屋
	{"id": "tea_house.floor", "style": "tea_house", "kind": "floor", "layer": "ground", "solid": false,
		"materials": [["village_tile", 10], ["tea_building", 0]], "note": "茶屋前庭木棧地坪"},
	{"id": "tea_house.stone_floor", "style": "tea_house", "kind": "stone_floor", "layer": "ground", "solid": false,
		"materials": [["stone_floor", 0], ["tea_building", 0]], "note": "茶屋的暖灰石地坪"},
	{"id": "tea_house.path", "style": "tea_house", "kind": "path", "layer": "ground", "solid": false,
		"materials": [["village_tile", 4]], "note": "茶園步道土石色"},
	{"id": "tea_house.wall", "style": "tea_house", "kind": "wall", "layer": "objects", "solid": true,
		"materials": [["tea_building", 0], ["tea_building", 1]], "note": "茶屋木作外牆"},
	{"id": "tea_house.window", "style": "tea_house", "kind": "window", "layer": "objects", "solid": true,
		"materials": [["furniture", "window"], ["tea_building", 0]], "note": "茶屋格窗"},
	{"id": "tea_house.door", "style": "tea_house", "kind": "door", "layer": "objects", "solid": true, "toggle": "door",
		"materials": [["furniture", "door"], ["tea_building", 0]], "note": "茶屋木門"},
	{"id": "tea_house.roof", "style": "tea_house", "kind": "roof", "layer": "roofs", "solid": false,
		"materials": [["tea_building", 0], ["tea_building", 2]], "note": "茶屋屋簷"},
	{"id": "tea_house.table", "style": "tea_house", "kind": "table", "layer": "objects", "solid": true,
		"materials": [["furniture", "table"], ["tea_icon", "tea_jar"]], "note": "奉茶小桌與陶罐"},
	{"id": "tea_house.chair", "style": "tea_house", "kind": "chair", "layer": "objects", "solid": false,
		"materials": [["furniture", "chair"]], "note": "茶席木椅"},
	{"id": "tea_house.stove", "style": "tea_house", "kind": "stove", "layer": "objects", "solid": true,
		"materials": [["furniture", "stove"], ["tea_icon", "tea_deep"]], "note": "焙茶石灶"},
	{"id": "tea_house.lamp", "style": "tea_house", "kind": "lamp", "layer": "objects", "solid": false,
		"materials": [["furniture", "lamp"], ["tea_icon", "tea_light"]], "note": "茶席木燈"},
	{"id": "tea_house.planter", "style": "tea_house", "kind": "planter", "layer": "objects", "solid": true,
		"materials": [["tea_icon", "tea_bush"], ["village_prop", 4]], "note": "茶樹盆景花箱"},
	{"id": "tea_house.long_bench", "style": "tea_house", "kind": "long_bench", "layer": "objects", "solid": true,
		"materials": [["village_prop", 11]], "note": "茶屋簷下長椅"},
	{"id": "tea_house.bed", "style": "tea_house", "kind": "bed", "layer": "objects", "solid": true,
		"materials": [["furniture", "bed"], ["tea_icon", "fiber_packet"]], "note": "茶屋小床"},
	# ---------------------------------------------------------------- 海邊
	{"id": "coast.floor", "style": "coast", "kind": "floor", "layer": "ground", "solid": false,
		"materials": [["salt_terrain", "plank"], ["salt_terrain", "heritage_floor"]], "note": "海岸木棧與鹽埕地坪"},
	{"id": "coast.stone_floor", "style": "coast", "kind": "stone_floor", "layer": "ground", "solid": false,
		"materials": [["stone_floor", 0], ["salt_terrain", "heritage_floor"]], "note": "鹽埕的灰石地坪"},
	{"id": "coast.path", "style": "coast", "kind": "path", "layer": "ground", "solid": false,
		"materials": [["salt_terrain", "sand"], ["salt_terrain", "coast"]], "note": "沙地步道"},
	{"id": "coast.wall", "style": "coast", "kind": "wall", "layer": "objects", "solid": true,
		"materials": [["salt_terrain", "heritage_fence"], ["salt_structure", "shed"]], "note": "鹽寮木板牆"},
	{"id": "coast.window", "style": "coast", "kind": "window", "layer": "objects", "solid": true,
		"materials": [["furniture", "window"], ["salt_structure", "shed"]], "note": "鹽寮採光窗"},
	{"id": "coast.door", "style": "coast", "kind": "door", "layer": "objects", "solid": true, "toggle": "door",
		"materials": [["furniture", "door"], ["salt_structure", "shed"]], "note": "鹽寮木門"},
	{"id": "coast.roof", "style": "coast", "kind": "roof", "layer": "roofs", "solid": false,
		"materials": [["salt_structure", "shed"], ["salt_structure", "bus_stop"]], "note": "鹽寮屋頂"},
	{"id": "coast.chest", "style": "coast", "kind": "chest", "layer": "objects", "solid": true,
		"materials": [["salt_structure", "coop_chest"], ["furniture", "chest"]], "note": "合作社共用箱"},
	{"id": "coast.bench", "style": "coast", "kind": "bench", "layer": "objects", "solid": true,
		"materials": [["furniture", "bench"], ["salt_item", "salt_rake_kit"]], "note": "收鹽工作台"},
	{"id": "coast.long_bench", "style": "coast", "kind": "long_bench", "layer": "objects", "solid": true,
		"materials": [["village_prop", 11], ["salt_structure", "bus_stop"]], "note": "候車亭長椅"},
	{"id": "coast.lamp", "style": "coast", "kind": "lamp", "layer": "objects", "solid": false,
		"materials": [["furniture", "lamp"], ["salt_terrain", "plank"]], "note": "木棧邊小燈"},
	{"id": "coast.sign", "style": "coast", "kind": "sign", "layer": "objects", "solid": false,
		"materials": [["salt_structure", "sign"], ["furniture", "sign"]], "note": "鹽田解說牌"},
	{"id": "coast.bed", "style": "coast", "kind": "bed", "layer": "objects", "solid": true,
		"materials": [["furniture", "bed"], ["salt_item", "sea_salt"]], "note": "海邊小床"},
	{"id": "coast.table", "style": "coast", "kind": "table", "layer": "objects", "solid": true,
		"materials": [["furniture", "table"], ["salt_item", "salt_grilled_fish"]], "note": "海產小桌"},
]

## What UI / placement integration still needs. None of this is implemented;
## owners are suggestions for the root integrator.
const INTEGRATION_REQUIREMENTS := [
	{"id": "ui_style_filter", "area": "UI", "files": ["scripts/life_ui_panels.gd"],
		"requirement": "Add a style filter (全部／茶屋／海邊) to the build catalog. Selecting an entry must set app.building = entry.kind and call _select_tool(\"build\"), the same flow as HouseUI.choose_part. No new action or request field."},
	{"id": "ui_preview_card", "area": "UI", "files": ["scripts/life_ui_panels.gd", "scripts/pixel_build_thumbnail.gd"],
		"requirement": "Use preview_spec(): a 32x48 BuildThumbnail of kind, the style name + base recipe name, and up to 2 material swatches drawn from resolve_material() with nearest filtering. Must still fit at 1024x640 and 1280x800 (run UI tests with -- --village-art-preview)."},
	{"id": "ui_recipe_truth", "area": "UI", "files": ["scripts/life_ui_panels.gd"],
		"requirement": "Cost, unlock text and per-person limits must come from World.BUILD / Village.unlocked as today. The style must not suggest a different cost or a different item."},
	{"id": "placement_unchanged", "area": "placement", "files": ["scripts/world.gd"],
		"requirement": "No change. world.act(..., \"build\", tile, entry.kind) is the only placement path; layer, collision, door toggle, auto-roof, undo and blueprint behave as for the base kind."},
	{"id": "persist_style_optional", "area": "save/net", "files": ["scripts/world.gd", "scripts/save_schema.gd", "scripts/blueprint_design.gd", "scripts/construction_history.gd"],
		"requirement": "ONLY if pieces should keep their look after placement: add an optional obj.style field (allowlisted style id), a save schema version bump with migration, blueprint piece settings, undo snapshot and snapshot redaction rules. Out of scope here; until then a style is a catalog filter and preview only."},
	{"id": "render_reskin_optional", "area": "art", "files": ["scripts/world_view.gd", "scripts/furniture_sprite_art.gd"],
		"requirement": "Style sprites need new PNG art: 32x32 ground/roof tiles and 32x48 objects drawn at at+(0,-16), same anchor as FurnitureSpriteArt. Requires persist_style_optional first; never draw a style from the local catalog selection alone (other players would disagree)."},
]

# ---------------------------------------------------------------- queries

static func style_ids() -> Array:
	var ids: Array = STYLES.keys()
	ids.sort()
	return ids

static func style(style_id: String) -> Dictionary:
	return STYLES.get(style_id, {}).duplicate(true)

## All entries, or only one style's, in catalog order (deep copies).
static func entries(style_id: String = "") -> Array:
	var out: Array = []
	for row in ENTRIES:
		if style_id.is_empty() or row.style == style_id:
			out.append(row.duplicate(true))
	return out

static func entry(entry_id: String) -> Dictionary:
	for row in ENTRIES:
		if row.id == entry_id:
			return row.duplicate(true)
	return {}

static func kinds(style_id: String) -> Array:
	var out: Array = []
	for row in ENTRIES:
		if row.style == style_id:
			out.append(row.kind)
	return out

static func distinct_kinds() -> Array:
	var seen := {}
	for row in ENTRIES:
		seen[row.kind] = true
	var out: Array = seen.keys()
	out.sort()
	return out

## The exact arguments World.act expects. Deliberately carries no style field.
static func placement_request(entry_id: String) -> Dictionary:
	var row := entry(entry_id)
	if row.is_empty():
		return {"ok": false, "message": "unknown style entry"}
	return {"ok": true, "action": "build", "extra": str(row.kind)}

## Display label: style name + the existing recipe name (read from World.BUILD).
static func label(entry_id: String) -> String:
	var row := entry(entry_id)
	if row.is_empty():
		return ""
	var build: Dictionary = load(WORLD_SCRIPT).BUILD
	var recipe: Dictionary = build.get(row.kind, {})
	return "%s・%s" % [STYLES[row.style].name, str(recipe.get("name", row.kind))]

static func coverage() -> Dictionary:
	return {"styles": STYLES.size(), "target_styles": TARGET_STYLES, "entries": ENTRIES.size(),
		"distinct_kinds": distinct_kinds().size(), "target_items": TARGET_ITEMS,
		"t069_complete": false, "new_item_ids": 0}

# ---------------------------------------------------------------- materials

## Resolve [provider, id] to {ok, provider, id, path, rect} using the owning art
## script's own constants, so a stale reference fails instead of drawing junk.
static func resolve_material(ref) -> Dictionary:
	var bad := {"ok": false, "provider": "", "id": null, "path": "", "rect": Rect2i()}
	if typeof(ref) != TYPE_ARRAY or ref.size() != 2 or typeof(ref[0]) != TYPE_STRING:
		return bad
	var provider: String = ref[0]
	var id = ref[1]
	if not PROVIDERS.has(provider):
		return bad
	var info: Dictionary = PROVIDERS[provider]
	var out := {"ok": false, "provider": provider, "id": id, "path": str(info.get("path", "")), "rect": Rect2i()}
	match provider:
		"stone_floor":
			if typeof(id) == TYPE_INT and id == 0:out.rect = Rect2i(0, 0, 32, 32)
		"village_tile":
			if typeof(id) == TYPE_INT and id >= 0 and id < 16:
				out.rect = Rect2i((id % 4) * 32, (id / 4) * 32, 32, 32)
		"village_prop":
			if typeof(id) == TYPE_INT and id >= 0 and id < 16:
				out.rect = Rect2i((id % 4) * 64, (id / 4) * 64, 64, 64)
		"furniture":
			var kinds_list: Array = load(info.script).KINDS
			var index: int = kinds_list.find(id) if typeof(id) == TYPE_STRING else -1
			if index >= 0:
				out.rect = Rect2i((index % 4) * 32, (index / 4) * 48, 32, 48)
		"tea_icon":
			var icons: Array = load(info.script).ICONS
			var index: int = icons.find(id) if typeof(id) == TYPE_STRING else -1
			if index >= 0:
				out.rect = Rect2i(index * 32, 0, 32, 32)
		"tea_building":
			if typeof(id) == TYPE_INT and id in TEA_BUILDING_INDICES:
				out.rect = Rect2i(id * 128, 0, 128, 128)
		"salt_terrain", "salt_structure", "salt_item":
			var salt = load(info.script)
			var sheet: Dictionary = salt.SHEETS[info.sheet]
			out.path = str(salt.DEFAULT_DIR) + str(sheet.file)
			if typeof(id) == TYPE_STRING:
				if provider == "salt_terrain" and salt.TERRAIN.has(id):
					out.rect = salt.terrain_window(int(salt.TERRAIN[id]))
				elif provider == "salt_structure" and salt.STRUCTURES.has(id):
					out.rect = salt.STRUCTURES[id].clip
				elif provider == "salt_item" and salt.ITEMS.has(id):
					out.rect = salt.item_clip(id)
	out.ok = out.rect.has_area() and not str(out.path).is_empty()
	return out

## Everything a preview card needs. No textures are loaded here.
static func preview_spec(entry_id: String) -> Dictionary:
	var row := entry(entry_id)
	if row.is_empty():
		return {"ok": false}
	var swatches: Array = []
	for ref in row.materials:
		swatches.append(resolve_material(ref))
	var style_row: Dictionary = STYLES[row.style]
	return {"ok": true, "id": row.id, "style": row.style, "style_name": style_row.name,
		"script": PREVIEW_SCRIPT, "kind": row.kind, "size": PREVIEW_SIZE,
		"footprint": FOOTPRINT, "swatches": swatches, "palette": style_row.palette.duplicate(),
		# Base art only; style sprites are not delivered yet.
		"style_sprite": false, "note": row.note}

# ---------------------------------------------------------------- validation

## Layer the existing placement code uses for `kind` (world.gd _build_piece).
static func expected_layer(kind: String) -> String:
	var design = load(BLUEPRINT_DESIGN_SCRIPT)
	if kind in design.ROOF_KINDS:
		return "roofs"
	if kind in design.GROUND_KINDS:
		return "ground"
	return "objects"

## Closed-state collision the existing World.blocked() applies for `kind`.
static func expected_solid(kind: String) -> bool:
	return kind == "door" or kind in load(WORLD_SCRIPT).UNDO_SOLID

## Self-check against current definitions. Returns human-readable problems.
static func validate() -> Array:
	var problems: Array = []
	var build: Dictionary = load(WORLD_SCRIPT).BUILD
	var ids := {}
	var pairs := {}
	for row in ENTRIES:
		var id := str(row.get("id", ""))
		if ids.has(id):
			problems.append("duplicate entry id " + id)
		ids[id] = true
		var style_id := str(row.get("style", ""))
		var kind := str(row.get("kind", ""))
		if not STYLES.has(style_id):
			problems.append(id + " unknown style")
		if id != style_id + "." + kind:
			problems.append(id + " id must be <style>.<kind>")
		var pair := style_id + "|" + kind
		if pairs.has(pair):
			problems.append(id + " repeats a kind inside its style")
		pairs[pair] = true
		if not build.has(kind):
			problems.append(id + " kind is not an existing World.BUILD key")
			continue
		if row.get("layer", "") != expected_layer(kind):
			problems.append(id + " layer disagrees with placement code")
		if bool(row.get("solid", false)) != expected_solid(kind):
			problems.append(id + " collision disagrees with World.blocked")
		var materials = row.get("materials", [])
		if typeof(materials) != TYPE_ARRAY or materials.is_empty():
			problems.append(id + " has no material reference")
			continue
		for ref in materials:
			if not resolve_material(ref).ok:
				problems.append("%s material %s does not resolve" % [id, str(ref)])
	for style_id in STYLES:
		var covered := kinds(style_id)
		for kind in STRUCTURE_KINDS:
			if kind not in covered:
				problems.append("%s misses structure kind %s" % [style_id, kind])
		for hex in STYLES[style_id].palette:
			if not Color.html_is_valid(hex):
				problems.append("%s palette colour %s invalid" % [style_id, hex])
	return problems
