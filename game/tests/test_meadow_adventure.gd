extends SceneTree

const Trial=preload("res://scripts/meadow_adventure.gd")
const Meadow=Trial.Meadow
const A:="meadow-private-a"
const B:="meadow-private-b"
const C:="meadow-private-c"
const D:="meadow-private-d"
const OUTSIDE:=Vector2(23.5,29.5)
const BESIDE:=Vector2(24.5,26.5)
var checks:=0
var failures:=0

func _initialize()->void:
	expect(Trial.begin([],10.0).is_empty(),"Cannot start an event without a player")
	var start:=Trial.begin([A,B],10.0)
	expect(start.phase==Trial.Phase.WARNING and start.required==2,"Two adventurers start a timed warning with two required roles")
	expect(Trial.step(start,{A:OUTSIDE,B:BESIDE},12.99)==start,"The full warning elapses before the pulse")
	expect(Trial.step(start,{A:OUTSIDE,B:BESIDE},13.0).is_empty(),"A player inside the pulse cannot fill the second required role")
	expect(Trial.step(start,{A:OUTSIDE},13.0).is_empty(),"Disconnection does not shrink the starting group quota")
	expect(Trial.step(start,{A:OUTSIDE,B:OUTSIDE},110.0).is_empty(),"A stale event expires")
	expect(not light(start,A,0).ok,"A lantern cannot skip the pulse")

	var round:=Trial.step(start,{A:OUTSIDE,B:OUTSIDE},13.0)
	expect(round.phase==Trial.Phase.LANTERNS and round.required==2,"Both clear the pulse and are eligible to light")
	expect(not light(round,C,0).ok,"Late arrivals cannot take over another player's round")
	expect(not Trial.light(round,A,Meadow.TABLES[0],OUTSIDE).ok,"Must be beside the lantern")
	expect(not light(round,A,-1).ok,"Unknown table is rejected")
	expect(not Trial.calm(round,A,Meadow.CENTER,BESIDE).ok,"Cannot calm early")
	round=light(round,A,0).round
	expect(not light(round,B,0).ok,"A lantern cannot be lit twice")
	round=light(round,A,1).round
	expect(not light(round,A,2).ok,"At least one lantern must be left for the other player")
	round=light(round,B,2).round
	expect(round.phase==Trial.Phase.CALMING,"With three lamps lit the room moves to calming")
	expect(Trial.step(round,{A:OUTSIDE},14.0).is_empty(),"A missing contributor cancels the unfinished round")
	expect(not Trial.calm(round,B,Meadow.CENTER,OUTSIDE).ok,"Final interaction requires approaching the guardian")
	expect(not Trial.calm(round,C,Meadow.CENTER,BESIDE).ok,"A spectator cannot take the co-op reward")
	var next:=Trial.calm(round,A,Meadow.CENTER,BESIDE)
	expect(next.ok and next.completed.is_empty(),"One member may wait safely for the other")
	expect(not Trial.calm(next.round,A,Meadow.CENTER,BESIDE).ok,"A single player cannot fill both final roles")
	var public_view:=Trial.public_view(next.round,B)
	expect(public_view.can_calm and public_view.lamps==[true,true,true] and public_view.calmed==1,"Client gets sufficient visual state")
	expect(not JSON.stringify(public_view).contains("meadow-private"),"Public view redacts participant identity")
	next=Trial.calm(next.round,B,Meadow.CENTER,BESIDE)
	expect(next.ok and next.round.is_empty() and next.completed==[A,B],"Both contributing players earn the claim together")

	round=Trial.step(Trial.begin([A],0.0),{A:OUTSIDE},3.0)
	for index in Meadow.TABLES.size():round=light(round,A,index).round
	next=Trial.calm(round,A,Meadow.CENTER,BESIDE)
	expect(next.ok and next.completed==[A],"Solo adventurers can fill the same roles in sequence")

	round=Trial.step(Trial.begin([A,B,C,D],0.0),{A:OUTSIDE,B:OUTSIDE,C:OUTSIDE,D:BESIDE},3.0)
	expect(round.required==3 and D not in round.eligible,"In a larger group one missed pulse does not cancel the three active roles")
	round=light(round,A,1).round
	expect(not light(round,A,2).ok,"Three active roles demand three distinct lantern lighters")
	round=light(round,B,2).round
	expect(not light(round,D,0).ok,"Player caught by the pulse sits out")
	round=light(round,C,0).round
	expect(round.phase==Trial.Phase.CALMING,"Three distinct adventurers can reach the finale")
	print("MEADOW_ADVENTURE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func light(round:Dictionary,token:String,index:int)->Dictionary:
	if index<0:return Trial.light(round,token,Vector2i.ZERO,OUTSIDE)
	var tile:Vector2i=Meadow.TABLES[index]
	return Trial.light(round,token,tile,Meadow.table_feet(tile)+Vector2.DOWN)

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
