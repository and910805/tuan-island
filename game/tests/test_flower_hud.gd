extends "res://tests/test_flower_nursery_ui.gd"
const FlowerMap=preload("res://scripts/island_map.gd")
var map_captured:=false
## Exercise the existing seeded phase/action matrix with real HUD refreshes.
func seed_state(region:String,cell:Vector2i,fields:Dictionary,inventory:Dictionary,garden:Dictionary={},unlocked:=true)->void:
	super.seed_state(region,cell,fields,inventory,garden,unlocked)
	app._refresh_hud()
	if region!=Flower.REGION:return
	var heading:Button=app.hud.find_child("TrackerHeading",true,false)
	var next:Button=app.hud.find_child("TrackerNext",true,false)
	var guidance:=FlowerUI.next_step(app.session.snapshot,app.session.own_id)
	check(heading.text.begins_with("花圃手記"),"Tianwei tracker heading")
	check(app.objective.text==str(guidance.title)+"\n"+str(guidance.detail),"HUD follows current flower phase")
	check(next.text=="翻開花圃手帳  →","tracker action describes journal")
	var markers:=FlowerMap.flower_landmarks(app.session.snapshot,app.session.own_id)
	var highlighted:=markers.filter(func(marker):return marker.active)
	check(markers.size()==8 and markers.all(func(marker):return Flower.land(marker.cell)),"Tianwei map shows eight landmarks on land")
	var expected:String=guidance.get("site","") if guidance.get("region","")==Flower.REGION else ""
	check(highlighted.size()==(0 if expected.is_empty() else 1) and (highlighted.is_empty() or highlighted[0].site==expected),
		"Tianwei map highlights the same destination as the journal")
	# Exercise actual HUD callback instead of direct FlowerUI.open.
	# Preserve open station modals: base test deliberately refreshes them in place.
	if app.modal==null:
		next.pressed.emit()
		check(app.modal!=null and app.modal.get_meta("flower_site","")=="journal","tracker opens flower journal")
		app._close_modal()

func open(site:String)->void:
	var preview:=OS.get_environment("FLOWER_MAP_QA_OUTPUT")
	if site=="farmer" and not map_captured and not preview.is_empty() and DisplayServer.get_name()!="headless":
		map_captured=true
		app._map_menu()
		await settle()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(preview)==OK,"Native Tianwei map captured")
	await super.open(site)
