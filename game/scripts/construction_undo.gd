extends RefCounted
## Pure inverse-delta capture and settlement for the planned T034 construction undo.
## NOT WIRED YET: nothing in World calls this module at this stage.
##
## capture(before, after, actor, revision_guard) -> {ok, message, record}
##   Compares two region-local snapshots {ground, objects, roofs, players} taken
##   around ONE server construction transaction and records only:
##     * changed entries of the three layers ground/objects/roofs, each as
##       {"before": entry-or-null, "after": entry-or-null} (null = absent);
##     * per-owner inventory deltas (before - after), i.e. the amounts to ADD to
##       that owner's CURRENT inventory to undo the transaction.
##   Nothing else (crops, forest, coins, other player fields, time, events...) is
##   captured; this is not a world-state rollback.
##
## prepare(current, actor, record, revisions) -> {ok, message, layers, inventories}
##   Validates that the record can still be undone against `current` and stages
##   the inverse: `layers` holds fresh deep copies of current ground/objects/roofs
##   with only the recorded keys restored to `before` (every other key kept as it
##   is now); `inventories` maps every affected owner to a fresh full inventory
##   copy = current inventory + recorded delta (items gained since the build and
##   unrelated items are kept). On failure `layers` and `inventories` are empty.
##
## Neither function mutates its inputs or the record; failures never return a
## partial result. Counts are normalized to int and runtime StringName inventory
## keys to String (a String/StringName key collision is rejected), matching
## auto_roof_settlement.gd.
##
## RECORD TRUST: a record is SERVER-ONLY data produced by capture() and kept in
## server memory/storage. It is never accepted from a client and carries no
## signature or MAC; validate_record() checks shape and ownership rules only and
## does not prove where the record came from.
##
## CALLER RESPONSIBILITIES (outside this module's boundary):
##   * Authorization: that `actor` is the authenticated requester, may undo in
##     this region, and that before/after really bracket one server transaction
##     by that actor. capture() accepts every inventory delta of a persistent
##     owner that is justified by a changed auto-roof of that owner (auto-roof
##     refunds/costs), so the caller must only pass genuine server snapshots.
##   * Revision guard coverage: `revision_guard` must contain a revision key for
##     everything the inverse depends on - every touched tile and its neighbours
##     in all layers, auto-roof enclosure topology, machine/logistics networks,
##     container contents, and any use-then-empty (ABA) state that deep equality
##     of the recorded entry cannot detect. prepare() only compares the recorded
##     keys exactly; an uncovered dependency is NOT detected.
##   * Players/actors standing on tiles that restored objects would occupy,
##     region membership, idempotence (consume the record exactly once), any
##     time expiry, persistence and atomic apply/rollback of layers +
##     inventories together, and schema/version migration of stored records.

const VERSION := 1
const LIMIT := 1000000000
const MAX_KEY_LEN := 64
const MAX_GUARD_KEYS := 4096
const MAX_GUARD_KEY_LEN := 256
const MAX_CHANGES := 4096
const MAX_ITEMS := 4096
const MAX_DEPTH := 32
const MAX_NODES := 65536
const MAX_REVISION_FLOAT := 9007199254740992.0  # 2^53: larger floats are not exact
const LAYERS := ["ground", "objects", "roofs"]
## Optional fourth sparse layer: snapshot.edges / changes.edges, keyed by canonical EdgeGrid
## keys ("x,y,N" / "x,y,W"). LAYERS deliberately stays the legacy three so v1 records (3 change
## layers) validate and hash exactly as before. changes.edges exists ONLY when at least one
## edge row changed; snapshots may omit "edges" entirely (both before and after, or neither).
## Rows: edge_wall/edge_window = exactly {type, owner}; edge_door = exactly {type, owner, open:bool}.
## Edge rows must be owned by the actor. Key bounds are structural only (any canonical key up to
## EDGE_LIMITS); ConstructionHistory bounds them against the real region size.
const EDGES := "edges"
const EDGE_TYPES := ["edge_wall", "edge_window", "edge_door"]
const EDGE_LIMITS := Vector2i(999999, 999999)
const EdgeGrid := preload("res://scripts/edge_grid.gd")

