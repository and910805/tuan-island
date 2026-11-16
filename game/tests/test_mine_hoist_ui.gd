extends SceneTree
## Q07 「卡住的升降台」 UI test: surface entry card repair section, the 波波 story
## letter, the 玻璃爐 build-catalog gate and the glass furnace processing queue.
## Same harness as test_mine_deep_ui.gd. Run with `-- --village-art-preview`.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP%; picnic + board flags set directly;
##  * mine progress is written directly via progress(): unlocked 5 or 6, pumped 24,
##    `hoist` false (reset before each viewport size);
##  * copper_joint / plank and the glass furnace build materials are written
##    directly into the backpack; the player is teleported next to each station;
##  * the hoist repair itself goes through the real UI button -> Session.perform
##    ("mine_hoist_repair") -> World path; the furnace is built once through
##    World.act("build") after the repair (and refused before it).
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
var furnace:=Vector2i(-1,-1)
var furnace_built:=false
var sequence:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and app.modal.get_global_rect().grow(0.5).encloses(c.get_global_rect())

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(name,true,false) as Control

func texts()->String:
	var out:=PackedStringArray()
	for label in app.modal.find_children("*","Label",true,false):out.append(label.text)
	return "\n".join(out)

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	app.session._send_snapshot(1)

func progress(unlocked:int,hoist:bool)->void:
	w.state.mine_depths={"unlocked":unlocked,"ready":{},"pumped":24,"hoist":hoist}
	app.session._send_snapshot(1)

func stock(items:Dictionary)->void:
	w.state.players[id].inventory.merge(items,true)
	app.session._send_snapshot(1)

func settle()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame

func fits(label:String)->void:
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Modal fits viewport: "+label)
	var scroll:=control("ModalScroll") as ScrollContainer
	if scroll:check(not scroll.get_v_scroll_bar().visible,"Content fits without scrolling: "+label)
	for c in app.modal.find_children("*","BaseButton",true,false):
		check(visible(c) and inside_modal(c),"Button fully visible inside the card: %s (%s)"%[c.name,label])
	for label_node:Label in app.modal.find_children("*","Label",true,false):
		if label_node.is_visible_in_tree():check(inside_modal(label_node),"Caption inside the card: %s (%s)"%[label_node.text,label])

func open(site:String,label:String)->void:
	UI.open(app,site)
	await settle()
	await fits("%s %s %s"%[site,label,root.size])

func enabled(name:String)->bool:
	var button:=control(name) as BaseButton
	return button!=null and visible(button) and not button.disabled

