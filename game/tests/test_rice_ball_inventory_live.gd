extends SceneTree
## Render the actual mine and backpack. Position and energy are seeded; the
## backpack button must call Main -> Session -> World and refresh from snapshot.

const World=preload("res://scripts/world.gd")
const TOKEN:="rice-ball-inventory-live"
const ITEM:="star_rice_ball"
var failures:=0
var app
var output:=OS.get_environment("RICE_BALL_QA_OUTPUT")

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	if not ok:
		failures+=1
		push_error(message)

func settle()->void:
	await create_timer(0.35).timeout
	app._refresh_hud()
	await process_frame
	await process_frame

func capture(name:String)->void:
	if output.is_empty():return
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name))==OK,"save "+name)

func run()->void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":TOKEN}
	var world:=World.new()
	world.save_path="user://rice-ball-inventory-live-%d.json"%OS.get_process_id()
	world.add_player(TOKEN,"礦場測試員")
	var miner:Dictionary=world.state.players[TOKEN]
	var arrival:=World.REGIONS.spawn("mine_1")
	miner.region="mine_1"
	miner.x=arrival.x
	miner.y=arrival.y
	miner.mine_energy=85
	miner.inventory[ITEM]=2
	session.world=world
	session._attach_registered(1,TOKEN)
	await settle()
	expect(app.objective.text.contains("85"),"mine HUD starts at 85 energy")
	app._inventory()
	await settle()
	var panel=app.modal
	panel.select_item(ITEM)
	await settle()
	var eat:Button=panel.eat_rice_ball
	expect(eat.is_visible_in_tree() and not eat.disabled and eat.text.contains("15"),"button offers 15 recovery")
	expect(panel.get_global_rect().encloses(eat.get_global_rect()),"eat button fits in backpack")
	await capture("01-before.png")
	eat.pressed.emit()
	await settle()
	expect(world.state.players[TOKEN].mine_energy==100 and world.state.players[TOKEN].inventory[ITEM]==1,"backpack action charges one food and restores energy")
	expect(panel.detail_count.text=="持有 1" and eat.disabled,"inventory refresh shows one remaining and disables eating")
	expect(panel.notice.visible and panel.notice.text.contains("恢復 15"),"inline notice confirms recovery")
	await capture("02-after.png")
	app._close_modal()
	await settle()
	expect(app.objective.text.contains("100"),"mine HUD shows restored energy")
	await capture("03-mine-hud.png")
	session.shutdown()
	print("RICE_BALL_INVENTORY_LIVE failures=",failures)
	quit(int(failures>0))
