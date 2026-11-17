extends "res://tests/test_manual_harvest_capacity_session.gd"
## Two WebSocket peers exercise the private chest using the normal action route.

func run()->void:
	var completed:=await scenario()
	expect(completed,"Private deposit scenario completed")
	await teardown()
	if failures==0:expect(remove_folder(),"Test save folder removed")
	else:print("Private deposit fixture retained at %s"%folder)
	finished=true
	print("PRIVATE_DEPOSIT_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func public_box(client:Client)->Dictionary:
	return client.session.snapshot.get("objects",{}).get(k1,{})

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("private-deposit-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"Temporary island folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(find_layout(),"Found chest site within reach for both residents"):return false
	var world:=fresh_probe()
	for token in [ALPHA,BETA]:
		var stand:=a_spot if token==ALPHA else b_spot
		world.state.players[token].x=stand.x
		world.state.players[token].y=stand.y
	world.state.players[ALPHA].inventory.wood=60
	world.save_path=save_path
	if not expect(world.save(),"Fixture saved"):return false
	var port:=start_server()
	if not expect(port>0,"WebSocket server started"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"Owner and guest joined"):return false
	if not expect((await act(alpha,"build",plot,"private_chest")).ok,"Owner places a private chest"):return false
	var guest_wood:=int(beta.bag().get("wood",0))
	expect(not (await act(beta,"deposit",plot,"wood")).ok,"Default box refuses guest deposits")
	expect(not (await act(beta,"box_deposit_access",plot,"island")).ok,"Guest cannot enable deposits")
	if not expect((await act(alpha,"box_deposit_access",plot,"island")).ok,"Owner enables deposits"):return false
	expect((await act(beta,"deposit",plot,"wood")).ok,"Guest deposits one wood")
	await settle([alpha,beta])
	var guest_view:=public_box(beta)
	expect(guest_view.get("guest_deposit",false) and guest_view.get("locked",false)
		and guest_view.get("items",{}).is_empty() and not guest_view.has("box_id") and not guest_view.has("freight_id"),
		"Guest sees access status with no contents or source IDs")
	expect(int(public_box(alpha).get("items",{}).get("wood",0))==1 and int(beta.bag().get("wood",0))==guest_wood-1,
		"Owner sees the deposited wood and the guest pays once")
	expect(not (await act(beta,"withdraw_all",plot,"wood")).ok and int(beta.bag().get("wood",0))==guest_wood-1,"Guest cannot recover the deposit")
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	if not expect(await stop_server(),"Server saves and closes"):return false
	port=start_server()
	if not expect(port>0,"Server reloads the same island"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"Both residents rejoin after restart"):return false
	expect(public_box(beta).get("guest_deposit",false) and public_box(beta).get("items",{}).is_empty(),"Restart keeps deposit access and hides contents")
	expect((await act(alpha,"withdraw",plot,"wood")).ok,"Owner retrieves the stored wood")
	expect((await act(alpha,"box_deposit_access",plot,"owner")).ok,"Owner revokes guest deposits")
	expect(not (await act(beta,"deposit",plot,"wood")).ok,"Guest's next deposit is rejected")
	expect(not public_box(beta).get("guest_deposit",false) and int(beta.bag().get("wood",0))==guest_wood-1,
		"Permission and backpack agree after the refused action")
	var guest_id:String=beta.session.own_id
	expect((await act(alpha,"deposit_half",plot,"wood")).ok,"Owner stocks the private chest")
	expect(not (await act(beta,"box_withdraw_access",plot,"friend:"+guest_id)).ok,"Guest cannot grant withdrawal")
	if not expect((await act(alpha,"box_withdraw_access",plot,"friend:"+guest_id)).ok,"Owner grants named visitor withdrawal"):return false
	await settle([alpha,beta])
	var supplied:=int(public_box(alpha).items.get("wood",0))
	guest_view=public_box(beta)
	expect(guest_view.locked and guest_view.guest_withdraw and int(guest_view.items.get("wood",0))==supplied
		and not guest_view.has("withdraw_guest") and not guest_view.has("box_id") and not guest_view.has("freight_id"),"Authorized visitor sees contents without admin or material-source data")
	expect(public_box(alpha).get("withdraw_guest")==guest_id,"Owner sees only public guest identity")
	var persisted:=World.new()
	expect(persisted.load_world(save_path) and persisted.state.objects[k1].get("withdraw_guest")==BETA,"Grant is stored against persistent character")
	expect(not (await act(beta,"deposit",plot,"wood")).ok,"Withdrawal permission does not allow deposits")
	expect(not (await act(beta,World.MATERIAL_SOURCES.PREPARE_ACTION,plot,k1)).ok,"Withdrawal permission does not create a construction material source")
	expect((await act(beta,"withdraw_half",plot,"wood")).ok,"Guest removes half the stack")
	await settle([alpha,beta])
	var received:=ceili(supplied/2.0)
	expect(int(beta.bag().get("wood",0))==guest_wood-1+received and int(public_box(alpha).items.get("wood",0))==supplied-received,"Private withdrawal changes the two stacks once")
	expect((await act(alpha,"box_withdraw_access",plot,"owner")).ok,"Owner revokes guest withdrawal")
	expect(not (await act(beta,"withdraw_all",plot,"wood")).ok and public_box(beta).items.is_empty(),"Revoked guest sees no contents and cannot withdraw again")
	return true
