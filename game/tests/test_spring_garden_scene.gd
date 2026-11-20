extends SceneTree
## Native flow. Picnic, clock and initial position are seeded. All route
## movement uses World.move_player; E/Esc and the board controls use normal input.
const World=preload("res://scripts/world.gd")
const Garden=World.SPRING_GARDEN
const HALF:=Vector2(0.5,0.5)
const OFFSETS:=[Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]
var app
var world:World
var player_id:String
var output:=""
var path:=""
var size_tag:=""
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:
	run.call_deferred()

func check(condition:bool,message:String)->bool:
	checks+=1
	if condition:return true
	failures+=1
	push_error(message+" "+size_tag)
	return false

func settle()->void:
	for index in 8:await process_frame

func key(code:Key)->void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		root.push_input(event)
	await settle()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)

func point()->Vector2:
	var person:Dictionary=world.state.players[player_id]
	return Vector2(person.x,person.y)

func route_to(site:Vector2i)->Array[Vector2i]:
	var start:=Vector2i(point().floor())
	var target:=site
	if not world.can_stand(Vector2(target)+HALF):
		for offset:Vector2i in OFFSETS:
			if world.can_stand(Vector2(site+offset)+HALF):
				target=site+offset
				break
	var visited:Dictionary={start:start}
	var queue:Array[Vector2i]=[start]
	var index:=0
	while index<queue.size() and not visited.has(target):
		var cell:=queue[index];index+=1
		for offset:Vector2i in OFFSETS:
			var next:=cell+offset
			if visited.has(next) or not world.can_stand(Vector2(next)+HALF):continue
			visited[next]=cell
			queue.append(next)
	var route:Array[Vector2i]=[]
	if not visited.has(target):return route
	while target!=start:
		route.push_front(target)
		target=visited[target]
	route.push_front(start)
	return route

func walk_to(site:Vector2i)->bool:
	var route:=route_to(site)
	if not check(not route.is_empty(),"Walkable route to "+str(site)):return false
	for cell:Vector2i in route:
		var needed:=Vector2(cell)+HALF-point()
		while needed.length()>0.001:
			world.move_player(player_id,needed.normalized(),minf(1.0/60.0,needed.length()/3.6))
			var remaining:=Vector2(cell)+HALF-point()
			if remaining.length()>=needed.length():return check(false,"Normal movement reaches "+str(cell))
			needed=remaining
	refresh()
	await settle()
	return true

func own()->Dictionary:
	return app.session.snapshot.get("own_spring_garden",{})

func button(id:String)->Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String)->bool:
	var control:=button(id)
	if not check(control!=null and not control.disabled,"Available control "+id):return false
	control.grab_focus()
	control.pressed.emit()
	await settle()
	return true

func capture(name:String)->void:
	app._layout_preview()
	await create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image.get_size()==root.size and image.save_png(output.path_join(size_tag+"_"+name+".png"))==OK,"Screenshot saved "+name)

func fit_panel()->void:
	if not check(is_instance_valid(app.modal),"Event panel is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Event panel fits in the window")
	var stamps:=app.modal.find_child("SpringGardenStamps",true,false) as Control
	if check(stamps!=null,"Stamp cards available"):
		check(app.modal.get_global_rect().encloses(stamps.get_global_rect()),"Stamp cards stay inside event panel")
	var reason:=app.modal.find_child("SpringGardenReason",true,false) as Label
	check(reason!=null and not reason.visible,"Available actions have no contradictory lock message")

func exercise()->void:
	var person:Dictionary=world.state.players[player_id]
	person.erase(Garden.KEY)
	refresh()
	await settle()
	if not await walk_to(Garden.BOARD):return
	await key(KEY_E)
	if not await press("SpringGardenLink"):return
	fit_panel()
	await capture("01-sign-up")
	if not await press("SpringGardenStart"):return
	if not check(own().get("active",false) and int(own().get("mask",-1))==0,"Start a new walk"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	for station:String in Garden.SPOTS:
		var site:Vector2i=Garden.SPOTS[station].cell
		var approach:=site+Vector2i.UP if station=="bluebell" else site
		if not await walk_to(approach):return
		app.view.camera=(Vector2(site)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
		app.view.queue_redraw()
		if station=="bluebell":
			app.toast.hide()
			await capture("02-flower-marker")
			var scale:float=app.view.view_zoom()
			var tile:=Rect2(app.view.screen(Vector2(site)),Vector2(32,32))
			var prompt_drawn:=false
			for entry:Dictionary in app.view.world_label_placements(Rect2(Vector2.ZERO,Vector2(root.size)/scale)):
				if entry.id=="spring_garden:bluebell":
					prompt_drawn=true
					check(not tile.intersects(entry.rect),"Interaction prompt keeps the flower sign visible")
			check(prompt_drawn,"The flower sign has an interaction prompt")
		await key(KEY_E)
		if not check(Garden.has_stamp(int(own().get("mask",0)),station),"E collects the "+station+" stamp, focus="+str(app.view.interaction_focus())):return
	if not await walk_to(Garden.BOARD):return
	await key(KEY_E)
	if not await press("SpringGardenLink"):return
	if not await press("SpringGardenFinish"):return
	check(own().get("completed",false) and not own().get("active",true),"The stamp album becomes a keepsake")
	for index in Garden.SPOTS.size():
		var card:Node=app.modal.find_child("SpringGardenStamp_%d"%index,true,false)
		check(card!=null and card.find_child("Mark",true,false).text=="已蓋章","Completed page preserves stamp "+str(index+1))
	fit_panel()
	await capture("03-keepsake")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(70.0).timeout.connect(func():check(false,"Native test watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/spring-garden-day")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("spring-garden-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"花園日旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=350.0
	var safe:=world.safe_arrival(Vector2(Garden.BOARD)+Vector2(0.5,1.5),player_id)
	world.state.players[player_id].x=safe.x
	world.state.players[player_id].y=safe.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
	for size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		size_tag="%dx%d"%[size.x,size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SPRING_GARDEN_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
