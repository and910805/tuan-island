extends RefCounted
## Drive a newly registered WebSocket client from the ferry lane to the table
## through the same movement RPC used by the client.

static func from_ferry(tree:SceneTree,session,target:Vector2)->bool:
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		var person:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
		if person.is_empty():break
		var delta:=target-Vector2(person.x,person.y)
		if delta.length()<0.45:
			session.input_direction(Vector2.ZERO)
			await tree.create_timer(0.25).timeout
			return true
		session.input_direction((delta*2.0).limit_length())
		await tree.create_timer(0.05).timeout
	session.input_direction(Vector2.ZERO)
	return false
