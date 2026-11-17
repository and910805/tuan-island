extends SceneTree
## 玉米濃湯 (corn_chowder) as the third shared dish on 渡口的共餐桌 — native render check at
## 1024×640 and 1280×800. Run non-headless:
##   --script res://tests/test_corn_chowder_scene.gd -- --profile=isolated-regression
## Screenshots go to outputs/玉米濃湯預覽 (or --capture-dir=), named <w>x<h>_<step>.png;
## icons.png and probe_tureen.png (once, ×8, no size prefix). Same harness as
## test_table_warmer_scene.gd / test_tea_service_scene.gd.
##
## The page row uses the dedicated corn-chowder.png icon
## (32×32), the table tureen = community_art.draw_chowder (10×7 at CHOWDER_RECT, one kernel
## dot per portion left, max 4) drawn by draw_table's trailing `chowder` argument from
## world_view's table block.
##
## PRESET / FIXTURE (not human play, nothing here goes through a player action):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic / state.community (table cell; hotpot / watermelon /
##    chowder rounds; "claimed" holds my token plus made-up "chowder-guest-*" tokens that
##    are NOT world players) written directly;
##  * state.table_warmer written / erased directly; state.tea_service written / erased
##    directly (a fresh deep round lent by me for the crowded world shot);
##  * my bag's trout_hotpot / watermelon_platter / corn_chowder written directly;
##  * the local player is teleported by writing x/y; app.view.reduced_motion set directly
##    (on for every world comparison, so steam / feedback do not differ);
##  * the page is opened with app._community_menu() (CommunityUI.open, what the interact
##    key reaches at the table) and closed with app._close_modal().
## REALLY EXERCISED: Session._send_snapshot (community.<dish>.claimed → claimed_own) → the
##  real community_ui page (build + refresh + main._layout_preview) on the native renderer;
##  the real world_view table block → community_art.draw_table(...,chowder) and the focused
##  「community」 label from world_view.world_label_placements.
## NOT EXERCISED: serve / claim actions, cooking corn_chowder, keyboard / gamepad input.
##
## SHOTS per size (11): page_bag0, page_bag4, page_served4, page_claimed3, page_all3,
##  world_plain, world_chowder4, crop_chowder4 (×8), crop_chowder1 (×8), world_crowded,
##  crop_crowded (×8). Once: icons (corn_chowder / soup / salad ×8), probe_tureen (×8 strip
##  of the offscreen tureen for 0..4 portions) → 24 in total.
const World=preload("res://scripts/world.gd")
const TeaService=preload("res://scripts/tea_service.gd")
const Art=preload("res://scripts/community_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const CommunityUI=preload("res://scripts/community_ui.gd")
const PK=preload("res://scripts/public_kitchen.gd")
const TABLE:=Vector2i(39,30)
## West of the table: the table is focused (same spot as test_table_warmer_scene).
const FOCUS_SPOT:=Vector2(38.0,31.5)
## South-east viewing spot: table and plaza in view, player clear of the table.
const VIEW_SPOT:=Vector2(41.2,31.7)
## The table cell neighbourhood (view px, relative to the cell origin) compared outside
## the tureen and cropped ×8 for review: the 32px cell, the tureen above its top edge,
## the warmer slab below it.
const CELL_REGION:=Rect2(-6,-10,44,44)
const DISH_IDS:=["DishMain_hotpot","HotpotWarm","DishMain_watermelon","DishMain_chowder"]
const HOTPOT_NONE:="雪點鱒魚火鍋 · 還沒上桌・背包 0 份"
const MELON_NONE:="夏日西瓜盤 · 還沒上桌・背包 0 份"
## Offscreen probe: viewport size and where the table cell origin sits in it.
const PROBE_SIZE:=Vector2i(72,64)
const PROBE_ORIGIN:=Vector2(30,22)
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
var written:=PackedStringArray()
var probe_view:SubViewport
var probe_node:Node2D
var probe_variant:=""

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("CORN_CHOWDER_FILES %d"%written.size())
	for file in written:print("CORN_CHOWDER_FILE %s"%file)
	print("CORN_CHOWDER_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	written.append(file)
	print("CORN_CHOWDER_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

func person()->Dictionary:
	return w.state.players[id]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

func colour_near(a:Color,b:Color)->bool:
	return absf(a.r-b.r)<=0.02 and absf(a.g-b.g)<=0.02 and absf(a.b-b.b)<=0.02

# ------------------------------------------------------------------ state --

## Server-shaped round: `portions` left; `mine` adds my token to "claimed"; the other
## claimed seats use made-up tokens (FIXTURE, not world players).
func meal(portions:int,mine:bool=false,total:int=4)->Dictionary:
	var claimed:={}
	var taken:int=total-portions
	if mine:
		claimed[id]=true
		taken-=1
	for i in range(maxi(0,taken)):claimed["chowder-guest-%d"%i]=true
	var record:Dictionary={"portions":portions,"claimed":claimed}
	if total!=4:record["total"]=total
	return record

func set_community(meals:Dictionary)->void:
	var record:Dictionary={"table":World.COMMUNITY.cell_key(TABLE)}
	for dish:String in meals:record[dish]=(meals[dish] as Dictionary).duplicate(true)
	w.state.community=record  # PRESET
	await refresh()

func set_warmer(on:bool)->void:
	if on:w.state.table_warmer={"installed":true}  # PRESET
	else:w.state.erase("table_warmer")  # PRESET

func set_tea(on:bool)->void:
	if on:w.state[TeaService.STATE_KEY]={"lender":id,"round":{"style":"deep","portions":6,"claimed":{},"day":TeaService.today(w.state)}}  # PRESET
	else:w.state.erase(TeaService.STATE_KEY)  # PRESET

func set_bag(values:Dictionary)->void:
	var bag:Dictionary=person().inventory
	for item:String in values:
		if int(values[item])>0:bag[item]=int(values[item])  # PRESET
		else:bag.erase(item)  # PRESET

# ------------------------------------------------------------------- page --

func page_open()->bool:
	return CommunityUI.is_open(app) and str((app.modal as Node).get_meta("life_modal_layout",""))==CommunityUI.LAYOUT

func page_node(node_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(node_name,true,false) as Control

func page_shown(node_name:String)->bool:
	var c:=page_node(node_name)
	return c!=null and c.is_visible_in_tree()

func page_text(node_name:String)->String:
	var l:=page_node(node_name) as Label
	return l.text if l!=null else ""

func open_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	app._community_menu()
	await settle()
	await settle()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	check(not is_instance_valid(app.modal),"Page closed (%s)"%tag)

## Screenshot pixels of a control (canvas → viewport → window transform).
func screen_rect(c:Control)->Rect2i:
	var xf:Transform2D=root.get_final_transform()*c.get_global_transform_with_canvas()
	var a:Vector2=xf*Vector2.ZERO
	var b:Vector2=xf*c.size
	return Rect2i(Vector2i(a.round()),Vector2i((b-a).round()))

## Exact texts of the three dish rows and the chowder button state.
func page_state(label:String,hotpot:String,melon:String,chowder:String,button:String,disabled:bool)->void:
	check(page_text("DishText_hotpot")==hotpot,"Hotpot row text (%s): 「%s」 want 「%s」"%[label,page_text("DishText_hotpot"),hotpot])
	check(page_text("DishText_watermelon")==melon,"Watermelon row text (%s): 「%s」 want 「%s」"%[label,page_text("DishText_watermelon"),melon])
	check(page_text("DishText_chowder")==chowder,"Chowder row text (%s): 「%s」 want 「%s」"%[label,page_text("DishText_chowder"),chowder])
	var b:=page_node("DishMain_chowder") as Button
	check(b!=null,"DishMain_chowder exists (%s)"%label)
	if b==null:return
	check(b.is_visible_in_tree(),"DishMain_chowder shown (%s)"%label)
	check(b.text==button,"Chowder button caption (%s): 「%s」 want 「%s」"%[label,b.text,button])
	check(b.disabled==disabled,"Chowder button %s (%s)"%["disabled" if disabled else "enabled",label])
	var icon:=page_node("DishIcon_chowder")
	check(icon!=null and icon.is_visible_in_tree() and icon.size.x>=16.0,"Chowder row icon shown (%s)"%label)

## Modal inside the window, no scrolling, every label / button whole, the three dish
## buttons inside their rows and not overlapping.
func page_fits(state:String)->void:
	var label:="%s %s"%[state,tag]
	check(page_open(),"渡口的共餐桌 page open (%s)"%label)
	if not page_open():return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Page inside the window (%s) %s"%[label,str(modal.get_global_rect())])
	var outer:=page_node("ModalScroll") as ScrollContainer
	check(outer!=null,"ModalScroll exists (%s)"%label)
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Page needs no scrolling (%s): max %.1f page %.1f"%[label,outer.get_v_scroll_bar().max_value,outer.get_v_scroll_bar().page])
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the page: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the page: 「%s」 (%s)"%[b.text,label])
	var rects:Array[Rect2]=[]
	var names:=PackedStringArray()
	for button_id:String in DISH_IDS:
		var b:=page_node(button_id) as Button
		if button_id!="HotpotWarm":check(b!=null and b.is_visible_in_tree(),"%s shown (%s)"%[button_id,label])
		if b==null or not b.is_visible_in_tree():continue
		var dish:String=button_id.trim_prefix("DishMain_") if button_id.begins_with("DishMain_") else "hotpot"
		var row:=page_node("Dish_"+dish)
		check(row!=null and row.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s inside row Dish_%s (%s) %s vs %s"%[button_id,dish,label,str(b.get_global_rect()),str(row.get_global_rect()) if row!=null else "null"])
		rects.append(b.get_global_rect())
		names.append(button_id)
	for i in range(rects.size()):
		for j in range(i+1,rects.size()):
			check(not rects[i].grow(-0.5).intersects(rects[j].grow(-0.5)),"%s and %s do not overlap (%s)"%[names[i],names[j],label])
	var rows:Array[Rect2]=[]
	for dish:String in CommunityUI.DISH_ORDER:
		var row:=page_node("Dish_"+dish)
		check(row!=null and row.is_visible_in_tree(),"Row Dish_%s shown (%s)"%[dish,label])
		if row!=null:rows.append(row.get_global_rect())
	for i in range(rows.size()):
		for j in range(i+1,rows.size()):
			check(not rows[i].grow(-0.5).intersects(rows[j].grow(-0.5)),"Dish rows %d and %d do not overlap (%s)"%[i,j,label])

func changed_pixels(a:Image,b:Image,box:Rect2i)->int:
	if a==null or b==null or a.get_size()!=b.get_size():return -1
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if box.size.x<=0 or box.size.y<=0:return -1
	var changed:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return changed

## Pixels changed inside `region` but outside `exclude` (any difference counts).
func changed_outside(a:Image,b:Image,region:Rect2i,exclude:Rect2i)->int:
	if a==null or b==null or a.get_size()!=b.get_size():return -1
	region=region.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if region.size.x<=0 or region.size.y<=0:return -1
	var changed:=0
	for x in range(region.position.x,region.end.x):
		for y in range(region.position.y,region.end.y):
			if exclude.has_point(Vector2i(x,y)):continue
			if a.get_pixel(x,y)!=b.get_pixel(x,y):changed+=1
	return changed

func page_flow()->void:
	app.view.reduced_motion=true
	set_warmer(false)
	set_tea(false)
	# 1. Chowder not served, bag 0: 上桌四份 disabled; 保溫底座 un-installed + 茶陶上桌 (tallest).
	set_bag({"trout_hotpot":0,"watermelon_platter":0,"corn_chowder":0})
	await set_community({})
	await open_page()
	check(page_shown("WarmerCard") and page_shown("WarmerMaterials") and page_shown("WarmerSource"),"Un-installed 保溫底座 card with materials shown (%s)"%tag)
	check(page_shown("TeaCard"),"茶陶上桌 card shown (%s)"%tag)
	page_state("bag0 "+tag,HOTPOT_NONE,MELON_NONE,"玉米濃湯 · 還沒上桌・背包 0 份",CommunityUI.PLAIN_SERVE,true)
	var bag0:Image=await shot("page_bag0")
	page_fits("bag0")
	var button:=page_node("DishMain_chowder")
	var box0:Rect2i=screen_rect(button) if button!=null else Rect2i()
	await close_page()
	# 2. Bag 4: 上桌四份 enabled.
	set_bag({"corn_chowder":4})
	await refresh()
	await open_page()
	page_state("bag4 "+tag,HOTPOT_NONE,MELON_NONE,"玉米濃湯 · 還沒上桌・背包 4 份",CommunityUI.PLAIN_SERVE,false)
	var bag4:Image=await shot("page_bag4")
	page_fits("bag4")
	button=page_node("DishMain_chowder")
	var box4:Rect2i=screen_rect(button) if button!=null else Rect2i()
	# The disabled caption style is a few px narrower (same for the older dish buttons);
	# the button stays right-aligned on the same line.
	check(box0.end.x==box4.end.x and box0.position.y==box4.position.y and box0.size.y==box4.size.y and box0.size.x>0,"Chowder button on the same line and right edge with bag 0 / 4 (%s) %s vs %s"%[tag,str(box0),str(box4)])
	var button_px:=changed_pixels(bag0,bag4,box4)
	print("NOTE %s: chowder button disabled→enabled %d px changed in %s"%[tag,button_px,str(box4)])
	check(button_px>=20,"Disabled and enabled chowder button differ in pixels (%d px) %s"%[button_px,tag])
	await close_page()
	# 3. Served 4/4.
	set_bag({"corn_chowder":0})
	await set_community({"chowder":meal(4)})
	await open_page()
	page_state("served4 "+tag,HOTPOT_NONE,MELON_NONE,"玉米濃湯 · 剩 4 / 4 份",CommunityUI.CLAIM,false)
	await shot("page_served4")
	page_fits("served4")
	await close_page()
	# 4. 3/4, I already claimed.
	await set_community({"chowder":meal(3,true)})
	var snap_meal:Variant=app.session.snapshot.get("community",{}).get("chowder",{})
	check(snap_meal is Dictionary and (snap_meal as Dictionary).get("claimed_own",false)==true and not (snap_meal as Dictionary).has("claimed"),"Snapshot carries claimed_own, no token list (%s): %s"%[tag,str(snap_meal)])
	await open_page()
	page_state("claimed3 "+tag,HOTPOT_NONE,MELON_NONE,"玉米濃湯 · 剩 3 / 4 份・你已領過",CommunityUI.CLAIM,true)
	await shot("page_claimed3")
	page_fits("claimed3")
	await close_page()
	# 5. All three dishes on the table.
	await set_community({"hotpot":meal(4),"watermelon":meal(4),"chowder":meal(4)})
	await open_page()
	page_state("all3 "+tag,"雪點鱒魚火鍋 · 剩 4 / 4 份","夏日西瓜盤 · 剩 4 / 4 份","玉米濃湯 · 剩 4 / 4 份",CommunityUI.CLAIM,false)
	for dish:String in ["hotpot","watermelon"]:
		var b:=page_node("DishMain_"+dish) as Button
		check(b!=null and b.text==CommunityUI.CLAIM and not b.disabled,"%s button 領一份 enabled (%s)"%[dish,tag])
	await shot("page_all3")
	page_fits("all3")
	await close_page()

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

## Screen pixels per view pixel (the world zoom as rendered).
func px_scale()->float:
	return maxf(1.0,view_to_pixels(Rect2(0,0,10,10)).size.x/10.0)

func table_origin()->Vector2:
	return app.view.screen(Vector2(TABLE))

func cell_rect(local:Rect2)->Rect2:
	return Rect2(table_origin()+local.position,local.size)

func tureen_box()->Rect2i:
	return pixel_box(cell_rect(Art.CHOWDER_RECT))

## The tureen box grown by about one view pixel (edge filtering at fractional zoom).
func tureen_exclude()->Rect2i:
	return tureen_box().grow(int(ceilf(px_scale()))+1)

func region_box()->Rect2i:
	return pixel_box(cell_rect(CELL_REGION))

## ×8 nearest-neighbour crop of the table cell region for review.
func save_crop(image:Image,step:String)->void:
	if image==null or image.is_empty():return
	var box:=region_box().intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	check(box.size.x>0 and box.size.y>0,"Crop region on screen (%s_%s) %s"%[tag,step,str(box)])
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*8,box.size.y*8,Image.INTERPOLATE_NEAREST)
	save_image(crop,step)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func table_label_title()->String:
	for entry:Dictionary in placements():
		if str(entry.id)=="community":return str(entry.title)
	return ""

## Tureen on screen and no world label over it (VIEW_SPOT shots).
func tureen_clear(label:String)->void:
	var r:=view_to_pixels(cell_rect(Art.CHOWDER_RECT))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(r),"Whole tureen on screen (%s) %s"%[label,str(r)])
	var inner:=cell_rect(Art.CHOWDER_RECT).grow(-1.0)
	for entry:Dictionary in placements():
		check(not (entry.rect as Rect2).intersects(inner),"Label 「%s」 not over the tureen (%s) %s vs %s"%[entry.title,label,str(entry.rect),str(inner)])

## chowder=0 vs chowder>0 (same other inputs): the tureen box changes, nothing else in the
## table cell region does.
func compare(without:Image,served:Image,label:String)->void:
	var box:=tureen_box()
	var inside:=changed_pixels(without,served,box)
	var share:=float(maxi(0,inside))/float(maxi(1,box.size.x*box.size.y))
	var outside:=changed_outside(without,served,region_box(),tureen_exclude())
	print("NOTE %s: tureen box %s changed %d px (%.0f%%), %d px changed outside it in %s"%[label,str(box),inside,share*100.0,outside,str(region_box())])
	# Nearer dishes (bread, watermelon tray) cover the tureen's lower rows.
	check(share>=0.3,"Tureen drawn in CHOWDER_RECT (%s): %.0f%% changed"%[label,share*100.0])
	check(outside==0,"Rest of the table cell identical with / without chowder (%s): %d px"%[label,outside])

func world_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	app.view.reduced_motion=true
	set_warmer(false)
	set_tea(false)
	await set_community({})
	await stand(VIEW_SPOT)
	var s:=px_scale()
	print("NOTE %s: %.2f screen px per view px, tureen box %s, region %s"%[tag,s,str(tureen_box()),str(region_box())])
	var plain:Image=await shot("world_plain")
	# Chowder only, 4 portions.
	await set_community({"chowder":meal(4)})
	var view_meal:Variant=app.view.data.get("community",{}).get("chowder",{})
	check(view_meal is Dictionary and int((view_meal as Dictionary).get("portions",0))==4,"View snapshot has chowder 4 (%s): %s"%[tag,str(view_meal)])
	var four:Image=await shot("world_chowder4")
	save_crop(four,"crop_chowder4")
	tureen_clear("chowder4 "+tag)
	compare(plain,four,"plain→chowder4 "+tag)
	var steam_box:=pixel_box(cell_rect(Rect2(21,-7,10,10)))
	var previous_elapsed:float=app.view.elapsed
	var was_processing:bool=app.view.is_processing()
	app.view.set_process(false)
	app.view.reduced_motion=false
	app.view.elapsed=0.0
	app.view.queue_redraw()
	var hot:Image=await shot("world_chowder_steam")
	app.view.elapsed=0.7
	app.view.queue_redraw()
	var later:Image=await grab()
	check(changed_pixels(hot,later,steam_box)>0,"Chowder steam moves above the tureen (%s)"%tag)
	app.view.reduced_motion=true
	app.view.queue_redraw()
	var still:Image=await grab()
	check(changed_pixels(four,still,steam_box)==0,"Reduced motion keeps the area above the tureen still (%s)"%tag)
	app.view.elapsed=previous_elapsed
	app.view.set_process(was_processing)
	# Chowder only, 1 portion: three kernel dots fewer.
	await set_community({"chowder":meal(1)})
	var one:Image=await grab()
	save_crop(one,"crop_chowder1")
	compare(plain,one,"plain→chowder1 "+tag)
	var kernels:=changed_pixels(one,four,tureen_box())
	print("NOTE %s: chowder 1→4 changed %d px in the tureen box (3 dots ≈ %.0f px)"%[tag,kernels,3.0*s*s])
	check(kernels>=int(2.0*s*s),"Kernel dots change between 1 and 4 portions (%d px) %s"%[kernels,tag])
	check(changed_outside(one,four,region_box(),tureen_exclude())==0,"Only the tureen changes between 1 and 4 portions (%s)"%tag)
	# Focused label.
	await stand(FOCUS_SPOT)
	check(str(app.view.interaction_focus())=="community","Table focused from the west (%s): %s"%[tag,str(app.view.interaction_focus())])
	check(table_label_title()=="濃湯 1","Focused label 濃湯 1 (%s): 「%s」"%[tag,table_label_title()])
	await set_community({"chowder":meal(4)})
	check(table_label_title()=="濃湯 4","Focused label 濃湯 4 (%s): 「%s」"%[tag,table_label_title()])
	# Most crowded: warm hotpot round of six, watermelon, tea set (fresh deep round), warmer.
	set_warmer(true)
	set_tea(true)
	await set_community({"hotpot":meal(6,false,6),"watermelon":meal(4)})
	check(table_label_title()=="火鍋 6 · 西瓜 4 · 茶 6","Crowded label without chowder (%s): 「%s」"%[tag,table_label_title()])
	await set_community({"hotpot":meal(6,false,6),"watermelon":meal(4),"chowder":meal(4)})
	check(table_label_title()=="火鍋 6 · 西瓜 4 · 濃湯 4 · 茶 6","Crowded label lists 濃湯 after 西瓜, before 茶 (%s): 「%s」"%[tag,table_label_title()])
	await set_community({"hotpot":meal(6,false,6),"watermelon":meal(4)})
	await stand(VIEW_SPOT)
	var without:Image=await grab()
	check(changed_pixels(plain,without,region_box())>0,"Crowded table differs from the plain table (sanity, %s)"%tag)
	await set_community({"hotpot":meal(6,false,6),"watermelon":meal(4),"chowder":meal(4)})
	var crowded:Image=await shot("world_crowded")
	save_crop(crowded,"crop_crowded")
	tureen_clear("crowded "+tag)
	compare(without,crowded,"crowded "+tag)
	# Cleanup for the next size.
	set_warmer(false)
	set_tea(false)
	await set_community({})

# ----------------------------------------------------------------- probes --

func draw_probe()->void:
	var at:=PROBE_ORIGIN
	var tea:Dictionary={"placed":true,"style":"deep","left":6,"cold":false}
	match probe_variant:
		"legacy":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{})
		"c0":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},0)
		"c1":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},1)
		"c2":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},2)
		"c3":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},3)
		"c4":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},4)
		"c9":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{},9)
		"all0":Art.draw_table(probe_node,at,1.0,true,{},{},6,4,true,tea,0)
		"all4":Art.draw_table(probe_node,at,1.0,true,{},{},6,4,true,tea,4)
		# Hotpot alone (pot centred) and the opened-kitchen spread (soup, bread, salad).
		"pot0":Art.draw_table(probe_node,at,1.0,true,{},{},4,0,false,{},0)
		"pot4":Art.draw_table(probe_node,at,1.0,true,{},{},4,0,false,{},4)
		"open0":Art.draw_table(probe_node,at,1.0,true,opened_kitchen(),{},0,0,false,{},0)
		"open4":Art.draw_table(probe_node,at,1.0,true,opened_kitchen(),{},0,0,false,{},4)

