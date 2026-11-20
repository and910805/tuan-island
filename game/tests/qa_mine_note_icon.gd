extends SceneTree
## 礦務隨身記圖示：以正式 MineNoteIcon / QuestNote / TrackerNext 驗收。
## 執行：Godot --path game --resolution 1024x640 --script res://tests/qa_mine_note_icon.gd -- <輸出資料夾> [large]
const World=preload("res://scripts/world.gd")

class PointerProbe extends Node:
	var unhandled_left:=0
	func _unhandled_input(event:InputEvent)->void:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:unhandled_left+=1

var app
var directory:=""
var failures:Array[String]=[]
var world:World
var person:Dictionary

func _initialize()->void:
	run.call_deferred()

func check(name:String,ok:bool)->void:
	print("QA %s %s"%["PASS" if ok else "FAIL",name])
	if not ok:failures.append(name)

func click(control:Control)->void:
	var center:=control.get_global_transform_with_canvas()*(control.size*0.5)
	await click_at(center)

func click_at(center:Vector2)->void:
	var motion:=InputEventMouseMotion.new()
	motion.position=center;motion.global_position=center
	root.push_input(motion,true)
	for down in [true,false]:
		var button:=InputEventMouseButton.new()
		button.button_index=MOUSE_BUTTON_LEFT
		button.position=center;button.global_position=center
		button.pressed=down
		button.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(button,true)
	await process_frame
	await process_frame

func shot(filename:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(filename))

func go(region:String)->void:
	person.region=region
	app.session._send_snapshot(1)
	app._refresh_hud()
	await process_frame
	await process_frame

