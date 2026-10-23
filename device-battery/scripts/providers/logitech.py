"""Solaar 1.1.20 adapter. Never starts its GUI or applies device settings."""
from .common import deadline, record


def battery_fields(battery):
    from logitech_receiver.common import BatteryLevelApproximation, NamedInt
    if battery is None:
        return dict(percent=None, state='unknown')
    level = battery.level
    state = getattr(battery.status, 'name', 'unknown').lower()
    state = {'recharging': 'charging', 'slow_recharge': 'charging', 'almost_full': 'charging'}.get(state, state)
    if isinstance(level, (BatteryLevelApproximation, NamedInt)):
        label = getattr(level, 'name', str(level)).lower()
        return dict(percent=None, level=label, precision='qualitative', state=state)
    from .common import percentage
    return dict(percent=percentage(level), state=state)


def scan():
    from solaar.cli import _receivers_and_devices
    from logitech_receiver.receiver import Receiver
    from logitech_receiver.device import CenturionReceiver
    from logitech_receiver.hidpp10 import Hidpp10
    from logitech_receiver.hidpp20 import Hidpp20
    roots, rows, errors, seen = [], [], [], set()
    try:
        for root in _receivers_and_devices():
            roots.append(root)
            devices = iter(root) if isinstance(root, (Receiver, CenturionReceiver)) else iter([root])
            try:
                for dev in devices:
                    try:
                        with deadline(4):
                            if not dev.ping():
                                continue  # Preserve known offline devices in the service cache, not anonymous slots.
                            uid = dev.unitId or dev.serial
                            receiver = getattr(dev, 'receiver', None)
                            if not uid and receiver:
                                uid = str(receiver.serial) + ':slot:' + str(dev.number)
                            if not uid:
                                errors.append('A Logitech device has no stable identity')
                                continue
                            identity = 'logitech:' + str(uid).lower()
                            if identity in seen:
                                continue
                            if dev.protocol < 2:
                                battery = Hidpp10().get_battery(dev)
                            else:
                                result = Hidpp20().get_battery(dev, None)
                                battery = result[1] if isinstance(result, tuple) and len(result) == 2 else None
                            row = record(identity, dev.name, str(dev.kind), 'logitech', source='Solaar',
                                         transport='Wireless' if receiver else 'USB / Bluetooth')
                            row.update(battery_fields(battery))
                            rows.append(row)
                            seen.add(identity)
                    except Exception as exc:
                        errors.append(type(exc).__name__ + ': ' + str(exc)[:180])
            except Exception as exc:
                errors.append(type(exc).__name__ + ': ' + str(exc)[:180])
    finally:
        for root in roots:
            try:
                root.close()
            except Exception:
                pass
    return rows, errors