const MSG_ACTOR := "無法確認施工者，無法復原"
const MSG_NOT_YOURS := "這筆施工紀錄不屬於你，無法復原"
const MSG_GUARD := "版本檢查資料有誤，無法復原"
const MSG_LAYERS := "施工區域資料有誤，無法復原"
const MSG_OWNER := "只能復原自己的施工，無法復原"
const MSG_NONE := "沒有可以復原的施工變更"
const MSG_TOO_MANY := "施工變更太多，無法復原"
const MSG_DATA := "背包資料有誤，無法復原"
const MSG_INV_OWNER := "無法確認背包變動的對象，無法復原"
const MSG_RECORD := "施工紀錄有誤，無法復原"
const MSG_STALE := "施工後這裡已有其他變動，無法復原"
const MSG_RESTORE_OWNER := "原本的擁有者已不存在，無法復原"
const MSG_MISSING := "背包材料不足，無法復原"
const MSG_CAP := "復原後背包數量會超過上限，無法復原"
const MSG_CAPTURED := "已記錄可復原的施工"
const MSG_VALID := "施工紀錄檢查通過"
const MSG_OK := "復原檢查通過"

# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------

static func capture(before: Dictionary, after: Dictionary, actor: String, revision_guard: Dictionary) -> Dictionary:
	if not _valid_owner(actor):return _capture_fail(MSG_ACTOR)
	if not _snapshot_valid(before) or not _snapshot_valid(after):return _capture_fail(MSG_LAYERS)
	var guard: Dictionary = _parse_guard(revision_guard)
	if not bool(guard["ok"]):return _capture_fail(MSG_GUARD)
	var raw_bp: Variant = before.get("players")
	var raw_ap: Variant = after.get("players")
	if not (raw_bp is Dictionary) or not (raw_ap is Dictionary):return _capture_fail(MSG_LAYERS)
	var bp: Dictionary = raw_bp
	var ap: Dictionary = raw_ap
	if not bp.has(actor) or not ap.has(actor):return _capture_fail(MSG_ACTOR)
	var actor_b: Dictionary = _counts(_raw_inventory(bp[actor]), true)
	var actor_a: Dictionary = _counts(_raw_inventory(ap[actor]), true)
	if not bool(actor_b["ok"]) or not bool(actor_a["ok"]):return _capture_fail(MSG_DATA)
	# --- layer differences ------------------------------------------------
	var changes := {}
	var total := 0
	var roof_owners := {}
	for layer_name in LAYERS:
		var layer: String = layer_name
		var raw_lb: Variant = before.get(layer)
		var raw_la: Variant = after.get(layer)
		if not (raw_lb is Dictionary) or not (raw_la is Dictionary):return _capture_fail(MSG_LAYERS)
		var lb: Dictionary = raw_lb
		var la: Dictionary = raw_la
		var keys: Array = lb.keys()
		for k in la:
			if not lb.has(k):keys.append(k)
		var layer_changes := {}
		for k in keys:
			if typeof(k) != TYPE_STRING:return _capture_fail(MSG_LAYERS)
			var tile: String = k
			if not _valid_tile(tile):return _capture_fail(MSG_LAYERS)
			var has_b: bool = lb.has(tile)
			var has_a: bool = la.has(tile)
			var eb: Variant = lb.get(tile)
			var ea: Variant = la.get(tile)
			if has_b and has_a and _deep_equal(eb, ea, 0):continue
			total += 1
			if total > MAX_CHANGES:return _capture_fail(MSG_TOO_MANY)
			var problem := _entry_check(layer, has_b, eb, actor)
			if problem == "":problem = _entry_check(layer, has_a, ea, actor)
			if problem != "":return _capture_fail(problem)
			for entry in [eb if has_b else null, ea if has_a else null]:
				if entry == null:continue
				var owner := _owner_of(entry)
				if owner != actor and (not bp.has(owner) or not ap.has(owner)):return _capture_fail(MSG_OWNER)
				if layer == "roofs" and _is_auto(entry):roof_owners[owner] = true
			layer_changes[tile] = {"before": _copy(eb) if has_b else null, "after": _copy(ea) if has_a else null}
		changes[layer] = layer_changes
	# --- edge differences (optional layer; both snapshots or neither) -------
	if before.has(EDGES) != after.has(EDGES):return _capture_fail(MSG_LAYERS)
	if before.has(EDGES):
		var raw_eb: Variant = before.get(EDGES)
		var raw_ea: Variant = after.get(EDGES)
		if not (raw_eb is Dictionary) or not (raw_ea is Dictionary):return _capture_fail(MSG_LAYERS)
		var xb: Dictionary = raw_eb
		var xa: Dictionary = raw_ea
		var xkeys: Array = xb.keys()
		for k in xa:
			if not xb.has(k):xkeys.append(k)
		var edge_changes := {}
		for k in xkeys:
			if typeof(k) != TYPE_STRING or not _valid_edge_key(k):return _capture_fail(MSG_LAYERS)
			var ekey: String = k
			var has_b: bool = xb.has(ekey)
			var has_a: bool = xa.has(ekey)
			var eb: Variant = xb.get(ekey)
			var ea: Variant = xa.get(ekey)
			if has_b and has_a and _deep_equal(eb, ea, 0):continue
			total += 1
			if total > MAX_CHANGES:return _capture_fail(MSG_TOO_MANY)
			var problem := _edge_check(has_b, eb, actor)
			if problem == "":problem = _edge_check(has_a, ea, actor)
			if problem != "":return _capture_fail(problem)
			edge_changes[ekey] = {"before": _copy(eb) if has_b else null, "after": _copy(ea) if has_a else null}
		if not edge_changes.is_empty():changes[EDGES] = edge_changes
	if total == 0:return _capture_fail(MSG_NONE)
	# --- inventory deltas -------------------------------------------------
	var deltas := {}
	var owners: Array = bp.keys()
	for o in ap:
		if not bp.has(o):owners.append(o)
	for o in owners:
		if not bp.has(o) or not ap.has(o):return _capture_fail(MSG_INV_OWNER)
		var is_actor: bool = typeof(o) == TYPE_STRING and String(o) == actor
		var inv_b: Variant = _raw_inventory(bp[o])
		var inv_a: Variant = _raw_inventory(ap[o])
		if not is_actor and _deep_equal(inv_b, inv_a, 0):continue
		if typeof(o) != TYPE_STRING:return _capture_fail(MSG_INV_OWNER)
		var owner: String = o
		if not _valid_owner(owner):return _capture_fail(MSG_INV_OWNER)
		var cb: Dictionary = actor_b if is_actor else _counts(inv_b, true)
		var ca: Dictionary = actor_a if is_actor else _counts(inv_a, true)
		if not bool(cb["ok"]) or not bool(ca["ok"]):return _capture_fail(MSG_DATA)
		var vb: Dictionary = cb["counts"]
		var va: Dictionary = ca["counts"]
		var delta := {}
		var items: Array = vb.keys()
		for item in va:
			if not vb.has(item):items.append(item)
		for item in items:
			var d: int = int(vb.get(item, 0)) - int(va.get(item, 0))
			if d != 0:delta[item] = d
		if delta.is_empty():continue
		if delta.size() > MAX_ITEMS:return _capture_fail(MSG_DATA)
		# Only the actor, or a persistent owner of a changed auto roof (refund /
		# cost of that roof), may have a recorded inventory delta.
		if owner != actor and not roof_owners.has(owner):return _capture_fail(MSG_INV_OWNER)
		deltas[owner] = delta
	var record := {
		"version": VERSION,
		"actor": actor,
		"revisions": guard["revisions"],
		"changes": changes,
		"inventory_deltas": deltas,
	}
	return {"ok": true, "message": MSG_CAPTURED, "record": record}

