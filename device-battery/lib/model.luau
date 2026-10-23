-- Pure state and display logic; also runnable by the local Lua test suite.
local M = {}
local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function M.valid(row)
  if type(row) ~= "table" or type(row.id) ~= "string" or #row.id == 0 or #row.id > 240 then return false end
  if type(row.name) ~= "string" or type(row.observed_at) ~= "number" then return false end
  if row.percent ~= nil and (type(row.percent) ~= "number" or row.percent ~= row.percent or row.percent < 0 or row.percent > 100) then return false end
  return true
end

function M.canonical(id, aliases)
  local original, seen = id, {}
  while type(aliases) == "table" and type(aliases[id]) == "string" and aliases[id] ~= "" do
    if seen[id] then return original end -- Invalid alias cycles must not merge unrelated devices.
    seen[id], id = true, aliases[id]
  end
  return id
end

-- Accept legacy single selections while normalizing the ordered multi-selection.
function M.selection(value, aliases)
  if type(value) == "string" then value = { value } end
  local result, seen = {}, {}
  for _, id in ipairs(type(value) == "table" and value or {}) do
    if type(id) == "string" and id ~= "" and id ~= "auto" and id ~= "none" then
      id = M.canonical(id, aliases)
      if not seen[id] then result[#result + 1], seen[id] = id, true end
    end
  end
  return result
end

function M.contains(selected, id)
  if type(selected) == "string" then return selected == id end
  for _, wanted in ipairs(selected or {}) do if wanted == id then return true end end
  return false
end

function M.selectedIds(snapshot)
  return M.selection(snapshot.selected_ids or snapshot.selected or "system")
end

function M.restore(saved)
  local cache = {}
  for _, raw in pairs(saved or {}) do
    if M.valid(raw) then
      local d = copy(raw)
      d.id = type(d.source_id) == "string" and d.source_id or d.id
      d.source_id, d.stale = d.id, true
      cache[d.id] = d
    end
  end
  return cache
end

function M.merge(cache, provider, devices, ok, now)
  local seen = {}
  if ok then
    for _, raw in ipairs(devices) do
      if M.valid(raw) and raw.observed_at <= now + 60 then
        local d = copy(raw)
        d.provider = provider
        d.source_id = raw.id
        d.last_seen_at = now
        seen[d.id] = true
        local old = cache[d.id]
        if not d.online or (d.percent == nil and d.level == nil) then
          if old then
            d.percent, d.level, d.precision = old.percent, old.level, old.precision
            d.observed_at = old.observed_at
          end
          d.stale = true
        else
          d.stale = false
        end
        -- Retain each transport independently. Grouping happens only at presentation time,
        -- so a disconnect or slow query cannot erase the other transport's current reading.
        cache[d.id] = d
      end
    end
  end
  for id, d in pairs(cache) do
    if d.provider == provider and not seen[id] then
      d.stale = true
      if ok then d.online = false end
    end
  end
end

local function retained(id, raw, selected, now, aliases)
  local canonical = M.canonical(id, aliases)
  return M.contains(M.selection(selected, aliases), canonical) or canonical == "system"
    or now - (raw.last_seen_at or raw.observed_at) < 86400
end

function M.persist(cache, selected, now, aliases)
  local saved = {}
  for id, d in pairs(cache) do
    if M.valid(d) and retained(id, d, selected, now, aliases) then saved[id] = d end
  end
  return saved
end

local function preferred(a, b)
  if not b then return true end
  if a.stale ~= b.stale then return not a.stale end
  -- Once all transports are stale, retain the most recent actual battery observation.
  local aKnown, bKnown = a.percent ~= nil or a.level ~= nil, b.percent ~= nil or b.level ~= nil
  if aKnown ~= bKnown then return aKnown end
  if a.observed_at ~= b.observed_at then return a.observed_at > b.observed_at end
  return a.source_id < b.source_id
end

function M.rows(cache, selected, now, interval, aliases)
  local rows, groups = {}, {}
  for id, raw in pairs(cache) do
    if M.valid(raw) and retained(id, raw, selected, now, aliases) then
      local d = copy(raw)
      d.source_id, d.id = raw.source_id or id, M.canonical(id, aliases)
      d.stale = d.stale or not d.online or now - d.observed_at > math.max(90, interval * 2)
      if preferred(d, groups[d.id]) then groups[d.id] = d end
    end
  end
  for _, d in pairs(groups) do rows[#rows + 1] = d end
  table.sort(rows, function(a, b)
    if a.id == "system" then return b.id ~= "system" end
    if b.id == "system" then return false end
    if a.online ~= b.online then return a.online == true end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return rows
end

function M.selected(snapshot)
  local wanted = M.selectedIds(snapshot)[1] or "none"
  for _, d in ipairs(snapshot.devices or {}) do if d.id == wanted then return d end end
  return { id = wanted, name = wanted == "system" and "Laptop battery" or (wanted == "auto" and "Device battery" or "Selected device"), online = false, stale = true }
end

function M.selectedDevices(snapshot)
  local byId, devices = {}, {}
  for _, d in ipairs(snapshot.devices or {}) do byId[d.id] = d end
  for _, id in ipairs(M.selectedIds(snapshot)) do
    devices[#devices + 1] = byId[id] or { id = id, name = id == "system" and "Laptop battery" or "Selected device", online = false, stale = true }
  end
  return devices
end

function M.visibleErrors(diagnostics, devices, aliases)
  local current, errors = {}, {}
  for _, d in ipairs(devices) do
    if d.online and not d.stale then current[d.id] = true end
  end
  for _, e in ipairs(diagnostics) do
    if type(e) == "string" then errors[#errors + 1] = e
    elseif type(e) == "table" and type(e.message) == "string" then
      -- An idle dongle is expected while this same controller is active on Bluetooth.
      if not current[M.canonical(e.device_id, aliases)] then errors[#errors + 1] = e.message end
    end
  end
  return errors
end

function M.level(d, inBar)
  if inBar and (d.stale or not d.online) then return "—" end
  if type(d.percent) == "number" then return tostring(math.floor(d.percent + .5)) .. "%" end
  if type(d.level) == "string" then return d.level:sub(1,1):upper() .. d.level:sub(2) end
  return inBar and "—" or "Unknown"
end

function M.glyph(d)
  if d.stale or not d.online then return "battery-off" end
  if d.state == "charging" then return "battery-charging" end
  if type(d.percent) ~= "number" then return "battery" end
  if d.percent >= 90 then return "battery-4" end
  if d.percent >= 60 then return "battery-3" end
  if d.percent >= 30 then return "battery-2" end
  if d.percent > 5 then return "battery-1" end
  return "battery"
end

function M.color(d, threshold)
  if d.stale or not d.online then return "on_surface_variant" end
  if d.state == "charging" then return "primary" end
  if (type(d.percent) == "number" and d.percent <= threshold) or d.level == "low" or d.level == "critical" then return "error" end
  return "on_surface"
end

function M.age(timestamp, now)
  if not timestamp or timestamp == 0 then return "never" end
  local seconds = math.max(0, now - timestamp)
  if seconds < 60 then return tostring(math.floor(seconds)) .. "s" end
  if seconds < 3600 then return tostring(math.floor(seconds / 60)) .. "m" end
  return tostring(math.floor(seconds / 3600)) .. "h"
end

return M
