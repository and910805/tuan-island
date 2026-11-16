extends SceneTree
## T066 第四批居民好感（阿潮、暖暖）native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/居民好感預覽第四批 (or --capture-dir=), named
## <w>x<h>_<step>.png. Same harness as test_resident_bond_ranch_scene.gd.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * app.village_art_preview=true is set by the test itself;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    max-stage preset's talk_day/gift_day 0 are valid past days;
##  * state.picnic=true and state.dock_stage written directly (0 for the first world
##    shot, then 1);
##  * player.bonds is erased before each viewport size;
##  * backpack written directly: every item giftable to the resident set to 0, then
##    阿潮: grilled_fish 1, salt_grilled_fish 1, fiber 2 (liked); 暖暖: ginger 2,
##    tea_light 1 (liked); both: radish 2 (common), wood 5;
##  * the player is teleported by writing region/x/y (jiaoxi is entered by writing
##    player.region, no ride is exercised): for world shots 1.2 tiles east of 阿潮 /
##    1.2 tiles west of 暖暖 so the player sprite does not cover them; for the E key
##    0.9 tile north of 阿潮 / south of 暖暖;
##  * fallback: a player-owned `wall` written to state.objects["49,30"] (removed after);
##  * max-stage preset: player.bonds.<id>={"points":24,"talk_day":0,"gift_day":0}.
## REALLY EXERCISED (buttons pressed by emitting `pressed`, real Session.perform path):
##  * app._interact() opens the bond dialogue; BondTalk, BondGift, BondGift_<liked>,
##    BondEvents.
## SHOTS (per size, 10): achao_world_before_dock, achao_world_dock, achao_dialogue,
##  achao_gift, achao_events_stage4, achao_world_fallback, nuannuan_world_spring,
##  nuannuan_dialogue, nuannuan_gift, nuannuan_events_stage4; plus
##  <id>_events_stage4_tab1 (認識 tab). The tabbed events page must need NO outer
##  scrolling at every tab (hard check).
## NOT CHECKED BY PIXELS: 暖暖 has no gate, so there is no "absent" frame to diff her
##  sprite box against; she is checked by label placement, on-screen foot/sprite box,
##  fixed-resource occlusion and a colour-variety count inside her sprite box.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const DOCK_DEFAULT:=Vector2i(49,30)
const DOCK_FALLBACK:=Vector2i(50,30)
const SPRING_CELL:=Vector2i(20,22)
const STOCK:={"achao":{"grilled_fish":1,"salt_grilled_fish":1,"fiber":2},"nuannuan":{"ginger":2,"tea_light":1}}
const LIKED_GIFT:={"achao":"fiber","nuannuan":"ginger"}
var app
var w
var id:String=""
var rid:String="achao"
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
	print("RESIDENT_BOND_COAST_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):
		var toast_label:Label=app.toast
		toast_label.hide()

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
			var c:=image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0))
			seen[c.to_html(false)]=true
	return seen.size()

