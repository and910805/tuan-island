extends SceneTree

const World=preload("res://scripts/world.gd")
const Porter=preload("res://scripts/lost_porter_mouse.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	expect(Porter.available("mine_6",6) and not Porter.available("mine_6",5) and not Porter.available("mine_5",6),"B6 unlock and region")
	for state in [-1,5,1.5,INF,"1",true,null]:
		expect(not Porter.valid(state),"Rejected malformed progress %s"%str(state))
	for state in range(5):
		expect(Porter.valid(state) and Porter.valid(float(state)),"Accept JSON round-trip state %d"%state)

	var world:=World.new()
	world.switch_region(Porter.REGION)
	for stage in range(Porter.Stage.REWARDED):
		var step:=Porter.next_step(stage)
		var at:Vector2=step.at
		var cell:Vector2i=step.cell
		var actor_at:=Porter.DELIVERY if cell==Porter.CRATE else at
		expect(world.can_stand(actor_at),"Stage %d is reachable near its marker"%stage)
		for action:String in Porter.ACTIONS:
			var result:=Porter.advance(stage,action,cell,actor_at)
			var permitted:bool=action==step.action
			expect(result.ok==permitted and result.stage==stage+int(permitted),"Stage %d, action %s"%[stage,action])
			expect(result.reward==(Porter.REWARD_COUNT if permitted and stage==Porter.Stage.DELIVERED else 0),
				"Only the confirmed gift stage pays")
		expect(not Porter.advance(stage,step.action,cell+Vector2i.RIGHT,actor_at).ok,"Reject incorrect interaction cell")
		expect(not Porter.advance(stage,step.action,cell,actor_at+Vector2(10,0)).ok,"Reject distant interaction")
		expect(not Porter.advance(stage,"",cell,actor_at).ok,"Reject unknown action")

	var full:=Porter.advance(Porter.Stage.DELIVERED,"porter_claim",Porter.CRATE,Porter.DELIVERY,false)
	expect(not full.ok and full.stage==Porter.Stage.DELIVERED and full.reward==0,"Full backpack preserves pending gift")
	var claim:=Porter.advance(full.stage,"porter_claim",Porter.CRATE,Porter.DELIVERY,true)
	expect(claim.ok and claim.reward==Porter.REWARD_COUNT,"Emptying the backpack permits retry")
	expect(not Porter.advance(claim.stage,"porter_claim",Porter.CRATE,Porter.DELIVERY).ok,"Gift can never be claimed twice")
	expect(Porter.next_step(claim.stage).is_empty(),"Completed request has no remaining objective")
	var anchors:=[Porter.START,Porter.MIDDLE,Porter.DELIVERY,Porter.REST]
	for stage in range(anchors.size()):
		expect(Porter.mouse_feet(stage)==anchors[stage],"Mouse anchor advances along the escort route")
	expect(world.can_stand(Porter.REST),"Relieved mouse has a clear spot beside the crate")
	expect(World.NAMES.has(Porter.REWARD_ITEM),"Gift is an existing B6 material")
	print("LOST_PORTER_MOUSE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
