local model = require("./lib/model.luau")
local options = require("./lib/options.luau")
local snapshot = noctalia.state.get("snapshot") or {}
-- Capture the host's initial bar orientation. Later snapshots in Noctalia 5.3
-- infer orientation from the rendered content bounds, which can flip a compact tree.
local vertical = barWidget.isVertical()
local function render()
  local selected = model.selectedDevices(snapshot)
  local settings = options.read(noctalia.getConfig)
  local devices = options.visible(selected, settings.show_offline)
  local groups, rows = {}, {}
  local layout = vertical and ui.column or ui.row
  local deviceIcons = settings.icon_style == "device" or (settings.icon_style == "auto" and #selected > 1)
  for _, d in ipairs(devices) do
    local color = model.color(d, settings.low_threshold)
    local children = { ui.glyph({ name = deviceIcons and options.deviceGlyph(d) or model.glyph(d), size = 16,
      color = color ~= "on_surface" and color or nil }) }
    if settings.show_percentage then
      children[#children + 1] = ui.label({ text = model.level(d, true), fontSize = 14 })
    end
    groups[#groups + 1] = layout({ key = d.id, gap = 4, align = "center" }, children)
    local detail = model.level(d, false)
    if d.stale then
      local age = d.observed_at and d.observed_at > 0 and (model.age(d.observed_at, math.floor(noctalia.nowMs()/1000)) .. " ago") or noctalia.tr("unavailable")
      detail = detail .. " · " .. noctalia.tr("stale") .. " " .. age
    elseif d.state and d.state ~= "unknown" then
      detail = detail .. " · " .. noctalia.tr(d.state == "empty" and "empty_state" or d.state)
    end
    rows[#rows + 1] = { key = d.name, value = detail }
  end
  if #groups == 0 then
    groups[1] = ui.glyph({ name = "devices", size = 16 })
    rows[1] = { key = noctalia.tr("title"), value = noctalia.tr(#selected > 0 and "selected_unavailable" or "select_devices") }
  end
  barWidget.render(layout({ gap = settings.entry_spacing, align = "center" }, groups))
  barWidget.setTooltip(rows)
end
noctalia.state.watch("snapshot", function(value) snapshot = value or {}; render() end)
function update() noctalia.setUpdateInterval(10000); render() end
function onClick()
  noctalia.state.set("panel_options", options.read(noctalia.getConfig))
  noctalia.togglePanel("sh/device-battery:devices")
end
function onConfigChanged()
  noctalia.state.set("panel_options", options.read(noctalia.getConfig))
  render()
end
render()
