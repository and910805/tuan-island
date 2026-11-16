extends SceneTree
## Render the normal backpack and handcraft from a fresh character's inventory.

const World=preload("res://scripts/world.gd")
const TOKEN:="rope-inventory-live"
var failures:=0
var app
var output:=OS.get_environment("ROPE_QA_OUTPUT")

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

func run()->void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":TOKEN}
	var world:=World.new()
	world.save_path="user://rope-inventory-live-%d.json"%OS.get_process_id()
	world.add_player(TOKEN,"手作測試員")
	session.world=world
	session._attach_registered(1,TOKEN)
	await settle()
	app._inventory()
	await settle()
	var panel=app.modal
	panel.select_category(1)
	panel.select_item("fiber")
	await settle()
	var craft:Button=panel.craft_rope
	expect(craft.is_visible_in_tree() and not craft.disabled and panel.get_global_rect().encloses(craft.get_global_rect()),"fiber handcraft button fits in the backpack")
	craft.pressed.emit()
	await settle()
	expect(world.state.players[TOKEN].inventory.fiber==5 and world.state.players[TOKEN].inventory.rope==1,"craft spends five starting fiber")
	expect(panel.detail_count.text=="持有 5" and panel.notice.text.contains("1 條繩索"),"slot count and feedback update after crafting")
	craft.pressed.emit()
	await settle()
	expect(craft.disabled and panel.detail_count.text=="持有 0","second craft uses last fiber and disables button")
	panel.select_item("rope")
	await settle()
	expect(panel.detail_count.text=="持有 2" and panel.detail_icon.texture.get_size()==Vector2(32,32),"rope detail shows count and dedicated art")
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(output.path_join("crafted-rope.png"))==OK,"save rendered backpack")
	session.shutdown()
	print("ROPE_INVENTORY_LIVE failures=",failures)
	quit(int(failures>0))
