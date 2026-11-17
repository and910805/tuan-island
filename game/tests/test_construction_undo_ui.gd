extends SceneTree
# Construction-undo entry in the EXISTING build menu (village_art_preview and legacy).
#
# PART A — STUB FIXTURE (always runs). Real main.tscn, real build menu, real
#   Esc/_input path, but session.snapshot is a hand-written fixture and
#   session.perform is captured by StubSession (test-only subclass below); no
#   World is involved. Expiry uses a simulated local clock (base_ms shifted).
# PART B — REAL SESSION (required): hosts a local
#   session, builds a floor via Session.perform/World.act, undoes it from the
#   build menu and checks state, exact refund and retry after save failure.
#
# Optional native capture: --qa-output=<dir>
const World=preload("res://scripts/world.gd")
const UndoUI=preload("res://scripts/construction_undo_ui.gd")
const ME:="fixture-own-id"

class StubSession extends "res://scripts/session.gd":
	var calls:Array=[]
	func perform(action:String,p:Vector2i,extra:String="")->int:
		calls.append([action,p,extra])
		return calls.size()
	func input_direction(_d:Vector2)->void:pass

var app
var stub:StubSession
var checks:=0
var failures:=0
var output:=""

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+message)

func record(id:String,label:String="放置地板",seconds:float=30.0,available:bool=true,reason:String="",region:String="home")->Dictionary:
	return {"id":id,"label":label,"available":available,"reason":reason,"seconds_left":seconds,"region":region}

func set_snapshot(summary:Variant,region:String="home")->void:
	var snap:={"region_id":region,"time":0,"objects":{},"mine_depths":{"unlocked":1},
		"players":{ME:{"x":20.5,"y":21.5,"coins":0,"inventory":{"wood":10,"fiber":4},"stories":{}}}}
	if typeof(summary)!=TYPE_NIL:snap["own_construction_undo"]=summary
	stub.snapshot=snap
	app.undo_ui.observe(snap)
	app.undo_ui.refresh()

func node(name:String)->Control:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func press(name:String)->void:
	var b:=node(name) as Button
	check(b!=null,"button "+name+" exists")
	if b:b.pressed.emit()

func esc()->void:
	var key:=InputEventKey.new()
	key.keycode=KEY_ESCAPE;key.physical_keycode=KEY_ESCAPE;key.pressed=true
	app._input(key)

func settle()->void:
	for i in 4:await process_frame
	if app.village_art_preview:app._layout_preview()
	await process_frame

func shot(name:String)->void:
	if output.is_empty():return
	app.toast.hide()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"capture "+name)

func strip_open()->bool:
	var bar:=node("UndoConfirmBar")
	return bar!=null and bar.is_visible_in_tree()

func layout(tag:String,expect_strip:bool)->void:
	var view:Rect2=app.get_viewport().get_visible_rect()
	check(app.modal!=null,tag+": build menu open")
	if app.modal==null:return
	var bounds:Rect2=app.modal.get_global_rect()
	check(view.encloses(bounds),tag+": build menu fits viewport %s in %s"%[bounds,view])
	var names:=["UndoConstruction","UndoStatus"]
	if expect_strip:names+=["UndoConfirm","UndoCancel","UndoConfirmText"]
	for name in names:
		var c:=node(name)
		check(c!=null and c.is_visible_in_tree(),tag+": "+name+" visible")
		if c:check(view.encloses(c.get_global_rect()) and bounds.grow(1).encloses(c.get_global_rect()),tag+": "+name+" inside menu and viewport")
	var entry:=node("UndoConstruction")
	if entry:check(entry.size.y<=52 and entry.size.x<=200,tag+": entry stays compact %s"%entry.size)
	var bar:=node("UndoConfirmBar")
	if bar and expect_strip:check(bar.size.y<=96,tag+": confirm strip compact %s"%bar.size)
	if app.village_art_preview and entry:
		check(entry.get_parent()==node("HouseCheck").get_parent(),tag+": entry lives in the existing catalog tab bar")
		var status:=node("UndoStatus") as Label
		check(status.get_parent()==node("BuildStyles") and status.global_position.y>=entry.get_global_rect().end.y,
			tag+": status has its own row below the entry")
		check(status.get_visible_line_count()==status.get_line_count(),tag+": full undo status is visible")

