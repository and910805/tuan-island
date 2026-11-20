extends SceneTree
## T071 市集攤位 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/市集攤位預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## as test_resident_bond_plaza_scene.gd.
##
## The stall cell is NEVER hard-coded: it comes from MarketStall.active_cell(snapshot).
## The prop reuses the 64×64 daily stall cell of assets/flowers/flower-market.png
## (FlowerSceneArt.market_texture(false)); no new art.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.picnic written directly (false for the before-picnic contrast frame);
##  * player.market erased before each size; backpack: every sellable item 0, then four
##    picked items 6 each;
##  * the player is teleported by writing region/x/y (world frames: a fixed spot near
##    the stall, chosen from SPOTS so the body overlaps neither the stall nor any of the
##    three MarketVisitors.SLOTS guest bodies and stays >= 1.2 tiles from every slot;
##    panel: next to the stall; overlap frame: exactly on a guest's foot point);
##  * app.view.reduced_motion=true for every world frame (stable pixels), except the
##    two shuffle frames where it is false and app.view.elapsed is written directly
##    with the view's own _process paused (app.view.set_process(false));
##  * PRESET second stall: a copied player record "PRESET-second-stall" is inserted
##    into w.state.players (another region, so it is not drawn) with market =
##    Market.fresh() + stock {picks[0]:1}, open_day=today, pending=true, giving
##    stalls_today==2; it is removed again before the midnight step so the existing
##    report (1 stall) is unchanged;
##  * world time set 0.5 s before the next world midnight, then World.step(1.0).
## REALLY EXERCISED: app._interact() opens the panel; 上架 / 開張營業 are pressed by
##  emitting `pressed` (real Session.perform path); the midnight tick settles the stall;
##  WorldView draws the market guests (market_guests/draw_market_guest) from the real
##  snapshot.own_market; the journal 「島嶼近況」 page is built by
##  life_ui_tasks.island_news(app) (called directly, not via the journal bookmark).
## T071 攤位布置 (also REALLY EXERCISED): WorldView.market_shelf_tags / draw_market_stall
##  draw the shelf tags from the real snapshot.own_market (stocked through the panel's
##  上架 buttons); the panel's MarketGuestRemark comes from the real panel build. Checked:
##  no tags on an empty stall; after stocking (stall still closed, new frame
##  world_stocked at the world_closed spot/camera) one tag per kind = MarketDisplay.shelf,
##  rect = stall origin + SLOTS[slot] (TAG size), inside the stall/viewport/clear of the
##  HUD, pixels changed vs world_closed, cream fill present, orange top strip only on
##  themed tags; open: tags unchanged, clear of the wish tags, guest bodies and the market
##  label; panel_opened: remark text == MarketDisplay.remark_line, unclipped; after
##  midnight: tags == shelf of what remained. PRESET for world_stocked: the panel is
##  closed and the player teleported back to the world spot, then the panel is reopened
##  next to the stall before 開張營業.
## SHOTS per size (14): world_before_picnic, world_closed, panel_empty, panel_stocked,
##  world_stocked, panel_opened, world_open, world_open_step, world_open_two_stalls,
##  world_open_overlap, news_open, panel_report, world_till, news_report.
##  (Temporary, deleted: world_closed_later, world_open_still, world_open_rest.)
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const Weather=preload("res://scripts/weather.gd")
const MarketVisitors=preload("res://scripts/market_visitors.gd")
const LabelLayout=preload("res://scripts/world_label_layout.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const MarketDisplay=preload("res://scripts/market_display.gd")
const CREAM:=Color(1.0,0.95,0.82)
## World-shot spots (feet, tiles relative to the stall cell's top-left); the first
## standable one clear of the stall and every guest slot is used.
const SPOTS:=[Vector2(0.5,2.4),Vector2(2.7,2.2),Vector2(0.5,3.9),Vector2(2.7,2.5),Vector2(-1.8,2.5),Vector2(2.7,0.7),Vector2(-1.8,0.7),
	Vector2(3.0,1.6),Vector2(-2.1,1.6),Vector2(2.7,3.6),Vector2(-1.8,3.6),Vector2(0.5,-1.6)]
const GUEST_CLEARANCE:=1.2
const SECOND_STALL:="PRESET-second-stall"
const SIDES:=[Vector2(0.5,1.4),Vector2(1.4,0.5),Vector2(-0.4,0.5),Vector2(0.5,-0.4)]
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
var picks:Array=[]

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("MARKET_STALL_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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

func shot(step:String)->Image:
	var file_name:="%s_%s"%[tag,step]
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var file:=output.path_join(file_name+".png")
	check(image!=null and not image.is_empty(),"non-empty native image "+file_name)
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s)"%file_name)
	check(colour_variety(image)>=12,"Screenshot is not blank (%s)"%file_name)
	check(image.save_png(file)==OK,"native screenshot saved "+file_name)
	shots+=1
	print("MARKET_STALL_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func panel_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="market_stall"

func own()->Dictionary:
	var found:Variant=app.session.snapshot.get("own_market",{})
	return found if found is Dictionary else {}

func stand(at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=at.x;person.y=at.y
	await refresh()

func standable(tile:Vector2i)->bool:
	return World.land(tile) and not w.blocked(tile)

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	return true

func panel_fits(label:String)->void:
	check(panel_open(),"Panel open (%s)"%label)
	if not panel_open():return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Panel fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer panel needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		var scroll:=control("MarketStockScroll")
		if scroll!=null and scroll.is_ancestor_of(l) and not scroll.get_global_rect().encloses(l.get_global_rect()):continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the panel: 「%s」 (%s)"%[l.text,label])

# ------------------------------------------------------------- world view --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

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

func stall_box(cell:Vector2i)->Rect2i:
	var r:=view_to_pixels(app.view.market_stall_rect(cell))
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## The market label is placed with the expected title, inside the screen, clear of
## other labels and of every HUD panel (hotbar, quest card...).
func label_ok(expected:String,label:String)->void:
	var list:=placements()
	var mine:={}
	for entry:Dictionary in list:
		if str(entry.id)=="market":mine=entry
	check(not mine.is_empty() and str(mine.title)==expected,"World label 「%s」 placed (%s): %s"%[expected,label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var pixels:=view_to_pixels(mine.rect)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(pixels),"Market label on screen (%s) %s"%[label,str(pixels)])
	for entry:Dictionary in list:
		if entry==mine:continue
		check(not (mine.rect as Rect2).intersects(entry.rect),"「%s」 does not overlap 「%s」 (%s)"%[expected,entry.title,label])
	for panel:Dictionary in hud_panels():
		check(not pixels.intersects(panel.rect),"Market label clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(pixels),str(panel.rect)])
	var box:=stall_box(Market.active_cell(app.session.snapshot))
	check(Rect2i(Vector2i.ZERO,root.size).encloses(box),"Whole stall prop on screen (%s) %s"%[label,str(box)])
	for panel:Dictionary in hud_panels():
		check(not Rect2(box).intersects(panel.rect),"Stall prop clear of HUD %s (%s)"%[panel.name,label])

## Body footprint (view coordinates) of someone whose feet are at `at` (world tiles);
## the same LabelLayout.body_rect WorldView uses for the guest fade.
func body_at(at:Vector2)->Rect2:
	var foot:Vector2=app.view.screen(at)
	return LabelLayout.body_rect(foot.round())

## True when a body at `at` covers neither the stall prop nor any guest slot.
func spot_clear(cell:Vector2i,at:Vector2)->bool:
	for off:Vector2 in MarketVisitors.SLOTS:
		var guest_at:Vector2=Vector2(cell)+off
		if at.distance_to(guest_at)<GUEST_CLEARANCE:return false
		if body_at(at).intersects(body_at(guest_at)):return false
	var stall:Rect2=app.view.market_stall_rect(cell)
	return not body_at(at).intersects(stall)

func world_spot(cell:Vector2i)->Vector2:
	for off:Vector2 in SPOTS:
		var at:Vector2=Vector2(cell)+off
		if standable(Vector2i(at.floor())) and spot_clear(cell,at):return at
	check(false,"A standable world spot clear of the stall and the guest slots near %s (%s)"%[str(cell),tag])
	return Vector2(cell)+SPOTS[0]

func px(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

func guest_box(guest:Dictionary)->Rect2i:
	var rect:Rect2=app.view.market_guest_rect(guest)
	return px(rect)

func wish_box(guest:Dictionary)->Rect2i:
	var rect:Rect2=app.view.market_wish_rect(guest)
	return px(rect)

## Pixel box where a guest standing in `slot` would be drawn (same camera as now).
func slot_box(cell:Vector2i,slot:int)->Rect2i:
	return guest_box({"position":Vector2(cell)+Vector2(MarketVisitors.SLOTS[slot])})

## Like box_difference but compares box_a of image a with an equally sized box_b of
## image b (used when the camera moved between the two frames).
func shifted_difference(a:Image,box_a:Rect2i,b:Image,box_b:Rect2i)->float:
	if a==null or b==null or box_a.size!=box_b.size or box_a.size.x<=0 or box_a.size.y<=0:return 0.0
	var changed:=0
	var counted:=0
	for dx in range(box_a.size.x):
		for dy in range(box_a.size.y):
			var pa:=box_a.position+Vector2i(dx,dy)
			var pb:=box_b.position+Vector2i(dx,dy)
			if pa.x<0 or pa.y<0 or pa.x>=a.get_width() or pa.y>=a.get_height():continue
			if pb.x<0 or pb.y<0 or pb.x>=b.get_width() or pb.y>=b.get_height():continue
			counted+=1
			var p:=a.get_pixel(pa.x,pa.y);var q:=b.get_pixel(pb.x,pb.y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(maxi(counted,1))

## market_guests() equals MarketVisitors.plan(own(), time) slot for slot, at the cell.
func guests_match_plan(guests:Array,cell:Vector2i,label:String)->void:
	var expected:Array=MarketVisitors.plan(own(),float(w.state.time))
	check(guests.size()==expected.size(),"market_guests() has the planned count %d (%s): %d"%[expected.size(),label,guests.size()])
	for i in range(mini(guests.size(),expected.size())):
		var a:Dictionary=guests[i]
		var b:Dictionary=expected[i]
		var same:bool=int(a.slot)==int(b.slot) and a.offset==b.offset and a.facing==b.facing and str(a.wish)==str(b.wish)
		check(same,"Guest %d matches MarketVisitors.plan (%s): %s vs %s"%[i,label,str(a),str(b)])
		var at:Vector2=a.position
		check(at.is_equal_approx(Vector2(cell)+Vector2(b.offset)),"Guest %d stands at cell+offset (%s): %s"%[i,label,str(at)])

## Every guest sprite box is fully on screen and clear of the HUD panels.
func guests_visible(guests:Array,label:String)->void:
	var panels:=hud_panels()
	for guest:Dictionary in guests:
		var box:=guest_box(guest)
		check(Rect2i(Vector2i.ZERO,root.size).encloses(box),"Guest slot %d sprite on screen (%s) %s"%[int(guest.slot),label,str(box)])
		for panel:Dictionary in panels:
			check(not Rect2(box).intersects(panel.rect),"Guest slot %d clear of HUD %s (%s)"%[int(guest.slot),panel.name,label])

func market_placement()->Dictionary:
	for entry:Dictionary in placements():
		if str(entry.id)=="market":return entry
	return {}

## 「島嶼近況」 page: MarketNews card lines equal summary_lines(own()), each line is
## whole and horizontally inside the modal; the card is scrolled into view for the shot.
func news_check(step:String,label:String)->void:
	if is_instance_valid(app.modal):app._close_modal();await settle()
	Tasks.island_news(app)
	await settle()
	var rows:=control("MarketNews") as VBoxContainer
	check(rows!=null,"「島嶼近況」 has the MarketNews card (%s)"%label)
	if rows==null:
		if is_instance_valid(app.modal):app._close_modal();await settle()
		return
	var scroller:Node=rows.get_parent()
	while scroller!=null and not scroller is ScrollContainer:scroller=scroller.get_parent()
	if scroller!=null:
		(scroller as ScrollContainer).ensure_control_visible(rows.get_parent() as Control)
		await settle()
	var expected:Array=MarketVisitors.summary_lines(own(),World.NAMES)
	check(not expected.is_empty(),"Market summary lines exist after the picnic (%s)"%label)
	var modal_rect:Rect2=(app.modal as Control).get_global_rect().grow(0.5)
	for i in range(expected.size()):
		var l:=control("MarketNewsLine%d"%i) as Label
		check(l!=null and l.text==str(expected[i]),"MarketNewsLine%d = 「%s」 (%s): 「%s」"%[i,str(expected[i]),label,l.text if l!=null else "missing"])
		if l==null or not l.is_visible_in_tree():continue
		var r:=l.get_global_rect()
		check(l.get_visible_line_count()>=l.get_line_count(),"MarketNewsLine%d not clipped (%s)"%[i,label])
		check(r.position.x>=modal_rect.position.x and r.end.x<=modal_rect.end.x,"MarketNewsLine%d horizontally inside the modal (%s) %s"%[i,label,str(r)])
	check(control("MarketNewsLine%d"%expected.size())==null,"No extra MarketNews line (%s)"%label)
	var heading_found:=false
	for node in rows.find_children("*","Label",true,false):
		if (node as Label).text=="我的市集攤位":heading_found=true
	check(heading_found,"MarketNews heading 「我的市集攤位」 (%s)"%label)
	await shot(step)
	app._close_modal()
	await settle()

func open_panel()->bool:
	if is_instance_valid(app.modal):app._close_modal();await settle()
	var cell:=Market.active_cell(app.session.snapshot)
	for off:Vector2 in SIDES:
		var at:Vector2=Vector2(cell)+off
		if not standable(Vector2i(at.floor())):continue
		await stand(at)
		if str(app.view.interaction_focus())=="market":break
	app._interact()
	await settle()
	check(panel_open(),"E next to the stall opens 市集攤位 (%s)"%tag)
	return panel_open()

# ------------------------------------------------------- 攤位布置 (shelf tags) --

## market_shelf_tags(cell) equals MarketDisplay.shelf(own()) entry for entry; every
## rect is the stall origin + SLOTS[slot] with TAG size and lies inside the stall rect.
func tags_match(cell:Vector2i,label:String)->Array:
	var tags:Array=app.view.market_shelf_tags(cell)
	var expected:Array=MarketDisplay.shelf(own())
	check(tags.size()==expected.size(),"Shelf tags = MarketDisplay.shelf count %d (%s): %d"%[expected.size(),label,tags.size()])
	var stall:Rect2=app.view.market_stall_rect(cell)
	for i in range(mini(tags.size(),expected.size())):
		var a:Dictionary=tags[i]
		var b:Dictionary=expected[i]
		var same:bool=int(a.get("slot",-1))==int(b.slot) and str(a.get("item",""))==str(b.item) and int(a.get("count",-1))==int(b.count) and bool(a.get("themed",false))==bool(b.themed)
		check(same,"Shelf tag %d matches MarketDisplay.shelf (%s): %s vs %s"%[i,label,str(a),str(b)])
		var r:Rect2=a.get("rect",Rect2())
		var want:=Rect2(stall.position+Vector2(MarketDisplay.SLOTS[int(b.slot)]),MarketDisplay.TAG)
		check(r.is_equal_approx(want),"Shelf tag %d rect = stall origin + SLOTS[%d], TAG size (%s): %s vs %s"%[i,int(b.slot),label,str(r),str(want)])
		check(stall.encloses(r),"Shelf tag %d inside the stall rect (%s): %s in %s"%[i,label,str(r),str(stall)])
	return tags

## Every tag's pixel box is on screen and clear of every HUD panel.
func tags_on_screen(tags:Array,label:String)->void:
	var panels:=hud_panels()
	for entry:Dictionary in tags:
		var box:=px(entry.rect)
		check(Rect2i(Vector2i.ZERO,root.size).encloses(box),"Shelf tag %s on screen (%s) %s"%[str(entry.item),label,str(box)])
		for panel:Dictionary in panels:
			check(not Rect2(box).intersects(panel.rect),"Shelf tag %s clear of HUD %s (%s)"%[str(entry.item),panel.name,label])

func is_cream(c:Color)->bool:
	var distance:=absf(c.r-CREAM.r)+absf(c.g-CREAM.g)+absf(c.b-CREAM.b)
	return distance<=0.45 and c.r>=0.70 and c.g>=0.64 and c.b>=0.50 and c.r-c.b>=0.05

func is_orange(c:Color)->bool:
	return c.r>=0.45 and c.r-c.g>=0.18 and c.g-c.b>=0.12

## Counts cream / orange pixels inside a view-space rect of `image`.
func colour_counts(image:Image,rect:Rect2)->Dictionary:
	var result:={"total":0,"cream":0,"orange":0}
	if image==null:return result
	var box:=px(rect).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			result.total=int(result.total)+1
			if is_cream(c):result.cream=int(result.cream)+1
			if is_orange(c):result.orange=int(result.orange)+1
	return result

## Pixel checks of the stocked (closed) frame against the empty-stall frame.
func tag_pixels(tags:Array,empty:Image,stocked:Image,label:String)->void:
	var themed_seen:=0
	for entry:Dictionary in tags:
		var r:Rect2=entry.rect
		var item:=str(entry.item)
		var diff:=box_difference(empty,stocked,px(r))
		print("NOTE %s: shelf tag %s (slot %d, themed %s) box %s changed %.0f%% vs world_closed"%[tag,item,int(entry.slot),str(entry.themed),str(px(r)),diff*100.0])
		check(diff>=0.25,"Shelf tag %s drawn (%.0f%% of its box changed vs the empty stall) %s"%[item,diff*100.0,label])
		var whole:=colour_counts(stocked,r.grow(-1))
		check(int(whole.cream)>0,"Shelf tag %s shows its cream fill (%d of %d px) %s"%[item,int(whole.cream),int(whole.total),label])
		# The 1px outer frame of a themed tag is orange (dark otherwise); the icon only
		# covers the inner box, so the top frame row is compared with the tag body.
		var strip:=colour_counts(stocked,Rect2(r.position,Vector2(r.size.x,1)))
		var body:=colour_counts(stocked,Rect2(r.position+Vector2(1,4),Vector2(r.size.x-2,r.size.y-5)))
		var strip_share:=float(strip.orange)/float(maxi(int(strip.total),1))
		var body_share:=float(body.orange)/float(maxi(int(body.total),1))
		print("NOTE %s: shelf tag %s orange strip %.0f%% / body %.0f%%"%[tag,item,strip_share*100.0,body_share*100.0])
		if bool(entry.themed):
			themed_seen+=1
			check(strip_share>=0.5,"Themed shelf tag %s has an orange top frame (%.0f%%) %s"%[item,strip_share*100.0,label])
		else:
			check(strip_share<=0.25,"Non-themed shelf tag %s has no orange top strip (strip %.0f%% vs body %.0f%%) %s"%[item,strip_share*100.0,body_share*100.0,label])
	print("NOTE %s: %d of %d shelf tags themed (theme %s)"%[tag,themed_seen,tags.size(),str(own().get("theme",""))])

## Open frame: tags clear of every guest's wish tag and body, and of the market label.
func tags_clear_of_guests(tags:Array,label:String)->void:
	var placed:=market_placement()
	for entry:Dictionary in tags:
		var r:Rect2=entry.rect
		for guest:Dictionary in app.view.market_guests():
			if not str(guest.wish).is_empty():
				var wish_rect:Rect2=app.view.market_wish_rect(guest)
				check(not wish_rect.intersects(r),"Shelf tag %s clear of guest %d's wish tag (%s): %s vs %s"%[str(entry.item),int(guest.slot),label,str(r),str(wish_rect)])
			var foot:Vector2=guest.position
			var guest_body:=body_at(foot)
			check(not guest_body.intersects(r),"Shelf tag %s clear of guest %d's body (%s): %s vs %s"%[str(entry.item),int(guest.slot),label,str(r),str(guest_body)])
		if not placed.is_empty():
			var label_rect:Rect2=placed.rect
			check(not label_rect.intersects(r),"Shelf tag %s clear of the market label (%s): %s vs %s"%[str(entry.item),label,str(r),str(label_rect)])

## Panel while the stall is open: the MarketGuestRemark line, exact and unclipped.
func remark_ok(label:String)->void:
	var expected:=MarketDisplay.remark_line(own(),World.NAMES)
	check(not expected.is_empty(),"A guest remark exists once a stall is open (%s)"%label)
	var l:=control("MarketGuestRemark") as Label
	check(l!=null and l.text==expected,"MarketGuestRemark = 「%s」 (%s): 「%s」"%[expected,label,l.text if l!=null else "missing"])
	if l==null:return
	check(l.is_visible_in_tree(),"MarketGuestRemark visible (%s)"%label)
	check(l.get_visible_line_count()>=l.get_line_count(),"MarketGuestRemark not clipped (%s)"%label)
	check((app.modal as Control).get_global_rect().grow(0.5).encloses(l.get_global_rect()),"MarketGuestRemark inside the panel (%s) %s"%[label,str(l.get_global_rect())])

# ------------------------------------------------------------------ flows --

func choose_picks()->void:
	var by_category:={}
	for item:String in Market.sellable_items():
		var category:=Market.category_of(item)
		if not by_category.has(category):by_category[category]=[]
		by_category[category].append(item)
	for category in ["produce","dish","flower","produce"]:
		var list:Array=by_category.get(category,[])
		for item in list:
			if item not in picks:picks.append(item);break
	check(picks.size()==4,"Four sellable items for the fixture: %s"%str(picks))

func size_flow()->void:
	var person:Dictionary=w.state.players[id]
	person.erase("market")  # PRESET
	var inv:Dictionary=person.inventory
	for item:String in Market.sellable_items():inv[item]=0
	for item in picks:inv[item]=6
	if is_instance_valid(app.modal):app._close_modal()
	app.view.reduced_motion=true  # PRESET stable frames (closed vs open comparisons)
	app.view.set_process(true)
	# Before the picnic: no stall.
	w.state.picnic=false  # PRESET
	await refresh()
	var cell:Vector2i=Market.cell_for(w.state)
	var spot:=world_spot(cell)
	check(spot_clear(cell,spot),"World-shot spot %s clear of the stall and all guest slots (%s)"%[str(spot),tag])
	await stand(spot)
	check(Market.active_cell(app.session.snapshot)==Market.NO_CELL,"No stall before the picnic (%s)"%tag)
	var has_label:=false
	for entry:Dictionary in placements():
		if str(entry.id)=="market":has_label=true
	check(not has_label and str(app.view.interaction_focus())!="market","No market label or focus before the picnic (%s)"%tag)
	var before:Image=await shot("world_before_picnic")
	# After the picnic, same spot and camera.
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(spot)
	check(Market.active_cell(app.session.snapshot)==cell,"Stall at %s after the picnic (%s)"%[str(cell),tag])
	var closed:Image=await shot("world_closed")
	var box:=stall_box(cell)
	var diff:=box_difference(before,closed,box)
	print("NOTE %s: stall box %s changed %.0f%% vs before the picnic; player at %s"%[tag,str(box),diff*100.0,str(spot)])
	check(diff>=0.25,"Stall prop drawn at its cell (%.0f%% of the 64×64 box changed) %s"%[diff*100.0,tag])
	label_ok("市集攤位","closed "+tag)
	var closed_guests:Array=app.view.market_guests()
	check(closed_guests.is_empty(),"No market guests while no stall is open (%s): %s"%[tag,str(closed_guests)])
	var closed_camera:Vector2=app.view.camera
	var empty_tags:Array=app.view.market_shelf_tags(cell)
	check(empty_tags.is_empty(),"No shelf tags on an empty stall (%s): %s"%[tag,str(empty_tags)])
	# Static in low-motion mode: same frame later shows the same stall pixels.
	app.view.reduced_motion=true
	app.view.elapsed+=1.3
	var later:Image=await shot("world_closed_later")
	shots-=1
	DirAccess.remove_absolute(output.path_join("%s_world_closed_later.png"%tag))
	check(box_difference(closed,later,box)<0.02,"Stall prop is static over time (low motion) %s"%tag)
	# Panel: empty, stocked, opened.
	if not await open_panel():return
	await shot("panel_empty")
	panel_fits("empty "+tag)
	await press("MarketDecorToggle")
	await press("MarketDecor_cloth_indigo")
	await press("MarketDecor_sign_flower")
	check(own().get("decor")=={"cloth":"indigo","sign":"flower"},"Both choices reached the host snapshot ("+tag+")")
	check(label_text("MarketDecorSummary").contains("藍染布") and label_text("MarketDecorSummary").contains("花飾招牌"),"Both selected styles are named in the panel ("+tag+")")
	panel_fits("decor picker "+tag)
	await shot("panel_decor")
	app._close_modal()
	await stand(spot)
	app.view.camera=closed_camera
	var dressed:Image=await shot("world_decor")
	var stall_origin:Vector2=app.view.market_stall_rect(cell).position
	var runner:=Rect2i(view_to_pixels(Rect2(stall_origin+Vector2(14,49),Vector2(36,3))))
	var charm:=Rect2i(view_to_pixels(Rect2(stall_origin+Vector2(52,21),Vector2(9,14))))
	check(box_difference(closed,dressed,runner)>0.15,"The indigo runner changes stall pixels ("+tag+")")
	check(box_difference(closed,dressed,charm)>0.08,"The flower charm changes stall pixels ("+tag+")")
	if not await open_panel():return
	await press("MarketDecorToggle")
	await press("MarketDecor_cloth_natural")
	await press("MarketDecor_sign_plain")
	await press("MarketDecorToggle")
	await press("MarketStock_%s_5"%picks[0])
	await press("MarketStock_%s_1"%picks[1])
	await press("MarketStock_%s_5"%picks[2])
	await press("MarketStock_%s_1"%picks[3])
	check(int(own().stock_count)==12 and own().stock.size()==4,"Stocked 4 kinds / 12 pieces (%s): %s"%[tag,str(own().stock)])
	await shot("panel_stocked")
	panel_fits("stocked "+tag)
	# 攤位布置: stocked but not open yet, same spot/camera as world_closed (no guests).
	app._close_modal()
	await stand(spot)
	check(not bool(own().get("open",false)) and int(own().get("stalls_today",0))==0,"Stall stocked but not open yet (%s): %s"%[tag,str(own().get("stalls_today"))])
	var stocked_guests:Array=app.view.market_guests()
	check(stocked_guests.is_empty(),"No market guests while the stall is only stocked (%s): %s"%[tag,str(stocked_guests)])
	var stocked:Image=await shot("world_stocked")
	var stocked_camera:Vector2=app.view.camera
	check(stocked_camera.distance_to(closed_camera)<0.5,"world_stocked uses the world_closed camera (%s): %s vs %s"%[tag,str(stocked_camera),str(closed_camera)])
	var shelf_tags:=tags_match(cell,"stocked "+tag)
	var stock_keys:Array=(own().get("stock",{}) as Dictionary).keys()
	stock_keys.sort()
	var tag_items:Array=[]
	for entry:Dictionary in shelf_tags:tag_items.append(str(entry.item))
	check(shelf_tags.size()==4 and tag_items==stock_keys,"One shelf tag per stocked kind, sorted (%s): %s vs %s"%[tag,str(tag_items),str(stock_keys)])
	for entry:Dictionary in shelf_tags:
		var themed_price:Variant=(own().get("prices",{}) as Dictionary).get(str(entry.item),{})
		var themed_expected:bool=themed_price is Dictionary and (themed_price as Dictionary).get("themed",false)==true
		check(bool(entry.themed)==themed_expected,"Shelf tag %s themed flag follows the price view (%s)"%[str(entry.item),tag])
	tags_on_screen(shelf_tags,"stocked "+tag)
	tag_pixels(shelf_tags,closed,stocked,"stocked "+tag)
	if not await open_panel():return
	await press("MarketOpen")
	var open_button:=control("MarketOpen") as Button
	check(open_button!=null and open_button.disabled and open_button.text=="今天已開張","開張營業 disabled after opening (%s)"%tag)
	await shot("panel_opened")
	panel_fits("opened "+tag)
	remark_ok("opened "+tag)
	app._close_modal()
	await stand(spot)
	var open:Image=await shot("world_open")
	label_ok("市集旅人的攤位","open "+tag)
	var open_tags:=tags_match(cell,"open "+tag)
	check(open_tags.size()==shelf_tags.size(),"Shelf tags still shown while open (%s): %d"%[tag,open_tags.size()])
	tags_on_screen(open_tags,"open "+tag)
	tags_clear_of_guests(open_tags,"open "+tag)
	await guests_flow(cell,spot,closed,open)
	await news_check("news_open","open "+tag)
	await stand(spot)
	# Midnight settlement.
	var today:=Market.day(float(w.state.time))
	w.state.time=float(today+1)*Weather.DAY_SECONDS-0.5  # PRESET time of day
	check(w.step(1.0,true),"World tick across midnight (%s)"%tag)
	await refresh()
	check(not own().get("report",{}).is_empty() and int(own().get("till",0))>0,"Report and till after midnight (%s): %s"%[tag,str(own().get("report",{}))])
	if await open_panel():
		check(label_text("MarketReport").begins_with("來客"),"Report shown in the panel (%s)"%tag)
		await shot("panel_report")
		panel_fits("report "+tag)
		app._close_modal()
	await stand(spot)
	var till:Image=await shot("world_till")
	label_ok("市集攤位・可領營收","till "+tag)
	var till_tags:=tags_match(cell,"till "+tag)
	print("NOTE %s: %d shelf tags after midnight (unsold stock %s)"%[tag,till_tags.size(),str(own().get("stock",{}))])
	tags_on_screen(till_tags,"till "+tag)
	var after:Array=app.view.market_guests()
	check(after.is_empty(),"No market guests after midnight settlement (%s): %s"%[tag,str(after)])
	# The side-slot boxes are only reported, not asserted: world_closed was taken at the
	# save's starting time of day while world_till is 0.5 s after midnight of the next
	# world day, so day/night lighting (and possibly the day's weather) differ across
	# the whole frame. Emptiness above is the real assertion.
	for slot in [0,1]:
		var slot_rect:=slot_box(cell,int(slot))
		print("NOTE %s: guest slot %d box %s differs %.1f%% world_till vs world_closed (lighting changed)"%[tag,int(slot),str(slot_rect),box_difference(closed,till,slot_rect)*100.0])
	await news_check("news_report","report "+tag)

## C-F: guests in front of the open stall (one stall → 2), low-motion stillness, the
## shuffle step, a PRESET second stall (→ 3) and the overlap fade.
func guests_flow(cell:Vector2i,spot:Vector2,closed:Image,open:Image)->void:
	# C. One open stall: two guests exactly as planned, drawn and clear of the HUD.
	var guests:Array=app.view.market_guests()
	check(guests.size()==2,"One open stall shows 2 guests (%s): %d"%[tag,guests.size()])
	guests_match_plan(guests,cell,"open "+tag)
	guests_visible(guests,"open "+tag)
	var wishers:=[]
	for guest:Dictionary in guests:
		var box:=guest_box(guest)
		var diff:=box_difference(closed,open,box)
		print("NOTE %s: guest slot %d box %s changed %.0f%% vs world_closed"%[tag,int(guest.slot),str(box),diff*100.0])
		check(diff>=0.10,"Guest slot %d drawn (%.0f%% of its 48×48 box changed) %s"%[int(guest.slot),diff*100.0,tag])
		if not str(guest.wish).is_empty():wishers.append(guest)
	check(wishers.size()==1,"Exactly one guest carries a wish (%s): %d"%[tag,wishers.size()])
	if wishers.size()==1:
		var wisher:Dictionary=wishers[0]
		var wish:=str(wisher.wish)
		check(ItemArt.icon(wish)!=null,"Wish item 「%s」 has an icon (%s)"%[wish,tag])
		var tag_box:=wish_box(wisher)
		var tag_diff:=box_difference(closed,open,tag_box)
		print("NOTE %s: wish tag %s box %s changed %.0f%% vs world_closed"%[tag,wish,str(tag_box),tag_diff*100.0])
		check(tag_diff>=0.5,"Wish tag drawn (%.0f%% of its 18×18 box changed) %s"%[tag_diff*100.0,tag])
		check(Rect2i(Vector2i.ZERO,root.size).encloses(tag_box),"Wish tag on screen (%s) %s"%[tag,str(tag_box)])
		var label:=market_placement()
		var wish_rect:Rect2=app.view.market_wish_rect(wisher)
		check(not label.is_empty() and not (label.rect as Rect2).intersects(wish_rect),"Market label clear of the wish tag (%s): %s vs %s"%[tag,str(label.get("rect","none")),str(wish_rect)])
	# D. Low motion: guests stay still over time.
	app.view.reduced_motion=true
	app.view.elapsed+=3.4
	var still:Image=await shot("world_open_still")
	shots-=1
	DirAccess.remove_absolute(output.path_join("%s_world_open_still.png"%tag))
	for guest:Dictionary in guests:
		var still_diff:=box_difference(open,still,guest_box(guest))
		check(still_diff<0.02,"Guest slot %d static in low motion (%.1f%%) %s"%[int(guest.slot),still_diff*100.0,tag])
	# D. Full motion: one guest mid-step vs at rest (elapsed written with the view paused).
	if not guests.is_empty():
		var mover:Dictionary=guests[0]
		var slot:=int(mover.slot)
		var step_at:=-1.0
		var rest_at:=-1.0
		var e:=0.0
		while e<MarketVisitors.SHUFFLE_PERIOD and (step_at<0.0 or rest_at<0.0):
			var phase:float=MarketVisitors.shuffle_phase(slot,e)
			if step_at<0.0 and phase>0.0 and sin(phase)>0.8:step_at=e
			if rest_at<0.0 and phase==0.0:rest_at=e
			e+=0.01
		check(step_at>=0.0 and rest_at>=0.0,"Shuffle phases sampled for slot %d (%s): step %.2f rest %.2f"%[slot,tag,step_at,rest_at])
		# Shift by whole periods past the current clock (shuffle_phase is 6 s periodic) so
		# no other elapsed-based feedback is rewound.
		var base:float=(floorf(float(app.view.elapsed)/MarketVisitors.SHUFFLE_PERIOD)+2.0)*MarketVisitors.SHUFFLE_PERIOD
		app.view.set_process(false)
		app.view.reduced_motion=false
		app.view.elapsed=base+rest_at
		app.view.queue_redraw()
		var rest:Image=await shot("world_open_rest")
		shots-=1
		DirAccess.remove_absolute(output.path_join("%s_world_open_rest.png"%tag))
		app.view.elapsed=base+step_at
		app.view.queue_redraw()
		var stepping:Image=await shot("world_open_step")
		var moved:=box_difference(rest,stepping,guest_box(mover))
		print("NOTE %s: slot %d shuffle step changed %.1f%% of its box (elapsed %.2f vs %.2f)"%[tag,slot,moved*100.0,base+step_at,base+rest_at])
		check(moved>0.01,"Guest slot %d steps in place with full motion (%.1f%%) %s"%[slot,moved*100.0,tag])
		app.view.reduced_motion=true
		app.view.set_process(true)
		app.view.queue_redraw()
		await settle()
	# E. PRESET second open stall → all three slots filled.
	var away:String=World.REGIONS.HOME
	for region in World.REGIONS.ALL:
		if str(region)!=World.REGIONS.HOME:away=str(region);break
	var second:Dictionary=(w.state.players[id] as Dictionary).duplicate(true)
	var market:Dictionary=Market.fresh()
	market.stock={str(picks[0]):1}
	market.open_day=Market.day(float(w.state.time))
	market.pending=true
	second["market"]=market
	second["region"]=away
	second.name="山風旅人"
	second.market_decor={"cloth":"indigo","sign":"flower"}
	w.state.players[SECOND_STALL]=second  # PRESET
	await refresh()
	check(int(own().get("stalls_today",0))==2,"PRESET second stall counted: stalls_today==2 (%s): %s"%[tag,str(own().get("stalls_today"))])
	var three:Array=app.view.market_guests()
	check(three.size()==3,"Two open stalls show 3 guests (%s): %d"%[tag,three.size()])
	guests_match_plan(three,cell,"two stalls "+tag)
	guests_visible(three,"two stalls "+tag)
	var two_open:Image=await shot("world_open_two_stalls")
	for guest:Dictionary in three:
		var box3:=guest_box(guest)
		print("NOTE %s: two stalls, guest slot %d box changed %.0f%% vs world_closed"%[tag,int(guest.slot),box_difference(closed,two_open,box3)*100.0])
	var original_time:=float(w.state.time)
	var visible_booth:Dictionary=app.session.snapshot.get("market_plaza",{})
	if visible_booth.get("vendor")!=SECOND_STALL.sha256_text().left(16):
		w.state.time=original_time+World.MARKET_DECOR.PLAZA_TURN
		await refresh()
		visible_booth=app.session.snapshot.get("market_plaza",{})
	var public_tags:Array=app.view.market_shelf_tags(cell)
	check(visible_booth.get("name")=="山風旅人" and visible_booth.get("style")==second.market_decor,"Visitor sees the other vendor's selected art after rotating")
	check(public_tags.size()==1 and public_tags[0].item==str(picks[0]),"Only the displayed vendor's product art appears on the counter")
	await shot("world_shared_stall")
	label_ok("山風旅人的攤位","visiting the displayed stall "+tag)
	w.state.time=original_time
	w.state.players.erase(SECOND_STALL)
	await refresh()
	check(int(own().get("stalls_today",0))==1 and app.view.market_guests().size()==2,"PRESET second stall removed again (%s)"%tag)
	# F. Stand exactly on a guest's feet: the guest fades, the player stays visible.
	var target:Dictionary=guests[0] if not guests.is_empty() else {}
	for guest:Dictionary in guests:
		var foot_tile:Vector2=guest.position
		if standable(Vector2i(foot_tile.floor())):target=guest;break
	if not target.is_empty():
		var before_box:=guest_box(target)
		var foot:Vector2=target.position
		await stand(foot)
		app.view._process(0.2)  # let the drawn position finish interpolating to the preset spot
		await settle()
		var shown:Vector2=app.view.display_positions.get(app.view.player_id,Vector2(-99,-99))
		check(shown.distance_to(foot)<0.01,"Player drawn on the guest's feet (%s): %s vs %s"%[tag,str(shown),str(foot)])
		check(body_at(shown).intersects(body_at(foot)),"Player and guest bodies intersect (fade case) (%s)"%tag)
		var overlap:Image=await shot("world_open_overlap")
		var now_guests:Array=app.view.market_guests()
		check(now_guests.size()==2,"Guests still shown while overlapped (%s)"%tag)
		var after_box:=guest_box(target)
		var faded:=shifted_difference(open,before_box,overlap,after_box)
		print("NOTE %s: overlapped guest slot %d box differs %.0f%% from the non-overlap world_open frame"%[tag,int(target.slot),faded*100.0])
		check(faded>0.02,"Player visible over the faded guest (%.0f%% changed) %s"%[faded*100.0,tag])
	await stand(spot)

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/市集攤位預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("market-stall-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"市集旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	choose_picks()
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=28,"14 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
