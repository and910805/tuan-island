extends "res://tests/network_sleepy_stone_guardian.gd"
## Self-check of the network test itself. The server Session is a TEST-ONLY
## subclass that (1) swaps in the reference World
## (test_sleepy_stone_guardian_reference.gd) and (2) returns guardian results to
## the acting peer through the existing receive_action_completed RPC. Clients are
## the unmodified production Session. A pass here only proves the network test is
## satisfiable by a contract-conforming server; it says nothing about production.

const Reference=preload("res://tests/test_sleepy_stone_guardian_reference.gd")

class ReferenceSession extends "res://scripts/session.gd":
	const Rules=preload("res://scripts/sleepy_stone_guardian.gd")
	func _complete_shipping(id:int,sequence:int,action:String,result:Dictionary) -> void:
		if action in Rules.ACTIONS:
			if id==1:receive_action_completed(sequence,action,result)
			elif _can_send(id):receive_action_completed.rpc_id(id,sequence,action,result)
			return
		super._complete_shipping(id,sequence,action,result)

func new_server_session():
	print("SELFCHECK: server uses the test-only reference World + Session subclass, not production")
	return ReferenceSession.new()

func server_hosted()->void:
	var world:=Reference.new()
	if world.load_world(save_path):server.world=world
	else:print("SELFCHECK: reference World could not load the fixture")
