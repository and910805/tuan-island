extends SceneTree
## Chapter Four dock/boat project — native render exercise (run WITHOUT --headless).
##
## Drives the real main.tscn client against an in-process World loaded from a
## DUPLICATED temp copy of the completed-public-garden fixture (the original
## fixture file is only read). For each of 1280x800 and 1024x640 a fresh copy is
## used and the whole project is played through real controls:
##   E at the board -> 「群島的來信」 -> dock modal (stage 0, short / stocked)
##   -> 「交付這期工程材料」 -> ferry caption + travel status (dock repaired)
##   -> stage 1 boat modal -> deliver -> completed modal
##   -> ferry caption 「合作小船」 + boat destinations (bamboo / jiaoxi)
##   -> select a boat route -> 「搭乘出發」 -> arrival.
## Screenshots go ONLY to the explicit output directory and their paths are
## written to <out-dir>/manifest.json.
##
## Usage (from game/):
##   godot --path . --script res://tests/test_dock_expedition_render.gd -- --village-art-preview --out-dir=<ABS_DIR>
## Exit 0 = pass, 1 = check failures, 2 = setup problem (no --out-dir / fixture).
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
const Bamboo=preload("res://scripts/bamboo_grove.gd")
const Springs=preload("res://scripts/warm_springs.gd")
const ACTOR:="dock-render-PRIVATE-TOKEN"
const FIXTURE_REL:="../work/salt/network/runs/20261114T054823Z/world-final.json"
const BOARD:=Vector2i(40,29)
const SIZES:=[Vector2i(1280,800),Vector2i(1024,640)]
const DOCK_COPY:=["碼頭待修 · 到公告板查看工程","碼頭已修好 · 等待小船完工","小船已就緒 · 可航往霧竹與暖泉"]
const ALL_MATERIALS:={"plank":20,"stone":8,"fiber":10,"copper_joint":2}

var checks:=0
var failures:=0
var out_dir:=""
var temp_dir:=""
var captures:Array=[]
var app
var game:World
var size_tag:=""

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:run.call_deferred()

func arg(name:String)->String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--"+name+"="):return item.trim_prefix("--"+name+"=")
	return ""

# ------------------------------------------------------------------ helpers

func button_at(node:Node,caption:String)->Button:
	if node==null:return null
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found:=button_at(child,caption)
		if found!=null:return found
	return null

func has_label(node:Node,needle:String)->bool:
	if node==null:return false
	if node is Label and (node as Label).text.contains(needle):return true
	for child in node.get_children():
		if has_label(child,needle):return true
	return false

func fully_visible(control:Control)->bool:
	if control==null or not control.is_visible_in_tree():return false
	var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
	if not screen.encloses(control.get_global_rect()):return false
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func modal_fits()->bool:
	return is_instance_valid(app.modal) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect())

func person()->Dictionary:
	return game.state.players[ACTOR]

func sync()->void:
	app.session._send_snapshot(1)
	app.view.update_snapshot(app.session.snapshot,app.session.own_id)
	var p:=person()
	app.view.display_positions[app.session.own_id]=Vector2(p.x,p.y)

func stand(at:Vector2)->void:
	var p:=person()
	p.region="home"
	p.x=at.x
	p.y=at.y
	sync()

func settle()->void:
	if is_instance_valid(app.modal):app._layout_preview()
	app._process(0.016)
	app.view.queue_redraw()
	for i in 4:await process_frame

func shoot(state:String)->void:
	await settle()
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	check(image.get_size()==root.size,"%s %s capture is %s"%[state,size_tag,image.get_size()])
	var path:=out_dir.path_join("%s-%s.png"%[state,size_tag])
	var err:=image.save_png(path)
	check(err==OK,"saved "+path)
	captures.append({"state":state,"size":size_tag,"path":path,"saved":err==OK})

func ferry_titles()->Array:
	var titles:=[]
	for entry in app.view.world_labels:
		if str(entry.id)=="transit:ferry":titles.append(entry.title)
	return titles

func open_board()->bool:
	app._close_modal()
	stand(Vector2(BOARD)+Vector2(0.5,0.5))
	app._interact()
	await settle()
	return is_instance_valid(app.modal) and button_at(app.modal,"群島的來信")!=null

## Board -> 「群島的來信」 through the real button.
func open_dock()->bool:
	if not await open_board():
		check(false,"%s board opens with 群島的來信 entry"%size_tag)
		return false
	var entry:=button_at(app.modal,"群島的來信")
	entry.pressed.emit()
	await settle()
	return is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="community_board" and button_at(app.modal,"返回公共工程")!=null

