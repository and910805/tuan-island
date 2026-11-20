extends RefCounted
## Production salt asset adapter (Beimen 鹽風合作鹽田, chapter 4), reconciled
## from the root-reviewed staged adapter work/salt/staged-full-art/salt_art.gd
## (sha 4d9dbdb6...) plus the production panel_art() provider used by main.gd.
## Full salt asset adapter. Display only:
## no World preload, no registration, no collision, no gameplay mutation. Every
## texture is rebuilt in memory from the delivered built-in image_gen PNGs with
## ONE fixed, aspect-preserving source window per object (Image.blit_rect inside
## that object's clip rectangle + INTERPOLATE_NEAREST resize) and cached. No
## per-state autocrop, so every state of one object keeps identical anchors.
## Unknown IDs, missing files and wrong-size sheets return null (recorded in
## `errors`); nothing ever falls back to geometric stand-in art.
##
## API-compatible superset of game/scripts/salt_art.gd (2026-11-14 13:08 version):
## same SHEETS/TERRAIN/PAN_STATES/MACHINE_ANCHOR/RESIDENT_FEET names and the
## same has_*/..._texture/draw_anchored/set_sheet_path/clear_cache functions.
## Added: configure() base-dir hook, provider(kind,id) for SaltPanUI.art_provider,
## pan_art_id(view), prop_texture() pass-through to salt_props_art.gd, and the
## RUNNING machine frame provider (machine_frame / draw_machine).
##
## Source sheets (game copies must stay byte-identical to work/salt/art-source):
##   salt-items.png       1254x1254 RGBA, 2x2 cells of 627
##   salt-pan-states.png  1774x887  RGBA, 4x2 cells, x 0,444,887,1331,1774 / y 0,444,887
##   salt-terrain.png     1254x1254 RGB,  4x4 cells, roundi(i*1254/4)=0,314,627,941,1254
##   salt-resident.png    1254x1254 RGBA, 2x2 cells (front, front_blink, back, right)
##   salt-portrait.png    1254x1254 RGBA, single bust
##   salt-structures.png  1774x887  RGBA, 2x2 RECTANGULAR cells; the shed crosses
##                        x887, so root's clip rectangles are used (see STRUCTURES)
##   salt-machines.png    1254x1254 RGBA, 2x2 cells of 627 (wheel working, collector
##                        working, empty wheel pad, empty collector pad)
##   salt-props.png       via salt_props_art.gd (gates + idle machines, 64x64)
##
## Generator haze: every RGBA sheet carries alpha 1..8 haze. Textures built HERE
## zero native pixels with alpha <= ALPHA_VISIBLE after downsampling (no faint
## halos). Textures that come from salt_props_art.gd keep that adapter's haze.
##
## ANIMATION (honest scope, see work/salt/staged-full-art/result.json):
## * salt-machines.png working frames are full redraws, not registered to the
##   idle props: after the best translation (wheel dy=-20, collector dx=-1
##   dy=-22 source px) 39% / 36% of visible source px still differ, the wheel's
##   rim/paddles and the outlet pipe moved (~3 native px). Whole-body idle <->
##   working flipping would wobble the machine, so it is NOT offered.
## * Running frames keep the idle props frame as a pixel-stable base and change
##   only clipped regions (animated_rois): waterwheel = the idle frame's OWN
##   water pixels (flume + outlet stream, colour-masked) cyclically advanced
##   along the flow direction, so silhouette/alpha never change but streaks
##   move; salt collector = the registered tray-interior window of the working
##   frame (rake lowered into the salt) on phases 2..3, plus the working frame's
##   real falling salt-grain pixels stepping down toward the basket every phase.
## * The wheel paddles do NOT rotate and the rake arm above the tray does not
##   move: a credible rotation needs a separately delivered, registered wheel
##   layer (see result.json needed_asset_fixes).
## * Reduced motion / not running => exactly the idle props texture (same object).
## * brine_alt is a static pan id only: inner tiles + rim drift, never flipped.

const DEFAULT_DIR := "res://assets/salt/"
const DIR := DEFAULT_DIR # compat name
const DEFAULT_PROPS_SCRIPT := "res://scripts/salt_props_art.gd"
const ALPHA_VISIBLE := 8

const SHEETS := {
	"terrain": {"file": "salt-terrain.png", "size": Vector2i(1254, 1254)},
	"pans": {"file": "salt-pan-states.png", "size": Vector2i(1774, 887)},
	"machines": {"file": "salt-machines.png", "size": Vector2i(1254, 1254)},
	"structures": {"file": "salt-structures.png", "size": Vector2i(1774, 887)},
	"resident": {"file": "salt-resident.png", "size": Vector2i(1254, 1254)},
	"portrait": {"file": "salt-portrait.png", "size": Vector2i(1254, 1254)},
	"items": {"file": "salt-items.png", "size": Vector2i(1254, 1254)},
	"props": {"file": "salt-props.png", "size": Vector2i(1254, 1254)},
}
## File names inside work/salt/art-source (for isolated tests: configure(dir, ART_SOURCE_FILES)).
const ART_SOURCE_FILES := {
	"terrain": "salt-terrain-source.png",
	"pans": "salt-pan-states-source.png",
	"machines": "salt-machines-source.png",
	"structures": "salt-structures-source.png",
	"resident": "salt-resident-source.png",
	"portrait": "salt-portrait-source.png",
	"items": "salt-items-source.png",
	"props": "salt-props-source-v2.png",
}