func run()->void:
	var args:=OS.get_cmdline_user_args()
	directory=args[0]
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token="mine-note-icon-qa"
	if app.session.host(0,"礦務手記驗收",directory.path_join("fixture-%d.json"%OS.get_process_id()))!=OK:
		quit(1);return
	await create_timer(0.25).timeout
	app.session.set_physics_process(false)
	world=app.session.world
	world.state.board=true
	world.state.picnic=true
	world.state.mine_depths.unlocked=3
	person=world.state.players[app.session.peers[1]]
	person.x=45.5;person.y=23.5
	if args.has("large"):
		app.sound.preferred_text_scale=app.TEXT_SCALE_FACTORS.size()-1
		app._apply_font_scale_tree()
	await go("home")
	if is_instance_valid(app.modal):app._close_modal()
	app.set_process(false)
	app.toast.hide()
	var probe:=PointerProbe.new()
	root.add_child(probe)
	var note:=app.preview_tracker as Control
	var icon:=app.hud.get_node("MineNoteIcon") as Button
	var warning:=icon.get_node("LowMineEnergy") as Label
	var title:=app.hud.find_child("RegionTitle",true,false) as Control
	var next:=note.find_child("TrackerNext",true,false) as Button
	var visible_rect:=root.get_visible_rect()
	print("QA window=%s canvas=%s"%[root.size,visible_rect.size])

	# 其他場景：不顯示圖示，追蹤卡照舊。
	check("home: icon hidden, note visible",not icon.visible and note.visible)
	check("home: note original width",note.size.x==226.0 and next.text=="看看下一步  →")
	await go("home")
	var home_y:=note.position.y
	await shot("00-home.png")

	# 進礦：預設收起。
	await go("mine_2")
	await shot("01-mine-collapsed.png")
	check("mine: a full stamina bar keeps the icon clear",not warning.is_visible_in_tree() and "100／100" in icon.tooltip_text)
	check("mine: the default tool suggests switching to the pickaxe",app.selected=="hoe" and app.selected_label.text=="採礦 · 按 %s 換十字鎬"%app.binding_label("pick"))
	app._select_tool("pick")
	app._refresh_hud()
	check("mine: no pickaxe shows where to borrow one",app.selected_label.text=="採礦需要強化石鎬 · 休息站可借公用鎬")
	var rest:Vector2i=World.MINES.REST
	person.x=rest.x+0.5;person.y=rest.y+1.5
	await go("mine_2")
	app._interact()
	await process_frame
	var loan:=app.modal.find_child("MineBorrowPick",true,false) as Button if is_instance_valid(app.modal) else null
	check("mine: rest station offers the public pick",loan!=null and not loan.disabled)
	if loan!=null:
		var ancestor:=loan.get_parent()
		while ancestor!=null and not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(loan)
		await process_frame
		var loan_point:=loan.get_global_transform_with_canvas()*(loan.size*0.5)
		check("mine: the loan button is covered by the modal world-input guard",not app._world_pointer_allowed(loan_point))
		await click(loan)
	check("mine: borrowing through the station grants use of the public pick",person.get("borrowed_mine_pick",false))
	if is_instance_valid(app.modal):app._close_modal()
	var ore_cell:Vector2i=World.MINES.NODES[0]
	person.mine_energy=26
	person.x=ore_cell.x+0.5;person.y=ore_cell.y+1.5
	await go("mine_2")
	check("mine: selecting the pickaxe describes mining veins",app.selected_label.text=="十字鎬 · 靠近礦脈後點擊採掘")
	var ore:String=World.MINES.ORES[1]
	var before_ore:=int(person.inventory.get(ore,0))
	var ore_point:Vector2=app.view.screen(Vector2(ore_cell)+Vector2(0.5,0.5))*app.view.view_zoom()
	await click_at(ore_point)
	app._refresh_hud()
	await process_frame
	check("mine: the selected tool collects ore through the host",int(person.inventory.get(ore,0))==before_ore+World.MINES.YIELDS[1])
	var energy:=World.MEAL_BUFF.whole_points(person)
	check("a mining strike reveals the exact low stamina count",energy>0 and energy<=25 and warning.is_visible_in_tree() and warning.text==str(energy) and "休息站喝水" in icon.tooltip_text)
	check("the stamina count stays inside the compact icon",icon.get_global_rect().encloses(warning.get_global_rect()))
	await shot("06-mine-public-pick-result.png")
	probe.unhandled_left=0
	person.x=45.5;person.y=23.5
	await go("mine_2")
	check("mine: icon visible, note collapsed",icon.visible and not note.visible)
	check("mine: glyph is the 32px notebook art",(icon.get_node("ToolArt") as TextureRect).texture.get_size()==Vector2(32,32) and icon.size==Vector2(48,48))
	check("mine: tooltip kept",icon.tooltip_text.begins_with("礦務隨身記"))
	check("mine: icon sits under the region title",icon.position.x<=24.0 and icon.get_global_rect().position.y>=title.get_global_rect().end.y and icon.position.y<=home_y+8.0)
	check("mine: icon inside window",visible_rect.encloses(icon.get_global_rect()))
	check("mine: no shortcut badge, no focus steal",icon.get_node_or_null("KeyBadge")==null and icon.focus_mode==Control.FOCUS_NONE)
	check("mine: icon blocks world pointer",not app._world_pointer_allowed(icon.get_global_rect().get_center()))
	check("mine: heading still mine notebook",(note.find_child("TrackerHeading",true,false) as Button).text.begins_with("礦務隨身記"))

	# 一次點擊展開，二次點擊收起。
	await click(warning)
	await shot("02-mine-expanded.png")
	check("click 1: expanded",note.visible)
	check("expanded: below icon, no overlap",not note.get_global_rect().intersects(icon.get_global_rect()) and note.get_global_rect().position.y>=icon.get_global_rect().end.y)
	check("expanded: inside window",visible_rect.encloses(note.get_global_rect()))
	check("expanded: next button inside note",next.is_visible_in_tree() and note.get_global_rect().encloses(next.get_global_rect()))
	check("expanded: no overlap with toolbar",not note.get_global_rect().intersects(app.preview_toolbar.get_global_rect()))
	check("expanded: no overlap with weather badge",not note.get_global_rect().intersects(app.preview_top.get_global_rect()))
	check("expanded: stamina/route text present",app.objective.is_visible_in_tree() and app.objective.text.length()>0)
	var objective:=app.objective as Label
	var hint:="往東找觀察點"
	var hint_width:=objective.get_theme_font("font").get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,objective.get_theme_font_size("font_size")).x
	check("expanded: direction has a dedicated line that fits",objective.text.ends_with("\n"+hint) and hint_width<=objective.size.x)
	print("QA objective=%s"%app.objective.text.replace("\n"," / "))
	await click(icon)
	check("click 2: collapsed",not note.visible and icon.visible)
	await click(icon)
	check("click 3: expanded again",note.visible)

	# 重複 HUD 更新與換樓層保留玩家選擇。
	for i in 3:
		app._refresh_hud()
		await process_frame
	app._layout_preview()
	await process_frame
	check("repeated refresh keeps open",note.visible and icon.visible)
	await go("mine_3")
	check("mine_2 -> mine_3 keeps open",note.visible and icon.visible)
	await click(icon)
	check("closed on mine_3",not note.visible)
	for i in 3:
		app._refresh_hud()
		await process_frame
	await go("mine_1")
	check("mine_3 -> mine_1 keeps closed",not note.visible and icon.visible)
	await go("mine_2")
	await click(icon)
	check("reopen",note.visible)

	# 地圖行動依舊。
	await click(next)
	var map_open:bool=is_instance_valid(app.modal) and str(app.modal.get_meta("life_modal_layout",""))=="island_map"
	check("TrackerNext opens island map",map_open)
	if is_instance_valid(app.modal):
		await create_timer(0.3).timeout
		await shot("03-map.png")
		app._close_modal()
		await process_frame
	check("map closed, note state kept",note.visible and icon.visible)
	var shortcut_map:=InputEventKey.new()
	shortcut_map.keycode=app.bindings.keys["map"]
	shortcut_map.physical_keycode=app.bindings.keys["map"]
	shortcut_map.pressed=true
	root.push_input(shortcut_map,true)
	await process_frame
	await process_frame
	var key_map:bool=is_instance_valid(app.modal)
	check("original map shortcut still works",key_map)
	if is_instance_valid(app.modal):app._close_modal()
	await process_frame
	check("no leaked world clicks",probe.unhandled_left==0)
	person.x=rest.x+0.5;person.y=rest.y+1.5
	await go("mine_2")
	app._interact()
	await process_frame
	var water:=app.modal.find_child("MineRest",true,false) as Button if is_instance_valid(app.modal) else null
	check("the rest station offers water",water!=null and not water.disabled)
	if water!=null:
		var rest_scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		if rest_scroll!=null:rest_scroll.ensure_control_visible(water)
		await process_frame
		await click(water)
	if is_instance_valid(app.modal):app._close_modal()
	app._refresh_hud()
	await process_frame
	check("drinking refills stamina and clears the badge",World.MEAL_BUFF.whole_points(person)==100 and not warning.is_visible_in_tree() and "100／100" in icon.tooltip_text)

	# 離礦：還原。
	await go("home")
	await shot("04-home-restored.png")
	check("leave mine: selected pickaxe restores the outdoor hint",app.selected=="pick" and "點附近岩石" in app.selected_label.text)
	check("leave mine: icon hidden, note restored",not icon.visible and note.visible and note.size.x==226.0)
	check("leave mine: note position restored",absf(note.position.y-home_y)<0.5 and next.text=="看看下一步  →")
	check("leave mine: icon no longer in pointer gate",not icon.is_visible_in_tree())
	await go("mine_2")
	check("re-enter mine: collapsed by default",icon.visible and not note.visible)
	world.state.mine_depths.unlocked=World.MINES.SHALLOW_DEPTH+1
	var deep_region:String=World.MINES.IDS[World.MINES.SHALLOW_DEPTH]
	await go(deep_region)
	check("deep mine: borrowed pick does not hide the personal pick requirement",app.selected_label.text=="深層礦道需要自備強化石鎬")
	person.inventory.reinforced_pick=1
	await go(deep_region)
	check("deep mine: personal pick restores the mining hint",app.selected_label.text=="十字鎬 · 靠近礦脈後點擊採掘")

	print("TRACKER_ICON_QA failures=%d unhandled=%d window=%s canvas=%s"%[failures.size(),probe.unhandled_left,root.size,visible_rect.size])
	app.session.shutdown()
	quit(1 if not failures.is_empty() else 0)
