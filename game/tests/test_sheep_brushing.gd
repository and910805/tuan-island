extends SceneTree
const World=preload("res://scripts/world.gd")
const SITE:=Vector2i(50,35)
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var world:=World.new()
	var path:=OS.get_environment("TEMP").path_join("sheep-brush-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	world.save_path=path
	world.add_player("owner","照料者")
	world.add_player("friend","朋友")
	# Fixture: chapter gate and standing positions only; original normal inventory.
	for person:Dictionary in world.state.players.values():person.x=50.5;person.y=36.5
	expect(not world.act("owner","locked","livestock_brush",SITE,"sheep").ok,"Grooming keeps the original picnic gate")
	world.state.picnic=true
	var inv:Dictionary=world.state.players.owner.inventory.duplicate(true)
	expect(not world.act("owner","wrong","livestock_brush",World.LIVESTOCK.ANIMALS.cow.cell,"cow").ok,"Sheep brush cannot groom the cow")
	expect(not world.act("owner","cell","livestock_brush",SITE+Vector2i.RIGHT,"sheep").ok,"Grooming requires the actual sheep care location")
	world.state.players.owner.x=40.5
	expect(not world.act("owner","far","livestock_brush",SITE,"sheep").ok,"Distance is enforced")
	world.state.players.owner.x=50.5
	var first:=world.act("owner","brush","livestock_brush",SITE,"sheep")
	expect(first.ok and int(world.state.livestock.sheep.bond)==1 and world.state.livestock.sheep.last_care=="brush","Real brushing increases bond once and records its presentation marker")
	expect(world.state.players.owner.inventory==inv and world.state.livestock.sheep.ready==0 and world.state.livestock.sheep.feed==0,"Brushing neither grants wool nor changes feed/inventory")
	expect(world.act("owner","brush","livestock_brush",SITE,"sheep")==first and int(world.state.livestock.sheep.bond)==1,"Same receipt does not brush twice")
	expect(not world.act("owner","pet-fast","livestock_pet",SITE,"sheep").ok,"Brushing shares the original pet cooldown")
	expect(not world.act("friend","friend-fast","livestock_brush",SITE,"sheep").ok,"Another player cannot bypass shared animal care cooldown")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and reloaded.state.livestock.sheep.last_care=="brush" and int(reloaded.state.livestock.sheep.bond)==1,"Grooming save reloads with bond and care type")
	expect(not reloaded.act("friend","reload-fast","livestock_brush",SITE,"sheep").ok,"Reload cannot bypass care cooldown")
	world=reloaded
	expect(world.step(World.LIVESTOCK.PET_INTERVAL,true),"Advance real existing cooldown")
	expect(world.act("friend","pet-after","livestock_pet",SITE,"sheep").ok and int(world.state.livestock.sheep.bond)==2 and not world.state.livestock.sheep.has("last_care"),"Ordinary petting resumes and clears brush-only presentation")
	var legacy:=World.new()
	expect(legacy.load_world(path) and not legacy.state.livestock.sheep.has("last_care"),"Animal record without new optional field still loads")
	expect(world.step(World.LIVESTOCK.PET_INTERVAL,true),"Advance another normal care interval")
	var before:Dictionary=world.state.duplicate(true)
	world.save_path=path.path_join("missing")
	expect(not world.act("owner","retry","livestock_brush",SITE,"sheep").ok and world.state==before,"Failed write rolls back entire brushing action")
	world.save_path=path
	expect(world.act("owner","retry","livestock_brush",SITE,"sheep").ok and int(world.state.livestock.sheep.bond)==3,"Retry after write recovery applies once")
	for value in ["pet","shear",true,12,{}]:
		var invalid:Dictionary=world.state.duplicate(true)
		invalid.livestock.sheep.last_care=value
		var file:=FileAccess.open(path+".invalid",FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid));file.close()
		expect(not reloaded.load_world(path+".invalid"),"Unknown care marker rejected: "+str(value))
	for suffix in ["",".bak",".tmp",".invalid"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHEEP_BRUSHING checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
