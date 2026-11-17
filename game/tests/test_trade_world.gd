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
	settlement_save_failure(path)
	settlement_stress()
	for suffix in ["",".bak"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TRADE WORLD checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func settlement_save_failure(path:String) -> void:
	const OFFER := "storage-fault-offer"
	const RETRY := "storage-fault-settle"
	expect(act("alice",OFFER,"trade_open","bob").ok,"Open trade for storage failure test")
	expect(act("alice","storage-fault-goods","trade_edit",JSON.stringify({"offer":OFFER,"items":[["wood",1]],"coins":0})).ok,"Offer wood")
	expect(act("bob","storage-fault-coins","trade_edit",JSON.stringify({"offer":OFFER,"items":[],"coins":5})).ok,"Offer coins")
	var confirm:=JSON.stringify({"offer":OFFER,"revision":2})
	expect(act("alice","storage-fault-first","trade_confirm",confirm).ok,"Commit first confirmation")
	var state_before:=world.state.duplicate(true)
	var backup:=path+".bak"
	var backup_hash:=FileAccess.get_sha256(backup)
	var main_hash:=FileAccess.get_sha256(path)
	expect(DirAccess.rename_absolute(backup,backup+".fixture")==OK,"Set aside previous backup during fault")
	expect(DirAccess.make_dir_absolute(backup)==OK,"Block backup slot with empty directory")
	var result:=act("bob",RETRY,"trade_confirm",confirm)
	expect(not result.ok and result.message==World.SAVE_FAILED_MSG,"Settlement surfaces save failure")
	expect(world.save_error.contains("directory") and world.state==state_before,"Storage error recorded and settlement rolled back")
	expect(world.trade_view("alice").i_confirmed and not world.trade_view("bob").i_confirmed,"Failed settlement leaves the offer retryable")
	expect(not world.state.players.bob.receipts.has(RETRY),"Failed settlement leaves no success receipt")
	expect(FileAccess.get_sha256(path)==main_hash and not FileAccess.file_exists(path+".tmp"),"Main save intact and no temporary write")
	expect(DirAccess.dir_exists_absolute(backup),"Write never replaces the blocking directory")
	var reload:=World.new()
	expect(not reload.load_world(backup),"A directory cannot be loaded as a new world")
	expect(DirAccess.remove_absolute(backup)==OK,"Clear injected fault")
	expect(DirAccess.rename_absolute(backup+".fixture",backup)==OK and FileAccess.get_sha256(backup)==backup_hash,"Restore previous backup unchanged")
	expect(act("bob",RETRY,"trade_confirm",confirm).ok and world.save_error.is_empty(),"Retry the same request after storage recovers")
	expect(act("bob",RETRY,"trade_confirm",confirm).ok,"Retry of committed receipt succeeds")
	expect(reload.load_world(path),"Reload settlement after retry")
	expect(reload.state.players.alice.inventory.wood==int(state_before.players.alice.inventory.wood)-1 and reload.state.players.bob.inventory.wood==int(state_before.players.bob.inventory.wood)+1,"Retried settlement transfers wood once")
	expect(reload.state.players.alice.coins==int(state_before.players.alice.coins)+5 and reload.state.players.bob.coins==int(state_before.players.bob.coins)-5,"Retried settlement transfers money once")

## Exercises the authoritative world entry point on one machine. The initial
## material is seeded by the fixture; every subsequent transfer uses trade.
func settlement_stress() -> void:
	world.state.players.alice.inventory.wood=4
	world.state.players.bob.inventory.wood=4
	var original_coins:int=world.state.players.alice.coins+world.state.players.bob.coins
	var final_bags:Dictionary=world.state.players.duplicate(true)
	for index in 100:
		var prefix:="stress-%03d"%index
		var seller:="alice" if index%2==0 else "bob"
		var buyer:="bob" if seller=="alice" else "alice"
		var first:=seller if index%4<2 else buyer
		var second:=buyer if first==seller else seller
		expect(act(seller,prefix,"trade_open",buyer).ok,prefix+" open")
		var sale:=JSON.stringify({"offer":prefix,"items":[["wood",1]],"coins":0})
		var payment:=JSON.stringify({"offer":prefix,"items":[],"coins":1})
		expect(act(seller,prefix+"-sale","trade_edit",sale).ok,prefix+" offer")
		expect(act(buyer,prefix+"-payment","trade_edit",payment).ok,prefix+" payment")
		var confirm:=JSON.stringify({"offer":prefix,"revision":2})
		expect(act(first,prefix+"-first","trade_confirm",confirm).ok,prefix+" first confirmation")
		expect(world.state.players[seller].inventory.wood==final_bags[seller].inventory.wood,prefix+" first confirmation leaves goods in bag")
		expect(act(second,prefix+"-settle","trade_confirm",confirm).ok,prefix+" settlement")
		var before_retry:=world.state.duplicate(true)
		expect(act(second,prefix+"-settle","trade_confirm",confirm).ok,prefix+" exact retry returns receipt")
		expect(not act(second,prefix+"-late","trade_confirm",confirm).ok,prefix+" new request cannot settle old offer")
		expect(world.state==before_retry,prefix+" retries preserve entire world")
		for actor in [seller,buyer]:
			var direction:=1 if actor==buyer else -1
			expect(world.state.players[actor].inventory.wood==int(final_bags[actor].inventory.wood)+direction,prefix+" exact goods")
			expect(world.state.players[actor].coins==int(final_bags[actor].coins)-direction,prefix+" exact coins")
		expect(world.state.players.alice.inventory.wood+world.state.players.bob.inventory.wood==8,prefix+" goods conserved")
		expect(world.state.players.alice.coins+world.state.players.bob.coins==original_coins,prefix+" coins conserved")
		final_bags=world.state.players.duplicate(true)
	var reloaded:=World.new()
	if reloaded.load_world(world.save_path):
		for actor in ["alice","bob"]:
			expect(reloaded.state.players[actor].inventory==final_bags[actor].inventory,"100 settlements reload "+actor+" bag")
			expect(reloaded.state.players[actor].coins==final_bags[actor].coins,"100 settlements reload "+actor+" coins")
	else:
		expect(false,"100 settlements reload from the main save")
