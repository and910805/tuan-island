extends SceneTree
## Edge walls/windows as support for wall-mounted fixtures: WallFixtures.has_support /
## has_tool_board_support with an edges layer, WallFixtures.removal_problem (pure), and the real
## EdgeConstruction.apply remove path (rejected without refund, allowed once nothing hangs there).
## Not run by the author (no shell); EdgeConstruction.apply is called directly on a real World, so it
## does not depend on World.act wiring.
const World=preload("res://scripts/world.gd")
const WF=preload("res://scripts/wall_fixtures.gd")
const EC=preload("res://scripts/edge_construction.gd")
const A:="tok-edgefix-alice"
const B:="tok-edgefix-bob"
const AT:=Vector2i(30,40)

var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:call_deferred("run")

func run()->void:
	test_has_support()
	test_tool_board_support()
	test_removal_problem()
	test_real_remove()
	print("EDGE_WALL_FIXTURE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func edge(type:String,owner:String=A)->Dictionary:
	return {"type":type,"owner":owner}

func prop(kind:String,owner:String=A)->Dictionary:
	return {"type":kind,"owner":owner,"items":{}}

func k(c:Vector2i)->String:
	return "%d,%d"%[c.x,c.y]

func test_has_support()->void:
	var north:=WF.north_edge_id(AT)
	expect(north=="30,40,N","north edge id of the anchor")
	expect(not WF.has_support({},AT,A),"nothing supports by default")
	expect(not WF.has_support({},AT,A,"",{}),"empty edges do not support")
	expect(WF.has_support({},AT,A,"",{north:edge("edge_wall")}),"own edge wall supports an ordinary fixture")
	expect(not WF.has_support({},AT,A,"",{north:edge("edge_wall",B)}),"another owner's edge wall does not")
	expect(not WF.has_support({},AT,A,"",{north:edge("edge_window")}),"edge window does not support a wall fixture")
	expect(not WF.has_support({},AT,A,"",{north:{"type":"edge_door","owner":A,"open":false}}),"edge door never supports")
	expect(not WF.has_support({},AT,A,WF.LIFEBUOY,{"30,41,N":edge("edge_wall")}),"edge south of the anchor does not count")
	expect(not WF.has_support({},AT,A,"",{"29,40,N":edge("edge_wall")}),"edge of the neighbouring column does not count")
	expect(not WF.has_support({},AT,A,"",{"30,40,W":edge("edge_wall")}),"vertical edge does not count")
	expect(WF.has_support({},AT,A,WF.BAMBOO_CURTAIN,{north:edge("edge_window")}),"own edge window supports a bamboo curtain")
	expect(not WF.has_support({},AT,A,WF.BAMBOO_CURTAIN,{north:edge("edge_wall")}),"edge wall does not support a bamboo curtain")
	expect(not WF.has_support({},AT,A,WF.BAMBOO_CURTAIN,{north:edge("edge_window",B)}),"foreign edge window does not support a curtain")
	expect(WF.has_support({k(AT+Vector2i.UP):{"type":"wall","owner":A}},AT,A),"legacy tile wall still supports")
	expect(WF.has_support({k(AT+Vector2i.UP):{"type":"window","owner":A}},AT,A,WF.BAMBOO_CURTAIN),"legacy tile window still supports a curtain")
	expect(not WF.has_support({k(AT+Vector2i.UP):{"type":"wall","owner":B}},AT,A),"legacy tile of another owner still fails")
	expect(not WF.has_support({k(AT+Vector2i.UP):{"type":"wall","owner":A}},AT,A,WF.BAMBOO_CURTAIN),"legacy wall still not a curtain support")

func test_tool_board_support()->void:
	var right:=AT+Vector2i.RIGHT
	var wall_tile:={k(AT+Vector2i.UP):{"type":"wall","owner":A}}
	var both:={WF.north_edge_id(AT):edge("edge_wall"),WF.north_edge_id(right):edge("edge_wall")}
	expect(WF.has_tool_board_support({},AT,A,both),"two edge walls support a tool board")
	expect(WF.has_tool_board_support(wall_tile,AT,A,{WF.north_edge_id(right):edge("edge_wall")}),"tile + edge (mixed) supports a tool board")
	var tile_right:={k(right+Vector2i.UP):{"type":"wall","owner":A}}
	expect(WF.has_tool_board_support(tile_right,AT,A,{WF.north_edge_id(AT):edge("edge_wall")}),"edge + tile (mixed) supports a tool board")
	expect(not WF.has_tool_board_support({},AT,A,{WF.north_edge_id(AT):edge("edge_wall")}),"one half alone is not enough")
	expect(not WF.has_tool_board_support({},AT,A,{WF.north_edge_id(AT):edge("edge_wall"),WF.north_edge_id(right):edge("edge_wall",B)}),"foreign second half rejected")
	expect(not WF.has_tool_board_support({},AT,A,{WF.north_edge_id(AT):edge("edge_wall"),WF.north_edge_id(right):edge("edge_window")}),"window half rejected")
	expect(WF.has_tool_board_support({k(AT+Vector2i.UP):{"type":"wall","owner":A},k(right+Vector2i.UP):{"type":"wall","owner":A}},AT,A),"legacy two-wall board still works without edges arg")

func test_removal_problem()->void:
	var right:=AT+Vector2i.RIGHT
	var id:=WF.north_edge_id(AT)
	var edges:={id:edge("edge_wall")}
	expect(WF.removal_problem({},edges,id)=="","no prop: removal allowed")
	for kind in [WF.CHIME,WF.LIGHT,WF.LIFEBUOY,WF.BARK_FRAME,WF.HOME_SIGN,WF.WATER_LISTENING_CHIME]:
		expect(WF.removal_problem({k(AT):prop(kind)},edges,id)==WF.REMOVE_MESSAGE,"%s on the edge wall blocks removal"%kind)
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY,B)},edges,id)=="","a prop of another owner is not carried by this edge")
	expect(WF.removal_problem({k(AT):{"type":"chest","owner":A}},edges,id)=="","ordinary object is not mounted")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},edges,"not-a-key")=="","bad id: no problem")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},{id:edge("edge_wall")},"30,40,W")=="","vertical edge never carries a prop")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},{},id)=="","missing edge row: nothing to strand")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},{id:edge("edge_door")},id)=="","a door row never carried it")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY),k(AT+Vector2i.UP):{"type":"wall","owner":A}},edges,id)=="","same-owner legacy wall substitutes")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY),k(AT+Vector2i.UP):{"type":"wall","owner":B}},edges,id)==WF.REMOVE_MESSAGE,"foreign legacy wall is no substitute")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY),k(AT+Vector2i.UP):{"type":"window","owner":A}},edges,id)==WF.REMOVE_MESSAGE,"legacy window is no wall substitute")
	# Another edge elsewhere does not count as a substitute (only the removed edge is the support).
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},{id:edge("edge_wall"),"31,40,N":edge("edge_wall")},id)==WF.REMOVE_MESSAGE,"neighbour edge does not carry this prop")
	# Bamboo curtains live on windows.
	var window_edges:={id:edge("edge_window")}
	expect(WF.removal_problem({k(AT):prop(WF.BAMBOO_CURTAIN)},window_edges,id)==WF.CURTAIN_REMOVE_MESSAGE,"curtain blocks edge window removal")
	expect(WF.removal_problem({k(AT):prop(WF.BAMBOO_CURTAIN)},edges,id)=="","curtain is not carried by an edge wall")
	expect(WF.removal_problem({k(AT):prop(WF.LIFEBUOY)},window_edges,id)=="","wall fixture is not carried by an edge window")
	expect(WF.removal_problem({k(AT):prop(WF.BAMBOO_CURTAIN),k(AT+Vector2i.UP):{"type":"window","owner":A}},window_edges,id)=="","legacy window substitutes for the curtain")
	# Tool board: a record on either half blocks that half's edge.
	var board:={k(AT):{"type":WF.TOOL_BOARD,"owner":A,"tool_board_part":0,WF.TOOL_BOARD_FIELD:["hoe","axe"]},k(right):{"type":WF.TOOL_BOARD,"owner":A,"tool_board_part":1}}
	var board_edges:={id:edge("edge_wall"),WF.north_edge_id(right):edge("edge_wall")}
	expect(WF.removal_problem(board,board_edges,id)==WF.REMOVE_MESSAGE,"left board half blocks its edge")
	expect(WF.removal_problem(board,board_edges,WF.north_edge_id(right))==WF.REMOVE_MESSAGE,"right board half blocks its edge")
	var mixed:=board.duplicate(true)
	mixed[k(right+Vector2i.UP)]={"type":"wall","owner":A}
	expect(WF.removal_problem(mixed,board_edges,WF.north_edge_id(right))=="","legacy wall behind the right half allows removing that edge")
	expect(WF.removal_problem(mixed,board_edges,id)==WF.REMOVE_MESSAGE,"left half still has only the edge")

