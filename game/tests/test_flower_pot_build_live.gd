extends SceneTree
## Use a seeded pot to exercise the build folio and the normal world click.
const World=preload("res://scripts/world.gd")
const Opening=preload("res://scripts/wangan_opening_ui.gd")
const TOKEN:="flower-pot-build-live"
const TILE:=Vector2i(41,35)
var app
var failures:=0
var output:=OS.get_environment("FLOWER_POT_QA_OUTPUT")

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->bool:
	if not ok:
		failures+=1
		push_error(message)
	return ok

func settle()->void:
	await create_timer(0.3).timeout
	await process_frame
	await process_frame

func capture(name:String)->void:
	if output.is_empty():return
	RenderingServer.force_draw()
	expect(root.get_texture().get_image().save_png(output.path_join(name))==OK,"save "+name)

func tap(button:JoyButton)->void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=button
		event.pressed=pressed
		root.push_input(event)
	await process_frame

func run()->void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":TOKEN}
	var world:=World.new()
	world.save_path="user://flower-pot-build-live-%d.json"%OS.get_process_id()
	world.add_player(TOKEN,"陶盆測試員")
	world.state.players[TOKEN].inventory.flower_pot=1
	var controller:bool="--qa-controller" in OS.get_cmdline_user_args()
	if controller:
		var person:Dictionary=world.state.players[TOKEN]
		person.x=40.5
		person.y=34.5
		root.size=Vector2i(1024,640)
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
	session.world=world
	session._attach_registered(1,TOKEN)
	await settle()
	if Opening.card_open(app):Opening.dismiss(app)
	if controller:await tap(JOY_BUTTON_Y)
	else:app._build_menu()
	await settle()
	var slot:=app.modal.find_child("BuildSlot_flower_pot_0",true,false) as Button
	if expect(slot!=null and not slot.disabled,"flower pot is selectable in the build folio"):
		var scroller:=slot.get_parent()
		while scroller!=null:
			if scroller is ScrollContainer:scroller.ensure_control_visible(slot)
			scroller=scroller.get_parent()
		if controller:
			slot.grab_focus()
			await tap(JOY_BUTTON_A)
		else:slot.pressed.emit()
		await settle()
		await capture("01-catalog.png")
		var choose:=app.modal.find_child("BuildPlace",true,false) as Button
		if expect(choose!=null and not choose.disabled,"choose flower pot"):
			if controller:
				await tap(JOY_BUTTON_Y)
				expect(root.gui_get_focus_owner()==choose,"Y jumps to the placement action")
				await tap(JOY_BUTTON_A)
			else:choose.pressed.emit()
			await settle()
			if controller:
				expect(app.modal==null and app.controller_aim and app.view.show_target,"A closes the catalogue and shows the controller placement preview")
				expect(app.selected_label.text.contains("X 施工") and app.selected_label.text.contains("Y 選物件"),"Active tool text shows the controller controls")
				expect(world.state.objects.get(World.key(TILE),{}).is_empty(),"preview does not place anything")
				await tap(JOY_BUTTON_DPAD_RIGHT)
				await settle()
				expect(app.view.target==TILE,"D-pad moves the displayed preview to the expected tile")
				await capture("02-preview.png")
				await tap(JOY_BUTTON_X)
			else:
				var click:=InputEventMouseButton.new()
				click.button_index=MOUSE_BUTTON_LEFT
				click.position=app.view.screen(Vector2(TILE)+Vector2(0.5,0.5))*app.view.view_zoom()
				click.global_position=click.position
				click.pressed=true
				root.push_input(click)
				click.pressed=false
				root.push_input(click)
			await settle()
			expect(world.state.objects.get(World.key(TILE),{}).get("type")=="flower_pot","selected input places a pot at the preview tile")
			expect(int(world.state.players[TOKEN].inventory.get("flower_pot",0))==0,"one pot is consumed")
			await capture("02-placed.png")
	expect(session.shutdown(),"Save and close the test island")
	var reloaded:=World.new()
	expect(reloaded.load_world(world.save_path) and reloaded.state.objects.get(World.key(TILE),{}).get("type")=="flower_pot","Placed pot survives a reload")
	print("FLOWER_POT_BUILD_LIVE failures=",failures)
	quit(int(failures>0))