# ---------------------------------------------------------------- items
# 2x2 cells of 627 -> whole square cell to 32x32 (root: "each 627 square cell may
# be resized 32px nearest"; scale 19.59, aspect exact). Measured alpha>8 bounds
# (absolute): sea_salt x106..537 y124..582, wheel kit x679..1188 y105..590,
# rake kit x50..594 y678..1191, fish x649..1219 y777..1127: all inside the cell.
const ICON_SIZE := Vector2i(32, 32)
const ITEMS := {
	"sea_salt": Vector2i(0, 0),
	"salt_wheel_kit": Vector2i(627, 0),
	"salt_rake_kit": Vector2i(0, 627),
	"salt_grilled_fish": Vector2i(627, 627),
}
const ITEM_WINDOW := Rect2i(0, 0, 627, 627) # cell-relative

# ---------------------------------------------------------------- pans
# 8 states, rounded boundaries (443/444 px cells). Measured alpha>8 cell-relative
# union of all states x30..415 y34..394 (each state within +-2 px). ONE window
# for every state: 396x396 (= 96*4.125) at cell-relative (25,16), centred on the
# union, clipped to the state's own cell -> pan rim on the same native px always.
const PAN_X := [0, 444, 887, 1331, 1774]
const PAN_Y := [0, 444, 887]
const PAN_WINDOW := Rect2i(25, 16, 396, 396)
const PAN_SIZE := Vector2i(96, 96)
const PAN_STATES := ["empty", "brine", "evaporating_1", "evaporating_2", "salt", "diluted", "covered", "brine_alt"]

# ---------------------------------------------------------------- terrain
# Opaque RGB 4x4. Each 32x32 tile = its WHOLE cell (314 or 313 px, clipped to
# the cell so neighbours never leak); 313/314 aspect drift <= 0.32%, inherent to
# the sheet, not a stretch into an arbitrary square.
const TERRAIN_BOUNDS := [0, 314, 627, 941, 1254]
const TILE := Vector2i(32, 32)
const TERRAIN := {
	"sand": 0, "sand_b": 1, "ridge": 2, "ridge_b": 3,
	"sea": 4, "sea_b": 5, "channel": 6, "channel_b": 7,
	"plank": 8, "coast": 9, "coast_b": 10, "shore": 11,
	"heritage_floor": 12, "heritage_fence": 13, "yard": 14, "yard_b": 15,
}
## shore = sea LEFT/west, sand RIGHT/east: only valid down the western coast.

# ---------------------------------------------------------------- resident
# Cell-relative bounds: front x146..489 y24..604, blink x145..489 y24..604,
# back x146..484 y25..604, right x161..475 y31..604 (feet y604 everywhere).
# One window (118,5,400,600) = 32x48 * 12.5 for all poses; feet native row 47.
const RESIDENT_WINDOW := Rect2i(118, 5, 400, 600)
const RESIDENT_SIZE := Vector2i(32, 48)
const RESIDENT_FEET := Vector2i(16, 48)
const POSES := {"front": Vector2i(0, 0), "front_blink": Vector2i(627, 0), "back": Vector2i(0, 627), "right": Vector2i(627, 627)}
## "left" = horizontal mirror of "right" (window centre 318 == right pose centre 318).
## "front_blink" = front texture with ONLY this native eye ROI taken from the blink
## cell (the rest of the blink cell has ~1px edge noise; not a whole-body swap).
const BLINK_ROI := Rect2i(9, 12, 14, 4)
const BLINK_PERIOD := 4.0
const BLINK_SECONDS := 0.15

# Portrait: whole 1254 canvas -> 64x64 (scale 19.59, aspect exact, nothing clipped:
# bust bounds x116..1120 y62..1226).
const PORTRAIT_WINDOW := Rect2i(0, 0, 1254, 1254)
const PORTRAIT_SIZE := Vector2i(64, 64)
const PORTRAIT_IDS := ["salt_worker", "a_shai"]

