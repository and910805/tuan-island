extends SceneTree
## 望安開場 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/望安開場預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
##
## Art: no new PNGs. The arrival card uses the existing paper panel style and
## Xiaoli's existing portrait frame; the plot marker (corner stakes, twine, soil
## hint) is program-drawn by wangan_opening_ui.draw_plot and has no time input,
## so it is identical with or without reduced motion. No boat sprite exists in
## the project, so the card has no boat picture (text only).
##
## PRESET / FIXTURE (not human play):
##  * each world is an isolated host save in %TEMP% (deleted at the end);
##    app.village_art_preview=true; app processing / Session physics off;
##  * the local player is teleported by writing x/y (VIEW_SPOT for the frames,
##    WORK_SPOT for the farm actions); the crop grows with World.step;
##  * the occupied cases add a fake neighbour with World.add_player, give them
##    wood/stone by writing their inventory, and fill plot cells with their
##    World.act hoe / build floor actions;
##  * the shipment is sent with session.perform("ship", …) like the shipping panel.
##  * after shipment, bridge/starter/stove materials and second-batch seeds and
##    cooking ingredients are provided. Devices use build actions. Refill,
##    enable, cook, collect and picnic delivery use the actual panel buttons.
##    Irrigation and cooking timers advance through World.step.
## REALLY EXERCISED: Session.host -> main._entered -> arrival card; my farm
##  actions through session.perform (hoe / seed / water / harvest / ship).
## SHOTS per size (11): arrival, plot_empty, plot_tilled, plot_sown, plot_watered,
##  plot_mature, plot_harvested, after_ship, occupied_partial, occupied_full,
##  hud_tracker (crop of the tracker during the find step).
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
## Below the plot (plot rows 26-27): with the player-centred camera the whole plot
## and its tag sit between the tracker (left) and the weather badge (right).
const VIEW_SPOT:=Vector2(46.5,30.5)
const WORK_SPOT:=Vector2(45.5,28.5)
const WORK_CELL:=Vector2i(45,27)
var app
var w
var me:=""
var id:=""
var path:=""
var paths:Array[String]=[]
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var neighbour:=""

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func check_tools(expected:Array,toggle_visible:bool)->void:
	var shown:Array=[]
	for index in Shell.TOOL_IDS.size():
		if app.tool_buttons[index].visible:shown.append(Shell.TOOL_IDS[index])
	var toggle:=app.preview_toolbar.find_child("AllToolsToggle",true,false) as Button
	check(shown==expected and toggle!=null and toggle.visible==toggle_visible,"Correct guided tools for "+step_id())
	var bar:Control=app.preview_toolbar
	check(absf(bar.get_global_rect().get_center().x-float(root.size.x)*0.5)<=1.0,"Toolbar stays centered")
	var shortcuts:Control=app.hud.get_node("LifeShortcuts")
	check(not shortcuts.get_global_rect().intersects(bar.get_global_rect()),"Shortcuts and tool strip never intersect")
	var titles:Array=[]
	for child in shortcuts.get_children():
		var caption:Label=child.get_node("ShortcutTitle")
		var key:Label=child.get_node("KeyBadge")
		var icon:Control=child.get_node("ToolArt")
		titles.append(caption.text)
		check(not key.get_global_rect().intersects(icon.get_global_rect()) and not caption.get_global_rect().intersects(icon.get_global_rect()) and key.has_theme_stylebox_override("normal"),"Shortcut icon, label and key use separate, readable lanes")
	check(titles==["背包","手帳","選單"],"All three shortcuts show clear names")

