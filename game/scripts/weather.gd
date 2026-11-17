extends RefCounted
## T039 basic weather (provisional). Pure and deterministic: no IO, no random,
## no wall clock, no World preload. Weather is derived only from persisted world
## time, so no save fields are needed.
##
## Calendar: day N (one-based) covers world time [(N-1)*DAY_SECONDS, N*DAY_SECONDS).
## A time exactly on a midnight belongs to the NEW day. The same seven-day cycle
## supplies the rain calendar. Some regions add dry-weather variations. The
## mines are indoors and never receive surface weather. Day 1 stays sunny.
##
## Crop rule (advance_plot): soil wetness lasts until the next game midnight.
## At each midnight every plot dries; an exposed plot (outdoor, no roof) is
## immediately re-wetted when the new day is rainy. Rain also wets an exposed
## dry plot at the start of any tick on a rainy day. Growth accumulates only for
## the wet duration and is capped at maturity (mature crops never rot).

const DAY_SECONDS := 1440.0
const DAYS_PER_SEASON := 14
const SEASONS := ["spring", "summer", "autumn", "winter"]
const SEASON_LABELS := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const CYCLE := ["sunny","cloudy","rainy","sunny","sunny","rainy","cloudy"]
const LABELS := {"sunny":"晴天","cloudy":"多雲","rainy":"小雨","windy":"微風","snowy":"細雪","indoor":"洞內"}
const BREEZE_REGIONS := ["home","bamboo_grove"]
const INDOOR_REGIONS := ["mine_1","mine_2","mine_3","mine_4","mine_5","mine_6","mine_7","mine_8","mine_9","mine_10","mine_11","mine_12","mine_13","mine_14","mine_15"]
## Largest day index converted to int; keeps int() well defined for absurd times.
const MAX_DAY_INDEX := 9.0e15
## Hard cap on per-day iterations in advance_plot (normally <= ~16 because a
## seven-day cycle always contains two rainy days and growth caps at maturity).
const MAX_DAY_STEPS := 4096

## Non-finite or negative times are clamped to 0 (day 1).
static func safe_time(time) -> float:
	if not (time is float or time is int):return 0.0
	var t := float(time)
	if is_nan(t) or is_inf(t) or t < 0.0:return 0.0
	return t

## Zero-based day index as a float integer (exact for any finite time).
static func day_index(time) -> float:
	return minf(floorf(safe_time(time) / DAY_SECONDS), MAX_DAY_INDEX)

## Outdoor weather id for a zero-based day index (cycle arithmetic, no loops).
static func outdoor_id(day: float) -> String:
	var d := floorf(day)
	if is_nan(d) or is_inf(d) or d < 0.0:d = 0.0
	return CYCLE[int(fmod(d, float(CYCLE.size())))]

static func is_indoor(region: String) -> bool:
	return region in INDOOR_REGIONS

## Whether rain falls in `region` on zero-based day `day`.
static func rains(day: float, region: String = "home") -> bool:
	return not is_indoor(region) and outdoor_id(day) == "rainy"

static func at(time: float, region: String = "home") -> Dictionary:
	var day := day_index(time)
	var id := "indoor" if is_indoor(region) else outdoor_id(day)
	var slot:=int(fmod(day,float(CYCLE.size())))
	if region in BREEZE_REGIONS and day>=DAYS_PER_SEASON and slot==4:
		id="windy"
	if region=="jiaoxi" and slot==6 and season_on_day(day)=="winter":
		id="snowy"
	return {"id": id, "label": LABELS[id], "raining": id == "rainy", "day": int(day) + 1}

## Advances one plot over world time [start, start+dt].
## wet: wetness at `start`; exposed: plot receives rain (outdoor and unroofed);
## growth/need: current growth and maturity time (need <= 0 means no growth,
## e.g. unplanted soil). Midnights strictly after `start` and up to and
## including `start+dt` are processed. Returns {wet, growth}.
## Cost is bounded independently of dt: once growth stops mattering the final
## wet state is computed directly from the final day.
static func season_on_day(day: float) -> String:
	return SEASONS[int(floor(fposmod(day, DAYS_PER_SEASON * SEASONS.size()) / DAYS_PER_SEASON))]

static func season_label(time: float) -> String:
	return SEASON_LABELS[season_on_day(day_index(time))] + "季"

## Empty seasons preserves the warm-season prototype. A greenhouse bypasses
## seasonal dormancy, while soil still needs water and dries at midnight.
static func advance_plot(wet: bool, exposed: bool, growth: float, need: float, start: float, dt: float, seasons: Array = [], greenhouse := false) -> Dictionary:
	var t0 := safe_time(start)
	if not (is_finite(dt) and dt > 0.0):return {"wet": wet, "growth": growth}
	var end := t0 + dt
	if not is_finite(end):end = t0
	var day := day_index(t0)
	if exposed and outdoor_id(day) == "rainy":wet = true
	var cursor := t0
	var growing := need > 0.0 and growth < need
	var steps := 0
	while true:
		var boundary := (day + 1.0) * DAY_SECONDS
		var seg_end := minf(boundary, end)
		if wet and growing and seg_end > cursor and (greenhouse or seasons.is_empty() or season_on_day(day) in seasons):
			growth = minf(growth + (seg_end - cursor), need)
			growing = growth < need
		if boundary > end:break
		# Midnight at `boundary` (<= end): dry, then re-wet if exposed and raining.
		day += 1.0
		cursor = boundary
		wet = exposed and outdoor_id(day) == "rainy"
		steps += 1
		if not growing or not exposed or steps >= MAX_DAY_STEPS:
			# Growth can no longer change (mature/unplanted, or unexposed and now
			# dry), or the safety cap was hit: jump straight to the final day.
			var last_day := day_index(end)
			if last_day > day:
				day = last_day
				wet = exposed and outdoor_id(day) == "rainy"
			break
	return {"wet": wet, "growth": growth}
