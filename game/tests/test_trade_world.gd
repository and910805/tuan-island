extends SceneTree

const World = preload("res://scripts/world.gd")
var world := World.new()
var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func act(actor: String, id: String, action: String, extra: String) -> Dictionary:
	return world.act(actor,id,action,Vector2i.ZERO,extra)

func _initialize() -> void:
	var path := "user://trade-world-%d.json" % Time.get_ticks_usec()
	world.save_path = path
	for name in ["alice","bob","outsider"]:
		world.add_player(name,name)
		world.state.players[name].inventory.wood = 4
	expect(act("alice","offer","trade_open","bob").ok,"Nearby players can open an offer")
	expect(world.trade_view("outsider").is_empty(),"Outsiders have no offer view")
	expect(act("alice","wood","trade_edit",JSON.stringify({"offer":"offer","items":[["wood",2]],"coins":0})).ok,"Wood added")
	expect(act("alice","first","trade_confirm",JSON.stringify({"offer":"offer","revision":1})).ok,"First side confirms")
	expect(world.state.players.alice.inventory.wood==4,"First confirmation never debits")
	expect(act("bob","coins","trade_edit",JSON.stringify({"offer":"offer","items":[],"coins":12})).ok,"Partner adds coins")
	expect(not world.trade_view("alice").i_confirmed,"Real edit clears confirmation")
	expect(not act("alice","stale","trade_confirm",JSON.stringify({"offer":"offer","revision":1})).ok,"Stale revision refuses")
	var confirmation := JSON.stringify({"offer":"offer","revision":2})
	expect(act("alice","current","trade_confirm",confirmation).ok,"New revision confirmed")
	expect(act("bob","settle","trade_confirm",confirmation).ok,"Second confirmation settles")
	expect(act("bob","settle","trade_confirm",confirmation).ok,"Committed request can be retried")
	expect(world.state.players.alice.inventory.wood==2 and world.state.players.bob.inventory.wood==6,"Wood transferred exactly once")
	expect(world.state.players.alice.coins==132 and world.state.players.bob.coins==108,"Coins transferred exactly once")
	var loaded := World.new()
	expect(loaded.load_world(path) and loaded.state.players.bob.inventory.wood==6 and loaded.state.players.bob.coins==108,"Both sides persisted")
	expect(act("alice","second","trade_open","bob").ok,"Can reopen after settlement")
	world.cancel_trades("bob")
	expect(world.trade_view("alice").is_empty(),"Disconnect cleanup removes both views")
	for suffix in ["",".bak"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TRADE WORLD checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
