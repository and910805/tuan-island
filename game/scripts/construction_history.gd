extends RefCounted

const Industry=preload("res://scripts/industry.gd")
## T034 server-only construction history: dependency watches, fingerprints and
## strict persisted-shape validation for `state.construction`.
##
## Pure helpers only. World owns clocks, orientation, transactions and saving;
## construction_undo.gd owns the inverse delta and per-owner settlement.
##
## state.construction = {
##   "serial": int            monotonic record counter (ids are "c<serial>")
##   "last":   {token: entry} at most one entry (the LAST construction) per actor
## }
## entry = {
##   "id": "c<n>", "region": region id,
##   "action": build|build_area|remove|move_object|blueprint (blueprint: save v19+)|
##             build_edge (builds 1)|remove_edge (builds 0),
##   "label": short public text, "created_utc": float, "expires_utc": created+30,
##   "status": live|invalid|consumed|expired, "reason": code ("" while live),
##   "builds": builds-counter delta to reverse (build 1, build_area 1..49,
##             blueprint 1..768, remove/move_object 0); see builds_valid(),
##   "record": construction_undo record (live only, else {}),
##   "watch":  {watch_key: sha256 fingerprint} (live only, else {}),
## }
## The module record's `revisions` hold exactly the watch keys, all 0. A watch
## mismatch (or an explicit use mark) flips the entry to invalid permanently, so
## no unbounded global revision map is needed.
##
## Watch keys "<tier>:x,y":
##   f  full tile, every layer (ground/objects/roofs/crops/forest/removed/damage)
##      for every tile the record changes.
##   t  enclosure topology (ground type, wall/window/door type, full roof entry)
##      for the whole affected floor component(s) before AND after the
##      construction, their boundary and their open (gap) neighbours. Only when
##      the record changes floor/wall/window/door or automatic roofs.
##   n  network/logistics participation (full object entry when it is a water or
##      logistics device, else null) for every member of the connected same-owner
##      water network before AND after, plus each member's 4 expansion cells, and
##      the 4 neighbours of any logistics endpoint/belt the record changes.
##   e  grid-line edge row "e:x,y,N|W" (canonical EdgeGrid key; fingerprint {"e": row-or-null},
##      so a door `open` flip or any placement/removal invalidates) for every edge the record
##      changes and every edge bounding the analysed room component(s) before AND after.
##      The "t" value additionally carries the rows on the 4 sides of the cell (key "e", only
##      when a row exists), and edge changes seed "t" watches on both adjacent in-map cells.
## Unrelated distant tiles are never watched.

const UNDO := preload("res://scripts/construction_undo.gd")
const ENCLOSURE := preload("res://scripts/room_enclosure.gd")
const INDUSTRY := preload("res://scripts/industry.gd")

const WINDOW_SECONDS := 30.0
const WINDOW_MSEC := 30000
const MAX_UTC := 1000000000000.0
const MAX_SERIAL := 9007199254740991
const MAX_ENTRIES := 64
const MAX_ID_LEN := 32
const MAX_LABEL_LEN := 40
const MAX_WATCH := 4096
const MAX_AREA := 49
## Save v19: one whole blueprint transaction (16x16 footprint x 3 layers).
const MAX_BLUEPRINT_BUILDS := 768
const MAX_EDGE_BLUEPRINT_BUILDS := 1312
const UTC_TOLERANCE := 0.01
## build_edge (builds 1) / remove_edge (builds 0): grid-line edge rows only. There is no generic
## door-toggle action, and an edge change that only flips a door's `open` is never valid history.
const ACTIONS := ["build","build_area","remove","move_object","blueprint","build_edge","remove_edge","edge_blueprint"]
const STATUSES := ["live","invalid","consumed","expired"]
const ENTRY_KEYS := ["action","builds","created_utc","expires_utc","id","label","reason","record","region","status","watch"]
## "edges" is keyed by canonical EdgeGrid keys, not tiles: the "f" tier skips it (legacy f
## fingerprints stay byte-identical) and edge rows are watched by the "e" tier instead.
const TILE_LAYERS := ["ground","objects","roofs","crops","forest","removed","damage","edges"]
const EDGE_LAYER := "edges"
const EdgeGrid := preload("res://scripts/edge_grid.gd")
## C09: floor kinds come from the shared helper. The "t" tier fingerprint keeps the RAW ground type
## ("floor" stays "floor", so entries created before stone_floor existed hash exactly as before;
## "stone_floor" hashes differently, so swapping floor material still invalidates a watch).
const TOPOLOGY := ["floor","stone_floor","wall","window","door"]
const BOUNDARY := ["wall","window","door"]
const NETWORK := INDUSTRY.NETWORK
const LOGISTICS := ["conveyor","private_chest","forester","sawmill","charcoal_kiln","waterworks","mine_drill","mill"]
const DIRS: Array[Vector2i] = [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]