func shot(step:String)->Image:
	var file_name:="%s_%s"%[tag,step]
	hide_toast()
	await create_timer(0.2).timeout  # modal fade-in (LifeShell.reveal) is 0.16 s
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var file:=output.path_join(file_name+".png")
	check(image!=null and not image.is_empty() and image.get_width()>0 and image.get_height()>0,"non-empty native image "+file_name)
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size %s (%s)"%[str(root.size),file_name])
	var variety:=colour_variety(image)
	check(variety>=12,"Screenshot is not blank or flat (%d colours on the grid) %s"%[variety,file_name])
	check(image.save_png(file)==OK,"native screenshot saved "+file_name)
	check(FileAccess.file_exists(file),"screenshot file exists "+file_name)
	var handle:=FileAccess.open(file,FileAccess.READ)
	var length:int=0
	if handle!=null:
		length=handle.get_length()
		handle.close()
	check(length>0,"screenshot file is not empty "+file_name)
	shots+=1
	print("RESIDENT_BOND_COAST_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func differ(a:Image,b:Image,label:String)->void:
	check(a!=null and b!=null and a.get_data()!=b.get_data(),"Screenshots differ: "+label)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and is_instance_valid(app.modal) and (app.modal as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect())

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func find_button(prefix:String)->Button:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Button",true,false):
		var b:=node as Button
		if b!=null and b.is_visible_in_tree() and b.text.begins_with(prefix):return b
	return null

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func has_texts(wanted:Array,label:String)->void:
	var all:=texts()
	for t in wanted:check(all.contains(str(t)),"Visible text '%s' (%s)"%[t,label])

func layout_meta()->String:
	if not is_instance_valid(app.modal):return ""
	return str((app.modal as Node).get_meta("life_modal_layout",""))

func modal_fits(label:String)->bool:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Modal open: "+label)
	if not ok:return false
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Modal fits viewport: "+label)
	return true

func ancestor_scroll(c:Control)->ScrollContainer:
	if c==null:return null
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer:return parent as ScrollContainer
		parent=parent.get_parent()
	return null

func reach(c:Control,label:String)->bool:
	if c==null:return false
	if visible(c) and inside_modal(c):return true
	var scroll:=ancestor_scroll(c)
	if scroll==null:return false
	scroll.ensure_control_visible(c)
	await settle()
	var ok:=visible(c) and inside_modal(c)
	if ok:print("NOTE %s: %s is reachable only after scrolling the modal"%[label,c.name])
	return ok

func scroll_top()->void:
	if not is_instance_valid(app.modal):return
	for node in (app.modal as Node).find_children("*","ScrollContainer",true,false):(node as ScrollContainer).scroll_vertical=0
	await settle()

func needs_scroll()->bool:
	var scroll:=control("ModalScroll") as ScrollContainer
	if scroll==null:return false
	var bar:=scroll.get_v_scroll_bar()
	return bar.max_value>bar.page+1.0

func text_fits(b:Button)->bool:
	return b!=null and b.size.x+0.5>=b.get_minimum_size().x and b.size.y+0.5>=b.get_minimum_size().y

func on_view_now(names:Array,label:String)->void:
	for control_name in names:
		var c:=control(str(control_name))
		check(c!=null and visible(c) and inside_modal(c),"%s fully on view inside the card without scrolling (%s)"%[control_name,label])
		if c is Button:check(text_fits(c as Button),"%s text not cut (%s)"%[control_name,label])

func labels_whole(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Modal open for label check: "+label)
		return
	var scrolled:=0
	var bad:=PackedStringArray()
	var seen:=0
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l==null or not l.is_visible_in_tree() or l.text.strip_edges().is_empty():continue
		seen+=1
		if not (visible(l) and inside_modal(l)):
			var scroll:=ancestor_scroll(l)
			if scroll!=null:
				scroll.ensure_control_visible(l)
				await settle()
				scrolled+=1
		var whole:=visible(l) and inside_modal(l) and l.get_visible_line_count()>=l.get_line_count() and l.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING
		if not whole:bad.append(l.text.left(24).replace("\n"," "))
	check(seen>0,"Modal has labels ("+label+")")
	check(bad.is_empty(),"Labels not cut (%s): %s"%[label," | ".join(bad)])
	if scrolled>0:print("NOTE %s: %d label(s) reachable only after scrolling the modal"%[label,scrolled])
	await scroll_top()

func region_of(resident:String)->String:
	return str(World.bond_place(app.session.snapshot,resident)[0])

func place()->Vector2i:
	return World.bond_place(app.session.snapshot,rid)[1]

func stand(region:String,at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=at.x;person.y=at.y
	await refresh()

## E-key spot: 0.9 tile from the cell centre on the free side.
func near(cell:Vector2i)->Vector2:
	if rid=="nuannuan":return Vector2(cell)+Vector2(0.5,1.4)
	return Vector2(cell)+Vector2(0.5,-0.4)

## World-shot spot: 1.2 tiles beside the resident, 0.4 lower, away from the ferry.
func beside(cell:Vector2i)->Vector2:
	if rid=="nuannuan":return Vector2(cell)+Vector2(-0.7,0.9)
	return Vector2(cell)+Vector2(1.7,0.9)

func press(control_name:String)->bool:
	var button:=control(control_name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+control_name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await settle()
	return true

func close()->void:
	app._close_modal()
	await settle()

func bond()->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(rid,{})
	return found if found is Dictionary else {}

func bag_count(item:String)->int:
	return int(w.state.players[id].inventory.get(item,0))

func npc()->String:
	return Bond.name_of(rid)

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and control("BondSummary")!=null and texts().contains("和%s聊聊"%npc())

func events_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and texts().contains("%s的關係事件"%npc()) and control("BondSummary")==null

func open_by_interact(label:String)->bool:
	await close()
	await stand(region_of(rid),near(place()))
	app._interact()
	await settle()
	var ok:=dialogue_open()
	check(ok,"E next to %s opens 和%s聊聊 (%s)"%[npc(),npc(),label])
	return ok

func stock_bag()->void:
	var inv:Dictionary=w.state.players[id].inventory
	for item in inv.keys():
		if Bond.giftable(rid,str(item)):inv[item]=0
	for item in STOCK[rid]:inv[item]=int(STOCK[rid][item])
	inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

# ------------------------------------------------------------ world view --

func to_pixels(world_point:Vector2)->Vector2:
	return app.view.get_global_transform_with_canvas()*(app.view.screen(world_point)*float(app.view.view_zoom()))

## Resident sprite box: 32×48 (×zoom) above the foot.
func sprite_box(cell:Vector2i)->Rect2i:
	var foot:=to_pixels(Vector2(cell)+Vector2(0.5,0.7))
	var zoom:float=float(app.view.view_zoom())*app.view.get_global_transform_with_canvas().get_scale().x
	var size:=Vector2(32,48)*zoom
	return Rect2i(Vector2i((foot-Vector2(size.x/2.0,size.y)).round()),Vector2i(size.round()))

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

func box_variety(image:Image,box:Rect2i)->int:
	if image==null:return 0
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var seen:={}
	for x in range(box.position.x,box.end.x,2):
		for y in range(box.position.y,box.end.y,2):seen[image.get_pixel(x,y).to_html(false)]=true
	return seen.size()

## No fixed tree/rock (and no planted tree/object) on the resident's cell or the
## cell below, whose sprites are drawn after the resident and would cover him/her.
func not_covered(cell:Vector2i,region:String,label:String)->void:
	var layers:Dictionary=w.state if region==World.REGIONS.HOME else w.state.regions[region]
	for p:Vector2i in [cell,cell+Vector2i.DOWN]:
		var fixed:=World.base_resource(p,region)
		var removed:bool=layers.get("removed",{}).has(World.key(p))
		check(removed or fixed not in ["tree","rock"],"No fixed %s on %s covering %s (%s)"%[fixed,str(p),npc(),label])
		check(not layers.get("forest",{}).has(World.key(p)),"No planted tree on %s covering %s (%s)"%[str(p),npc(),label])
		if p!=cell:check(not layers.get("objects",{}).has(World.key(p)),"No object on %s covering %s (%s)"%[str(p),npc(),label])
	check(World.land(cell,region),"%s stands on land at %s (%s)"%[npc(),str(cell),label])

## The focus label is placed, on screen and does not overlap other labels;
## the sprite box is inside the viewport.
func world_label_ok(label:String,cell:Vector2i)->void:
	check(str(app.view.focused_label)==rid,"World focus is %s (%s): %s"%[npc(),label,str(app.view.focused_label)])
	var zoom:float=app.view.view_zoom()
	var placements:Array=app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))
	var mine:Dictionary={}
	for entry:Dictionary in placements:
		if str(entry.id)==rid:mine=entry
	check(not mine.is_empty() and str(mine.get("title",""))==npc() and bool(mine.get("active",false)),"Active world label 「%s」 placed (%s): %s"%[npc(),label,str(mine)])
	if mine.is_empty():return
	var box:Rect2=mine.rect
	var on_screen:=Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom)
	check(on_screen.encloses(box),"「%s」 label inside the viewport (%s) %s"%[npc(),label,str(box)])
	var anchor:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.7))+Vector2(0,-47)
	var gap:=box.get_center().distance_to(anchor)
	print("NOTE %s: %s label centre is %.0f view px from its head anchor %s"%[label,npc(),gap,str(anchor)])
	# 鏡頭停定的位置每次執行略有不同（同一畫面量到 31–42 px）；玩家貼在居民旁時
	# 標籤排版會繞開玩家，因此玩家在 1.5 格內時放寬到 64 px（與第五批廣場測試相同）。
	var me:Dictionary=w.state.players.get(id,{})
	var close_by:bool=not me.is_empty() and Vector2(me.x,me.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=1.5
	check(gap<=(64.0 if close_by else 40.0),"「%s」 label stays next to the resident's head (%.0f view px from the anchor) (%s)"%[npc(),gap,label])
	var others:=PackedStringArray()
	for entry:Dictionary in placements:
		if entry==mine:continue
		others.append("%s@%s"%[entry.title,str(entry.rect)])
		check(not box.intersects(entry.rect),"「%s」 label does not overlap 「%s」 (%s) %s vs %s"%[npc(),entry.title,label,str(box),str(entry.rect)])
	print("NOTE %s: %s label %s, other labels: %s"%[label,npc(),str(box),", ".join(others)])
	var foot:=to_pixels(Vector2(cell)+Vector2(0.5,0.7))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(foot),"%s's foot is on screen (%s) %s"%[npc(),label,str(foot)])
	var sprite:=sprite_box(cell)
	check(Rect2i(Vector2i.ZERO,root.size).encloses(sprite),"%s's whole sprite box is inside the viewport (%s) %s"%[npc(),label,str(sprite)])

