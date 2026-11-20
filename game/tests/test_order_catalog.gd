extends SceneTree

const Catalog = preload("res://scripts/order_catalog.gd")
const Village = preload("res://scripts/village.gd")
const Weather = preload("res://scripts/weather.gd")
const World = preload("res://scripts/world.gd")

var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var spring_day := Weather.DAYS_PER_SEASON - 1
	var summer_day := spring_day + 1
	var winter_day := Weather.DAYS_PER_SEASON * 3
	var spring := Catalog.make_context(spring_day, true, false, [], World.CROP_SEASONS)
	var summer := Catalog.make_context(summer_day, true, false, [], World.CROP_SEASONS)
	var winter := Catalog.make_context(winter_day, true, false, [], World.CROP_SEASONS)
	expect(Catalog.validate_catalog().is_empty(), "Catalog IDs and material routes validate")
	for definition:Dictionary in Catalog.orders():
		expect(World.ORDER_BOARDS.has(definition.get("channel","village")),"Every order has a shared delivery destination")
	expect(Catalog.candidate_ids(spring_day, spring) == ["radish", "fish", "bread"], "Spring offers crops, fish and bread")
	expect(Catalog.candidate_ids(winter_day, winter) == ["fish"], "Winter excludes unavailable crops and dependent bread")
	var now := float(spring_day) * Village.DAY + 100.0
	var bag := {"radish": 3}
	var book := {"day": spring_day, "done": []}
	expect(not Catalog.check_delivery(book, "radish", now, bag, spring).ok, "Legacy book requires acceptance")
	var accepted := Catalog.accept(book, "radish", now, spring)
	expect(accepted.ok and not book.has("active"), "Accept preserves the caller's book")
	var saved_book: Dictionary = JSON.parse_string(JSON.stringify(accepted.book))
	var later := float(summer_day) * Village.DAY
	expect(not Catalog.candidate_ids(summer_day, summer).has("radish"), "Summer excludes new radish orders")
	expect(Catalog.board_view(saved_book, later, summer).any(func(row: Dictionary) -> bool:
		return row.id == "radish" and row.status == "active" and row.remaining > 0
	), "Active radish order survives reloading and season rollover")
	var short_delivery := Catalog.check_delivery(saved_book, "radish", later, {}, summer)
	expect(not short_delivery.ok and short_delivery.book.active.has("radish"), "Missing items leave the order active")
	var delivered := Catalog.check_delivery(saved_book, "radish", later, bag, summer)
	expect(delivered.ok and delivered.book.done == ["radish"] and bag.radish == 3, "Delivery returns a commit plan without mutating the bag")
	expect(not Catalog.check_delivery(delivered.book, "radish", later, bag, summer).ok, "Same-day delivery cannot repeat")
	var deadline := float(saved_book.active.radish.due)
	expect(Catalog.check_delivery(saved_book, "radish", deadline - 0.01, bag, summer).ok, "Delivery accepted just before the deadline")
	var expired := Catalog.check_delivery(saved_book, "radish", deadline, bag, summer)
	expect(not expired.ok and expired.message == Catalog.MSG_EXPIRED, "Deadline is exclusive")
	expect(Catalog.cancel(saved_book, "radish", later).book.active.is_empty() and saved_book.active.has("radish"), "Cancellation removes only the returned active entry")
	var book_across_regions:={"active":{
		"lanyang_rice":{"accepted":5.0,"due":1300.0},
		"radish":{"accepted":0.0,"due":1500.0},
		"dock_shrimp":{"accepted":1.0,"due":1000.0},
	}}
	var tracking:=Catalog.journal_rows(book_across_regions,1200.0)
	expect(tracking.map(func(row):return row.id)==["lanyang_rice","radish","dock_shrimp"],"Cross-region journal lists active orders by nearest deadline, then expired")
	expect(tracking[0].remaining==100.0 and tracking[2].status=="expired" and tracking[2].remaining==0.0,"Journal countdown and expiry use world time")
	expect(book_across_regions.active.size()==3,"Reading the journal cannot change saved orders")
	print("ORDER CATALOG checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
