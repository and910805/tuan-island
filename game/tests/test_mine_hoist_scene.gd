extends SceneTree
## T067 Q07 「卡住的升降台」 + 玻璃爐 native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/升降台與玻璃爐預覽 (or --capture-dir=).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP%; picnic + board flags set directly;
##  * mine progress is written directly: unlocked 15, pumped 24, `hoist` false
##    (reset before each viewport size, so the stuck state is shown at both sizes);
##  * copper_joint / plank, the furnace build kit and the furnace recipe inputs
##    (crystal_sand, wood, vein_quartz) are written directly into the backpack;
##  * the player is teleported next to the entry sign and next to the furnace;
##    the furnace site is cleared by the fixture (same search as test_mine_hoist_ui).
## REALLY EXERCISED:
##  * the hoist repair goes through the real MineHoistRepairButton -> Session path;
##  * the letter / build folio / furnace queue are opened through the real menus,
##    the furnace queue via app._interact() next to the furnace;
##  * both furnace jobs are queued through the real ProcessingEnqueue button
##    (falls back to World.act only if the button path did not commit).
## FAST-FORWARD: world time is advanced with World.step(120.1,true) to make the
##  glass job claimable, and again (60.1 s) to clear the queue before the next size.
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/mine_ui.gd")
const BuildFolio=preload("res://scripts/build_folio.gd")
const ProcessingQueueUI=preload("res://scripts/processing_queue_ui.gd")
const Village=preload("res://scripts/village.gd")
const FURNACE_KIT:={"stone":12,"ochre_earth":4,"copper_joint":2}
var app
var w
var id:String
var checks:=0
var failures:=0
var output:=""
var furnace:=Vector2i(-1,-1)
var furnace_built:=false
var sequence:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	if is_instance_valid(app.toast):app.toast.hide()
	await settle()