func opened_kitchen()->Dictionary:
	var meals:Dictionary={}
	for item in PK.MEALS:meals[item]=int(PK.REQUIREMENTS[item])
	return {"stove":"40,34","seats":["41,34","42,34"],"meals":meals,"opened":true}

func probe(variant:String)->Image:
	probe_variant=variant
	probe_node.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image:=probe_view.get_texture().get_image()
	if image!=null and image.is_compressed():image.decompress()
	if image!=null:image.convert(Image.FORMAT_RGBA8)
	return image

func probe_box(local:Rect2)->Rect2i:
	return Rect2i(Vector2i((PROBE_ORIGIN+local.position).floor()),Vector2i(local.size))

func kernel_count(image:Image)->int:
	var box:=probe_box(Art.CHOWDER_RECT)
	var count:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			if colour_near(image.get_pixel(x,y),Art.CHOWDER_KERNEL):count+=1
	return count

## Offscreen 1× draws of draw_table: chowder=0 is byte-identical to the call without the
## argument; the tureen changes nothing outside CHOWDER_RECT; one kernel dot per portion.
func probe_flow()->void:
	probe_view=SubViewport.new()
	probe_view.size=PROBE_SIZE
	probe_view.transparent_bg=false
	probe_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	probe_view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	probe_node=Node2D.new()
	probe_node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	probe_node.draw.connect(draw_probe)
	probe_view.add_child(probe_node)
	root.add_child(probe_view)
	await process_frame
	var legacy:Image=await probe("legacy")
	check(legacy!=null and not legacy.is_empty() and legacy.get_size()==PROBE_SIZE,"Probe renders")
	if legacy==null or legacy.is_empty():return
	var states:Array[Image]=[]
	for n in range(5):
		var image:Image=await probe("c%d"%n)
		states.append(image)
	var nine:Image=await probe("c9")
	var all0:Image=await probe("all0")
	var all4:Image=await probe("all4")
	check(legacy.get_data()==states[0].get_data(),"draw_table with chowder=0 identical to the 10-arg call (byte compare)")
	var whole:=Rect2i(Vector2i.ZERO,PROBE_SIZE)
	var box:=probe_box(Art.CHOWDER_RECT)
	for n in range(1,5):
		var inside:=changed_pixels(states[0],states[n],box)
		# The bread of the default spread covers the tureen's lower-left rows.
		check(inside>=25,"Probe: tureen drawn for %d portions (%d px)"%[n,inside])
		check(changed_pixels(states[0],states[n],whole)==inside,"Probe: %d portions change nothing outside CHOWDER_RECT"%n)
		check(kernel_count(states[n])==n,"Probe: %d kernel dots for %d portions (%d)"%[n,n,kernel_count(states[n])])
	check(kernel_count(states[0])==0,"Probe: no kernel dots without chowder (%d)"%kernel_count(states[0]))
	check(changed_pixels(states[1],states[4],box)==3,"Probe: 1→4 portions changes exactly three dots (%d)"%changed_pixels(states[1],states[4],box))
	check(nine.get_data()==states[4].get_data(),"Probe: more than four portions draws four dots")
	var crowd:=changed_pixels(all0,all4,box)
	check(crowd>=25 and changed_pixels(all0,all4,whole)==crowd,"Probe: crowded table — tureen only inside CHOWDER_RECT (%d px)"%crowd)
	check(kernel_count(all4)==4,"Probe: crowded table still shows four kernel dots above the watermelon tray (%d)"%kernel_count(all4))
	# Hotpot alone: the centred pot covers the tureen's left columns only.
	var pot0:Image=await probe("pot0")
	var pot4:Image=await probe("pot4")
	var pot_px:=changed_pixels(pot0,pot4,box)
	check(pot_px>=20 and changed_pixels(pot0,pot4,whole)==pot_px,"Probe: hotpot alone — tureen only inside CHOWDER_RECT (%d px)"%pot_px)
	# Opened-kitchen spread: the tureen stands three pixels higher, above the salad.
	var open0:Image=await probe("open0")
	var open4:Image=await probe("open4")
	check(PK.shape_ok(opened_kitchen()) and open0.get_data()!=states[0].get_data(),"Probe: opened-kitchen spread differs from the picnic spread")
	var open_box:=probe_box(Art.CHOWDER_OPENED_RECT)
	var open_px:=changed_pixels(open0,open4,open_box)
	check(open_px>=25 and changed_pixels(open0,open4,whole)==open_px,"Probe: opened spread — tureen only inside CHOWDER_OPENED_RECT (%d px)"%open_px)
	# ×8 strip of the whole table cell for 0..4 portions, the crowded table, hotpot alone
	# and the opened-kitchen spread.
	var local:=Rect2(Vector2(-4,-8),Vector2(40,44))
	var area:=probe_box(local)
	var shown:Array[Image]=[states[0],states[1],states[4],all4,pot4,open4]
	var strip:=Image.create_empty(shown.size()*(area.size.x+2),area.size.y,false,Image.FORMAT_RGBA8)
	strip.fill(Color("1c2a2a"))
	for i in range(shown.size()):
		strip.blit_rect(shown[i],area,Vector2i(i*(area.size.x+2),0))
	strip.resize(strip.get_width()*8,strip.get_height()*8,Image.INTERPOLATE_NEAREST)
	var keep:=tag
	tag=""
	save_image(strip,"probe_tureen")
	tag=keep
	probe_view.queue_free()
	await process_frame

