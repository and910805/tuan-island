extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

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

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

## --size=WxH (default 1024x640); malformed or tiny values fall back to the default.
func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=640 and wanted.y>=480:return wanted
	return Vector2i(1024,640)

func capture_settled(file_name:String) -> void:
	for i in 3:await process_frame
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func has_node_named(id:String) -> bool:
	return is_instance_valid(app.modal) and app.modal.find_child(id,true,false)!=null

func modal_mentions(text:String) -> bool:
	if not is_instance_valid(app.modal):return false
	var pending:Array[Node]=[app.modal]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		if (node is Label or node is Button) and str(node.text).contains(text):return true
		pending.append_array(node.get_children())
	return false

func open_voyage() -> void:
	app._interact()
	await process_frame
	await press("AchaoVoyage")

func photograph(path:String,file:String) -> void:
	expect(app.voyage_photo.visible and not app.hud.visible,"Camera is offered while sailing")
	app.voyage_photo.pressed.emit()
	await RenderingServer.frame_post_draw
	await process_frame
	expect(FileAccess.file_exists(path),"Actual photo file was saved")
	if FileAccess.file_exists(path):
		var picture:=Image.load_from_file(path)
		expect(picture!=null and picture.get_size()==Vector2i(Vector2(root.get_texture().get_size())*0.65),"Photo frames the center of the sailing viewport")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and FileAccess.file_exists(path):
			expect(Image.load_from_file(path).save_png(arg.trim_prefix("--capture-dir=").path_join(file))==OK,"Keep photo evidence: "+file)

func run() -> void:
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var tag:="%dx%d"%[window_size().x,window_size().y]+("-large" if large_text else "")
	var path:="user://achao-photo-test-%d.json"%OS.get_process_id()
	app.session.profile.token="achao-photo-test-%d"%OS.get_process_id()
	if app.session.host(0,"拍照島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.dock_stage=2
	world.state[Goals.DOCK_LIGHT]=true
	person.bonds={"achao":{"points":24,"talk_day":-1,"gift_day":-1}}
	person[Goals.RECORD_KEY]={"achao":{"3":""}}
	person[Goals.VOYAGE_PAINT]=true
	var dock:=World.RESIDENT_BOND.dock_cell(world.state)
	stand(dock)
	expect(not world.act(token,"land-photo",Goals.VOYAGE_ACTION,dock,"photo").ok,"Onshore photos do not satisfy the quest")
	await open_voyage()
	await press("AchaoVoyage_depart")
	world.step(5.5,true)
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	var photo:=Tasks.achao_photo_path(app)
	await photograph(photo,"01-solo-with-achao.png")
	expect(person.get(Goals.VOYAGE_PHOTO,false),"The photo is recorded for this resident")
	app.voyage_return.pressed.emit()
	await process_frame
	expect(app.hud.visible and not app.voyage_photo.visible,"Returning restores the island HUD")
	await open_voyage()
	await press("AchaoVoyageAlbum")
	expect(app.modal.find_child("AchaoAlbumPhoto",true,false)!=null,"Album shows the captured frame")
	await capture_settled("03-voyage-album-%s.png"%tag)
	app._close_modal()
	await open_voyage()
	await press("AchaoVoyage_depart")
	var buddy:="photo-buddy"
	world.add_player(buddy,"朋友")
	var guest:Dictionary=world.state.players[buddy]
	guest.x=person.x
	guest.y=person.y
	guest.bonds={"achao":{"points":14,"talk_day":-1,"gift_day":-1}}
	guest.blue_outfit=true
	expect(world.act(buddy,"join","achao_voyage",dock,"join").ok,"A nearby friend can board by choice")
	var peer:=200
	app.session.peers[peer]=buddy
	var guest_id:=buddy.sha256_text().left(16)
	world.step(5.5,true)
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	var public_guest:Dictionary=app.session.snapshot.players[guest_id]
	expect(public_guest.get("voyage_captain")==app.session.own_id and not public_guest.has(Goals.VOYAGE_CAPTAIN),"Snapshots identify the shared boat without exposing the profile token")
	expect(not world.act(buddy,"guest-photo","achao_voyage",dock,"photo").ok and not guest.has(Goals.VOYAGE_PHOTO),"Participation does not give a guest the main player's quest credit")
	await photograph(photo,"02-with-guest.png")
	app.session.peers.erase(peer)
	app.voyage_return.pressed.emit()
	await process_frame
	expect(not guest.has(Goals.VOYAGE_START) and not guest.has(Goals.VOYAGE_CAPTAIN),"Captain's early return also lands their companion")
	Tasks.bond_goal(app,"achao",4)
	await process_frame
	await press("BondGoalDo")
	var keepsake:="keepsake_achao_oar"
	expect(int(person.inventory.get(Goals.keepsake_item(keepsake),0))==1,"Report awards one displayable wooden oar")
	var oar_key:String=Goals.keepsake_item(keepsake)
	# Finished goal: album entry -> photo, oar shortcut, back.
	Tasks.bond_goal(app,"achao",4)
	await process_frame
	expect(has_node_named("AchaoGoalAlbum") and not has_node_named("BondGoalDo"),"Completed goal offers the album")
	await capture_settled("04-goal-done-%s.png"%tag)
	await press("AchaoGoalAlbum")
	expect(has_node_named("AchaoAlbumPhoto"),"Goal album opens the same real photo")
	expect(has_node_named("AchaoAlbumOar") and has_node_named("AchaoAlbumBack"),"Album offers oar shortcut and back")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	expect(scroll!=null and not scroll.get_v_scroll_bar().visible,"Photo and oar preview fit together")
	await capture_settled("05-goal-album-%s.png"%tag)
	await press("AchaoAlbumBack")
	expect(has_node_named("AchaoGoalAlbum") and not has_node_named("AchaoAlbumPhoto"),"Back returns to the finished goal")
	await press("AchaoGoalAlbum")
	await press("AchaoAlbumOar")
	expect(not has_node_named("AchaoAlbumPhoto") and modal_mentions("紀念木槳"),"Oar shortcut opens the old keepsake")
	await capture_settled("06-album-oar-%s.png"%tag)
	expect(int(person.inventory.get(oar_key,0))==1,"Viewing the keepsake does not change the inventory")
	app._close_modal()
	# Missing local photo: still reachable, falls back to the oar.
	expect(FileAccess.file_exists(photo) and DirAccess.remove_absolute(photo)==OK,"Remove the local photo")
	Tasks.bond_goal(app,"achao",4)
	await process_frame
	await press("AchaoGoalAlbum")
	expect(not has_node_named("AchaoAlbumPhoto"),"No photo is shown when the local file is gone")
	expect(modal_mentions("紀念木槳") or has_node_named("AchaoAlbumOar"),"Missing photo still opens the oar")
	await capture_settled("07-missing-photo-oar-%s.png"%tag)
	app._close_modal()
	var spot:=Vector2i(38,33)
	stand(spot)
	expect(world.act(token,"display-oar","build",spot,keepsake).ok,"The oar can be placed as home decor")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(Goals.done(loaded.state.players[token],"achao").has(4) and loaded.state.objects.get(World.key(spot),{}).get("type")==keepsake,"Photo milestone and placed reward survive reload")
	for file:String in [path,path+".bak",path+".tmp",photo]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_PHOTO_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