# ---------------------------------------------------------------------------
# validate_record
# ---------------------------------------------------------------------------

## Structural and ownership validation of a server-side record (as produced by
## capture). Does not prove origin; never pass client data here.
## Returns {ok, message}.
static func validate_record(record: Dictionary) -> Dictionary:
	var version: Variant = record.get("version")
	if _whole(version) != VERSION:return _bad(MSG_RECORD)
	var raw_actor: Variant = record.get("actor")
	if typeof(raw_actor) != TYPE_STRING:return _bad(MSG_RECORD)
	var actor: String = raw_actor
	if not _valid_owner(actor):return _bad(MSG_RECORD)
	# JSON reloads whole numbers as floats; validate without mutating the record.
	var raw_rev: Variant = record.get("revisions")
	if not (raw_rev is Dictionary):return _bad(MSG_RECORD)
	var revs: Dictionary = raw_rev
	if revs.is_empty() or revs.size() > MAX_GUARD_KEYS:return _bad(MSG_RECORD)
	for k in revs:
		if typeof(k) != TYPE_STRING or not _valid_guard_key(String(k)):return _bad(MSG_RECORD)
		var v: Variant = revs[k]
		if _revision(v) < 0:return _bad(MSG_RECORD)
	# changes
	var raw_changes: Variant = record.get("changes")
	if not (raw_changes is Dictionary):return _bad(MSG_RECORD)
	var changes: Dictionary = raw_changes
	var has_edges: bool = changes.has(EDGES)
	if changes.size() != LAYERS.size() + (1 if has_edges else 0):return _bad(MSG_RECORD)
	var total := 0
	var roof_owners := {}
	for layer_name in LAYERS:
		var layer: String = layer_name
		var raw_layer: Variant = changes.get(layer)
		if not (raw_layer is Dictionary):return _bad(MSG_RECORD)
		var layer_changes: Dictionary = raw_layer
		for k in layer_changes:
			if typeof(k) != TYPE_STRING or not _valid_tile(String(k)):return _bad(MSG_RECORD)
			total += 1
			if total > MAX_CHANGES:return _bad(MSG_RECORD)
			var raw_change: Variant = layer_changes[k]
			if not (raw_change is Dictionary):return _bad(MSG_RECORD)
			var change: Dictionary = raw_change
			if change.size() != 2 or not change.has("before") or not change.has("after"):return _bad(MSG_RECORD)
			var eb: Variant = change["before"]
			var ea: Variant = change["after"]
			if eb == null and ea == null:return _bad(MSG_RECORD)
			if eb != null and ea != null and _deep_equal(eb, ea, 0):return _bad(MSG_RECORD)
			for entry in [eb, ea]:
				if entry == null:continue
				var problem := _entry_check(layer, true, entry, actor)
				if problem != "":return _bad(MSG_RECORD)
				if layer == "roofs" and _is_auto(entry):roof_owners[_owner_of(entry)] = true
	if has_edges:
		var raw_edges: Variant = changes[EDGES]
		if not (raw_edges is Dictionary) or (raw_edges as Dictionary).is_empty():return _bad(MSG_RECORD)
		var edge_changes: Dictionary = raw_edges
		for k in edge_changes:
			if typeof(k) != TYPE_STRING or not _valid_edge_key(String(k)):return _bad(MSG_RECORD)
			total += 1
			if total > MAX_CHANGES:return _bad(MSG_RECORD)
			var raw_change: Variant = edge_changes[k]
			if not (raw_change is Dictionary):return _bad(MSG_RECORD)
			var change: Dictionary = raw_change
			if change.size() != 2 or not change.has("before") or not change.has("after"):return _bad(MSG_RECORD)
			var eb: Variant = change["before"]
			var ea: Variant = change["after"]
			if eb == null and ea == null:return _bad(MSG_RECORD)
			if eb != null and ea != null and _deep_equal(eb, ea, 0):return _bad(MSG_RECORD)
			for entry in [eb, ea]:
				if entry == null:continue
				if _edge_check(true, entry, actor) != "":return _bad(MSG_RECORD)
	if total == 0:return _bad(MSG_RECORD)
	# inventory deltas
	var raw_deltas: Variant = record.get("inventory_deltas")
	if not (raw_deltas is Dictionary):return _bad(MSG_RECORD)
	var deltas: Dictionary = raw_deltas
	for o in deltas:
		if typeof(o) != TYPE_STRING:return _bad(MSG_RECORD)
		var owner: String = o
		if not _valid_owner(owner):return _bad(MSG_RECORD)
		if owner != actor and not roof_owners.has(owner):return _bad(MSG_RECORD)
		var raw_delta: Variant = deltas[o]
		if not (raw_delta is Dictionary):return _bad(MSG_RECORD)
		var delta: Dictionary = raw_delta
		if delta.is_empty() or delta.size() > MAX_ITEMS:return _bad(MSG_RECORD)
		for item in delta:
			if typeof(item) != TYPE_STRING or not _valid_item(String(item)):return _bad(MSG_RECORD)
			var d: Variant = delta[item]
			if typeof(d) not in [TYPE_INT,TYPE_FLOAT]:return _bad(MSG_RECORD)
			if not is_finite(float(d)) or float(d)!=floorf(float(d)) or absf(float(d))>LIMIT or float(d)==0:return _bad(MSG_RECORD)
	return {"ok": true, "message": MSG_VALID}

