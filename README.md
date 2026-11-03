# MonoBar

A native AppKit status bar for macOS, designed for AeroSpace. It uses a borderless non-activating `NSPanel`, CoreGraphics text drawing, a small TOML configuration reader, and a Unix datagram socket for AeroSpace event callbacks.

## Build

Requires macOS 13+ and Swift 6.

Bluetooth toggling uses [`blueutil`](https://github.com/toy/blueutil); install it with `brew install blueutil`.

Weather uses the OpenWeather current weather API. Add your API key under `[weather]` in `~/.config/monobar/config.toml`. MonoBar uses current location when latitude and longitude are omitted, or you can set both coordinates to avoid location lookup. Choose `metric`, `imperial`, or `standard` units.

The `volume` and `mic` modules show the current output and input volume. Click either module to toggle mute, or scroll up and down over it to adjust that device's level.

Set `radius_top_left`, `radius_top_right`, `radius_bottom_right`, and `radius_bottom_left` in `[bar]` to configure each corner independently. Values are point radii and are clamped to half the bar's height or width.

Set `float = true` to keep the bar above normal app windows, or `false` to let windows cover it. `offset_top` moves the bar down from the top edge in points; the existing `offset_y` setting remains supported, and `offset_top` takes precedence when both are set.

`offset_side` sets an equal inset from the left and right edges in points. With `width = "100%"`, the bar fills the remaining width and stays centered. The existing `offset_x` remains available as an additional horizontal shift.

### For debug builds
```sh
make build
```
The executable is present at `.build/debug/monobar`. 

### For release builds
```sh
make install
```
The executable is present at  `"$HOME/Applications/MonoBar.app"` and can be launched by 

```sh
open -a "$HOME/Applications/MonoBar.app"
```
Copy `config/config.toml` to `~/.config/monobar/config.toml`, replace the example socket path with your home path, then run the executable. `XDG_CONFIG_HOME` is also supported. Existing `MonoBar` configuration files are still read as a fallback.

## AeroSpace events

See `aerospace.toml.example`; merge the hook into your AeroSpace config and reload AeroSpace. Workspace pills invoke `aerospace workspace <name>`. The bar refreshes workspaces on hook events and reads the focused window title during refresh.

The implementation is intentionally compact. `music` remains an extension point. Wi-Fi, Bluetooth, audio volume, and weather use native system APIs or the configured OpenWeather provider; CPU/RAM and battery use native system APIs.
