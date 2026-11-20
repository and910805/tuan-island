extends SceneTree
## C11 石工台 UI + real recipe flow through the main scene (local host). Not run by the author (no
## Godot in the authoring session): Codex runs it.
##
## Covers: Build Folio lock state before/after Q03 (earned through the real donate action), normal
## build-tool placement, opening the compact recipe card from the FAR end, material icons/amounts, the
## Q05 foundation craft through the real button, C09/C10 routed through the station, locked stone
## furniture staying locked, a real save -> load_world round trip, and the art fallback contract.

const World:=preload("res://scripts/world.gd")
const Stone:=World.STONE_WORKSHOP
const BuildFolio:=preload("res://scripts/build_folio.gd")
const WorldView:=preload("res://scripts/world_view.gd")
const KIND:="stone_workbench"
const BOARD:=Vector2i(40,29)
const SITE:=Vector2i(40,35)
const FAR:=Vector2i(41,35)
const FLOOR_TILE:=Vector2i(43,37)
const SMELTER_SITE:=Vector2i(47,37)
const BRIDGE_TILE:=Vector2i(55,30)

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0
var serial:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(at:Vector2) -> void:
	person.x=at.x
	person.y=at.y
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func button(id:String) -> Button:
	return node(id) as Button

func label_text(id:String) -> String:
	var found:=node(id) as Label
	return found.text if found!=null else ""

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:target.pressed.emit()
	await process_frame
	await process_frame

func act(action:String,tile:Vector2i,extra:="") -> Dictionary:
	serial+=1
	return world.act(token,"stone-ui-%d"%serial,action,tile,extra)

func modal_closed() -> bool:
	return app.modal==null or not is_instance_valid(app.modal)

func open_folio_slot(kind:String) -> void:
	app._build_menu()
	await process_frame
	var slot:=app.modal.find_child("BuildSlot_%s_0"%kind,true,false) as Button
	expect(slot!=null,"The build shelf lists "+kind)
	if slot!=null:slot.pressed.emit()
	await process_frame