# ---------------------------------------------------------------- structures
# Root clip rectangles (shed crosses x887!). Measured alpha>8 bounds (absolute):
#   shed     x82..902    y27..438  -> 192x128, scale 4.375 (window 840x560), visible ~188x94
#   bus_stop x1065..1629 y66..433  ->  96x64,  scale 6     (window 576x384), visible ~94x61
#            (root suggested 64x64, but that leaves the roof at 41px, BELOW a 46px
#            actor's head in the native preview; 96x64 keeps aspect, roof ~2 tiles.
#            Visual is 3 tiles wide over a 1x1 contract cell: lead decides collision.)
#   sign     x240..725   y493..861 ->  32x48,  scale 15.25 (window 488x732), visible 32x25
#   chest    x1038..1597 y511..854 ->  32x32,  scale 17.5  (window 560x560), visible 32x20
# Windows: native aspect exactly, centred on the bounds, bottom = feet + 3 source
# px; overhang outside the clip is transparent. Anchor = bottom centre (feet).
const STRUCTURES := {
	"shed": {"clip": Rect2i(0, 0, 930, 445), "window": Rect2i(72, -119, 840, 560), "size": Vector2i(192, 128), "footprint": Vector2i(6, 3)},
	"bus_stop": {"clip": Rect2i(930, 0, 844, 445), "window": Rect2i(1059, 52, 576, 384), "size": Vector2i(96, 64), "footprint": Vector2i(1, 1)},
	"sign": {"clip": Rect2i(0, 445, 887, 442), "window": Rect2i(238, 132, 488, 732), "size": Vector2i(32, 48), "footprint": Vector2i(1, 1)},
	"coop_chest": {"clip": Rect2i(887, 445, 887, 442), "window": Rect2i(1038, 297, 560, 560), "size": Vector2i(32, 32), "footprint": Vector2i(1, 1)},
}
const STRUCTURE_ALIASES := {"heritage_sign": "sign", "public_sign": "sign", "chest": "coop_chest", "bus": "bus_stop"}

# ---------------------------------------------------------------- machines
# Same 9 src px per native px as salt-props.png (576 window -> 64x64, feet (32,64)).
# Empty pads reuse the idle props frame's cell-relative x (wheel 30, collector 10:
# idle x72 == pad x72 left edge) and are bottom-anchored 3px under their own feet
# (wheel pad y585 -> 12, collector pad y584 -> 11) => native foot row 63.
const MACHINE_CELL := 627
const MACHINE_SIZE := Vector2i(64, 64)
const MACHINE_ANCHOR := Vector2i(32, 64)
const MACHINE_KINDS := ["waterwheel", "salt_collector"]
const FOUNDATIONS := {
	"waterwheel_empty": {"cell": Vector2i(0, 627), "window": Rect2i(30, 12, 576, 576)},
	"salt_collector_empty": {"cell": Vector2i(627, 627), "window": Rect2i(10, 11, 576, 576)},
}
## Working cell of the collector registered onto the idle props window (10,-10):
## best translation working->idle = (-1,-22) source px, so the working window is (11,12).
const COLLECTOR_WORKING := {"cell": Vector2i(627, 0), "window": Rect2i(11, 12, 576, 576)}
const MACHINES := ["waterwheel", "salt_collector", "waterwheel_working", "salt_collector_working", "waterwheel_empty", "salt_collector_empty"]

const RUN_PHASES := 4
const RUN_FRAME_SECONDS := 0.15
## Native ROIs (64x64 canvas). Outside them a running frame is bit-identical to idle.
const WHEEL_FLUME_ROI := Rect2i(24, 11, 12, 10) # water flows +x (toward the wheel)
const WHEEL_STREAM_ROI := Rect2i(53, 45, 6, 9) # water falls +y (foam below is static)
const WHEEL_FLOW_STEP := 2
const RAKE_ROI := Rect2i(8, 31, 31, 16) # tray interior: rake head + salt
const GRAIN_ROI := Rect2i(44, 25, 9, 12) # falling grains above the basket rim
const GRAIN_STEP := 3
const RAKE_DOWN_PHASES := [2, 3]
## Compat: machine_texture("<kind>_working") returns this running phase.
const WORKING_PHASE := {"waterwheel": 1, "salt_collector": 2}
## Status ids (SaltPan.STATUS_IDS) that show motion. Rain pauses wheel filling
## but not raking. Everything else (off/full/invalid/unset/waiting/manual/
## wheel_only/reserve/owner/"") is the static idle frame.
const MOTION := {"running": ["waterwheel", "salt_collector"], "rain": ["salt_collector"]}

# ---------------------------------------------------------------- state

static var base_dir: String = DEFAULT_DIR
static var file_names: Dictionary = {}
static var paths: Dictionary = {}
static var props_script_path: String = DEFAULT_PROPS_SCRIPT
static var props_script: GDScript = null
static var cache: Dictionary = {}
static var built: Dictionary = {}
static var natives: Dictionary = {}
static var errors: Array[String] = []

