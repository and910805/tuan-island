extends RefCounted
## C11 fixture helper: new stone floors and small smelters now need the Q03 board flag and a stone
## workbench on the island. Tests that are about something else (rooms, smelting, permissions...)
## call install() once on their world instead of re-implementing the unlock.
##
## The station is written straight into the HOME object layer at a cell that is open water (so it never
## collides with a test yard). That is exactly what a loaded save looks like, which is the point:
## production code only ever asks "is there a stone workbench", never how it got there.
const World=preload("res://scripts/world.gd")
const CELL:=Vector2i(2,2)

static func install(w:World,owner:String) -> void:
	w.state.board=true
	var home:Dictionary=w.home_layer("objects")
	for part in 2:
		home[World.key(CELL+Vector2i(part,0))]={"type":World.INDUSTRY.STONE_WORKBENCH,"owner":owner,"items":{},"stone_bench_part":part}