func shot(name:String)->Image:
	if is_instance_valid(app.toast):app.toast.hide()
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var path:=output.path_join(name+".png")
	check(image.save_png(path)==OK,"native screenshot "+name)
	print("MINE_HOIST_SHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
	return image

func differ(a:Image,b:Image,label:String)->void:
	check(a!=null and b!=null and a.get_data()!=b.get_data(),"Screenshots differ: "+label)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and app.modal.get_global_rect().grow(0.5).encloses(c.get_global_rect())

## Like inside_modal, but for the part a scrolling list actually shows: a row
## peeking at the bottom of the shelf is clipped by its ScrollContainer.
func shown_inside_modal(c:Control)->bool:
	if c==null:return false
	var rect:=c.get_global_rect()
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer:rect=rect.intersection((parent as Control).get_global_rect())
		parent=parent.get_parent()
	return app.modal.get_global_rect().grow(0.5).encloses(rect)

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(name,true,false) as Control

## Visible Label + Button texts inside the current modal.
func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in app.modal.find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in app.modal.find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func has_texts(wanted:Array,label:String)->void:
	var all:=texts()
	for t in wanted:check(all.contains(str(t)),"Visible text '%s' (%s)"%[t,label])

## True when an ancestor ScrollContainer clips c entirely (scrolled-out list content).
func scrolled_out(c:Control)->bool:
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().intersects(c.get_global_rect()):return true
		parent=parent.get_parent()
	return false

## allow_scroll: the card has a scrolling list (build folio); fully scrolled-out
## rows are skipped, everything actually on view must sit inside the card.
func fits(label:String,allow_scroll:=false)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Modal open: "+label)
	if not ok:return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Modal fits viewport: "+label)
	for c in app.modal.find_children("*","BaseButton",true,false):
		if not (c as Control).is_visible_in_tree() or (allow_scroll and scrolled_out(c)):continue
		if allow_scroll:check(shown_inside_modal(c),"Button inside the card: %s (%s)"%[c.name,label])
		else:check(visible(c) and inside_modal(c),"Button fully visible inside the card: %s (%s)"%[c.name,label])
	for label_node in app.modal.find_children("*","Label",true,false):
		if not (label_node as Control).is_visible_in_tree() or (allow_scroll and scrolled_out(label_node)):continue
		check(shown_inside_modal(label_node) if allow_scroll else inside_modal(label_node),"Caption inside the card: %s (%s)"%[(label_node as Label).text,label])

## Home workshop layout: no outer scrolling, the blueprint book button and the
## first two shelf rows (thumbnail + caption) entirely on view, status not cut.
func folio_layout(label:String)->void:
	var folio:=control("BuildFolio")
	var book:=control("BlueprintBook")
	check(book!=null and visible(book) and inside_modal(book),"藍圖冊 button fully on view (%s)"%label)
	var outer:ScrollContainer=null
	var inner:Control=null
	if folio!=null:
		inner=folio.get_parent() as Control
		outer=inner.get_parent() as ScrollContainer
	check(outer!=null and inner.size.y<=outer.size.y+1.0,"Workshop needs no outer scrolling (%s): content %s in %s"%[label,str(inner.size.y) if inner!=null else "?",str(outer.size.y) if outer!=null else "?"])
	var page:=control("BuildPage0") as GridContainer
	check(page!=null and page.get_child_count()>=page.columns*2,"Shelf page has two rows (%s)"%label)
	if page!=null:
		for index in range(mini(page.columns*2,page.get_child_count())):
			var slot:=page.get_child(index) as Control
			var caption:=slot.get_child(0) as Label
			check(visible(slot) and visible(caption),"Shelf slot %s and its name fully on view (%s)"%[caption.text,label])
	var status:=control("BuildStatus") as Label
	check(status!=null and status.get_visible_line_count()>=status.get_line_count(),"Recipe status text is not cut (%s)"%label)

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	await refresh()

func progress(unlocked:int,hoist:bool)->void:
	w.state.mine_depths={"unlocked":unlocked,"ready":{},"pumped":24,"hoist":hoist}
	app.session._send_snapshot(1)

func stock(items:Dictionary)->void:
	w.state.players[id].inventory.merge(items,true)
	app.session._send_snapshot(1)

func press(name:String)->bool:
	var button:=control(name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await process_frame
	return true

func open_letter(label:String)->bool:
	app._chapter_menu()
	await settle()
	var link:=control("HoistLetterLink") as BaseButton
	check(link!=null,"Island story lists 卡住的升降台 (%s)"%label)
	if link==null:return false
	await create_timer(0.12).timeout
	link.pressed.emit()
	await settle()
	var opened:bool=is_instance_valid(app.modal) and (str(app.modal.name)=="HoistLetter" or app.modal.has_meta("hoist_letter"))
	check(opened,"Letter modal opens (%s)"%label)
	return opened

func step_done(index:int)->bool:
	var row:=control("HoistStep%d"%index)
	return row!=null and bool(row.get_meta("done",false))

func catalog_place(label:String)->Button:
	app._build_menu()
	await settle()
	var slot:=control("BuildSlot_glass_furnace_0") as BaseButton
	check(slot!=null,"Build catalog lists 玻璃爐 (%s)"%label)
	if slot==null:return null
	slot.pressed.emit()
	await process_frame
	app._refresh_hud()
	await settle()
	return control("BuildPlace") as Button

func site_clear(a:Vector2i,size:Vector2i)->bool:
	for y in range(a.y,a.y+size.y):
		for x in range(a.x,a.x+size.x):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if not w.is_land(c) or w.water(c) or w.protected(c):return false
			for field in ["objects","ground","roofs","crops","forest"]:
				if w.state[field].has(k):return false
			var had:bool=w.state.removed.has(k)
			w.state.removed[k]=true
			var blocked:bool=w.blocked(c)
			if not had:w.state.removed.erase(k)
			if blocked:return false
	return true

func find_site()->Vector2i:
	var avoid:Array=[Vector2i(World.SPAWN),Vector2i(40,29),Vector2i(43,29),Vector2i(45,34),Vector2i(54,25),World.COPPER_CELL]
	for resident in Village.ids_for_region("home"):avoid.append(Village.NPCS[resident].cell)
	for candidate in World.SHIPPING.CANDIDATES:avoid.append(candidate)
	for candidate in World.COMMUNITY.CANDIDATES:avoid.append(candidate)
	for oy in range(3,57):
		for ox in range(3,77):
			var far:=true
			for a in avoid:
				if Vector2(ox,oy).distance_to(Vector2(a))<7.0:
					far=false
					break
			if not far:continue
			if site_clear(Vector2i(ox-2,oy-2),Vector2i(5,5)):
				for y in range(oy-2,oy+3):
					for x in range(ox-2,ox+3):
						var c:=Vector2i(x,y)
						if w.resource(c)!="":w.state.removed[World.key(c)]=true
				return Vector2i(ox,oy)
	check(false,"Fixture found a legal empty furnace site")
	return Vector2i(-1,-1)

func stand_by_furnace()->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=furnace.x+0.5;person.y=furnace.y+1.6
	await refresh()

## The jinguashi -> home teleport shows the real 1.8 s TravelArrival ribbon right
## over the furnace; press its own 略過 button so the world shot shows the furnace.
func dismiss_arrival()->void:
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon==null:return
	for b in ribbon.find_children("*","Button",true,false):
		if (b as Button).text=="略過":(b as Button).pressed.emit()
	await process_frame
	if is_instance_valid(ribbon) and ribbon.is_inside_tree():app.hud.remove_child(ribbon);ribbon.queue_free()
	await settle()

func build_furnace()->Dictionary:
	sequence+=1
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=furnace.x+0.5;person.y=furnace.y+1.6
	var result:Dictionary=w.act(id,"hoist-scene-build-%d"%sequence,"build",furnace,"glass_furnace")
	app.session._send_snapshot(1)
	return result

func processing()->Dictionary:
	var obj=w.state.objects.get(World.key(furnace),{})
	if not (obj is Dictionary):return {}
	var p=obj.get("processing",{})
	return p if p is Dictionary else {}

func job_count()->int:
	var p:=processing()
	var n:=0
	if p.get("active",null) is Dictionary and not (p.get("active",{}) as Dictionary).is_empty():n+=1
	for field in ["waiting","ready"]:
		if p.get(field,null) is Array:n+=(p.get(field,[]) as Array).size()
	return n

func open_furnace(label:String)->bool:
	await stand_by_furnace()
	app._interact()
	await settle()
	var opened:bool=is_instance_valid(app.modal) and str(app.modal.name)=="ProcessingQueueUI"
	check(opened,"Interact next to the glass furnace opens the processing queue (%s)"%label)
	if not opened:
		ProcessingQueueUI.open(app,furnace)
		await settle()
	return is_instance_valid(app.modal) and str(app.modal.name)=="ProcessingQueueUI"

func enqueue(recipe:String,label:String)->void:
	var before:=job_count()
	var pick:=control("ProcessingRecipe_"+recipe) as BaseButton
	if pick:
		pick.pressed.emit()
		await settle()
		var button:=control("ProcessingEnqueue") as BaseButton
		if button and not button.disabled:
			button.pressed.emit()
			for i in range(4):await settle()
	var via_ui:=job_count()==before+1
	check(via_ui,"ProcessingEnqueue queues %s through the UI (%s)"%[recipe,label])
	if not via_ui:
		sequence+=1
		var r:Dictionary=w.act(id,"hoist-scene-queue-%d"%sequence,"queue_processing",furnace,recipe)
		check(bool(r.get("ok",false)),"Fallback World.act queues %s: %s"%[recipe,r.get("message","")])
		app.session._send_snapshot(1)
		await settle()

func clear_furnace()->void:
	for i in range(3):
		w.step(120.1,true)
		sequence+=1
		w.act(id,"hoist-scene-claim-%d"%sequence,"claim_processing",furnace)
	app.session._send_snapshot(1)

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/升降台與玻璃爐預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	var path:=OS.get_environment("TEMP").path_join("hoist-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"升降台旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.picnic=true;w.state.board=true
	furnace=find_site()
	var cost:Dictionary=World.MINES.HOIST_COST
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		w.state.players[id].mine_energy=60
		stock({"copper_joint":0,"plank":0})
		# PRESET: the furnace from the previous size is removed first, because a
		# save may not hold a glass furnace while the hoist is still stuck.
		if furnace_built:
			w.state.objects.erase(World.key(furnace))
			furnace_built=false
		progress(15,false)  # PRESET: B15 reached by stairs, hoist still stuck
		# 1. Entry card, stuck, no materials.
		await place("jinguashi",World.MINES.ENTRY)
		UI.open(app,"entry");await settle()
		fits("entry stuck empty "+tag)
		has_texts(["升降台卡住了。","波波需要材料修理。","交付修理材料",
			"%s  %d／%d"%[World.NAMES.get("copper_joint","copper_joint"),0,int(cost.get("copper_joint",0))],
			"%s  %d／%d"%[World.NAMES.get("plank","plank"),0,int(cost.get("plank",0))]],"entry stuck empty "+tag)
		var repair:=control("MineHoistRepairButton") as Button
		check(repair!=null and repair.disabled,"Repair button disabled without materials at "+tag)
		var img_empty:Image=await shot("entry-stuck-empty-%s"%tag)
		app._close_modal()
		# 4a. Letter mid-progress.
		var img_letter_before:Image=null
		if await open_letter("before "+tag):
			fits("letter before "+tag)
			check(step_done(1) and not step_done(2) and not step_done(4),"Letter mid-progress (step 1 done only) at "+tag)
			has_texts(["波波","0／12","0／4"],"letter before "+tag)
			img_letter_before=await shot("letter-before-%s"%tag)
		app._close_modal()
		# 5a. Build folio, furnace locked.
		var locked:Button=await catalog_place("before "+tag)
		var img_folio_before:Image=null
		if is_instance_valid(app.modal):
			fits("folio locked "+tag,true)
			folio_layout("locked "+tag)
			check(visible(control("BuildSlot_glass_furnace_0")),"Selected 玻璃爐 slot is on view (locked %s)"%tag)
			check(visible(locked),"Locked BuildPlace button on view at "+tag)
			check(locked!=null and locked.disabled and locked.text=="完成卡住的升降台","Folio shows 玻璃爐 locked at "+tag)
			has_texts(["玻璃爐","修好金瓜石的升降台後解鎖。"],"folio locked "+tag)
			img_folio_before=await shot("folio-furnace-locked-%s"%tag)
		app._close_modal()
		# 2. Entry card with materials.
		stock(cost.duplicate())  # PRESET materials
		await place("jinguashi",World.MINES.ENTRY)
		UI.open(app,"entry");await settle()
		fits("entry stuck stocked "+tag)
		has_texts(["%s  %d／%d"%[World.NAMES.get("copper_joint","copper_joint"),12,12],"%s  %d／%d"%[World.NAMES.get("plank","plank"),4,4]],"entry stocked "+tag)
		repair=control("MineHoistRepairButton") as Button
		check(repair!=null and not repair.disabled and visible(repair),"Repair button enabled with materials at "+tag)
		var img_stocked:Image=await shot("entry-stuck-stocked-%s"%tag)
		differ(img_empty,img_stocked,"entry empty vs stocked at "+tag)
		# 3. Real repair through the button.
		await press("MineHoistRepairButton")
		await settle()
		check(bool(w.state.mine_depths.get("hoist",false)),"Repair button commits the hoist repair at "+tag)
		app.session._send_snapshot(1)
		UI.refresh(app);await settle()
		fits("entry repaired "+tag)
		check(control("MineHoistRepair")==null,"Repair section gone at "+tag)
		has_texts(["升降台已修好，可直達已開通的停靠層。"],"entry repaired "+tag)
		for depth in [6,10,15]:
			var lift:=control("MineLift%d"%depth) as BaseButton
			check(lift!=null and visible(lift) and not lift.disabled,"Landing B%d unlocked on the entry card at %s"%[depth,tag])
		var img_repaired:Image=await shot("entry-repaired-%s"%tag)
		differ(img_stocked,img_repaired,"entry stocked vs repaired at "+tag)
		app._close_modal()
		# 4b. Letter completed.
		if await open_letter("after "+tag):
			fits("letter after "+tag)
			for index in range(1,5):check(step_done(index),"Letter step %d done at %s"%[index,tag])
			var reply:=control("HoistLetterReply") as Label
			check(reply!=null and reply.is_visible_in_tree() and reply.text.contains("玻璃爐"),"Completed reply mentions 玻璃爐 at "+tag)
			var img_letter_after:Image=await shot("letter-after-%s"%tag)
			differ(img_letter_before,img_letter_after,"letter before vs after at "+tag)
		app._close_modal()
		# 5b. Build folio, furnace unlocked.
		check(BuildFolio.unlocked(app,w.state.players[id],"glass_furnace"),"Glass furnace unlocked after the repair at "+tag)
		var unlocked_place:Button=await catalog_place("after "+tag)
		if is_instance_valid(app.modal):
			fits("folio unlocked "+tag,true)
			folio_layout("unlocked "+tag)
			check(visible(control("BuildSlot_glass_furnace_0")),"Selected 玻璃爐 slot is on view (unlocked %s)"%tag)
			check(visible(unlocked_place),"BuildPlace button on view at "+tag)
			check(unlocked_place!=null and not unlocked_place.disabled,"Folio lets 玻璃爐 be placed at "+tag)
			has_texts(["玻璃爐"],"folio unlocked "+tag)
			var img_folio_after:Image=await shot("folio-furnace-unlocked-%s"%tag)
			differ(img_folio_before,img_folio_after,"folio locked vs unlocked at "+tag)
		app._close_modal()
		# 6. Built furnace in the world + its processing queue.
		if furnace.x<0:continue
		if not furnace_built:
			stock(FURNACE_KIT.duplicate())  # PRESET build kit
			var built:=build_furnace()
			check(bool(built.get("ok",false)),"World builds the furnace after the repair: %s"%built.get("message",""))
			var obj=w.state.objects.get(World.key(furnace),{})
			furnace_built=obj is Dictionary and str(obj.get("type",""))=="glass_furnace"
			check(furnace_built,"Glass furnace object placed")
		if not furnace_built:continue
		await stand_by_furnace()
		await dismiss_arrival()
		check(app.hud.get_node_or_null("TravelArrival")==null,"Arrival ribbon dismissed before the world shot at "+tag)
		check(not is_instance_valid(app.modal),"No modal over the world view at "+tag)
		# PRESET placement: one cell east of the furnace so the sprite is not hidden behind the player.
		var person:Dictionary=w.state.players[id]
		person.x=furnace.x+1.5;person.y=furnace.y+0.9
		await refresh()
		await dismiss_arrival()
		await shot("furnace-world-%s"%tag)
		stock({"crystal_sand":3,"wood":1,"vein_quartz":2})  # PRESET recipe inputs
		if await open_furnace("queue "+tag):
			for product in ["glass","crystal_sand"]:
				var b:=control("ProcessingRecipe_"+product)
				check(b!=null and visible(b),"Furnace lists recipe %s on screen at %s"%[product,tag])
			await enqueue("glass","queue "+tag)
			await enqueue("crystal_sand","queue "+tag)
			app._close_modal()
		if await open_furnace("queued "+tag):
			check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Furnace queue fits viewport (queued %s)"%tag)
			has_texts(["玻璃爐","加工中：","等候中（1）","成品架（0）"],"furnace queued "+tag)
			var img_queued:Image=await shot("furnace-queue-queued-%s"%tag)
			app._close_modal()
			w.step(120.1,true)  # FAST-FORWARD: glass finishes, crystal sand starts
			app.session._send_snapshot(1)
			if await open_furnace("ready "+tag):
				check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Furnace queue fits viewport (ready %s)"%tag)
				has_texts(["成品架（1）","領取最早完成："],"furnace ready "+tag)
				var claim:=control("ProcessingClaim") as BaseButton
				check(claim!=null and visible(claim) and not claim.disabled,"Claim button enabled with a ready product at "+tag)
				var img_ready:Image=await shot("furnace-queue-ready-%s"%tag)
				differ(img_queued,img_ready,"furnace queued vs ready at "+tag)
		app._close_modal()
		clear_furnace()  # FAST-FORWARD + claim so the next size starts empty
		check(job_count()==0,"Furnace queue cleared after %s"%tag)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()

func finish()->void:
	print("MINE_HOIST_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