## Point the adapter at another directory (absolute or res://) and optional file
## names (e.g. ART_SOURCE_FILES) and props adapter script path. Clears caches.
static func configure(dir: String = DEFAULT_DIR, names: Dictionary = {}, props_path: String = DEFAULT_PROPS_SCRIPT) -> void:
	base_dir = dir if dir.ends_with("/") else dir + "/"
	file_names = names.duplicate()
	paths.clear()
	props_script_path = props_path
	_release_props()
	clear_cache()

## Hand the shared props adapter back its default sheet before forgetting it, so
## a test path never leaks into the gates/idle machines drawn elsewhere.
static func _release_props() -> void:
	if props_script != null:
		props_script.set_source_path(str(props_script.get_script_constant_map().get("DEFAULT_SOURCE_PATH", DEFAULT_DIR + "salt-props.png")))
		props_script.clear_cache()
	props_script = null

static func clear_cache() -> void:
	cache.clear()
	built.clear()
	natives.clear()
	errors.clear()
	if props_script != null:
		props_script.clear_cache()

static func sheet_path(sheet: String) -> String:
	if paths.has(sheet):
		return str(paths[sheet])
	if not SHEETS.has(sheet):
		return ""
	return base_dir + str(file_names.get(sheet, SHEETS[sheet]["file"]))

## Compat test hook: one sheet at another path ("" restores the default).
static func set_sheet_path(sheet: String, path: String) -> void:
	if path.is_empty():
		paths.erase(sheet)
	else:
		paths[sheet] = path
	if sheet == "props":
		_release_props()
	clear_cache()

static func _error(message: String) -> void:
	if not errors.has(message):
		errors.append(message)

static func source_image(sheet: String) -> Image:
	if not SHEETS.has(sheet):
		return null
	var path := sheet_path(sheet)
	var image: Image = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if not ResourceLoader.exists(path):
			_error("missing sheet " + path)
			return null
		var texture := load(path) as Texture2D
		if texture == null:
			_error("unloadable sheet " + path)
			return null
		image = texture.get_image()
	else:
		if not FileAccess.file_exists(path):
			_error("missing sheet " + path)
			return null
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		_error("empty sheet " + path)
		return null
	if image.is_compressed() and image.decompress() != OK:
		_error("compressed sheet " + path)
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_size() != SHEETS[sheet]["size"]:
		_error("wrong size %s %s" % [path, image.get_size()])
		return null
	return image

## Window `window` of `image`, only pixels inside `clip` copied (no neighbour
## bleed), nearest-resized to `size`; alpha <= ALPHA_VISIBLE zeroed if `clean`.
static func render_window(image: Image, clip: Rect2i, window: Rect2i, size: Vector2i, clean: bool = true) -> Image:
	var canvas := windowed(image, clip, window)
	canvas.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	if clean:
		for y in size.y:
			for x in size.x:
				if canvas.get_pixel(x, y).a8 <= ALPHA_VISIBLE:
					canvas.set_pixel(x, y, Color(0, 0, 0, 0))
	return canvas

## Compat with salt_props_art.gd / production salt_art.gd: un-resized window.
static func windowed(image: Image, clip: Rect2i, window: Rect2i) -> Image:
	var canvas := Image.create_empty(window.size.x, window.size.y, false, Image.FORMAT_RGBA8)
	var take := window.intersection(clip).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if take.has_area():
		canvas.blit_rect(image, take, take.position - window.position)
	return canvas

static func _store(key: String, image: Image, meta: Dictionary) -> Texture2D:
	var texture := ImageTexture.create_from_image(image)
	for k in meta:
		texture.set_meta(k, meta[k])
	texture.set_meta("art_key", key)
	cache[key] = texture
	return texture

static func _put(key: String, sheet: String, image: Image, clip: Rect2i, window: Rect2i, size: Vector2i) -> void:
	_store(key, render_window(image, clip, window, size), {"source_png": sheet_path(sheet), "source_window": window, "source_clip": clip})

