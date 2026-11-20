extends SceneTree

# Standalone checks for scripts/livestock_scene_art.gd (no World, no registration).
const Art = preload("res://scripts/livestock_scene_art.gd")
const INVALID_IDS := ["", "Cow", "cow ", "chicken", "goat", "milk", "wool"]
const INVALID_STATES := ["", "Idle", "eating", "ready", "fed "]

var checks := 0
var failures := 0
var report: Array = []

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(image.get_width() * image.get_height())
	for y in image.get_height():
		for x in image.get_width():
			out[y * image.get_width() + x] = 1 if image.get_pixel(x, y).a8 > 0 else 0
	return out

func mask_diff(a: PackedByteArray, b: PackedByteArray) -> int:
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n

func pixel_diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n

func bounds(image: Image) -> Rect2i:
	var out := Rect2i()
	var any := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a8 > 0:
				var p := Rect2i(x, y, 1, 1)
				out = p if not any else out.merge(p)
				any = true
	return out

func colour_count(image: Image) -> int:
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a8 > 0:
				seen[c.to_html()] = true
	return seen.size()

func verify_parts() -> void:
	for name in Art.PARTS:
		var rows: Array = Art.PARTS[name]
		expect(rows.size() > 0, "%s has rows" % name)
		var width := String(rows[0]).length()
		for i in rows.size():
			var row: String = rows[i]
			expect(row.length() == width, "%s row %d width %d == %d" % [name, i, row.length(), width])
			for ch in row:
				expect(ch == "." or Art.PALETTE.has(ch), "%s row %d char '%s' is in palette" % [name, i, ch])
	# Every part placement stays fully on the 48x32 canvas.
	for id in Art.IDS:
		var spec: Dictionary = Art.LAYOUT[id]
		var placements := [[spec.body, spec.body_at], [spec.head, spec.head_up], [spec.head, spec.head_down + Vector2i(0, 1)],
			[spec.head, spec.head_up + Vector2i(0, 1)], [Art.TROUGH, spec.trough_at], [spec.prop, spec.prop_at]]
		for x in spec.leg_x:
			placements.append([spec.leg, Vector2i(int(x), int(spec.leg_y))])
		for t in spec.twinkle:
			placements.append([Art.TWINKLE, t])
		for p in placements:
			var rows: Array = p[0]
			var at: Vector2i = p[1]
			var r := Rect2i(at, Vector2i(String(rows[0]).length(), rows.size()))
			expect(Rect2i(Vector2i.ZERO, Art.SIZE).encloses(r), "%s part at %s fits canvas" % [id, r])

func verify_api() -> void:
	expect(Art.IDS == ["cow", "sheep"], "ids match livestock.gd ANIMALS keys")
	expect(Art.sprite_size() == Vector2i(48, 32), "48x32 native canvas (1.5x1 tiles at 32px)")
	expect(Art.sprite_anchor() == Vector2i(24, 32), "bottom-centre anchor")
	for id in INVALID_IDS:
		expect(Art.texture(id, "idle") == null, "unknown id '%s' gives null" % id)
	for state in INVALID_STATES:
		expect(Art.texture("cow", state) == null, "unknown state '%s' gives null" % state)
	expect(Art.texture("cow", "idle", 2) == null and Art.texture("cow", "idle", -1) == null, "out-of-range frame gives null")
	expect(Art.state_for({}) == "idle", "empty record idle")
	expect(Art.state_for({"feed": 0, "ready": 0, "next": -1.0}) == "idle", "fresh record idle")
	expect(Art.state_for({"feed": 3, "ready": 0, "next": 10.0}) == "fed", "stocked feed -> fed")
	expect(Art.state_for({"feed": 3, "ready": 1, "next": 10.0}) == "produce", "ready product wins over feed")
	expect(Art.state_for({"feed": 0, "ready": 2, "next": -1.0}) == "produce", "ready without feed -> produce")
	var a := Art.texture("sheep", "fed", 1)
	expect(a != null and a == Art.texture("sheep", "fed", 1), "texture cached per key")
	Art.clear_cache()
	expect(Art.cache.is_empty(), "clear_cache empties cache")

