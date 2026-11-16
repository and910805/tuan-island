extends SceneTree
## T067 共餐桌保溫底座 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/保溫底座預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness as
## test_souvenir_exchange_scene.gd.
##
## Art is runtime-painted, no new PNGs: the base = community_art.draw_warmer (a 38×12
## warm-amber slab with a copper band under the 32px table, copper corner caps beside
## it); the item = inventory_item_art.warm_stone_icon() (32×32).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic / state.community={"table":"39,30"} written directly;
##    state.table_warmer ERASED directly before each size (un-install);
##  * bags written directly (warm_stone / copper_joint / stone / trout_hotpot /
##    watermelon_platter);
##  * the local player is teleported by writing x/y.
## REALLY EXERCISED: app._interact() at the table opens the page; 加裝保溫底座 /
##  保溫上桌六份 / 領一份 / 上桌四份 pressed by emitting `pressed` (real Session.perform
##  → World → snapshot → page and world update); the backpack is the real InventoryPanel.
## SHOTS per size (11): world_before, world_installed, world_installed_focus,
##  world_warm_six, world_warm_five, page_short, page_ready, page_installed,
##  page_warm_six, page_both, inventory_warm_stone; plus icons.png (once) — the
##  warm stone next to stone / ochre_earth / clay / charcoal at 4×.
const World=preload("res://scripts/world.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const UI=preload("res://scripts/community_ui.gd")
const Art=preload("res://scripts/community_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const TABLE:=Vector2i(39,30)
## West of the table: the table is focused, the local player stands clear of the base.
const FOCUS_SPOT:=Vector2(38.0,31.5)
## South-east viewing spot: table, base and plaza labels in view, player clear of them.
const VIEW_SPOT:=Vector2(41.2,31.7)
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("TABLE_WARMER_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step] if not tag.is_empty() else "%s.png"%step)
	check(image.save_png(file)==OK,"native screenshot saved %s"%file.get_file())
	shots+=1
	print("TABLE_WARMER_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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
	save_image(image,step)
	return image

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==UI.LAYOUT

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func hotpot()->Dictionary:
	return w.state.community.get("hotpot",{})

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func set_bag(values:Dictionary)->void:
	for item:String in values:bag()[item]=int(values[item])  # PRESET
	await refresh()

func open_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await stand(FOCUS_SPOT)
	check(str(app.view.interaction_focus())=="community","Table focused from the west (%s): %s"%[tag,str(app.view.interaction_focus())])
	app._interact()
	await settle()
	check(page_open(),"Interact at the table opens the page (%s)"%tag)

func page_fits(label:String)->void:
	check(page_open(),"Page open (%s)"%label)
	if not page_open():return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer page needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the page: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the page: 「%s」 (%s)"%[b.text,label])

# ------------------------------------------------------------- world view --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

func box_difference(a:Image,b:Image,box:Rect2i)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 0.0
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var changed:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(box.size.x*box.size.y)

## Share of pixels in `box` painted in the base's own palette (amber top, burnt-orange
## front, highlight, copper band / caps, dark edge), within a small tolerance.
func amber_share(image:Image,box:Rect2i)->float:
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var palette:=[Art.WARM_TOP,Art.WARM_FRONT,Art.WARM_LIGHT,Art.WARM_DARK,Art.WARM_EDGE,Art.COPPER,Art.COPPER_LIGHT,Art.COPPER_DARK,Art.WARM_GLOW,Art.WARM_SEAM]
	var hits:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			for p:Color in palette:
				if absf(c.r-p.r)+absf(c.g-p.g)+absf(c.b-p.b)<0.09:
					hits+=1
					break
	return float(hits)/float(box.size.x*box.size.y)

## 4× crop around the table (base, table top, neighbours) for review.
func save_crop(image:Image,step:String)->void:
	var box:=pixel_box(Rect2(table_origin()+Vector2(-40,-48),Vector2(112,96))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*3,box.size.y*3,Image.INTERPOLATE_NEAREST)
	save_image(crop,step)

func table_origin()->Vector2:
	return app.view.screen(Vector2(TABLE))

## The base in view coordinates (the slab, including the 3px beyond each side).
func base_rect()->Rect2:
	return Rect2(table_origin()+Art.WARMER_RECT.position,Art.WARMER_RECT.size)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func hud_panels()->Array:
	var result:=[]
	if not is_instance_valid(app.hud) or not (app.hud as CanvasItem).is_visible_in_tree():return result
	var area:=Vector2(root.size).x*Vector2(root.size).y
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		if c.size.x*c.size.y>area*0.5:continue
		result.append({"name":str(c.name),"rect":c.get_global_rect()})
	return result

## Base on screen, clear of HUD panels; no world label (resident name tags, the table
## label, prompts) overlaps the base and the table label stays placed.
func world_ok(label:String,expect_table_label:bool)->void:
	var list:=placements()
	var ids:=PackedStringArray()
	var table_label:={}
	for entry:Dictionary in list:
		ids.append("%s「%s」%s"%[str(entry.id),str(entry.title),str(entry.rect)])
		if str(entry.id)=="community":table_label=entry
	print("NOTE %s labels: %s"%[label,", ".join(ids)])
	var base:=base_rect()
	var base_px:=view_to_pixels(base)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(base_px),"Whole base on screen (%s) %s"%[label,str(base_px)])
	for panel:Dictionary in hud_panels():check(not base_px.intersects(panel.rect),"Base clear of HUD %s (%s)"%[panel.name,label])
	for entry:Dictionary in list:check(not (entry.rect as Rect2).intersects(base.grow(-1.0)),"Label 「%s」 not over the base (%s) %s vs %s"%[entry.title,label,str(entry.rect),str(base)])
	if expect_table_label:
		check(not table_label.is_empty(),"Table prompt placed (%s)"%label)
		if not table_label.is_empty():
			check(view_to_pixels(table_label.rect).intersects(Rect2(Vector2.ZERO,Vector2(root.size))),"Table prompt on screen (%s)"%label)

## Ignoring the player sprite: the base pixels look as painted (no later sprite on top).
func base_uncovered(image:Image,label:String)->void:
	var box:=pixel_box(base_rect())
	var share:=amber_share(image,box)
	print("NOTE %s: amber share in the base box %.0f%%"%[label,share*100.0])
	check(share>=0.45,"Base visible as warm amber (%s): %.0f%%"%[label,share*100.0])

# ------------------------------------------------------------------ flows --

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.erase("table_warmer")  # PRESET
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
	for item in ["warm_stone","copper_joint","stone","trout_hotpot","watermelon_platter"]:bag()[item]=0  # PRESET
	app.view.reduced_motion=false
	await refresh()

func size_flow()->void:
	await reset()
	# World before installing.
	await stand(VIEW_SPOT)
	var before:Image=await shot("world_before")
	save_crop(before,"crop_before")
	# The plain table's own wood shares a few of these colours (~17%); the base adds ~45 points.
	check(amber_share(before,pixel_box(base_rect()))<0.25,"No amber base before installing (%s): %.0f%%"%[tag,amber_share(before,pixel_box(base_rect()))*100.0])
	world_ok("before "+tag,false)
	# Page: not installed, short.
	await set_bag({"warm_stone":2,"copper_joint":1,"stone":4})
	await open_page()
	await shot("page_short")
	page_fits("short "+tag)
	check((control("WarmerInstall") as Button).disabled and label_text("WarmerReason").contains("暖岩片 4"),"Short page explains the shortfall (%s): %s"%[tag,label_text("WarmerReason")])
	app._close_modal()
	# Page: ready.
	await set_bag({"warm_stone":6,"copper_joint":2,"stone":4})
	await open_page()
	await shot("page_ready")
	page_fits("ready "+tag)
	await press("WarmerInstall")
	check(Warmer.installed(w.state),"Installed through the page (%s)"%tag)
	await shot("page_installed")
	page_fits("installed "+tag)
	check(label_text("WarmerStatus")==UI.STATUS_DONE,"Installed state on the page (%s)"%tag)
	app._close_modal()
	# World after installing.
	await stand(VIEW_SPOT)
	var installed:Image=await shot("world_installed")
	save_crop(installed,"crop_installed")
	var drawn:=box_difference(before,installed,pixel_box(base_rect()))
	print("NOTE %s: base box changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.3,"Base drawn at the table (%.0f%% changed) %s"%[drawn*100.0,tag])
	base_uncovered(installed,"installed "+tag)
	world_ok("installed "+tag,false)
	# Static from frame to frame (motion on) and with reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(box_difference(installed,root.get_texture().get_image(),pixel_box(base_rect()))<=0.01,"Base static with motion on (%s)"%tag)
	app.view.reduced_motion=true
	var still_a:Image=await grab()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(box_difference(still_a,root.get_texture().get_image(),pixel_box(base_rect()))<=0.01,"Base static with reduced motion (%s)"%tag)
	check(amber_share(still_a,pixel_box(base_rect()))>=0.45,"Base drawn with reduced motion too (%s)"%tag)
	app.view.reduced_motion=false
	# Focused: the table prompt and the base together.
	await stand(FOCUS_SPOT)
	var focused:Image=await shot("world_installed_focus")
	base_uncovered(focused,"focused "+tag)
	world_ok("focused "+tag,true)
	# A warm round of six.
	await set_bag({"trout_hotpot":6,"watermelon_platter":4})
	await open_page()
	await press("HotpotWarm")
	check(hotpot()=={"portions":6,"claimed":{},"total":6},"Warm round of six on the table (%s): %s"%[tag,str(hotpot())])
	await shot("page_warm_six")
	page_fits("warm six "+tag)
	check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 6 / 6 份","Page shows 剩 6 / 6 份 (%s): %s"%[tag,label_text("DishText_hotpot")])
	app._close_modal()
	await stand(VIEW_SPOT)
	var six:Image=await shot("world_warm_six")
	save_crop(six,"crop_warm_six")
	var top_box:=pixel_box(Rect2(table_origin()+Vector2(2,10),Vector2(28,12)))
	check(box_difference(installed,six,top_box)>=0.08,"Hotpot and bowls drawn on the warm table (%s): %.0f%%"%[tag,box_difference(installed,six,top_box)*100.0])
	base_uncovered(six,"six "+tag)
	world_ok("six "+tag,false)
	# Claim one: the bowl row changes (6 -> 5 visible bowls).
	await open_page()
	await press("DishMain_hotpot")
	check(int(hotpot().get("portions",0))==5,"Claimed one (%s)"%tag)
	await press("DishMain_watermelon")
	check(int(w.state.community.get("watermelon",{}).get("portions",0))==4,"Watermelon on the table too (%s)"%tag)
	await shot("page_both")
	page_fits("both "+tag)
	check(label_text("DishText_hotpot").contains("剩 5 / 6 份") and label_text("DishText_watermelon").contains("剩 4 / 4 份"),"Both dishes listed (%s)"%tag)
	app._close_modal()
	await stand(VIEW_SPOT)
	var five:Image=await shot("world_warm_five")
	save_crop(five,"crop_warm_five")
	var bowls:=pixel_box(Rect2(table_origin()+Vector2(3,17),Vector2(26,4)))
	check(box_difference(six,five,bowls)>0.0,"Bowl markers change as the warm round is claimed (%s)"%tag)
	base_uncovered(five,"five "+tag)
	world_ok("five "+tag,false)
	# Backpack with 暖岩片.
	await set_bag({"warm_stone":3})
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack open (%s)"%tag)
	if app.modal is InventoryPanel:
		app.modal.select_item("warm_stone")
		await settle()
		var slot=app.modal.slots.get("warm_stone")
		check(slot!=null and slot.visible,"暖岩片 slot shown (%s)"%tag)
		if slot!=null:(slot as Control).grab_focus()
		await settle()
		check(str(app.modal.selected_id)=="warm_stone" and app.modal.detail_name.text=="暖岩片","暖岩片 selected (%s)"%tag)
		await shot("inventory_warm_stone")
	app._close_modal()
	await settle()

## Icon checks and a 4× comparison strip (warm stone, stone, ochre earth, clay, charcoal).
func icon_flow()->void:
	var ids:=["warm_stone","stone","ochre_earth","clay","charcoal","bread"]
	var images:={}
	for item:String in ids:
		var tex:=Items.icon(item)
		check(tex!=null,"Icon exists: %s"%item)
		if tex==null:continue
		var image:=tex.get_image()
		if image.is_compressed():image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		images[item]=image
	if not images.has("warm_stone"):return
	var warm:Image=images.warm_stone
	check(warm.get_size()==Vector2i(32,32),"暖岩片 icon is 32×32")
	var hue:=0.0;var sat:=0.0;var count:=0
	for x in 32:
		for y in 32:
			var c:=warm.get_pixel(x,y)
			if c.a<0.9 or c.v<0.45:continue
			hue+=c.h;sat+=c.s;count+=1
	hue/=maxf(1.0,count);sat/=maxf(1.0,count)
	print("NOTE warm_stone icon: %d bright pixels, mean hue %.3f sat %.2f"%[count,hue,sat])
	check(count>=150 and hue>=0.05 and hue<=0.14 and sat>=0.5,"暖岩片 icon reads warm amber-orange (hue %.3f sat %.2f)"%[hue,sat])
	for other:String in ["stone","ochre_earth","clay","charcoal","bread"]:
		if not images.has(other):continue
		var b:Image=images[other]
		var differ:=0
		for x in 32:
			for y in 32:
				var p:=warm.get_pixel(x,y);var q:=b.get_pixel(x,y)
				if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)+absf(p.a-q.a)>0.3:differ+=1
		var share:=float(differ)/1024.0
		print("NOTE warm_stone vs %s icon: %.0f%% pixels differ"%[other,share*100.0])
		check(share>=0.3,"暖岩片 icon differs from %s (%.0f%%)"%[other,share*100.0])
	var strip:=Image.create(ids.size()*136+8,144,false,Image.FORMAT_RGBA8)
	strip.fill(Color("f3e6c8"))
	for i in ids.size():
		if not images.has(ids[i]):continue
		var big:Image=(images[ids[i]] as Image).duplicate()
		big.resize(128,128,Image.INTERPOLATE_NEAREST)
		strip.blend_rect(big,Rect2i(0,0,128,128),Vector2i(8+i*136,8))
	tag=""
	save_image(strip,"icons")

func run()->void:
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/保溫底座預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("table-warmer-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"保溫旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	# The fresh host shows the 望安 arrival card over the top of the plaza; close it
	# directly (a player closes it with E / Esc; covered in test_table_warmer_ui).
	WanganUI.dismiss(app)
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	icon_flow()
	check(shots>=31,"15 screenshots per size plus the icon strip (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
