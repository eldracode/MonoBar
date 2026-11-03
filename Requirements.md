# MISSION & SPECIFICATION: Native, Ultra-Lightweight MonoBar for macOS & AeroSpace

You are an expert macOS systems and graphics engineer specializing in Rust, Swift/Cocoa, CoreGraphics, and tiling window managers. 

Build a standalone, minimal, ultra-performant, and battery-friendly desktop status bar for macOS (Apple Silicon native) inspired by Linux's `polybar`. It must integrate deeply and reactively with the `aerospace` tiling window manager without polling bottlenecks or Electron/web-view bloat.

---

### 1. Architectural & Performance Constraints
- **Language / Stack:** Rust (using `objc2` / `cocoa-rs` / `metal-rs` or `winit`) OR pure Swift/AppKit (raw `NSPanel` / `NSWindow` + `CoreGraphics` / `Metal`). **Do NOT use SwiftUI or Web/Electron frameworks.**
- **CPU & Memory Budget:** Target idle CPU < 0.2%, memory usage < 30 MB RSS.
- **Rendering:** Direct 2D rendering via CoreGraphics or lightweight Metal pipeline. No heavy layout engines.
- **Window Level & Layering:**
  - Create a borderless, non-activating floating panel using `NSPanel` (`styleMask: [.nonactivatingPanel, .borderless]`).
  - Window level must be set above standard applications but below system alert overlays (`level = .floating` or `.dock` / `.mainMenu`).
  - Screen space reservation: Calculate display bounds excluding the menu bar and dock, or configure it to sit cleanly at the top or bottom of the screen.
  - Exclude from macOS Mission Control and window lists (`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`).
  - Multi-monitor support: Span across or spawn independent instances per active `NSScreen`.

---

### 2. AeroSpace Window Manager Integration
- **Zero-Latency Event-Driven Updates:**
  - Do NOT poll `aerospace list-workspaces` in a tight loop.
  - Implement a Unix domain socket server / listener or a dedicated CLI event subscriber (e.g., parsing `aerospace list-workspaces --focused` or listening to `exec-on-workspace-change` callbacks registered in `aerospace.toml`).
  - Alternatively, monitor AeroSpace IPC via its CLI output stream or IPC socket if available.
- **Workspace Module:**
  - Distinct visual states: `active`, `visible-inactive`, `occupied`, `empty`, and `urgent`.
  - Clickable workspace pills: Clicking a workspace pill should execute `aerospace workspace <name>`.
  - Focused window title module: Display current focused window app name and title, updating on window focus change.

---

### 3. MonoBar Configuration (TOML or INI)
The application must parse a configuration file located at `~/.config/monobar/config.toml` (or standard XDG paths).
- **Bar Settings:**
  - `monitor`, `width`, `height`, `offset_x`, `offset_y`, `padding`, `module_margin`
  - Colors: HEX/RGBA format for `background`, `foreground`, `border`, `accent`
  - Fonts: Support primary text font + fallback glyph/symbol font (e.g., Nerd Fonts, SF Pro, FontAwesome) with baseline alignment.
- **Layout Definition:**
  - `modules-left = ["workspaces", "title"]`
  - `modules-center = ["music"]`
  - `modules-right = ["cpu", "ram", "battery", "volume", "mic", "wifi", "bluetooth", "weather", "clock"]`

---

### 4. Built-In Core Modules (Event-Driven & Polling)
Implement standard status bar modules with minimal syscall overhead:
1. **Workspaces (AeroSpace):** Live workspace buttons with click handlers.
2. **Window Title:** Active window/app name.
3. **Battery:** Native reading via `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` (register for I/O Kit sleep/wake/power state notifications instead of polling).
4. **Clock / Date:** High-efficiency timer scheduled on `RunLoop` synchronized to the top of each minute or second.
5. **System Stats (CPU & RAM):** Host statistics via `mach/host_info.h` (`HOST_VM_INFO64`, `host_cpu_load_info`) polling at configurable intervals (e.g., 2–5s).
6. **Weather:** Current local conditions and temperature through a configurable provider.
7. **Audio:** Output and microphone volume percentages, adjustable with vertical scrolling over each module.
7. **Custom Script Module (`custom/script`):**
   - Support `exec = "sh script.sh"`, `interval = N`, `tail = bool` (stream output line-by-line), `click-left = "command"`.

---

### 5. Implementation Roadmap Deliverables
Please structure the codebase cleanly:
1. **`src/main`:** App initialization, `NSApplication` runloop setup, panel spawning on screen bounds.
2. **`src/bar/window`:** Native window/panel configuration, layer setup, mouse event handling (hit-testing modules).
3. **`src/config`:** Parser and type definitions for bar layout, dimensions, colors, and typography.
4. **`src/modules/`:**
   - Trait / Protocol `Module` (`render(&self, ctx)`, `update(&mut self)`, `handle_click(&self, button)`).
   - Implementation of `workspaces` with AeroSpace IPC.
5. **`Makefile` or `Cargo.toml` / Xcode project:** Build script for instant compiling and binary output.
6. **Sample Configuration:** A complete `aerospace.toml` snippet showing required hooks, plus an initial `config.toml` that looks clean and modern.

Please start by outputting the project structure and drafting the core window/panel initialization and AeroSpace IPC bridge.
