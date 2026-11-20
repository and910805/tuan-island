extends SceneTree
## T064 公用耕田機：地圖農機架、登記頁、工具列與生活技能卡片的介面驗證。
##
## FIXTURES（不是正常遊玩取得）：直接把野餐設為已舉辦、把角色放到農機架旁、
## 預置 2 份木炭。登記、選工具與整地都走正式的互動鍵、按鈕與 session.perform。
## 參數：--size=WxH（預設 1024x640）、--large-text、--capture-dir=<資料夾>（非 headless 才截圖）。

const World:=preload("res://scripts/world.gd")
const Loan:=World.PUBLIC_TILLER
const LoanUI:=preload("res://scripts/public_tiller_ui.gd")
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Shell:=preload("res://scripts/life_ui_shell.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func settle(frames:=3) -> void:
	for frame in frames:await process_frame

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=1024 and wanted.y>=640:return wanted
	return Vector2i(1024,640)

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree():lines.append((candidate as Label).text)
	return "\n".join(lines)

func check_fit(label:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+label+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+label+")")
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if target.is_visible_in_tree():expect(target.size.x+1.0>=target.get_combined_minimum_size().x,"Button is not squeezed (%s): %s"%[label,str(target.name)])

func rack_label() -> String:
	for entry:Dictionary in app.view.world_labels:
		if entry.id==Loan.POINT:return entry.title
	return ""

func run() -> void:
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if "--large-text" in OS.get_cmdline_user_args():
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var path:="user://public-tiller-ui-%d.json"%OS.get_process_id()
	if app.session.host(0,"晚來島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	app.sound.volume=0.0
	world.state.chapter_one.shipped=true
	var slot:Button=app.preview_toolbar.find_child("TillerSlot",true,false)
	var rack:Vector2i=Loan.SITES[0]
	var beside:=rack+Vector2i.UP

	# --- 野餐前：沒有農機架、沒有互動點，也借不到 -------------------------------
	stand(beside)
	await settle()
	expect(Loan.site(world.state)==Loan.NO_SITE and LoanUI.points(app.session.snapshot).is_empty(),"No rack or interaction point before the picnic")
	expect(app.view.interaction_focus()!=Loan.POINT,"Nothing to focus at the rack cell before the picnic")
	expect(slot!=null and not slot.visible,"Tiller slot is hidden without a machine or a loan")
	app._select_tool("till_area")
	expect(app.selected!="till_area","The tiller cannot be equipped without a machine or a loan")

	# --- 野餐後：農機架出現，標籤說明能做什麼 ---------------------------------
	world.state.picnic=true
	person.inventory.charcoal=2
	stand(beside)
	await settle()
	expect(Loan.site(app.session.snapshot)==rack,"The rack stands on the first reserved cell after the picnic")
	expect(app.view.interaction_focus()==Loan.POINT,"Standing beside the rack focuses it (got %s)"%app.view.interaction_focus())
	if DisplayServer.get_name()!="headless":
		await settle(4)
		expect(rack_label()=="借用公用耕田機","The map label invites borrowing (got '%s')"%rack_label())
	expect(Loan.label(person)=="借用公用耕田機","Label text for a player who has not borrowed")
	await capture("01-rack-on-map.png")

	# --- 互動鍵開登記頁 -------------------------------------------------------
	app._interact()
	await settle()
	expect(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="public_tiller","The interact key opens the public tiller page")
	check_fit("loan page")
	var borrow:=button("PublicTillerBorrow")
	expect(borrow!=null and not borrow.disabled,"The borrow button is enabled beside the rack")
	expect(visible_text(app.modal).contains("不進背包"),"The page says the loan is not an item")
	await capture("02-loan-page.png")
	var bag_before:Dictionary=person.inventory.duplicate(true)
	if borrow!=null and not borrow.disabled:borrow.pressed.emit()
	await settle()
	expect(person.get(Loan.FIELD,false)==true,"Pressing the button registers the loan on the host world")
	expect(person.inventory==bag_before and not person.inventory.has("tiller"),"Borrowing hands out no inventory")
	expect(not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout","")!="public_tiller","The page closes after registering")

	# --- 工具列、快捷鍵與提示 -------------------------------------------------
	stand(beside)
	await settle()
	Shell.refresh_hud(app,app.session.snapshot,app.session.snapshot.players[app.session.own_id])
	await settle()
	expect(slot.visible,"Tiller slot appears for a borrower")
	expect(Loan.label(app.session.snapshot.players[app.session.own_id])=="公用耕田機・已登記","Label changes once registered")
	var shortcut:=InputEventKey.new()
	shortcut.keycode=KEY_U
	shortcut.physical_keycode=KEY_U
	shortcut.pressed=true
	app._select_tool("hoe")
	app._unhandled_input(shortcut)
	expect(app.selected=="till_area","The tiller key equips the borrowed machine")
	await capture("03-borrowed-toolbar.png")

	# --- 用借來的機器整地：耗自己的木炭，田是自己的 -----------------------------
	var field:=Vector2i(47,35)
	stand(field)
	await settle()
	var plan:Dictionary=World.TILLER.plan(world,token,field)
	expect(plan.cells.size()>0,"Fixture field has tillable ground")
	app._perform_build_action("till_area",field)
	await settle()
	var mine:=0
	for key:String in plan.cells:
		if world.state.crops.get(key,{}).get("owner","")==token:mine+=1
	expect(mine==plan.cells.size() and int(person.inventory.get("charcoal",0))==1,"One pass tills the planned cells for the borrower and spends one charcoal")
	expect(not person.inventory.has("tiller"),"Still no tiller item after using the loan")
	await capture("04-tilled-with-loan.png")

	# --- 再開登記頁與生活技能卡片 ---------------------------------------------
	stand(beside)
	await settle()
	app._select_tool("hoe")
	app._interact()
	await settle()
	expect(is_instance_valid(app.modal) and button("PublicTillerBorrow")==null and visible_text(app.modal).contains("已登記"),"A registered player sees the status instead of the button")
	check_fit("registered page")
	await capture("05-registered-page.png")
	app._close_modal()
	person.erase(Loan.FIELD)
	stand(rack+Vector2i(8,8))
	await settle()
	Tasks.skill_book(app)
	await settle()
	var far:=button("PublicTillerBorrow")
	expect(far!=null and far.disabled and visible_text(app.modal).contains("農機架"),"The skill book offers the loan but asks a distant player to walk to the rack")
	await capture("06-skill-book.png")
	var directions:=button("PublicTillerDirections")
	expect(directions!=null and not directions.disabled,"The skill book offers a map to a distant borrower")
	if directions!=null:
		directions.pressed.emit()
		await settle()
		if is_instance_valid(app.map_view):
			var route:Array=app.map_view.home_route_cells
			var status:=app.modal.find_child("HomeWalkRouteStatus",true,false) as Label
			expect(app.map_view.home_route=="tiller" and button("TillerWalkRoute").button_pressed,"The map opens with the tiller route selected")
			expect(route.size()>1 and (route.back() as Vector2i).distance_squared_to(rack)==1,"The displayed path leads to a walkable tile beside the rack")
			expect(status.text.contains("渡口農機架") and status.text.contains("步行"),"The route names the rack and shows the walking distance")
			await capture("07-find-loan.png")
			var occupied:Dictionary=app.session.snapshot.duplicate(true)
			for site:Vector2i in Loan.SITES:occupied.ground[World.key(site)]={"type":"floor","owner":token}
			app.map_view.update_world(occupied,app.session.own_id)
			var fallback:Array=app.map_view.home_route_cells
			expect(fallback.size()>1 and (fallback.back() as Vector2i).distance_squared_to(Loan.DESK)==1,"If all rack sites are occupied, the path updates to the board")
			expect(status.text.contains("公告板借用處"),"The map describes the board fallback")
			button("LocalMapTravel").pressed.emit()
			await settle()
			expect(button("PublicTillerDirections")!=null,"The map returns to the skill book")
		else:expect(false,"The loan directions open the local map")
	app._close_modal()
	person.inventory.tiller=1
	stand(beside)
	await settle()
	app._interact()
	await settle()
	expect(is_instance_valid(app.modal) and button("PublicTillerBorrow")==null and visible_text(app.modal).contains("自己的手推耕田機"),"An owner is told to leave the public machine for others")
	app._close_modal()

	app.playing=false
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.queue_free()
	await process_frame
	print("PUBLIC_TILLER_UI_TESTS checks=%d failures=%d art=%s"%[checks,failures,"png" if Loan.texture()!=null else "fallback"])
	quit(int(failures>0))