# ---------------------------------------------------------------------------
# prepare
# ---------------------------------------------------------------------------

## Only the read-only HUD preview supplies a cache. A hit reuses a detached
## proposal. Callers must not edit it or use it to commit an undo.
static func prepare(current: Dictionary, actor: String, record: Dictionary, revisions: Dictionary, preview:Variant=null) -> Dictionary:
	if not preview is Dictionary:return _prepare(current,actor,record,revisions)
	var players:Variant=current.get("players")
	if not players is Dictionary:return _prepare_fail(MSG_LAYERS)
	# The proposal depends on inventory and layer contents, including in-place
	# edits, but never on player coordinates or elapsed time.
	var inventories:Dictionary={}
	for owner in players:inventories[owner]=_raw_inventory(players[owner])
	var key:=var_to_bytes([actor,record,revisions,inventories,current.get("ground"),current.get("objects"),
		current.get("roofs"),current.has(EDGES),current.get(EDGES)])
	if not key.is_empty() and preview.get("inputs")==key:return preview.prepared
	var result:=_prepare(current,actor,record,revisions)
	if result.ok and not key.is_empty():
		preview["inputs"]=key
		preview["prepared"]=result
	return result

static func _prepare(current: Dictionary, actor: String, record: Dictionary, revisions: Dictionary) -> Dictionary:
	if not _valid_owner(actor):return _prepare_fail(MSG_ACTOR)
	if not _snapshot_valid(current):return _prepare_fail(MSG_LAYERS)
	var checked: Dictionary = validate_record(record)
	if not bool(checked["ok"]):return _prepare_fail(MSG_RECORD)
	var record_actor: String = record["actor"]
	if record_actor != actor:return _prepare_fail(MSG_NOT_YOURS)
	# --- exact revision match for every recorded dependency ---------------
	var recorded: Dictionary = record["revisions"]
	for k in recorded:
		if not revisions.has(k):return _prepare_fail(MSG_STALE)
		var now := _revision(revisions[k])
		if now < 0:return _prepare_fail(MSG_GUARD)
		if now != int(recorded[k]):return _prepare_fail(MSG_STALE)
	# --- current region shape ---------------------------------------------
	var raw_players: Variant = current.get("players")
	if not (raw_players is Dictionary):return _prepare_fail(MSG_LAYERS)
	var players: Dictionary = raw_players
	if not players.has(actor):return _prepare_fail(MSG_ACTOR)
	var actor_inv: Dictionary = _counts(_raw_inventory(players[actor]), true)
	if not bool(actor_inv["ok"]):return _prepare_fail(MSG_DATA)
	var changes: Dictionary = record["changes"]
	var current_layers := {}
	for layer_name in LAYERS:
		var layer: String = layer_name
		var raw_layer: Variant = current.get(layer)
		if not (raw_layer is Dictionary):return _prepare_fail(MSG_LAYERS)
		current_layers[layer] = raw_layer
	# --- every changed entry must still equal the recorded `after` --------
	for layer_name in LAYERS:
		var layer: String = layer_name
		var cur: Dictionary = current_layers[layer]
		var layer_changes: Dictionary = changes[layer]
		for tile in layer_changes:
			var change: Dictionary = layer_changes[tile]
			var ea: Variant = change["after"]
			var eb: Variant = change["before"]
			if ea == null:
				if cur.has(tile):return _prepare_fail(MSG_STALE)
			elif not cur.has(tile) or not _deep_equal(cur[tile], ea, 0):
				return _prepare_fail(MSG_STALE)
			if eb != null and not players.has(_owner_of(eb)):return _prepare_fail(MSG_RESTORE_OWNER)
	# --- edge rows (optional layer): same stale / owner rules ---------------
	var edge_changes: Dictionary = changes.get(EDGES, {})
	var current_edges: Dictionary = {}
	var has_current_edges: bool = current.has(EDGES)
	if has_current_edges:current_edges = current[EDGES]  # shape proven by _snapshot_valid
	if not edge_changes.is_empty() and not has_current_edges:return _prepare_fail(MSG_LAYERS)
	for ekey in edge_changes:
		var change: Dictionary = edge_changes[ekey]
		var ea: Variant = change["after"]
		var eb: Variant = change["before"]
		if ea == null:
			if current_edges.has(ekey):return _prepare_fail(MSG_STALE)
		elif not current_edges.has(ekey) or not _deep_equal(current_edges[ekey], ea, 0):
			return _prepare_fail(MSG_STALE)
		if eb != null and not players.has(_owner_of(eb)):return _prepare_fail(MSG_RESTORE_OWNER)
	# --- inventories: current + recorded delta, per owner -----------------
	var deltas: Dictionary = record["inventory_deltas"]
	var missing := false
	var capped := false
	var inventories := {}
	for o in deltas:
		var owner: String = o
		var parsed: Dictionary = actor_inv
		if owner != actor:
			if not players.has(owner):return _prepare_fail(MSG_INV_OWNER)
			parsed = _counts(_raw_inventory(players[owner]), true)
			if not bool(parsed["ok"]):return _prepare_fail(MSG_DATA)
		# Fresh copy; each owner only ever sees its own delta.
		var inv: Dictionary = (parsed["counts"] as Dictionary).duplicate()
		var delta: Dictionary = deltas[o]
		for item in delta:
			var key: String = item
			var value: int = int(inv.get(key, 0)) + int(delta[item])
			if value < 0:missing = true
			elif value > LIMIT:capped = true
			elif value != 0 or inv.has(key):inv[key] = value
		inventories[owner] = inv
	if missing:return _prepare_fail(MSG_MISSING)
	if capped:return _prepare_fail(MSG_CAP)
	# --- stage layers: copy, then restore only recorded keys --------------
	var layers := {}
	for layer_name in LAYERS:
		var layer: String = layer_name
		var cur: Dictionary = current_layers[layer]
		var staged: Dictionary = cur.duplicate(true)
		var layer_changes: Dictionary = changes[layer]
		for tile in layer_changes:
			var change: Dictionary = layer_changes[tile]
			var eb: Variant = change["before"]
			if eb == null:staged.erase(tile)
			else:staged[tile] = _copy(eb)
		layers[layer] = staged
	if has_current_edges:
		var staged_edges: Dictionary = current_edges.duplicate(true)
		for ekey in edge_changes:
			var eb: Variant = (edge_changes[ekey] as Dictionary)["before"]
			if eb == null:staged_edges.erase(ekey)
			else:staged_edges[ekey] = _copy(eb)
		layers[EDGES] = staged_edges
	return {"ok": true, "message": MSG_OK, "layers": layers, "inventories": inventories}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Reject malformed cells even outside the delta before deep-copying a layer.
