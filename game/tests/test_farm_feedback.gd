extends SceneTree

const World = preload("res://scripts/world.gd")
const Feedback = preload("res://scripts/farm_feedback.gd")
const View = preload("res://scripts/world_view.gd")
const CENTER := Vector2i(42, 36)
const CELL := "42,36"

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func run() -> void:
	var world = World.new()
	world.add_player("local", "田園")
	world.add_player("remote", "鄰居")
	for person in world.state.players.values():
		person.x = 42.5
		person.y = 36.5
		person.inventory.merge({"tiller": 1, "seeder": 1, "harvester": 1, "charcoal": 6}, true)
	var feedback := Feedback.new()
	var before: Dictionary = world.state.duplicate(true)
	expect(world.act("local", "till", "till_area", CENTER).ok, "successful till")
	var after: Dictionary = world.state.duplicate(true)
	feedback.observe({}, after, 0.0)
	expect(feedback.active("local", 0.0).is_empty(), "initial old event is silent")
	feedback.reset()
	feedback.observe({}, before, 0.0)
	feedback.observe(before, after, 1.0)
	var active: Dictionary = feedback.active("local", 1.0)
	expect(active.get("kind") == "tiller" and active.get("cells", []).size() == 9, "tiller action starts feedback for actual plots")
	feedback.observe(after, after.duplicate(true), 1.2)
	expect(feedback.active("local", 1.2).get("started") == 1.0, "duplicate snapshot does not restart feedback")
	expect(feedback.active("local", 10.0).is_empty(), "feedback expires by presentation time")
	expect(feedback.active("remote", 1.2).is_empty(), "local event does not animate another player")
	world.state.players.local.inventory.radish_seed = 1
	before = world.state.duplicate(true)
	expect(world.act("local", "seed", "seed_area", CENTER, "radish").ok, "successful partial seed")
	after = world.state.duplicate(true)
	feedback.observe(before, after, 11.0)
	active = feedback.active("local", 11.0)
	expect(active.get("kind") == "seeder" and active.get("cells") == [CELL], "seed feedback shows actual limited footprint")
	expect(feedback.sprout_offset(CELL,11.0,false) == Vector2(0,-7), "new sprout starts above its plot")
	expect(feedback.sprout_offset(CELL,11.2,false) == Vector2(0,-2), "sprout settles in whole pixels")
	expect(feedback.sprout_offset("41,36",11.0,false) == Vector2.ZERO, "empty neighbor stays still")
	expect(feedback.sprout_offset(CELL,11.0,true) == Vector2.ZERO, "reduced motion draws sprout in final position")
	feedback.observe(after,after.duplicate(true),11.2)
	expect(feedback.sprout_offset(CELL,11.2,false) == Vector2(0,-2), "duplicate snapshot leaves the original timing")
	expect(feedback.sprout_offset(CELL,11.5,false) == Vector2.ZERO, "settled sprout stays on its soil")
	world.state.crops[CELL].growth = World.CROPS.radish.time
	before = world.state.duplicate(true)
	expect(world.act("local", "harvest", "harvest_area", CENTER).ok, "successful harvest")
	after = world.state.duplicate(true)
	feedback.observe(before, after, 12.0)
	active = feedback.active("local", 12.0)
	expect(active.get("kind") == "harvester" and active.get("items", {}).has(CELL), "harvest feedback can use crop from previous snapshot")
	var old_event: Dictionary = after.duplicate(true)
	world.step(1.0, true)
	expect(not world.act("local", "empty", "harvest_area", CENTER).ok, "failed batch does not harvest")
	feedback.observe(old_event, world.state.duplicate(true), 20.0)
	expect(feedback.active("local", 20.0).is_empty(), "failed action cannot play old feedback again")

	world.state.players.remote.x = 46.5
	before = world.state.duplicate(true)
	expect(world.act("remote", "remote-till", "till_area", Vector2i(46,36)).ok, "remote action succeeds")
	after = world.state.duplicate(true)
	feedback.observe(before, after, 21.0)
	expect(feedback.active("remote", 21.0).get("kind") == "tiller" and feedback.active("local", 21.0).is_empty(),
		"remote feedback stays on its actor")
	feedback.reset()
	expect(feedback.active("remote", 21.0).is_empty(), "reset clears visual events")

	var projected:Dictionary={"time":22.0,"view_rect":[0,0,12,12],"view_full":false,"crops":{
		"38,30":{"kind":"radish","growth":89.0,"owner":"remote"},
		"39,30":{"kind":"radish","growth":89.0,"owner":"local"},
		"4,5":{"kind":"radish","growth":89.0,"owner":"remote"}}}
	var expanded:=projected.duplicate(true)
	expanded.time=23.0
	expanded.erase("view_rect")
	for plot:Dictionary in expanded.crops.values():plot.growth=90.0
	feedback.observe({},projected,22.0,"local")
	feedback.observe(projected,expanded,23.0,"local")
	expect(feedback.ripening_age("38,30",23.0)<0,"Expanding world coverage never replays an unknown remote ripening")
	expect(feedback.ripening_age("4,5",23.0)==0 and feedback.ripening_age("39,30",23.0)==0,
		"Continuously observed crops and the player's own crops still show their ripening")

	var view = View.new()
	root.add_child(view)
	view.set_process(false)
	view.update_snapshot(before, "local")
	view.reduced_motion = true
	view.update_snapshot(after, "local")
	expect(view.farm_feedback.active("remote", view.elapsed).get("kind") == "tiller",
		"reduced motion retains remote feedback state")
	expect(not view.compact_farm_prompt(), "remote feedback does not compact local prompts")
	view.selected = "till_area"
	view.show_target = true
	expect(view.compact_farm_prompt(), "reduced motion still keeps farm interaction prompt compact")
	view.target = CENTER
	view.focused_label = "44,36"
	for extent in [Vector2(1024,640), Vector2(1280,800), Vector2(1920,1080)]:
		for zoom_value in [1.0, 2.0]:
			view.zoom = zoom_value
			var viewport := Rect2(Vector2.ZERO, extent / zoom_value)
			var foot := Vector2(viewport.end.x - 30, viewport.size.y / 2)
			view.camera = Vector2(42.5,36.5) * view.TILE - foot
			view.display_positions.local = Vector2(42.5,36.5)
			view.world_labels.clear()
			view.world_label(foot + Vector2(12,-8), "灑水器 · 補水與啟停", "44,36")
			view.world_label(Vector2(viewport.size.x / 2, -2), "離屏居民", "xiaoli")
			var placements: Array = view.world_label_placements(viewport)
			expect(not placements.any(func(entry): return entry.id == "xiaoli"),
				"offscreen resident stays hidden at %s and zoom %s" % [extent, zoom_value])
			var player_box := Rect2(foot - Vector2(15,44), Vector2(30,48))
			var plots := Rect2(view.screen(Vector2(CENTER - Vector2i.ONE)), Vector2(96,96))
			expect(placements.size() == 1 and placements[0].active, "interaction prompt stays visible near right edge")
			if not placements.is_empty():
				var rect: Rect2 = placements[0].rect
				expect(viewport.encloses(rect) and not rect.intersects(player_box) and not rect.intersects(plots),
					"prompt stays inside %s at zoom %s and off player/field" % [extent, zoom_value])
	view.show_target = false
	expect(not view.compact_farm_prompt(), "an inactive cursor does not suppress normal prompts")
	view.queue_free()
	await process_frame
	print("FARM_FEEDBACK_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
