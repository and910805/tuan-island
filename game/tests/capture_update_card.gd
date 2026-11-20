extends SceneTree
const Checker=preload("res://scripts/version_update_checker.gd")
var checks:=0
var failures:=0
var app
func _initialize()->void:run.call_deferred()
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func press(key:Key)->void:
	var input:=InputEventKey.new()
	input.keycode=key
	input.physical_keycode=key
	input.pressed=true
	root.push_input(input)
	input=input.duplicate()
	input.pressed=false
	root.push_input(input)

func joy(button:JoyButton)->void:
	var input:=InputEventJoypadButton.new()
	input.button_index=button
	input.pressed=true
	root.push_input(input)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	var directory:String=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	# Explicit external fixture path; no network, user world or actual download.
	var manifest:=FileAccess.get_file_as_bytes(app.arg_value("qa-manifest",""))
	var key:=Checker.installed_public_key()
	var optional:=Checker.verify_manifest(manifest,key,"0.50.22-dev")
	var required:=Checker.verify_manifest(manifest,key,"0.50.20-dev")
	assert(not optional.is_empty() and required.get("required",false))
	var solo:Button=app.menu.find_child("TitleSolo",true,false)
	solo.grab_focus()
	app._show_version_update(optional)
	await process_frame
	var initial_overlay:Control=app.version_update_dialog
	var toggle_button:Button=initial_overlay.find_child("UpdateMethodsToggle",true,false)
	var methods:Control=initial_overlay.find_child("UpdateManualMethods",true,false)
	var nav:=preload("res://scripts/update_card.gd")
	expect(root.gui_get_focus_owner()==nav.find_button(initial_overlay,"在遊戲內下載"),"Main action receives initial focus")
	press(KEY_TAB)
	expect(root.gui_get_focus_owner()==toggle_button,"Keyboard Tab reaches other methods")
	joy(JOY_BUTTON_A)
	expect(methods.visible,"Controller A opens the focused disclosure")
	joy(JOY_BUTTON_DPAD_DOWN)
	joy(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner()==nav.find_button(initial_overlay,"前往下載新版"),"Controller visits manual download after footer")
	joy(JOY_BUTTON_B)
	expect(not methods.visible and root.gui_get_focus_owner()==toggle_button,"Controller Back collapses disclosure and restores toggle focus")
	var dismiss:=nav.find_button(initial_overlay,"稍後再說")
	dismiss.disabled=true
	press(KEY_ESCAPE)
	expect(app.version_update_dialog==initial_overlay,"Cancel cannot dismiss during active transfer")
	dismiss.disabled=false
	app.playing=true
	expect(not app._world_keyboard_allowed() and not app._world_pointer_allowed(Vector2(500,400)),"Open card blocks world keyboard and pointer operations")
	app.playing=false
	app.controller_sticks[0]=Vector2.RIGHT
	var release_stick:=InputEventJoypadMotion.new()
	release_stick.axis=JOY_AXIS_LEFT_X
	release_stick.axis_value=0.0
	root.push_input(release_stick)
	expect(app.controller_sticks[0]==Vector2.ZERO,"Stick release under the card cannot leave movement latched")
	press(KEY_ESCAPE)
	expect(app.version_update_dialog==null and root.gui_get_focus_owner()==solo,"Closing restores the previously focused main menu control")
	await process_frame
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		for scale in 4:
			app.sound.preferred_text_scale=scale
			app.sound.reduced_motion=scale%2==0
			for must_update in [false,true]:
				app._show_version_update(required if must_update else optional)
				expect(app.version_update_dialog.modulate.a==1.0 if app.sound.reduced_motion else app.version_update_dialog.modulate.a==0.0,"Opening fade respects reduced motion")
				await process_frame
				await process_frame
				await create_timer(0.16).timeout
				var overlay:Control=app.version_update_dialog
				var panel:Control=overlay.find_child("VersionUpdatePanel",true,false)
				var toggle:Button=overlay.find_child("UpdateMethodsToggle",true,false)
				var manual:Control=overlay.find_child("UpdateManualMethods",true,false)
				var snapshot:Dictionary=app.session.snapshot.duplicate(true)
				for expanded in [false,true]:
					if expanded:toggle.pressed.emit()
					await process_frame
					await RenderingServer.frame_post_draw
					expect(manual.visible==expanded,"Disclosure only opens when requested")
					var bounds:=Rect2(Vector2.ZERO,Vector2(size))
					expect(bounds.encloses(panel.get_global_rect()),"Pixel update card fits viewport at all text sizes")
					for button:Button in overlay.find_children("*","Button",true,false):
						if not button.is_visible_in_tree():continue
						expect(panel.get_global_rect().encloses(button.get_global_rect()),"Every visible update action remains in the card: "+button.text)
						expect(button.size.y>=42 and button.size.x>=button.get_combined_minimum_size().x,"Buttons remain readable and usable: "+button.text)
						expect(app.session.snapshot==snapshot and app.session.world==null,"Opening manual methods cannot mutate or start a world")
					if scale==1 and not must_update:
						root.get_texture().get_image().save_png(directory.path_join("%d_%s.png"%[size.x,"manual" if expanded else "card"]))
				var fetch:=preload("res://scripts/update_card.gd").find_button(overlay,"在遊戲內下載")
				var progress:ProgressBar=overlay.find_child("UpdateDownloadProgress",true,false)
				for node in overlay.get_children():
					if node.has_signal("transfer_progress"):node.emit_signal("transfer_progress",37)
				expect(progress.visible and progress.value==37,"Progress display follows the real transfer progress signal")
				var launch:=preload("res://scripts/update_card.gd").find_button(overlay,"啟動新版")
				launch.show() # Presentation transition only; never launch unverified code.
				expect(not fetch.visible and launch.visible,"Verified-stage presentation offers only one main action")
				expect(root.gui_get_focus_owner()==launch,"Prepared action receives focus after download button disappears")
				var status:Label=overlay.find_child("UpdateArchiveStatus",true,false)
				status.text="驗證失敗，請從下載頁重新取得完整封包。原版本與既有存檔仍然保留，可以稍後再更新。"
				await process_frame
				await process_frame
				expect(status.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(size)).encloses(panel.get_global_rect()),"Failure feedback stays visible without pushing the card off screen")
				overlay.queue_free()
				app.version_update_dialog=null
				await process_frame
	app.queue_free()
	await process_frame
	print("UPDATE_CARD_CAPTURE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
