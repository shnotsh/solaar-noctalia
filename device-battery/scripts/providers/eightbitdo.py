"""Ultimate 2 Wireless status query; no mode switches or configuration writes.

Protocol reference: MiguelSanzBr/8bitdo-ultimate2-linux (MIT), revision
03957a0c165b214a501337279149144e36764af3, Device.pad_status().
See THIRD_PARTY_NOTICES.md for attribution.
"""
import os
from pathlib import Path
import select
import time
from .common import deadline, read, record

QUERY = bytes.fromhex('81 04 21 01 00 00 06').ljust(64, b'\0')
PREFIX = bytes.fromhex('02 04 04 00 21 01')
PIDS = {0x310B, 0x6012, 0x6013}


def parse_reply(reply):
    if not reply.startswith(PREFIX) or len(reply) < 24:
        return None
    size = int.from_bytes(reply[6:8], 'little')
    if size < 6 or 18 + size > len(reply) or reply[18] > 100:
        return None
    return reply[18]


def discover(sys=Path('/sys'), dev=Path('/dev')):
    for p in sorted((sys/'class/hidraw').glob('hidraw*')):
        values = dict(line.split('=', 1) for line in read(p/'device/uevent').splitlines() if '=' in line)
        try:
            bus, vendor, product = (int(v, 16) for v in values.get('HID_ID', '').split(':'))
        except ValueError:
            continue
        if bus != 3 or vendor != 0x2DC8 or product not in PIDS:
            continue
        descriptor = (p/'device/report_descriptor').read_bytes()
        if not descriptor.startswith((b'\x06\x7a\xff', b'\x06\xa0\xff')) or b'\x85\x81' not in descriptor:
            continue
        usb = (p/'device').resolve().parent.parent
        # Only the gamepad interface is a valid keepalive; keyboard/mouse events are not.
        node = next((dev/'input'/n.name for n in (sys/'class/input').glob('js*')
                     if (n/'device').resolve().is_relative_to(usb)), None)
        serial = values.get('HID_UNIQ') or read(usb/'serial')
        if not serial:
            serial = 'port:' + usb.name  # explicit topology fallback, never hidraw numbering
        yield dev/p.name, node, serial


def query(path, input_node):
    if input_node is None:
        raise RuntimeError('No gamepad input: controller asleep/disconnected, or xpad unavailable')
    keepalive = os.open(input_node, os.O_RDONLY | os.O_NONBLOCK)
    try:
        fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        try:
            until = time.monotonic() + .1
            while time.monotonic() < until and select.select([fd], [], [], .01)[0]:
                os.read(fd, 64)
            if os.write(fd, QUERY) != len(QUERY):
                raise OSError('Incomplete battery request')
            until = time.monotonic() + .75
            while time.monotonic() < until:
                if select.select([fd], [], [], min(.1, until - time.monotonic()))[0]:
                    value = parse_reply(os.read(fd, 64))
                    if value is not None:
                        return value
            raise TimeoutError('Controller asleep, disconnected, or not answering')
        finally:
            os.close(fd)
    finally:
        os.close(keepalive)


def scan():
    rows, errors = [], []
    for path, node, serial in discover():
        row = record('8bitdo:usb:' + serial.lower(), '8BitDo Ultimate 2', 'gamepad', 'eightbitdo',
                     source='8BitDo HID', transport='2.4 GHz')
        try:
            with deadline(3):
                row['percent'] = query(path, node)
        except Exception as exc:
            row.update(online=False, observed_at=0, error=str(exc)[:180])
            errors.append({'device_id': row['id'], 'message': '8BitDo: ' + str(exc)[:180]})
        rows.append(row)
    return rows, errors
