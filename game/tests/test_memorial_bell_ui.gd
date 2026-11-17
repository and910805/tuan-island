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
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
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
	expect(int(person.inventory.get("copper_ingot",0))==0 and int(person.inventory.get("copper_joint",0))==2,"Lingpopo consumes ingots and leaves copper joints for the build")
	var Folio:=preload("res://scripts/build_folio.gd")
	expect(Folio.unlocked(app,person,Goals.FESTIVAL_BELL),"Pattern becomes available in the normal build catalog")
	stand(build)
	expect(world.act(token,"place-copper","build",build,Goals.FESTIVAL_BELL).ok,"Place the patterned bell with normal build inputs")
	stand(build)
	app._interact()
	await process_frame
	expect(world.state.objects[World.key(build)].has("bell_at"),"The bell rings from normal interaction in silent mode")
	expect(not world.act(token,"rapid",Goals.FESTIVAL_BELL_RING,build).ok,"Ringing respects cooldown")
	await capture("01-bell.png")
	var tree:=World.Festival.TREE_CELL
	stand(tree)
	expect(not world.act(token,"early",Goals.TREE_NOTE_ACTION,tree,"晚安").ok,"Tree posting requires the last event")
	world.state.festival.round=1
	stand(npc)
	Tasks.bond_goal(app,"lingpopo",4)
	await process_frame
	await press("BondGoalDo")
	expect(int(person.inventory.get(Goals.keepsake_item(Goals.FESTIVAL_BELL_REWARD),0))==1,"Reporting grants the keepsake bell")
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
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MEMORIAL_BELL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
