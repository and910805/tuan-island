extends SceneTree

const WeatherArt=preload("res://scripts/weather_art.gd")
const WeatherRules=preload("res://scripts/weather.gd")
const View=preload("res://scripts/world_view.gd")
const DAY:=1440.0
var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(condition:bool,description:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(description)

func run() -> void:
	var view_size:=Vector2(640,360)
	var camera:=Vector2(1200,900)
	# HUD mapping mirrors weather.gd exactly and never shows the sun when not sunny.
	for day in range(7):
		for region in ["home","lanyang","mine_1","mine_5"]:
			var snap:Dictionary={"time":day*DAY+600.0,"region_id":region}
			var info:Dictionary=WeatherArt.current(snap)
			var truth:Dictionary=WeatherRules.at(day*DAY+600.0,region)
			expect(WeatherArt.label(info)==str(truth.get("label","")),"HUD label is the authoritative weather label")
			expect(WeatherArt.weather_id(info)==str(truth.get("id","")),"Weather id is passed through")
			if WeatherArt.weather_id(info)!="sunny":
				expect(WeatherArt.icon_id(info)!="weather","No sun icon outside sunny weather")
			if region.begins_with("mine_"):
				expect(not WeatherArt.rains(info),"Mines are indoor and never rain")
	var rainy:Dictionary={"id":"rainy","label":"雨","raining":true,"day":3}
	var indoor:Dictionary={"id":"indoor","label":"洞內","raining":false,"day":3}
	expect(WeatherArt.icon_id(rainy)=="calendar","Rain uses the neutral calendar icon")
	expect(WeatherArt.icon_id({"id":"sunny"})=="weather","Sunny keeps the sun icon")
	expect(WeatherArt.rains(rainy) and not WeatherArt.rains(indoor),"Rain flag respects indoor")
	expect(WeatherArt.tint(rainy).a<=0.1 and WeatherArt.tint({"id":"cloudy"}).a<=0.06,"Tints stay subtle")
	expect(is_zero_approx(WeatherArt.tint({"id":"sunny"}).a) and is_zero_approx(WeatherArt.tint(indoor).a),"Sunny/indoor have no tint")
	expect(WeatherArt.current({}).is_empty(),"Empty snapshot yields no weather")
	# Deterministic, bounded sampling.
	expect(WeatherArt.MAX_DROPS>0 and WeatherArt.MAX_DROPS<=64,"Fixed sane particle cap")
	for i in range(WeatherArt.MAX_DROPS):
		var a:Vector3=WeatherArt.drop(i,3.7,camera,view_size)
		var b:Vector3=WeatherArt.drop(i,3.7,camera,view_size)
		expect(a==b,"Drop sampling is deterministic")
		expect(a.z>=0.0 and a.z<1.0,"Phase stays in [0,1)")
		expect(a.x>=-WeatherArt.TILE*2 and a.x<=view_size.x+WeatherArt.TILE*2,"Drop x near view")
		expect(a.y>=-WeatherArt.TILE*2 and a.y<=view_size.y+WeatherArt.TILE*2,"Drop y near view")
		expect(is_equal_approx(a.x,roundf(a.x)) and is_equal_approx(a.y,roundf(a.y)),"Drops land on whole pixels")
		# World anchoring: a small camera move inside the same tile keeps the world landing spot.
		var moved:Vector3=WeatherArt.drop(i,3.7,camera+Vector2(5,3),view_size)
		expect(Vector2(moved.x,moved.y)+camera+Vector2(5,3)==Vector2(a.x,a.y)+camera,"Landing point is world-anchored")
		var head:Vector2=WeatherArt.streak_head(Vector3(a.x,a.y,0.0))
		expect(head.y<a.y and head.y>=a.y-WeatherArt.FALL_DISTANCE-1.0,"Streak falls a short distance only")
	expect(is_zero_approx(WeatherArt.ripple_strength(Vector3(0,0,0.2))),"No ripple while falling")
	expect(WeatherArt.ripple_strength(Vector3(0,0,WeatherArt.FALL_PART))>0.9,"Ripple begins at landing")
	var distinct:={}
	for i in range(WeatherArt.MAX_DROPS):
		var d:Vector3=WeatherArt.drop(i,10.0,camera,view_size)
		distinct[Vector2(d.x,d.y)]=true
	expect(distinct.size()*2>WeatherArt.MAX_DROPS,"Drops are spread, not stacked")
	# Static marks (reduced motion) are a pure function of the cell and stay sparse.
	var marks:=0
	for y in range(40):
		for x in range(40):
			var cell:=Vector2i(x,y)
			var mark:Vector2=WeatherArt.static_mark(cell)
			expect(mark==WeatherArt.static_mark(cell),"Static mark deterministic")
			if mark.x>=0.0:
				marks+=1
				expect(mark.x>=1.0 and mark.x<=30.0 and mark.y>=1.0 and mark.y<=30.0,"Static mark inside tile")
	expect(marks>0 and marks*6<1600,"Static marks are sparse")
	# Shelter lookup is read-only over roofs and does not touch snapshot data.
	var view:=View.new()
	var data:Dictionary={"time":2*DAY+30.0,"region_id":"home","roofs":{"3,4":{}}}
	var before:=JSON.stringify(data)
	view.data=data
	expect(view.rain_sheltered(Vector2i(3,4)) and not view.rain_sheltered(Vector2i(4,4)),"Roofed cells are sheltered")
	expect(WeatherArt.label(view.weather_info())==str(WeatherRules.at(2*DAY+30.0,"home").get("label","")),"View reads weather from snapshot time/region")
	expect(JSON.stringify(view.data)==before,"Weather presentation never writes the snapshot")
	view.free()
	print("WEATHER_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
