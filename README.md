# Polybar Mac

A native AppKit status bar for macOS, designed for AeroSpace. It uses a borderless non-activating `NSPanel`, CoreGraphics text drawing, a small TOML configuration reader, and a Unix datagram socket for AeroSpace event callbacks.

## Build

Requires macOS 13+ and Swift 6.

```sh
make build
```

The executable is `.build/debug/polybar-mac`. Copy `config/config.toml` to `~/.config/polybar-mac/config.toml`, replace the example socket path with your home path, then run the executable. `XDG_CONFIG_HOME` is also supported.

## AeroSpace events

See `aerospace.toml.example`; merge the hook into your AeroSpace config and reload AeroSpace. Workspace pills invoke `aerospace workspace <name>`. The bar refreshes workspaces on hook events and reads the focused window title during refresh.

The implementation is intentionally compact. `music` and `wifi` currently render no playback/network metadata; those modules are extension points. CPU/RAM and battery are sampled with native system APIs, and the clock redraws once a second.