func press(name:String)->bool:
	var button:=control(name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await process_frame
	return true

func count_text(item:String,have:int,need:int)->String:
	return "%s  %d／%d"%[World.NAMES.get(item,item),have,need]

# ------------------------------------------------------------- letter --

func open_letter(label:String)->bool:
	app._chapter_menu()
	await settle()
	var link:=control("HoistLetterLink") as BaseButton
	check(link!=null,"Island story lists 卡住的升降台 (%s)"%label)
	if link==null:return false
	await create_timer(0.12).timeout
	link.pressed.emit()
	await settle()
	check(is_instance_valid(app.modal) and (str(app.modal.name)=="HoistLetter" or app.modal.has_meta("hoist_letter")),"Letter modal opens (%s)"%label)
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Letter fits viewport (%s %s)"%[label,root.size])
	return true

func step_done(index:int)->bool:
	var row:=control("HoistStep%d"%index)
	return row!=null and bool(row.get_meta("done",false))

func step_text(index:int)->String:
	var row:=control("HoistStep%d"%index)
	if row==null:return ""
	var out:=PackedStringArray()
	for label in row.find_children("*","Label",true,false):out.append(label.text)
	return "\n".join(out)

# ------------------------------------------------------------ catalog --

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

# ------------------------------------------------------------ furnace --

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

func build_furnace()->Dictionary:
	sequence+=1
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=furnace.x+0.5;person.y=furnace.y+1.6
	var result:Dictionary=w.act(id,"hoist-ui-build-%d"%sequence,"build",furnace,"glass_furnace")
	app.session._send_snapshot(1)
	return result

func open_furnace(label:String)->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=furnace.x+0.5;person.y=furnace.y+1.6
	app.session._send_snapshot(1)
	await settle()
	app._interact()
	await settle()
	var opened:=is_instance_valid(app.modal) and str(app.modal.name)=="ProcessingQueueUI"
	check(opened,"Interact next to the glass furnace opens the processing queue (%s)"%label)
	if not opened:
		ProcessingQueueUI.open(app,furnace)
		await settle()
	check(is_instance_valid(app.modal) and root.get_visible_rect().encloses(app.modal.get_global_rect()),"Furnace queue fits viewport (%s)"%label)
	var header:=control("ProcessingHeader")
	var header_text:=""
	if header:
		for node:Label in header.find_children("*","Label",true,false):header_text+=node.text
	check(header_text.contains("玻璃爐"),"Furnace header names 玻璃爐 (%s): %s"%[label,header_text])
	var icon:=control("ProcessingStationIcon") as TextureRect
	check(icon!=null and icon.texture!=null,"Furnace header has a station picture (%s)"%label)
	for product in ["glass","crystal_sand"]:
		var button:=control("ProcessingRecipe_"+product)
		check(button!=null,"Furnace lists the %s recipe (%s)"%[product,label])
		if button==null:continue
		var art:TextureRect=null
		for child in button.get_children():
			if child is TextureRect:art=child
		check(art!=null and art.texture!=null,"Furnace recipe %s has an icon (%s)"%[product,label])
		check(root.get_visible_rect().encloses(button.get_global_rect()),"Furnace recipe %s on screen (%s)"%[product,label])
	for name in ["ProcessingManualTab","ProcessingAutoTab","ProcessingFeed","ProcessingToggleAuto"]:
		var node:=control(name)
		check(node==null or not node.is_visible_in_tree(),"Furnace is manual-only, no %s (%s)"%[name,label])
	check(control("ProcessingEnqueue")!=null,"Furnace offers the manual queue (%s)"%label)

# ---------------------------------------------------------------- run --

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("hoist-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"升降台旅人",path)!=OK:check(false,"Host starts");print("MINE_HOIST_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(1);return
	w=app.session.world;id=app.session.profile.token
	w.state.picnic=true;w.state.board=true
	furnace=find_site()
	var cost:Dictionary=World.MINES.HOIST_COST
	check(int(cost.get("copper_joint",0))==12 and int(cost.get("plank",0))==4,"Hoist cost is 12 copper joints + 4 planks")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		w.state.players[id].mine_energy=60
		stock({"copper_joint":0,"plank":0})
		# Before B6: no repair section, no letter link.
		progress(5,false)
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","unlocked 5")
		check(control("MineHoistRepair")==null and control("MineHoistReady")==null,"No hoist section before B6 at "+tag)
		check(control("MineLiftLandings")==null,"No surface landings before B6 at "+tag)
		app._chapter_menu();await settle()
		check(control("HoistLetterLink")==null,"Letter link hidden before B6 at "+tag)
		app._close_modal()
		# B6 open, hoist stuck, no materials.
		progress(6,false)
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","stuck empty")
		var section:=control("MineHoistRepair")
		check(section!=null and section.is_visible_in_tree(),"Stuck hoist shows MineHoistRepair at "+tag)
		check("升降台卡住了。" in texts() and "波波需要材料修理。" in texts(),"Repair caption names 波波 at "+tag)
		check(control("MineHoistRequirements")!=null and control("MineHoistRequirements").get_child_count()==cost.size(),"One badge per hoist material at "+tag)
		for item in cost:
			var badge_text:=control("MineHoistCount_"+str(item)) as Label
			check(badge_text!=null and badge_text.text==count_text(str(item),0,int(cost[item])),"Badge shows have／need for %s at %s"%[item,tag])
			check(control("MineHoistNeed_"+str(item))!=null and visible(control("MineHoistNeed_"+str(item))),"Badge visible for %s at %s"%[item,tag])
		var repair:=control("MineHoistRepairButton") as Button
		check(repair!=null and repair.text=="交付修理材料" and repair.disabled,"Repair button disabled without materials at "+tag)
		check(control("MineLiftLandings")==null and control("MineLift6")==null,"No surface lift before the repair at "+tag)
		check(control("MineHoistReady")==null,"No ready caption before the repair at "+tag)
		check(enabled("MineEnter"),"Stairs into B1 stay usable at "+tag)
		# Letter before the repair.
		if await open_letter("before "+tag):
			check(step_done(1),"Step 1 (B6 open) is checked at "+tag)
			check(not step_done(2) and step_text(2).contains("0／12") and step_text(2).contains("0／4"),"Step 2 shows have／need at "+tag)
			check(not step_done(3) and not step_done(4),"Steps 3–4 pending before the repair at "+tag)
			for index in range(1,5):check(control("HoistStep%d"%index)!=null,"HoistStep%d exists at %s"%[index,tag])
			check(control("HoistLetterReply")==null or not control("HoistLetterReply").is_visible_in_tree(),"No reply before the repair at "+tag)
			check("波波" in texts(),"Letter is signed by 波波 at "+tag)
		app._close_modal()
		# Catalog before the repair.
		check(not BuildFolio.unlocked(app,w.state.players[id],"glass_furnace"),"Glass furnace locked before the repair")
		var locked:Button=await catalog_place("before "+tag)
		check(locked!=null and locked.disabled and locked.text=="完成卡住的升降台","Catalog shows 玻璃爐 locked before the repair at "+tag)
		check("修好金瓜石的升降台後解鎖。" in texts(),"Catalog explains the furnace gate at "+tag)
		app._close_modal()
		if not furnace_built and furnace.x>=0:
			stock(FURNACE_KIT.duplicate())
			var refused:=build_furnace()
			check(not bool(refused.get("ok",false)) and str(refused.get("message","")).contains("升降台"),"World refuses the furnace before the repair: %s"%refused.get("message",""))
		# Materials in hand: button enables, press through the real session path.
		stock(cost.duplicate())
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","stuck stocked")
		for item in cost:
			var stocked_text:=control("MineHoistCount_"+str(item)) as Label
			check(stocked_text!=null and stocked_text.text==count_text(str(item),int(cost[item]),int(cost[item])),"Badge shows full stock for %s at %s"%[item,tag])
		check(enabled("MineHoistRepairButton"),"Repair button enabled with materials nearby at "+tag)
		place("jinguashi",World.MINES.ENTRY+Vector2i(8,6))
		UI.refresh(app);await settle()
		check(control("MineHoistRepairButton")!=null and (control("MineHoistRepairButton") as Button).disabled,"Repair button disabled when far from the sign at "+tag)
		place("jinguashi",World.MINES.ENTRY)
		UI.refresh(app);await settle()
		await press("MineHoistRepairButton")
		await settle()
		check(bool(w.state.mine_depths.get("hoist",false)),"Repair button commits the hoist repair at "+tag)
		for item in cost:check(int(w.state.players[id].inventory.get(item,0))==0,"Repair spent %s at %s"%[item,tag])
		UI.refresh(app);await settle()
		await fits("entry repaired %s"%tag)
		check(control("MineHoistRepair")==null,"Repair section gone after the repair at "+tag)
		var ready:=control("MineHoistReady") as Label
		check(ready!=null and ready.text=="升降台已修好，可直達已開通的停靠層。","Ready caption after the repair at "+tag)
		check(control("MineLiftLandings")!=null and enabled("MineLift6"),"Surface lift to B6 appears after the repair at "+tag)
		check(control("MineLift10")==null,"Only opened landings are offered at "+tag)
		await press("MineLift6")
		check(str(app.session.snapshot.region_id)=="mine_6","Repaired hoist lowers to B6 at "+tag)
		app._close_modal()
		# Letter after the repair (re-readable, completed reply).
		if await open_letter("after "+tag):
			for index in range(1,5):check(step_done(index),"Step %d checked after the repair at %s"%[index,tag])
			var reply:=control("HoistLetterReply") as Label
			check(reply!=null and reply.is_visible_in_tree() and reply.text.contains("玻璃爐"),"Completed reply mentions the furnace plan at "+tag)
		app._close_modal()
		# Catalog after the repair.
		check(BuildFolio.unlocked(app,w.state.players[id],"glass_furnace"),"Glass furnace unlocked after the repair")
		var unlocked_place:Button=await catalog_place("after "+tag)
		check(unlocked_place!=null and not unlocked_place.disabled,"Catalog lets 玻璃爐 be chosen after the repair at "+tag)
		app._close_modal()
		# Furnace queue UI.
		if furnace.x>=0:
			if not furnace_built:
				stock(FURNACE_KIT.duplicate())
				var built:=build_furnace()
				check(bool(built.get("ok",false)),"World builds the furnace after the repair: %s"%built.get("message",""))
				var obj=w.state.objects.get(World.key(furnace),{})
				furnace_built=obj is Dictionary and str(obj.get("type",""))=="glass_furnace"
				check(furnace_built,"Glass furnace object placed")
			if furnace_built:await open_furnace(tag)
			app._close_modal()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	if checks==0:failures+=1
	print("MINE_HOIST_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