func verify_sprites() -> void:
	var idle_masks := {}
	for id in Art.IDS:
		var masks := {}
		for state in Art.STATES:
			var f0 := Art.build_image(id, state, 0)
			var f1 := Art.build_image(id, state, 1)
			expect(f0 != null and f1 != null, "%s %s builds both frames" % [id, state])
			if f0 == null or f1 == null:
				continue
			expect(f0.get_size() == Art.SIZE and f0.get_format() == Image.FORMAT_RGBA8, "%s %s is 48x32 RGBA8" % [id, state])
			var crisp := true
			for y in Art.SIZE.y:
				for x in Art.SIZE.x:
					var al := f0.get_pixel(x, y).a8
					if al != 0 and al != 255:
						crisp = false
			expect(crisp, "%s %s alpha is crisp 0/255" % [id, state])
			var b := bounds(f0)
			expect(b.end.y == Art.SIZE.y, "%s %s feet on bottom row (bounds %s)" % [id, state, b])
			expect(b.size.x >= 30 and b.size.y >= 18, "%s %s silhouette is animal-sized (%s)" % [id, state, b])
			var colours := colour_count(f0)
			expect(colours >= 7, "%s %s uses shaded palette (%d colours)" % [id, state, colours])
			var moved := pixel_diff(f0, f1)
			# A 1px head bob recolours the head's edge rows (~12x11 part); cap well under a full head.
			expect(moved >= 2 and moved <= 132,"%s %s frame 1 differs by a small pixel-scale amount (%d px)" % [id, state, moved])
			masks[state] = mask(f0)
			report.append("%s %s bounds=%s colours=%d frame_delta=%d" % [id, state, b, colours, moved])
		if masks.size() == 3:
			var ifd := mask_diff(masks.idle, masks.fed)
			var ipd := mask_diff(masks.idle, masks.produce)
			var fpd := mask_diff(masks.fed, masks.produce)
			expect(ifd >= 40, "%s idle vs fed silhouettes distinct (%d px)" % [id, ifd])
			expect(ipd >= 40, "%s idle vs produce silhouettes distinct (%d px)" % [id, ipd])
			expect(fpd >= 40, "%s fed vs produce silhouettes distinct (%d px)" % [id, fpd])
			report.append("%s silhouette deltas idle/fed=%d idle/produce=%d fed/produce=%d" % [id, ifd, ipd, fpd])
			idle_masks[id] = masks.idle
	if idle_masks.size() == 2:
		var cs := mask_diff(idle_masks.cow, idle_masks.sheep)
		expect(cs >= 60, "cow vs sheep idle silhouettes distinct (%d px)" % cs)
	# Species identity: cow keeps caramel patches, sheep keeps cloud wool.
	var cow := Art.build_image("cow", "idle", 0)
	var sheep := Art.build_image("sheep", "idle", 0)
	expect(has_colour(cow, Art.PALETTE.c) and not has_colour(cow, Art.PALETTE.f), "cow is cream/caramel, no wool")
	expect(has_colour(sheep, Art.PALETTE.f) and not has_colour(sheep, Art.PALETTE.c), "sheep is wool, no caramel")
	# Fed shows the trough; produce shows the right product.
	expect(has_colour(Art.build_image("cow", "fed", 0), Art.PALETTE.r), "fed draws trough")
	expect(not has_colour(cow, Art.PALETTE.r), "idle has no trough")
	expect(has_colour(Art.build_image("cow", "produce", 0), Art.PALETTE.m), "cow produce draws milk can")
	expect(has_colour(Art.build_image("sheep", "produce", 0), Art.PALETTE.y), "sheep produce draws twine-bound wool")
	expect(not has_colour(sheep, Art.PALETTE.y), "sheep idle has no wool bundle")

func has_colour(image: Image, colour: Color) -> bool:
	if image == null:
		return false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a8 > 0 and image.get_pixel(x, y).to_html() == colour.to_html():
				return true
	return false