func open_menu()->void:
	app._build_menu()
	app.undo_ui.refresh()
	await settle()

func stub_suite(tag:String)->void:
	stub.calls.clear()
	# --- absent / malformed data => disabled, no history ---------------------
	set_snapshot(null)
	await open_menu()
	var modal_before=app.modal
	var entry:=node("UndoConstruction") as Button
	var status:=node("UndoStatus") as Label
	check(entry!=null and status!=null,tag+": entry and status exist in build menu")
	if entry==null or status==null:
		app._close_modal()
		return
	check(entry.disabled,tag+": absent data disables entry")
	check(status.text==UndoUI.TEXT_NONE,tag+": absent data says no history")
	press("UndoConstruction")
	check(not strip_open() and stub.calls.is_empty(),tag+": disabled entry opens nothing")
	set_snapshot({"id":"x".repeat(40),"label":"太長","available":true,"seconds_left":20,"region":"home"})
	check(entry.disabled,tag+": over-long id treated as absent")
	set_snapshot({"label":"沒有編號","available":true,"seconds_left":20})
	check(entry.disabled,tag+": missing id treated as absent")
	# --- available record: clear label + countdown ----------------------------
	set_snapshot(record("rec-a","放置木牆",30.0))
	check(not entry.disabled,tag+": available record enables entry")
	check(status.text.contains("放置木牆") and status.text.contains("剩 30 秒"),tag+": status shows last action and 30s: "+status.text)
	await settle()
	layout(tag+" idle",false)
	await shot(tag+"-idle")
	# --- region mismatch / unavailable reason ---------------------------------
	set_snapshot(record("rec-a","放置木牆",30.0,true,"","lanyang"))
	check(entry.disabled and status.text.contains(UndoUI.TEXT_REGION),tag+": other region disables")
	set_snapshot(record("rec-a","放置木牆",30.0,false,"施工後這裡已有其他變動，無法復原"))
	check(entry.disabled and status.text.contains("已有其他變動"),tag+": server reason shown: "+status.text)
	if app.village_art_preview:
		await settle()
		check(status.get_visible_line_count()==status.get_line_count(),tag+": unavailable reason fits its row")
	# --- open confirmation inside the same menu; Cancel => nothing -----------
	set_snapshot(record("rec-a","放置木牆",30.0))
	press("UndoConstruction")
	await settle()
	check(app.modal==modal_before,tag+": confirmation is inline, not a new menu")
	check(strip_open(),tag+": confirmation strip shown")
	check(root.gui_get_focus_owner()==node("UndoCancel"),tag+": confirmation starts on safe cancel action")
	check(str(app.undo_ui.shown.get("id",""))=="rec-a",tag+": shown id stored on confirmation")
	check((node("UndoConfirmText") as Label).text.contains("放置木牆"),tag+": confirmation names the action")
	layout(tag+" confirm",true)
	await shot(tag+"-confirm")
	press("UndoCancel")
	await settle()
	check(not strip_open() and stub.calls.is_empty() and app.modal==modal_before,tag+": cancel sends nothing, menu stays")
	check(root.gui_get_focus_owner()==entry,tag+": cancel restores keyboard focus to undo entry")
	# --- Esc: first closes strip only, second closes menu (existing path) -----
	press("UndoConstruction")
	check(strip_open(),tag+": reopened strip")
	esc()
	await settle()
	check(not strip_open() and app.modal==modal_before and stub.calls.is_empty(),tag+": Esc cancels confirmation only")
	check(root.gui_get_focus_owner()==entry,tag+": Esc restores keyboard focus to undo entry")
	esc()
	await settle()
	check(app.modal==null and stub.calls.is_empty(),tag+": second Esc closes build menu, nothing sent")
	# --- record changed while open => re-quote, no silent submit -------------
	set_snapshot(record("rec-a","放置木牆",30.0))
	await open_menu()
	entry=node("UndoConstruction") as Button
	status=node("UndoStatus") as Label
	check(entry!=null and status!=null,tag+": reopened menu has entry")
	if entry==null or status==null:
		app._close_modal()
		return
	press("UndoConstruction")
	stub.snapshot["own_construction_undo"]=record("rec-b","放置木門",30.0)
	app.undo_ui.observe(stub.snapshot)
	press("UndoConfirm")   # pressed before any refresh tick saw the change
	check(stub.calls.is_empty(),tag+": changed record not submitted")
	check(strip_open() and str(app.undo_ui.shown.get("id",""))=="rec-b",tag+": confirmation re-quoted to new record")
	check((node("UndoConfirmText") as Label).text.contains("請再確認") and (node("UndoConfirmText") as Label).text.contains("放置木門"),tag+": re-quote is visible")
	# --- dispatch exactly once with actor tile and shown id -------------------
	press("UndoConfirm")
	check(stub.calls.size()==1,tag+": confirm dispatches once")
	if stub.calls.size()>=1:
		check(stub.calls[0]==["undo_build",Vector2i(20,21),"rec-b"],tag+": perform('undo_build', own tile, id) %s"%[stub.calls[0]])
	press("UndoConfirm")
	app.undo_ui.confirm()
	press("UndoConstruction")
	press("UndoConfirm")
	check(stub.calls.size()==1,tag+": repeated presses do not resend")
	check(entry.disabled and status.text.contains(UndoUI.TEXT_SENT),tag+": entry shows sent state")
	# --- becomes unavailable while open => disables, never sends -------------
	set_snapshot(record("rec-c","拆除椅子",30.0))
	press("UndoConstruction")
	set_snapshot(record("rec-c","拆除椅子",28.0,false,"背包材料不足，無法復原"))
	check((node("UndoConfirm") as Button).disabled,tag+": confirm disabled when record becomes unavailable")
	check((node("UndoConfirmText") as Label).text.contains("背包材料不足"),tag+": reason shown in confirmation")
	press("UndoConfirm")
	check(stub.calls.size()==1,tag+": unavailable record not sent")
	# Record disappears entirely while open.
	set_snapshot(record("rec-d","放置地板",30.0))
	app.undo_ui.cancel_confirmation()
	press("UndoConstruction")
	set_snapshot(null)
	check((node("UndoConfirm") as Button).disabled,tag+": confirm disabled when history vanishes")
	press("UndoConfirm")
	check(stub.calls.size()==1,tag+": vanished record not sent")
	app.undo_ui.cancel_confirmation()
	# --- countdown & expiry (simulated local elapsed) -------------------------
	set_snapshot(record("rec-e","放置地板",30.0))
	app.undo_ui.base_ms-=10500
	app.undo_ui.refresh()
	check(status.text.contains("剩 20 秒"),tag+": countdown uses local elapsed: "+status.text)
	stub.snapshot["own_construction_undo"]=record("rec-e","放置地板",25.0)
	app.undo_ui.observe(stub.snapshot);app.undo_ui.refresh()
	check(status.text.contains("剩 25 秒"),tag+": new snapshot seconds rebase countdown")
	press("UndoConstruction")
	app.undo_ui.base_ms-=26000
	app.undo_ui.refresh()
	check(entry.disabled and status.text.contains(UndoUI.TEXT_EXPIRED),tag+": expired disables entry")
	check((node("UndoConfirm") as Button).disabled,tag+": expired disables open confirmation")
	press("UndoConfirm")
	check(stub.calls.size()==1,tag+": expired record not sent")
	# --- refresh never adds widgets -------------------------------------------
	var count:int=app.modal.find_children("*","",true,false).size()
	for i in 25:app.undo_ui.refresh()
	check(app.modal.find_children("*","",true,false).size()==count,tag+": refresh creates no nodes")
	app._close_modal()
	await settle()
	app.undo_ui.refresh()
	check(app.undo_ui.entry==null,tag+": closing menu detaches entry")