# Full placement, resource bounds and recipe validity remain World/Schema rules.
static func _snapshot_valid(snapshot: Dictionary) -> bool:
	var players=snapshot.get("players")
	if not players is Dictionary:return false
	for owner in players:
		if not owner is String or not _valid_owner(owner):return false
		if not _counts(_raw_inventory(players[owner]),true).ok:return false
	for layer in LAYERS:
		var entries=snapshot.get(layer)
		if not entries is Dictionary:return false
		if _scan(entries,0,MAX_NODES)<0:return false
		for tile in entries:
			if not tile is String or not _valid_tile(tile):return false
			var entry=entries[tile]
			if not _entry_shape(layer,entry):return false
			if not players.has(entry.owner):return false
	if snapshot.has(EDGES):
		var rows=snapshot[EDGES]
		if not rows is Dictionary:return false
		if _scan(rows,0,MAX_NODES)<0:return false
		for ekey in rows:
			if not ekey is String or not _valid_edge_key(ekey):return false
			var row=rows[ekey]
			if not _edge_shape(row):return false
			if not players.has(row.owner):return false
	return true

static func _valid_edge_key(key:String)->bool:
	return key.length()<=MAX_KEY_LEN and EdgeGrid.is_valid_key(key,EDGE_LIMITS)

## Exact edge row shape: wall/window {type,owner}; door {type,owner,open:bool}. All keys Strings.
static func _edge_shape(row:Variant)->bool:
	if not row is Dictionary:return false
	for k in row:
		if typeof(k)!=TYPE_STRING:return false
	var kind=row.get("type")
	if not kind is String or kind not in EDGE_TYPES:return false
	var owner=row.get("owner")
	if not owner is String or not _valid_owner(owner):return false
	if kind=="edge_door":
		return row.size()==3 and typeof(row.get("open"))==TYPE_BOOL
	return row.size()==2

