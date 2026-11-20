extends SceneTree
const Sweep=preload("res://scripts/edge_foot_sweep.gd")
const Industry=preload("res://scripts/industry.gd")
var checks:=0
var failures:=0
const B:=Vector2i(80,60)
# Exact binary offsets so "touching" positions are exactly representable.
const FOOT:=[Vector2(-0.25,-0.125),Vector2(0.25,0.125)]

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func wall(open:=false,type:="edge_wall") -> Dictionary:
	return {"type":type,"owner":"t","open":open}

func blocks(a:Vector2,b:Vector2,edges:Dictionary,foot:=FOOT) -> bool:
	return Sweep.blocks_axis(a,b,edges,B,foot)

func stand(p:Vector2,edges:Dictionary,foot:=FOOT) -> bool:
	return Sweep.can_stand(p,edges,B,foot)

func run() -> void:
	var v:={"5,10,W":wall()}   # vertical wall on X=5, Y 10..11
	var h:={"5,10,N":wall()}   # horizontal wall on Y=10, X 5..6
	# Empty fast path.
	expect(not blocks(Vector2(0,0),Vector2(50,0),{}) and stand(Vector2(5,5),{}),"empty edges")
	expect(not blocks(Vector2(0,0),Vector2(50,0),{},Industry.FOOT_BOX),"empty edges real foot")
	# Basic crossing both directions, including large steps (no tunneling).
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),v),"cross right")
	expect(blocks(Vector2(6,10.5),Vector2(4,10.5),v),"cross left")
	expect(blocks(Vector2(0.5,10.5),Vector2(70,10.5),v),"large step right")
	expect(blocks(Vector2(70,10.5),Vector2(0.5,10.5),v),"large step left")
	expect(blocks(Vector2(0.5,10.5),Vector2(1.0e12,10.5),v),"huge step right")
	expect(not blocks(Vector2(0.5,10.5),Vector2(1.0e12,10.5),{}),"huge axis-aligned step, no edges")
	expect(not blocks(Vector2(0.5,20.5),Vector2(1.0e12,20.5),v),"huge step beyond finite wall row")
	expect(blocks(Vector2(0.5,10.5),Vector2(1.0e12,10.5),v,Industry.FOOT_BOX),"real foot box crossing")
	expect(not blocks(Vector2(0.5,10.5),Vector2(4.5,10.5),v),"stop short of wall")
	# Touching exactly is allowed, crossing is not.
	expect(not blocks(Vector2(4.0,10.5),Vector2(4.75,10.5),v),"end exactly touching from left")
	expect(blocks(Vector2(4.75,10.5),Vector2(4.76,10.5),v),"start touching, move into wall")
	expect(not blocks(Vector2(4.75,10.5),Vector2(3,10.5),v),"start touching, move away")
	expect(not blocks(Vector2(5.25,10.5),Vector2(6,10.5),v),"touching from right, move away")
	expect(blocks(Vector2(5.25,10.5),Vector2(5.2,10.5),v),"touching from right, move into wall")
	expect(not blocks(Vector2(7,10.5),Vector2(5.25,10.5),v),"end exactly touching from right")
	# Vertical movement vs horizontal wall.
	expect(blocks(Vector2(5.5,9),Vector2(5.5,11),h),"cross down")
	expect(blocks(Vector2(5.5,11),Vector2(5.5,9),h),"cross up")
	expect(not blocks(Vector2(5.5,9),Vector2(5.5,9.875),h),"touch from above")
	expect(blocks(Vector2(5.5,9.875),Vector2(5.5,9.9),h),"touching above, move in")
	expect(not blocks(Vector2(5.5,10.125),Vector2(5.5,12),h),"touching below, move away")
	expect(blocks(Vector2(5.5,0.5),Vector2(5.5,1.0e12),h),"huge vertical step")
	# Perpendicular extent: foot spanning two segments.
	var seg11:={"5,11,W":wall()}
	expect(blocks(Vector2(4,10.9),Vector2(6,10.9),seg11),"foot spans seg 10 and 11, only 11 walled")
	expect(not blocks(Vector2(4,10.5),Vector2(6,10.5),seg11),"foot only on seg 10")
	expect(not blocks(Vector2(4,10.875),Vector2(6,10.875),seg11),"foot top exactly at segment start")
	expect(blocks(Vector2(4,11.125),Vector2(6,11.125),seg11),"foot bottom exactly at segment start, overlaps 11")
	expect(not blocks(Vector2(4,11.125),Vector2(6,11.125),v),"foot starts exactly at segment end")
	expect(blocks(Vector2(4,10.9),Vector2(6,10.9),v),"foot spans seg 10 and 11, only 10 walled")
	# Finite edges: pass around the ends.
	expect(not blocks(Vector2(4,9.5),Vector2(6,9.5),v),"pass above finite wall")
	expect(not blocks(Vector2(4,12.5),Vector2(6,12.5),v),"pass below finite wall")
	# Multiple lines in one step: any one blocks.
	var multi:={"3,10,W":wall(true,"edge_door"),"7,10,W":wall()}
	expect(blocks(Vector2(0.5,10.5),Vector2(9.5,10.5),multi),"open door then wall")
	expect(not blocks(Vector2(0.5,10.5),Vector2(6.5,10.5),multi),"only open door crossed")
	# Types.
	expect(not blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":wall(true,"edge_door")}),"open door passes")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":wall(false,"edge_door")}),"closed door blocks")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":{"type":"edge_door","owner":"t"}}),"door without open blocks")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":{"type":"edge_door","owner":"t","open":1}}),"door open must be bool true")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":wall(true,"edge_window")}),"window blocks even if open")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":wall(true,"edge_wall")}),"wall blocks even if open")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":{"type":"mystery","open":true}}),"unknown type fails closed")
	expect(blocks(Vector2(4,10.5),Vector2(6,10.5),{"5,10,W":"junk"}),"non-dictionary row fails closed")
	# Argument handling.
	expect(blocks(Vector2(4,10.5),Vector2(6,11.5),v),"diagonal fails closed")
	expect(blocks(Vector2(0,0),Vector2(NAN,0),v) and blocks(Vector2(0,0),Vector2(INF,0),v),"non-finite fails closed")
	expect(not blocks(Vector2(4.75,10.5),Vector2(4.75,10.5),v),"zero move")
	expect(not stand(Vector2(NAN,0),v) and not stand(Vector2(INF,0),v),"can_stand non-finite")
	# Parallel walls: sliding into a wall that runs along the motion.
	expect(blocks(Vector2(4.5,10),Vector2(5.5,10),h),"slide in x into horizontal wall through foot")
	expect(not blocks(Vector2(5.5,10),Vector2(4.5,10),h),"escape from straddling horizontal wall")
	expect(blocks(Vector2(3.5,10),Vector2(8.5,10),h),"slide fully over parallel wall (no tunneling)")
	expect(not blocks(Vector2(3.5,10.5),Vector2(8.5,10.5),h),"slide beside horizontal wall")
	expect(blocks(Vector2(5,9.5),Vector2(5,10.5),v),"slide in y into vertical wall through foot")
	expect(not blocks(Vector2(5,10.5),Vector2(5,13),v),"escape from straddling vertical wall")
	# can_stand: stationary straddle.
	expect(not stand(Vector2(5.0,10.5),v),"foot straddles vertical segment")
	expect(not stand(Vector2(5.0,10.9),v),"straddle at segment end overlap")
	expect(stand(Vector2(5.0,11.125),v),"zero-length overlap with segment end")
	expect(stand(Vector2(5.0,9.5),v),"beside finite wall end")
	expect(stand(Vector2(5.25,10.5),v) and stand(Vector2(4.75,10.5),v),"touching wall from either side")
	expect(not stand(Vector2(5.5,10.0),h),"foot straddles horizontal segment")
	expect(stand(Vector2(4.5,10.0),h),"horizontal segment not under foot")
	expect(stand(Vector2(5.5,10.125),h) and stand(Vector2(5.5,9.875),h),"touching horizontal wall")
	expect(stand(Vector2(5.0,10.5),{"5,10,W":wall(true,"edge_door")}),"open door can be stood in")
	expect(not stand(Vector2(5.0,10.5),{"5,10,W":wall(false,"edge_door")}),"closed door cannot")
	expect(not stand(Vector2(5.0,10.5),{"5,10,W":wall(true,"edge_window")}),"window cannot")
	# Real foot box: corners across a wall.
	expect(not stand(Vector2(5.0,10.5),v,Industry.FOOT_BOX),"real foot box straddle")
	expect(stand(Vector2(5.3,10.5),v,Industry.FOOT_BOX),"real foot box clear")
	expect(blocks(Vector2(4.5,10.5),Vector2(5.5,10.5),v,Industry.FOOT_BOX),"real foot box crossing")
	expect(blocks(Vector2(4.5,10.9),Vector2(5.5,10.9),seg11,Industry.FOOT_BOX),"real foot spans two segments")
	# Rim edges and bounds.
	var small:=Vector2i(10,10)
	expect(Sweep.blocks_axis(Vector2(9.5,3.5),Vector2(10.5,3.5),{"10,3,W":wall()},small,FOOT),"east rim edge blocks")
	expect(Sweep.blocks_axis(Vector2(0.5,3.5),Vector2(-1.5,3.5),{"0,3,W":wall()},small,FOOT),"west rim edge blocks")
	expect(Sweep.blocks_axis(Vector2(3.5,9.5),Vector2(3.5,10.5),{"3,10,N":wall()},small,FOOT),"south rim edge blocks")
	expect(not Sweep.blocks_axis(Vector2(9.5,3.5),Vector2(10.5,3.5),{"10,10,W":wall()},small,FOOT),"invalid key ignored")
	expect(not Sweep.blocks_axis(Vector2(12.5,3.5),Vector2(20.5,3.5),{"15,3,W":wall()},small,FOOT),"edges beyond bounds ignored")
	expect(Sweep.can_stand(Vector2(5,5),v,Vector2i.ZERO,FOOT),"zero bounds ignores everything")
	# Offsets edge cases.
	expect(blocks(Vector2(4.5,10.5),Vector2(5.5,10.5),v,[]),"empty offsets act as point foot")
	expect(not blocks(Vector2(4.5,10.5),Vector2(4.9,10.5),v,[]),"point foot short of wall")
	expect(blocks(Vector2(4.5,10.5),Vector2(5.5,10.5),v,["x",Vector2(0.1,0.0)]),"non-Vector2 offsets skipped")
	expect(Industry.FOOT_BOX.size()==4 and Industry.FOOT_BOX[0]==Vector2(-0.22,-0.17),"FOOT_BOX layout assumed")
	# Input dictionary is not mutated.
	var before:=v.duplicate(true)
	blocks(Vector2(0,10.5),Vector2(9,10.5),v)
	expect(v==before,"edges not mutated")

	print("edge_foot_sweep checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
