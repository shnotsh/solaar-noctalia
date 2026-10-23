# Device Battery for Noctalia

Laptop, Logitech, and 8BitDo controller batteries together in your Noctalia bar. Choose one or several devices, see their charge at a glance, and open the dropdown for details.

## Features

- Multiple devices in the bar, with selections remembered across restarts.
- Automatic battery or device icons, optional percentages, and adjustable spacing.
- Last-known readings for offline devices, or automatic hiding until they reconnect.
- Configurable peripheral polling and an immediate refresh shortcut.
- Support for horizontal and vertical bars, including desktops without a laptop battery.

## Supported devices

| Device | Battery source | Support |
| --- | --- | --- |
| Laptop battery | UPower, with a Linux power-supply fallback | Multiple internal batteries are combined when capacity data is available. |
| Logitech peripherals | Solaar | Battery reporting depends on Solaar and the device. Verified with the PRO X 2 mouse and G325 LIGHTSPEED headset. |
| 8BitDo Ultimate 2 Wireless, 2.4 GHz dongle | USB HID status query | Battery percentage supported. Charging state is unavailable through this query. |
| 8BitDo controllers over Bluetooth | Linux HID or BlueZ | Requires the controller to expose battery information. |

Other 8BitDo dongles and models are not assumed compatible. Some devices report a qualitative level such as “Good” instead of a percentage; the widget displays that level without inventing a number.

## Requirements

- Linux with Noctalia plugin API **31 or newer**; tested with Noctalia 5.3.0.
- **Python 3.11+**, available as `python3`.
- **Solaar** for Logitech devices. The adapter is tested with Solaar 1.1.20; its Python modules must be available to the system Python.
- **UPower** and Python D-Bus bindings (`dbus-python`, often packaged as `python-dbus` or `python3-dbus`) for UPower and BlueZ integration. The Linux power-supply fallback can work without D-Bus.
- Permission to access the relevant HID devices. The Ultimate 2 dongle also needs a working gamepad driver and an accessible joystick input device.

Install dependencies through your distribution. The Solaar GUI does not need to be running.

## Installation

With Noctalia running, clone the repository into a permanent location and run the installer:

```sh
git clone https://github.com/shnotsh/solaar-noctalia.git
cd solaar-noctalia
python3 scripts/install.py
```

The installer registers this folder as a local plugin source, enables **Device Battery**, and adds it to the default bar before the network widget, or at the end if there is no network widget. It backs up settings before changing the bar and can be run again without adding a duplicate widget.

Keep the repository folder in place: Noctalia loads the plugin from it. Run the installer as your regular desktop user.

For a setup without a default bar, register and enable the plugin manually from the repository folder:

```sh
noctalia msg plugins source add device-battery path "$PWD"
noctalia msg plugins enable sh/device-battery
```

Then add **Device Battery** to your preferred bar in Noctalia settings.

## Usage

| Action | Result |
| --- | --- |
| Left-click | Open the device dropdown. |
| Click a device row | Toggle that device in the bar. |
| Middle-click | Open this widget’s bar settings. |
| Right-click | Refresh all device statuses immediately. |
| Hover | Show names, charge levels, and status. |

Selected devices appear in selection order. The laptop is selected initially; on a desktop, the first available peripheral is selected instead. Selections are shared across instances of this plugin.

An unavailable reading is shown as `—` in the bar and marked as last known in the dropdown. Turning off **Show offline devices** hides unavailable entries from both views without clearing their selections. They return automatically when a fresh reading arrives. A small devices icon remains clickable if no entries are visible.

## Settings

Middle-click the widget, or open its entry in **Noctalia Settings → Bar**.

| Setting | Default | Options |
| --- | --- | --- |
| Peripheral polling interval | 60 seconds | 30–600 seconds |
| Low battery color threshold | 20% | 0–50% |
| Show percentage in the bar | On | On / off |
| Spacing between devices | 12 px | 0–48 px |
| Bar icon style | Automatic | Automatic / battery level / device type |
| Show offline devices | On | On / off |
| Show charge bars in the dropdown | On | On / off |

Automatic icon style uses a battery icon for one selection and device icons for multiple selections. Noctalia’s standard controls also provide widget colors, scale, fonts, and other presentation options.

The laptop refreshes every 30 seconds. If several widget instances use different polling intervals, the shared readers use the shortest interval. Right-click refreshes immediately; a provider query already in progress is allowed to finish.

### Link Bluetooth and dongle entries

The same controller can have different Bluetooth and USB identities. To show it as one device when switching connections:

1. Connect it through each mode and obtain the device IDs using the diagnostic command below.
2. Open **Device Battery** in Noctalia’s plugin settings and find the advanced **Device identity aliases** setting.
3. Map each alternate ID to one chosen ID for that physical device.

Only link IDs you know belong to the same device. Matching model names alone are not enough. The widget preserves selection across linked transports and avoids duplicate entries.

## Troubleshooting

**A device is missing or unavailable**

Power it on, check its connection, and right-click the widget. Enable **Show offline devices** to see cached entries. If a Logitech device is missing, check that Solaar can detect it and that its Python modules are installed for `python3`.

**The 8BitDo dongle has no reading**

Confirm that the controller is awake and connected in 2.4 GHz mode, that Linux recognizes its gamepad interface, and that your user can access its HID and joystick devices. Check your distribution’s device permissions and gamepad driver setup. Do not run Noctalia as root. The controller’s Bluetooth and dongle support can differ by model and firmware.

**Inspect battery data**

```sh
noctalia msg plugin sh/device-battery:service all dump
```

This writes `snapshot.json` in the plugin’s data directory, normally `~/.local/state/noctalia/plugins/data/sh/device-battery/`. It includes device IDs, readings, and errors. If you use a custom Noctalia state directory, look there instead.

For a provider-specific check, run from this repository:

```sh
python3 device-battery/scripts/battery_helper.py --provider system
python3 device-battery/scripts/battery_helper.py --provider logitech
python3 device-battery/scripts/battery_helper.py --provider eightbitdo
```

When opening a GitHub issue, include your Noctalia and Solaar versions, Linux distribution, device model, connection mode, and relevant errors. Remove Bluetooth addresses and device serials from any output you share.

## Updating and removal

To update a cloned installation, pull the latest changes in the repository folder, then reload Noctalia’s configuration:

```sh
git pull --ff-only
noctalia msg config-reload
```

To remove the widget, remove it from your bar and disable **Device Battery** in Noctalia’s plugin settings. Remove its local source in the plugin source settings before deleting the repository folder. Saved selections and cached readings can be removed separately from the plugin data directory.

## License

[MIT](LICENSE). The 8BitDo protocol attribution and accompanying license are included in [third-party notices](device-battery/THIRD_PARTY_NOTICES.md).
