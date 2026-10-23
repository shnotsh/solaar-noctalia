local model = dofile("device-battery/lib/model.luau")
local options = dofile("device-battery/lib/options.luau")
local stamp, pending, state, watched, disk = 100000, {}, {}, {}, {}
local saved, aliasSettings = nil, {}
local widgetSettings = {battery={type='sh/device-battery:battery',refresh_seconds=60}}
local host = {
  nowMs=function() return stamp end, pluginDir=function() return 'device-battery' end,
  pluginDataDir=function() return '/data' end,
  getConfig=function(key) if key=='refresh_seconds' then return 60 elseif key=='device_aliases' then return aliasSettings end end,
  getSetting=function(key) assert(key=='widget'); return widgetSettings end,
  readFile=function(path) return disk[path] end,
  writeFile=function(path, value) disk[path]=value; return true end,
  renameFile=function(a,b) disk[b]=disk[a]; disk[a]=nil; return true end,
  setUpdateInterval=function() end,
  json={ encode=function(value) saved=value; return 'saved' end,
    decode=function(value) if value=='saved' then return saved else return value end end },
  state={get=function(key) return state[key] end, set=function(key,value) state[key]=value end,
    watch=function(key,fn) watched[key]=fn end},
  runAsync=function(argv,callback,timeout) assert(timeout==15000); pending[#pending+1]={provider=argv[#argv],callback=callback}; return true end,
}
local env = setmetatable({ noctalia=host, require=function(path) return path:find('options') and options or model end }, {__index=_G})
assert(loadfile('device-battery/service.luau','t',env))()
env.update(); env.update()
assert(#pending==3, 'overlapping requests must be suppressed')
for _, request in ipairs(pending) do
  local devices = request.provider=='system' and {{id='system',name='Laptop',percent=73,online=true,observed_at=100}} or {}
  request.callback({exitCode=0,stdout={schema=1,provider=request.provider,devices=devices,errors={},ok=true}})
end
assert(not state.snapshot.busy and #state.snapshot.devices==1)
watched.request({action='refresh'}); assert(#pending==3, 'refresh debounce')
stamp=131000; env.update(); assert(#pending==4, 'system cadence independent of peripheral cadence')
pending[4].callback({exitCode=-1,timedOut=true})
assert(state.snapshot.devices[1].percent==73 and state.snapshot.devices[1].stale, 'timeout retains last known')
watched.request({action='select',id='not-found'}); assert(state.snapshot.selected=='system')
env.onIpc('dump'); assert(disk['/data/snapshot.json'], 'diagnostic snapshot available')
-- Loading a pre-fix cache must migrate the selected Bluetooth ID and merge all
-- previously visible identities before the first new hardware poll completes.
saved = {schema=1, selected='bt', cache={
  bt={id='bt',source_id='bt',provider='system',name='Controller',percent=61,online=false,observed_at=120},
  usb={id='usb',source_id='usb',provider='eightbitdo',name='Controller',percent=60,online=false,observed_at=121},
  cable={id='cable',source_id='cable',provider='eightbitdo',name='Controller',percent=73,online=false,observed_at=110},
}}
disk['/data/state.json']='saved'; aliasSettings={bt='usb',cable='usb'}
assert(loadfile('device-battery/service.luau','t',env))()
assert(state.snapshot.selected=='usb' and #state.snapshot.devices==1, 'legacy cache and selection migrate before refresh')
env.onIpc('select','bt')
assert(saved.schema==3 and saved.selected_ids[1]=='usb', 'selecting old transport persists canonical identity')
assert(saved.cache.bt and saved.cache.usb and saved.cache.cable, 'all transport observations persist separately')
assert(loadfile('device-battery/service.luau','t',env))()
assert(state.snapshot.selected=='usb' and #state.snapshot.devices==1, 'restart preserves selection without duplicate entries')
aliasSettings={bt='usb',cable='usb',usb='physical-controller'}
env.onConfigChanged()
assert(state.snapshot.selected=='physical-controller' and #state.snapshot.devices==1, 'runtime alias edit migrates existing selection')
widgetSettings.battery.refresh_seconds=120
env.update()
assert(state.snapshot.refresh_seconds==120, 'bar widget polling setting reaches shared service')
-- A cache copied from a laptop must not create a phantom laptop on a desktop.
saved={schema=2,selected='system',cache={system={id='system',name='Laptop',percent=100,online=true,provider='system',observed_at=120}}}
disk['/data/state.json']='saved';aliasSettings={};pending={}
assert(loadfile('device-battery/service.luau','t',env))()
env.update()
pending[1].callback({exitCode=0,stdout={schema=1,provider='system',devices={},errors={},ok=true}})
assert(#state.snapshot.devices==0 and state.snapshot.selected=='auto', 'no laptop row or phantom laptop selection on a desktop')
pending[3].callback({exitCode=0,stdout={schema=1,provider='eightbitdo',devices={{id='pad',name='Controller',percent=60,online=true,observed_at=131}},errors={},ok=true}})
assert(#state.snapshot.devices==1 and state.snapshot.selected=='pad', 'desktop automatically selects an available peripheral')
-- Multiple choices preserve user order, survive restart, and retain every selected
-- offline device beyond the normal cache expiry. Aliases never duplicate a choice.
saved={schema=3,selected_ids={'bt','mouse','usb'},cache={
  bt={id='bt',provider='system',name='Controller',percent=60,online=false,observed_at=120},
  usb={id='usb',provider='eightbitdo',name='Controller',percent=59,online=false,observed_at=121},
  mouse={id='mouse',provider='logitech',name='Mouse',percent=85,online=false,observed_at=120},
  old={id='old',provider='logitech',name='Forgotten',percent=40,online=false,observed_at=120},
}}
disk['/data/state.json']='saved';aliasSettings={bt='usb'};pending={};stamp=90000000
assert(loadfile('device-battery/service.luau','t',env))()
assert(table.concat(state.snapshot.selected_ids,',')=='usb,mouse' and #state.snapshot.devices==2, 'all selected devices retained and aliased selections deduplicated')
watched.request({action='toggle',id='bt'})
assert(table.concat(saved.selected_ids,',')=='mouse', 'toggle through a transport alias removes just that selection')
-- Supply a fresh controller after its unselected, old observation expires.
env.update()
pending[3].callback({exitCode=0,stdout={schema=1,provider='eightbitdo',devices={{id='usb',name='Controller',percent=59,online=true,observed_at=90000}},errors={},ok=true}})
watched.request({action='toggle',id='bt'})
assert(table.concat(saved.selected_ids,',')=='mouse,usb', 'new selections append without replacing existing choices')
assert(loadfile('device-battery/service.luau','t',env))()
assert(table.concat(state.snapshot.selected_ids,',')=='mouse,usb', 'multiple selections and ordering survive restart')
watched.request({action='toggle',id='mouse'});watched.request({action='toggle',id='usb'})
assert(#saved.selected_ids==0 and not saved.auto_select, 'deselecting all is an explicit choice')
assert(loadfile('device-battery/service.luau','t',env))()
pending={};env.update()
pending[1].callback({exitCode=0,stdout={schema=1,provider='system',devices={},errors={},ok=true}})
pending[3].callback({exitCode=0,stdout={schema=1,provider='eightbitdo',devices={{id='usb',name='Controller',percent=59,online=true,observed_at=90000}},errors={},ok=true}})
assert(#state.snapshot.selected_ids==0, 'an empty selection survives restart and discovery on desktops')
watched.request({action='toggle',id='system'})
assert(#state.snapshot.selected_ids==0, 'a missing laptop cannot be selected')
-- Right-click bypasses polling/debounce delays, but never overlaps a provider query.
saved=nil;disk={};pending={};aliasSettings={};stamp=100000000
assert(loadfile('device-battery/service.luau','t',env))()
env.update()
for _, request in ipairs(pending) do
  request.callback({exitCode=0,stdout={schema=1,provider=request.provider,devices={},errors={},ok=true}})
end
assert(#pending==3 and not state.snapshot.busy)
env.onIpc('force-refresh')
assert(#pending==6 and state.snapshot.busy, 'force refresh immediately queries all providers after a completed scan')
assert(pending[4].provider=='system' and pending[5].provider=='logitech' and pending[6].provider=='eightbitdo')
env.onIpc('force-refresh');env.update()
assert(#pending==6, 'repeated force refresh cannot overlap in-flight queries')
print('Service checks passed: scheduling, timeouts, migration, multi-selection, desktop behavior and immediate refresh')