func run() -> void:
	root.size=Vector2i(1152,720)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://stone-workbench-ui-%d.json"%OS.get_process_id()
	if app.session.host(0,"石工島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]

	# --- 1. Locked before Q03: shelf, folio and the server all agree -------------------------------
	person.inventory={"wood":100,"stone":100,"copper_ore":10,"fiber":20}
	stand(Vector2(40.5,36.5))
	expect(not BuildFolio.unlocked(app,person,KIND),"The shelf mirrors the lock before Q03")
	expect(not act("build",SITE,KIND).ok and not world.state.objects.has(World.key(SITE)),"The server refuses the station before Q03")
	await open_folio_slot(KIND)
	var place:=button("BuildPlace")
	expect(place!=null and place.disabled and label_text("BuildStatus")=="圖樣未解鎖","The folio shows the locked state")
	expect(label_text("BuildDescription").contains("公告板"),"The lock text names the board repair")
	app._close_modal()

	# --- 2. Real Q03: the donate action, never a UI flag ------------------------------------------
	person.inventory={"wood":30,"stone":10}
	stand(Vector2(40.5,30.5))
	var donated:=act("donate",BOARD)
	expect(donated.ok and world.state.board==true,"Q03 completes through donate: "+str(donated.get("message","")))
	person.inventory={"wood":100,"stone":100,"copper_ore":10,"fiber":20}
	stand(Vector2(40.5,36.5))
	expect(BuildFolio.unlocked(app,person,KIND) and not BuildFolio.unlocked(app,person,"stone_floor") and not BuildFolio.unlocked(app,person,"small_smelter"),"After Q03 the station opens; R11/R12 still wait for it")
	await open_folio_slot(KIND)
	place=button("BuildPlace")
	expect(place!=null and not place.disabled and label_text("BuildTitle").contains("石工台"),"The folio unlocks 石工台")
	expect(node("BuildMaterial0")!=null and node("BuildMaterial1")!=null,"The recipe card lists its two materials")
	await press("BuildPlace")
	expect(app.building==KIND and app.selected=="build" and modal_closed(),"Choosing the recipe selects the normal build tool")
	stand(Vector2(40.5,36.5))
	app._perform_build_action("build",SITE,KIND)
	await process_frame
	var anchor:Dictionary=world.state.objects.get(World.key(SITE),{})
	var far_cell:Dictionary=world.state.objects.get(World.key(FAR),{})
	expect(anchor.get("type")==KIND and anchor.get("stone_bench_part")==0 and far_cell.get("stone_bench_part")==1,"The build tool places both cells")
	expect(int(person.inventory.stone)==80 and int(person.inventory.wood)==92,"It cost 20 stone and 8 wood")
	expect(world.blocked(SITE) and world.blocked(FAR),"Both cells block walking")
	# Q05 wood and rope go in at the board first (real action); the foundations then come from the station card.
	person.inventory.rope=5
	stand(Vector2(40.5,30.5))
	var q05:=act(Stone.DONATE_ACTION,BOARD)
	expect(q05.ok and int(world.state.bridge_project.wood)==60 and int(world.state.bridge_project.rope)==4 and int(person.inventory.wood)==32 and int(person.inventory.rope)==1 and world.water(BRIDGE_TILE),"Q05 wood and rope are donated at the board and the river stays closed: "+str(q05.get("message","")))

	# --- 3. The compact recipe card, opened from the FAR end -------------------------------------
	stand(Vector2(41.5,36.5))
	app._interact()
	await process_frame
	expect(node("StoneWorkbenchSummary")!=null,"Interacting at the far end opens the station card")
	for entry:Dictionary in Stone.RECIPES:
		var panel:=node("StoneRecipe_"+entry.id)
		expect(panel!=null,"Recipe row: "+entry.id)
		if panel==null:continue
		var chips:=0
		for child in panel.find_children("Material_*","HBoxContainer",true,false):
			chips+=1
			var icon:=child.get_child(0) as TextureRect
			var count:=child.get_child(1) as Label
			expect(icon!=null and icon.texture!=null and count!=null and count.text.contains("／"),"%s shows a material icon and held／needed"%entry.id)
		expect(chips>=1,"%s lists at least one material"%entry.id)
	expect(node("Material_copper_ore")!=null and node("Material_clay")!=null and node("Material_hardwood")!=null,"Smelter, footbath and furniture rows show their real materials")
	expect(label_text("StoneWorkbenchSummary").contains("0／2"),"The summary shows the Q05 foundation count: "+label_text("StoneWorkbenchSummary"))
	var footbath:=button("StoneRoute_inn_stone_footbath")
	expect(footbath!=null and footbath.disabled,"Resident-gated stone furniture stays locked on the card")

	# --- 4. Q05 through the real craft button ----------------------------------------------------
	await press("StoneCraft_bridge_foundation")
	expect(int(world.state.bridge_project.foundations)==1 and int(person.inventory.stone)==70,"One foundation crafted for 10 stone")
	expect(world.water(BRIDGE_TILE),"One foundation is not enough: the river stays closed")
	stand(Vector2(41.5,36.5))
	expect(label_text("StoneWorkbenchSummary").contains("1／2"),"The card refreshes its progress")
	await press("StoneCraft_bridge_foundation")
	expect(world.state.bridge_project.done==true and not world.water(BRIDGE_TILE),"The second foundation opens the bridge")
	stand(Vector2(41.5,36.5))
	var craft:=button("StoneCraft_bridge_foundation")
	expect(craft!=null and craft.disabled,"The craft button retires once the bridge is open")

	# --- 5. C09 / C10 through the station routes -------------------------------------------------
	person.inventory={"wood":20,"stone":60,"copper_ore":10,"hardwood":10}
	stand(Vector2(41.5,36.5))
	expect(BuildFolio.unlocked(app,person,"stone_floor") and BuildFolio.unlocked(app,person,"small_smelter"),"With a station on the island R11/R12 unlock")
	await press("StoneRoute_stone_floor")
	expect(app.building=="stone_floor" and app.selected=="build" and modal_closed(),"The R11 row selects the stone floor build tool")
	stand(Vector2(FLOOR_TILE.x+0.5,FLOOR_TILE.y+1.5))
	app._perform_build_action("build",FLOOR_TILE,"stone_floor")
	await process_frame
	expect(str(world.state.ground.get(World.key(FLOOR_TILE),{}).get("type",""))=="stone_floor" and int(person.inventory.stone)==58,"R11: one stone floor for 2 stone")
	stand(Vector2(41.5,36.5))
	app._interact()
	await process_frame
	await press("StoneRoute_small_smelter")
	expect(app.building=="small_smelter" and app.selected=="build","The R12 row selects the small smelter build tool")
	for offset:Vector2i in World.INDUSTRY.SMELTER_CELLS:
		world.state.removed[World.key(SMELTER_SITE+offset)]=true
	stand(Vector2(SMELTER_SITE.x+0.5,SMELTER_SITE.y+2.5))
	app._perform_build_action("build",SMELTER_SITE,"small_smelter")
	await process_frame
	expect(world.state.objects.get(World.key(SMELTER_SITE),{}).get("type")=="small_smelter" and int(person.inventory.stone)==33 and int(person.inventory.copper_ore)==5,"R12: the smelter costs 25 stone and 5 copper ore")
	stand(Vector2(41.5,36.5))
	app._interact()
	await process_frame
	await press("StoneRoute_spring_stone_bench")
	expect(app.building=="spring_stone_bench","The stone furniture row routes to the normal build tool")
	app._select_tool("pick")

	# --- 6. Real save -> load -------------------------------------------------------------------
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.board==true,"The save reloads and Q03 is still done")
	expect(loaded.state.objects.get(World.key(FAR),{}).get("stone_bench_part")==1 and loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND,"The station survives the restart")
	var project:Dictionary=loaded.state.get(Stone.PROJECT_KEY,{})
	expect(int(project.get("foundations",-1))==2 and project.get("done")==true and not loaded.water(BRIDGE_TILE),"Q05 progress and the open bridge survive the restart")
	expect(str(loaded.state.ground.get(World.key(FLOOR_TILE),{}).get("type",""))=="stone_floor" and loaded.state.objects.has(World.key(SMELTER_SITE)),"The routed C09/C10 pieces survive the restart")

	# --- 7. Art contract: dedicated textures when supplied, fallback otherwise ----------------------
	var view:=WorldView.new()
	var wide:=view.stone_workbench_texture(false)
	var tall:=view.stone_workbench_texture(true)
	expect(wide==null or wide.get_size()==Vector2(64,32),"stone-workbench-wide.png is 64x32 when present")
	expect(tall==null or tall.get_size()==Vector2(32,64),"stone-workbench-tall.png is 32x64 when present")
	view.free()

	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("STONE_WORKBENCH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