const TEXT_NONE := "目前沒有可復原的施工"
const TEXT_READY := "可以復原"
const REASONS := {
	"":"",
	"changed":"施工後這裡已有其他變動，無法復原",
	"used":"施工的設施或家具已被使用，無法復原",
	"untracked":"這次施工無法記錄復原資料",
	"expired":"已超過 30 秒，無法復原",
	"clock":"伺服器時間異常，無法復原",
	"consumed":"這次施工已復原",
}

static func fresh() -> Dictionary:
	return {"serial":0,"last":{}}

static func reason_text(code: String) -> String:
	return str(REASONS.get(code,"這筆施工已無法復原"))

# ---------------------------------------------------------------------------
# fingerprints
# ---------------------------------------------------------------------------

## Canonical JSON: sorted keys, whole numbers printed as integers whatever their
## runtime type (int vs JSON float), other floats via JSON.stringify (the same
## precision the save file uses, so values survive a reload unchanged).
static func canonical(value: Variant, depth: int = 0) -> String:
	if depth > UNDO.MAX_DEPTH:return "\"<deep>\""
	match typeof(value):
		TYPE_NIL:return "null"
		TYPE_BOOL:return "true" if value else "false"
		TYPE_INT:return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f):return "\"<nonfinite>\""
			if f == floorf(f) and absf(f) < 9007199254740992.0:return str(int(f))
			return JSON.stringify(f)
		TYPE_STRING, TYPE_STRING_NAME:return JSON.stringify(String(value))
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item in value:parts.append(canonical(item, depth + 1))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var names: Array = []
			var by_name := {}
			for k in dict:
				var name := JSON.stringify(str(k))
				names.append(name)
				by_name[name] = dict[k]
			names.sort()
			var parts: PackedStringArray = []
			for name in names:parts.append(str(name) + ":" + canonical(by_name[name], depth + 1))
			return "{" + ",".join(parts) + "}"
	return "\"<type%d>\"" % typeof(value)

static func fingerprint(value: Variant) -> String:
	return canonical(value).sha256_text()

static func _layer(layers: Dictionary, name: String) -> Dictionary:
	var layer = layers.get(name, {})
	return layer if layer is Dictionary else {}

static func _tier_value(layers: Dictionary, tier: String, tile: String, cell:Vector2i) -> Variant:
	match tier:
		"f":
			var all := {}
			for name in TILE_LAYERS:
				if name != EDGE_LAYER:all[name] = _layer(layers, name).get(tile)
			return all
		"t":
			var g = _layer(layers, "ground").get(tile)
			var o = _layer(layers, "objects").get(tile)
			var gt := str(g.get("type", "")) if g is Dictionary else ""
			var ot := str(o.get("type", "")) if o is Dictionary else ""
			var value := {"g":gt, "b":ot if ot in BOUNDARY else "", "r":_layer(layers, "roofs").get(tile)}
			# Rows on the 4 sides of the cell (N,E,S,W). Key only present when a row exists, so
			# fingerprints of cells without adjacent edges equal the legacy ones.
			var edges := _layer(layers, EDGE_LAYER)
			if not edges.is_empty():
				var rows := {}
				for side in EdgeGrid.SIDE_COUNT:
					var ek := EdgeGrid.key(cell, side, UNDO.EDGE_LIMITS)
					if ek != "" and edges.get(ek) != null:rows[ek] = edges[ek]
				if not rows.is_empty():value["e"] = rows
			return value
		"e":
			# tile is the canonical edge key itself: the single row (null when absent).
			return {"e":_layer(layers, EDGE_LAYER).get(tile)}
		"n":
			var o = _layer(layers, "objects").get(tile)
			if o is Dictionary and (str(o.get("type", "")) in NETWORK or str(o.get("type", "")) in LOGISTICS):return {"o":o}
			return {"o":null}
	return null

static func tile_fingerprint(layers: Dictionary, watch_key: String) -> String:
	var parsed := parse_watch_key(watch_key)
	if not parsed.ok:return ""
	return fingerprint(_tier_value(layers, parsed.tier, parsed.tile, parsed.cell))

