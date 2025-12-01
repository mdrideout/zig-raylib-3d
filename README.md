# Zig 3D Game Engine Example

A super light and basic 3D game engine built with Zig, Raylib, and Jolt Physics. 

This repo is meant to demonstrate the basics of tool programming and gizmos needed to build a 3D game scene with a camera, lighting, shadows, physics, basic character controls, and most importantly, **a debug menu**.

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

- **Click** - Click the window to capture mouse for camera control
- **ESC** - Release mouse control
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
- **No missed inputs** - Latching ensures every click/keypress is captured
- **Smooth visuals** - Interpolation eliminates stutter between physics ticks

See [INPUT_SYSTEM_PLAN.md](INPUT_SYSTEM_PLAN.md) for detailed implementation documentation.
