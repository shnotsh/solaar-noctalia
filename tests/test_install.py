import importlib.util
from pathlib import Path
import tomllib
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1]/'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_new_source_uses_public_name(self):
        self.assertEqual(installer.source_registration(''), ('device-battery', False))

    def test_existing_source_is_reused(self):
        for name in ('device-battery', 'device-battery-dev'):
            self.assertEqual(installer.source_registration(f'{name} path {installer.ROOT}\n'), (name, True))

    def test_conflicting_source_path_is_rejected(self):
        for name in ('device-battery', 'device-battery-dev'):
            with self.assertRaises(RuntimeError):
                installer.source_registration(f'{name} path /another/checkout\n')

    def test_preserves_other_settings_and_is_idempotent(self):
        original = '# user comment\n[bar.default]\nend = ["tray", "network", "clock"]\nstart = ["launcher"]\n\n[theme]\nmode = "dark"\n'
        updated = installer.edit_bar(original)
        parsed = tomllib.loads(updated)
        self.assertEqual(parsed['bar']['default']['end'], ['tray', 'device_battery', 'network', 'clock'])
        self.assertEqual(parsed['bar']['default']['start'], ['launcher'])
        self.assertIn('# user comment', updated)
        self.assertEqual(parsed['theme'], {'mode': 'dark'})
        self.assertEqual(installer.edit_bar(updated), updated)

    def test_conflicting_widget_name_is_rejected(self):
        with self.assertRaises(RuntimeError):
            installer.edit_bar('[bar.default]\nend=[]\n[widget.device_battery]\ntype="other"\n')