func open_ferry()->bool:
	app._close_modal()
	var cell:Vector2i=Transit.points("home").ferry.cell
	stand(Vector2(cell)+Vector2(0.5,0.5))
	app._interact()
	await settle()
	return is_instance_valid(app.modal) and str(app.modal.get_meta("travel_station",""))=="ferry"

func status_text()->String:
	var node=app.modal.find_child("DockTravelStatus",true,false) if is_instance_valid(app.modal) else null
	return (node as Label).text if node is Label else ""

func route_button(region:String)->Button:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child("SelectRoute_"+region,true,false) as Button

func bag(item:String)->int:
	return int(person().inventory.get(item,0))

# ------------------------------------------------------------------ setup

func fresh_world(fixture:String,index:int)->bool:
	var copy:=temp_dir.path_join("world-%d.json"%index)
	var bytes:=FileAccess.get_file_as_bytes(fixture)
	if bytes.is_empty():return false
	var file:=FileAccess.open(copy,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes)
	file.close()
	game=World.new()
	if not game.load_world(copy):return false
	game.save_path=copy
	game.add_player(ACTOR,"渡口修船人")
	var p:=person()
	p.region="home"
	for item in ALL_MATERIALS:p.inventory[item]=0
	return true

func wire()->void:
	app.session.world=game
	app.session.own_id=ACTOR
	app.session.peers={1:ACTOR}
	app.session.sequences[1]=app.session.counter
	app.session.rates[1]=[]
	sync()

# ------------------------------------------------------------------ run

