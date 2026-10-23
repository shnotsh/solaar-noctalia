"""System battery and standard 8BitDo Bluetooth battery interfaces."""
from pathlib import Path
from .common import percentage, read, record

STATES = {1: "charging", 2: "discharging", 3: "empty", 4: "full", 5: "charging", 6: "discharging"}


def sysfs_laptop(root=Path('/sys/class/power_supply')):
    batteries = []
    for p in sorted(root.glob('*')):
        if read(p/'type') != 'Battery' or read(p/'scope') == 'Device':
            continue
        if p.name.startswith(('hid', 'xpad')) or read(p/'present', '1') != '1':
            continue
        cap = percentage(read(p/'capacity'))
        if cap is not None:
            batteries.append((p, cap))
    if not batteries:
        return None
    if len(batteries) == 1:
        p, cap = batteries[0]
    else:
        energy = []
        for p, _ in batteries:
            try:
                energy.append((float(read(p/'energy_now')), float(read(p/'energy_full'))))
            except ValueError:
                # Don't average percentages of batteries with different capacities.
                raise RuntimeError('UPower is unavailable and combined battery energy is unknown')
        full = sum(e[1] for e in energy)
        cap = percentage(100 * sum(e[0] for e in energy) / full) if full > 0 else None
    row = record('system', 'Laptop battery', 'laptop', 'system', cap, source='sysfs', transport='internal')
    states = [read(p/'status').lower() for p, _ in batteries]
    row['state'] = 'charging' if 'charging' in states else ('full' if all(s == 'full' for s in states) else states[0])
    return row


def scan():
    rows, errors, bus = [], [], None
    try:
        import dbus
        bus = dbus.SystemBus()
        props = dbus.Interface(bus.get_object('org.freedesktop.UPower', '/org/freedesktop/UPower/devices/DisplayDevice'),
                               'org.freedesktop.DBus.Properties').GetAll('org.freedesktop.UPower.Device', timeout=2)
        if props.get('IsPresent') and int(props.get('Type', 0)) == 2:
            row = record('system', 'Laptop battery', 'laptop', 'system', props.get('Percentage'),
                         source='UPower', transport='internal')
            row['state'] = STATES.get(int(props.get('State', 0)), 'unknown')
            rows.append(row)
    except Exception:
        pass
    if not rows:
        row = sysfs_laptop()
        if row:
            rows.append(row)
    # The kernel's HID battery works even when BlueZ does not expose Battery1.
    bluetooth_ids = set()
    for p in Path('/sys/class/power_supply').glob('hid-*-battery'):
        target = str((p/'device').resolve()).upper()
        if '0005:2DC8:' not in target:
            continue
        address = p.name[4:-8].lower()
        row = record('8bitdo:bt:' + address, read(p/'model_name', '8BitDo controller'), 'gamepad', 'system',
                     read(p/'capacity'), source='Linux HID', transport='Bluetooth')
        row['state'] = read(p/'status', 'unknown').lower()
        rows.append(row)
        bluetooth_ids.add(address)
    if bus is not None:
        try:
            import dbus
            objects = dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager').GetManagedObjects(timeout=2)
            for interfaces in objects.values():
                dev = interfaces.get('org.bluez.Device1', {})
                bat = interfaces.get('org.bluez.Battery1', {})
                name = str(dev.get('Name', dev.get('Alias', '')))
                if not dev.get('Connected') or not ('8bitdo' in name.lower() or 'v2dc8' in str(dev.get('Modalias', '')).lower()):
                    continue
                address = str(dev.get('Address', '')).lower()
                if not address or address in bluetooth_ids or 'Percentage' not in bat:
                    continue
                rows.append(record('8bitdo:bt:' + address, name, 'gamepad', 'system', bat['Percentage'],
                                   source='BlueZ', transport='Bluetooth'))
        except Exception:
            pass  # Bluetooth is optional; the laptop remains usable without BlueZ.
    return rows, errors
