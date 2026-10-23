#!/usr/bin/env python3
"""Register this local checkout and add one battery widget, preserving other settings."""
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tomllib
import time

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = 'sh/device-battery'
SOURCE = 'device-battery'


def source_registration(sources):
    # Reuse an existing registration, including the original local-source name.
    for name in (SOURCE, 'device-battery-dev'):
        matching = [line for line in sources.splitlines() if line.startswith(name + ' ')]
        if matching:
            if matching[0].strip() != name + ' path ' + str(ROOT):
                raise RuntimeError(f'Source name {name} already points elsewhere')
            return name, True
    return SOURCE, False


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def edit_bar(text):
    data = tomllib.loads(text)
    bar = data.get('bar', {}).get('default', {})
    members = list(bar.get('end', []))
    name = 'device_battery'
    existing = data.get('widget', {}).get(name)
    if existing and existing.get('type') != PLUGIN + ':battery':
        raise RuntimeError('The device_battery widget name is already used by another widget')
    if name not in members:
        index = members.index('network') if 'network' in members else len(members)
        members.insert(index, name)
    match = re.search(r'^\[bar\.default\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if not match:
        raise RuntimeError('No [bar.default] section; choose a bar explicitly before installing')
    body = match.group(1)
    value = 'end = ' + json.dumps(members)
    if re.search(r'^end\s*=.*$', body, re.M):
        body = re.sub(r'^end\s*=.*$', lambda _: value, body, count=1, flags=re.M)
    else:
        body = value + '\n' + body
    updated = text[:match.start(1)] + body + text[match.end(1):]
    if existing is None:
        updated += '\n[widget.device_battery]\ntype = "sh/device-battery:battery"\n'
    tomllib.loads(updated)
    return updated


def main():
    print(run('noctalia', 'plugins', 'lint', str(ROOT/'device-battery')).strip())
    sources = run('noctalia', 'msg', 'plugins', 'source', 'list')
    name, registered = source_registration(sources)
    if not registered:
        print(run('noctalia', 'msg', 'plugins', 'source', 'add', name, 'path', str(ROOT)).strip())
    print(run('noctalia', 'msg', 'plugins', 'enable', PLUGIN).strip())
    state = Path(os.environ.get('NOCTALIA_STATE_HOME', os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))))/'noctalia'
    settings = state/'settings.toml'
    # Enabling a plugin exports in the background. Wait for its persisted state.
    for _ in range(100):
        if settings.exists() and PLUGIN in tomllib.loads(settings.read_text()).get('plugins', {}).get('enabled', []):
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Noctalia did not finish enabling the plugin within ten seconds')
    original = settings.read_text()
    if 'default' not in tomllib.loads(original).get('bar', {}):
        effective = tomllib.loads(run('noctalia', 'config', 'export', 'merged'))
        members = effective.get('bar', {}).get('default', {}).get('end')
        if members is None:
            raise RuntimeError('Configure a default bar before installing the widget')
        base = original + '\n[bar.default]\nend = ' + json.dumps(members) + '\n'
    else:
        base = original
    updated = edit_bar(base)
    if original != updated:
        backup = settings.with_name('settings.toml.before-device-battery-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
        shutil.copy2(settings, backup)
        if settings.read_text() != original:
            raise RuntimeError('Settings changed during installation; retry')
        temporary = settings.with_name('settings.toml.device-battery-tmp')
        temporary.write_text(updated)
        temporary.replace(settings)
        print('Settings backup:', backup)
    print(run('noctalia', 'config', 'validate').strip())
    print(run('noctalia', 'msg', 'config-reload').strip())
    print('Installed Device Battery before the network widget.')


if __name__ == '__main__': main()
