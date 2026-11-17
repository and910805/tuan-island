extends SceneTree

const InventoryPanel = preload("res://scripts/inventory_panel.gd")
const World = preload("res://scripts/world.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const EXISTING_IDS := ["tea_leaf","clay","tea_jar","tea_returned_jar","tea_worn_jar","tea_spent_jar","tea_light","tea_deep","mine_drill_kit","waterworks_kit","gold_ore","gold_sample","wood","stone","fiber","radish","lettuce","wheat","radish_seed","lettuce_seed","wheat_seed","carp","minnow","redfish","loach","egg","feed","soup","bread","sapling","carrot","potato","tomato","carrot_seed","potato_seed","tomato_seed","salad","baked_potato","grilled_fish","carrot_soup","reinforced_pick","copper_ore","copper_joint","sprinkler_kit","plank","resin","charcoal","pipe_kit","tank_kit","pump_kit","sawmill_kit","kiln_kit","forester_kit","conveyor_kit","tiller","seeder","harvester","pumpkin","pumpkin_seed","flour","pumpkin_pie","mill_kit"]
const FLOWER_IDS := ["bluebell","orange_blossom","chime_herb","bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar","garden_cookie"]
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
	world.add_player("player", "島民")
	var panel := InventoryPanel.new()
	root.add_child(panel)
	panel.setup(world.state, "player", Theme.new())
	expect(panel.slots.size()==World.NAMES.size() and World.NAMES.keys().all(func(id):return panel.slots.has(id)),"Inventory exposes every registered item")
	for id in EXISTING_IDS:
		expect(panel.slots.has(id),"existing inventory item preserved: "+id)
	for id in FLOWER_IDS:
		expect(panel.slots.has(id),"new flower inventory item present: "+id)
	for spec in [["ochre_earth","ochre-earth","clay"],["vein_quartz","vein-quartz","stone"]]:
		var icon:=ItemArt.icon(spec[0])
		var original:=ItemArt.icon(spec[2])
		expect(icon.resource_path.ends_with("/"+spec[1]+".png"),"Deep-mine material uses dedicated art: "+spec[0])
		expect(icon.get_size()==Vector2(32,32) and icon.get_image().get_pixel(0,0).a==0.0,"Icon is 32px with a transparent background: "+spec[0])
		expect(icon.get_image().get_data()!=original.get_image().get_data(),"Mine sprite is distinct from its old source: "+spec[0])
	var tea_items := [
		["tea_leaf", "新鮮茶葉", "烘焙台", 2],
		["clay", "陶土", "工坊窯", 3],
		["tea_jar", "陶罐", "小栗", 4],
		["tea_returned_jar", "回收陶罐", "優先使用", 5],
		["tea_worn_jar", "磨損陶罐", "剩 1 次", 8],
		["tea_spent_jar", "待修陶罐", "不能裝茶", 9],
		["tea_light", "淺焙茶", "寄運桌", 6],
		["tea_deep", "深焙茶", "寄運桌", 7],
	]
	for item in tea_items:
		var id: String = item[0]
		world.state.players.player.inventory[id] = item[3]
	panel.refresh(world.state, "player")
	for item in tea_items:
		var id: String = item[0]
		panel.select_item(id)
		var icon: Texture2D = panel.slots[id].artwork.texture
		expect(icon != null and icon.get_size() == Vector2(32,32) and icon.get_image() != null and not icon.get_image().is_invisible(), "%s has nonempty 32px art" % id)
		expect(panel.detail_name.text == item[1] and panel.detail_use.text.contains(item[2]) and panel.detail_count.text == "持有 %d" % item[3] and panel.slots[id].count == item[3], "%s has its own name, description and count" % id)
	panel.select_item("tea_worn_jar")
	expect(panel.detail_use.text.contains("最後一趟") and panel.detail_use.text.contains("修補"), "worn jar description explains last trip and repair")
	panel.select_item("tea_spent_jar")
	expect(panel.detail_use.text.contains("陶土 1 份") and panel.detail_use.text.contains("製罐窯"), "spent jar description explains repair material and kiln")
	var worn: Texture2D = panel.slots.tea_worn_jar.artwork.texture
	var spent: Texture2D = panel.slots.tea_spent_jar.artwork.texture
	expect(worn != null and spent != null and worn.get_image().get_data() != spent.get_image().get_data(), "worn and spent jars have distinct images")
	panel.select_item("wood")
	panel.select_category(1)
	expect(panel.slots.clay.visible and panel.slots.tea_jar.visible and panel.slots.tea_returned_jar.visible and panel.slots.tea_worn_jar.visible and panel.slots.tea_spent_jar.visible and not panel.slots.tea_leaf.visible and not panel.slots.tea_light.visible and not panel.slots.tea_deep.visible, "tea ceramics appear only under materials")
	expect(panel.slots.copper_ore.visible and panel.slots.copper_joint.visible, "copper items appear under materials")
	expect(panel.slots.plank.visible and panel.slots.resin.visible and panel.slots.charcoal.visible, "forestry outputs appear under materials")
	panel.select_category(3)
	expect(panel.slots.tea_leaf.visible and panel.slots.tea_light.visible and panel.slots.tea_deep.visible and not panel.slots.clay.visible and not panel.slots.tea_jar.visible and not panel.slots.tea_returned_jar.visible and not panel.slots.tea_worn_jar.visible and not panel.slots.tea_spent_jar.visible, "tea harvests appear only under harvest")
	panel.select_category(4)
	expect(panel.slots.reinforced_pick.visible and panel.slots.sprinkler_kit.visible, "automation equipment appears under other items")
	expect(panel.slots.pipe_kit.visible and panel.slots.sawmill_kit.visible, "industry kits appear under other items")
	expect(panel.slots.forester_kit.visible, "forestry kit appears under other items")
	panel.select_category(0)
	for extent in [Vector2(1024,640), Vector2(1280,720), Vector2(800,600), Vector2(1280,800), Vector2(1920,1080)]:
		panel.layout_for(extent)
		await process_frame
		await process_frame
		expect(panel.size == Vector2(minf(900,extent.x-32), 560), "panel keeps responsive width at %s (actual %s)" % [extent, panel.size])
		expect(panel.grid.columns==(5 if extent.x==800 else 6),"grid uses the available width at %s"%extent)
		expect(panel.get_rect().get_center().distance_to(extent / 2) < 1, "panel centers at %s" % extent)
		expect(panel.scroller.size.x >= panel.grid.size.x, "grid width fits tray at %s" % extent)
	expect(panel.selected_id == "wood" and panel.detail_count.text == "持有 12", "wood is selected on open")
	panel.select_category(2)
	expect(panel.selected_id == "radish_seed", "seed tab selects its first item")
	panel.slots.tomato_seed.grab_focus()
	expect(panel.selected_id == "tomato_seed" and panel.detail_count.text == "持有 0", "zero-count seed remains selectable")
	expect(panel.detail_value.text == "購入價　55 鈴幣", "seed price matches shop")
	var focused := root.gui_get_focus_owner()
	world.state.players.player.inventory.tomato_seed = 3
	panel.refresh(world.state, "player")
	expect(panel.slots.tomato_seed.count == 3 and panel.detail_count.text == "持有 3", "live update changes slot and detail")
	expect(root.gui_get_focus_owner() == focused and panel.category == 2, "live update preserves focus and category")
	panel.select_category(0)
	expect(panel.selected_id == "tomato_seed", "selection persists when still visible")
	panel.show_notice("已保存", true)
	expect(panel.notice.visible and panel.notice.text == "已保存", "panel supports status notice")
	world.state.players.player.inventory.star_rice_ball=1
	world.state.players.player.mine_energy=94
	panel.refresh(world.state,"player")
	panel.select_item("star_rice_ball")
	expect(not panel.eat_rice_ball.visible,"food action is hidden outside mines")
	var mine_snapshot:Dictionary=world.state.duplicate(true)
	mine_snapshot.region_id="mine_1"
	panel.refresh(mine_snapshot,"player")
	expect(panel.eat_rice_ball.visible and not panel.eat_rice_ball.disabled and panel.eat_rice_ball.text.contains("6"),"mine shows the actual capped recovery")
	var requests:=[0]
	panel.rice_ball_requested.connect(func():requests[0]+=1)
	panel.eat_rice_ball.pressed.emit()
	expect(requests[0]==1,"eat button sends one request")
	mine_snapshot.players.player.mine_energy=100
	panel.refresh(mine_snapshot,"player")
	expect(panel.eat_rice_ball.disabled,"full energy disables food action")
	panel.select_item("fiber")
	expect(panel.craft_rope.visible and not panel.craft_rope.disabled,"fiber shows handcraft action")
	var rope_requests:=[0]
	panel.rope_requested.connect(func():rope_requests[0]+=1)
	panel.craft_rope.pressed.emit()
	expect(rope_requests[0]==1,"handcraft button sends one request")
	world.state.players.player.inventory.fiber=4
	panel.refresh(world.state,"player")
	expect(panel.craft_rope.disabled,"handcraft button disables below five fiber")
	panel.queue_free()
	await process_frame
	print("INVENTORY_PANEL_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
