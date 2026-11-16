extends "res://tests/test_flower_nursery_ui.gd"
## Exercise the existing seeded phase/action matrix with real HUD refreshes.
func seed_state(region:String,cell:Vector2i,fields:Dictionary,inventory:Dictionary,garden:Dictionary={},unlocked:=true)->void:
	super.seed_state(region,cell,fields,inventory,garden,unlocked)
	app._refresh_hud()
	if region!=Flower.REGION:return
	var heading:Button=app.hud.find_child("TrackerHeading",true,false)
	var next:Button=app.hud.find_child("TrackerNext",true,false)
	var guidance:=FlowerUI.next_step(app.session.snapshot,app.session.own_id)
	check(heading.text=="花圃手記  ▾","Tianwei tracker heading")
	check(app.objective.text==str(guidance.title)+"\n"+str(guidance.detail),"HUD follows current flower phase")
	check(next.text=="翻開花圃手帳  →","tracker action describes journal")
	# Exercise actual HUD callback instead of direct FlowerUI.open.
	# Preserve open station modals: base test deliberately refreshes them in place.
	if app.modal==null:
		next.pressed.emit()
		check(app.modal!=null and app.modal.get_meta("flower_site","")=="journal","tracker opens flower journal")
		app._close_modal()
