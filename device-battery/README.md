# Device Battery

Show laptop, Logitech, and 8BitDo controller batteries in your Noctalia bar.

- **Left-click:** open the device list and toggle which devices appear in the bar.
- **Middle-click:** open polling and appearance settings.
- **Right-click:** refresh all device statuses immediately.

Multiple selections are remembered across restarts. Offline devices retain their last reading or can be hidden until they reconnect.

Requires Noctalia plugin API 31+ and Python 3.11+. Logitech support requires Solaar; UPower and Bluetooth integration use the Python D-Bus bindings. The 8BitDo Ultimate 2 Wireless dongle requires access to its HID and gamepad devices.

See the [repository README](../README.md) for installation, compatibility, settings, and troubleshooting.

Licensed under [MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for protocol attribution.
