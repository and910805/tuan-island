extends SceneTree
## T071 紀念品交換攤 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/紀念品交換攤預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## as test_showcase_scene.gd.
##
## Art is runtime-painted, no new PNGs: booth = souvenir_art.booth() (48×56, teal
## awning, bunting, ticket on the counter); the seven decorations = souvenir_art.piece()
## (32×32, also the backpack icons).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic written directly (picnic false for the first frame);
##  * TICKETS SEEDED BY DIRECT WRITES (player.harvest_relay / fish_meet / showcase
##    records); player.souvenir, kits and souvenir objects erased before each size;
##  * the local player is teleported by writing x/y; the paused frames write three lamp
##    objects onto the booth candidates.
## REALLY EXERCISED: app._interact() at the booth opens the page; 兌換 pressed by
##  emitting `pressed` (real Session.perform → World → snapshot); the seven decorations
##  are placed with the client build path (app.building + app._select_tool("build") +
##  app._use_selected_at(cell) → Session.perform("build")); the backpack is the real
##  InventoryPanel.
## SHOTS per size (12): world_before_picnic, world_booth, world_booth_focused,
##  page_none, page_all, page_after, page_paused, world_paused, inventory_kits,
##  world_decor, world_decor_reduced, decor_strip (crop).
const World=preload("res://scripts/world.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const SouvUI=preload("res://scripts/souvenir_exchange_ui.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const BOOTH:=Vector2i(37,25)
const BOOTH_SPOT:=Vector2(37.5,27.5)
## Viewing spot east of the market stall: booth, its label, the seven decorations and
## the neighbouring labels sit clear of the tracker and the quick-key bar.
const VIEW_SPOT:=Vector2(38.5,28.6)
## Where the seven decorations go: a row in the open home build area north-east of the
## plaza (no base trees / rocks, clear of resident labels and the first field). A first
## layout in row 27 right in front of the booth was dropped after reviewing the
## screenshots (before/): the pine at (33,28), the local player and the 阿榆 / 公告板
## labels covered parts of it.
const LAYOUT:={"veg_basket_rack":Vector2i(46,23),"relay_crate_stack":Vector2i(47,27),"carp_banner":Vector2i(48,27),"float_garland":Vector2i(49,27),
	"lantern_post":Vector2i(50,23),"flower_arch":Vector2i(51,23),"trio_keepsake":Vector2i(52,23)}
const DECOR_SPOT:=Vector2(49.5,26.6)
var app
var w
var id:String=""
var path:String=""
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
	print("SOUVENIR_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("SOUVENIR_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

## Current frame without saving it.
func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

## Decorations: on screen, clear of every HUD panel, no world label (name tags
## included) over any decoration tile.
func decor_ok(label:String,cells:Array)->void:
	var list:=placements()
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	var ids:=PackedStringArray()
	for entry:Dictionary in list:ids.append("%s「%s」"%[str(entry.id),str(entry.title)])
	print("NOTE %s labels: %s"%[label,", ".join(ids)])
	for cell:Vector2i in cells:
		var px:=view_to_pixels(cell_rect(cell))
		check(screen_rect.encloses(px),"Decoration %s on screen (%s) %s"%[str(cell),label,str(px)])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Decoration %s clear of HUD %s (%s)"%[str(cell),panel.name,label])
		for entry:Dictionary in list:check(not (entry.rect as Rect2).intersects(cell_rect(cell).grow(-1.0)),"Label 「%s」 not over the decoration at %s (%s)"%[entry.title,str(cell),label])
		var hint:=app.selected_label as Control
		if hint!=null and hint.is_visible_in_tree():check(not px.intersects(hint.get_global_rect()),"Decoration %s clear of the tool hint (%s)"%[str(cell),label])

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==SouvUI.LAYOUT

func own()->Dictionary:
	return SouvUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

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
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

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

func region_difference(image:Image,a:Rect2i,b:Rect2i)->float:
	var size:=Vector2i(mini(a.size.x,b.size.x),mini(a.size.y,b.size.y))
	if size.x<=0 or size.y<=0:return 0.0
	var changed:=0
	for x in size.x:
		for y in size.y:
			var p:=image.get_pixel(a.position.x+x,a.position.y+y);var q:=image.get_pixel(b.position.x+x,b.position.y+y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(size.x*size.y)

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

func cell_rect(cell:Vector2i)->Rect2:
	return Rect2(app.view.screen(Vector2(cell)),Vector2(32,32))

func booth_rect()->Rect2:
	return SouvUI.booth_rect(app.view,BOOTH)

## Labels: the booth label is placed with the right title near the booth, never over
## the booth sprite or any decoration, never overlapping another label (residents,
## market stall, 公告板, name tags); booth + decorations clear of every HUD panel.
func world_ok(label:String,decor:Array,expect_booth:=true)->void:
	var list:=placements()
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	var booth_label:Dictionary={}
	var ids:=PackedStringArray()
	for entry:Dictionary in list:
		ids.append("%s「%s」"%[str(entry.id),str(entry.title)])
		if str(entry.id)==SouvUI.POINT:booth_label=entry
	print("NOTE %s labels: %s"%[label,", ".join(ids)])
	if not expect_booth:
		check(booth_label.is_empty(),"No booth label (%s)"%label)
		return
	var expected:=SouvUI.booth_title(str(app.view.focused_label)==SouvUI.POINT)
	check(not booth_label.is_empty() and str(booth_label.title)==expected,"Booth label 「%s」 placed (%s): %s"%[expected,label,str(booth_label.get("title","none"))])
	if booth_label.is_empty():return
	var r:Rect2=booth_label.rect
	var booth:=booth_rect()
	check(screen_rect.encloses(view_to_pixels(r)),"Booth label on screen (%s)"%label)
	check(not r.intersects(booth.grow(-2.0)),"Booth label not over the booth (%s) %s vs %s"%[label,str(r),str(booth)])
	check(absf(r.get_center().x-booth.get_center().x)<=48.0 and r.end.y<=booth.position.y+4.0 and r.end.y>=booth.position.y-30.0,"Booth label stays just above the booth (%s) %s vs %s"%[label,str(r),str(booth)])
	for other:Dictionary in list:
		if other==booth_label:continue
		check(not r.grow(1.0).intersects(other.rect),"Booth label does not overlap 「%s」 (%s) %s vs %s"%[other.title,label,str(r),str(other.rect)])
		if str(other.id)!="":
			for third:Dictionary in list:
				if third!=other and str(third.id)!="" and third!=booth_label:check(not (other.rect as Rect2).intersects(third.rect),"「%s」 does not overlap 「%s」 (%s)"%[other.title,third.title,label])
	for cell:Vector2i in decor:
		check(not r.intersects(cell_rect(cell).grow(-1.0)),"Booth label not over the decoration at %s (%s)"%[str(cell),label])
	var booth_px:=view_to_pixels(booth)
	check(screen_rect.encloses(booth_px),"Whole booth on screen (%s) %s"%[label,str(booth_px)])
	for panel:Dictionary in hud_panels():
		check(not booth_px.intersects(panel.rect),"Booth clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(booth_px),str(panel.rect)])
		check(not view_to_pixels(r).intersects(panel.rect),"Booth label clear of HUD %s (%s)"%[panel.name,label])
		for cell:Vector2i in decor:check(not view_to_pixels(cell_rect(cell)).intersects(panel.rect),"Decoration %s clear of HUD %s (%s)"%[str(cell),panel.name,label])
	var hint:=app.selected_label as Control
	if hint!=null and hint.is_visible_in_tree():check(not booth_px.intersects(hint.get_global_rect()),"Booth clear of the tool hint (%s)"%label)

## No tree crown (or any later-drawn sprite) covers the booth: the booth's own colours
## stay where they were painted. Samples the awning stripes and the ticket.
func booth_uncovered(image:Image,label:String)->void:
	var art:Image=preload("res://scripts/souvenir_art.gd").booth().get_image()
	var booth:=booth_rect()
	var matched:=0
	var total:=0
	for y in range(0,56,2):
		for x in range(0,48,2):
			var c:=art.get_pixel(x,y)
			if c.a<0.99:continue
			total+=1
			var at:=pixel_box(Rect2(booth.position+Vector2(x,y),Vector2.ONE)).position
			if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height():continue
			var q:=image.get_pixel(at.x,at.y)
			if absf(c.r-q.r)+absf(c.g-q.g)+absf(c.b-q.b)<0.15:matched+=1
	var share:=float(matched)/maxf(1.0,float(total))
	print("NOTE %s: booth pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.8,"Booth is not covered by canopies or other sprites (%s): %.0f%%"%[label,share*100.0])

# ------------------------------------------------------------------ flows --

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	var p:Dictionary=person()
	p.erase("souvenir")  # PRESET
	for item:String in Souv.items():(p.inventory as Dictionary).erase(item)
	for k in (w.state.objects as Dictionary).keys():
		if Souv.is_kind(str(w.state.objects[k].get("type",""))) or World.cell(str(k)) in Souv.CANDIDATES:w.state.objects.erase(k)
	app.view.reduced_motion=false

func seed_tickets(n:int)->void:
	for field in ["harvest_relay","fish_meet","showcase"]:
		if n<=0:person().erase(field)
		else:person()[field]={"tickets":n,"rounds":n,"best":0,"paid_round":1}  # PRESET
	await refresh()

func open_at_booth()->void:
	await stand(BOOTH_SPOT)
	check(str(app.view.interaction_focus())==SouvUI.POINT,"Booth focused (%s)"%tag)
	app._interact()
	await settle()
	check(page_open(),"Interact at the booth opens 紀念品交換攤 (%s)"%tag)

func size_flow()->void:
	reset()
	await seed_tickets(0)
	w.state.board=true  # PRESET
	w.state.picnic=false  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	check(not SouvUI.booth_shown(app.session.snapshot),"No booth before the picnic (%s)"%tag)
	var before:Image=await shot("world_before_picnic")
	world_ok("before picnic "+tag,[],false)
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	check(SouvUI.booth_cell(app.session.snapshot)==BOOTH,"Booth at (37,25) (%s)"%tag)
	var booth_img:Image=await shot("world_booth")
	var drawn:=box_difference(before,booth_img,pixel_box(booth_rect().grow(-2.0)))
	print("NOTE %s: booth box changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.35,"Booth drawn at its cell (%.0f%% changed) %s"%[drawn*100.0,tag])
	booth_uncovered(booth_img,"booth "+tag)
	world_ok("booth "+tag,[])
	# The market stall five tiles south looks different from the booth.
	var stall:Rect2=app.view.market_stall_rect(Souv.CANDIDATES[0]+Vector2i(-1,5))
	var stall_box:=pixel_box(Rect2(stall.position+Vector2(8,4),Vector2(48,56)))
	var booth_box:=pixel_box(booth_rect())
	var unlike:=region_difference(booth_img,booth_box,stall_box)
	print("NOTE %s: booth vs market stall difference %.0f%%"%[tag,unlike*100.0])
	check(unlike>=0.4,"Booth looks different from the market stall (%.0f%%) %s"%[unlike*100.0,tag])
	# Static frame to frame.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(box_difference(booth_img,root.get_texture().get_image(),pixel_box(booth_rect()))<=0.01,"Booth static (%s)"%tag)
	# Focused prompt.
	await stand(BOOTH_SPOT)
	await shot("world_booth_focused")
	world_ok("booth focused "+tag,[])
	# Page: nothing affordable.
	await open_at_booth()
	if not page_open():return
	await shot("page_none")
	page_fits("none "+tag)
	check(button_disabled_all(),"Nothing affordable: every 兌換 disabled (%s)"%tag)
	app._close_modal()
	# Everything affordable.
	await seed_tickets(12)
	await open_at_booth()
	await shot("page_all")
	page_fits("all "+tag)
	await press("SouvenirRedeem_relay_crate_stack")
	await press("SouvenirRedeem_carp_banner")
	check(label_text("SouvenirBalance_harvest_relay")=="剩 6 張" and label_text("SouvenirBalance_fish_meet")=="剩 9 張","Balances after two redemptions (%s)"%tag)
	await shot("page_after")
	page_fits("after "+tag)
	for entry:String in ["veg_basket_rack","float_garland","lantern_post","flower_arch","trio_keepsake"]:await press("SouvenirRedeem_"+entry)
	for entry:String in Souv.ENTRY_ORDER:check(int((person().inventory as Dictionary).get(Souv.item_of(entry),0))==1,"%s redeemed (%s)"%[entry,tag])
	app._close_modal()
	# Paused.
	for cell:Vector2i in Souv.CANDIDATES:w.state.objects[World.key(cell)]={"type":"lamp","owner":id,"items":{}}  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	await shot("world_paused")
	world_ok("paused "+tag,[],false)
	app._board()
	await settle()
	var entry_button:=control("SouvenirEntry") as Button
	check(entry_button!=null,"Board lists 紀念品交換攤 (%s)"%tag)
	if entry_button!=null:
		entry_button.pressed.emit()
		await settle()
	check(page_open() and label_text("SouvenirBlocked").contains("(37,25)"),"Paused page lists the cells (%s)"%tag)
	await shot("page_paused")
	page_fits("paused "+tag)
	app._close_modal()
	for cell:Vector2i in Souv.CANDIDATES:w.state.objects.erase(World.key(cell))
	await refresh()
	# Backpack with the seven kits (其他 tab, 三活動紀念牌 selected).
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack open (%s)"%tag)
	if app.modal is InventoryPanel:
		app.modal.select_category(4)
		# Keyboard focus on the kit selects it and scrolls the grid to the kits.
		app.modal.slots["trio_keepsake_kit"].grab_focus()
		await settle()
		check(str(app.modal.selected_id)=="trio_keepsake_kit","Kit selected by focus (%s)"%tag)
		for entry:String in Souv.ENTRY_ORDER:
			var slot=app.modal.slots.get(Souv.item_of(entry))
			check(slot!=null and slot.visible and int(slot.count)==1,"%s kit slot shown with 1 (%s)"%[entry,tag])
		await shot("inventory_kits")
		check(str(app.modal.detail_value.text)=="紀念票兌換的紀念品 · 不能出售或交易","Kit value line (%s)"%tag)
	app._close_modal()
	await settle()
	# Place the seven decorations with the client build path.
	await stand(DECOR_SPOT)
	var empty_img:Image=await grab()
	for entry:String in Souv.ENTRY_ORDER:
		var cell:Vector2i=LAYOUT[entry]
		await stand(Vector2(cell)+Vector2(0.5,1.5))
		app.building=entry
		app._select_tool("build")
		app.action_clock=0
		app.session.rates[1].clear()
		app._use_selected_at(cell)
		await refresh()
		check(str(w.state.objects.get(World.key(cell),{}).get("type",""))==entry,"%s placed at %s (%s): %s"%[entry,str(cell),tag,str(app.toast.text)])
	app._select_tool("hoe")
	await stand(DECOR_SPOT)
	var decor_img:Image=await shot("world_decor")
	var cells:Array=LAYOUT.values()
	decor_ok("decorations "+tag,cells)
	var boxes:={}
	for entry:String in Souv.ENTRY_ORDER:
		boxes[entry]=pixel_box(cell_rect(LAYOUT[entry]))
		var changed:=box_difference(empty_img,decor_img,boxes[entry])
		check(changed>=0.15,"%s drawn on its tile (%.0f%% changed) %s"%[entry,changed*100.0,tag])
	var least:=1.0
	for i in Souv.ENTRY_ORDER.size():
		for j in range(i+1,Souv.ENTRY_ORDER.size()):
			var a:String=Souv.ENTRY_ORDER[i];var b:String=Souv.ENTRY_ORDER[j]
			var d:=region_difference(decor_img,boxes[a],boxes[b])
			least=minf(least,d)
			check(d>=0.2,"%s and %s look different (%.0f%%) %s"%[a,b,d*100.0,tag])
	print("NOTE %s: least pairwise decoration difference %.0f%%"%[tag,least*100.0])
	var strip:=Rect2i(boxes.veg_basket_rack).merge(boxes.trio_keepsake).grow(8)
	save_image(decor_img.get_region(strip.intersection(Rect2i(Vector2i.ZERO,decor_img.get_size()))),"decor_strip")
	# Reduced motion: still.
	app.view.reduced_motion=true
	var still_a:Image=await shot("world_decor_reduced")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var still_b:Image=root.get_texture().get_image()
	var area:=Rect2i(boxes.veg_basket_rack).merge(boxes.trio_keepsake)
	check(box_difference(still_a,still_b,area)<=0.01,"Decorations static with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# The booth with decorations elsewhere on the island: still uncovered and labelled.
	await stand(VIEW_SPOT)
	booth_uncovered(await grab(),"booth after placing "+tag)
	world_ok("booth after placing "+tag,[])
	for cell:Vector2i in cells:w.state.objects.erase(World.key(cell))

func button_disabled_all()->bool:
	for entry:String in Souv.ENTRY_ORDER:
		var b:=control("SouvenirRedeem_"+entry) as Button
		if b==null or not b.disabled:return false
	return true

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/紀念品交換攤預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("souvenir-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"兌換旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=24,"12 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
