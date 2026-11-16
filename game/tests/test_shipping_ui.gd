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
	for extent in extents:
		root.size=extent
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
		check(not app.preview_toolbar.visible,"World HUD hidden")
		panel.select_category(1)
		panel.select_item("radish")
		panel.set_amount("radish",3)
		var balance:int=player.coins
		panel.confirm()
		check(panel.reviewing and player.coins==balance and player.inventory.radish==12,"Review has no side effect")
		if not photo.is_empty() and stage=="review":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(photo)==OK,"Rendered shipping review")
		var escape:=InputEventKey.new()
		escape.pressed=true
		escape.physical_keycode=KEY_ESCAPE
		app._input(escape)
		check(app.modal==null and app.preview_toolbar.visible and player.inventory.radish==12,"Escape restores HUD without sale")
	app._interact()
	var panel:ShippingPanel=app.modal
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
	panel.confirm()
	panel.confirm()
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
	await process_frame
	await process_frame
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