## Builds every texture of one sheet at once, then drops the big source image.
static func _ensure(sheet: String) -> bool:
	if built.has(sheet):
		return built[sheet]
	var image := source_image(sheet)
	built[sheet] = image != null
	if image == null:
		return false
	match sheet:
		"items":
			for id in ITEMS:
				_put("item:" + id, sheet, image, item_clip(id), item_window(id), ICON_SIZE)
		"pans":
			for state in PAN_STATES:
				_put("pan:" + state, sheet, image, pan_cell(state), pan_window(state), PAN_SIZE)
		"terrain":
			for index in 16:
				_put("terrain:%d" % index, sheet, image, terrain_window(index), terrain_window(index), TILE)
		"resident":
			for pose in POSES:
				_put("resident_raw:" + pose, sheet, image, Rect2i(POSES[pose], Vector2i(627, 627)), resident_window(pose), RESIDENT_SIZE)
			var front: Image = (cache["resident_raw:front"] as Texture2D).get_image()
			var blink: Image = (cache["resident_raw:front_blink"] as Texture2D).get_image()
			var eyes := front.duplicate() as Image
			eyes.blit_rect(blink, BLINK_ROI, BLINK_ROI.position)
			for pose in ["front", "back", "right"]:
				cache["resident:" + pose] = cache["resident_raw:" + pose]
			_store("resident:front_blink", eyes, {"source_png": sheet_path(sheet), "composite": "front + blink BLINK_ROI"})
			var left := (cache["resident_raw:right"] as Texture2D).get_image().duplicate() as Image
			left.flip_x()
			_store("resident:left", left, {"source_png": sheet_path(sheet), "composite": "mirror of right"})
		"portrait":
			_put("portrait", sheet, image, PORTRAIT_WINDOW, PORTRAIT_WINDOW, PORTRAIT_SIZE)
		"structures":
			for id in STRUCTURES:
				var spec: Dictionary = STRUCTURES[id]
				_put("structure:" + id, sheet, image, spec["clip"], spec["window"], spec["size"])
		"machines":
			for id in FOUNDATIONS:
				_put("machine:" + id, sheet, image, machine_clip(id), machine_window(id), MACHINE_SIZE)
			var clip := Rect2i(COLLECTOR_WORKING["cell"], Vector2i(MACHINE_CELL, MACHINE_CELL))
			var window := Rect2i(Vector2i(COLLECTOR_WORKING["cell"]) + Vector2i(COLLECTOR_WORKING["window"].position), COLLECTOR_WORKING["window"].size)
			natives["collector_working"] = render_window(image, clip, window, MACHINE_SIZE)
	return true

static func _cached(key: String, sheet: String) -> Texture2D:
	if not cache.has(key):
		_ensure(sheet)
	return cache.get(key, null)

# ---------------------------------------------------------------- windows

static func item_clip(id: String) -> Rect2i:
	return Rect2i(ITEMS[id], Vector2i(627, 627)) if ITEMS.has(id) else Rect2i()

static func item_window(id: String) -> Rect2i:
	return Rect2i(Vector2i(ITEMS[id]) + ITEM_WINDOW.position, ITEM_WINDOW.size) if ITEMS.has(id) else Rect2i()

static func terrain_window(index: int) -> Rect2i:
	if index < 0 or index >= 16:
		return Rect2i()
	var x0: int = TERRAIN_BOUNDS[index % 4]
	var y0: int = TERRAIN_BOUNDS[index / 4]
	return Rect2i(x0, y0, int(TERRAIN_BOUNDS[index % 4 + 1]) - x0, int(TERRAIN_BOUNDS[index / 4 + 1]) - y0)

static func pan_cell(state: String) -> Rect2i:
	var i := PAN_STATES.find(state)
	if i < 0:
		return Rect2i()
	var x0: int = PAN_X[i % 4]
	var y0: int = PAN_Y[i / 4]
	return Rect2i(x0, y0, int(PAN_X[i % 4 + 1]) - x0, int(PAN_Y[i / 4 + 1]) - y0)

static func pan_window(state: String) -> Rect2i:
	var cell := pan_cell(state)
	return Rect2i(cell.position + PAN_WINDOW.position, PAN_WINDOW.size) if cell.has_area() else Rect2i()

static func resident_window(pose: String) -> Rect2i:
	return Rect2i(Vector2i(POSES[pose]) + RESIDENT_WINDOW.position, RESIDENT_WINDOW.size) if POSES.has(pose) else Rect2i()

static func machine_window(id: String) -> Rect2i:
	if not FOUNDATIONS.has(id):
		return Rect2i()
	return Rect2i(Vector2i(FOUNDATIONS[id]["cell"]) + Vector2i(FOUNDATIONS[id]["window"].position), FOUNDATIONS[id]["window"].size)

static func machine_clip(id: String) -> Rect2i:
	return Rect2i(FOUNDATIONS[id]["cell"], Vector2i(MACHINE_CELL, MACHINE_CELL)) if FOUNDATIONS.has(id) else Rect2i()

static func structure_id(id: String) -> String:
	return str(STRUCTURE_ALIASES.get(id, id))

# ---------------------------------------------------------------- textures

static func has_item(id: String) -> bool:
	return ITEMS.has(id)

## 32x32 inventory icon for the 4 salt items; null for anything else.
static func item_texture(id: String) -> Texture2D:
	return _cached("item:" + id, "items") if ITEMS.has(id) else null

## 96x96 pan (3x3 tiles) for one of PAN_STATES; draw at the pan rect's top-left.
static func pan_texture(state: String) -> Texture2D:
	return _cached("pan:" + state, "pans") if PAN_STATES.has(state) else null

