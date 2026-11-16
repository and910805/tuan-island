extends SceneTree
const View=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var view:=View.new()
	view.village_art_preview=true
	view.reduced_motion=true
	root.add_child(view)
	root.size=Vector2i(1280,800)
	var world:=World.new()
	world.add_player("tester","蘭陽農人")
	var p:Dictionary=world.state.players.tester
	p.region="lanyang"
	p.x=31.5
	p.y=25.5
	view.update_snapshot(world.region_snapshot("lanyang"),"tester")
	if view.interaction_focus()!="ditch:33,25":quit(1);return
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(args[0].path_join("ditch-before-1280x800.png"))!=OK:quit(1);return
	for cell in World.LANYANG_LIFE.BLOCKAGES:
		world.state.lanyang_life.cleared[World.key(cell)]=true
	world.state.lanyang_life.repaired=true
	p.x=32.5
	p.y=28.5
	view.update_snapshot(world.region_snapshot("lanyang"),"tester")
	if view.interaction_focus()!="gardener":quit(1);return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(args[0].path_join("ditch-after-1280x800.png"))!=OK:quit(1);return
	view.queue_free()
	await process_frame
	print("LANYANG_LIFE_ART_PASS")
	quit()