## "" when an edge row is acceptable for `actor` (shape ok and owned by the actor).
static func _edge_check(present:bool,row:Variant,actor:String)->String:
	if not present:return ""
	if not _edge_shape(row):return MSG_LAYERS
	if _scan(row,0,MAX_NODES)<0:return MSG_LAYERS
	if String((row as Dictionary)["owner"])!=actor:return MSG_OWNER
	return ""

static func _entry_shape(layer:String,entry:Variant)->bool:
	if not entry is Dictionary:return false
	var kind=entry.get("type")
	if not kind is String or kind.is_empty():return false
	var owner=entry.get("owner")
	if not owner is String or not _valid_owner(owner):return false
	if not _counts(entry.get("items"),true).ok:return false
	if layer=="roofs" and kind not in ["roof",preload("res://scripts/greenhouse_glass.gd").XINGHE_ROOF,preload("res://scripts/terracotta_roof.gd").KIND]:return false
	if layer=="roofs" and kind!="roof" and entry.has("auto"):return false
	if entry.has("auto") and (layer!="roofs" or typeof(entry.auto)!=TYPE_BOOL):return false
	return true

## "" when the entry is acceptable for `actor`, otherwise an error message.
## Non-roof entries and manual roofs must be owned by the actor; automatic
## roofs may belong to another owner (persistence is checked by the caller).
static func _entry_check(layer: String, present: bool, entry: Variant, actor: String) -> String:
	if not present:return ""
	if not _entry_shape(layer,entry):return MSG_LAYERS
	if _scan(entry, 0, MAX_NODES) < 0:return MSG_LAYERS
	var raw_owner: Variant = (entry as Dictionary).get("owner")
	if typeof(raw_owner) != TYPE_STRING:return MSG_OWNER
	var owner: String = raw_owner
	if not _valid_owner(owner):return MSG_OWNER
	if owner == actor:return ""
	if layer == "roofs" and _is_auto(entry):return ""
	return MSG_OWNER

