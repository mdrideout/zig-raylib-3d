# Zig 3D Game Engine Example

A super light and basic 3D game engine built with Zig, Raylib, and Jolt Physics. 

This repo is meant to demonstrate the basics of tool programming and gizmos needed to build a 3D game scene with a camera, lighting, physics, basic character controls, and most importantly, **a debug menu**.

Opinionated organization and architecture:

- DoD: Data-Oriented Design
- SoA: Structured-Of-Arrays
- VSA: Vertical Slice Architecture

## Requirements

- Zig 0.15.2 or later
- [Install zig](https://ziglang.org/learn/getting-started/#managers)
- [MacOS Zig Homebrew](https://formulae.brew.sh/formula/zig)

## Building

```bash
zig build
```

## Running

```bash
zig build run
```

## Controls

- **1** - Free camera mode
- **2** - Character camera mode
- **ESC** - Release mouse control
- **F3** - Toggle debug menu (fn + F3 on mac)
- **W/S** - Move forward/backward
- **A/D** - Strafe left/right
- **E/Q** - Move up/down
- **Mouse** - Look around

## Dependencies

- [raylib-zig](https://github.com/raylib-zig/raylib-zig) - Zig bindings for Raylib
- [zphysics](https://github.com/zig-gamedev/zphysics) - Zig bindings for Jolt Physics

Reference [zig-gamedev](https://github.com/zig-gamedev) for more information on the ecosystem and zig game development needs.

## Architecture

This project follows opinionated architectural patterns:

- **Data-Oriented Design** - Entities stored in cache-friendly arrays, explicit data flow
- **Structure of Arrays (SoA)** - All collections use `std.MultiArrayList` for consistency
- **Vertical Slice Architecture** - Features co-locate code, shaders, and assets together
- **Zig-idiomatic** - Explicit control, pure Zig libraries preferred, no hidden state

[AGENTS.md](AGENTS.md) contains more details about the design decisions for vibe coding consistency.

## Game Loop Architecture

This engine implements **The Canonical Game Loop** (also known as "Fixed Timestep with Interpolation"), the same architecture used by Unity, Unreal Engine, and Godot.

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: INPUT PUMP (Per-Frame / Uncapped)                  │
│ - Drains OS events, latches actions to the Input Buffer.    │
├─────────────────────────────────────────────────────────────┤
│ Phase 2: SIMULATION TICK (Fixed 120Hz)                      │
│ - The "Authority." Runs physics, gameplay logic, & consume. │
├─────────────────────────────────────────────────────────────┤
│ Phase 3: PRESENTATION (Interpolated)                        │
│ - Renders the "Visual State" blended between two ticks.     │
└─────────────────────────────────────────────────────────────┘
```

**Why this pattern?**
- **Deterministic physics** - Same behavior at 30 FPS or 144 FPS
- **Input Latching Strategy** - Designed to capture inputs between frames (though currently limited by Raylib's polling implementation).
- **Smooth visuals** - Interpolation eliminates stutter between physics ticks

See [INPUT_SYSTEM_PLAN.md](INPUT_SYSTEM_PLAN.md) for detailed implementation documentation.

## Debug UI ([zgui](https://github.com/zig-gamedev/zgui) + [rlImGui](https://github.com/raylib-extras/rlImGui))

The debug overlay uses **Dear ImGui** via a dual-library setup:

| Library | Role |
|---------|------|
| **rlImGui** | Creates ImGui context, Raylib rendering backend, input forwarding |
| **zgui** | Idiomatic Zig API for widgets (buttons, sliders, windows) |

**How it works:** ImGui uses a global context internally. rlImGui creates it, zgui attaches to it via `initNoContext()`. Both libraries then operate on the same context - rlImGui handles rendering, zgui provides the Zig API.

```
rlImGuiSetup()        → Creates ImGui context
zgui.initNoContext()  → Attaches to existing context (doesn't create new one)
rlImGuiBegin/End()    → Frame lifecycle + Raylib rendering
zgui.button(), etc.   → Widget calls to shared context
```

Press **F3** to toggle the debug overlay. See [AGENTS.md](AGENTS.md#debug-ui-architecture-zgui--rlimgui) for full architecture details.

## Known Issues

_As of Dec 1, 2025_

**Mouse click detection & Raylib Ceiling** Raylib's core API abstracts input into a polling model (`IsMouseButtonPressed`). While the underlying GLFW library supports event callbacks, Raylib consumes them internally to update its global state.

This creates a hard architectural ceiling:

*   **Frame-Perfect Clicks**: Fast press/release events occurring between two poll calls can be overwritten before the user code sees them.
*   **OS Blocking**: On macOS, window interactions (moving, resizing, or Magnet window snapping) pause the main thread. Since Raylib polls input on the main thread, the game effectively goes "blind" during these pauses, dropping inputs entirely.
    *   Some window managers like Magnet cause significant delays (100s of ms) by just running in the background. (see github issues below)

**Current Status**: Input latching was attempted in `src/input/mod.zig`, but cannot overcome the main-thread blocking inherent to the Raylib/macOS interaction. For high click accuracy that is consistent in any environment (such as distributing a game), you cannot ask users to close their window managers, making this a hard ceiling on Raylib's viability for input-sensitive applications.

**Alternatives**: 

* [SDL3](https://wiki.libsdl.org/SDL3/SDL_Event) uses an event queue where each click generates exactly one `SDL_MOUSEBUTTONDOWN` and one `SDL_MOUSEBUTTONUP` event - 1 click = 1 event, guaranteed.
* [sokol_app](https://github.com/floooh/sokol/issues/293) uses OS-pushed event callbacks rather than polling, though building a polling API on top requires extra work.

**Related GitHub Issues:**
*   [GLFW #1665](https://github.com/glfw/glfw/issues/1665) (MacOS click delays caused by Magnet window manager)
*   [Raylib #4749](https://github.com/raysan5/raylib/issues/4749)
*   [Raylib #3354](https://github.com/raysan5/raylib/issues/3354)