func run()->void:
	out_dir=arg("out-dir")
	if out_dir.is_empty():
		push_error("DOCK_RENDER needs an explicit --out-dir=<absolute directory>")
		print("DOCK_EXPEDITION_RENDER checks=0 failures=1 (missing --out-dir)")
		quit(2)
		return
	out_dir=ProjectSettings.globalize_path(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not "--village-art-preview" in OS.get_cmdline_user_args():
		push_warning("DOCK_RENDER: pass -- --village-art-preview so the board uses the life-task layout (forced on anyway)")
	var fixture:=ProjectSettings.globalize_path("res://").path_join(FIXTURE_REL).simplify_path()
	temp_dir=OS.get_temp_dir().path_join("dock-expedition-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var fixture_before:=FileAccess.get_md5(fixture)
	if fixture_before.is_empty():
		push_error("DOCK_RENDER fixture missing: "+fixture)
		print("DOCK_EXPEDITION_RENDER checks=0 failures=1 (missing fixture)")
		quit(2)
		return
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide()
	app.hud.show()
	app.playing=true
	for index in SIZES.size():
		var size:Vector2i=SIZES[index]
		size_tag="%dx%d"%[size.x,size.y]
		root.size=size
		await process_frame
		if not fresh_world(fixture,index):
			check(false,"%s duplicated fixture loads"%size_tag)
			continue
		wire()
		await exercise(size)
	app._close_modal()
	app.playing=false
	check(FileAccess.get_md5(fixture)==fixture_before,"source fixture unchanged")
	for file in DirAccess.get_files_at(temp_dir):DirAccess.remove_absolute(temp_dir.path_join(file))
	DirAccess.remove_absolute(temp_dir)
	var manifest:=FileAccess.open(out_dir.path_join("manifest.json"),FileAccess.WRITE)
	if manifest!=null:
		manifest.store_string(JSON.stringify({"test":"test_dock_expedition_render","checks":checks,"failures":failures,"captures":captures},"\t"))
		manifest.close()
	check(manifest!=null,"manifest written")
	for entry in captures:print("DOCK_RENDER_CAPTURE %s %s %s"%[entry.state,entry.size,entry.path])
	app.queue_free()
	await process_frame
	print("DOCK_EXPEDITION_RENDER checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func exercise(size:Vector2i)->void:
	var t:=size_tag
	# Fixture prerequisites (read from the duplicate, never patched).
	check(World.CHAPTER_ONE.phase(game.state)=="complete","%s fixture: chapter one complete"%t)
	check(game.state.get("flower_nursery",{}).get("garden",{}).get("complete",false),"%s fixture: Tianwei public garden complete"%t)
	check(int(game.state.get("dock_stage",0))==0,"%s fixture: dock not yet repaired"%t)
	check(not Transit.boat_open(game.state),"%s fixture: boat closed"%t)

	# ---- ferry before any repair: plain caption, stage-0 status, no boat routes
	check(await open_ferry(),"%s E at the ferry opens the travel ticket"%t)
	check(status_text()==DOCK_COPY[0],"%s ferry status stage 0 '%s'"%[t,status_text()])
	check(route_button(Bamboo.REGION)==null and route_button(Springs.REGION)==null,"%s no boat destinations before repair"%t)
	check(modal_fits(),"%s travel ticket fits (stage 0)"%t)
	app._close_modal()
	await settle()
	check(ferry_titles()==["渡口轉乘"],"%s ferry caption is plain 渡口轉乘 before repair %s"%[t,ferry_titles()])

	# ---- stage 0 with an empty bag: modal, progress, refusal
	check(await open_dock(),"%s board -> 群島的來信 opens the dock project"%t)
	check(has_label(app.modal,"修復渡口碼頭"),"%s stage 0 heading 修復渡口碼頭"%t)
	check(not has_label(app.modal,"渡口故事與田尾公共花園完成後"),"%s prerequisites satisfied, no lock hint"%t)
	var submit:=button_at(app.modal,"交付這期工程材料")
	check(submit!=null and not submit.disabled and fully_visible(submit),"%s stage 0 submit visible and enabled"%t)
	check(fully_visible(button_at(app.modal,"返回公共工程")),"%s back to board visible"%t)
	check(modal_fits(),"%s dock modal fits (stage 0 short)"%t)
	await shoot("01-dock-stage0-short")
	if submit!=null:submit.pressed.emit()
	await settle()
	sync()
	check(int(game.state.get("dock_stage",0))==0,"%s empty bag cannot repair the dock"%t)

	# ---- stage 0 stocked: deliver via real button
	for item in ALL_MATERIALS:person().inventory[item]=ALL_MATERIALS[item]
	sync()
	check(await open_dock(),"%s dock project reopens"%t)
	await shoot("02-dock-stage0-ready")
	submit=button_at(app.modal,"交付這期工程材料")
	check(submit!=null and not submit.disabled,"%s stocked submit enabled"%t)
	if submit!=null:submit.pressed.emit()
	await settle()
	sync()
	check(int(game.state.get("dock_stage",0))==1,"%s first delivery repairs the dock"%t)
	check(bag("plank")==8 and bag("stone")==0 and bag("fiber")==10 and bag("copper_joint")==2,"%s dock debits plank 12 / stone 8 only"%t)
	check(not is_instance_valid(app.modal) or app.modal.is_queued_for_deletion(),"%s submit closes the modal"%t)

	# ---- ferry after the dock: caption + status, still no boat routes
	stand(Vector2(Transit.points("home").ferry.cell)+Vector2(0.5,0.5))
	await settle()
	check(ferry_titles().has("碼頭已修復"),"%s ferry caption 碼頭已修復 %s"%[t,ferry_titles()])
	await shoot("03-ferry-dock-repaired-world")
	check(await open_ferry(),"%s ferry ticket reopens"%t)
	check(status_text()==DOCK_COPY[1],"%s ferry status stage 1 '%s'"%[t,status_text()])
	check(route_button(Bamboo.REGION)==null and route_button(Springs.REGION)==null,"%s boat routes still closed at stage 1"%t)
	check(modal_fits(),"%s travel ticket fits (stage 1)"%t)
	await shoot("04-ferry-ticket-stage1")

	# ---- stage 1: boat repair
	check(await open_dock(),"%s dock project at stage 1"%t)
	check(has_label(app.modal,"修復渡口小船"),"%s stage 1 heading 修復渡口小船"%t)
	check(modal_fits(),"%s dock modal fits (stage 1)"%t)
	await shoot("05-dock-stage1-boat")
	submit=button_at(app.modal,"交付這期工程材料")
	check(submit!=null and not submit.disabled and fully_visible(submit),"%s stage 1 submit visible"%t)
	if submit!=null:submit.pressed.emit()
	await settle()
	sync()
	check(int(game.state.get("dock_stage",0))==2 and Transit.boat_open(game.state),"%s second delivery opens the boat"%t)
	check(game.water(Vector2i(app.view.DOCKED_BOAT.floor())),"%s moored boat is over water"%t)
	check(is_finite(app.view.dock_launch_started),"%s completion starts the dock animation"%t)
	var launch_started:float=app.view.dock_launch_started
	sync()
	check(app.view.dock_launch_started==launch_started,"%s repeat snapshot does not restart the animation"%t)
	check(bag("plank")==0 and bag("fiber")==0 and bag("copper_joint")==0 and bag("stone")==0,"%s boat debits exact materials"%t)
	check(await open_dock(),"%s dock project after completion"%t)
	check(has_label(app.modal,"碼頭與小船都修好了") and button_at(app.modal,"交付這期工程材料")==null,"%s completed copy, no submit"%t)
	check(modal_fits(),"%s dock modal fits (complete)"%t)
	await shoot("06-dock-complete")

	# ---- ferry: 合作小船 caption, boat destinations, real departure
	app._close_modal()
	preload("res://scripts/travel_ui.gd").dismiss_arrival(app)
	stand(Vector2(54.5,33.5))
	app.toast.hide()
	await shoot("07-cooperative-boat")
	stand(Vector2(Transit.points("home").ferry.cell)+Vector2(0.5,0.5))
	await settle()
	check(ferry_titles().has("合作小船"),"%s ferry caption 合作小船 %s"%[t,ferry_titles()])
	await shoot("07-ferry-boat-world")
	check(await open_ferry(),"%s ferry ticket with boat"%t)
	check(status_text()==DOCK_COPY[2],"%s ferry status stage 2 '%s'"%[t,status_text()])
	for region in [Bamboo.REGION,Springs.REGION]:
		var route:=route_button(region)
		check(route!=null and fully_visible(route),"%s boat destination %s visible"%[t,region])
	var destination:String=Bamboo.REGION if size==SIZES[0] else Springs.REGION
	var pick:=route_button(destination)
	if pick!=null:pick.pressed.emit()
	await settle()
	check(str(app.modal.get_meta("travel_selected",""))==destination if is_instance_valid(app.modal) else false,"%s selecting %s updates the ticket"%[t,destination])
	check(has_label(app.modal,"合作小船"),"%s ticket shows 合作小船 mode"%t)
	var ticket_art:=app.modal.find_child("TravelTicketArt",true,false) as TextureRect
	check(ticket_art!=null and ticket_art.texture==TransitArt.icon("cooperative_boat"),"%s ticket uses the cooperative hull"%t)
	var depart:Button=null
	if is_instance_valid(app.modal):depart=app.modal.find_child("TravelDepart",true,false) as Button
	check(depart!=null and not depart.disabled and fully_visible(depart),"%s depart enabled at the ferry"%t)
	check(modal_fits(),"%s boat ticket fits"%t)
	await shoot("08-ferry-boat-ticket-%s"%destination)
	if depart!=null:depart.pressed.emit()
	app._close_modal()
	sync()
	await settle()
	check(game.player_region(ACTOR)==destination,"%s boat departure reaches %s (at %s)"%[t,destination,game.player_region(ACTOR)])
	check(app.view.region_id()==destination,"%s view follows to %s"%[t,destination])
	var arrival_art:=app.hud.find_child("ArrivalArt",true,false) as TextureRect
	check(arrival_art!=null and arrival_art.texture==TransitArt.icon("cooperative_boat"),"%s arrival repeats the ticket hull"%t)
	var walkable:=false
	if game.player_region(ACTOR)==destination:
		game.switch_region(destination)
		walkable=game.can_stand(Vector2(person().x,person().y))
		game.switch_region("home")
	check(walkable,"%s arrival is walkable"%t)
	await shoot("09-boat-arrival-%s"%destination)
	# Return boat from the destination station back to the ferry (reverse route).
	var back:Vector2i=Transit.STATIONS[destination].cell
	person().x=back.x+0.5
	person().y=back.y+0.5
	var commission_id:="bamboo_tea_rest" if destination==Bamboo.REGION else "springs_footbath"
	var commission:Dictionary=World.OUTLYING_COMMISSIONS.DEFS[commission_id]
	person().inventory.merge(commission.needs,true)
	sync()
	app._interact()
	await settle()
	var deliver:=button_at(app.modal,"交付地方委託")
	check(deliver!=null and not deliver.disabled,"%s local delivery is enabled after gathering"%t)
	if deliver!=null:
		var parent:=deliver.get_parent()
		while parent!=null:
			if parent is ScrollContainer:parent.ensure_control_visible(deliver)
			parent=parent.get_parent()
	await shoot("10-local-commission-%s"%destination)
	if deliver!=null:deliver.pressed.emit()
	await settle()
	check(World.OUTLYING_COMMISSIONS.done(game.state,ACTOR,commission_id),"%s station control submits the commission"%t)
	check(button_at(app.modal,"交付地方委託")==null,"%s submitted commission no longer has a delivery button"%t)
	check(game.act(ACTOR,"dock-render-home-"+t,"transit",back,"home").ok and game.player_region(ACTOR)=="home","%s return boat reaches the ferry"%t)
	app._close_modal()
	sync()
	await settle()
