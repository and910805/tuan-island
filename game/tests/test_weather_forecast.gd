extends SceneTree
## Pure forecast/watering-guidance model plus the shell's focus-tip helpers.
## No network, no World instance, no wall clock.
const Weather=preload("res://scripts/weather.gd")
const Forecast=preload("res://scripts/weather_forecast.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const DAY:=1440.0
const EXPECTED:=["sunny","cloudy","rainy","sunny","sunny","rainy","cloudy"]
var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:
	test_day_boundaries()
	test_cycle_wrap()
	test_regions_and_cave()
	test_text_contract()
	test_unsafe_and_far_time()
	test_read_only()
	await test_shell_focus_tip()
	print("WEATHER_FORECAST_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func snap(time,region:="home") -> Dictionary:
	return {"time":time,"region_id":region}

func test_day_boundaries() -> void:
	expect(Weather.DAY_SECONDS==DAY,"forecast uses authoritative day length")
	for d in range(15):
		for t in [d*DAY,d*DAY+700.0,d*DAY+DAY-0.001]:
			var days:Array=Forecast.days(snap(t))
			expect(days.size()==3,"three entries at %s"%str(t))
			for k in 3:
				var e:Dictionary=days[k]
				var want:String=EXPECTED[(d+k)%7]
				expect(e.day==d+1+k and e.offset==k and e.name==Forecast.DAY_NAMES[k],"day %d offset %d numbering at %s"%[d+1,k,str(t)])
				expect(e.id==want and e.label==Weather.LABELS[want] and e.raining==(want=="rainy"),"day %d offset %d is %s"%[d+1,k,want])
				expect(e.id==Weather.at((d+k)*DAY+1.0).id,"entry agrees with weather.gd at()")
			expect(days[0].day==Weather.at(t).day,"today matches weather.gd day at %s"%str(t))
	var before_midnight:Array=Forecast.days(snap(DAY-0.001))
	var at_midnight:Array=Forecast.days(snap(DAY))
	expect(before_midnight[0].day==1 and before_midnight[1].day==2 and before_midnight[1].id=="cloudy","last instant of day 1 forecasts cloudy day 2")
	expect(at_midnight[0].day==2 and at_midnight[0].id=="cloudy" and at_midnight[1].id=="rainy","midnight belongs to the new day")
	expect(Forecast.tomorrow_line(snap(DAY-0.001))=="明日 多雲" and Forecast.tomorrow_line(snap(DAY))=="明日 小雨","tomorrow line flips exactly at midnight")

func test_cycle_wrap() -> void:
	var day6:Array=Forecast.days(snap(5.0*DAY+10.0))
	expect(day6[0].id=="rainy" and day6[1].id=="cloudy" and day6[2].id=="sunny" and day6[2].day==8,"forecast wraps past the seven-day cycle")
	var day7:Array=Forecast.days(snap(6.0*DAY))
	expect(day7[1].id=="sunny" and day7[1].day==8 and day7[2].id=="cloudy" and day7[2].day==9,"day 7 forecast wraps to cycle start")
	expect(Forecast.days(snap(7.0*DAY*3.0+2.0*DAY))[0].raining,"third cycle day 3 rains")

func test_regions_and_cave() -> void:
	var t:=2.0*DAY+30.0 # rainy day 3, sunny tomorrow
	var home:Array=Forecast.days(snap(t))
	for region in ["lanyang","jinguashi","unknown_place"]:
		expect(Forecast.days(snap(t,region))==home,"%s shares the outdoor forecast"%region)
		expect(not Forecast.is_indoor(snap(t,region)),"%s is outdoor"%region)
	for region in Weather.INDOOR_REGIONS:
		var s:=snap(t,region)
		expect(Forecast.is_indoor(s),"%s indoor"%region)
		expect(Forecast.here(s).id=="indoor" and Forecast.here(s).label=="洞內","%s current weather is 洞內"%region)
		expect(Forecast.days(s)==home,"%s sky forecast uses home"%region)
		expect(Forecast.scope_label(s)=="地表預報","%s forecast labelled 地表預報"%region)
		expect(Forecast.tomorrow_line(s)=="地表明日 晴天","%s compact line marks surface"%region)
		var tip:=Forecast.tooltip(s)
		expect(tip.begins_with("地表預報") and tip.contains(Forecast.CAVE_RULE),"%s tooltip explains cave is dry"%region)
		var hint:=Forecast.water_hint(s)
		expect(hint.contains("洞內不會下雨") and not hint.contains("替露天") and not hint.contains("小雨"),"%s water hint never implies rain waters the cave"%region)
	expect(Forecast.scope_label(snap(t))=="三日天氣" and not Forecast.tooltip(snap(t)).contains(Forecast.CAVE_RULE),"outdoor tooltip has no cave note")

func test_text_contract() -> void:
	for d in range(7):
		var s:=snap(d*DAY+100.0)
		var days:Array=Forecast.days(s)
		var tip:=Forecast.tooltip(s)
		for e in days:expect(tip.contains("%s · 第 %d 日 · %s"%[e.name,e.day,e.label]),"tooltip lists %s"%e.name)
		for rule in Forecast.RULES:expect(tip.contains(rule),"tooltip has rule %s"%rule)
		expect(tip.contains("午夜") and tip.contains("重新澆水") and tip.contains("小雨") and tip.contains("暫停生長") and tip.contains("不會枯死") and tip.contains("沒人在線"),"tooltip explains calendar-day watering, pause-not-die and no offline wall time")
		var line:=Forecast.tomorrow_line(s)
		expect(line=="明日 "+str(days[1].label),"compact line day %d"%(d+1))
		expect(not line.contains("\n") and line.length()<=8,"compact line stays one short line")
		var hint:=Forecast.water_hint(s)
		expect(hint.begins_with("澆水：") and hint.contains("午夜") and hint.contains("雨"),"water hint day %d mentions midnight and rain"%(d+1))
		expect(not hint.contains("\n") and hint.length()<=46,"water hint fits the 740px tool hint line")
		if hint.contains("明日"):expect(hint.contains("明日"+str(days[1].label)),"water hint names tomorrow's real weather")
		if days[0].raining:expect(hint.contains("今天小雨"),"rainy-day hint says rain already watered exposed plots")
		elif days[1].raining:expect(hint.contains("明日小雨會替露天田補水"),"hint previews tomorrow rain")
		else:expect(hint.contains("記得再澆"),"dry forecast reminds to re-water")

func test_unsafe_and_far_time() -> void:
	for bad in [-1.0,-1.0e300,INF,-INF,"noon",null]:
		var days:Array=Forecast.days(snap(bad))
		expect(days[0].day==1 and days[0].id=="sunny" and days[1].id=="cloudy","unsafe time %s clamps to day 1"%str(bad))
	expect(Forecast.days(snap(NAN))[0].day==1,"NaN time clamps to day 1")
	expect(Forecast.days({})[0].day==1 and Forecast.tomorrow_line({})=="明日 多雲","empty snapshot defaults to day 1 at home")
	var far:Array=Forecast.days(snap(1.0e6*7.0*DAY+2.0*DAY))
	expect(far[0].id=="rainy" and far[0].day==7000003 and far[1].id=="sunny" and far[1].day==7000004,"far future cycle arithmetic")
	var huge:Array=Forecast.days(snap(1.0e300))
	expect(huge.size()==3 and huge[1].id in EXPECTED and huge[2].id in EXPECTED,"absurd finite time stays well formed")
	expect(Forecast.days(snap(12345.0))==Forecast.days(snap(12345.0)),"deterministic")

func test_read_only() -> void:
	var s:={"time":5.0*DAY+77.0,"region_id":"mine_3","players":{"a":{"coins":5}},"crops":{"1,1":{"wet":false}}}
	var before:=s.duplicate(true)
	Forecast.days(s);Forecast.here(s);Forecast.tomorrow_line(s);Forecast.tooltip(s);Forecast.water_hint(s);Forecast.scope_label(s)
	s.region_id="home"
	Forecast.days(s);Forecast.tooltip(s);Forecast.water_hint(s)
	s.region_id="mine_3"
	expect(s==before,"forecast never mutates the snapshot or adds fields")
	expect(not s.has("forecast") and s.keys().size()==before.keys().size(),"no stored forecast field")

class FakeApp extends RefCounted:
	var hud:Control
	var modal=null

## Minimal node set with the names make_hud() creates; exercises the real shell
## refresh/focus helpers without the full app harness.
func test_shell_focus_tip() -> void:
	var app:=FakeApp.new()
	app.hud=Control.new()
	app.hud.size=Vector2(1024,640)
	root.add_child(app.hud)
	var badge:=PanelContainer.new();badge.name="WeatherBadge";badge.focus_mode=Control.FOCUS_ALL
	app.hud.add_child(badge)
	var line:=Label.new();line.name="WeatherTomorrow";badge.add_child(line)
	var tip:=PanelContainer.new();tip.name="WeatherForecastTip";tip.hide();app.hud.add_child(tip)
	var tip_text:=Label.new();tip_text.name="WeatherForecastTipText";tip.add_child(tip_text)
	badge.focus_entered.connect(func():Shell.sync_forecast_tip(app))
	badge.focus_exited.connect(func():Shell.sync_forecast_tip(app))
	await process_frame
	var s:=snap(2.0*DAY+5.0,"mine_1")
	var before:=s.duplicate(true)
	Shell.refresh_forecast(app,s)
	expect(line.text=="地表明日 晴天","shell writes compact surface line")
	expect(badge.tooltip_text.begins_with(Forecast.tooltip(s)) and tip_text.text.begins_with(Forecast.tooltip(s)),"hover tooltip and focus tip share the three-day text")
	expect(badge.tooltip_text.ends_with(Shell.FORECAST_HOVER_HINT) and tip_text.text.ends_with(Shell.FORECAST_TIP_HINT) and Shell.FORECAST_HOVER_HINT.contains("Shift+Tab"),"hover/focus text names the Shift+Tab keyboard path")
	expect(not tip.visible,"tip hidden without focus")
	badge.grab_focus()
	await process_frame
	expect(tip.visible,"keyboard focus on the badge shows the tip")
	app.modal=Control.new()
	Shell.sync_forecast_tip(app)
	expect(not tip.visible,"tip never shows over a modal")
	app.modal.free();app.modal=null
	Shell.sync_forecast_tip(app)
	expect(tip.visible,"tip returns after modal closes while still focused")
	expect(Shell.release_forecast_focus(app) and not badge.has_focus() and not tip.visible,"Esc/world click releases focus and hides tip")
	expect(not Shell.release_forecast_focus(app),"release is a no-op when badge is not focused")
	expect(Shell.toggle_forecast_focus(app) and badge.has_focus() and tip.visible,"toggle focuses badge when nothing else holds focus")
	expect(Shell.toggle_forecast_focus(app) and not badge.has_focus() and not tip.visible,"second toggle drops focus and hides tip")
	var other:=Button.new();app.hud.add_child(other);other.grab_focus()
	expect(not Shell.toggle_forecast_focus(app) and other.has_focus() and not tip.visible,"toggle leaves GUI focus navigation alone when another control is focused")
	other.release_focus()
	app.modal=Control.new()
	expect(not Shell.toggle_forecast_focus(app) and not badge.has_focus(),"toggle is inert while a modal is open")
	app.modal.free();app.modal=null
	expect(s==before,"shell forecast refresh is read-only")
	app.hud.queue_free()
	await process_frame