## SaltPan.pan_view(...) dictionary -> PAN_STATES id (never brine_alt). Pure.
static func pan_art_id(view: Dictionary) -> String:
	match str(view.get("s", "empty")):
		"salt":
			return "covered" if bool(view.get("covered", false)) else "salt"
		"brine":
			if bool(view.get("diluted", false)):
				return "diluted"
			var ratio := float(view.get("ratio", 0.0))
			if ratio >= 2.0 / 3.0:
				return "evaporating_2"
			if ratio >= 1.0 / 3.0:
				return "evaporating_1"
			return "brine"
		"empty":
			return "empty"
	return ""

## 32x32 terrain tile by index (0..15) or TERRAIN name. Null when unknown/missing.
static func terrain_texture(id: Variant) -> Texture2D:
	var index := -1
	if id is int:
		index = id
	elif TERRAIN.has(str(id)):
		index = int(TERRAIN[str(id)])
	if index < 0 or index >= 16:
		return null
	return _cached("terrain:%d" % index, "terrain")

## Deterministic per-cell variant (no per-frame randomness): base or base_b.
static func terrain_variant(base: String, cell: Vector2i) -> String:
	var alt := base + "_b"
	if not TERRAIN.has(base) or not TERRAIN.has(alt):
		return base if TERRAIN.has(base) else ""
	return alt if absi(cell.x * 7127 + cell.y * 19391) % 3 == 0 else base

## 32x48 阿曬 map sprite (front, front_blink, back, right, left); feet RESIDENT_FEET.
static func resident_texture(pose: String = "front") -> Texture2D:
	if not (POSES.has(pose) or pose == "left"):
		return null
	return _cached("resident:" + pose, "resident")

## Pure: should the (optional) eye blink show now? Never in reduced motion.
static func resident_blinking(time_sec: float, reduced_motion: bool) -> bool:
	return not reduced_motion and fposmod(time_sec, BLINK_PERIOD) < BLINK_SECONDS

## 64x64 dialogue portrait of 阿曬.
static func portrait_texture(id: String = "salt_worker") -> Texture2D:
	return _cached("portrait", "portrait") if PORTRAIT_IDS.has(id) else null

static func has_structure(id: String) -> bool:
	return STRUCTURES.has(structure_id(id))

static func structure_size(id: String) -> Vector2i:
	var key := structure_id(id)
	return STRUCTURES[key]["size"] if STRUCTURES.has(key) else Vector2i.ZERO

## Bottom-centre (feet) anchor of a structure canvas; (-1,-1) for unknown IDs.
static func structure_anchor(id: String) -> Vector2i:
	var key := structure_id(id)
	if not STRUCTURES.has(key):
		return Vector2i(-1, -1)
	var size: Vector2i = STRUCTURES[key]["size"]
	return Vector2i(size.x / 2, size.y)

static func structure_footprint(id: String) -> Vector2i:
	var key := structure_id(id)
	return STRUCTURES[key]["footprint"] if STRUCTURES.has(key) else Vector2i.ZERO

static func structure_texture(id: String) -> Texture2D:
	var key := structure_id(id)
	return _cached("structure:" + key, "structures") if STRUCTURES.has(key) else null

# ---------------------------------------------------------------- props + machines

## salt_props_art.gd (gates + idle machines), loaded lazily from props_script_path
## and pointed at this adapter's "props" sheet path. Null when unavailable.
static func props_adapter() -> GDScript:
	if props_script != null:
		return props_script
	var path := props_script_path
	var exists := ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)
	if not exists:
		_error("missing props adapter " + path)
		return null
	props_script = load(path) as GDScript
	if props_script == null:
		_error("unloadable props adapter " + path)
		return null
	props_script.set_source_path(sheet_path("props"))
	return props_script

## gate_broken / gate_repaired / waterwheel / salt_collector (64x64, feet (32,64)).
static func prop_texture(id: String) -> Texture2D:
	var props := props_adapter()
	if props == null or not props.has_prop(id):
		return null
	var texture: Texture2D = props.prop_texture(id)
	if texture == null:
		_error("props texture unavailable " + id)
	return texture

static func has_machine(id: String) -> bool:
	return MACHINES.has(id) or (id.begins_with("waterwheel_running_") or id.begins_with("salt_collector_running_"))

## Static machine art: "waterwheel"/"salt_collector" = idle props frame,
## "<kind>_empty" = empty foundation pad, "<kind>_working" = the stable-base
## running composite at WORKING_PHASE (NOT the raw working cell, which wobbles),
## "<kind>_running_<n>" = running phase n. All 64x64 with feet MACHINE_ANCHOR.
static func machine_texture(id: String) -> Texture2D:
	if MACHINE_KINDS.has(id):
		return prop_texture(id)
	if FOUNDATIONS.has(id):
		return _cached("machine:" + id, "machines")
	for kind in MACHINE_KINDS:
		if id == kind + "_working":
			return running_frame(kind, WORKING_PHASE[kind])
		if id.begins_with(kind + "_running_") and id.trim_prefix(kind + "_running_").is_valid_int():
			var phase := int(id.trim_prefix(kind + "_running_"))
			return running_frame(kind, phase) if phase >= 0 and phase < RUN_PHASES else null
	return null