# ------------------------------------------------------------------ icons --

func icon_image(item:String)->Image:
	var tex:=Items.icon(item)
	check(tex!=null,"Icon exists: %s"%item)
	if tex==null:return null
	var image:=tex.get_image()
	if image==null or image.is_empty():return null
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

func shared_serve_flow(dish:String,item:String)->void:
	await set_community({})
	await stand(VIEW_SPOT)
	set_bag({item:4})
	var was_processing:bool=app.view.is_processing()
	app.view.set_process(false)
	var started:float=app.view.elapsed
	app.view.reduced_motion=false
	app.session.perform("serve_"+dish,TABLE)
	await settle()
	app.view.elapsed=started+0.55
	var event:Dictionary=app.view.community_feedback.sample_shared(app.view.elapsed,false)
	check(event.keys()==[item],"Actual serve produces one %s presentation (%s)"%[dish,tag])
	app.view.queue_redraw()
	var animated:Image=await shot("world_%s_served"%dish)
	app.view.photograph_mode=true
	app.view.queue_redraw()
	var still:Image=await grab()
	var cue_box:=pixel_box(cell_rect(Rect2(-12,-34,58,20)))
	check(changed_pixels(animated,still,cue_box)>0,"Serving cue visibly changes pixels above the table (%s)"%tag)
	app.view.photograph_mode=false
	check(app.view.community_feedback.sample_shared(app.view.elapsed,true).is_empty(),"Reduced motion suppresses the serving cue (%s)"%tag)
	check(app.view.community_feedback.sample_shared(started+2.0,false).is_empty(),"Serving cue expires (%s)"%tag)
	app.view.set_process(was_processing)

