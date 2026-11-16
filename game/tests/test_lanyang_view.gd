extends SceneTree

const View=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	run.call_deferred()
func check(ok:bool,description:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(description)
func run()->void:
	var view:=View.new()
	view.village_art_preview=true
	root.add_child(view)
	root.size=Vector2i(1280,800)
	var world:=World.new()
	world.add_player("tester","蘭陽農人")
	world.state.picnic=true
	var player:Dictionary=world.state.players.tester
	player.x=46.5
	player.y=30.5
	view.update_snapshot(world.region_snapshot("home"),"tester")
	await process_frame
	check(view.interaction_focus()=="transit:ferry","Unlocked home exit focuses the ferry transfer point")
	var before:=view.camera
	player.region="lanyang"
	player.x=12.5
	player.y=20.5
	view.show_target=true
	view.area_drag=true
	view.update_snapshot(world.region_snapshot("lanyang"),"tester")
	check(view.camera!=before and view.display_positions.tester==Vector2(12.5,20.5),"Region switch snaps camera and display positions")
	check(not view.show_target and not view.area_drag and view.farm_feedback.operations.is_empty(),"Region switch resets transient overlays")
	check(view.interaction_focus()=="travel","Lanyang return exit has travel focus")
	player.x=30.5
	player.y=25.5
	view.update_snapshot(world.region_snapshot("lanyang"),"tester")
	await process_frame
	check(view.interaction_focus()=="ditch:33,25","Nearby ditch blockage has Lanyang focus")
	player.x=40.5
	player.y=29.5
	view.update_snapshot(world.region_snapshot("lanyang"),"tester")
	await process_frame
	check(view.interaction_focus().is_empty(),"Home board coordinates do not contribute focus away from Lanyang interactions")
	var output:=OS.get_cmdline_user_args()
	if not output.is_empty() and output[0].begins_with("--qa-output="):
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output[0].trim_prefix("--qa-output="))==OK,"Rendered Lanyang screenshot")
	view.queue_free()
	await process_frame
	print("LANYANG_VIEW_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