## Pure: does this machine show motion for this unit status? (rain: rake only)
static func machine_motion(kind: String, status_id: String, raining: bool = false) -> bool:
	if not MACHINE_KINDS.has(kind):
		return false
	if kind == "waterwheel" and raining:
		return false
	return MOTION.has(status_id) and (MOTION[status_id] as Array).has(kind)

static func machine_phase(time_sec: float) -> int:
	return int(floorf(fposmod(time_sec, RUN_FRAME_SECONDS * RUN_PHASES) / RUN_FRAME_SECONDS)) % RUN_PHASES

## Native rectangles that may differ from the idle frame while running.
static func animated_rois(kind: String) -> Array[Rect2i]:
	var rois: Array[Rect2i] = []
	if kind == "waterwheel":
		rois.append(WHEEL_FLUME_ROI)
		rois.append(WHEEL_STREAM_ROI)
	elif kind == "salt_collector":
		rois.append(RAKE_ROI)
		rois.append(GRAIN_ROI)
	return rois

## THE frame provider. Pure (no state mutation besides texture caching):
## idle props texture unless machine_motion(...) and not reduced_motion.
static func machine_frame(kind: String, status_id: String, time_sec: float, reduced_motion: bool, raining: bool = false) -> Texture2D:
	if not MACHINE_KINDS.has(kind):
		return null
	if reduced_motion or not machine_motion(kind, status_id, raining):
		return prop_texture(kind)
	return running_frame(kind, machine_phase(time_sec))

static func is_water(c: Color) -> bool:
	return c.a8 > 200 and c.b > c.r + 0.1 and c.g > c.r

static func is_grain(c: Color) -> bool:
	return c.a8 > 200 and c.r8 > 200 and c.g8 > 200 and c.b8 > 200

## Cyclic advance of the base's water pixels inside `roi` along +x or +y.
static func flow(base: Image, out: Image, roi: Rect2i, vertical: bool, shift: int) -> void:
	var lines := roi.size.x if vertical else roi.size.y
	var length := roi.size.y if vertical else roi.size.x
	for i in lines:
		var cells: Array[Vector2i] = []
		for j in length:
			var p := Vector2i(roi.position.x + i, roi.position.y + j) if vertical else Vector2i(roi.position.x + j, roi.position.y + i)
			if is_water(base.get_pixelv(p)):
				cells.append(p)
		var n := cells.size()
		if n < 2:
			continue
		for k in n:
			var c := base.get_pixelv(cells[posmod(k - shift, n)])
			c.a = base.get_pixelv(cells[k]).a # colour moves, alpha/silhouette stays
			out.set_pixelv(cells[k], c)

## Grain pixels (position, colour) of the registered working collector frame.
static func grains() -> Array:
	var list := []
	_ensure("machines")
	if not natives.has("collector_working"):
		return list
	var working: Image = natives["collector_working"]
	for y in range(GRAIN_ROI.position.y, GRAIN_ROI.end.y):
		for x in range(GRAIN_ROI.position.x, GRAIN_ROI.end.x):
			if is_grain(working.get_pixel(x, y)):
				list.append([Vector2i(x, y), working.get_pixel(x, y)])
	return list

## Running composite for phase 0..RUN_PHASES-1 (cached). Null when art missing.
static func running_frame(kind: String, phase: int) -> Texture2D:
	if not MACHINE_KINDS.has(kind) or phase < 0 or phase >= RUN_PHASES:
		return null
	var key := "run:%s:%d" % [kind, phase]
	if cache.has(key):
		return cache[key]
	var idle := prop_texture(kind)
	if idle == null:
		return null
	var base := idle.get_image()
	if base.get_format() != Image.FORMAT_RGBA8:
		base.convert(Image.FORMAT_RGBA8)
	var out := base.duplicate() as Image
	if kind == "waterwheel":
		var shift := phase * WHEEL_FLOW_STEP + 1
		flow(base, out, WHEEL_FLUME_ROI, false, shift)
		flow(base, out, WHEEL_STREAM_ROI, true, shift)
	else:
		if not _ensure("machines") or not natives.has("collector_working"):
			return null
		var working: Image = natives["collector_working"]
		if RAKE_DOWN_PHASES.has(phase):
			out.blit_rect(working, RAKE_ROI, RAKE_ROI.position)
		for grain in grains():
			var p: Vector2i = grain[0]
			var y := GRAIN_ROI.position.y + posmod(p.y - GRAIN_ROI.position.y + phase * GRAIN_STEP, GRAIN_ROI.size.y)
			out.set_pixel(p.x, y, grain[1])
	return _store(key, out, {"base": "props idle " + kind, "phase": phase, "rois": animated_rois(kind)})

# ---------------------------------------------------------------- provider

