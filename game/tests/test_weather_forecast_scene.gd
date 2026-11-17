extends "res://tests/test_weather_scene.gd"
## Native forecast/watering guidance on the actual HUD. Seeded weather fixture.
const LifeShell=preload("res://scripts/life_ui_shell.gd")
const Forecast=preload("res://scripts/weather_forecast.gd")
func weather_frame(name:String,quiet:bool,t:float)->void:
	await super.weather_frame(name,quiet,t)
	if name not in ["weather-sunny","weather-cloudy","weather-reduced","weather-rain-1024"]:return
	var expected:String=Weather.at(float(world.state.time)+Weather.DAY_SECONDS).label
	var found:=false
	for label in app.hud.find_children("*","Label",true,false):
		if label.is_visible_in_tree() and (label.text.contains("明日") or label.text.contains("明天")):
			found=true
			expect(label.text.contains(expected),"native tomorrow forecast matches world clock")
			expect(root.get_visible_rect().encloses(label.get_global_rect()),"native forecast fits viewport")
	expect(found,"tomorrow forecast remains visible without opening another modal")
	if name not in ["weather-reduced","weather-rain-1024"]:return
	var before:=JSON.stringify(world.state)
	var old_tool:String=app.selected
	app._select_tool("water")
	app._refresh_hud();await settle()
	expect(app.selected_label.text.contains("午夜") and app.selected_label.text.contains("雨"),"watering guidance explains midnight and rain")
	expect(root.get_visible_rect().encloses(app.selected_label.get_global_rect()),"watering guidance fits viewport")
	var font:Font=app.selected_label.get_theme_font("font")
	var font_size:int=app.selected_label.get_theme_font_size("font_size")
	expect(font.get_string_size(app.selected_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=app.selected_label.size.x,"watering hint text itself fits without hidden overflow")
	expect(JSON.stringify(world.state)==before,"forecast and tool guidance do not change world")
	await super.shot("weather-guidance-%d"%root.size.x)
	await forecast_keyboard_checks()
	expect(JSON.stringify(world.state)==before,"keyboard forecast focus does not change world")
	app._select_tool(old_tool);app._refresh_hud();await settle()

## Actual key events pushed through the root viewport (same path as the OS keyboard),
## not grab_focus(): Shift+Tab focuses the badge, Esc drops focus first, Tab stays inventory.
func key(code:Key,shift:=false)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.shift_pressed=shift;e.pressed=pressed
		root.push_input(e)
	await settle()
func forecast_keyboard_checks()->void:
	var badge:Control=app.hud.find_child("WeatherBadge",true,false)
	var tip:Control=app.hud.get_node("WeatherForecastTip")
	var tip_text:Label=tip.find_child("WeatherForecastTipText",true,false)
	var width:=root.size.x
	expect(root.gui_get_focus_owner()==null and not tip.visible,"forecast tip starts hidden with no GUI focus (%d)"%width)
	await key(KEY_TAB,true)
	expect(badge.has_focus() and tip.visible and app.modal==null,"native Shift+Tab focuses forecast badge without opening inventory (%d)"%width)
	expect(app._world_keyboard_allowed(),"badge focus keeps world keyboard/movement allowed (%d)"%width)
	var t:=float(world.state.time)
	for offset in 3:
		var info:Dictionary=Weather.at(t+offset*Weather.DAY_SECONDS) if offset>0 else Weather.at(t,"home")
		var day_name:String=Forecast.DAY_NAMES[offset]
		expect(tip_text.text.contains("%s · 第 %d 日 · %s"%[day_name,int(info.day),info.label]),"focus tip lists %s from world clock (%d)"%[day_name,width])
	expect(tip_text.text.contains("午夜") and tip_text.text.contains("小雨") and tip_text.text.contains("Esc"),"focus tip explains watering and how to close (%d)"%width)
	var rect:=tip.get_global_rect()
	expect(root.get_visible_rect().encloses(rect),"focus tip fits viewport (%d) %s"%[width,rect])
	for blocker in [app.preview_toolbar,app.selected_label,app.hud.get_node("LifeShortcuts"),badge,app.preview_controls[0]]:
		if blocker.is_visible_in_tree():expect(not rect.intersects(blocker.get_global_rect()),"focus tip does not cover %s (%d)"%[blocker.name,width])
	var line_height:=tip_text.get_line_height()
	expect(tip_text.get_line_count()*line_height<=tip_text.size.y+1,"focus tip text not clipped (%d)"%width)
	await super.shot("weather-focus-tip-%d"%width)
	await key(KEY_ESCAPE)
	expect(not badge.has_focus() and not tip.visible and app.modal==null,"first Esc only drops forecast focus (%d)"%width)
	await key(KEY_TAB,true)
	expect(badge.has_focus() and tip.visible,"Shift+Tab reopens forecast (%d)"%width)
	await key(KEY_TAB,true)
	expect(not badge.has_focus() and not tip.visible and app.modal==null,"second Shift+Tab closes forecast (%d)"%width)
	await key(KEY_TAB,true)
	await key(KEY_TAB)
	expect(app.modal!=null and not tip.visible,"plain Tab still opens inventory and hides the tip (%d)"%width)
	await key(KEY_TAB)
	expect(app.modal==null,"plain Tab closes inventory again (%d)"%width)
	if badge.has_focus():await key(KEY_ESCAPE)
	expect(not badge.has_focus() and not tip.visible,"forecast focus cleared after inventory round trip (%d)"%width)
	# Mine: current 洞內 but surface-labelled forecast, never implying rain waters caves.
	var cave:Dictionary=app.session.snapshot.duplicate(true);cave.region_id="mine_1"
	LifeShell.refresh_forecast(app,cave)
	await settle()
	var line:Label=app.hud.find_child("WeatherTomorrow",true,false)
	expect(line.text.begins_with("地表明日") and badge.tooltip_text.begins_with("地表預報") and badge.tooltip_text.contains(Forecast.CAVE_RULE),"mine HUD forecast labelled 地表 (%d)"%width)
	expect(root.get_visible_rect().encloses(line.get_global_rect()) and line.get_theme_font("font").get_string_size(line.text,HORIZONTAL_ALIGNMENT_LEFT,-1,line.get_theme_font_size("font_size")).x<=line.size.x,"mine surface line fits badge (%d)"%width)
	var cave_hint:=Forecast.water_hint(cave)
	expect(cave_hint.contains("洞內不會下雨") and font_fits(cave_hint),"mine water hint fits 740px tool hint (%d)"%width)
	app._refresh_hud();await settle()
	expect(not line.text.begins_with("地表"),"HUD forecast restored to outdoor (%d)"%width)
func font_fits(text:String)->bool:
	var font:Font=app.selected_label.get_theme_font("font")
	return font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,app.selected_label.get_theme_font_size("font_size")).x<=app.selected_label.size.x
