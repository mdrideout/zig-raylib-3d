# Zig 3D Game Demo

A 3D game built with Zig and Raylib. This repo demonstrates:

- Opinionated organization and architecture (DoD, SoA, VSA)
- Zig idioms (explicit control, pure libraries)
- Raylib and Jolt Physics
  - Falling blocks
  - Collisions with ground
  - Collisions with other blocks
  - Lighting: 
    - Directional light
    - Point light (orbital animation)

## Requirements

- Zig 0.15.2 or later

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

## Testing

```bash
zig build test
```

## Dependencies

- [raylib-zig](https://github.com/raylib-zig/raylib-zig) - Zig bindings for Raylib
- [zphysics](https://github.com/zig-gamedev/zphysics) - Zig bindings for Jolt Physics

## Architecture

This project follows opinionated architectural patterns:

- **Data-Oriented Design** - Entities stored in cache-friendly arrays, explicit data flow
- **Structure of Arrays (SoA)** - All collections use `std.MultiArrayList` for consistency
- **Vertical Slice Architecture** - Features co-locate code, shaders, and assets together
- **Zig-idiomatic** - Explicit control, pure Zig libraries preferred, no hidden state

[AGENTS.md](AGENTS.md) contains more details about the design decisions for vibe coding consistency.
