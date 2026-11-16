extends SceneTree

const Art = preload("res://scripts/crop_sprite_art.gd")
const World = preload("res://scripts/world.gd")
const FIELD := Vector2i(38, 34)

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func verify_stages() -> void:
	expect(Art.ROWS == World.CROPS.keys(), "atlas rows cover all six crops in order")
	expect(Art.stage_for({"kind": "", "growth": 0, "wet": true}) == -1, "wet empty soil draws no plant")
	for kind in World.CROPS:
		var duration := float(World.CROPS[kind].time)
		var crop := {"kind": kind, "wet": true, "growth": 0.0}
		for sample in [[0.0, 0], [0.249, 0], [0.25, 1], [0.649, 1], [0.65, 2], [0.999, 2], [1.0, 3]]:
			crop.growth = duration * sample[0]
			expect(Art.stage_for(crop) == sample[1], "%s reaches stage %d at %s" % [kind, sample[1], sample[0]])
		crop.wet = false
		expect(Art.stage_for(crop) == 3, kind + " mature dry plot uses harvestable art")
		crop.growth = duration * 0.4
		expect(Art.stage_for(crop) == 1, kind + " dry plot preserves a young growth stage")

func verify_tomato_regrowth() -> void:
	var world = World.new()
	world.add_player("farmer", "島民")
	world.state.players.farmer.inventory.tomato_seed = 1
	expect(world.act("farmer", "hoe", "hoe", FIELD).ok, "prepare tomato plot")
	expect(world.act("farmer", "seed", "seed", FIELD, "tomato").ok, "seed tomato")
	for remaining in [2, 1, 0]:
		expect(world.act("farmer", "water-%d" % remaining, "water", FIELD).ok, "water tomato")
		var crop: Dictionary = world.state.crops[World.key(FIELD)]
		expect(Art.stage_for(crop) == 0, "watering starts each tomato cycle at the seedling stage")
		world.step(120, true)
		expect(Art.stage_for(crop) == 3, "tomato reaches harvest art each cycle")
		expect(world.act("farmer", "harvest-%d" % remaining, "harvest", FIELD).ok, "harvest tomato")
		expect(crop.remaining == remaining and Art.stage_for(crop) == (0 if remaining > 0 else -1), "harvest resets art for %d remaining" % remaining)

func verify_dry_ripe_save() -> void:
	var world = World.new()
	world.add_player("farmer", "島民")
	world.state.crops[World.key(FIELD)] = {
		"kind": "radish", "wet": false, "growth": World.CROPS.radish.time, "owner": "farmer", "remaining": 1,
	}
	var directory := OS.get_environment("TEMP")
	if directory.is_empty():
		directory = OS.get_environment("TMPDIR")
	if directory.is_empty():
		directory = "/tmp"
	var path := directory.path_join("tuantuan-dry-ripe-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	world.save_path = path
	var saved: bool = world.save()
	expect(saved, "write isolated mature dry crop save")
	if not saved:
		return
	var restored = World.new()
	var loaded: bool = restored.load_world(path)
	expect(loaded, "mature dry crop is legal on reload")
	if loaded:
		var crop: Dictionary = restored.state.crops[World.key(FIELD)]
		expect(not crop.wet and Art.stage_for(crop) == 3, "loaded dry crop shows ripe artwork")
		expect(restored.act("farmer", "harvest-dry", "harvest", FIELD).ok, "loaded dry crop can be harvested")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func verify_atlas() -> void:
	var art = Art.new()
	var ready: bool = art.setup()
	expect(ready, "atlas imports at 128 by 192 pixels")
	if not ready:
		return
	var image: Image = art.atlas.get_image()
	expect(image.detect_alpha() != Image.ALPHA_NONE, "atlas has transparent background")
	for row in range(Art.ROWS.size()):
		var previous: Image
		for stage in range(4):
			var sprite := image.get_region(Rect2i(Vector2i(stage, row) * Art.CELL, Art.CELL))
			var bounds := sprite.get_used_rect()
			var label := "%s stage %d" % [Art.ROWS[row], stage]
			expect(bounds.has_area() and Rect2i(1, 1, 30, 30).encloses(bounds), label + " fits inside transparent cell edges")
			expect(absf(bounds.end.y - 1 - Art.FOOT.y) <= 1 and bounds.position.x <= Art.FOOT.x and bounds.end.x > Art.FOOT.x, label + " is aligned to the common foot")
			if previous != null:
				expect(sprite.get_data() != previous.get_data(), label + " differs from previous stage")
			previous = sprite

func _initialize() -> void:
	verify_stages()
	verify_tomato_regrowth()
	verify_dry_ripe_save()
	verify_atlas()
	print("CROP_SPRITE_ART_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