func finish()->void:
	if finished:return
	finished=true
	for item in paths:
		for suffix in ["",".bak",".tmp",".writer-lock"]:
			if FileAccess.file_exists(item+suffix):DirAccess.remove_absolute(item+suffix)
	print("WANGAN_OPENING_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func person()->Dictionary:
	return w.state.players[me]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	if v.goals.has(id):
		v.starts[id]=v.goals[id]
		v.display_positions[id]=v.goals[id]
	v.facings[id]=Vector2i.UP
	v._process(0.0)
	await settle()

func perform(action:String,cell:Vector2i,extra:String="")->void:
	app.session.rates[1].clear()
	app.session.perform(action,cell,extra)
	await refresh()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func shot(step:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("WANGAN_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func step_corner_visible(image:Image,cell:Vector2i)->bool:
	var corner:Vector2=app.view.screen(Vector2(cell)).round()+Vector2(6,3)
	var position:=Vector2i(view_to_pixels(Rect2(corner,Vector2.ONE)).position)
	return Rect2i(Vector2i.ZERO,image.get_size()).has_point(position) and image.get_pixelv(position).is_equal_approx(Color("fff0ad"))

func plot_world_rect()->Rect2:
	var cells:=Opening.plot_rect()
	return Rect2(app.view.screen(Vector2(cells.position)),Vector2(cells.size)*32.0)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func hud_panels()->Array:
	var result:=[]
	var area:=Vector2(root.size).x*Vector2(root.size).y
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		if c.size.x*c.size.y>area*0.5:continue
		result.append({"name":str(c.name),"rect":c.get_global_rect()})
	return result

## Stake pixels at the four plot corners (exact program colours).
func stake_pixels(image:Image)->int:
	var r:=plot_world_rect().grow(-1.0)
	var count:=0
	for corner in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
		var box:=view_to_pixels(Rect2((corner as Vector2).round()+Vector2(-2,-9),Vector2(4,11)))
		for x in range(int(box.position.x),int(box.end.x)):
			for y in range(int(box.position.y),int(box.end.y)):
				if x<0 or y<0 or x>=image.get_width() or y>=image.get_height():continue
				var c:=image.get_pixel(x,y)
				if absf(c.r-WanganUI.STAKE.r)+absf(c.g-WanganUI.STAKE.g)+absf(c.b-WanganUI.STAKE.b)<0.06:count+=1
	return count

func marker_ok(image:Image,label:String,shown:bool)->void:
	var list:=placements()
	var tag_entry:={}
	for entry:Dictionary in list:
		if str(entry.id)==Opening.PLOT_LABEL_ID:tag_entry=entry
	var stakes:=stake_pixels(image) if image!=null else 0
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	if not shown:
		check(not Opening.marker_shown(app.session.snapshot,id),"Marker off in the snapshot (%s)"%label)
		check(tag_entry.is_empty(),"No 「小栗留的田」 tag (%s)"%label)
		# Floor planks share a few stake-brown pixels; a drawn marker has >= 40.
		check(stakes<20,"No plot stakes drawn (%s): %d px"%[label,stakes])
		return
	check(not tag_entry.is_empty() and str(tag_entry.title)=="小栗留的田","Tag 「小栗留的田」 placed (%s)"%label)
	check(stakes>=40,"Corner stakes drawn (%s): %d px"%[label,stakes])
	var plot_px:=view_to_pixels(plot_world_rect())
	check(screen_rect.encloses(plot_px),"Whole plot on screen (%s) %s"%[label,str(plot_px)])
	for panel:Dictionary in hud_panels():
		check(not plot_px.grow(12).intersects(panel.rect),"Plot clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(plot_px),str(panel.rect)])
		if not tag_entry.is_empty():check(not view_to_pixels(tag_entry.rect).intersects(panel.rect),"Tag clear of HUD %s (%s)"%[panel.name,label])
	if not tag_entry.is_empty():
		var tag_rect:Rect2=tag_entry.rect
		check(screen_rect.encloses(view_to_pixels(tag_rect)),"Tag on screen (%s)"%label)
		check(not tag_rect.intersects(plot_world_rect().grow(-2.0)),"Tag does not cover the plot cells or crops (%s) %s"%[label,str(tag_rect)])
		for entry:Dictionary in list:
			if entry!=tag_entry:check(not tag_rect.intersects(entry.rect),"Tag does not overlap 「%s」 (%s)"%[entry.title,label])
		var foot:Vector2=app.view.screen(app.view.display_positions.get(id,Vector2(person().x,person().y)))
		check(not tag_rect.intersects(Rect2(foot+Vector2(-16,-48),Vector2(32,48))),"Tag clear of my body (%s)"%label)

func open_world()->bool:
	path=OS.get_environment("TEMP").path_join("wangan-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	paths.append(path)
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.sound.reduced_motion=root.size.x>=1280
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"望安旅人",path)!=OK:
		check(false,"Host starts")
		return false
	await settle()
	w=app.session.world;me=app.session.profile.token;id=app.session.own_id
	if not app.playing:app.playing=true
	app._update_world_label_obstacles()
	await refresh()
	return true

func close_world()->void:
	app.session.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	await process_frame

func step_id()->String:
	return str(Chapter.first_crop_step(app.session.snapshot,id).get("id",""))

func size_flow(size:Vector2i)->void:
	root.size=size
	tag="%dx%d"%[size.x,size.y]
	if not await open_world():return
	# Arrival card over the landing.
	var card:=WanganUI.card(app)
	check(card!=null and card.is_visible_in_tree(),"Arrival card shown (%s)"%tag)
	await shot("arrival")
	var illustration:Control=card.find_child("ArrivalIllustration",true,false) if card else null
	check(illustration!=null and illustration.is_visible_in_tree(),"Arrival shows the landing illustration (%s)"%tag)
	if illustration and illustration.motion:
		check(illustration.elapsed<illustration.ARRIVAL_SECONDS,"The boat begins its approach (%s)"%tag)
		await create_timer(illustration.ARRIVAL_SECONDS).timeout
		check(is_equal_approx(illustration.elapsed,illustration.ARRIVAL_SECONDS) and not illustration.is_processing(),"Landing finishes and stops animating (%s)"%tag)
		await shot("arrival_disembarked")
	elif illustration:
		check(is_equal_approx(illustration.elapsed,illustration.ARRIVAL_SECONDS) and not illustration.is_processing(),"Reduced motion uses the landed frame (%s)"%tag)
	if card!=null:
		for panel:Dictionary in hud_panels():
			if panel.name!=WanganUI.CARD:check(not card.get_global_rect().intersects(panel.rect),"Card clear of HUD %s (%s)"%[panel.name,tag])
	var image:=await shot("hud_tracker_full")
	if image!=null:
		var tracker_rect:=Rect2i(app.preview_tracker.get_global_rect().grow(6.0))
		tracker_rect=tracker_rect.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		var crop:=image.get_region(tracker_rect)
		var file:=output.path_join("%s_hud_tracker.png"%tag)
		check(crop.save_png(file)==OK,"tracker crop saved (%s)"%tag)
		DirAccess.remove_absolute(output.path_join("%s_hud_tracker_full.png"%tag))
	WanganUI.dismiss(app)
	# Plot marker through the first crop.
	await stand(VIEW_SPOT)
	check(step_id()=="till","At the view spot the step is till (%s): %s"%[tag,step_id()])
	check_tools(["hoe"],true)
	var expand:=app.preview_toolbar.find_child("AllToolsToggle",true,false) as Button
	if expand:
		expand.pressed.emit()
		await settle()
		check_tools(Shell.TOOL_IDS,true)
		expand.pressed.emit()
		await settle()
		check_tools(["hoe"],true)
	var default_text:int=app.sound.preferred_text_scale
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	await settle()
	check_tools(["hoe"],true)
	await shot("large-shortcuts")
	app.sound.preferred_text_scale=default_text
	app._apply_font_scale_tree()
	await settle()
	marker_ok(await shot("plot_empty"),"empty "+tag,true)
	await stand(WORK_SPOT)
	await perform("hoe",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="sow","Tilled (%s)"%tag)
	check_tools(["hoe","seed"],true)
	marker_ok(await shot("plot_tilled"),"tilled "+tag,true)
	var bag:Dictionary=person().inventory
	for item in bag.keys():
		if str(item).ends_with("_seed"):bag.erase(item)
	await refresh()
	check(step_id()=="buy_seed","Empty seed pouch points to the shop (%s)"%tag)
	var stall:Vector2i=World.Village.resident_cell(w.state,"xiaoli")
	var coins:=int(person().coins)
	await stand(Vector2(stall)+Vector2(0.5,1.5))
	await shot("restock_seeds")
	var shop_cue:Rect2=app.view.first_crop_cue_rect
	check(shop_cue.has_point(app.view.screen(Vector2(stall)+Vector2(0.5,0.5))),
		"The gold cue surrounds Xiaoli's stand (%s)"%tag)
	app._interact()
	await settle()
	var seed:Button=app.modal.find_child("StallBuy_radish",true,false) if is_instance_valid(app.modal) else null
	var offer:Button=app.modal.find_child("StallOffer",true,false) if is_instance_valid(app.modal) else null
	check(is_instance_valid(seed) and is_instance_valid(offer),"The interaction opens the real seed shop (%s)"%tag)
	if seed!=null and offer!=null:
		seed.pressed.emit()
		offer.pressed.emit()
	app._close_modal()
	await refresh()
	check(step_id()=="sow" and int(bag.get("radish_seed",0))==1 and int(person().coins)==coins-int(World.CROPS.radish.seed_price),
		"Buying one seed returns the cue to the tilled plot (%s)"%tag)
	await stand(WORK_SPOT)
	await perform("seed",WORK_CELL,"radish")
	await stand(VIEW_SPOT)
	check(step_id()=="water","Sown (%s)"%tag)
	check_tools(["hoe","seed","water"],true)
	var sown:=await shot("plot_sown")
	marker_ok(sown,"sown "+tag,true)
	check(step_corner_visible(sown,WORK_CELL),"The water cue marks the planted tile (%s)"%tag)
	var cue:Rect2=app.view.first_crop_cue_rect
	check(cue.has_area() and placements().all(func(entry):return not entry.rect.intersects(cue)),
		"World labels leave the marked crop visible (%s)"%tag)
	app.target=WORK_CELL
	app.view.show_target=true
	var before_remove: String=app.selected
	app._select_tool("remove")
	app._refresh_hud()
	check("收成後才能恢復草地" in app.selected_label.text,"Removal cursor warns before harvesting (%s)"%tag)
	app._select_tool(before_remove)
	await stand(WORK_SPOT)
	await perform("water",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="wait","Watered (%s)"%tag)
	var watered:=await shot("plot_watered")
	marker_ok(watered,"watered "+tag,true)
	check(not step_corner_visible(watered,WORK_CELL),"The cue clears while the plant grows (%s)"%tag)
	for i in 30:
		if float(w.state.crops[World.key(WORK_CELL)].growth)>=float(World.CROPS.radish.time):break
		w.step(5.0,true)
	await refresh()
	check(step_id()=="harvest","Mature (%s)"%tag)
	check_tools(["hoe","seed","water","harvest"],true)
	marker_ok(await shot("plot_mature"),"mature "+tag,true)
	await stand(WORK_SPOT)
	await perform("harvest",WORK_CELL)
	await stand(VIEW_SPOT)
	check(step_id()=="ship","Harvested (%s)"%tag)
	marker_ok(await shot("plot_harvested"),"harvested "+tag,true)
	await stand(WORK_SPOT)
	app.target=WORK_CELL
	app.view.show_target=true
	app._select_tool("remove")
	app._refresh_hud()
	check(app.selected_label.text=="空農田 · 點擊恢復草地","Empty field offers ground restoration (%s)"%tag)
	await shot("plot_restore_hint")
	await perform("remove",WORK_CELL)
	check(not w.state.crops.has(World.key(WORK_CELL)),"Removing an empty field restores the original ground (%s)"%tag)
	await shot("plot_restored")
	await stand(Vector2(42.5,32.5))
	await perform("ship",World.SHIPPING.cell_for(w.state),JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)]))
	check(bool(w.state.chapter_one.shipped),"Shipped (%s)"%tag)
	await stand(VIEW_SPOT)
	check_tools(Shell.TOOL_IDS,false)
	marker_ok(await shot("after_ship"),"after ship "+tag,false)
	check(str(app.objective.text).contains("到公告板按") and app.view.first_crop_cue_rect.has_point(
		app.view.screen(Vector2(40.5,29.5))),"First shipment points to the board and shows how to contribute (%s)"%tag)
	await stand(Vector2(40.5,30.5))
	await shot("bridge_board")
	person().inventory.merge({"wood":34,"stone":12},true)
	await refresh()
	app._interact()
	await settle()
	var donate:Button=app.modal.find_child("BoardDonateBridge",true,false) if is_instance_valid(app.modal) else null
	check(donate!=null and donate.text=="捐入 木材 30、石材 10","Board gives the capped contribution before confirmation (%s)"%tag)
	await shot("bridge_contribution")
	if donate!=null:donate.pressed.emit()
	await refresh()
	await settle()
	var aru:Vector2i=Chapter.STARTER_CELL
	check(w.state.board and str(app.objective.text).contains("找阿榆") and app.view.first_crop_cue_rect.has_point(
		app.view.screen(Vector2(aru)+Vector2(0.5,0.5))),"Completing the bridge moves the cue to Aru (%s)"%tag)
	check(person().inventory.wood==4 and person().inventory.stone==2,"Donation leaves surplus materials in the bag (%s)"%tag)
	check(is_instance_valid(app.modal) and app.modal.find_child("BoardServePicnic",true,false)!=null,"The board stays open and advances to the next project (%s)"%tag)
	app._close_modal()
	await stand(Vector2(aru)+Vector2(0.5,1.5))
	await shot("irrigation_aru")
	person().inventory.merge(Chapter.STARTER_COST,true)
	await refresh()
	app._interact()
	await settle()
	var controls:Dictionary=app.modal.get_meta("chapter_starter_controls",{}) if is_instance_valid(app.modal) else {}
	var claim:Button=controls.get("claim")
	check(claim!=null and claim.is_visible_in_tree() and not claim.disabled,
		"Aru opens directly to the available starter kit (%s)"%tag)
	if claim!=null:claim.pressed.emit()
	app._close_modal()
	await refresh()
	check(w.state.chapter_one.starter_claims.has(me) and int(person().inventory.get("sprinkler_kit",0))==1
		and not app.view.first_crop_cue_rect.has_area() and str(app.objective.text).contains("補滿水桶"),
		"After the trade the cue switches to connecting the kit (%s)"%tag)
	var tracker:Button=app.hud.find_child("TrackerNext",true,false)
	tracker.pressed.emit()
	await settle()
	var guide:Button=app.modal.find_child("ChapterStarterIrrigationGuide",true,false)
	check(guide!=null,"Chapter tracker offers the starter irrigation diagram (%s)"%tag)
	if guide:
		guide.pressed.emit()
		await settle()
		check(app.modal.get_meta("life_modal_layout","")=="workshop_guide" and app.get_meta("workshop_guide_topic",-1)==3,
			"Chapter link opens the starter setup, not the pump lesson (%s)"%tag)
	app._close_modal()
	await stand(Vector2(46.5,28.5))
	for entry in [[Vector2i(45,26),"water_tank"],[Vector2i(46,26),"water_pipe"],
		[Vector2i(47,26),"water_pipe"],[Vector2i(47,27),"sprinkler"]]:  # (48,26) is the reserved public-mill approach
		await perform("build",entry[0],entry[1])
	check(int(person().inventory.tank_kit)==0 and int(person().inventory.pipe_kit)==0
		and int(person().inventory.sprinkler_kit)==0,"The whole supplied kit is placed (%s)"%tag)
	person().inventory.radish_seed=1
	await stand(Vector2(48.5,28.5))
	await perform("hoe",Vector2i(48,27))
	await perform("seed",Vector2i(48,27),"radish")
	await stand(Vector2(47.5,28.5))
	app._interact()
	await settle()
	var dry_supply:Label=app.modal.find_child("SprinklerSupply",true,false)
	check(dry_supply!=null and dry_supply.text.contains("先給管網補水"),"Empty connected sprinkler sends the player to refill the network (%s)"%tag)
	app._close_modal()
	await stand(Vector2(44.5,26.5))
	app._interact()
	await settle()
	var refill:Button=null
	if is_instance_valid(app.modal):
		for button:Button in app.modal.find_children("*","Button",true,false):
			if button.text=="補滿儲水桶":refill=button
	check(refill!=null,"The installed tank can be filled through its panel (%s)"%tag)
	if refill!=null:refill.pressed.emit()
	app._close_modal()
	await stand(Vector2(47.5,28.5))
	app._interact()
	await settle()
	var ready_supply:Label=app.modal.find_child("SprinklerSupply",true,false)
	check(ready_supply!=null and ready_supply.text.contains("水源已接通") and ready_supply.text.contains("啟用後"),
		"Filled tank changes the sprinkler hint to enabling it (%s)"%tag)
	var enable:Button=null
	if is_instance_valid(app.modal):
		for button:Button in app.modal.find_children("*","Button",true,false):
			if button.text=="啟用":enable=button
	check(enable!=null,"The installed sprinkler can be enabled through its panel (%s)"%tag)
	if enable!=null:enable.pressed.emit()
	app._close_modal()
	check(w.step(8.0,true),"Advance the real irrigation schedule (%s)"%tag)
	await refresh()
	check(w.state.crops.get("48,27",{}).get("wet",false) and w.state.chapter_one.watered
		and Chapter.phase(w.state)=="meal","Network irrigation completes and advances to the picnic (%s)"%tag)
	await shot("irrigation_complete")
	var stove:=Vector2i(46,28)
	person().inventory.merge({"wood":12,"stone":15,"radish":2,"wheat":2},true)
	await stand(Vector2(46.5,29.5))
	await perform("build",stove,"stove")
	for dish in ["soup","bread"]:
		app._cook_menu(stove)
		await settle()
		var recipe:Button=app.modal.find_child("CookingRecipe_"+dish,true,false)
		var enqueue:Button=app.modal.find_child("CookingEnqueue",true,false)
		check(recipe!=null and enqueue!=null,"Recipe and cook action are present (%s, %s)"%[dish,tag])
		if recipe!=null:recipe.pressed.emit()
		await settle()
		if enqueue!=null:enqueue.pressed.emit()
		await refresh()
		if dish=="soup":
			check(str(app.objective.text).contains("小石灶料理中"),"The tracker identifies the cooking stage (%s)"%tag)
			app._close_modal()
			await shot("picnic_soup_cooking")
		check(w.step(float(World.RECIPES[dish].time)+0.2,true),"Advance cooking time (%s, %s)"%[dish,tag])
		await refresh()
		if dish=="soup":
			check(str(app.objective.text).contains("料理好了"),"The tracker reminds the player to collect (%s)"%tag)
			await shot("picnic_soup_ready")
			app._cook_menu(stove)
			await settle()
		var collect:Button=app.modal.find_child("CookingClaim",true,false)
		check(collect!=null and not collect.disabled,"Cooked dish is ready to collect (%s, %s)"%[dish,tag])
		if collect!=null:collect.pressed.emit()
		await refresh()
		app._close_modal()
		check(int(person().inventory.get(dish,0))==int(World.RECIPES[dish].yield),
			"Collected the recipe's exact yield (%s, %s)"%[dish,tag])
	preload("res://scripts/chapter_ui.gd").open(app)
	await settle()
	var meal_step:Dictionary=app.modal.get_meta("chapter_step",{})
	check(meal_step.get("meal_counts",{}).get("soup")==2 and meal_step.get("meal_counts",{}).get("bread")==1
		and meal_step.get("meal_counts",{}).get("radish")==0 and meal_step.get("meal_counts",{}).get("wheat")==0,
		"The letter reads the consumed ingredients and collected dishes (%s)"%tag)
	await shot("picnic_dishes_ready")
	app._close_modal()
	await stand(Vector2(40.5,30.5))
	check(str(app.objective.text).contains("到公告板按") and app.view.first_crop_cue_rect.has_point(
		app.view.screen(Vector2(40.5,29.5))),"Prepared dishes guide the player to the delivery board (%s)"%tag)
	await shot("picnic_delivery_cue")
	app._interact()
	await settle()
	var serve:Button=app.modal.find_child("BoardServePicnic",true,false) if is_instance_valid(app.modal) else null
	check(serve!=null and not serve.disabled,"The board accepts the cooked dishes (%s)"%tag)
	var portions:Label=app.modal.find_child("PicnicContributionHint",true,false)
	check(portions!=null and portions.text=="這次端上 %s ×2、%s ×1"%[World.NAMES.soup,World.NAMES.bread],
		"Cooked dishes are previewed before donating (%s)"%tag)
	await shot("picnic_contribution")
	if serve!=null:serve.pressed.emit()
	await refresh()
	check(serve.disabled and portions.text.contains("小栗"),"Completed board points to Xiaoli while still open (%s)"%tag)
	app._close_modal()
	await refresh()
	check(w.state.picnic and w.state.picnic_materials.soup==2 and w.state.picnic_materials.bread==1,
		"The first picnic opens with exactly the requested portions (%s)"%tag)
	await shot("picnic_complete")
	check(str(app.objective.text).contains("收下小栗的介紹信") and app.view.first_crop_cue_rect.has_area(),
		"Picnic completion points to Xiaoli's next chapter (%s)"%tag)
	await stand(Vector2(43.5,30.5))
	app._interact()
	await settle()
	var tea_link:Button=app.modal.find_child("XiaoliTeaOrder",true,false) if is_instance_valid(app.modal) else null
	check(tea_link!=null,"Xiaoli's shop exposes the tea order entry (%s)"%tag)
	if tea_link!=null:tea_link.pressed.emit()
	await settle()
	var intro:Button=app.modal.find_child("TeaIntro",true,false) if is_instance_valid(app.modal) else null
	check(intro!=null and not intro.disabled,"Xiaoli offers the next chapter's letter (%s)"%tag)
	if intro!=null:intro.pressed.emit()
	await refresh()
	check(app.session.snapshot.get("tea_ceramics",{}).get("own_record",{}).get("intro",false),
		"The real letter action starts the tea and pottery chapter (%s)"%tag)
	app._close_modal()
	await refresh()
	check(not app.view.first_crop_cue_rect.has_area(),"Reading the letter clears Xiaoli's cue (%s)"%tag)
	await shot("tea_letter_read")
	await close_world()
	# Occupied plot (another player's soil and floors).
	if not await open_world():return
	WanganUI.dismiss(app)
	neighbour="wangan-scene-neighbour"
	w.add_player(neighbour,"鄰居")
	var other:Dictionary=w.state.players[neighbour]
	other.inventory.wood=100;other.inventory.stone=100
	other.x=46.5;other.y=28.5
	var cells:=Chapter.STARTER_PLOT
	for i in 3:
		var result:Dictionary=w.act(neighbour,"scene-occupy-%d"%i,"hoe" if i%2==0 else "build",cells[i],"" if i%2==0 else "floor")
		check(result.ok,"Neighbour occupies %s (%s)"%[str(cells[i]),tag])
	other.x=50.5;other.y=33.5
	await stand(VIEW_SPOT)
	marker_ok(await shot("occupied_partial"),"occupied partial "+tag,true)
	other.x=46.5;other.y=28.5
	for i in range(3,cells.size()):
		var result:Dictionary=w.act(neighbour,"scene-occupy-%d"%i,"hoe" if i%2==0 else "build",cells[i],"" if i%2==0 else "floor")
		check(result.ok,"Neighbour occupies %s (%s)"%[str(cells[i]),tag])
	other.x=50.5;other.y=33.5
	await stand(VIEW_SPOT)
	check(Chapter.first_crop_step(app.session.snapshot,id).get("cell")==Chapter.NO_PLOT_CELL,"Fully occupied: no plot target (%s)"%tag)
	marker_ok(await shot("occupied_full"),"occupied full "+tag,false)
	await close_world()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/望安開場預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		await size_flow(size)
		print("NOTE size %dx%d done at %.1f s"%[size.x,size.y,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=22,"11 screenshots per size (%d)"%shots)
	finish()
