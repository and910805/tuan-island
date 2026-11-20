extends SceneTree
## Real site interaction, using fixture travel, bond and chapter progress.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

var app

func shown(node_name:String) -> Control:
	if not is_instance_valid(app.modal):return null
	var node:=app.modal.find_child(node_name,true,false) as Control
	return node if node!=null and node.is_visible_in_tree() else null

func hint_text() -> String:
	var hint:Node=app.modal.find_child("AchaoRouteHint",true,false) if is_instance_valid(app.modal) else null
	return str(hint.get("text")) if hint!=null else ""

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await create_timer(0.21).timeout
			await settle()
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func fits(node_name:String,tag:String) -> void:
	var node:=shown(node_name)
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer if is_instance_valid(app.modal) else null
	expect(node!=null and scroll!=null and scroll.get_global_rect().encloses(node.get_global_rect()),"%s fits (%s)"%[node_name,tag])

## Opens the book from Achao's bond menu; the completed goal also offers AchaoGoalRouteBook.
func open_book(via_goal:=false) -> void:
	if via_goal:Tasks.bond_goal(app,"achao",2)
	else:app._resident_bond_menu("achao")
	await process_frame
	var button:=app.modal.find_child("AchaoGoalRouteBook" if via_goal else "AchaoRouteBook",true,false) as Button if is_instance_valid(app.modal) else null
	expect(button!=null,"Route book button is offered: "+("AchaoGoalRouteBook" if via_goal else "AchaoRouteBook"))
	if button!=null:button.pressed.emit()
	await process_frame

## Every original sign key has its own button; selecting one rewrites AchaoRouteHint without touching progress.
func check_site_buttons(tag:String) -> void:
	var hints:={}
	var marks_before:=int(app.session.snapshot.own_achao_route_marks)
	for site:String in Goals.ROUTE_SIGNS:
		var button:=app.modal.find_child("AchaoRouteSite_"+site,true,false) as Button if is_instance_valid(app.modal) else null
		expect(button!=null,"Site button exists for %s (%s)"%[site,tag])
		if button==null:continue
		button.pressed.emit()
		await process_frame
		var text:=hint_text()
		hints[site]=text
		expect(text==Goals.ROUTE_SIGNS[site].hint,"Hint follows the selected landmark %s (%s)"%[site,tag])
		expect(button.button_pressed,"Selected landmark stays highlighted (%s)"%site)
	var distinct:={}
	for text in hints.values():distinct[text]=true
	expect(distinct.size()==Goals.ROUTE_SIGNS.size(),"Each site button shows a different hint (%s)"%tag)
	expect(int(app.session.snapshot.own_achao_route_marks)==marks_before,"Selecting a site never changes progress (%s)"%tag)

func check_local_chart(done:bool,tag:String) -> void:
	expect(shown("AchaoLocalChart")!=null,"Local schematic is shown (%s)"%tag)
	if done:
		expect(shown("AchaoRegionMapTab")!=null and shown("AchaoLocalMapTab")!=null,"Both map tabs are offered once complete (%s)"%tag)
	else:
		expect(shown("AchaoChart")==null and shown("AchaoRegionMapTab")==null,"Region map stays locked before completion (%s)"%tag)

func check_tab_switch(tag:String) -> void:
	var region_tab:=shown("AchaoRegionMapTab") as Button
	var local_tab:=shown("AchaoLocalMapTab") as Button
	expect(region_tab!=null and local_tab!=null,"Both tabs exist ("+tag+")")
	if region_tab==null or local_tab==null:return
	region_tab.pressed.emit()
	await process_frame
	await process_frame
	expect(shown("AchaoChart")!=null and shown("AchaoLocalChart")==null,"Region tab shows the existing AchaoChart ("+tag+")")
	fits("AchaoChart",tag)
	await capture("achao-route-region-%s.png"%tag)
	local_tab.pressed.emit()
	await process_frame
	await process_frame
	expect(shown("AchaoLocalChart")!=null and shown("AchaoChart")==null,"Local tab returns to the schematic ("+tag+")")
	fits("AchaoLocalChart",tag)

