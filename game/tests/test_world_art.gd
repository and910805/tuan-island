extends SceneTree

const View=preload("res://scripts/world_view.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(condition:bool,description:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(description)

func snapshot(at:Vector2) -> Dictionary:
	return {"players":{"artist":{"x":at.x,"y":at.y,"name":"Artist"}}}

func run() -> void:
	var view:=View.new()
	var at:=Vector2(40.0,32.0)
	view.update_snapshot(snapshot(at),"artist")
	view._process(0.1)
	expect(not view.walking.artist,"The first snapshot starts idle")
	for direction in [Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT,Vector2i.DOWN]:
		at+=Vector2(direction)*0.24
		view.update_snapshot(snapshot(at),"artist")
		view._process(0.05)
		expect(view.facings.artist==direction,"Interpolation faces the actual travel direction")
		expect(view.walking.artist,"Interpolation starts the walk cycle")
		expect(float(view.gait.artist)>0.0,"The walk cycle advances with travel")
		expect(view.display_positions.artist.distance_to(at)>0.1,"The pose tracks the interpolated position")
		view._process(0.05)
		view._process(0.09)
		expect(not view.walking.artist and is_zero_approx(view.gait.artist),"Idle settles the step")
		expect(view.facings.artist==direction,"Idle preserves the last direction")
	view.update_snapshot(snapshot(at+Vector2(10,0)),"artist")
	view._process(0.05)
	expect(not view.walking.artist,"A snapshot jump does not animate as walking")
	view.update_snapshot({"players":{}},"artist")
	expect(view.facings.is_empty() and view.walking.is_empty() and view.gait.is_empty() and view.stride_stop.is_empty(),"Departed players release animation state")
	view.free()
	print("WORLD_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
