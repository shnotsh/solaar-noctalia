local model = require("./lib/model.luau")
local options = require("./lib/options.luau")
local providers = { "system", "logitech", "eightbitdo" }
local cache, selected, busy, errors, attempted = {}, { "system" }, {}, {}, {}
local autoSelect = false
local directory = noctalia.pluginDataDir()
local storePath = directory and (directory .. "/state.json")
local helper = noctalia.pluginDir() .. "/scripts/battery_helper.py"
local function now() return math.floor(noctalia.nowMs() / 1000) end
local function interval() return options.pollInterval(noctalia.getSetting("widget")) end
local function aliases() return noctalia.getConfig("device_aliases") or {} end

if storePath then
  local raw = noctalia.readFile(storePath)
  local saved = raw and noctalia.json.decode(raw)
  if type(saved) == "table" and (saved.schema == 1 or saved.schema == 2 or saved.schema == 3) then
    selected = model.selection(saved.schema == 3 and saved.selected_ids or saved.selected or "system", aliases())
    autoSelect = saved.auto_select == true or (saved.schema < 3 and saved.selected == "auto")
    cache = model.restore(saved.cache)
  end
end

local function snapshot()
  local status, working = {}, false
  for _, p in ipairs(providers) do
    if busy[p] then working = true end
    for _, e in ipairs(errors[p] or {}) do status[#status + 1] = e end
  end
  local devices = model.rows(cache, selected, now(), interval(), aliases())
  if autoSelect then
    for _, d in ipairs(devices) do
      if d.online and not d.stale then selected, autoSelect = { d.id }, false; break end
    end
  end
  return { devices = devices, selected_ids = selected, selected = selected[1] or (autoSelect and "auto" or "none"), busy = working,
    errors = model.visibleErrors(status, devices, aliases()), diagnostics = status,
    initialized = next(attempted) ~= nil, sampled_at = now(), refresh_seconds = interval() }
end

local function publish() noctalia.state.set("snapshot", snapshot()) end
local function save()
  if not storePath then return end
  -- Preserve separate transport observations so aliases remain reversible and survive restart.
  local saved = model.persist(cache, selected, now(), aliases())
  local encoded = noctalia.json.encode({ schema = 3, selected_ids = selected, auto_select = autoSelect, cache = saved })
  if encoded and noctalia.writeFile(storePath .. ".tmp", encoded) then
    noctalia.renameFile(storePath .. ".tmp", storePath)
  end
end

local function fetch(provider)
  if busy[provider] then return end
  busy[provider], attempted[provider] = true, now()
  publish()
  local launched = noctalia.runAsync({ "python3", helper, "--provider", provider }, function(result)
    busy[provider] = false
    local data = result.exitCode == 0 and not result.timedOut and not result.stdoutTruncated
      and noctalia.json.decode(result.stdout or "") or nil
    if type(data) == "table" and data.schema == 1 and data.provider == provider
      and type(data.devices) == "table" and type(data.errors) == "table" then
      errors[provider] = data.errors
      model.merge(cache, provider, data.devices, data.ok == true, now())
      if provider == "system" and data.ok == true then
        local hasLaptop = false
        for _, d in ipairs(data.devices) do if d.id == "system" then hasLaptop = true end end
        if not hasLaptop then
          cache.system = nil
          if model.contains(selected, "system") then
            local remaining = {}
            for _, id in ipairs(selected) do if id ~= "system" then remaining[#remaining + 1] = id end end
            selected, autoSelect = remaining, #remaining == 0
          end
        end
      end
    else
      errors[provider] = { provider .. ": " .. (result.timedOut and "battery query timed out" or "battery query failed") }
      model.merge(cache, provider, {}, false, now())
    end
    publish()
    save()
  end, 15000)
  if not launched then
    busy[provider] = false
    errors[provider] = { provider .. ": could not start Python battery reader" }
    model.merge(cache, provider, {}, false, now())
    publish()
  end
end

function update()
  noctalia.setUpdateInterval(1000)
  for _, p in ipairs(providers) do
    local delay = p == "system" and 30 or interval()
    if not attempted[p] or now() - attempted[p] >= delay then fetch(p) end
  end
  publish()
end

local function refresh(force, immediate)
  for _, p in ipairs(providers) do
    if immediate or not attempted[p] or now() - attempted[p] >= (force and 5 or 15) then fetch(p) end
  end
end

local function choose(id, toggle)
  if type(id) ~= "string" then return end
  id = model.canonical(id, aliases())
  local found = false
  for _, d in ipairs(model.rows(cache, selected, now(), interval(), aliases())) do
    if d.id == id then found = true; break end
  end
  if not found then return end
  if toggle then
    local nextSelection = {}
    for _, current in ipairs(selected) do if current ~= id then nextSelection[#nextSelection + 1] = current end end
    if not model.contains(selected, id) then nextSelection[#nextSelection + 1] = id end
    selected = nextSelection
  else
    selected = { id }
  end
  autoSelect = false
  publish()
  save()
end

noctalia.state.watch("request", function(request)
  if type(request) ~= "table" then return end
  if request.action == "select" then choose(request.id)
  elseif request.action == "toggle" then choose(request.id, true)
  elseif request.action == "refresh" then refresh(true)
  elseif request.action == "open" then refresh(false) end
end)

function onIpc(event, payload)
  if event == "refresh" then refresh(true)
  elseif event == "force-refresh" then refresh(true, true)
  elseif event == "select" then choose(payload)
  elseif event == "toggle" then choose(payload, true)
  elseif event == "dump" and directory then
    noctalia.writeFile(directory .. "/snapshot.json", noctalia.json.encode(snapshot(), true))
  end
end

function onConfigChanged()
  selected = model.selection(selected, aliases())
  refresh(true); publish(); save()
end
publish()
