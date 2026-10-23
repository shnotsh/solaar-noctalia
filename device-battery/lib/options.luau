local M = {}
local function bounded(value, fallback, low, high)
  local n = tonumber(value)
  if not n or n ~= n then n = fallback end
  return math.max(low, math.min(high, n))
end

function M.read(get)
  local iconStyle = get("icon_style")
  return {
    refresh_seconds = bounded(get("refresh_seconds"), 60, 30, 600),
    low_threshold = bounded(get("low_threshold"), 20, 0, 50),
    show_percentage = get("show_percentage") ~= false,
    entry_spacing = bounded(get("entry_spacing"), 12, 0, 48),
    icon_style = (iconStyle == "device" or iconStyle == "battery") and iconStyle or "auto",
    show_offline = get("show_offline") ~= false,
    show_progress = get("show_progress") ~= false,
  }
end

function M.pollInterval(widgets)
  local seconds
  for _, widget in pairs(widgets or {}) do
    if widget.type == "sh/device-battery:battery" then
      local value = bounded(widget.refresh_seconds, 60, 30, 600)
      seconds = seconds and math.min(seconds, value) or value
    end
  end
  -- Readers are shared. Multiple widget instances use the shortest requested interval.
  return seconds or 60
end

function M.visible(devices, showOffline)
  local rows = {}
  for _, d in ipairs(devices or {}) do
    if showOffline or (d.online and not d.stale) then rows[#rows + 1] = d end
  end
  return rows
end

function M.deviceGlyph(d)
  local icons = { laptop = "device-laptop", mouse = "mouse", keyboard = "keyboard", headset = "headphones", gamepad = "device-gamepad-2" }
  return icons[d.kind] or "devices"
end

return M
