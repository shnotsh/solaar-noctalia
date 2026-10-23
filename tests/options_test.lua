local options = dofile('device-battery/lib/options.luau')
local widgets = {
  first={type='sh/device-battery:battery',refresh_seconds=90},
  unrelated={type='clock',refresh_seconds=1},
}
assert(options.pollInterval(widgets)==90)
widgets.second={type='sh/device-battery:battery',refresh_seconds=45}
assert(options.pollInterval(widgets)==45, 'shared provider uses the shortest configured interval')
widgets.second.refresh_seconds=0
assert(options.pollInterval(widgets)==30, 'invalid rapid polling is clamped')
local config={show_percentage=false,icon_style='device',low_threshold=35,show_offline=false,show_progress=false}
local settings=options.read(function(k)return config[k]end)
assert(not settings.show_percentage and settings.icon_style=='device' and settings.low_threshold==35)
local devices={{id='selected',online=false,stale=true},{id='stale',online=true,stale=true},{id='current',online=true,stale=false}}
local visible=options.visible(devices,false)
assert(#visible==1 and visible[1].id=='current', 'offline and stale devices hide in both bar and dropdown')
assert(#options.visible(devices,true)==3)
local model=dofile('device-battery/lib/model.luau')
local snapshot={devices=devices,selected_ids={'selected','current'}}
assert(#options.visible(model.selectedDevices(snapshot),false)==1, 'selected offline devices hide from the bar')
assert(#snapshot.selected_ids==2, 'filtering preserves selection')
devices[1].online=true;devices[1].stale=false
local reconnected=options.visible(model.selectedDevices(snapshot),false)
assert(#reconnected==2 and reconnected[1].id=='selected', 'reconnected device returns in its original selection order')
assert(options.read(function()end).entry_spacing==12)
for _, pair in ipairs({{-1,0},{0,0},{24,24},{100,48}}) do
  assert(options.read(function(k)if k=='entry_spacing' then return pair[1] end end).entry_spacing==pair[2])
end
assert(options.read(function()end).icon_style=='auto')
assert(options.read(function(k)if k=='icon_style' then return 'battery' end end).icon_style=='battery', 'explicit icon preference is preserved')
print('Widget options checks passed')
