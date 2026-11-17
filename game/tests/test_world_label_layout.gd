extends SceneTree

const World = preload("res://scripts/world.gd")
const View = preload("res://scripts/world_view.gd")
const Layout = preload("res://scripts/world_label_layout.gd")
const MILL := Vector2i(44, 30)
const MILL_KEY := "44,30"
const MILL_TITLE := "麵粉磨坊 · 加工中 42%"

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func rects(list: Array) -> Array[Rect2]:
	var typed: Array[Rect2] = []
	for r in list:
		typed.append(r)
	return typed

func run() -> void:
	geometry_checks()
	view_checks()
	crowded_people_checks()
	await process_frame
	print("WORLD_LABEL_LAYOUT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

func crowded_people_checks()->void:
	var world:=World.new()
	world.add_player("local","旅人")
	var view:=View.new()
	root.add_child(view)
	view.set_process(false)
	view.update_snapshot(world.state.duplicate(true),"local")
	for extent in [Vector2(1024,640),Vector2(1280,800),Vector2(1920,1080)]:
		for zoom_value in [1.0,2.0]:
			view.zoom=zoom_value
			view.camera=Vector2.ZERO
			var area:=Rect2(Vector2.ZERO,extent/zoom_value)
			var foot:=area.get_center()
			view.display_positions={"local":foot/32.0,"visitor":(foot+Vector2(32,-12))/32.0}
			var resident:=Layout.body_rect(foot+Vector2(-32,-8))
			view.character_label_obstacles=[resident]
			view.world_labels.clear()
			view.world_label(foot+Vector2(0,-20),"兌換紀念品","souvenir:booth")
			view.focused_label="souvenir:booth"
			var placements:=view.world_label_placements(area)
			expect(placements.size()==1 and placements[0].active,"Crowded interaction retains its focused action")
			if placements.is_empty():continue
			var box:Rect2=placements[0].rect
			expect(not box.intersects(resident),"Focused action avoids rendered resident")
			for person in view.display_positions.values():
				expect(not box.intersects(Layout.body_rect(person*32.0)),"Focused action avoids every player")
			expect(area.encloses(box),"Crowded action remains inside viewport")
	view.queue_free()

func geometry_checks() -> void:
	var viewport := Rect2(0, 0, 512, 320)
	var area := Layout.safe_area(viewport)
	expect(area == Rect2(4, 4, 504, 312), "safe area insets the screen edge")
	expect(Layout.safe_area(Rect2(0, 0, 20, 20)) == Rect2(0, 0, 20, 20), "tiny viewport is not inset")

	var free := Rect2(200, 100, 120, 16)
	var plain := Layout.place(free, Vector2(260, 116), rects([]), area)
	expect(plain.clear and plain.rect == free, "unobstructed label keeps its natural spot")

	# Long processing label anchored above a mill while the player stands on it.
	var foot := Vector2(256, 160)
	var body := Layout.body_rect(foot)
	expect(body == Rect2(241, 116, 30, 48), "body footprint matches the drawn player")
	var anchor := foot + Vector2(0, -18)
	var preferred := Rect2(anchor.x - 70, anchor.y - 16, 140, 16)
	expect(preferred.intersects(body), "fixture reproduces the label crossing the torso")
	var first := Layout.place(preferred, anchor, rects([body]), area)
	var second := Layout.place(preferred, anchor, rects([body]), area)
	expect(first.clear and not first.rect.grow(Layout.CLEARANCE).intersects(body), "label steps off the player body")
	expect(first.rect == second.rect, "placement is deterministic")
	expect(first.rect.size == preferred.size, "label is never resized or truncated")
	expect(area.encloses(first.rect), "label stays inside the edge margin")
	expect(Layout.distance_to_rect(anchor, first.rect) <= 24.0, "label stays near its target anchor")

	var edge_anchor := Vector2(506, 40)
	var edge := Layout.place(Rect2(edge_anchor.x - 70, 24, 140, 16), edge_anchor, rects([]), area)
	expect(area.encloses(edge.rect), "label near the right edge is pulled inside")

	var hud := Rect2(0, 280, 512, 40)
	var low_anchor := Vector2(256, 290)
	var low := Layout.place(Rect2(186, 274, 140, 16), low_anchor, rects([hud]), area)
	expect(low.clear and not low.rect.intersects(hud), "label avoids a HUD band")

	var cramped := Rect2(0, 0, 60, 30)
	var blocked := Layout.place(Rect2(0, 0, 50, 16), Vector2(25, 16), rects([cramped]), cramped)
	expect(not blocked.clear and blocked.rect.size == Vector2(50, 16) and cramped.encloses(blocked.rect),
		"no clear spot still returns the prompt instead of dropping it")

func label_width(view, title: String, active: bool) -> float:
	var width: float = ceilf(view.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, view.world_label_font_size()).x/view.view_zoom()) + 8
	if active:
		width += view.interaction_badge_width() + 3
	return width

