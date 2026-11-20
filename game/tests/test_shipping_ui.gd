extends SceneTree
const ShippingPanel=preload("res://scripts/shipping_panel.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize()->void:
	run.call_deferred()
func tap(button:JoyButton)->void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=button
		event.pressed=pressed
		root.push_input(event)
	await process_frame

func run()->void:
	var folder:=OS.get_environment("TEMP").path_join("shipping-ui-"+Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("world.json")
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	var port:=int(app.arg_value("qa-port","30483"))
	var error:int=app.session.host(port,"出貨島民",path)
	check(error==OK and app.playing,"Local Session entered")
	if error!=OK:quit(1);return
	var id:String=app.session.peers[1]
	var player:Dictionary=app.session.world.state.players[id]
	player.x=42.5
	player.y=32.5
	player.inventory.radish=12
	player.inventory.carrot=8
	app.session._send_snapshot(1)
	app.set_process(false)
	app.session.set_physics_process(false)
	var photo:String=app.arg_value("qa-output","")
	var stage:String=app.arg_value("qa-stage","review")
	var extents:=[Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]
	if not photo.is_empty():
		var size:String=app.arg_value("qa-size","1024x640")
		var dimensions:=size.split("x")
		extents=[Vector2i(int(dimensions[0]),int(dimensions[1]))]
	var layouts:Array[Vector3i]=[]
	for extent in extents:
		var scales:Array=[0,1,2,3] if photo.is_empty() else [int(app.arg_value("qa-text-scale","3"))]
		for scale_id:int in scales:
			layouts.append(Vector3i(extent.x,extent.y,scale_id))
	for layout in layouts:
		var extent:=Vector2i(layout.x,layout.y)
		root.size=extent
		app.sound.preferred_text_scale=layout.z
		app._apply_font_scale_tree()
		await process_frame
		if not photo.is_empty() and stage=="world":
			app._process(0.0)
			app._refresh_hud()
			app.view.elapsed=1.0
			app.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(photo)==OK,"Rendered shipping landmark")
		app._interact()
		check(app.modal is ShippingPanel,"World interaction opens shipping")
		if not app.modal is ShippingPanel:quit(1);return
		var panel:ShippingPanel=app.modal
		await process_frame
		await process_frame
		check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(panel.get_global_rect()),"Panel fits "+str(extent))
		check(panel.confirm_button.is_visible_in_tree() and panel.get_global_rect().encloses(panel.confirm_button.get_global_rect()),"Confirmation fully visible")
		check(panel.detail_name.get_theme_font_size("font_size")==app.scaled_font_size(21),"Selection name uses the chosen text size")
		check(not app.preview_toolbar.visible,"World HUD hidden")
		panel.select_category(1)
		panel.slots.radish.grab_focus()
		await tap(JOY_BUTTON_X)
		check(root.gui_get_focus_owner()==panel.plus,"X goes straight to quantity controls")
		await tap(JOY_BUTTON_A)
		await tap(JOY_BUTTON_DPAD_RIGHT)
		check(root.gui_get_focus_owner()==panel.all_button,"D-pad reaches the bulk quantity action")
		await tap(JOY_BUTTON_A)
		check(panel.cart.get("radish",0)==12,"A places all held radishes in the basket")
		await tap(JOY_BUTTON_DPAD_DOWN)
		var balance:int=player.coins
		await tap(JOY_BUTTON_A)
		check(panel.reviewing and player.coins==balance and player.inventory.radish==12,"Review has no side effect")
		if not photo.is_empty() and stage=="review":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(photo)==OK,"Rendered shipping review")
		await tap(JOY_BUTTON_B)
		check(app.modal==null and app.preview_toolbar.visible and player.inventory.radish==12,"B restores HUD without sale")
	app._interact()
	var panel:ShippingPanel=app.modal
	await process_frame
	await process_frame
	panel.set_amount("radish",3)
	panel.confirm()
	player.inventory.radish=2
	app.session._send_snapshot(1)
	var before:int=player.coins
	panel.confirm()
	check(player.inventory.radish==2 and player.coins==before,"Stale inventory cannot debit or credit")
	panel.clear_cart()
	panel.set_amount("radish",2)
	var quote:Dictionary=panel.current_quote()
	panel.confirm_button.grab_focus()
	await tap(JOY_BUTTON_A)
	check(panel.reviewing,"First A requests review after refreshing the basket")
	await tap(JOY_BUTTON_A)
	await tap(JOY_BUTTON_A)
	check(panel.is_ancestor_of(root.gui_get_focus_owner()) and root.gui_get_focus_owner()!=panel.confirm_button,"Sale returns focus to a usable control")
	player=app.session.world.state.players[id]
	var persisted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(player.coins==before+int(quote.total) and int(player.inventory.get("radish",0))==0,"Real Session sale commits coins and inventory")
	check(int(persisted.players[id].coins)==player.coins and int(persisted.players[id].inventory.get("radish",0))==0,"Both changes are on disk")
	check(not panel.pending and panel.cart.is_empty(),"Successful shipment clears receipt")
	check(not panel.slots.radish.visible,"Sold-out item leaves held inventory grid after receipt acknowledgement")
	if not photo.is_empty() and stage=="success":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(photo)==OK,"Rendered persisted successful shipment")
	player.inventory.carrot=1000000
	app.session._send_snapshot(1)
	panel.select_category(1)
	panel.select_item("carrot")
	panel.select_all()
	var longest_id:=""
	for item_id:String in panel.prices:
		if longest_id.is_empty() or String(panel.World.NAMES[item_id]).length()>String(panel.World.NAMES[longest_id]).length():longest_id=item_id
	player.inventory[longest_id]=1
	app.session._send_snapshot(1)
	panel.select_category(panel.category_for(longest_id))
	panel.select_item(longest_id)
	panel.set_amount(longest_id,1)
	await process_frame
	await process_frame
	check(panel.detail_name.text==panel.World.NAMES[longest_id] and panel.detail_name.get_visible_line_count()==panel.detail_name.get_line_count(),"Longest item name fits the selection details")
	var receipt_name_fits:=false
	for label:Label in panel.receipt.find_children("*","Label",true,false):
		if label.text==panel.World.NAMES[longest_id]:
			receipt_name_fits=label.get_visible_line_count()==label.get_line_count()
	check(receipt_name_fits,"Longest item name fits the receipt")
	check(panel.get_global_rect().encloses(panel.confirm_button.get_global_rect()),"Large quantities keep confirmation inside panel")
	check(panel.receipt_scroll.get_global_rect().size.x>=panel.receipt.get_global_rect().size.x,"Large receipt quantities fit available width")
	panel.pending=true
	var held_cart:=panel.cart.duplicate()
	panel.confirm()
	panel.clear_cart()
	panel.set_amount("carrot",1)
	check(panel.cart==held_cart,"Pending submission blocks duplicate confirm and edits")
	panel.complete({"ok":false,"message":"操作太快了，稍等一下再試。"})
	check(not panel.pending and panel.cart==held_cart and panel.notice.text.contains("操作太快"),"Failure restores editing and retains receipt")
	app.session.shutdown()
	await create_timer(0.8).timeout
	app.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("SHIPPING_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
