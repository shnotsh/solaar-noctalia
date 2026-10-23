import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'device-battery/scripts'))
from providers.common import percentage
from providers.eightbitdo import parse_reply, discover
from providers.system import sysfs_laptop


class BatteryTests(unittest.TestCase):
    def test_real_dongle_response(self):
        raw = bytes.fromhex('0204040021010600000000000000000000003d6e00000001').ljust(64, b'\0')
        self.assertEqual(parse_reply(raw), 61)
        self.assertEqual(parse_reply(raw[:18] + b'\0' + raw[19:]), 0)

    def test_dongle_rejects_malformed_or_unrelated_reports(self):
        raw = bytes.fromhex('0204040021010600000000000000000000003d6e00000001').ljust(64, b'\0')
        for bad in [b'', raw[:20], b'\x03'+raw[1:], raw[:6]+b'\xff\xff'+raw[8:],
                    raw[:6]+b'\x01\0'+raw[8:], raw[:18]+b'\xff'+raw[19:]]:
            self.assertIsNone(parse_reply(bad))

    def test_invalid_percentages_are_unknown_not_zero(self):
        for v in [None, '', 'unknown', -1, 101, float('nan'), float('inf')]:
            self.assertIsNone(percentage(v))
        self.assertEqual(percentage(0), 0)
        self.assertEqual(percentage('61'), 61)

    def test_laptop_fallback_excludes_peripherals_and_absent_batteries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def battery(name, **attrs):
                p = root/name
                p.mkdir()
                for k, v in dict(type='Battery', **attrs).items(): (p/k).write_text(str(v))
            battery('BAT1', capacity=73, status='Discharging', present=1)
            battery('hidpp_battery_0', capacity=99)
            battery('other', capacity=12, scope='Device')
            battery('BAT2', capacity=10, present=0)
            row = sysfs_laptop(root)
            self.assertEqual((row['percent'], row['state']), (73, 'discharging'))

    def test_multiple_batteries_use_energy_weighting(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, cap, energy, full in [('BAT0', 50, 10, 20), ('BAT1', 100, 60, 60)]:
                p = root/name; p.mkdir()
                for key, value in dict(type='Battery', capacity=cap, energy_now=energy, energy_full=full, status='Discharging').items():
                    (p/key).write_text(str(value))
            self.assertEqual(sysfs_laptop(root)['percent'], 88)
            (root/'BAT1/energy_full').unlink()
            with self.assertRaises(RuntimeError): sysfs_laptop(root)

    @unittest.skipUnless(importlib.util.find_spec('solaar'), 'System Solaar not installed')
    def test_solaar_qualitative_levels_remain_qualitative(self):
        from providers.logitech import battery_fields
        from logitech_receiver.common import Battery, BatteryLevelApproximation, BatteryStatus
        row = battery_fields(Battery(BatteryLevelApproximation.GOOD, None, BatteryStatus.DISCHARGING, None))
        self.assertIsNone(row['percent'])
        self.assertEqual(row['level'], 'good')
        self.assertEqual(row['precision'], 'qualitative')
        self.assertEqual(battery_fields(Battery(0, None, BatteryStatus.DISCHARGING, None))['percent'], 0)


if __name__ == '__main__': unittest.main()