func new_world()->World:
	var w:=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory={"wood":100,"fiber":20,"glass":5}
	w.save_path=OS.get_user_data_dir().path_join("edge-wall-fixture-test.json")
	return w

func place_player(w:World,token:String)->void:
	# Midpoint of the north edge of AT is (x+0.5, y); stand next to it.
	w.state.players[token].x=AT.x+0.5
	w.state.players[token].y=AT.y+0.5

func test_real_remove()->void:
	var w:=new_world()
	place_player(w,A)
	var id:=WF.north_edge_id(AT)
	w.state.edges[id]=edge("edge_wall")
	w.state.objects[k(AT)]=prop(WF.LIFEBUOY)
	var wood_before:=int(w.state.players[A].inventory.wood)
	var result:Dictionary=EC.apply(w,A,EC.REMOVE,AT,"0")
	expect(not result.get("ok",false),"real remove rejected while a fixture hangs on the edge wall")
	expect(str(result.get("message",""))==WF.REMOVE_MESSAGE,"rejection explains the fixture must come off first")
	expect(w.state.edges.has(id),"rejected removal keeps the edge")
	expect(int(w.state.players[A].inventory.wood)==wood_before,"rejected removal pays no refund")
	# A legacy wall of the same owner substitutes.
	w.state.objects[k(AT+Vector2i.UP)]={"type":"wall","owner":A}
	result=EC.apply(w,A,EC.REMOVE,AT,"0")
	expect(result.get("ok",false) and not w.state.edges.has(id),"real remove allowed when a legacy wall substitutes")
	expect(int(w.state.players[A].inventory.wood)==wood_before+3,"allowed removal refunds exactly")
	# Fixture taken down: removal is allowed.
	w.state.objects.erase(k(AT+Vector2i.UP))
	w.state.edges[id]=edge("edge_wall")
	w.state.objects.erase(k(AT))
	result=EC.apply(w,A,EC.REMOVE,AT,"0")
	expect(result.get("ok",false) and not w.state.edges.has(id),"real remove allowed once nothing hangs there")
	# Curtain on an edge window.
	w.state.edges[id]=edge("edge_window")
	w.state.objects[k(AT)]=prop(WF.BAMBOO_CURTAIN)
	var glass_before:=int(w.state.players[A].inventory.glass)
	result=EC.apply(w,A,EC.REMOVE,AT,"0")
	expect(not result.get("ok",false) and str(result.get("message",""))==WF.CURTAIN_REMOVE_MESSAGE,"real remove of a curtained edge window rejected")
	expect(w.state.edges.has(id) and int(w.state.players[A].inventory.glass)==glass_before,"curtained window stays, no refund")