func verify_motion() -> void:
	var times := [0.0, 0.3, 0.61, 1.0, 1.25, 2.5, 3.7, 9.99, 123.4]
	for id in Art.IDS:
		for state in Art.STATES:
			var still := Art.texture_at(id, state, 0.0, true)
			for t in times:
				expect(Art.texture_at(id, state, t, true) == still, "%s %s reduced motion static at t=%s" % [id, state, t])
				expect(Art.motion_offset(state, t, true) == Vector2i.ZERO, "%s reduced motion zero offset t=%s" % [state, t])
				var o := Art.draw_origin(Vector2(100.4, 200.6), state, t, true)
				expect(o == Vector2(76, 169), "%s reduced draw origin fixed whole pixels (%s)" % [state, o])
	var frames := {}
	var offsets := {}
	for i in 40:
		var t := i * 0.25
		frames[Art.frame_index(t, false)] = true
		var off := Art.motion_offset("idle", t, false)
		offsets[off] = true
		expect(absi(off.x) <= 1 and off.y == 0, "idle shuffle stays within 1px (t=%s)" % t)
		expect(Art.motion_offset("fed", t, false) == Vector2i.ZERO and Art.motion_offset("produce", t, false) == Vector2i.ZERO, "fed/produce planted")
		var o := Art.draw_origin(Vector2(100.4, 200.6), "idle", t, false)
		expect(o == o.round(), "animated draw origin is whole pixels")
	expect(frames.size() == 2, "animation cycles both frames")
	expect(offsets.size() == 3, "idle shuffle visits -1/0/+1 px")
	expect(Art.frame_index(-5.0, false) == 0, "negative elapsed clamps to frame 0")
	var peak:=Art.PET_SECONDS/2.0
	expect(Art.reaction_offset("cow",peak,0,false)==Vector2(0,2),"A newly acquainted cow dips toward the feed")
	expect(Art.reaction_offset("cow",peak,5,false)==Vector2(0,3),"A bonded cow makes a stronger motion")
	expect(Art.reaction_offset("sheep",peak,0,false)==Vector2(0,-3),"A newly acquainted sheep hops")
	expect(Art.reaction_offset("sheep",peak,5,false)==Vector2(0,-6),"A bonded sheep makes a higher hop")
	for id in Art.IDS:
		expect(Art.reaction_offset(id,peak,5,true)==Vector2.ZERO,"Reduced motion keeps the animal still")
		expect(Art.reaction_offset(id,Art.PET_SECONDS,5,false)==Vector2.ZERO,"The reaction ends at the home position")

func verify_reaction_events() -> void:
	var World=preload("res://scripts/world.gd")
	var world=World.new()
	world.add_player("ranch","牧場")
	world.state.picnic=true
	var actor:Dictionary=world.state.players.ranch
	var cell:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	actor.x=cell.x+0.5
	actor.y=cell.y+0.5
	actor.inventory.feed=1
	expect(world.act("ranch","adopt-cow","livestock_adopt",cell,"cow").ok,"D07: the cow is adopted before it is fed")
	var view=preload("res://scripts/world_view.gd").new()
	root.add_child(view)
	view.set_process(false)
	view.update_snapshot(world.state.duplicate(true),"ranch")
	expect(view.livestock_pet_feedback.is_empty(),"Joining does not animate the stored livestock state")
	expect(world.act("ranch","feed-cow","livestock_feed",cell,"cow").ok,"Cow feeding succeeds through World")
	view.elapsed=1.0
	view.update_snapshot(world.state.duplicate(true),"ranch")
	expect(view.livestock_pet_feedback.get("cow")==1.0,"Cow reacts to confirmed feeding")
	view.elapsed=1.1
	view.update_snapshot(world.state.duplicate(true),"ranch")
	expect(view.livestock_pet_feedback.get("cow")==1.0,"Duplicate snapshots do not restart the reaction")
	cell=World.LIVESTOCK.ANIMALS.sheep.cell
	actor.x=cell.x+0.5
	actor.y=cell.y+0.5
	expect(world.act("ranch","pet-sheep","livestock_pet",cell,"sheep").ok,"Sheep petting succeeds through World")
	view.update_snapshot(world.state.duplicate(true),"ranch")
	expect(view.livestock_pet_feedback.get("sheep")==1.1,"Sheep reacts to confirmed petting")
	view.free()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	verify_parts()
	verify_api()
	verify_sprites()
	verify_motion()
	verify_reaction_events()
	for line in report:
		print("LIVESTOCK " + line)
	print("LIVESTOCK_SCENE_ART_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