func run() -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://achao-route-%d.json"%OS.get_process_id()
	if app.session.host(0,"航線旅人",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var man:Dictionary=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.dock_stage=1
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	man.bonds={"achao":{"points":6,"talk_day":-1,"gift_day":-1}}
	for site:String in Goals.ROUTE_SIGNS:
		var at:=World.achao_route_cell(site)
		man.x=at.x+0.5
		man.y=at.y+0.5
		app.session._send_snapshot(1)
		app._interact()
		await process_frame
		var marker:=app.modal.find_child("AchaoRouteMarker",true,false) as Button if is_instance_valid(app.modal) else null
		expect(marker!=null,"The ordinary site page has a marker: "+site)
		if marker!=null:marker.pressed.emit()
		await process_frame
		expect((int(app.session.snapshot.own_achao_route_marks)&int(Goals.ROUTE_SIGNS[site].bit))!=0,"Marks are synced for "+site)
		expect(not world.act(token,"repeat-"+site,Goals.ROUTE_ACTION,at,site).ok,"One sign counts only once")
		# Private progress: the book reflects only this player's marks so far.
		var achao_now:Vector2i=World.bond_place(world.state,"achao")[1]
		man.x=achao_now.x+0.5
		man.y=achao_now.y+0.5
		app.session._send_snapshot(1)
		await open_book()
		check_local_chart(false,"after "+site)
		var expected:=int(app.session.snapshot.own_achao_route_marks)
		expected=expected&int(Goals.ROUTE_MASK)
		expect(expected==int(man.get(Goals.ROUTE_KEY,0)),"Snapshot marks match this player's private record after "+site)
		app._close_modal()
		await process_frame
	var achao:Vector2i=World.bond_place(world.state,"achao")[1]
	man.x=achao.x+0.5
	man.y=achao.y+0.5
	# Before completion: all three marked, goal not yet reported.
	await open_book()
	check_local_chart(false,"before-report")
	await check_site_buttons("before-report")
	fits("AchaoLocalChart","before-report")
	await capture("achao-route-local-before.png")
	var report:=shown("AchaoRouteReport") as Button
	expect(report!=null,"The completed local map offers a return to Achao's report")
	if report!=null:report.pressed.emit()
	await process_frame
	app.session.rates[1].clear()
	var finish:=shown("BondGoalDo") as Button
	expect(finish!=null and not finish.disabled,"Achao accepts the three marks on the ordinary goal page")
	if finish!=null and not finish.disabled:finish.pressed.emit()
	await process_frame
	expect(app.session.snapshot.resident_goals.achao["2"].state=="done","Report all three landmarks")
	await open_book()
	check_local_chart(true,"done")
	await check_site_buttons("done")
	await capture("achao-route-local-done.png")
	await check_tab_switch("done")
	app._close_modal()
	await process_frame
	await open_book(true)
	check_local_chart(true,"goal-button")
	await check_site_buttons("goal-button")
	await check_tab_switch("goal-button")
	# Max text: the schematic, hint and tabs must stay inside the scroll area.
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	await process_frame
	expect(app.font_scale_factor()>=1.2,"Max text is active")
	for resolution in [Vector2i(1280,800),Vector2i(1024,640)]:
		root.size=resolution
		await process_frame
		var tag:="max-%dx%d"%[resolution.x,resolution.y]
		check_local_chart(true,tag)
		fits("AchaoLocalChart",tag)
		await check_site_buttons(tag)
		await capture("achao-route-local-%s.png"%tag)
		await check_tab_switch(tag)
	app.sound.preferred_text_scale=1
	app._apply_font_scale_tree()
	root.size=Vector2i(1280,800)
	app._close_modal()
	await process_frame
	await open_book()
	await process_frame
	var title_found:=false
	for label in app.modal.find_children("*","Label",true,false):
		if label.text=="阿潮的手繪群島地圖":title_found=true
	expect(title_found,"Unlocked view shows Achao's map")
	for resolution in [Vector2i(1280,800),Vector2i(1024,640)]:
		root.size=resolution
		await process_frame
		await process_frame
		# The region map is now behind its tab; the existing AchaoChart must still fit the whole map.
		var region_tab:=app.modal.find_child("AchaoRegionMapTab",true,false) as Button
		if region_tab!=null:region_tab.pressed.emit()
		await process_frame
		var map:=app.modal.find_child("AchaoChart",true,false) as Control
		var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		expect(map!=null and scroll!=null and scroll.get_global_rect().encloses(map.get_global_rect()),"Whole travel map fits at "+str(resolution))
		await capture("achao-route-map-%dx%d.png"%[resolution.x,resolution.y])
		var local_tab:=app.modal.find_child("AchaoLocalMapTab",true,false) as Button
		if local_tab!=null:local_tab.pressed.emit()
		await process_frame
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and int(loaded.state.players[token].get(Goals.ROUTE_KEY,0))==Goals.ROUTE_MASK,"All three marks survive a reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_ROUTE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
