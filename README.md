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
