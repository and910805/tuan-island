extends SceneTree
const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
var checks:=0
var failures:=0
func expect(ok:bool,detail:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(detail)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var old_view:=View.new()
	root.add_child(old_view)
	expect(old_view.character_art==null and old_view.crop_art==null,"Original mode stays opt-in")
	old_view.queue_free()
	var view:=View.new()
	view.village_art_preview=true
	root.add_child(view)
	view.set_process(false)
	expect(view.character_art!=null and view.crop_art!=null,"Preview loads both character and crop renderers")
	expect(view.character_art.animals!=null and view.character_art.animals.get_size()==Vector2(64,64),"Animal atlas is exported and has four cells")
	if view.character_art.animals!=null:
		var sheet:Image=view.character_art.animals.get_image()
		for i in range(4):
			var frame:=sheet.get_region(Rect2i(i%2*32,i/2*32,32,32))
			var used:=frame.get_used_rect()
			expect(used.has_area() and Rect2i(1,1,30,30).encloses(used),"Animal cell has artwork and transparent margins")
	var world:=World.new()
	world.add_player("local","小糰")
	world.add_player("friend","朋友")
	view.update_snapshot(world.state,"local")
	view._process(0.1)
	expect(view.display_positions.has("friend"),"Remote player remains in the same renderer")
	var radians:=0.0
	for i in range(10):
		world.move_player("local",Vector2.LEFT,0.1)
		view.update_snapshot(world.state,"local")
		var previous:=float(view.gait.get("local",0))
		view._process(0.1)
		radians+=fposmod(float(view.gait.get("local",0))-previous,TAU)
	expect(radians/TAU<=2.5 and radians/TAU>=1.0,"At normal movement speed, sprite cycling stays in a readable range")
	expect(view.facings.local==Vector2i.LEFT,"Actual world movement selects its facing")
	var before:=var_to_bytes(world.state)
	view._process(0.1)
	await process_frame
	expect(before==var_to_bytes(world.state),"Rendering and settling do not mutate world data")
	expect(not view.walking.local and view.facings.local==Vector2i.LEFT,"Stopped player keeps the last facing")
	for zoom in [1.0,2.0]:
		view.zoom=zoom
		view._process(0.1)
		var p:=Vector2(40.5,29.5)
		expect(view.to_cell(view.screen(p)*zoom)==Vector2i(40,29),"Click coordinates remain aligned under both zoom levels")
	view.queue_free()
	await process_frame
	print("LIFE_ART_INTEGRATION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