## {ok, tier, tile, cell}. Canonical "x,y" only.
static func parse_watch_key(key: String) -> Dictionary:
	var bad := {"ok":false}
	if key.length() < 5 or key.length() > 32 or key[1] != ":":return bad
	var tier := key[0]
	if tier not in ["f","t","n","e"]:return bad
	var tile := key.substr(2)
	if tier == "e":
		# "e:x,y,N|W": cell is the canonical owner cell of the edge (may sit on the map rim).
		var d := EdgeGrid.decode(tile, UNDO.EDGE_LIMITS)
		if d.is_empty():return bad
		return {"ok":true, "tier":tier, "tile":tile, "cell":d.cell}
	var c := parse_tile(tile)
	if not c.ok:return bad
	return {"ok":true, "tier":tier, "tile":tile, "cell":c.cell}

static func parse_tile(tile: String) -> Dictionary:
	var parts := tile.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return {"ok":false}
	var x := int(parts[0])
	var y := int(parts[1])
	if absi(x) > 100000 or absi(y) > 100000 or tile != "%d,%d" % [x, y]:return {"ok":false}
	return {"ok":true, "cell":Vector2i(x, y)}

static func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

# ---------------------------------------------------------------------------
# watch construction / observation
# ---------------------------------------------------------------------------

