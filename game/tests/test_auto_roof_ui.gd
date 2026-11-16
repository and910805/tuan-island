extends SceneTree
# Controlled room fixture; real Session.perform / World.act for confirmation.
const World=preload("res://scripts/world.gd")
const Preview=preload("res://scripts/auto_roof_preview.gd")
var app
var world
var actor:String
var origin:Vector2i
var gap:Vector2i
var checks:=0
var failures:=0
var output:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+message)
func settle()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	for i in 6:await process_frame
	app._layout_preview()
	await create_timer(0.25).timeout
func piece(kind:String)->Dictionary:
	var out:={"type":kind,"owner":actor,"items":{}}
	if kind=="door":out.open=false
	return out
func find_site()->Vector2i:
	for y in range(18,50):
		for x in range(14,64):
			var clear:=true
			for dy in 4:
				for dx in 4:
					var p:=Vector2i(x+dx,y+dy)
					if world.blocked(p) or world.protected(p) or world.resource(p)!="" or world.state.ground.has(World.key(p)):clear=false
			if clear:return Vector2i(x,y)
	return Vector2i(-1,-1)
func fixture()->void:
	origin=find_site()
	check(origin.x>=0,"clear legal fixture site")
	gap=origin+Vector2i(1,0)
	for y in 4:
		for x in 4:
			var p:=origin+Vector2i(x,y)
			if x in [1,2] and y in [1,2]:world.state.ground[World.key(p)]=piece("floor")
			elif p!=gap:world.state.objects[World.key(p)]=piece("door" if Vector2i(x,y)==Vector2i(1,3) else "wall")
	world.state.players[actor].x=origin.x+1.5
	world.state.players[actor].y=origin.y+1.5
	world.state.players[actor].inventory.wood=100
	world.state.players[actor].inventory.fiber=100
func click(name:String)->void:
	var node=app.modal.find_child(name,true,false) if app.modal else null
	check(node is Button,"button "+name)
	if node is Button:node.pressed.emit()
func shot(name:String)->void:
	if output.is_empty():return
	app.toast.hide()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"capture "+name)
func modal_layout()->void:
	check(app.modal!=null,"confirmation opens")
	if not app.modal:return
	var bounds:Rect2=app.modal.get_global_rect()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(bounds),"modal fits viewport")
	for name in ["RoofConfirm","RoofCancel"]:
		var b=app.modal.find_child(name,true,false)
		check(b is Control and b.is_visible_in_tree() and bounds.encloses(b.get_global_rect()),name+" visible")
	var scroll=app.modal.find_child("ModalScroll",true,false)
	if scroll:check(not scroll.get_v_scroll_bar().visible,"quote fits without vertical scrolling")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="):output=arg.trim_prefix("--qa-output=")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	var path:=OS.get_environment("TEMP").path_join("auto-roof-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	check(app.session.host(0,"屋頂試作",path)==OK,"local session host")
	app.session.set_physics_process(false)
	world=app.session.world
	actor=app.session.peers[1]
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		fixture()
		await settle()
		var before:Dictionary=world.state.duplicate(true)
		app._perform_build_action("build",gap,"wall")
		await settle()
		modal_layout()
		check(world.state==before,"opening quote does not build/deduct")
		await shot("quote-%dx%d"%[size.x,size.y])
		click("RoofCancel")
		await settle()
		check(app.modal==null and world.state==before,"cancel leaves world unchanged")
		app._perform_build_action("build",gap,"wall")
		await settle()
		# Another valid change reduces missing roofs while the quote is open.
		world.state.roofs[World.key(origin+Vector2i(2,2))]=piece("roof")
		await settle()
		var changed:Dictionary=world.state.duplicate(true)
		click("RoofConfirm")
		await settle()
		check(app.modal!=null and world.state==changed,"changed quote requires another confirmation")
		var quote:Dictionary=Preview.quote(app.session.snapshot,app.session.own_id,"build",gap,"wall")
		check(quote.ok and quote.plan.add.size()==3,"updated quote retains manual roof")
		click("RoofConfirm")
		await settle()
		check(app.modal==null and world.state.objects.has(World.key(gap)),"confirm performs original build")
		check(world.state.players[actor].inventory.wood==100-int(quote.total_cost.get("wood",0)),"actual wood equals displayed total")
		check(world.state.players[actor].inventory.fiber==100-int(quote.total_cost.get("fiber",0)),"actual fiber equals displayed total")
		var automatic:=0
		for y in [1,2]:
			for x in [1,2]:
				var roof:Dictionary=world.state.roofs.get(World.key(origin+Vector2i(x,y)),{})
				check(not roof.is_empty(),"interior covered")
				if roof.get("auto",false):automatic+=1
		check(automatic==3,"exactly three automatic plus one manual roof")
		await shot("built-%dx%d"%[size.x,size.y])
		app._perform_build_action("remove",gap,"")
		await settle()
		modal_layout()
		var remove_before:Dictionary=world.state.duplicate(true)
		var esc:=InputEventKey.new()
		esc.keycode=KEY_ESCAPE;esc.physical_keycode=KEY_ESCAPE;esc.pressed=true
		app._input(esc)
		await settle()
		check(app.modal==null and world.state==remove_before,"Esc cancels structural removal")
	check(app.session.shutdown(),"session shutdown saves")
	app.queue_free()
	await process_frame
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("AUTO_ROOF_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
