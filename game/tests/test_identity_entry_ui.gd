extends SceneTree

const Main=preload("res://scripts/main.gd")
const Entry=preload("res://scripts/identity_entry.gd")
class RefreshProbe extends "res://scripts/identity_entry.gd":
	var reply:Dictionary={}
	var requests:=0
	func request(route:String,_body:Dictionary,_bearer:="") -> Dictionary:
		if route=="/v1/refresh":requests+=1
		return reply
var failures:=0
var checks:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool, description:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr(description)

func has_button_text(node:Node,wanted:String) -> bool:
	if node is Button and (node as Button).text==wanted:return true
	for child in node.get_children():
		if has_button_text(child,wanted):return true
	return false

func run() -> void:
	var app:=Main.new()
	app.village_art_preview=true
	root.add_child(app)
	var badge:Label=app.menu.find_child("TitleBuild",true,false)
	var release:=app._release_metadata()
	check(is_instance_valid(badge) and badge.text=="版本 %s r%d"%[release.version,int(release.build)],
		"Title shows the version and the installer build")
	check(app._release_version()==release.version and app._release_update_version()!=release.version,
		"The visible version keeps its label while update comparison includes the build")
	app._open_identity()
	var entry:Control=app.identity_entry
	check(entry.login_page.visible and not entry.world_page.visible,"Starts at identity")
	check(entry.credential.secret and entry.invite.secret,"Sensitive entries masked")
	entry.api.text="http://example.test"
	entry.login()
	check(entry.status.text.contains("HTTPS") and not entry.busy,"Insecure API rejected")
	check(Entry.endpoint("https://example.test","https","http",false),"HTTPS accepted")
	check(not Entry.endpoint("https://user@example.test","https","http",false),"Userinfo rejected")
	check(not Entry.endpoint("https://example.test\n","https","http",false),"Control characters rejected")
	check(not Entry.valid_token("abc\r\n"),"Credential headers reject control characters")
	check(not Entry.endpoint("http://127.0.0.1:4000","https","http",false),"Loopback explicit only")
	check(Entry.endpoint("http://127.0.0.1:4000","https","http",true),"Loopback opt-in")
	check(not Entry.endpoint("ws://127.0.0.1.example:4000","wss","ws",true),"Non-loopback rejected")
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		await process_frame
		await process_frame
		var panel:Control=entry.get_child(0)
		check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(panel.get_global_rect()),"Identity panel fits %s" % extent)
	entry.token="fixture"
	entry.reset_identity()
	check(entry.token.is_empty(),"Reset clears session")
	entry.joining=true
	app._disconnected()
	check(not entry.joining and entry.status.text.contains("無法連上"),"Transport failure returns to retryable state")
	entry.back()
	check(not entry.visible and app.menu.visible,"Back preserves local menu")
	var listed:={"world_id":"garden","name":"測試島","status":"online","protocol":Main.Session.PROTOCOL,
		"mode":"生活","online":1,"capacity":4,"members_count":2,"role":"owner","members":[{"name":"阿糰","role":"owner","online":true}]}
	entry.show_world(listed,"")
	check(entry.chosen_world.get("world_id")=="garden" and entry.world_detail.get_child_count()==1,"Postcard displays selected world")
	check(entry.world_state(listed)=="可加入","Available matching world can join")
	listed.protocol=-1
	check(entry.world_state(listed)=="需要更新","Incompatible protocol disabled")
	ProjectSettings.set_setting("application/config/update_url","http://updates.example.test/game")
	check(entry.configured_update_url().is_empty(),"Update destination requires HTTPS")
	ProjectSettings.set_setting("application/config/update_url","https://updates.example.test/game")
	check(entry.configured_update_url()=="https://updates.example.test/game","HTTPS update destination accepted")
	entry.chosen_world=listed
	entry.joining=true
	entry.join_result(false,"遊戲版本過舊或不相容，請更新遊戲後再加入。","VERSION_MISMATCH")
	check(is_instance_valid(entry.update_dialog) and entry.update_dialog.visible,"Protocol rejection opens update prompt")
	check(has_button_text(entry.update_dialog,"前往下載新版"),"Configured update page is offered")
	if is_instance_valid(entry.update_dialog):entry.update_dialog.queue_free();entry.update_dialog=null
	app.session.receive_notice("房間密碼不正確，無法加入。",false)
	check(not is_instance_valid(app.room_update_dialog),"Wrong room password does not suggest an update")
	app.session.receive_notice(Main.Session.VERSION_MISMATCH_NOTICE,false)
	check(is_instance_valid(app.room_update_dialog) and has_button_text(app.room_update_dialog,"前往下載新版"),
		"Direct room protocol rejection uses the same update prompt")
	var room_prompt:Control=app.room_update_dialog
	app.session.receive_notice(Main.Session.VERSION_MISMATCH_NOTICE,false)
	check(app.room_update_dialog==room_prompt,"Repeated room rejection keeps one prompt")
	app._disconnected()
	check(is_instance_valid(room_prompt) and room_prompt.is_visible_in_tree(),"Disconnect does not erase the reason")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("TUAN_UPDATE_CAPTURE").is_empty():
		root.size=Vector2i(1024,640)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_environment("TUAN_UPDATE_CAPTURE"))==OK,"Capture room update prompt")
	for control in room_prompt.find_children("*","Button",true,false):
		if control.text=="稍後再說":control.pressed.emit()
	await process_frame
	check(not is_instance_valid(app.room_update_dialog) and app.menu.visible,"Dismiss returns to the title")
	listed.status="offline"
	check(entry.world_state(listed)=="世界離線","Offline world disabled")
	listed.status="online"
	listed.protocol=Main.Session.PROTOCOL
	listed.online=4
	check(entry.world_state(listed)=="島上已滿","Full world disabled")
	entry.show_world_tab(true)
	check(entry.invitation_view.visible and not entry.worlds_view.visible and entry.chosen_world.is_empty(),"Invite tab clears selected world")
	var probe:=RefreshProbe.new()
	app.menu.add_child(probe)
	probe.setup(app)
	probe.hide()
	probe.token="fixture"
	probe.refresh_remaining=1.0
	probe.busy=true
	probe._process(2.0)
	check(probe.requests==0,"Refresh waits while busy")
	probe.busy=false
	probe.joining=true
	probe._process(0.0)
	check(probe.requests==0,"Refresh waits while joining")
	probe.joining=false
	probe.reply={"session":"fixture","expires":2000000000}
	probe._process(0.0)
	check(probe.requests==1 and probe.expires==2000000000.0 and probe.refresh_remaining==300.0 and not probe.greeting.tooltip_text.is_empty(),"Hidden menu refreshes and shows expiry")
	probe.reply={}
	probe._process(300.0)
	check(probe.requests==2 and probe.refresh_remaining==30.0 and probe.token=="fixture","Network failure retries without changing identity")
	probe.reply={"expired":true}
	probe._process(30.0)
	check(probe.requests==3 and probe.token.is_empty() and probe.expires==0.0 and probe.status.text.contains("到期"),"Unauthorized clears identity and asks for login")
	app.island_passport={"can_manage":true,"world_name":"測試島","members":[],"management_history":[
		{"action":"block","actor":"阿糰","target":"小栗","at":0}]}
	app._passport_menu()
	check(has_button_text(app.modal,"查看管理紀錄"),"Owner passport links to management history")
	app._passport_management_history()
	var labels:=app.modal.find_children("*","Label",true,false)
	check(labels.any(func(entry_label):return entry_label.text=="封鎖入島 · 小栗") and has_button_text(app.modal,"返回通行簿"),
		"History shows localized action, affected resident and back button")
	app.island_passport={"can_manage":false,"world_name":"測試島","members":[]}
	app._passport_menu()
	check(not has_button_text(app.modal,"查看管理紀錄"),"Member passport hides management history")
	app.island_passport.members=[{"name":"小栗","role":"member","management_id":"fixture","public_builder":false}]
	app._passport_menu()
	check(has_button_text(app.modal,"授予渡口公共地塊施工權"),"Manager sees the public construction grant")
	app.island_passport.members[0].public_builder=true
	app._passport_menu()
	check(has_button_text(app.modal,"收回渡口公共地塊施工權"),"Manager sees the revoke action after granting access")
	app.queue_free()
	await process_frame
	print("IDENTITY_ENTRY_UI_TEST checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

