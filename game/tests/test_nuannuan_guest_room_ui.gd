extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const HouseUI:=preload("res://scripts/house_ui.gd")
const Folio:=preload("res://scripts/build_folio.gd")
const ORIGIN:=Vector2i(24,34)
const ROOM_SIGN:="keepsake_nuannuan_room"
const CAPTURE_DELAY:=0.45
# Themed furniture beyond the generic bed/lamp/chair ids.
const THEME_BED:="cedar_bed"
const THEME_LAMP:="paper_tea_lamp"
const THEME_SEAT:="indigo_cushion"

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		# Let any modal/ribbon fade finish before grabbing the frame.
		await create_timer(CAPTURE_DELAY).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func piece(kind:String) -> Dictionary:
	var result:={"type":kind,"owner":token,"items":{}}
	if kind=="door":result.open=false
	return result

func shell() -> void:
	# Interior is 3x3 so a two-cell bed, wardrobe and cushion still leave a path from the door.
	for y in 5:
		for x in 5:
			var tile:=World.key(ORIGIN+Vector2i(x,y))
			world.state.removed[tile]=true
			if x in [1,2,3] and y in [1,2,3]:
				world.state.ground[tile]=piece("floor")
				world.state.roofs[tile]=piece("roof")
			else:
				world.state.objects[tile]=piece("door" if Vector2i(x,y)==Vector2i(1,0) else "wall")

