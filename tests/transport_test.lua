local model = dofile('device-battery/lib/model.luau')
local usb, cable, bt = '8bitdo:usb:receiver', '8bitdo:usb:controller', '8bitdo:bt:address'
local aliases = {[bt]=usb, [cable]=usb}
local cache, count = {}, 0
local function check(value, message) assert(value, message); count=count+1 end
local function device(id, percent, stamp)
  return {id=id, name='Same model name', online=true, observed_at=stamp, percent=percent}
end
local function view(stamp)
  local rows = model.rows(cache, usb, stamp, 60, aliases)
  check(#rows==1, 'exactly one physical controller must be visible')
  check(rows[1].id==usb, 'canonical selected identity must remain stable')
  return rows[1]
end
model.merge(cache,'eightbitdo',{device(usb,61,100), device(cable,73,90)},true,100)
model.merge(cache,'system',{device(bt,61,95)},true,100)
check(#model.rows(cache,usb,100,60)==3, 'unlinked identities remain distinct')
check(view(100).source_id==usb, 'adding aliases merges pre-existing cached duplicates immediately')
check(model.canonical(bt,aliases)==usb and model.canonical(cable,aliases)==usb, 'old selections migrate')
model.merge(cache,'eightbitdo',{},true,105)
model.merge(cache,'system',{device(bt,60,106)},true,106)
check(view(106).source_id==bt and not view(106).stale, 'switch to Bluetooth uses fresh Bluetooth observation')
model.merge(cache,'eightbitdo',{{id=usb,name='Receiver',online=false,observed_at=0}},true,107)
check(view(107).source_id==bt, 'disconnected receiver cannot displace current Bluetooth')
model.merge(cache,'eightbitdo',{device(usb,59,110)},true,110)
check(view(110).percent==59, 'switch back uses fresh dongle reading')
model.merge(cache,'system',{},true,111)
check(not view(111).stale, 'late Bluetooth disappearance cannot invalidate dongle')
model.merge(cache,'system',{device(bt,58,112)},true,112)
model.merge(cache,'system',{},false,113)
check(view(113).source_id==usb and not view(113).stale, 'failed newer transport falls back to still-current other transport')
model.merge(cache,'eightbitdo',{},true,114)
local off=view(114)
check(off.stale and off.percent==58 and model.level(off,true)=='—', 'all offline retains latest actual observation marked stale')
local restored=model.restore(model.persist(cache,usb,114,aliases))
check(restored[usb] and restored[cable] and restored[bt], 'restart preserves individual transport records')
check(#model.rows(restored,usb,114,60,aliases)==1, 'restart does not resurrect duplicate rows')
check(#model.rows(restored,usb,114,60,{})==3, 'removing an alias restores separate identities')
model.merge(cache,'eightbitdo',{device(usb,57,120),device('another-controller',99,120)},true,120)
check(#model.rows(cache,usb,120,60,aliases)==2, 'same name alone never merges different physical controllers')
check(model.canonical(bt,{[bt]=cable,[cable]=usb})==usb, 'alias chains resolve')
check(model.canonical(bt,{[bt]=cable,[cable]=bt})==bt, 'alias cycles do not collapse identities')
local diagnostic={{device_id=usb,message='Controller not answering on dongle'}}
check(#model.visibleErrors(diagnostic,{{id=usb,online=true,stale=false,source_id=bt}},aliases)==0, 'inactive linked dongle does not show a false controller warning during Bluetooth use')
check(#model.visibleErrors(diagnostic,{{id=usb,online=false,stale=true}},aliases)==1, 'device error stays visible when all its transports are unavailable')
check(#model.visibleErrors(diagnostic,{{id='another-controller',online=true,stale=false}},aliases)==1, 'unrelated active controller never hides an error')
print('Transport checks passed: '..count)