## Owner string of an entry already accepted by _entry_check.
static func _owner_of(entry: Variant) -> String:
	if not (entry is Dictionary):return ""
	var raw_owner: Variant = (entry as Dictionary).get("owner")
	if typeof(raw_owner) != TYPE_STRING:return ""
	var owner: String = raw_owner
	return owner

static func _is_auto(entry: Variant) -> bool:
	if not (entry is Dictionary):return false
	var flag: Variant = (entry as Dictionary).get("auto")
	return typeof(flag) == TYPE_BOOL and bool(flag)

static func _copy(entry: Variant) -> Variant:
	if entry is Dictionary:return (entry as Dictionary).duplicate(true)
	return null

static func _raw_inventory(player: Variant) -> Variant:
	if not (player is Dictionary):return null
	return (player as Dictionary).get("inventory")

## Remaining node budget, or -1 when the value contains unsupported types,
## non-finite floats, or exceeds depth/size bounds (also stops cycles).
static func _scan(value: Variant, depth: int, budget: int) -> int:
	budget -= 1
	if budget < 0 or depth > MAX_DEPTH:return -1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2I, TYPE_VECTOR3I:
			return budget
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return budget
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f):return -1
			return budget
		TYPE_ARRAY:
			var arr: Array = value
			for item in arr:
				budget = _scan(item, depth + 1, budget)
				if budget < 0:return -1
			return budget
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			for k in dict:
				budget = _scan(k, depth + 1, budget)
				if budget < 0:return -1
				budget = _scan(dict[k], depth + 1, budget)
				if budget < 0:return -1
			return budget
	return -1