func view_checks() -> void:
	var world = World.new()
	world.add_player("local", "田園")
	var view = View.new()
	root.add_child(view)
	view.set_process(false)
	view.update_snapshot(world.state.duplicate(true), "local")
	view.show_target = false
	for extent in [Vector2(1024, 640), Vector2(1280, 800), Vector2(1920, 1080)]:
		for zoom_value in [1.0, 2.0]:
			for side in ["center", "right"]:
				view.zoom = zoom_value
				var tag := "%s zoom %s %s" % [extent, zoom_value, side]
				var viewport := Rect2(Vector2.ZERO, extent / zoom_value)
				var foot := (viewport.size / 2).round() if side == "center" else Vector2(viewport.end.x - 20, roundf(viewport.size.y / 2))
				# Player stands just north of the mill, the case seen in the mill screenshot.
				var position := Vector2(MILL) + Vector2(0.5, -0.25)
				view.camera = position * view.TILE - foot
				view.display_positions.local = position
				var mill_at: Vector2 = view.screen(Vector2(MILL))
				var npc_anchor := foot+Vector2(-110,-45)
				view.world_labels.clear()
				view.world_label(mill_at + Vector2(16, -26), MILL_TITLE, MILL_KEY)
				view.world_label(foot + Vector2(0, -40), "田園", "")
				view.world_label(npc_anchor, "米露", "milu")
				view.focused_label = MILL_KEY
				view.label_avoid_rects.clear()
				view.label_text_scale=1.0 if side=="center" else 1.25
				var height:float=ceilf(view.font.get_height(view.world_label_font_size())/zoom_value)+4
				var placements: Array = view.world_label_placements(viewport)
				var by_id := {}
				for entry in placements:
					by_id[entry.id] = entry
				expect(by_id.has(MILL_KEY) and by_id[MILL_KEY].active, "focused mill prompt is shown at %s" % tag)
				expect(not by_id.has("") and by_id.has("milu"), "nearby NPC name remains visible while the local name stays hidden at %s" % tag)
				if not (by_id.has(MILL_KEY) and by_id.has("milu")):
					continue
				var body := Rect2(foot - Vector2(15, 44), Vector2(30, 48))
				var active: Rect2 = by_id[MILL_KEY].rect
				var anchor: Vector2 = (mill_at + Vector2(16, -26)).round()
				var natural := Rect2(roundf(anchor.x - label_width(view, MILL_TITLE, true) / 2.0), anchor.y - height,
					label_width(view, MILL_TITLE, true), height)
				expect(natural.intersects(body), "fixture's old placement crosses the torso at %s" % tag)
				expect(not active.intersects(body), "mill prompt avoids the player body at %s" % tag)
				expect(not active.intersects(by_id["milu"].rect), "mill prompt remains distinct from the nearby name tag at %s" % tag)
				expect(viewport.grow(-Layout.EDGE_MARGIN).encloses(active), "mill prompt keeps clear of the screen edge at %s" % tag)
				expect(active.size.x == natural.size.x, "mill prompt keeps full text and key badge at %s" % tag)
				expect(Layout.distance_to_rect(anchor, active) <= 40.0, "mill prompt stays near the mill at %s" % tag)
				var expected_font:=roundi((18 if zoom_value==1.0 else 28)*view.label_text_scale)
				expect(view.world_label_font_size()==expected_font,"Names use the chosen scale at final pixel size")
				var npc_width := label_width(view, "米露", false)
				expect(by_id["milu"].rect == Rect2(roundf(npc_anchor.x - npc_width / 2.0), npc_anchor.y - height, npc_width, height),
					"NPC name keeps its natural spot at %s" % tag)
				# Root may report visible HUD rects in screen pixels; the prompt must avoid them too.
				var hud_screen := Rect2(active.position * zoom_value, active.size * zoom_value)
				view.label_avoid_rects.clear()
				view.label_avoid_rects.append(hud_screen)
				var again: Array = view.world_label_placements(viewport)
				var moved: Rect2 = again.filter(func(entry): return entry.id == MILL_KEY)[0].rect
				var hud := Rect2(hud_screen.position / zoom_value, hud_screen.size / zoom_value)
				expect(not moved.intersects(hud) and not moved.intersects(body), "mill prompt avoids reported HUD at %s" % tag)
				view.world_label(foot-Vector2(6,12),"出貨箱","shipping")
				for entry in view.world_label_placements(viewport):
					if entry.id=="shipping":
						expect(not entry.rect.intersects(body) and not entry.rect.intersects(hud),"Passive labels keep the player and HUD clear at %s" % tag)
	view.label_avoid_rects.clear()
	view.queue_free()