## before/after: region layer dicts (TILE_LAYERS) bracketing ONE construction
## transaction; changes: construction_undo record["changes"]. Fingerprints are
## taken from `after`. Returns {ok, watch} (watch empty on failure).
## `size` (optional) is the region size: edge-derived topology seeds are then limited to in-map
## cells so every emitted watch cell stays inside the -1..size window _entry_valid accepts.
## Edge support: a record's changes.edges adds an "e:<edge key>" watch per changed edge, topology
## ("t") seeds on both adjacent in-map cells, and "e:" watches for the edge boundary of every
## analysed room component (before AND after). When either snapshot carries an "edges" layer,
## the tiles with a full ("f") watch that lie in the topology set also get a "t" watch so
## placements/removals on their sides by others invalidate the entry. Without any edge input the
## result is identical to the legacy one.
static func build_watch(before: Dictionary, after: Dictionary, changes: Dictionary, size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var full := {}
	var edge_aware: bool = before.has(EDGE_LAYER) or after.has(EDGE_LAYER)
	var edge_watch := {}
	var raw_edge_changes = changes.get(EDGE_LAYER, {})
	if not raw_edge_changes is Dictionary:return {"ok":false, "watch":{}}
	if changes.has(EDGE_LAYER) and raw_edge_changes.is_empty():return {"ok":false, "watch":{}}
	var topo_seeds: Array[Vector2i] = []
	var net_seeds: Array = []
	var logistics: Array[Vector2i] = []
	for layer in UNDO.LAYERS:
		var layer_changes = changes.get(layer)
		if not layer_changes is Dictionary:return {"ok":false, "watch":{}}
		for tile in layer_changes:
			var parsed := parse_tile(str(tile))
			if not parsed.ok:return {"ok":false, "watch":{}}
			var c: Vector2i = parsed.cell
			full[c] = true
			var change = layer_changes[tile]
			if not change is Dictionary:return {"ok":false, "watch":{}}
			for side in ["before","after"]:
				var entry = change.get(side)
				if not entry is Dictionary:continue
				var kind := str(entry.get("type", ""))
				var auto_roof: bool = layer == "roofs" and typeof(entry.get("auto")) == TYPE_BOOL and bool(entry.get("auto"))
				if auto_roof or (layer != "roofs" and kind in TOPOLOGY):topo_seeds.append(c)
				if layer == "objects" and kind in NETWORK:net_seeds.append([c, str(entry.get("owner", ""))])
				if layer == "objects" and kind in LOGISTICS:logistics.append(c)
	for ek in raw_edge_changes:
		var edge_key := str(ek)
		if typeof(ek) != TYPE_STRING or not EdgeGrid.is_valid_key(edge_key, UNDO.EDGE_LIMITS):return {"ok":false, "watch":{}}
		var echange = raw_edge_changes[ek]
		if not echange is Dictionary:return {"ok":false, "watch":{}}
		edge_watch[edge_key] = true
		for cell in EdgeGrid.cells_of(edge_key, UNDO.EDGE_LIMITS):
			if cell.x < 0 or cell.y < 0:continue
			if size != Vector2i.ZERO and (cell.x >= size.x or cell.y >= size.y):continue
			topo_seeds.append(cell)
	var topo := {}
	var net := {}
	for snapshot in [before, after]:
		var ground := _layer(snapshot, "ground")
		var objects := _layer(snapshot, "objects")
		var edge_rows := _layer(snapshot, EDGE_LAYER)
		var seen := {}
		for origin in topo_seeds:
			for start in [origin, origin + DIRS[0], origin + DIRS[1], origin + DIRS[2], origin + DIRS[3]]:
				topo[start] = true
				if seen.has(start):continue
				var comp: Dictionary = ENCLOSURE.analyze({"ground":ground, "objects":objects, "edges":edge_rows}, start)
				if comp.truncated:return {"ok":false, "watch":{}}
				for ek in comp.edge_boundary:edge_watch[ek] = true
				var inside := {}
				for cell in comp.cells:
					inside[cell] = true
					seen[cell] = true
					topo[cell] = true
				for cell in comp.boundary:topo[cell] = true
				for cell in comp.cells:
					for d in DIRS:topo[cell + d] = true
				if topo.size() > MAX_WATCH:return {"ok":false, "watch":{}}
		for pair in net_seeds:
			if not _network(objects, pair[0], pair[1], net):return {"ok":false, "watch":{}}
	for c in logistics:
		for d in DIRS:net[c + d] = true
	var watch := {}
	for c in full:watch["f:" + _key(c)] = ""
	for c in topo:
		if not full.has(c) or edge_aware:watch["t:" + _key(c)] = ""
	for c in net:
		if not full.has(c):watch["n:" + _key(c)] = ""
	for ek in edge_watch:watch["e:" + str(ek)] = ""
	if watch.is_empty() or watch.size() > MAX_WATCH:return {"ok":false, "watch":{}}
	for k in watch.keys():
		var parsed := parse_watch_key(k)
		if not parsed.ok:return {"ok":false, "watch":{}}
		watch[k] = fingerprint(_tier_value(after, parsed.tier, parsed.tile, parsed.cell))
	return {"ok":true, "watch":watch}

## Same-owner water network containing `start` (mirrors industry.gd components):
## adds members and their 4 expansion cells to `out`.
static func _network(objects: Dictionary, start: Vector2i, owner: String, out: Dictionary) -> bool:
	var first = objects.get(_key(start))
	if not first is Dictionary or str(first.get("type", "")) not in NETWORK or str(first.get("owner", "")) != owner:return true
	var seen := {start:true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		out[c] = true
		for d in DIRS:
			var n: Vector2i = c + d
			out[n] = true
			if seen.has(n):continue
			var other = objects.get(_key(n))
			if not other is Dictionary or str(other.get("type", "")) not in NETWORK or str(other.get("owner", "")) != owner:continue
			seen[n] = true
			queue.append(n)
		if out.size() > MAX_WATCH:return false
	return true

static func watch_matches(layers: Dictionary, watch: Dictionary) -> bool:
	if watch.is_empty():return false
	for k in watch:
		if typeof(k) != TYPE_STRING:return false
		var expected = watch[k]
		if typeof(expected) != TYPE_STRING or expected == "":return false
		if tile_fingerprint(layers, k) != expected:return false
	return true

## Used by periodic observation and the HUD. Exact bytes only reuse a previous
## successful comparison. A change is always judged by the persisted hash rules.
static func watch_matches_cached(layers:Dictionary,watch:Dictionary,memo:Dictionary) -> bool:
	if watch.is_empty():return false
	var watch_key:=var_to_bytes(watch)
	if watch_key.is_empty():return watch_matches(layers,watch)
	var same_watch:bool=memo.get("watch")==watch_key
	var checks:Array[Dictionary]=[]
	if same_watch:
		checks=memo.checks
	else:
		for key in watch:
			if not key is String or not watch[key] is String or watch[key].is_empty():return false
			var check:=parse_watch_key(key)
			if not check.ok:return false
			check.expected=watch[key]
			checks.append(check)
	var values:Array=[]
	for check:Dictionary in checks:
		values.append(_tier_value(layers,check.tier,check.tile,check.cell))
	var values_key:=var_to_bytes(values)
	if same_watch and not values_key.is_empty() and memo.get("values")==values_key:return true
	for index in checks.size():
		if fingerprint(values[index])!=checks[index].expected:return false
	if not values_key.is_empty():
		memo["watch"]=watch_key
		memo["checks"]=checks
		memo["values"]=values_key
	return true

## True when an explicitly used tile (machine/bench/pipe/belt use that may not
## change the tile itself) is a full or network dependency of this watch.
static func watch_used(watch: Dictionary, used_tiles: Dictionary) -> bool:
	for tile in used_tiles:
		if watch.has("f:" + str(tile)) or watch.has("n:" + str(tile)):return true
	return false

# ---------------------------------------------------------------------------
# strict persisted shape
# ---------------------------------------------------------------------------

static func _number(value, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _whole(value, maximum: float) -> bool:
	return _number(value, 0.0, maximum) and floorf(float(value)) == float(value)

static func _location(value, size: Vector2i) -> bool:
	if not value is String:return false
	var c := parse_tile(value)
	return c.ok and c.cell.x >= 0 and c.cell.y >= 0 and c.cell.x < size.x and c.cell.y < size.y

static func _plain_text(text: String, maximum: int) -> bool:
	if text.is_empty() or text.length() > maximum:return false
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch < 32 or ch == 127:return false
	return true

static func _sha256_text(value) -> bool:
	if not value is String or value.length() != 64:return false
	for i in 64:
		var ch: int = value.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102)):return false
	return true

static func id_serial(id) -> int:
	if not id is String or id.length() < 2 or id.length() > MAX_ID_LEN or id[0] != "c":return -1
	var digits: String = id.substr(1)
	if not digits.is_valid_int() or digits.begins_with("0") or digits.begins_with("-") or digits.begins_with("+"):return -1
	var n := int(digits)
	if n < 1 or "c%d" % n != id:return -1
	return n

## Per-action builds-counter delta. The only place history compares builds
## against an action: build exactly 1, build_area 1..MAX_AREA, blueprint
## 1..MAX_BLUEPRINT_BUILDS, remove/move_object exactly 0. Unknown actions,
## bools, strings, NaN/inf and fractional numbers are rejected; whole JSON
## floats (e.g. 26.0 after a JSON round-trip) are accepted.
static func builds_valid(action, builds) -> bool:
	if not action is String or action not in ACTIONS:return false
	match action:
		"build","build_edge":return _whole(builds, 1.0) and int(builds) == 1
		"build_area":return _whole(builds, float(MAX_AREA)) and int(builds) >= 1
		"blueprint":return _whole(builds, float(MAX_BLUEPRINT_BUILDS)) and int(builds) >= 1
		"edge_blueprint":return _whole(builds, float(MAX_EDGE_BLUEPRINT_BUILDS)) and int(builds) >= 1
		"remove","move_object","remove_edge":return _whole(builds, 0.0)
	return false

## Minimal shape a runtime caller needs before reading an entry (no record check).
static func entry_basic(entry) -> bool:
	if not entry is Dictionary:return false
	if id_serial(entry.get("id")) < 1 or not entry.get("region") is String or not entry.get("label") is String:return false
	if entry.get("status") not in STATUSES or not entry.get("reason") is String or not entry.get("action") is String or entry.get("action") not in ACTIONS:return false
	if not _number(entry.get("created_utc"), 0.0, MAX_UTC) or not _number(entry.get("expires_utc"), 0.0, MAX_UTC + WINDOW_SECONDS):return false
	if not builds_valid(entry.get("action"), entry.get("builds")):return false
	return entry.get("record") is Dictionary and entry.get("watch") is Dictionary

## Strict validation of s.construction against the (already validated) players.
## Region placement and per-object field rules of the recorded entries are
## checked by SaveSchema through validate_region projections.
static func validate(s: Dictionary, size: Vector2i, build: Dictionary, regions: Array) -> bool:
	var data = s.get("construction")
	if not data is Dictionary or data.size() != 2 or not data.has("serial") or not data.has("last"):return false
	if not _whole(data.serial, float(MAX_SERIAL)):return false
	var serial := int(data.serial)
	var last = data.last
	if not last is Dictionary or last.size() > MAX_ENTRIES:return false
	var players = s.get("players")
	if not players is Dictionary:return false
	# Alternate placement recipes and older machines can refund materials
	# which do not appear in the current construction catalog.
	var materials := {"sprinkler_kit":true,"ochre_earth":true}
	for kit: String in Industry.SPRINKLER_KITS.values():materials[kit]=true
	if build.has(Industry.MILL):
		for item: String in Industry.LEGACY_MILL_COST:
			if item != "name":materials[item]=true
	for kind in build:
		for item in build[kind]:
			if item != "name":materials[item] = true
	var ids := {}
	for token in last:
		if not token is String or not players.has(token):return false
		var entry = last[token]
		if not _entry_valid(entry, token, serial, size, build, regions, players, materials):return false
		if ids.has(entry.id):return false
		ids[entry.id] = true
	return true

static func _entry_valid(entry, token: String, serial: int, size: Vector2i, build: Dictionary, regions: Array, players: Dictionary, materials: Dictionary) -> bool:
	if not entry is Dictionary or entry.size() != ENTRY_KEYS.size():return false
	for field in ENTRY_KEYS:
		if not entry.has(field):return false
	if not entry_basic(entry):return false
	var n := id_serial(entry.id)
	if n > serial:return false
	if entry.region not in regions or not _plain_text(entry.label, MAX_LABEL_LEN):return false
	var created := float(entry.created_utc)
	if created <= 0.0 or created > MAX_UTC:return false
	if absf(float(entry.expires_utc) - created - WINDOW_SECONDS) > UTC_TOLERANCE:return false
	if not REASONS.has(entry.reason):return false
	if not builds_valid(entry.action, entry.builds):return false
	if entry.status != "live":
		return entry.reason != "" and entry.record.is_empty() and entry.watch.is_empty()
	if entry.reason != "":return false
	var record: Dictionary = entry.record
	if not UNDO.validate_record(record).ok or record.get("actor") != token:return false
	var watch: Dictionary = entry.watch
	var revisions: Dictionary = record.revisions
	if watch.is_empty() or watch.size() > MAX_WATCH or revisions.size() != watch.size():return false
	for k in watch:
		if not k is String or not revisions.has(k) or not _whole(revisions[k], 0.0):return false
		var parsed := parse_watch_key(k)
		if not parsed.ok:return false
		var c: Vector2i = parsed.cell
		if c.x < -1 or c.y < -1 or c.x > size.x or c.y > size.y:return false
		if not _sha256_text(watch[k]):return false
	var full := 0
	for layer in UNDO.LAYERS:
		var layer_changes: Dictionary = record.changes[layer]
		for tile in layer_changes:
			if not _location(tile, size) or not watch.has("f:" + tile):return false
			full += 1
			for side in ["before","after"]:
				var e = layer_changes[tile][side]
				if e == null:continue
				var kind = e.get("type")
				if not build.has(kind) or not players.has(e.get("owner")):return false
				if layer == "ground" and kind not in ["floor","stone_floor","path","spring_pebble_path",Industry.LEAF_MAT]:return false
				if layer == "roofs" and kind not in ["roof","greenhouse_roof",preload("res://scripts/greenhouse_glass.gd").XINGHE_ROOF,preload("res://scripts/terracotta_roof.gd").KIND]:return false
				if layer == "objects" and kind in ["floor","stone_floor","path","spring_pebble_path",Industry.LEAF_MAT,"roof","greenhouse_roof",preload("res://scripts/greenhouse_glass.gd").XINGHE_ROOF,preload("res://scripts/terracotta_roof.gd").KIND]:return false
	var edge_changes: Dictionary = record.changes.get(EDGE_LAYER, {})
	var edge_total := 0
	for ekey in edge_changes:
		if not EdgeGrid.is_valid_key(ekey, size) or not watch.has("e:" + ekey):return false
		edge_total += 1
		var change: Dictionary = edge_changes[ekey]
		var eb = change["before"]
		var ea = change["after"]
		for e in [eb, ea]:
			if e != null and not players.has(e.get("owner")):return false
		# A door `open` flip (same type and owner, nothing else different) is never undoable.
		if eb != null and ea != null and eb.get("type") == ea.get("type") and eb.get("owner") == ea.get("owner"):return false
		if entry.action == "build_edge" and (eb != null or ea == null):return false
		if entry.action == "remove_edge" and (eb == null or ea != null):return false
	if entry.action in ["build_edge","remove_edge"]:
		if edge_total < 1:return false
		# Edge actions may only touch edges plus (automatic) roofs; no tile ground/object edits.
		if not record.changes["ground"].is_empty() or not record.changes["objects"].is_empty():return false
	if full + edge_total < 1:return false
	if entry.action=="edge_blueprint" and edge_total<1:return false
	for owner in record.inventory_deltas:
		if not players.has(owner):return false
		for item in record.inventory_deltas[owner]:
			if not materials.has(item):return false
	return true
