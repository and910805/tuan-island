extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func story_bell() -> Control:
	return app.modal.find_child("LingpopoBellScene",true,false) as Control if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

## --size=WxH (1280x800 or 1024x640 default); malformed or tiny values fall back to the default.
func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=1024 and wanted.y>=640:return wanted
	return Vector2i(1024,640)

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree():lines.append((candidate as Label).text)
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

## The modal stays inside the window and visible buttons are neither squeezed nor sideways-scrolled.
func check_fit(label:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+label+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+label+")")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:expect(not scroll.get_h_scroll_bar().visible,"No sideways scrolling ("+label+")")
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if target.is_visible_in_tree():expect(target.size.x+1.0>=target.get_combined_minimum_size().x,"Button is not squeezed (%s): %s"%[label,str(target.name)])

func run() -> void:
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var reduced_motion:="--reduced-motion" in OS.get_cmdline_user_args()
	app.sound.reduced_motion=reduced_motion
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var path:="user://memorial-bell-%d.json"%OS.get_process_id()
	if app.session.host(0,"敲鐘島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	app.sound.volume=0.0
	world.state.picnic=true
	person.bonds={"lingpopo":{"points":24,"talk_day":-1,"gift_day":-1}}
	person.inventory.wood=6
	person.inventory.copper_joint=2
	person.inventory.glass=3
	person.inventory.soup=1
	person.inventory.stone=25
	person.inventory.iron_ingot=6
	person.inventory.charcoal=2
	person.borrowed_mine_pick=true
	world.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true}
	var node:Vector2i=World.JINGUASHI.NODES[0]
	person.region=World.REGIONS.JINGUASHI
	stand(node+Vector2i.DOWN)
	expect(int(person.inventory.get("copper_ore",0))==0,"Copper starts outside the inventory")
	app._perform_build_action("pick",node)
	await process_frame
	expect(int(person.inventory.get("copper_ore",0))==4,"Mine four copper ore at the Jinguashi node")
	person.region=World.REGIONS.HOME
	var furnace:=Vector2i(40,34)
	stand(furnace+Vector2i(1,2))
	expect(world.act(token,"build-furnace","build",furnace,"glass_furnace").ok,"Build the normal glass furnace after the hoist")
	stand(furnace+Vector2i(1,2))
	app._interact()
	await process_frame
	await press("ProcessingRecipe_copper_ingot")
	await capture("00-copper-smelting.png")
	await press("ProcessingEnqueue")
	await press("ProcessingEnqueue")
	expect(int(person.inventory.get("copper_ore",0))==0 and int(person.inventory.get("charcoal",0))==0,"Two queued batches consume the mined ore and two charcoal")
	expect(world.step(90.1,true),"Both smelting batches finish on the world clock")
	stand(furnace+Vector2i(1,2))
	await process_frame
	await press("ProcessingClaim")
	await press("ProcessingClaim")
	expect(int(person.inventory.get("copper_ingot",0))==4,"Claim four copper ingots from the furnace")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and int(checkpoint.state.players[token].inventory.get("copper_ingot",0))==4,"Ingot stack survives a reload")
	app._close_modal()
	var build:=Vector2i(38,33)
	stand(build)
	expect(not world.act(token,"locked", "build",build,Goals.FESTIVAL_BELL).ok,"Craftable bell requires the printed pattern")
	var npc:=World.RESIDENT_BOND.bell_cell(world.state)
	stand(npc)
	Tasks.bond_goal(app,"lingpopo",3)
	await process_frame
	await press("BondGoalOption_soup")
	await press("BondGoalDo")
	expect(int(person.inventory.get("copper_ingot",0))==0 and int(person.inventory.get("copper_joint",0))==2 and int(person.inventory.get("glass",0))==1 and int(person.inventory.get("soup",0))==0,"Hand-in consumes four ingots, two glass and a soup, reserving joints for the build")
	expect(int(person.inventory.get(Goals.keepsake_item("keepsake_lingpopo"),0))==1,"The separate personal bell kit is awarded")
	var Folio:=preload("res://scripts/build_folio.gd")
	# N08-3: the completed modal stays open after the authoritative snapshot and offers the printed pattern.
	await process_frame
	expect(is_instance_valid(app.modal) and button("LingpopoBellPattern")!=null,"Completed N08-3 modal remains open with the bell pattern button")
	var pattern:=button("LingpopoBellPattern")
	expect(pattern!=null and pattern.is_visible_in_tree() and not pattern.disabled,"Pattern button is enabled and visible")
	var story_scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	var back:=button("BondGoalBack")
	expect(story_scroll!=null and pattern!=null and back!=null and story_scroll.get_global_rect().encloses(pattern.get_global_rect().merge(back.get_global_rect())),"Workshop and back actions are both visible without scrolling the completed page")
	var done_text:=visible_text(app.modal) if is_instance_valid(app.modal) else ""
	expect(done_text.contains(str(World.BUILD[Goals.FESTIVAL_BELL].name)),"Completed page shows the patterned bell name")
	expect(done_text.contains("留著你的顏色的鈴"),"Completed page still identifies the separate personal keepsake")
	var recipe:Dictionary=World.BUILD[Goals.FESTIVAL_BELL]
	var preview:=app.modal.find_child("LingpopoBellPatternCard",true,false) as PanelContainer if is_instance_valid(app.modal) else null
	var images:=0
	if preview!=null:
		for picture:TextureRect in preview.find_children("*","TextureRect",true,false):
			if picture.texture!=null and picture.is_visible_in_tree():images+=1
	expect(images==recipe.size(),"The pattern card contains the bell preview and an icon for every ingredient")
	var before:Dictionary={}
	for item:String in recipe:
		if item=="name":continue
		before[item]=int(person.inventory.get(item,0))
		expect(done_text.contains("%s ×%d"%[World.NAMES[item],recipe[item]]),"The pattern card shows the actual quantity for "+item)
	check_fit("N08-3 completed")
	await capture("n08-3-completed.png")
	await press("LingpopoBellPattern")
	expect(button("BuildPlace")!=null and not button("BuildPlace").disabled,"Pattern button opens the normal workshop")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text.contains(str(recipe.name)),"Workshop directly selects the festival memorial bell")
	var chosen:=0
	var wrong:=0
	for candidate:Node in app.modal.find_children("BuildSlot_*","Button",true,false):
		var slot:=candidate as Button
		if not slot.button_pressed or not slot.is_visible_in_tree():continue
		if str(slot.name).begins_with("BuildSlot_"+Goals.FESTIVAL_BELL+"_"):chosen+=1
		else:wrong+=1
	expect(chosen==1 and wrong==0,"Only the memorial bell slot is selected")
	check_fit("N08-3 workshop")
	await capture("n08-3-workshop.png")
	await press("BuildPlace")
	expect(app.building==Goals.FESTIVAL_BELL and app.selected=="build","The normal build tool holds the memorial bell")
	expect(Folio.unlocked(app,person,Goals.FESTIVAL_BELL),"Pattern becomes available in the normal build catalog")
	stand(build)
	app._perform_build_action("build",build,Goals.FESTIVAL_BELL)
	await process_frame
	expect(world.state.objects.get(World.key(build),{}).get("type")==Goals.FESTIVAL_BELL,"Place the patterned bell through regular gameplay")
	var exact:=true
	for item:String in before:exact=exact and int(person.inventory.get(item,0))==int(before[item])-int(recipe[item])
	expect(exact,"Ingredients are deducted exactly once by the recipe cost")
	expect(Goals.keepsake_item(Goals.FESTIVAL_BELL_REWARD)!=Goals.FESTIVAL_BELL and int(person.inventory.get(Goals.keepsake_item(Goals.FESTIVAL_BELL_REWARD),0))==0,"The gift keepsake is a distinct item and not yet granted")
	# Replay from the relationship page keeps the pattern reachable.
	app._close_modal()
	stand(npc)
	Tasks.bond_goal(app,"lingpopo",3)
	await process_frame
	expect(button("LingpopoBellPattern")!=null,"Replay from the relationship shows the pattern again")
	check_fit("N08-3 replay")
	app._close_modal()
	stand(build)
	app._interact()
	await process_frame
	expect(world.state.objects[World.key(build)].has("bell_at"),"The bell rings from normal interaction in silent mode")
	expect(not world.act(token,"rapid",Goals.FESTIVAL_BELL_RING,build).ok,"Ringing respects cooldown")
	await capture("01-bell.png")
	var tree:=World.Festival.TREE_CELL
	stand(tree)
	expect(not world.act(token,"early",Goals.TREE_NOTE_ACTION,tree,"晚安").ok,"Tree posting requires the last event")
	stand(npc)
	Tasks.bond_goal(app,"lingpopo",4)
	await process_frame
	var waiting:=story_bell()
	var first_ring:=button("BondGoalDo")
	expect(waiting!=null and not bool(waiting.get("rang")) and first_ring!=null and first_ring.disabled,"The bell is still and disabled before an island festival finishes")
	world.state.festival.round=1
	stand(npc)
	await process_frame
	expect(story_bell()==waiting and first_ring!=null and not first_ring.disabled and world.state.festival.contributors.is_empty(),"The ceremony becomes available in-place for a player who missed the festival")
	if not reduced_motion:app.sound.volume=0.40
	await capture("n08-4-before-ring.png")
	await press("BondGoalDo")
	var rung:=story_bell()
	var kit:=Goals.keepsake_item(Goals.FESTIVAL_BELL_REWARD)
	expect(rung!=null and rung!=waiting and bool(rung.get("rang")) and Goals.done(person,"lingpopo").has(4),"A confirmed hand-ring opens the completed scene and starts the visual feedback")
	expect(rung!=null and rung.is_processing()!=reduced_motion,"Reduced motion shows the result immediately while normal mode animates")
	expect(int(person.inventory.get(kit,0))==1,"Hand-ringing grants exactly one keepsake bell")
	await capture("n08-4-rung.png")
	if not reduced_motion:
		await create_timer(0.18).timeout
		expect(app.sound.player.stream==app.sound.sounds.memorial_bell and app.sound.player.playing,"The first story ring plays the dedicated cue")
	check_fit("N08-4 completed")
	var completed_scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	expect(completed_scroll!=null and not completed_scroll.get_v_scroll_bar().visible,"The completed bell memory fits without scrolling")
	Tasks.bond_goal(app,"lingpopo",4)
	await process_frame
	var replay_bell:=story_bell()
	expect(replay_bell!=null and not bool(replay_bell.get("rang")),"Opening the event again waits for the player to replay it")
	var before_replay:int=app.session.counter
	await press("LingpopoRingAgain")
	expect(replay_bell!=null and bool(replay_bell.get("rang")) and app.session.counter==before_replay and int(person.inventory.get(kit,0))==1,"Replay is local, with visual feedback and no repeat reward")
	await create_timer(1.25).timeout
	expect(replay_bell!=null and not replay_bell.is_processing(),"Visual feedback settles and stops rendering new frames")
	app.sound.volume=0.0
	app._close_modal()
	stand(tree)
	app._interact()
	await process_frame
	var draft:=app.modal.find_child("FestivalTreeDraft",true,false) as LineEdit
	expect(draft!=null,"Wind chime tree opens its note editor")
	if draft!=null:draft.text="晚歸的人，記得抬頭看燈。"
	await press("FestivalTreePost")
	expect(world.state[Goals.TREE_NOTES][0].text=="晚歸的人，記得抬頭看燈。" and world.state.get("island_notes",[]).is_empty(),"Notes are posted directly to this tree")
	app._interact()
	await process_frame
	await capture("02-tree-notes.png")
	app._close_modal()
	var reward:=Vector2i(37,32)
	stand(reward)
	expect(world.act(token,"place-award","build",reward,Goals.FESTIVAL_BELL_REWARD).ok,"Place the awarded bell")
	stand(reward)
	app._interact()
	await process_frame
	expect(world.state.objects.get(World.key(reward),{}).has("bell_at"),"The gifted bell is also playable")
	stand(reward+Vector2i(0,-1))
	await create_timer(0.3).timeout
	await capture("03-two-bells.png")
	expect(world.step(2.0,true),"Advance beyond the bell cooldown")
	app.sound.volume=0.40
	stand(reward)
	app._interact()
	await create_timer(0.25).timeout
	expect(app.sound.player.stream==app.sound.sounds.memorial_bell and app.sound.player.playing,"The audible interaction plays the dedicated bell cue")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state[Goals.TREE_NOTES][0].sender=="敲鐘島民" and loaded.state.objects[World.key(reward)].type==Goals.FESTIVAL_BELL_REWARD,"Authored note and the placed keepsake survive reload")
	expect(loaded.state.objects.get(World.key(build),{}).get("type")==Goals.FESTIVAL_BELL and Goals.done(loaded.state.players[token],"lingpopo").has(3),"The pattern-placed bell and completed N08-3 survive reload")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MEMORIAL_BELL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