func make_app(preview:bool)->void:
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=preview
	root.add_child(app)
	app.set_process(false)
	await process_frame

func drop_app()->void:
	if app:
		app.session.set_physics_process(false)
		app.queue_free()
		await process_frame
	app=null

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="):output=arg.trim_prefix("--qa-output=")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	var scale_mode:=root.content_scale_mode
	# Legacy first: preview disables content scaling on the shared window.
	for preview in [false,true]:
		for size in [Vector2i(1024,640),Vector2i(1280,800)]:
			root.content_scale_mode=scale_mode
			root.size=size
			await make_app(preview)
			var real_session=app.session
			stub=StubSession.new()
			stub.own_id=ME
			app.session=stub
			app.playing=true
			app.menu.hide()
			app.hud.show()
			await stub_suite("%s-%dx%d"%["preview" if preview else "legacy",size.x,size.y])
			app.session=real_session
			app.playing=false
			stub.free()
			await drop_app()
	root.content_scale_mode=scale_mode
	root.size=Vector2i(1024,640)
	await make_app(true)
	var real_session=app.session
	stub=StubSession.new()
	stub.own_id=ME
	app.session=stub
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	await stub_suite("preview-1024x640-extra-large")
	app.session=real_session
	app.playing=false
	stub.free()
	await drop_app()
	await real_suite()
	print("CONSTRUCTION_UNDO_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------------------
# PART B — real Session/World (only when core exposes undo_summary)
# ---------------------------------------------------------------------------
func real_suite()->void:
	var probe=World.new()
	var core_ready:bool=probe.has_method("undo_summary")
	probe=null
	if not core_ready:
		check(false,"required real-session undo API missing")
		return
	root.size=Vector2i(1280,800)
	await make_app(true)
	var path:=OS.get_environment("TEMP").path_join("undo-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	check(app.session.host(0,"復原試作",path)==OK,"real: local session host")
	app.session.set_physics_process(false)
	var world=app.session.world
	var actor:String=app.session.peers[1]
	var site:=Vector2i(-1,-1)
	for y in range(18,50):
		for x in range(14,64):
			var ok:=true
			for d in [Vector2i.ZERO,Vector2i(1,0)]:
				var p:Vector2i=Vector2i(x,y)+d
				if world.blocked(p) or world.protected(p) or world.resource(p)!="" or world.state.ground.has(World.key(p)) or world.state.objects.has(World.key(p)):ok=false
			if ok:site=Vector2i(x,y);break
		if site.x>=0:break
	check(site.x>=0,"real: clear fixture site")
	world.state.players[actor].x=site.x+0.5
	world.state.players[actor].y=site.y+0.5
	world.state.players[actor].inventory.wood=100
	var tile:=site+Vector2i(1,0)
	app.session._send_snapshot(1)
	app._perform_build_action("build",tile,"floor")
	app.session._send_snapshot(1)
	await process_frame
	check(world.state.ground.has(World.key(tile)),"real: floor built")
	var wood_after_build:=int(world.state.players[actor].inventory.wood)
	var summary:=UndoUI.normalize(app.session.snapshot.get("own_construction_undo"))
	check(not summary.is_empty() and summary.available,"real: snapshot offers undo %s"%[summary])
	await open_menu()
	layout("real",false)
	press("UndoConstruction")
	await settle()
	layout("real confirm",true)
	await shot("real-confirm")
	press("UndoConfirm")
	app.session._send_snapshot(1)
	await settle()
	check(not world.state.ground.has(World.key(tile)),"real: server undo removed the floor")
	check(int(world.state.players[actor].inventory.wood)==wood_after_build+int(World.BUILD.floor.wood),"real: exact materials refunded")
	press("UndoConfirm")
	check(not world.state.ground.has(World.key(tile)),"real: no second undo effect")
	# A temporary save error returns an authoritative completion and releases
	# the same record for retry without waiting for a UI timeout.
	app._close_modal()
	app._perform_build_action("build",tile,"floor")
	app.session._send_snapshot(1)
	await open_menu()
	press("UndoConstruction")
	world.save_path=path+"/missing/world.json"
	press("UndoConfirm")
	await settle()
	check(world.state.ground.has(World.key(tile)),"real: save failure keeps construction")
	check(not (node("UndoConstruction") as Button).disabled,"real: server failure allows immediate retry")
	world.save_path=path
	press("UndoConstruction")
	press("UndoConfirm")
	await settle()
	check(not world.state.ground.has(World.key(tile)),"real: retry succeeds")
	check(int(world.state.players[actor].inventory.wood)==100,"real: failed attempt plus retry refunds exactly once")
	check(app.session.shutdown(),"real: session shutdown saves")
	await drop_app()
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