func run() -> void:
	var rest_choice:="porch"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--inn-seat="):rest_choice=arg.trim_prefix("--inn-seat=")
	var rest_suffix:="" if rest_choice=="porch" else "-"+rest_choice
	root.size=Vector2i(1280,800) if "--wide" in OS.get_cmdline_user_args() else Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.session.profile.token=Crypto.new().generate_random_bytes(24).hex_encode()
	var path:="user://nuannuan-guest-room-%d.json"%OS.get_process_id()
	if app.session.host(0,"旅舍島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.inventory.merge({"wood":80,"fiber":40,"stone":30,"plank":4,
		"bamboo":10,"cotton_cloth":5,"copper_ingot":2,"blue_dye":2},true)
	person.bonds={"nuannuan":{"points":14,"talk_day":-1,"gift_day":-1}}
	shell()
	var interior:=ORIGIN+Vector2i(1,1)
	var bed:=ORIGIN+Vector2i(3,2)
	var lamp:=ORIGIN+Vector2i(3,1)
	var chair:=ORIGIN+Vector2i(1,3)
	stand(interior)
	var bed_result:=world.act(token,"add-bed","build",bed,THEME_BED)
	expect(bed_result.ok,"Built a themed cedar bed: "+str(bed_result.get("message","")))
	expect(world.state.objects.get(World.key(bed),{}).get("type")==THEME_BED and world.state.objects.get(World.key(bed+Vector2i.DOWN),{}).get("type")==THEME_BED,
		"The cedar bed occupies its full two-cell footprint inside the room")
	expect(world.act(token,"add-lamp","build",lamp,THEME_LAMP).ok,"Built a themed paper tea lamp")
	stand(interior)
	HouseUI.open(app)
	await process_frame
	var register_room:=button("GuestRoomRegister")
	expect(register_room!=null and register_room.disabled,"A seat is required even in a complete house")
	expect(not world.act(token,"no-chair",Goals.GUEST_ROOM_ACTION,interior).ok,"Server rejects incomplete furnishings")
	app._close_modal()
	expect(world.act(token,"add-chair","build",chair,THEME_SEAT).ok,"Built a themed indigo cushion seat")
	stand(ORIGIN+Vector2i(1,-1))
	expect(not world.act(token,"outside",Goals.GUEST_ROOM_ACTION,ORIGIN+Vector2i(1,-1)).ok,"No registration from outside")
	stand(interior)
	# Ready stage: open the checker from the story page's own button.
	Tasks.bond_goal(app,"nuannuan",3)
	await process_frame
	await press("NuannuanCheckGuestRoom")
	var check_modal:Control=app.modal
	expect(is_instance_valid(check_modal) and check_modal.has_meta("house_check"),"The story page opens the house checker")
	await capture("01-guest-room-check.png")
	await press("GuestRoomRegister")
	expect(is_instance_valid(app.modal) and app.modal==check_modal,"Registration stays on the same modal")
	var status:=app.modal.find_child("GuestRoomStatus",true,false) as Label if is_instance_valid(app.modal) else null
	expect(status!=null and status.text.begins_with("✓"),"The status label confirms registration")
	var gone:=button("GuestRoomRegister")
	expect(gone==null or not gone.visible,"The register button hides after success")
	await capture("01b-guest-room-registered.png")
	expect(app.session.snapshot.own_guest_room and not app.session.snapshot.players[app.session.own_id].has(Goals.GUEST_ROOM_KEY),"Saved personal room progress without publishing it")
	expect(not world.act(token,"repeat-room",Goals.GUEST_ROOM_ACTION,interior).ok,"Room is registered only once")
	var host:Vector2i=World.bond_place(world.state,"nuannuan")[1]
	var springs:=World.REGIONS.Springs
	person.region=springs.REGION
	world.switch_region(springs.REGION)
	expect(world.blocked(springs.INN_FOOTPRINT.position) and not world.blocked(springs.INN_DOOR),"The inn walls block movement while the porch doorway is reachable")
	world.switch_region(World.REGIONS.HOME)
	stand(springs.INN_DOOR)
	app.WanganUI.dismiss(app)
	app._interact()
	await process_frame
	await capture("08-warm-springs-inn.png")
	expect(not world.act(token,"outside-inn-furniture",springs.INN_USE,Vector2i(61,22)).ok,"Outdoor players cannot use indoor furniture")
	expect(not world.act(token,"wrong-inn-door",springs.INN_PORTAL,springs.INN_EXIT).ok,"Outside players cannot address the interior exit")
	await press("WarmSpringsInnEnter")
	expect(springs.in_inn(person) and Vector2i(Vector2(person.x,person.y))==springs.INN_EXIT+Vector2i.UP,"Reception sends the player through the door")
	world.switch_region(springs.REGION)
	expect(world.blocked(Vector2i(61,23)) and not world.blocked(Vector2i(65,24)),"The displayed bed blocks its full footprint and the aisle remains walkable")
	world.switch_region(World.REGIONS.HOME)
	if DisplayServer.get_name()!="headless":
		expect(app.sound.music.scene_id=="warm_springs_interior" and app.sound.music.current.playing,
			"The client switches to the indoor soundtrack on entry")
	var indoors_save:=World.new()
	expect(indoors_save.load_world(path) and springs.in_inn(indoors_save.state.players.get(token,{})),"An indoor player reloads inside the inn")
	world.move_player(token,Vector2.UP,0.72)
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	var ribbon:Control=app.hud.get_node_or_null("TravelArrival")
	if ribbon:ribbon.hide()
	app.toast.hide()
	await capture("09-warm-springs-inn-interior.png")
	var time:float=world.state.time
	person.mine_energy=21
	stand(Vector2i(62,23))
	app._interact()
	expect(person.mine_energy==100 and world.state.time==time,"The public quilt bed restores the visitor's energy without advancing island time")
	var chair_cell:=Vector2i(67,24)
	stand(Vector2i(67,23))
	world.move_player(token,Vector2.DOWN,0.075)
	app.session._send_snapshot(1)
	app._interact()
	var seat_prefix:=springs.INN_USE+":"
	expect(person.get(springs.REST_SEAT_KEY)==seat_prefix+World.key(chair_cell),"The real tea-table interaction seats the player")
	var guest_id:="inn-chair-guest"
	world.add_player(guest_id,"旅舍訪客")
	var guest:Dictionary=world.state.players[guest_id]
	guest.region=springs.REGION
	guest.mine_energy=32
	guest.x=65.5
	guest.y=25.5
	expect(not world.act(guest_id,"same-seat",springs.INN_USE,chair_cell).ok,"A visitor cannot take an occupied chair")
	var second_chair:=Vector2i(66,25)
	expect(world.act(guest_id,"another-seat",springs.INN_USE,second_chair).ok and guest.mine_energy==32
		and guest.get(springs.REST_SEAT_KEY)==seat_prefix+World.key(second_chair),"The second chair is available and sitting does not restore energy")
	app.session.peers[2]=guest_id
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	await capture("10-warm-springs-inn-tea-seats.png")
	app.session.peers.erase(2)
	world.move_player(token,Vector2.RIGHT,0.1)
	expect(not person.has(springs.REST_SEAT_KEY),"Movement frees the tea chair")
	expect(world.act(guest_id,"newly-free-seat",springs.INN_USE,chair_cell).ok,"Another visitor can take the freed chair")
	stand(springs.INN_EXIT+Vector2i.UP)
	app._interact()
	expect(not springs.in_inn(person) and Vector2i(Vector2(person.x,person.y))==springs.INN_DOOR,"The exit returns to the outdoor porch")
	if DisplayServer.get_name()!="headless":
		expect(app.sound.music.scene_id==springs.REGION and app.sound.music.current.playing,"Outdoor music resumes on exit")
	app._interact()
	await process_frame
	await press("WarmSpringsInnStory")
	expect(is_instance_valid(app.modal) and app.modal.find_child("BondEventTabs",true,false)!=null,"The inn entrance opens Warm Warm's story from the notice")
	app._close_modal()
	stand(host)
	app.WanganUI.dismiss(app)
	expect(not world.act(token,"pre-report",Goals.GUEST_CLOTH_ACTION,host).ok,"Reward cannot be claimed before reporting")
	Tasks.bond_goal(app,"nuannuan",3)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.nuannuan["3"].state=="done","Warm Springs report completes the event")
	expect(button("NuannuanGuestCloth")!=null and button("NuannuanGuestWardrobePattern")!=null,"The N12-3 report immediately leaves the cloth reward and pattern on screen")
	await capture("03-guest-room-rewards.png")
	await press("NuannuanGuestCloth")
	expect(int(person.inventory.get("cotton_cloth",0))==2 and app.session.snapshot.own_guest_cloth,"Received the two pieces of lodge cloth")
	expect(not world.act(token,"repeat-cloth",Goals.GUEST_CLOTH_ACTION,host).ok,"Cloth cannot be claimed twice")
	expect(is_instance_valid(app.modal) and button("NuannuanGuestWardrobePattern")!=null,"Claiming keeps the reward page open without a manual reopen")
	expect(button("NuannuanGuestCloth")==null,"The completed page reflects a claimed reward")
	person.region=World.REGIONS.HOME
	stand(interior)
	var wardrobe:=ORIGIN+Vector2i(2,1)
	expect(Folio.unlocked(app,app.session.snapshot.players[app.session.own_id],Goals.WARDROBE_KIND),"Wardrobe diagram available in the furniture catalogue")
	Tasks.bond_goal(app,"nuannuan",3)
	await process_frame
	await press("NuannuanGuestWardrobePattern")
	expect(is_instance_valid(app.modal) and app.modal.find_child("BuildRecipe",true,false)!=null,"The story links to the workshop recipe")
	app._close_modal()
	expect(world.act(token,"build-wardrobe","build",wardrobe,Goals.WARDROBE_KIND).ok,"Built wardrobe using the cloth reward and four planks")
	expect(world.state.objects.get(World.key(wardrobe),{}).get("type")==Goals.WARDROBE_KIND and world.blocked(wardrobe),"Wardrobe is placed and obeys furniture collision")
	expect(not world.act(token,"locked-apron",Goals.APRON_ACTION,wardrobe).ok,"Wardrobe cannot grant a locked outfit")
	# The original co-dining unlock is outside this feature's fixture; simulate it after checking its gate.
	person.bonds.milu={"points":24,"talk_day":-1,"gift_day":-1}
	person.bond_goals.milu={"4":""}
	# The paper lamp is interactive too: stand beside the wardrobe so it is the nearest target.
	stand(interior)
	world.move_player(token,Vector2.RIGHT,0.075)
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	await capture("02-guest-wardrobe.png")
	await press("GuestWardrobeApron")
	expect(person.get(Goals.APRON_KEY,false),"Equipped the earned apron from the wardrobe")
	person.bonds.nuannuan.points=24
	person.region=World.REGIONS.Springs.REGION
	stand(host)
	Tasks.bond_goal(app,"nuannuan",4)
	await process_frame
	await press("BondGoalOption_"+rest_choice)
	await press("BondGoalDo")
	expect(person.get(springs.REST_SEAT_KEY)==rest_choice and Vector2i(Vector2(person.x,person.y))==springs.REST_SEATS[rest_choice],
		"The event actually seats the player at "+rest_choice)
	await create_timer(0.3).timeout
	var arrival:Control=app.hud.get_node_or_null("TravelArrival")
	if arrival:arrival.hide()
	app.toast.hide()
	await capture("06-inn-rest-together"+rest_suffix+".png")
	# Solo seat is shown above; now a visiting player joins the same selected seat.
	var seat_cell:Vector2i=springs.REST_SEATS[rest_choice]
	var friend_anchor:=Vector2(seat_cell)+Vector2(1.42,0.66)
	guest.erase(springs.REST_SEAT_KEY)
	guest.region=springs.REGION
	guest.x=seat_cell.x+0.5
	guest.y=seat_cell.y+1.5
	var join:=world.act(guest_id,"join-rest",springs.REST_JOIN,seat_cell,rest_choice)
	expect(springs.REST_JOIN=="nuannuan_rest_join" and join.ok,"A visitor can join the selected rest seat: "+str(join.get("message","")))
	expect(person.get(springs.REST_SEAT_KEY)==rest_choice and guest.get(springs.REST_SEAT_KEY)=="friend:"+rest_choice,
		"The primary keeps the seat while the visitor is recorded as its friend")
	expect(Vector2(guest.x,guest.y).distance_to(friend_anchor)<0.01,"The friend is anchored beside the primary seat")
	app.session.peers[2]=guest_id
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	var seated_names:Array=[]
	var own_seated:=false
	var friend_seated:=false
	for actor_id in app.session.snapshot.players:
		var actor:Dictionary=app.session.snapshot.players[actor_id]
		var actor_seat=actor.get(springs.REST_SEAT_KEY,"")
		if actor_id==app.session.own_id:own_seated=actor_seat==rest_choice
		elif str(actor.get("name",""))=="旅舍訪客":friend_seated=actor_seat=="friend:"+rest_choice
	expect(own_seated and friend_seated,"The snapshot shows both the primary and the friend seated")
	var arrival_friend:Control=app.hud.get_node_or_null("TravelArrival")
	if arrival_friend:arrival_friend.hide()
	app.toast.hide()
	await capture("06b-inn-rest-friend"+rest_suffix+".png")
	if DisplayServer.get_name()!="headless":
		Tasks.bond_goal(app,"nuannuan",4)
		await process_frame
		await press("NuannuanTakePhoto")
		var friend_photo:=Tasks.inn_photo_path(app)
		expect(FileAccess.file_exists(friend_photo),"The primary's real photo button saves a multiplayer rest image")
		Tasks.bond_goal(app,"nuannuan",4)
		await process_frame
		await press("NuannuanViewPhoto")
		expect(is_instance_valid(app.modal) and app.modal.find_child("NuannuanInnPhoto",true,false)!=null,"The album shows the multiplayer rest photo")
		await capture("07b-inn-photo-album-friend"+rest_suffix+".png")
		if FileAccess.file_exists(friend_photo):DirAccess.remove_absolute(friend_photo)
		app._close_modal()
	app.session.peers.erase(2)
	guest.erase(springs.REST_SEAT_KEY)
	world.move_player(token,Vector2.LEFT,0.1)
	expect(not person.has(springs.REST_SEAT_KEY),"Moving ends the seated pose")
	stand(host)
	var sign_kit:=Goals.keepsake_item(ROOM_SIGN)
	expect(int(person.inventory.get(sign_kit,0))==1 and Goals.keepsake_claimed(person,ROOM_SIGN),"Completing the final story grants one room sign")
	Tasks.bond_goal(app,"nuannuan",4)
	await process_frame
	await capture("04-inn-room-sign-reward.png")
	await press("NuannuanRestReplay")
	expect(person.get(springs.REST_SEAT_KEY)==rest_choice and person.inventory[sign_kit]==1,"The completed page replays the seat without another reward")
	if DisplayServer.get_name()!="headless":
		Tasks.bond_goal(app,"nuannuan",4)
		await process_frame
		await press("NuannuanTakePhoto")
		var photo_path:=Tasks.inn_photo_path(app)
		expect(FileAccess.file_exists(photo_path),"The photo button saves an actual game image")
		Tasks.bond_goal(app,"nuannuan",4)
		await process_frame
		await press("NuannuanViewPhoto")
		expect(is_instance_valid(app.modal) and app.modal.find_child("NuannuanInnPhoto",true,false)!=null,"The story album displays the saved group photo")
		await capture("07-inn-photo-album"+rest_suffix+".png")
		if FileAccess.file_exists(photo_path):DirAccess.remove_absolute(photo_path)
	world.move_player(token,Vector2.LEFT,0.1)
	person.region=World.REGIONS.HOME
	stand(interior)
	var display:=ORIGIN+Vector2i(1,2)
	expect(world.act(token,"place-room-sign","build",display,ROOM_SIGN).ok and not world.blocked(display),"The completed reward places a walkable room sign")
	expect(int(person.inventory.get(sign_kit,0))==0,"Displaying the sign consumes exactly one reward")
	stand(interior)
	await capture("05-inn-room-sign-displayed.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	expect(record.get(Goals.GUEST_ROOM_KEY,false) and record.get(Goals.GUEST_CLOTH_KEY,false) and record.get(Goals.APRON_KEY,false),"Room, claim and apron are persistent")
	expect(loaded.state.objects.get(World.key(wardrobe),{}).get("type")==Goals.WARDROBE_KIND,"Wardrobe survives reload")
	expect(loaded.state.objects.get(World.key(display),{}).get("type")==ROOM_SIGN and Goals.keepsake_claimed(record,ROOM_SIGN),
		"The placed room sign and claim survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("NUANNUAN_GUEST_ROOM_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