# --------------------------------------------------------------- flows --

## Bond page, gift page (real talk + liked gift), then the stage-4 events page.
func pages_flow()->void:
	var step:="%s dialogue stage 0 %s"%[rid,tag]
	if not await open_by_interact(step):return
	modal_fits(step)
	on_view_now(["BondSummary","BondTalk","BondGift","BondEvents"],step)
	check(control("BondSiteBack")==null,"No BondSiteBack for %s (%s)"%[npc(),step])
	has_texts(["和%s聊聊"%npc(),"%s・%s"%[npc(),Bond.LOCAL_PLACES[rid]],"%s喜歡：%s"%[npc(),Bond.LIKE_TEXT[rid]],"好感・尚未認識  0／1","聊聊近況","送禮物","關係事件  0／4"],step)
	await shot(rid+"_dialogue")
	await labels_whole(step)
	await press("BondTalk")
	check(int(bond().get("stage",0))==1 and bool(bond().get("talked_today",false)),"Talk reaches 認識 (%s %s)"%[rid,tag])
	step="%s gift %s"%[rid,tag]
	if not await open_by_interact(step):return
	var talk:=control("BondTalk") as Button
	check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk shows disabled 今天聊過了 (%s)"%step)
	var gift_pressed:bool=await press("BondGift")
	if gift_pressed and modal_fits(step):
		check(texts().contains("送給%s的禮物"%npc()),"Gift page title (%s)"%step)
		var names:Array=["BondGiftList","BondGift_radish"]
		for item in STOCK[rid]:names.append("BondGift_"+item)
		on_view_now(names,step)
		check(control("BondGift_wood")==null,"wood not offered (%s)"%step)
		for item in STOCK[rid]:
			var b:=control("BondGift_"+item) as Button
			check(b!=null and b.text.begins_with("喜歡・"),"%s marked 喜歡・ (%s)"%[item,step])
		var radish:=control("BondGift_radish") as Button
		check(radish!=null and not radish.text.begins_with("喜歡・"),"radish not marked liked (%s)"%step)
		var back:=find_button("回到%s身邊"%npc())
		check(back!=null and visible(back) and inside_modal(back) and text_fits(back),"回到%s身邊 on view (%s)"%[npc(),step])
		var scroll:=control("ModalScroll") as ScrollContainer
		if scroll!=null:check(not scroll.get_v_scroll_bar().visible,"Gift page needs no scrolling (%s)"%step)
		await shot(rid+"_gift")
		await labels_whole(step)
		var liked:String=LIKED_GIFT[rid]
		var held:=bag_count(liked)
		await press("BondGift_"+liked)
		check(bag_count(liked)==held-1,"Gift removes one %s (%s)"%[liked,step])
		check(int(bond().get("points",0))==Bond.TALK_POINTS+Bond.LIKED_POINTS,"Talk + liked gift = %d points (%s)"%[Bond.TALK_POINTS+Bond.LIKED_POINTS,step])
	# Stage-4 events page (preset), opened from the bond dialogue.
	var person:Dictionary=w.state.players[id]
	var bonds:Dictionary=person.get("bonds",{})
	bonds[rid]={"points":Bond.LIMIT,"talk_day":0,"gift_day":0}  # PRESET stage 4
	person.bonds=bonds
	await refresh()
	check(int(bond().get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 (%s %s)"%[rid,tag])
	step="%s events stage 4 %s"%[rid,tag]
	var events_pressed:=false
	if await open_by_interact(step):events_pressed=await press("BondEvents")
	if events_pressed:
		check(events_open(),"Events page opens (%s)"%step)
		if modal_fits(step):
			has_texts(["%s的關係事件"%npc(),"四階事件都已展開","返回居民回憶","%s・%s"%[str(Bond.STAGES[3]),str(Bond.EVENTS[rid][3].title)]],step)
			check(not texts().contains("尚未展開"),"No locked card (%s)"%step)
			var back:=control("BondEventsBack") as Button
			check(back!=null and back.text=="返回居民回憶" and visible(back) and inside_modal(back),"BondEventsBack reads 返回居民回憶 on view (%s)"%step)
			check(not needs_scroll(),"Stage-4 events page needs no scrolling (%s)"%step)
			tab_page_fits(step)
			tab_card(rid,4,3,step)
			var img_four:Image=await shot(rid+"_events_stage4")
			await event_tabs(rid,4,step)
			# Non-default tab capture: 認識.
			if await press_tab(0,step):
				tab_card(rid,4,0,step+" tab 1")
				var img_one:Image=await shot(rid+"_events_stage4_tab1")
				differ(img_four,img_one,"stage-4 tab 4 vs tab 1 (%s)"%step)
	await close()

func achao_flow()->void:
	rid="achao"
	stock_bag()
	await close()
	# 0. Dock not repaired: nobody at the dock cell.
	w.state.picnic=true
	w.state.dock_stage=0
	await stand(World.REGIONS.HOME,beside(DOCK_DEFAULT))
	check(place()==DOCK_DEFAULT,"阿潮's cell is 49,30 "+tag)
	check(str(app.view.focused_label)!=rid,"No 阿潮 focus before the dock repair "+tag)
	var before:Image=await shot("achao_world_before_dock")
	# 1. Dock repaired (stage 1).
	w.state.dock_stage=1
	await stand(World.REGIONS.HOME,beside(DOCK_DEFAULT))
	not_covered(DOCK_DEFAULT,World.REGIONS.HOME,"world dock "+tag)
	world_label_ok("world dock "+tag,DOCK_DEFAULT)
	var dock_image:Image=await shot("achao_world_dock")
	var box:=sprite_box(DOCK_DEFAULT)
	var diff:=box_difference(before,dock_image,box)
	print("NOTE world dock %s: 阿潮 sprite box %s changed %.0f%% vs before the dock repair (sprite variety %d)"%[tag,str(box),diff*100.0,box_variety(dock_image,box)])
	check(diff>=0.15,"阿潮 is drawn at his cell (%.0f%% of the sprite box changed after the dock repair) %s"%[diff*100.0,tag])
	var aru_foot:=to_pixels(Vector2(Village.NPCS.aru.cell)+Vector2(0.5,0.7))
	print("NOTE world dock %s: 阿榆 foot at %s (on screen=%s) for visual comparison"%[tag,str(aru_foot),str(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(aru_foot))])
	# 2. Pages.
	await pages_flow()
	# 3. Fallback cell.
	await close()
	w.state.objects[World.key(DOCK_DEFAULT)]={"type":"wall","owner":id,"items":{}}  # PRESET wall
	await stand(World.REGIONS.HOME,beside(DOCK_FALLBACK))
	check(place()==DOCK_FALLBACK,"Wall on 49,30 moves 阿潮 to 50,30 "+tag)
	not_covered(DOCK_FALLBACK,World.REGIONS.HOME,"world fallback "+tag)
	world_label_ok("world fallback "+tag,DOCK_FALLBACK)
	var fallback:Image=await shot("achao_world_fallback")
	differ(dock_image,fallback,"world dock vs fallback "+tag)
	var moved:=sprite_box(DOCK_FALLBACK)
	print("NOTE world fallback %s: 阿潮 sprite box %s (sprite variety %d)"%[tag,str(moved),box_variety(fallback,moved)])
	w.state.objects.erase(World.key(DOCK_DEFAULT))
	await refresh()

func nuannuan_flow()->void:
	rid="nuannuan"
	stock_bag()
	await close()
	check(region_of(rid)=="jiaoxi" and place()==SPRING_CELL,"暖暖 is at jiaoxi 20,22 "+tag)
	await stand("jiaoxi",beside(SPRING_CELL))
	check(str(app.session.snapshot.get("region_id",""))=="jiaoxi","Snapshot is the jiaoxi region "+tag)
	# The region change shows the 1.8 s arrival ribbon (TravelArrival); dismiss it with
	# its real 「略過」 button so the world shot shows the spring, not the banner.
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	print("NOTE world spring %s: arrival ribbon present after teleport=%s"%[tag,str(ribbon!=null)])
	if ribbon!=null:
		for node in ribbon.find_children("*","Button",true,false):
			if (node as Button).text=="略過":(node as Button).pressed.emit()
		await settle()
		await refresh()
	check(app.hud.get_node_or_null("TravelArrival")==null or (app.hud.get_node("TravelArrival") as Node).is_queued_for_deletion(),"Arrival ribbon dismissed before the spring shot "+tag)
	not_covered(SPRING_CELL,"jiaoxi","world spring "+tag)
	world_label_ok("world spring "+tag,SPRING_CELL)
	var spring:Image=await shot("nuannuan_world_spring")
	var box:=sprite_box(SPRING_CELL)
	var variety:=box_variety(spring,box)
	print("NOTE world spring %s: 暖暖 sprite box %s variety %d"%[tag,str(box),variety])
	check(variety>=8,"暖暖's sprite box is not flat ground (%d colours) %s"%[variety,tag])
	await pages_flow()

# ------------------------------------------------- T066 tabbed events page --
## The 關係事件 page shows one stage at a time: BondEventsBack + BondEventsSummary,
## four toggle tabs BondEventTab_0..3, one BondEventCard and the footer hint.
## HARD rule at every tab: no outer scrolling, every Label/Button fully on view
## inside the modal and not cut; the selected stage's title and lines (or the
## locked 「尚未展開（好感 N）」 line) sit fully inside the card.
const EVENTS_FOOTER:="聊天、送禮和完成委託都會增加好感。好感不會因為沒上線而下降，朋友的進度也不影響你。"

## Focus + press one stage tab (emitting `pressed`).
func press_tab(index:int,label:String)->bool:
	var tab:=control("BondEventTab_%d"%index) as Button
	check(tab!=null and not tab.disabled,"BondEventTab_%d enabled (%s)"%[index,label])
	if tab==null or tab.disabled:return false
	tab.grab_focus()
	await create_timer(0.12).timeout
	tab.pressed.emit()
	await settle()
	return true

func tab_find_label(text:String)->Label:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l!=null and l.is_visible_in_tree() and l.text==text:return l
	return null

func tab_not_cut(l:Label)->bool:
	if l==null or l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.size.y+0.5<l.get_combined_minimum_size().y:return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func tab_button_not_cut(b:Button)->bool:
	if b==null or b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x and b.size.y+0.5>=b.get_combined_minimum_size().y

## No outer scrolling; every Label/Button on the page fully on view and not cut.
func tab_page_fits(label:String)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Events modal open (%s)"%label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Events modal fits the viewport (%s)"%label)
	check(str((app.modal as Node).get_meta("life_modal_layout",""))=="community_board","Events modal keeps the community_board layout (%s)"%label)
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll!=null and scroll.get_child_count()>0,"Events modal has its ModalScroll body (%s)"%label)
	if scroll==null or scroll.get_child_count()==0:return
	var content:=scroll.get_child(0) as Control
	var need:float=content.get_combined_minimum_size().y
	var bar:=scroll.get_v_scroll_bar()
	print("RESIDENT_BOND_DIAG events-fit %s content=%.0f view=%.0f spare=%.0f"%[label,need,scroll.size.y,scroll.size.y-need])
	check(need<=scroll.size.y+0.5 and not bar.visible and scroll.scroll_vertical==0,"Events page needs no outer scrolling (%s) content=%.0f view=%.0f"%[label,need,scroll.size.y])
	check(tab_find_label(EVENTS_FOOTER)!=null,"Events footer hint shown (%s)"%label)
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree():continue
		if c is Label:
			check(visible(c) and inside_modal(c),"Caption fully on view inside the modal: %s (%s)"%[(c as Label).text,label])
			check(tab_not_cut(c as Label),"Caption not cut or ellipsized: %s (%s)"%[(c as Label).text,label])
		elif c is Button:
			check(visible(c) and inside_modal(c),"Button fully on view inside the modal: %s (%s)"%[c.name,label])
			check(tab_button_not_cut(c as Button),"Button caption not cut: %s (%s)"%[c.name,label])

