extends SceneTree
## Native seeded UI integration; programmatic signals and keys, not human play.
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/public_kitchen_ui.gd")
const HOST:="kitchen-ui-host"
const GUEST:="kitchen-ui-guest"
const LATE:="kitchen-ui-late"
const STOVE:=Vector2i(38,33)
const SEATS:=[Vector2i(37,34),Vector2i(39,34)]
var app
var world
var checks:=0
var failures:=0
var out:=""
func _initialize()->void:call_deferred("run")
func expect(value:bool,note:String)->void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+note)
func settle(frames:int=8)->void:
	for i in frames:await process_frame
func control(id:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(id,true,false) as Control
func reveal(c:Control)->void:
	var p:=c.get_parent()
	while p!=null:
		if p is ScrollContainer:p.ensure_control_visible(c)
		p=p.get_parent()
	await settle(3)
func visible_rect(c:Control)->bool:
	if c==null or not c.is_visible_in_tree():return false
	if not root.get_visible_rect().grow(0.5).encloses(c.get_global_rect()):return false
	var p:=c.get_parent()
	while p!=null:
		if p is ScrollContainer and not p.get_global_rect().grow(0.5).encloses(c.get_global_rect()):return false
		p=p.get_parent()
	return true
func choose(id:String,key:String)->void:
	var option:=control(id) as OptionButton
	expect(option!=null,id+" exists")
	if option==null:return
	for i in option.item_count:
		if str(option.get_item_metadata(i))==key:
			expect(not option.is_item_disabled(i),id+" selected option allowed")
			option.select(i);option.item_selected.emit(i)
			await settle()
			return
	expect(false,id+" has "+key)
func press(id:String)->void:
	var b:=control(id) as Button
	expect(b!=null and not b.disabled,id+" enabled")
	if b==null or b.disabled:return
	await reveal(b)
	expect(visible_rect(b),id+" reachable without clipping")
	b.pressed.emit()
	await settle()
func tap_pad(button:JoyButton)->void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=button
		event.pressed=down
		root.push_input(event)
	await settle()
func attach(token:String)->void:
	app._close_modal()
	app.session.profile={"token":token}
	app.session.world=world
	app.session._attach_registered(1,token)
	app.session.set_physics_process(false)
	app.set_process(false)
	app._refresh_hud()
	await settle()
func shot(state:String,target:String)->void:
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle(20)
		var c:=control(target)
		expect(c!=null,state+" primary control exists")
		if c!=null:
			await reveal(c)
			expect(visible_rect(c),state+" primary control visible at "+str(size))
		expect(root.get_visible_rect().grow(0.5).encloses(app.modal.get_global_rect()),state+" modal contained")
		var status:=control("KitchenStatus")
		expect(visible_rect(status),state+" status visible")
		if state=="collect" or state=="open":
			expect(visible_rect(control("KitchenReason")),state+" cooking and donation explanation visible")
			for meal in ["soup","bread","salad"]:
				expect(visible_rect(control("KitchenIngredients_"+meal)),state+" ingredient icons visible: "+meal)
		if not out.is_empty():
			await RenderingServer.frame_post_draw
			var pic:=root.get_texture().get_image()
			var path:=out.path_join("kitchen-%s-%dx%d.png"%[state,size.x,size.y])
			expect(pic!=null and pic.get_size()==size and pic.save_png(path)==OK,"save "+path)
			print("PUBLIC_KITCHEN_UI_SCREENSHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="):out=arg.trim_prefix("--qa-output=")
	if not out.is_empty():DirAccess.make_dir_recursive_absolute(out)
	print("PUBLIC_KITCHEN_UI fixture=seeded-native user_data_dir="+OS.get_user_data_dir())
	print("FIXTURE seeded picnic, inventories and player positions; normal World.act building; UI signals; no world-time advance; not human play")
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.title="糰糰島｜公共廚房原生檢查（測試物資）"
	world=World.new();world.save_path="user://public-kitchen-ui.json"
	for token in [HOST,GUEST]:
		world.add_player(token,"米飯" if token==HOST else "湯圓")
		world.state.players[token].x=38.5;world.state.players[token].y=35.5
	world.state.picnic=true
	world.state.board=true
	world.state.players[HOST].stories.aru=2
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	world.state.players[HOST].inventory={"wood":100,"stone":100,"fiber":100,"soup":2,"bread":1}
	world.state.players[GUEST].inventory={"soup":2,"bread":1,"salad":2,"radish":2}
	for pair in [[STOVE,"stove"],[SEATS[0],"long_bench"],[SEATS[1],"long_bench"]]:
		var r:Dictionary=world.act(HOST,"fixture-build-"+World.key(pair[0]),"build",pair[0],pair[1])
		expect(r.ok,"build fixture "+str(pair)+": "+str(r.get("message")))
	await attach(HOST)
	root.size=Vector2i(1024,640)
	preload("res://scripts/community_ui.gd").open(app)
	await settle(20)
	expect(visible_rect(control("KitchenEntry")),"table kitchen entry visible at minimum viewport")
	await press("KitchenEntry")
	await settle()
	expect((control("KitchenRegister") as Button).disabled,"no automatic registration")
	await choose("KitchenStoveSelect",World.key(STOVE))
	await choose("KitchenSeatA",World.key(SEATS[0]))
	await choose("KitchenSeatB",World.key(SEATS[1]))
	expect((control("KitchenRegister") as Button).disabled,"donation requires explicit acknowledgement")
	var confirm:=control("KitchenConfirm") as CheckBox
	expect(confirm!=null,"permanent donation confirmation exists")
	if confirm!=null:confirm.button_pressed=true
	await settle()
	await shot("register","KitchenRegister")
	await press("KitchenRegister")
	expect(World.PUBLIC_KITCHEN.registered(world.state),"UI registered public kitchen through Session")
	expect(World.PUBLIC_KITCHEN.events(world.state).size()==2,"registration memory unlocked")
	await shot("collect","KitchenContribute")
	await press("KitchenContribute")
	expect(world.state.public_kitchen.meals=={"soup":2,"bread":1,"salad":0} and not world.state.public_kitchen.opened,"first member partial contribution")
	await attach(GUEST)
	UI.open(app);await settle()
	var contribute:=control("KitchenContribute") as Button
	contribute.release_focus()
	var before_shortcut:int=app.session.counter
	await tap_pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==contribute and app.session.counter==before_shortcut,"X focuses the donation without sending it")
	await tap_pad(JOY_BUTTON_A)
	expect(world.state.public_kitchen.opened,"second member finishes opening meal")
	await shot("open","KitchenCook")
	await tap_pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==control("KitchenCook"),"X focuses cooking when the kitchen no longer accepts donations")
	await tap_pad(JOY_BUTTON_A)
	expect(app.modal.name=="CookingQueueUI","public stove opens existing cooker")
	app._close_modal()
	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"opening reloads primary save")
	world=reopened
	world.add_player(LATE,"晚到的朋友")
	world.state.players[LATE].x=38.5;world.state.players[LATE].y=35.5
	await attach(LATE)
	var before:Dictionary=world.state.duplicate(true)
	root.size=Vector2i(1024,640)
	app._journal()
	await settle(20)
	expect(visible_rect(control("KitchenMemoryBookmark")),"journal memory bookmark visible at minimum viewport")
	await press("KitchenMemoryBookmark")
	expect(World.PUBLIC_KITCHEN.events(app.session.snapshot).size()==3,"late member sees all three memories")
	await press("KitchenStoryReplay")
	await press("KitchenStoryNext")
	expect(world.state==before,"replay and next line do not mutate world or grant items")
	await shot("memory","KitchenStoryReplay")
	var tab:=InputEventKey.new();tab.keycode=KEY_TAB;tab.physical_keycode=KEY_TAB;tab.pressed=true
	Input.parse_input_event(tab);await settle()
	expect(is_instance_valid(app.modal),"Tab keeps scrapbook open")
	var esc:=InputEventKey.new();esc.keycode=KEY_ESCAPE;esc.physical_keycode=KEY_ESCAPE;esc.pressed=true
	Input.parse_input_event(esc);await settle()
	expect(not is_instance_valid(app.modal),"Esc closes scrapbook")
	app.session.shutdown()
	print("PUBLIC_KITCHEN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