## SaltPanUI.art_provider-compatible: func(kind,id)->Texture2D. Current UI calls:
## ("portrait","salt_worker"), ("pan", "empty"|"brine"|"salt"), ("status", id),
## ("heritage","jingzaijiao"). No status icons were delivered, so those return
## null (UI keeps its own life icons); the heritage picture is served by
## panel_art() / heritage_texture(), not by this scene/inventory provider.
## Extra kinds for scene/inventory use: item, terrain, actor|resident,
## structure, machine, prop.
static func provider(kind: String, id: String) -> Texture2D:
	match kind:
		"portrait":
			return portrait_texture(id)
		"pan":
			return pan_texture(id)
		"item":
			return item_texture(id)
		"terrain":
			return terrain_texture(id)
		"actor", "resident":
			return resident_texture(id)
		"structure":
			return structure_texture(id)
		"machine":
			return machine_texture(id)
		"prop":
			return prop_texture(id)
	return null

## Journal illustration(s): whole delivered PNG, shown as-is (no window, no
## resample here). Game illustration, NOT a historical photo: the UI captions it.
## Provenance: assets/salt/salt-heritage-jingzaijiao-source.md.
const HERITAGE := {
	"jingzaijiao": {"file": "salt-heritage-jingzaijiao.png", "size": Vector2i(288, 192)},
}

static func has_heritage(id: String) -> bool:
	return HERITAGE.has(id)

static func heritage_path(id: String) -> String:
	return base_dir + str(HERITAGE[id]["file"]) if HERITAGE.has(id) else ""

## 288x192 heritage journal illustration. Null (recorded in `errors`, never
## cached) for unknown ids, a missing/unloadable file or a wrong-size image, so
## the journal simply keeps its previous picture-less left page.
static func heritage_texture(id: String = "jingzaijiao") -> Texture2D:
	if not HERITAGE.has(id):
		return null
	var key := "heritage:" + id
	if cache.has(key):
		return cache[key]
	var path := heritage_path(id)
	var texture: Texture2D = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if not ResourceLoader.exists(path):
			_error("missing heritage art " + path)
			return null
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	else:
		_error("missing heritage art " + path)
		return null
	if texture == null:
		_error("unloadable heritage art " + path)
		return null
	if Vector2i(texture.get_size()) != HERITAGE[id]["size"]:
		_error("wrong size %s %s" % [path, Vector2i(texture.get_size())])
		return null
	texture.set_meta("art_key", key)
	texture.set_meta("source_png", path)
	cache[key] = texture
	return texture

## SaltPanUI.art_provider as wired by main.gd: kind "portrait" id "salt_worker"
## -> 阿曬 portrait; kind "pan" id = one of PAN_STATES except brine_alt -> pan
## preview; kind "heritage" id "jingzaijiao" -> the journal illustration.
## Everything else (other heritage ids, status) has no delivered art: null.
static func panel_art(kind: String, id: String) -> Texture2D:
	match kind:
		"portrait":
			return portrait_texture() if id == "salt_worker" else null
		"pan":
			return pan_texture(id) if id != "brine_alt" else null
		"heritage":
			return heritage_texture(id)
	return null

# ---------------------------------------------------------------- drawing
# Callers must draw with TEXTURE_FILTER_NEAREST. All return false when art is missing.

## Draw a texture with its anchor on `feet`; false when the art is missing.
static func draw_anchored(canvas: CanvasItem, texture: Texture2D, feet: Vector2, anchor: Vector2i) -> bool:
	if texture == null:
		return false
	canvas.draw_texture(texture, (feet - Vector2(anchor)).round())
	return true

static func draw_pan(canvas: CanvasItem, state: String, top_left: Vector2) -> bool:
	return draw_anchored(canvas, pan_texture(state), top_left, Vector2i.ZERO)

static func draw_terrain(canvas: CanvasItem, id: Variant, top_left: Vector2) -> bool:
	return draw_anchored(canvas, terrain_texture(id), top_left, Vector2i.ZERO)

static func draw_resident(canvas: CanvasItem, pose: String, feet: Vector2) -> bool:
	return draw_anchored(canvas, resident_texture(pose), feet, RESIDENT_FEET)

static func draw_structure(canvas: CanvasItem, id: String, feet: Vector2) -> bool:
	return draw_anchored(canvas, structure_texture(id), feet, structure_anchor(id))

## installed=false draws the empty pad; otherwise machine_frame(...).
static func draw_machine(canvas: CanvasItem, kind: String, feet: Vector2, installed: bool, status_id: String, time_sec: float, reduced_motion: bool, raining: bool = false) -> bool:
	if not MACHINE_KINDS.has(kind):
		return false
	var texture := machine_frame(kind, status_id, time_sec, reduced_motion, raining) if installed else machine_texture(kind + "_empty")
	return draw_anchored(canvas, texture, feet, MACHINE_ANCHOR)