## Tabs reflect the selection; the card holds exactly the selected stage.
func tab_card(resident:String,stage:int,index:int,label:String)->void:
	var card:=control("BondEventCard")
	check(card!=null and visible(card) and inside_modal(card),"BondEventCard fully on view (%s)"%label)
	for i in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%i) as Button
		check(tab!=null and tab.toggle_mode and tab.button_pressed==(i==index),"BondEventTab_%d %s (%s)"%[i,"selected" if i==index else "not selected",label])
		if tab==null:continue
		check(not tab.disabled and tab.focus_mode==Control.FOCUS_ALL,"BondEventTab_%d enabled and focusable (%s)"%[i,label])
		check(tab.text.ends_with(str(Bond.STAGES[i])) and tab.text.begins_with("✓" if i<stage else "○"),"BondEventTab_%d reads %s with its marker (%s): %s"%[i,Bond.STAGES[i],label,tab.text])
	var event:Dictionary=Bond.EVENTS[resident][index]
	var wanted:Array=[]
	if index<stage:
		wanted.append("%s・%s"%[str(Bond.STAGES[index]),str(event.title)])
		for t in event.lines:wanted.append(str(t))
	else:wanted.append("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[index]),int(Bond.THRESHOLDS[index])])
	for text:String in wanted:
		var l:=tab_find_label(text)
		check(l!=null and card!=null and card.is_ancestor_of(l),"BondEventCard shows 「%s」 (%s)"%[text,label])
		if l==null or card==null:continue
		check(visible(l) and card.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and tab_not_cut(l),"「%s」 fully readable inside BondEventCard (%s)"%[text,label])
	var shown:=0
	if card!=null:
		for node in card.find_children("*","Label",true,false):
			if (node as Control).is_visible_in_tree():shown+=1
	check(shown==wanted.size(),"BondEventCard holds only stage %d (%s): %d labels, want %d"%[index+1,label,shown,wanted.size()])
	for j in range(Bond.STAGES.size()):
		if j==index:continue
		var other:Dictionary=Bond.EVENTS[resident][j]
		check(tab_find_label("%s・%s"%[str(Bond.STAGES[j]),str(other.title)])==null and tab_find_label("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[j]),int(Bond.THRESHOLDS[j])])==null,"Stage %d is not on the page while tab %d is open (%s)"%[j+1,index+1,label])
	var back:=control("BondEventsBack") as Button
	check(back!=null and visible(back) and inside_modal(back),"BondEventsBack on view (%s)"%label)

## Default tab = newest unlocked stage (stage 1 when none); then every tab is
## focused and pressed (emitting `pressed`), and re-checked.
func event_tabs(resident:String,stage:int,label:String)->void:
	var first:=clampi(stage-1,0,Bond.STAGES.size()-1)
	tab_page_fits("default tab %s"%label)
	tab_card(resident,stage,first,"default tab %s"%label)
	for index in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%index) as Button
		check(tab!=null,"BondEventTab_%d exists (%s)"%[index,label])
		if tab==null:continue
		tab.grab_focus()
		await create_timer(0.12).timeout
		tab.pressed.emit()
		await settle()
		check(is_instance_valid(tab) and root.gui_get_focus_owner()==tab,"Focus stays on BondEventTab_%d after pressing it (%s)"%[index,label])
		tab_page_fits("tab %d %s"%[index+1,label])
		tab_card(resident,stage,index,"tab %d %s"%[index+1,label])
	for index in range(Bond.STAGES.size()-1):
		var a:=control("BondEventTab_%d"%index)
		var b:=control("BondEventTab_%d"%(index+1))
		check(a!=null and b!=null and a.find_valid_focus_neighbor(SIDE_RIGHT)==b,"Right from BondEventTab_%d reaches the next tab (%s)"%[index,label])

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民好感預覽第四批").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("bond-coast-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"渡口旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationships
		w.state.objects.erase(World.key(DOCK_DEFAULT))
		await achao_flow()
		await nuannuan_flow()
		await stand(World.REGIONS.HOME,Vector2(46.5,30.5))
		await close()
	check(shots>=20,"10 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
