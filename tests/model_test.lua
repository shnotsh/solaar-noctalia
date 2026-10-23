local model = dofile("device-battery/lib/model.luau")
local count = 0
local function check(value, message) assert(value, message); count = count + 1 end
local cache = {}
local function row(id, percent, stamp)
  return { id = id, name = id, percent = percent, observed_at = stamp or 100, online = true, state = "discharging" }
end
model.merge(cache, "eightbitdo", { row("pad", 61) }, true, 100, {})
check(cache.pad.percent == 61, "live percentage")
model.merge(cache, "eightbitdo", {}, false, 110, {})
check(cache.pad.percent == 61 and cache.pad.stale, "failure preserves marked last-known value")
check(model.level(cache.pad, true) == "—", "stale percentage never appears current on bar")
model.merge(cache, "eightbitdo", { row("pad", 60, 120) }, true, 120, {})
check(not cache.pad.stale and model.level(cache.pad, true) == "60%", "reconnect clears stale")
model.merge(cache, "eightbitdo", {}, true, 130, {})
check(cache.pad.online == false, "disconnected receiver")
local aliases = { ["bt-pad"] = "pad" }
model.merge(cache, "system", { row("bt-pad", 59, 140) }, true, 140)
check(#model.rows(cache, "pad", 140, 60, aliases) == 1, "explicit transport mapping deduplicates")
model.merge(cache, "eightbitdo", { { id="pad", name="pad", online=false, observed_at=0 } }, true, 141, {})
local linked = model.rows(cache, "pad", 141, 60, aliases)[1]
check(linked.provider == "system" and not linked.stale, "failed dongle cannot replace fresh Bluetooth")
model.merge(cache, "system", { row("system", 100, 140), row("bt-pad", 59, 140) }, true, 140, { ["bt-pad"] = "pad" })
local list = model.rows(cache, "pad", 150, 60, aliases)
check(#list == 2 and list[1].id == "system", "laptop ordered first")
check(model.selected({ selected="missing", devices=list }).id == "missing", "missing selection never silently switches")
check(model.rows(cache, "pad", 300, 60, aliases)[2].stale, "age invalidates stale readings")
check(model.rows(cache, "pad", 90000, 60, aliases)[2].id == "pad", "selected offline device survives retention")
check(not model.valid(row("bad", 101)), "invalid percentage rejected")
check(not model.valid(row("bad", 0/0)), "NaN rejected")
local zero = row("zero", 0); zero.stale = false
check(model.level(zero, true) == "0%" and model.color(zero,20) == "error", "zero is a valid low battery")
zero.state = "charging"
check(model.glyph(zero) == "battery-charging" and model.color(zero,20) == "primary", "charging wins over warning")
local unknown = {}
model.merge(unknown, "eightbitdo", {{id="new-pad", name="Controller", observed_at=0, online=false}}, true, 90000, {})
check(#model.rows(unknown, "system", 90001, 60) == 1, "discovered offline controller remains visible without a fabricated reading")
check(#model.rows(unknown, "system", 180000, 60) == 0, "unselected unseen devices expire after a day")
local multi = { selected_ids = {"pad", "system"}, devices = list }
local chosen = model.selectedDevices(multi)
check(#chosen == 2 and chosen[1].id == "pad" and chosen[2].id == "system", "bar order follows selection rather than panel order")
check(#model.selectedDevices({selected_ids={}, selected="system",devices=list}) == 0, "explicit empty multi-selection wins over legacy selection")
check(table.concat(model.selection({"bt-pad", "system", "pad"}, aliases), ",") == "pad,system", "aliased multi-selections merge without reordering")
print("Model checks passed: " .. count)