## Deep equality with JSON-compatible numeric equality, but no bool coercion. Values
## deeper than MAX_DEPTH compare unequal, so cycles terminate deterministically.
static func _deep_equal(a: Variant, b: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH:return false
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:
		return is_finite(float(a)) and is_finite(float(b)) and a==b
	if typeof(a) != typeof(b):return false
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():return false
			for k in da:
				if not db.has(k):return false
				if not _deep_equal(da[k], db[k], depth + 1):return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():return false
			for i in aa.size():
				if not _deep_equal(aa[i], ab[i], depth + 1):return false
			return true
		TYPE_FLOAT:
			var fa: float = a
			var fb: float = b
			return fa == fb
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
	return a == b

## {ok, revisions}: fresh String => int map; 1..MAX_GUARD_KEYS keys.
static func _parse_guard(raw: Dictionary) -> Dictionary:
	if raw.is_empty() or raw.size() > MAX_GUARD_KEYS:return {"ok": false}
	var out := {}
	for k in raw:
		if typeof(k) != TYPE_STRING:return {"ok": false}
		var key: String = k
		if not _valid_guard_key(key):return {"ok": false}
		var v := _revision(raw[k])
		if v < 0:return {"ok": false}
		out[key] = v
	return {"ok": true, "revisions": out}

## Non-negative whole finite revision as int, or -1.
static func _revision(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			var n: int = value
			return n if n >= 0 and n <= 9007199254740992 else -1
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or f < 0.0 or f > MAX_REVISION_FLOAT:return -1
			return int(f)
	return -1

## {ok, counts}: fresh String => int copy of an inventory. Keys non-empty
## Strings (StringName allowed when allow_names, normalized; collisions fail).
static func _counts(source: Variant, allow_names: bool = false) -> Dictionary:
	if not (source is Dictionary):return {"ok": false}
	var dict: Dictionary = source
	var values := {}
	for item in dict:
		var t := typeof(item)
		if t != TYPE_STRING and not (allow_names and t == TYPE_STRING_NAME):return {"ok": false}
		var key := String(item)
		if not _valid_item(key):return {"ok": false}
		if values.has(key):return {"ok": false}
		var n := _whole(dict[item])
		if n < 0:return {"ok": false}
		values[key] = n
	return {"ok": true, "counts": values}

## Integer count in 0..LIMIT, or -1 (bool/string/NaN/inf/fractional rejected).
static func _whole(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			var n: int = value
			return n if n >= 0 and n <= LIMIT else -1
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or f < 0.0 or f > float(LIMIT):return -1
			return int(f)
	return -1

static func _valid_owner(owner: String) -> bool:
	if owner == "" or owner.length() > MAX_KEY_LEN or owner.strip_edges() != owner:return false
	for i in owner.length():
		var ch := owner.unicode_at(i)
		if ch < 32 or ch == 127:return false
	return true

static func _valid_tile(tile: String) -> bool:
	return tile != "" and tile.length() <= MAX_KEY_LEN

static func _valid_item(item: String) -> bool:
	return item != "" and item.length() <= MAX_KEY_LEN

static func _valid_guard_key(key: String) -> bool:
	return key != "" and key.length() <= MAX_GUARD_KEY_LEN

static func _bad(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _capture_fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "record": {}}

static func _prepare_fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "layers": {}, "inventories": {}}
