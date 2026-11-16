extends RefCounted
## Standalone fishing pity (rare-fish guarantee) rules.
##
## Pure and side-effect free except for `commit`, which only touches the one
## counter named by an outcome. It never reads world state, saves or the
## network; callers pass the per-player dictionary and the catch context.
##
## Source of truth today is still Collections.fishing_result (called from
## World.act "fish_catch"). This module mirrors those rules exactly and reuses
## Collections.RARE_WATERS / RARE_FISH_LIMIT so fish IDs and save counter keys
## stay identical. test_fishing_pity.gd asserts parity over a context grid.
##
## Integration hooks (NOT wired; shared files are owned elsewhere):
##   world.gd  ~L1960-1972 fish_catch: replace the `result.has("counter")`
##             write with FishingPity.resolve(...) + FishingPity.commit(...)
##             after the inventory-cap check passes.
##   collections.gd fishing_result L63-87: could delegate its eligibility and
##             misses branches to FishingPity.eligible / FishingPity.resolve.
##   save_schema.gd ~L712-717: legacy beimen_fishing_misses migration and the
##             whole(counter,19) check; FishingPity.migrate / valid_state cover
##             the same rules if the schema wants to call them.

const Collections := preload("res://scripts/collections.gd")
const BambooGrove := preload("res://scripts/bamboo_grove.gd")

const LIMIT: int = Collections.RARE_FISH_LIMIT
const MAX_MISSES: int = Collections.RARE_FISH_LIMIT - 1
## Every 23rd lifetime catch (total % 23 == 22) in an eligible water is a lucky
## early rare, matching Collections.fishing_result.
const LUCKY_PERIOD := 23
const LEGACY_COUNTERS := {"beimen_fishing_misses": "beimen_flounder_misses"}


static func regions() -> Array:
	var keys: Array = Collections.RARE_WATERS.keys()
	keys.sort()
	return keys


static func counters() -> Array:
	var names: Array = []
	for region in regions():
		names.append(String(Collections.RARE_WATERS[region].counter))
	return names


static func counter_for(region: String) -> String:
	return String(Collections.RARE_WATERS.get(region, {}).get("counter", ""))


static func rare_fish_for(region: String) -> String:
	return String(Collections.RARE_WATERS.get(region, {}).get("fish", ""))


## A stored counter value is valid when it is a finite whole number in
## [0, MAX_MISSES]. JSON reloads turn ints into floats, so 7.0 is accepted.
static func valid_misses(value) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= float(MAX_MISSES) and floorf(number) == number


## Conservative read: invalid, missing or out-of-range values count as zero so
## a corrupt save can never grant an early guarantee.
static func sanitize_misses(value) -> int:
	return int(value) if valid_misses(value) else 0


## True when every pity counter present on the player is valid. Mirrors the
## save_schema whole(counter, RARE_FISH_LIMIT - 1) rule, including legacy keys.
static func valid_state(person) -> bool:
	if not person is Dictionary:
		return false
	for key in LEGACY_COUNTERS:
		if person.has(key) and not valid_misses(person[key]):
			return false
	for key in counters():
		if person.has(key) and not valid_misses(person[key]):
			return false
	return true


## Returns a new dictionary holding exactly the known counters as ints. Legacy
## keys are folded in when the modern key is absent (same as save_schema).
## Does not mutate `person`.
static func sanitize(person) -> Dictionary:
	var source: Dictionary = person if person is Dictionary else {}
	var clean := {}
	for key in counters():
		clean[key] = sanitize_misses(source.get(key, 0))
	for legacy in LEGACY_COUNTERS:
		var modern: String = LEGACY_COUNTERS[legacy]
		if source.has(legacy) and not source.has(modern):
			clean[modern] = sanitize_misses(source[legacy])
	return clean


## In-place legacy migration matching save_schema: returns false (and leaves
## the dictionary untouched) if a legacy value is invalid.
static func migrate(person: Dictionary) -> bool:
	for legacy in LEGACY_COUNTERS:
		if person.has(legacy) and not valid_misses(person[legacy]):
			return false
	for legacy in LEGACY_COUNTERS:
		if not person.has(legacy):
			continue
		var modern: String = LEGACY_COUNTERS[legacy]
		if not person.has(modern):
			person[modern] = person[legacy]
		person.erase(legacy)
	return true


## Whether a successful catch in this context draws from the region's rare
## pool (and therefore advances or spends its pity counter). `minute` is the
## minute of the in-game day (0..1440).
static func eligible(region: String, season: String, minute: float = 720.0, spot: String = "coast", raining: bool = false) -> bool:
	match region:
		"lanyang":
			return season == String(Collections.RARE_WATERS.lanyang.season) or raining
		"beimen":
			# Tide pools always give gold_shrimp, the pier gives moon_squid at
			# night and every daytime spot gives sardine without touching pity.
			return spot != "tidepool" and spot != "pier" and not Collections.coast_is_day(minute)
		"jiaoxi":
			return spot == "upland" and season == "winter"
		"bamboo_grove":
			return BambooGrove.breezy(minute)
		"star_garden":
			return not Collections.coast_is_day(minute)
	return false


## Pure prediction of what a *successful* catch would do to pity.
## Returns {"eligible":false} or
## {"eligible":true,"region","counter","fish","hit","misses_before","misses"}
## where "misses" is the counter value to store after the catch.
static func resolve(region: String, season: String, total: int, person, minute: float = 720.0, spot: String = "coast", raining: bool = false) -> Dictionary:
	if not eligible(region, season, minute, spot, raining):
		return {"eligible": false}
	var counter := counter_for(region)
	var before := sanitize_misses((person if person is Dictionary else {}).get(counter, 0))
	var hit := before + 1 >= LIMIT or total % LUCKY_PERIOD == LUCKY_PERIOD - 1
	return {
		"eligible": true,
		"region": region,
		"counter": counter,
		"fish": rare_fish_for(region),
		"hit": hit,
		"misses_before": before,
		"misses": 0 if hit else before + 1,
	}


## Applies a resolved outcome to one player's dictionary. Only writes when the
## catch action itself succeeded (`landed`) and the outcome was eligible; a
## failed cast, early reel, wrong spot, cap rejection or replay must pass
## landed=false. Returns true if the counter was written.
static func commit(person: Dictionary, outcome: Dictionary, landed: bool) -> bool:
	if not landed or not outcome.get("eligible", false):
		return false
	var counter = outcome.get("counter", "")
	if not counter is String or counter not in counters():
		return false
	var value = outcome.get("misses")
	if not valid_misses(value):
		return false
	person[counter] = int(value)
	return true


## Catches remaining until the guarantee fires (1 means the next eligible
## catch is guaranteed). Ignores the lucky-period bonus.
static func catches_until_guarantee(person, region: String) -> int:
	var counter := counter_for(region)
	if counter.is_empty():
		return -1
	return LIMIT - sanitize_misses((person if person is Dictionary else {}).get(counter, 0))
