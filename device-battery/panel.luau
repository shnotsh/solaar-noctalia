local model = require("./lib/model.luau")
local options = require("./lib/options.luau")
local snapshot = noctalia.state.get("snapshot") or {}
local settings = noctalia.state.get("panel_options") or options.read(function() return nil end)
local nonce = 0
local function request(action, id)
  nonce = nonce + 1
  noctalia.state.set("request", { action = action, id = id, nonce = noctalia.nowMs() + nonce })
end
local function tr(key) return noctalia.tr(key) end

local function card(d)
  local chosen = model.contains(model.selectedIds(snapshot), d.id)
  local color = model.color(d, settings.low_threshold)
  local detail = d.transport or ""
  if d.stale then
    detail = d.online and tr("stale") or tr("offline")
    if d.observed_at and d.observed_at > 0 then
      detail = detail .. " · last read " .. model.age(d.observed_at, math.floor(noctalia.nowMs()/1000)) .. " ago"
    end
  elseif d.state and d.state ~= "unknown" then
    detail = detail .. (detail ~= "" and " · " or "") .. tr(d.state == "empty" and "empty_state" or d.state)
  end
  local name = d.id == "system" and "Laptop battery" or d.name
  local content = {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = options.deviceGlyph(d), size = 21, color = chosen and "primary" or "on_surface_variant" }),
      ui.column({ flexGrow = 1, gap = 3 }, {
        ui.label({ text = name, fontSize = 14, fontWeight = "medium", maxLines = 1, maxWidth = 235 }),
        ui.label({ text = detail, fontSize = 11, color = "on_surface_variant", maxLines = 1, maxWidth = 235 }),
      }),
      ui.label({ text = model.level(d, false), fontSize = 16, fontWeight = "semibold", color = color }),
      ui.glyph({ name = chosen and "circle-check-filled" or "circle", size = 20, color = chosen and "primary" or "on_surface_variant" }),
    }),
  }
  if settings.show_progress and type(d.percent) == "number" then
    content[#content + 1] = ui.progress({ progress = d.percent / 100, height = 4, radius = 2,
      fill = d.stale and "on_surface_variant/0.45" or (color == "error" and "error" or "primary"), track = "on_surface/0.08" })
  end
  return ui.column({ key = d.id, gap = 10, padding = 13, radius = 12,
    fill = chosen and "primary/0.10" or "on_surface/0.035",
    border = chosen and "primary/0.40" or "on_surface/0.07", borderWidth = 1,
    onClick = function() request("toggle", d.id) end }, content)
end

local function render()
  local cards = {}
  local devices = options.visible(snapshot.devices, settings.show_offline)
  for _, d in ipairs(devices) do cards[#cards + 1] = card(d) end
  if #cards == 0 then
    cards[1] = ui.column({ gap = 12, padding = 24, align = "center" }, {
      ui.glyph({ name = "battery-off", size = 36, color = "on_surface_variant" }),
      ui.label({ text = snapshot.busy and tr("waiting") or tr("empty"), color = "on_surface_variant" }),
    })
  end
  local tree = {
    ui.row({ align = "center", gap = 12 }, {
      ui.label({ text = tr("title"), fontSize = 16, fontWeight = "semibold", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", width = 36, height = 36,
        enabled = not snapshot.busy, tooltip = snapshot.busy and tr("refreshing") or tr("refresh"),
        onClick = function() request("refresh") end }),
    }),
    ui.scroll({ flexGrow = 1, gap = 9, align = "stretch" }, cards),
  }
  if snapshot.errors and #snapshot.errors > 0 then
    tree[#tree + 1] = ui.label({ text = snapshot.errors[1], fontSize = 11, color = "on_surface_variant", maxLines = 2 })
  end
  tree[#tree + 1] = ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = tostring(#model.selectedIds(snapshot)) .. " selected", fontSize = 11, color = "on_surface_variant" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = snapshot.busy and tr("refreshing") or tostring(#devices) .. " devices", fontSize = 11, color = "on_surface_variant" }),
  })
  panel.render(ui.column({ flexGrow = 1, gap = 16 }, tree))
end

noctalia.state.watch("snapshot", function(value) snapshot = value or {}; render() end)
noctalia.state.watch("panel_options", function(value) settings = value or settings; render() end)
function onOpen() request("open"); render() end
function update() noctalia.setUpdateInterval(1000); render() end
render()
