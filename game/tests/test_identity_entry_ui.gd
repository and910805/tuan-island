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
	app.queue_free()
	await process_frame
	print("IDENTITY_ENTRY_UI_TEST checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

