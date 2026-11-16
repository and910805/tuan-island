extends SceneTree
## SEEDED UI FIXTURE: world.state records are injected directly per site/phase to
## exercise the flower nursery panels. This is not a natural-acquisition journey
## (see test_flower_journey.gd for that). Action buttons are pressed for real and
## routed through app.session.perform -> World.act.

const World=preload("res://scripts/world.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const FlowerUI=preload("res://scripts/flower_nursery_ui.gd")
const FlowerArt=preload("res://scripts/flower_art.gd")
const Resident=preload("res://scripts/flower_resident_art.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const SIZES:=[Vector2i(1024,640),Vector2i(1280,720),Vector2i(1280,800),Vector2i(1920,1080)]
var app
var world
var actor:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func control(id:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(id,true,false) as Control

func text_of(id:String)->String:
	var item:=control(id)
	if item is Label:return (item as Label).text
	if item is Button:return (item as Button).text
	return ""

func button(id:String)->Button:
	return control(id) as Button

func visible(item:Control)->bool:
	if not item or not item.is_visible_in_tree() or not root.get_visible_rect().encloses(item.get_global_rect()):return false
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().grow(1).encloses(item.get_global_rect()):return false
		parent=parent.get_parent()
	return true

## main.gd's "flower_nursery" layout case is wired later by flower_exec_scene; until
## then the test applies FlowerUI.layout after main's own (deferred) layout pass.
func settle()->void:
	for i in range(4):await process_frame
	app._layout_preview()
	for i in range(3):
		FlowerUI.layout(app,Vector2(root.size))
		await process_frame

func record()->Dictionary:
	return Flower.own_record(world.state,actor)

func person()->Dictionary:
	return world.state.players[actor]

func publish()->void:
	app.session._send_snapshot(1)
	FlowerUI.refresh(app)

## Seed one consistent player state (record keys exactly FRESH).
func seed_state(region:String,cell:Vector2i,fields:Dictionary,inventory:Dictionary,garden:Dictionary={},unlocked:=true)->void:
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	if unlocked:
		tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1;tea.tea_discussed=true;tea.potter_story=true
		tea.trials={"jar":true,"fiber":true};tea.comparison_complete=true
	world.state.tea_ceramics.players[actor]=tea
	var flower:Dictionary=Flower.FRESH.duplicate(true)
	for key in fields:flower[key]=fields[key]
	world.state.flower_nursery.players[actor]=flower
	var shared:=Flower.garden_fresh()
	for key in garden:shared[key]=garden[key]
	world.state.flower_nursery.garden=shared
	var p:=person()
	p.travel_book.visited[Flower.REGION]=bool(fields.get("intro",false)) or region==Flower.REGION
	for id in Flower.NAMES:p.inventory.erase(id)
	for id in inventory:
		if id!="coins":p.inventory[id]=inventory[id]
	p.coins=int(inventory.get("coins",p.coins))
	p.region=region
	p.x=cell.x+0.5
	p.y=cell.y+1.5
	publish()

func open(site:String)->void:
	app._close_modal()
	FlowerUI.open(app,site)
	await settle()
	check(is_instance_valid(app.modal) and app.modal.get_meta("flower_site","")==site,"Opens flower site "+site)

func capture_workwear(name:String)->void:
	var directory:=OS.get_environment("WORKWEAR_QA_OUTPUT")
	if directory.is_empty():return
	app._close_modal()
	await settle()
	var banners:Array[Control]=[]
	for id in ["WanganArrival","TravelArrival"]:
		var banner:=app.hud.get_node_or_null(id) as Control
		if banner and banner.visible:
			banners.append(banner)
			banner.hide()
	RenderingServer.force_draw()
	var frame:=root.get_texture().get_image()
	check(frame.save_png(directory.path_join(name+".png"))==OK,"captures "+name+" workwear on the map")
	for banner in banners:banner.show()
	await open("dye")

func scroll_to(item:Control)->void:
	if not item:return
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer:parent.ensure_control_visible(item)
		parent=parent.get_parent()
	await process_frame
	await process_frame

func press(id:String)->void:
	await settle()
	var target:=button(id)
	if target and not visible(target):await scroll_to(target)
	check(target!=null and visible(target) and not target.disabled,"Enabled and visible "+id)
	if target and not target.disabled:
		target.pressed.emit()
	await process_frame
	FlowerUI.refresh(app)
	await settle()

func disabled_with(id:String,reason:String)->void:
	var target:=button(id)
	var note:=control(id+"Reason") as Label
	check(target!=null and target.disabled,id+" disabled")
	check(note!=null and visible(note) and reason in note.text,"%s reason visible: want '%s' got '%s'"%[id,reason,note.text if note else "<none>"])
	check(target!=null and reason in target.tooltip_text,id+" tooltip carries reason")

func fit(name:String)->void:
	for size in SIZES:
		root.size=size
		await settle()
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"%s modal within %s"%[name,size])
		if app.modal.get_meta("flower_site","")!="journal":
			check(app.modal.size.y<=FlowerUI.content_height(app)+1.0,"%s modal sized to content at %s (%.0f vs %.0f)"%[name,size,app.modal.size.y,FlowerUI.content_height(app)])
		var scroll:=control("ModalScroll") as ScrollContainer
		var bar:=scroll.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"%s fits without scrolling at %s (content %.0f page %.0f)"%[name,size,bar.max_value,bar.page])
		for item in app.modal.find_children("*","Button",true,false):
			if item.visible:check(visible(item),"%s %s button visible: %s"%[name,size,item.name])
		for item in app.modal.find_children("*","Label",true,false):
			var label:=item as Label
			if not label.is_visible_in_tree() or label.text.is_empty():continue
			check(label.size.x+0.5>=label.get_minimum_size().x and label.size.y+0.5>=label.get_minimum_size().y,"%s %s label not clipped: %s '%s'"%[name,size,label.name,label.text.left(24)])
			check(label.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING or label.get_line_count()<=label.get_visible_line_count(),"%s label not truncated %s"%[name,label.name])
	root.size=SIZES[0]
	await settle()

func focus_reaches_all(name:String)->void:
	var buttons:Array=[]
	for item in app.modal.find_children("*","BaseButton",true,false):
		if item.is_visible_in_tree() and not item.disabled:buttons.append(item)
	if buttons.is_empty():return
	var first:Control=buttons[0]
	first.grab_focus()
	await process_frame
	check(root.gui_get_focus_owner()==first,name+" first button takes keyboard focus")
	var seen:={}
	var current:Control=first
	for i in range(240):
		seen[current]=true
		current=current.find_next_valid_focus()
		if current==null or current==first:break
	for item in buttons:check(seen.has(item),"%s keyboard focus reaches %s"%[name,item.name])
	for item in app.modal.find_children("*","BaseButton",true,false):
		check(item.focus_mode!=Control.FOCUS_NONE,"%s %s focusable"%[name,item.name])

func icon_ok(id:String,item:String)->void:
	var picture:=control("Icon_"+item) as TextureRect
	var expected:=FlowerArt.item_texture(item)
	if expected==null:
		check(picture==null,id+" missing art shows name only for "+item)
	else:
		check(picture!=null and picture.texture==expected and picture.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,id+" uses FlowerArt icon "+item)

func run()->void:
	root.size=SIZES[0]
	var path:=OS.get_environment("TEMP").path_join("flower-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"花圃旅人",path)!=OK:
		check(false,"Host starts")
		print("FLOWER_NURSERY_UI_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	world=app.session.world
	actor=app.session.peers[1]
	app.sound.reduced_motion=true
	check(world.state.has("flower_nursery") and world.state.regions.has(Flower.REGION),"World carries flower nursery state and tianwei region")

	# Pure data / API shape.
	check(FlowerUI.interaction_points("home").is_empty(),"No flower world points at home (letter goes through the stall)")
	var points:=FlowerUI.interaction_points(Flower.REGION)
	for site in ["farmer","seed","dye","market","garden","xinghe"]:
		check(points.has("flower:"+site) and points["flower:"+site]==Vector2(FlowerUI.site_cell(site))+Vector2(0.5,0.5),"Interaction point "+site)
	check(FlowerUI.site_cell("garden")==Flower.GARDEN_CELL and FlowerUI.site_cell("letter")==Flower.RECEIVER_HOME,"Site cells come from FlowerNursery")

	# Locked letter (chapter two incomplete).
	seed_state("home",Flower.RECEIVER_HOME,{},{},{},false)
	check(not FlowerUI.unlocked(app.session.snapshot),"Locked before tea comparison")
	app._shop()
	await settle()
	var content:=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	FlowerUI.counter_link(app,content)
	check(control("XiaoliFlowerLetter")==null,"Stall letter link hidden while locked")
	await open("letter")
	disabled_with("FlowerLetter","第二章")

	# Letter: unlocked, real action.
	seed_state("home",Flower.RECEIVER_HOME,{},{})
	app._shop()
	await settle()
	content=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	FlowerUI.counter_link(app,content)
	check(control("XiaoliFlowerLetter")!=null,"Stall shows flower letter link once unlocked")
	await press("XiaoliFlowerLetter")
	check(app.modal.get_meta("flower_site","")=="letter","Stall link opens letter")
	check(Flower.STORY.letter in text_of("FlowerLine"),"Letter shows story line")
	await fit("letter")
	await focus_reaches_all("letter")
	await press("FlowerLetter")
	check(record().letter,"flower_letter committed through session.perform")
	check(control("FlowerLetterDone")!=null,"Letter panel shows replay note after reading")

	# Farmer intro.
	seed_state(Flower.REGION,Flower.FARMER,{"letter":true},{})
	await open("farmer")
	var farmer_face:=control("FlowerPortrait") as TextureRect
	check(text_of("FlowerSpeakerName")==FlowerUI.FARMER_NAME and farmer_face!=null and farmer_face.texture==Resident.portrait_texture() and farmer_face.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Farmer shows A-Lei's delivered portrait with nameplate")
	for seed in Flower.STARTER:icon_ok("farmer",seed)
	await fit("farmer")
	await press("FlowerIntro")
	check(record().intro and int(person().inventory.get("bluebell_seed",0))==int(Flower.STARTER.bluebell_seed),"flower_intro grants starter seeds")
	check("下一步" in text_of("FlowerFarmerNext"),"Farmer shows next step after intro")
	seed_state(Flower.REGION,Flower.FARMER+Vector2i(8,0),{"letter":true},{})
	await open("farmer")
	disabled_with("FlowerIntro","請靠近")

	# Seed table.
	var grown:={"planted":{"bluebell":true,"orange_blossom":true,"chime_herb":true},"harvested":{"bluebell":4}}
	seed_state(Flower.REGION,Flower.SEED_TABLE,{"letter":true,"intro":true}.merged(grown),{"bluebell":4,"orange_blossom":0})
	await open("seed")
	for kind in Flower.FLOWERS:
		check(control("FlowerSeedRow_"+kind)!=null,"Seed row "+kind)
		icon_ok("seed",kind)
	check(text_of("FlowerSeedHint")=="出貨前每種至少留 1 包","Seed footer hint")
	check(text_of("FlowerSave_bluebell")=="留 1 包（%d 秒）"%int(Flower.SAVE_SECONDS),"Save button label uses SAVE_SECONDS")
	disabled_with("FlowerSave_orange_blossom","先在田尾育苗床採收過")
	await fit("seed")
	await focus_reaches_all("seed")
	await press("FlowerSave_bluebell")
	check(record().saving.get("kind","")=="bluebell","flower_save started")
	disabled_with("FlowerSave_chime_herb","留種台正在處理另一包")
	disabled_with("FlowerSaveTake","還要")
	world.state.time+=Flower.SAVE_SECONDS
	publish()
	await settle()
	await press("FlowerSaveTake")
	check(record().saved.get("bluebell",false),"flower_save_take saved bluebell")
	var row_text:=""
	for item in control("FlowerSeedRow_bluebell").find_children("*","Label",true,false):row_text+=item.text
	check("✓ 已留過種" in row_text,"Saved row shows check mark with text")

	# Dye table.
	seed_state(Flower.REGION,Flower.DYE_TABLE,{"letter":true,"intro":true},{"bluebell":2})
	await open("dye")
	check(text_of("FlowerDyeSource")=="花色染料配方","Dye shows player-facing recipe heading")
	icon_ok("dye","bluebell");icon_ok("dye","blue_dye")
	disabled_with("FlowerDye","鈴蘭藍花不足 3 朵")
	person().inventory.bluebell=3
	publish()
	await fit("dye")
	await press("FlowerDye")
	check(not record().dyeing.is_empty(),"flower_dye started")
	disabled_with("FlowerDyeTake","還要")
	world.state.time+=float(Flower.DYE.time)
	publish()
	await press("FlowerDyeTake")
	check(int(person().inventory.get("blue_dye",0))==int(Flower.DYE.yield),"flower_dye_take yields dye")
	await capture_workwear("01-original")
	await press("FlowerOutfit")
	check(person().get("blue_outfit",false) and int(person().inventory.blue_dye)==int(Flower.DYE.yield)-1,"apply workwear dye once")
	var observer:Dictionary=app.session.public_state(Flower.REGION)
	check(observer.players[app.session.own_id].get("blue_outfit",false),"other clients can see worn colour")
	var reopened:=World.new()
	check(reopened.load_world(world.save_path) and not reopened.recovered_from_backup and reopened.state.players.get(actor,{}).get("blue_outfit",false),"blue workwear survives primary-save reload")
	await capture_workwear("02-blue")
	await press("FlowerOutfit")
	check(not person().get("blue_outfit",false) and int(person().inventory.blue_dye)==int(Flower.DYE.yield)-1,"restore original without spending dye")
	check(reopened.load_world(world.save_path) and not reopened.state.players.get(actor,{}).has("blue_outfit"),"original workwear persists after changing back")

	# Market + order card.
	var saved_all:={"bluebell":true,"orange_blossom":true,"chime_herb":true}
	var harvested_all:={"bluebell":2,"orange_blossom":2,"chime_herb":1}
	var ready:={"letter":true,"intro":true,"planted":saved_all.duplicate(),"harvested":harvested_all,"saved":{"bluebell":true}}
	seed_state(Flower.REGION,Flower.MARKET,ready,{"coins":300,"bluebell":2,"orange_blossom":2,"chime_herb":1})
	await open("market")
	for id in Flower.MARKET_PRICES:
		check(control("FlowerBuyRow_"+id)!=null,"Market row "+id)
		icon_ok("market",id)
	check("今日剩 %d 份"%Flower.SUGAR_DAILY in text_of("FlowerBuyInfo_sugar"),"Sugar shows remaining today")
	var market_grid:=control("FlowerMarketGrid") as GridContainer
	check(market_grid!=null and market_grid.get_child_count()==Flower.MARKET_PRICES.size(),"Market lays products out as a card grid")
	for id in Flower.MARKET_PRICES:
		var product:=control("FlowerBuyRow_"+id)
		var buys:Array=product.find_children("FlowerBuy_*","Button",true,false) if product else []
		check(product is PanelContainer and buys.size()==1,"Product card %s has exactly one buy action"%id)
		var face:=control("Icon_"+id) as TextureRect
		check(face!=null and face.custom_minimum_size==Vector2(64,64) and product.is_ancestor_of(face),"Product card %s shows a 64px icon"%id)
		check(str(Flower.MARKET_PRICES[id]) in text_of("FlowerPrice_"+id),"Product card %s shows a price badge"%id)
	for kind in Flower.ORDER:
		var crate:=control("FlowerOrderNeed_"+kind)
		var produce:TextureRect=crate.find_child("Icon_"+kind,true,false) as TextureRect if crate else null
		check(produce!=null and produce.custom_minimum_size.x>=48,"Order board shows large produce icon "+kind)
	check(control("FlowerReserveChips")!=null and control("FlowerReserveChips").get_child_count()==Flower.RESERVE.size(),"Order board shows one reserve chip per seed")
	disabled_with("FlowerShip",Flower.UNSAVED_MESSAGE)
	check(text_of("FlowerOrderSaved").begins_with("✗"),"Order card saved check ✗")
	await fit("market-unsaved")
	await focus_reaches_all("market")
	ready.saved=saved_all.duplicate()
	seed_state(Flower.REGION,Flower.MARKET,ready,{"coins":300,"bluebell":1,"orange_blossom":2,"chime_herb":1,"bluebell_seed":1,"orange_blossom_seed":1})
	await settle()
	disabled_with("FlowerShip","鈴蘭藍花還差 1")
	check(text_of("FlowerOrderCount_bluebell").begins_with("✗"),"Order need shows ✗ when short")
	person().inventory.bluebell=2
	publish()
	await settle()
	disabled_with("FlowerShip",Flower.RESERVE_MESSAGE)
	check(text_of("FlowerReserve_bluebell_seed").begins_with("✓") and text_of("FlowerReserve_chime_herb_seed").begins_with("✗"),"Reserve checks show ✓/✗ with text")
	check("交貨後留下" in text_of("FlowerReserve_chime_herb_seed") and "目前 0" in text_of("FlowerReserve_chime_herb_seed"),"Reserve check explains held count")
	person().inventory.chime_herb_seed=1
	publish()
	await settle()
	check(text_of("FlowerOrderSaved").begins_with("✓"),"Saved check ✓")
	await fit("market-ready")
	var coins_before:=int(person().coins)
	await press("FlowerShip")
	check(record().shipped and int(person().coins)==coins_before+Flower.ORDER_PAY,"flower_ship pays ORDER_PAY")
	check(control("FlowerShipped")!=null and control("FlowerShip")==null,"Shipped order shows done text")
	await press("FlowerBuy_sugar")
	await press("FlowerBuy_sugar")
	check(int(person().inventory.get("sugar",0))==Flower.SUGAR_DAILY,"Bought daily sugar")
	disabled_with("FlowerBuy_sugar","今日糖已達 %d 份"%Flower.SUGAR_DAILY)
	check("今日剩 0 份" in text_of("FlowerBuyInfo_sugar"),"Sugar remaining reaches 0")
	person().coins=10
	publish()
	await settle()
	disabled_with("FlowerBuy_bluebell_seed","鈴幣不足")

	# Garden.
	var shipped:=ready.duplicate(true)
	shipped.shipped=true
	seed_state(Flower.REGION,Flower.GARDEN_CELL,shipped,{"bluebell_seed":3,"orange_blossom_seed":2})
	await open("garden")
	for id in Flower.GARDEN_NEEDS:
		check(text_of("FlowerGardenCount_"+id)=="0/%d"%int(Flower.GARDEN_NEEDS[id]),"Garden progress "+id)
		icon_ok("garden",id)
	check("合力島民 0 位" in text_of("FlowerContributors"),"Contributor count shown")
	check(FlowerUI.SEED_NOTE in text_of("FlowerSeedNote"),"Garden says seeds are not taken")
	disabled_with("FlowerGive","種子不會被拿走")
	person().inventory.blue_dye=6
	person().inventory.chime_herb=1
	publish()
	await settle()
	var preview:=control("FlowerGivePreview")
	var preview_text:=""
	for item in preview.find_children("*","Label",true,false):preview_text+=item.text
	check("藍色染料 ×4" in preview_text and "風鈴香草 ×1" in preview_text and "種子" not in preview_text,"Give preview caps to remaining need and excludes seeds")
	await fit("garden")
	await focus_reaches_all("garden")
	await press("FlowerGive")
	check(int(world.state.flower_nursery.garden.given.blue_dye)==4 and int(person().inventory.bluebell_seed)==3,"flower_give takes needs only, seeds untouched")
	check(text_of("FlowerGardenCount_blue_dye")=="4/4 ✓" and "合力島民 1 位" in text_of("FlowerContributors") and "你已捐 5 份" in text_of("FlowerContributors"),"Garden progress and own contribution refresh")
	# Completed garden, reduced motion: no tween.
	var done_garden:={"given":Flower.GARDEN_NEEDS.duplicate(),"contributors":{actor:10},"complete":true,"completed_at":float(world.state.time)}
	seed_state(Flower.REGION,Flower.GARDEN_CELL,shipped,{},done_garden)
	app.sound.reduced_motion=true
	await open("garden")
	check(get_processed_tweens().is_empty(),"Reduced motion: opening a completed garden creates no tweens")
	check((control("FlowerGardenStatus") as Label).modulate.a==1.0 and "✓" in text_of("FlowerGardenStatus"),"Completed garden uses text and check mark")
	await press("FlowerReplayOpening")
	check(Flower.GARDEN_EVENT in text_of("FlowerOpeningStory"),"Opening event replay")
	await fit("garden-complete")
	app.sound.reduced_motion=false
	await open("garden")
	check(not get_processed_tweens().is_empty(),"Normal motion animates the completed garden status")
	app.sound.reduced_motion=true

	# Xinghe report.
	seed_state(Flower.REGION,Flower.XINGHE,ready,{},done_garden)
	await open("xinghe")
	check(control("FlowerPortrait")!=null,"Xinghe portrait shown")
	disabled_with("FlowerReport","先完成市集的合作訂單")
	seed_state(Flower.REGION,Flower.XINGHE,shipped,{},done_garden)
	await settle()
	for seed in Flower.MEMENTO:icon_ok("xinghe",seed)
	await fit("xinghe")
	await press("FlowerReport")
	check(record().complete,"flower_report completes chapter slice")
	check(control("FlowerReportDone")!=null,"Report done text")

	# Journal.
	seed_state(Flower.REGION,Flower.SEED_TABLE,{"letter":true,"intro":true,"planted":saved_all.duplicate(),"harvested":harvested_all},{})
	await open("journal")
	var guide:=Flower.guidance(world.state,actor)
	check(guide.phase=="save" and str(guide.title) in text_of("FlowerNextTitle") and text_of("FlowerNextDetail")==str(guide.detail),"Journal next step from FlowerNursery.guidance")
	check(text_of("FlowerPhase_plant").begins_with("✓") and text_of("FlowerPhase_save").begins_with("▶") and text_of("FlowerPhase_ship").begins_with("・"),"Journal phase list marks done/current/pending")
	var book:=control("FlowerJournalBook")
	var left_page:=control("FlowerJournalLeftPage")
	var right_page:=control("FlowerJournalRightPage")
	check(book!=null and left_page!=null and right_page!=null and left_page.get_global_rect().end.x<right_page.get_global_rect().position.x,"Journal is an open two-page book spread")
	check(left_page!=null and left_page.is_ancestor_of(control("FlowerPhases")) and left_page.is_ancestor_of(control("FlowerNextTitle")),"Chapter route and next step sit on the left page")
	check(right_page!=null and right_page.is_ancestor_of(control("FlowerTab_plan")) and control("FlowerTab_plan").size_flags_horizontal!=Control.SIZE_EXPAND_FILL,"Page tabs are compact bookmarks on the right page")
	var route_art:=0
	for step in FlowerUI.ROUTE:
		var stone:=control("FlowerStep_"+step)
		if stone and not stone.find_children("*","TextureRect",true,false).is_empty():route_art+=1
	check(route_art==FlowerUI.ROUTE.size(),"Every route step has a picture")
	check(not control("FlowerStep_save").get_theme_stylebox("panel") is StyleBoxEmpty and control("FlowerStep_ship").get_theme_stylebox("panel") is StyleBoxEmpty,"Current route step is highlighted, pending steps are plain")
	await fit("journal-progress")
	await focus_reaches_all("journal")
	await press("FlowerTab_plan")
	for kind in Flower.FLOWERS:
		var plan:=text_of("FlowerPlanText_"+kind)
		check("目前全年可種" in plan and "約 %d 秒成熟"%int(Flower.CROPS[kind].time) in plan,"Journal shows current planting behavior and duration "+kind)
	check("目前全年可種" in text_of("FlowerPlanText_bluebell"),"Bluebell does not falsely advertise enforced seasons")
	check("留種方法" in text_of("FlowerDesignSave") and "花園餅乾" in text_of("FlowerDesignCookie") and not "設計選擇" in text_of("FlowerDesignCookie"),"Useful recipe text without developer labels")
	check("鈴蘭藍花 %d → 藍色染料 %d"%[int(Flower.DYE.ingredients.bluebell),int(Flower.DYE.yield)] in text_of("FlowerPlanDye"),"Dye recipe shows actual ingredient and yield amounts")
	await fit("journal-plan")
	var record_before:=JSON.stringify(record())
	await press("FlowerTab_story")
	check(control("FlowerStory_letter")!=null and control("FlowerStory_intro")!=null and control("FlowerStory_ship")==null,"Story replay lists only unlocked lines")
	await press("FlowerStory_letter")
	check(text_of("FlowerStoryText")==Flower.STORY.letter,"Story replay shows chosen line")
	await press("FlowerStory_intro")
	var story_face:=control("FlowerPortrait") as TextureRect
	check(text_of("FlowerStoryText")==Flower.STORY.intro and story_face!=null and story_face.texture==Resident.portrait_texture(),"A-Lei's story page shows her portrait")
	check(JSON.stringify(record())==record_before,"Story replay is client-only")
	await fit("journal-story")
	# Keyboard: Tab moves within the modal, Esc closes.
	await press("FlowerTab_progress")
	button("FlowerTab_plan").grab_focus()
	await key_event(KEY_TAB)
	var tab_focus:=root.gui_get_focus_owner()
	check(tab_focus is BaseButton and app.modal.is_ancestor_of(tab_focus),"Tab keeps focus inside the flower modal")
	await key_event(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the flower modal")

	# Stall lock / unlock (life_ui_panels shop).
	seed_state("home",Panels.STALL,{"letter":true,"intro":true},{"coins":500})
	app._shop()
	await settle()
	for kind in Flower.FLOWERS:check(control("StallBuy_"+kind)!=null,"Stall lists flower seed "+kind)
	await press("StallBuy_bluebell")
	check(not button("StallOffer").visible,"Locked flower seed shows no buy button")
	var lock:=control("StallLockReason") as Label
	await scroll_to(lock)
	check(lock!=null and visible(lock) and lock.text==Flower.HOME_SEED_MESSAGE,"Locked flower seed shows reason")
	check(button("StallBuy_bluebell").tooltip_text==Flower.HOME_SEED_MESSAGE,"Locked entry tooltip carries reason")
	await press("StallBuy_radish")
	check(button("StallOffer").visible and not button("StallOffer").disabled and not lock.visible,"Existing crop seeds unchanged")
	app._close_modal()
	var done:={"letter":true,"intro":true,"planted":saved_all.duplicate(),"harvested":harvested_all,"saved":saved_all.duplicate(),"shipped":true,"complete":true}
	seed_state("home",Panels.STALL,done,{"coins":500},done_garden)
	app._shop()
	await settle()
	await press("StallBuy_bluebell")
	check(button("StallOffer").visible and not lock_visible(),"Completed chapter unlocks flower seeds at the stall")
	var seeds_before:=int(person().inventory.get("bluebell_seed",0))
	await press("StallOffer")
	check(int(person().inventory.get("bluebell_seed",0))==seeds_before+1,"Home stall sells flower seed after completion")
	app._close_modal()

	# Inventory descriptions.
	for id in Flower.NAMES:check(not InventoryPanel.use_for(id).is_empty(),"Inventory description "+id)
	for id in ["bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar"]:
		check("不能出售" in InventoryPanel.use_for(id) and "不能出售" in InventoryPanel.value_for(id),"Not sellable label "+id)
	check("麵粉、糖、風鈴香草" in InventoryPanel.use_for("garden_cookie") and not "設計選擇" in InventoryPanel.use_for("garden_cookie"),"Garden cookie describes usable ingredients")
	check("目前全年可種" in InventoryPanel.use_for("bluebell_seed"),"Seed description explains current planting rules")
	check(InventoryPanel.value_for("garden_cookie")=="出售價　%d 鈴幣"%Flower.COOKIE_PRICE,"Garden cookie sell price")

	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("FLOWER_NURSERY_UI_TESTS checks=%d failures=%d (seeded UI fixture)"%[checks,failures])
	quit(int(failures>0))

func lock_visible()->bool:
	var lock:=control("StallLockReason")
	return lock!=null and lock.is_visible_in_tree()

func key_event(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await settle()
