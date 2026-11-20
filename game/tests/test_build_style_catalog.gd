extends SceneTree
## T051/T069 standalone style catalog: uniqueness, traceability to existing
## definitions, valid material references, and live proof that placing a style
## entry is byte-for-byte the existing placement of its base kind.
## Run: godot --headless --path game --script res://tests/test_build_style_catalog.gd

const Catalog = preload("res://scripts/build_style_catalog.gd")
const World = preload("res://scripts/world.gd")
const StoneStation = preload("res://tests/stone_station_fixture.gd")
const BlueprintDesign = preload("res://scripts/blueprint_design.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const FurnitureArt = preload("res://scripts/furniture_sprite_art.gd")
const TeaArt = preload("res://scripts/tea_ceramics_art.gd")
const SaltArt = preload("res://scripts/salt_art.gd")
## Same walkable tile and stand-in materials as tests/test_build_catalog.gd.
const TILE := Vector2i(38, 34)
const MATERIALS := ["wood", "stone", "fiber", "glass"]
## Collision table copied from tests/test_build_catalog.gd PLACEMENT (independent of world.gd lists).
const EXPECTED := {
	"floor": ["ground", false], "stone_floor": ["ground", false], "path": ["ground", false], "roof": ["roofs", false],
	"wall": ["objects", true], "window": ["objects", true], "door": ["objects", true],
	"chest": ["objects", true], "bench": ["objects", true], "bed": ["objects", true],
	"table": ["objects", true], "stove": ["objects", true], "long_bench": ["objects", true],
	"planter": ["objects", true], "lamp": ["objects", false], "chair": ["objects", false],
	"sign": ["objects", false],
}

var checks := 0
var failures := 0
var sequence := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func test_uniqueness() -> void:
	var rows: Array = Catalog.entries()
	expect(rows.size() == Catalog.ENTRIES.size() and rows.size() > 0, "entries() returns every row")
	expect(Catalog.style_ids() == ["coast", "tea_house"], "exactly the two requested styles")
	var ids := {}
	var pairs := {}
	var notes := {}
	for row in rows:
		expect(not ids.has(row.id), "unique entry id " + str(row.id))
		ids[row.id] = true
		expect(row.id == "%s.%s" % [row.style, row.kind], row.id + " id is <style>.<kind>")
		var pair := "%s|%s" % [row.style, row.kind]
		expect(not pairs.has(pair), row.id + " kind appears once per style")
		pairs[pair] = true
		var note_key := "%s|%s" % [row.style, row.note]
		expect(not notes.has(note_key) and not str(row.note).is_empty(), row.id + " has a distinct note in its style")
		notes[note_key] = true
		var refs := {}
		for ref in row.materials:
			expect(not refs.has(str(ref)), row.id + " material listed once: " + str(ref))
			refs[str(ref)] = true
	for style_id in Catalog.style_ids():
		var labels := {}
		for row in Catalog.entries(style_id):
			var text := Catalog.label(row.id)
			expect(not labels.has(text), "unique label " + text)
			labels[text] = true
	# The styles must actually differ on every structure piece.
	for kind in Catalog.STRUCTURE_KINDS:
		var tea := Catalog.entry("tea_house." + kind)
		var coast := Catalog.entry("coast." + kind)
		expect(not tea.is_empty() and not coast.is_empty(), kind + " present in both styles")
		if not tea.is_empty() and not coast.is_empty():
			expect(str(tea.materials) != str(coast.materials), kind + " materials differ between styles")

func test_traceability() -> void:
	expect(Catalog.validate().is_empty(), "validate(): " + str(Catalog.validate()))
	for row in Catalog.entries():
		var kind: String = row.kind
		expect(World.BUILD.has(kind), row.id + " kind is an existing World.BUILD key")
		expect(EXPECTED.has(kind), row.id + " kind has an independent collision expectation")
		if EXPECTED.has(kind):
			expect(row.layer == EXPECTED[kind][0], row.id + " layer matches test_build_catalog")
			expect(row.solid == EXPECTED[kind][1], row.id + " collision matches test_build_catalog")
		expect(row.layer == Catalog.expected_layer(kind), row.id + " layer matches blueprint_design kinds")
		expect(row.solid == Catalog.expected_solid(kind), row.id + " solid matches World.UNDO_SOLID/door")
		expect(Catalog.label(row.id).ends_with(str(World.BUILD[kind].name)), row.id + " label keeps the base recipe name")
		var request := Catalog.placement_request(row.id)
		expect(request == {"ok": true, "action": "build", "extra": kind}, row.id + " placement request is the plain build action")
	expect(not Catalog.placement_request("tea_house.missing").ok, "unknown entry is rejected")
	expect(Catalog.entry("nope").is_empty() and Catalog.label("nope") == "", "unknown entry has no data")
	for style_id in Catalog.style_ids():
		var covered := Catalog.kinds(style_id)
		for kind in HouseUI.PARTS:
			expect(kind in covered, "%s covers house part %s" % [style_id, kind])
		for kind in World.AUTO_ROOF_BUILDS:
			expect(kind in covered, "%s covers auto-roof kind %s" % [style_id, kind])
		for hex in Catalog.STYLES[style_id].palette:
			expect(Color.html_is_valid(hex), "%s palette %s is a valid colour" % [style_id, hex])
	expect(Catalog.FOOTPRINT == Vector2i(1, 1), "every existing BUILD piece is one tile")
	var cover := Catalog.coverage()
	expect(cover.styles == 2 and cover.target_styles == 6 and cover.target_items == 96 and not cover.t069_complete and cover.new_item_ids == 0, "coverage reports T069 as incomplete")
	expect(cover.distinct_kinds == Catalog.distinct_kinds().size() and cover.distinct_kinds <= World.BUILD.size(), "distinct kinds counted")

func test_materials() -> void:
	var sizes := {}
	for row in Catalog.entries():
		for ref in row.materials:
			var resolved := Catalog.resolve_material(ref)
			expect(resolved.ok, "%s resolves %s" % [row.id, str(ref)])
			if not resolved.ok:
				continue
			expect(ResourceLoader.exists(resolved.path), "%s sheet exists %s" % [row.id, resolved.path])
			if not ResourceLoader.exists(resolved.path):
				continue
			if not sizes.has(resolved.path):
				var texture := load(resolved.path) as Texture2D
				sizes[resolved.path] = Vector2i(texture.get_size()) if texture else Vector2i.ZERO
			var bounds := Rect2i(Vector2i.ZERO, sizes[resolved.path])
			expect(bounds.encloses(resolved.rect), "%s %s rect %s inside sheet %s" % [row.id, str(ref), str(resolved.rect), str(bounds.size)])
	# Cross-check the formulas with the owning art scripts.
	var lamp := Catalog.resolve_material(["furniture", "lamp"])
	var index := FurnitureArt.KINDS.find("lamp")
	expect(lamp.rect == Rect2i((index % 4) * 32, (index / 4) * 48, 32, 48), "furniture rect mirrors FurnitureSpriteArt.draw_sprite")
	expect(Catalog.resolve_material(["tea_icon", "tea_jar"]).rect == Rect2i(TeaArt.ICONS.find("tea_jar") * 32, 0, 32, 32), "tea icon rect mirrors TeaCeramicsArt.icon")
	expect(Catalog.resolve_material(["salt_terrain", "plank"]).rect == SaltArt.terrain_window(SaltArt.TERRAIN.plank), "salt terrain rect mirrors SaltArt.terrain_window")
	expect(Catalog.resolve_material(["salt_structure", "shed"]).rect == SaltArt.STRUCTURES.shed.clip, "salt structure rect is its sheet clip")
	expect(Catalog.resolve_material(["salt_item", "sea_salt"]).rect == SaltArt.item_clip("sea_salt"), "salt item rect mirrors SaltArt.item_clip")
	expect(Catalog.resolve_material(["salt_item", "sea_salt"]).path == "res://assets/salt/salt-items.png", "salt path built from SaltArt.SHEETS")
	# Stale or malformed references must fail closed.
	for bad in [["furniture", "throne"], ["tea_icon", "kettle"], ["salt_terrain", "lava"], ["salt_structure", "lighthouse"],
			["village_tile", 16], ["village_prop", -1], ["tea_building", 3], ["unknown", 0], "furniture", ["furniture"], [1, 2]]:
		expect(not Catalog.resolve_material(bad).ok, "bad reference rejected " + str(bad))

func test_preview() -> void:
	expect(ResourceLoader.exists(Catalog.PREVIEW_SCRIPT), "preview script exists")
	expect(Catalog.PREVIEW_SIZE == Vector2i(HouseUI.THUMB_SIZE), "preview frame matches HouseUI BuildThumbnail")
	for row in Catalog.entries():
		var spec := Catalog.preview_spec(row.id)
		expect(spec.ok and spec.kind == row.kind and spec.script == Catalog.PREVIEW_SCRIPT, row.id + " preview draws its base kind")
		expect(spec.swatches.size() == row.materials.size() and spec.swatches.all(func(s): return s.ok), row.id + " preview swatches resolve")
		expect(spec.style_sprite == false, row.id + " preview does not claim style sprites exist")
		expect(spec.footprint == Vector2i(1, 1), row.id + " preview footprint one tile")
	expect(not Catalog.preview_spec("coast.throne").ok, "unknown preview rejected")
	# Rendering the thumbnail needs a scene tree + village art; that belongs to
	# the UI integration tests (run with -- --village-art-preview), not here.

func new_world():
	var world = World.new()
	world.add_player("builder", "島民")
	var player: Dictionary = world.state.players.builder
	player.stories = {"aru": 4, "milu": 4, "bobo": 3}
	for material in MATERIALS:
		player.inventory[material] = 100
	return world

func act(world, action: String, kind: String = "") -> Dictionary:
	sequence += 1
	return world.act("builder", "style-%d" % sequence, action, TILE, kind)

## Place one entry through its placement_request and return the three layers.
func place(entry_id: String) -> Dictionary:
	var row := Catalog.entry(entry_id)
	var world = new_world()
	var request := Catalog.placement_request(entry_id)
	if row.kind == "roof":
		expect(act(world, "build", "floor").ok, entry_id + " lays the floor a roof needs")
	if row.kind in World.STONE_WORKSHOP.STATION_BUILDS:
		StoneStation.install(world,"builder")
	var result: Dictionary = act(world, request.action, request.extra)
	expect(result.ok, "%s placement (%s)" % [entry_id, result.get("message", "")])
	var key := World.key(TILE)
	var stored: Dictionary = world.state[row.layer].get(key, {})
	expect(stored.get("type", "") == row.kind, entry_id + " stores the existing item id on layer " + row.layer)
	expect(not stored.has("style"), entry_id + " does not persist a style field")
	var center := Vector2(TILE) + Vector2(0.5, 0.5)
	if row.layer != "roofs":
		expect(world.blocked(TILE) == row.solid and world.can_stand(center) != row.solid, entry_id + " collision as declared")
	else:
		expect(not world.blocked(TILE) and world.can_stand(center), entry_id + " roof keeps the tile walkable")
	if row.get("toggle", "") == "door":
		expect(act(world, "door").ok and not world.blocked(TILE), entry_id + " door still opens")
		expect(act(world, "door").ok and world.blocked(TILE), entry_id + " door still closes")
	var layers := {}
	for layer in BlueprintDesign.LAYERS:
		layers[layer] = world.state[layer].duplicate(true)
	layers["inventory"] = world.state.players.builder.inventory.duplicate(true)
	expect(act(world, "remove").ok, entry_id + " removable by its owner")
	return layers

func test_live_placement() -> void:
	var by_kind := {}
	for row in Catalog.entries():
		var layers := place(row.id)
		if by_kind.has(row.kind):
			expect(var_to_bytes(layers) == var_to_bytes(by_kind[row.kind].layers), "%s places identically to %s" % [row.id, by_kind[row.kind].id])
		else:
			by_kind[row.kind] = {"id": row.id, "layers": layers}
	# Shared kinds exist, so the identity check above is not vacuous.
	var shared := 0
	for kind in Catalog.kinds("tea_house"):
		if kind in Catalog.kinds("coast"):
			shared += 1
	expect(shared >= Catalog.STRUCTURE_KINDS.size(), "both styles share structure kinds for the identity check")

func _initialize() -> void:
	test_uniqueness()
	test_traceability()
	test_materials()
	test_preview()
	test_live_placement()
	print("BUILD_STYLE_CATALOG_TESTS entries=%d checks=%d failures=%d" % [Catalog.ENTRIES.size(), checks, failures])
	quit(0 if failures == 0 and checks > 0 else 1)
