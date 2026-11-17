extends RefCounted
## Read-only three-day sky forecast and watering guidance for the HUD.
## Pure: derives everything from snapshot.time / snapshot.region_id through the
## authoritative weather.gd (at(), DAY_SECONDS, is_indoor). No IO, no wall clock,
## no random, no stored fields, never mutates the snapshot.
##
## Outside mines the forecast uses the current region. Inside a mine the
## current weather is reported as 洞內 and the forecast is labelled 地表預報 so
## it never implies that rain reaches cave plots.

const Weather=preload("res://scripts/weather.gd")
const SKY_REGION:="home"
const DAYS:=3
const DAY_NAMES:=["今天","明天","後天"]
const SCOPE_OUTDOOR:="三日天氣"
const SCOPE_SURFACE:="地表預報"
const RULES:=[
	"澆過的田濕潤到當天午夜，午夜後需重新澆水。",
	"小雨日替露天田補水；屋頂下仍要自己澆。",
	"缺水只會暫停生長，不會枯死；成熟作物不會壞。",
	"沒人在線時島上時間暫停，田不會因現實時間乾掉。",
]
const CAVE_RULE:="礦坑在洞內不會下雨，洞內的田要自己澆。"

static func _time(snapshot:Dictionary) -> float:
	return Weather.safe_time(snapshot.get("time",0.0))

static func _region(snapshot:Dictionary) -> String:
	return str(snapshot.get("region_id","home"))

static func is_indoor(snapshot:Dictionary) -> bool:
	return Weather.is_indoor(_region(snapshot))

## Weather where the player stands right now (洞內 inside mines).
static func here(snapshot:Dictionary) -> Dictionary:
	return Weather.at(_time(snapshot),_region(snapshot))

## Today + the next two calendar days of outdoor sky weather. Each entry:
## {offset, name, day, id, label, raining}. Future days are sampled at midday so
## midnight rounding can never shift a day.
static func days(snapshot:Dictionary) -> Array:
	var result:=[]
	var today:=Weather.day_index(_time(snapshot))
	var sky_region:=SKY_REGION if is_indoor(snapshot) else _region(snapshot)
	for offset in DAYS:
		var time:=(today+float(offset))*Weather.DAY_SECONDS+Weather.DAY_SECONDS*0.5 if offset>0 else _time(snapshot)
		var info:=Weather.at(time,sky_region)
		result.append({"offset":offset,"name":DAY_NAMES[offset],"day":int(today)+1+offset,"id":str(info.id),"label":str(info.label),"raining":bool(info.raining)})
	return result

static func scope_label(snapshot:Dictionary) -> String:
	return SCOPE_SURFACE if is_indoor(snapshot) else SCOPE_OUTDOOR

## Compact one-line text for the HUD badge, e.g. "明日 小雨" / "地表明日 晴天".
static func tomorrow_line(snapshot:Dictionary) -> String:
	var tomorrow:Dictionary=days(snapshot)[1]
	return ("地表明日 %s" if is_indoor(snapshot) else "明日 %s")%tomorrow.label

## Multi-line hover/focus tooltip: three-day forecast plus watering rules.
static func tooltip(snapshot:Dictionary) -> String:
	var lines:=PackedStringArray()
	lines.append(scope_label(snapshot)+("（現在在洞內，以下是地面的天空）" if is_indoor(snapshot) else ""))
	for entry in days(snapshot):
		lines.append("%s · 第 %d 日 · %s"%[entry.name,entry.day,entry.label])
	lines.append("")
	lines.append("澆水小提醒")
	if is_indoor(snapshot):lines.append("・"+CAVE_RULE)
	for rule in RULES:lines.append("・"+rule)
	if _region(snapshot) in Weather.BREEZE_REGIONS:lines.append("・微風時採集雜草可多得 2 份纖維。")
	if _region(snapshot)=="jiaoxi":lines.append("・細雪天仍需替農田澆水。")
	return "\n".join(lines)

## Short single-line guidance for the selected water tool. Always mentions the
## midnight reset; mentions rain only for exposed outdoor plots.
static func water_hint(snapshot:Dictionary) -> String:
	var base:="澆水：點農田補水，濕潤到午夜"
	if is_indoor(snapshot):return base+" · 洞內不會下雨，要自己澆"
	var forecast:=days(snapshot)
	if forecast[0].raining:return base+" · 今天小雨已替露天田補水，屋頂下仍要澆"
	if forecast[1].raining:return base+" · 明日小雨會替露天田補水"
	return base+" · 明日%s，記得再澆；小雨日露天田免澆"%forecast[1].label