func festival_flow()->void:
	var previous:Dictionary=w.state.festival.duplicate(true)
	w.state.festival.collected=app.Festival.GOAL # PRESET: relay completion is covered by test_ui.
	w.state.festival.round=1
	w.state.festival.finished=40.0
	w.state.festival.best=40.0
	set_bag({"corn_chowder":4})
	await set_community({})
	# Fixture for the full results list without writing extra profiles into the save.
	for index in range(4):
		app.session.snapshot.festival.contributors["preview-%d"%index]={"name":"接力旅人 %d"%(index+1),"count":3}
	app._festival_menu()
	await settle()
	var chowder:=page_node("FestivalChowder") as Button
	check(chowder!=null and not chowder.disabled,"Completed relay shows the chowder action (%s)"%tag)
	await shot("festival_chowder")
	var scroll:=page_node("ModalScroll") as ScrollContainer
	if chowder!=null and scroll!=null:
		check(scroll.get_global_rect().encloses(chowder.get_global_rect()),"Chowder action visible without scrolling (%s)"%tag)
	await close_page()
	w.state.festival=previous

func icon_flow()->void:
	var distinct:Dictionary={}
	for id in ["trout_hotpot","watermelon_platter","corn_chowder","soup","salad"]:
		var icon:=icon_image(id)
		check(icon!=null and icon.get_size()==Vector2i(32,32),"32px icon for "+id)
		if icon==null:continue
		var key:=icon.get_data().hex_encode().sha256_text()
		check(not distinct.has(key),"Dedicated icon distinct from earlier dishes: "+id)
		distinct[key]=true
	var chowder:=icon_image("corn_chowder")
	var soup:=icon_image("soup")
	var salad:=icon_image("salad")
	check(chowder!=null,"玉米濃湯 icon has an image")
	if chowder==null:return
	check(chowder.get_size()==Vector2i(32,32),"玉米濃湯 icon is 32×32 (%s)"%str(chowder.get_size()))
	for corner:Vector2i in [Vector2i(0,0),Vector2i(31,0),Vector2i(0,31),Vector2i(31,31)]:
		check(chowder.get_pixel(corner.x,corner.y).a==0.0,"玉米濃湯 icon corner %s transparent"%str(corner))
	var yellow_px:=0
	var blue_px:=0
	for x in 32:
		for y in 32:
			var c:=chowder.get_pixel(x,y)
			if c.a<0.9:continue
			if c.h>=0.10 and c.h<=0.16 and c.s>=0.4 and c.v>=0.7:yellow_px+=1
			if c.h>=0.5 and c.h<=0.64 and c.s>=0.3:blue_px+=1
	check(yellow_px>=30,"玉米濃湯 icon has a corn-yellow soup surface (%d px)"%yellow_px)
	check(blue_px>=20,"玉米濃湯 icon matches the shared table's blue-banded bowl (%d px)"%blue_px)
	var chowder_texture:Texture2D=Items.icon("corn_chowder")
	check(chowder_texture.resource_path=="res://assets/ui-inventory/corn-chowder.png","玉米濃湯 uses its dedicated PNG")
	var ids:Array[Image]=[chowder,soup,salad]
	var strip:=Image.create_empty(ids.size()*272+16,288,false,Image.FORMAT_RGBA8)
	strip.fill(Color("f3e6c8"))
	for i in range(ids.size()):
		if ids[i]==null:continue
		var big:=ids[i].duplicate() as Image
		big.resize(256,256,Image.INTERPOLATE_NEAREST)
		strip.blend_rect(big,Rect2i(0,0,256,256),Vector2i(16+i*272,16))
	var keep:=tag
	tag=""
	save_image(strip,"icons")
	tag=keep

# -------------------------------------------------------------------- run --

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/玉米濃湯預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("corn-chowder-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"濃湯旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	# The fresh host shows the 望安 arrival card over the top of the plaza; close it
	# directly (a player closes it with E / Esc; covered in test_table_warmer_ui).
	WanganUI.dismiss(app)
	icon_flow()
	await probe_flow()
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await page_flow()
		await world_flow()
		for dish:String in World.COMMUNITY.DISHES:
			await shared_serve_flow(dish,World.COMMUNITY.DISHES[dish])
		await festival_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=26,"12 screenshots per size plus icons and probe strip (%d)"%shots)
	set_warmer(false)  # PRESET cleanup before the final save
	set_tea(false)
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
