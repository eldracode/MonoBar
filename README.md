# MonoBar

A native AppKit status bar for macOS, designed for AeroSpace. It uses a borderless non-activating `NSPanel`, CoreGraphics text drawing, a small TOML configuration reader, and a Unix datagram socket for AeroSpace event callbacks.

## Build

Requires macOS 13+ and Swift 6.

Bluetooth toggling uses [`blueutil`](https://github.com/toy/blueutil); install it with `brew install blueutil`.

Weather uses the OpenWeather current weather API. Add your API key under `[weather]` in `~/.config/monobar/config.toml`. MonoBar uses current location when latitude and longitude are omitted, or you can set both coordinates to avoid location lookup. Choose `metric`, `imperial`, or `standard` units.

```sh
make build
```

The executable is `.build/debug/monobar`. Copy `config/config.toml` to `~/.config/monobar/config.toml`, replace the example socket path with your home path, then run the executable. `XDG_CONFIG_HOME` is also supported. Existing `polybar-mac` configuration files are still read as a fallback.

## AeroSpace events

See `aerospace.toml.example`; merge the hook into your AeroSpace config and reload AeroSpace. Workspace pills invoke `aerospace workspace <name>`. The bar refreshes workspaces on hook events and reads the focused window title during refresh.

The implementation is intentionally compact. `music` remains an extension point. Wi-Fi, Bluetooth, and weather use native system APIs or the configured OpenWeather provider; CPU/RAM and battery use native system APIs.
