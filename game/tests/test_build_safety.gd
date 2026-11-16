extends SceneTree

const World=preload("res://scripts/world.gd")
const CAP:=1000000000
var checks:=0
var failures:=0
var seq:=0
var world:World

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func act(action:String,position:Vector2i,extra:String="",who:String="alice")->Dictionary:
	seq+=1
	return world.act(who,"build-safety-%d"%seq,action,position,extra)

func _initialize()->void:
	world=World.new()
	world.add_player("alice","米")
	world.add_player("bob","豆")
	world.save_path="user://build-safety-%d.json"%Time.get_ticks_usec()
	var alice:Dictionary=world.state.players.alice
	alice.stories={"aru":4,"milu":4,"bobo":3}
	var pos:=Vector2i(38,34)
	alice.inventory.wood=20
	alice.inventory.stone=5
	var built:=act("build",pos,"bench")
	expect(built.ok,"workbench is placed with exact materials: "+str(built.get("message","")))
	expect(alice.inventory.wood==0 and alice.inventory.stone==0,"placement consumes the full recipe")
	if not world.state.objects.has(World.key(pos)):
		print("BUILD_SAFETY_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	var placed:Dictionary=world.state.objects[World.key(pos)].duplicate(true)
	# Simulate a full backpack slot for one of the two refund materials.
	alice.inventory.stone=CAP
	var before_inventory:Dictionary=alice.inventory.duplicate(true)
	var before_state:Dictionary=world.state.duplicate(true)
	var denied:=act("remove",pos)
	expect(not denied.ok and denied.message.contains("上限"),"dismantling is refused when a material refund would exceed the item cap")
	expect(world.state==before_state,"refused dismantle leaves the entire world unchanged")
	expect(alice.inventory==before_inventory,"refused dismantle leaves every inventory count unchanged")
	expect(world.state.objects.get(World.key(pos),{})==placed,"refused dismantle retains the building")
	# One unit of headroom below each refunded material must allow an exact refund.
	alice.inventory.stone=CAP-5
	var wood_before:=int(alice.inventory.get("wood",0))
	var stone_before:=int(alice.inventory.get("stone",0))
	expect(act("remove",pos).ok,"dismantling succeeds when both refunds fit exactly")
	expect(not world.state.objects.has(World.key(pos)),"successful dismantle removes the object exactly once")
	expect(int(alice.inventory.wood)==wood_before+20 and int(alice.inventory.stone)==stone_before+5,"successful dismantle returns exact recipe materials")
	expect(int(alice.inventory.wood)<=CAP and int(alice.inventory.stone)==CAP,"exact-cap refund never exceeds item limits")
	expect(not act("remove",pos).ok,"repeated dismantle cannot grant a second refund")
	expect(int(alice.inventory.wood)==wood_before+20 and int(alice.inventory.stone)==CAP,"repeated dismantle leaves refunded inventory unchanged")

	# Moving a filled private box relocates one authoritative object and preserves
	# its owner, contents, and every other field without a material transaction.
	var box:=Vector2i(40,34)
	alice.inventory.wood=100
	expect(act("build",box,"private_chest").ok,"private chest can be built before relocation")
	expect(act("deposit",box,"wood").ok,"private chest receives an item")
	var box_key:=World.key(box)
	var destination:=Vector2i(41,34)
	var box_before:Dictionary=world.state.objects[box_key].duplicate(true)
	var inventory_before_move:Dictionary=alice.inventory.duplicate(true)
	expect(act("move_object",box,"%d,%d"%[destination.x,destination.y]).ok,"filled private chest can be moved by its owner")
	expect(not world.state.objects.has(box_key) and world.state.objects.get(World.key(destination),{})==box_before,"move leaves exactly one copy with contents and ownership intact")
	expect(alice.inventory==inventory_before_move,"moving a building neither charges nor refunds materials")
	world.state.players.bob.x=43.5
	world.state.players.bob.y=34.5
	var before_blocked_move:Dictionary=world.state.duplicate(true)
	expect(not act("move_object",destination,"43,34").ok,"move cannot place a building over another active player")
	expect(world.state==before_blocked_move,"refused move leaves the object and contents unchanged")

	if FileAccess.file_exists(world.save_path):DirAccess.remove_absolute(world.save_path)
	if FileAccess.file_exists(world.save_path+".bak"):DirAccess.remove_absolute(world.save_path+".bak")
	print("BUILD_SAFETY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
