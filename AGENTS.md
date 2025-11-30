# Architecture & Code Opinions

This document captures architectural decisions and coding conventions for this project.

## Building & Testing

Use these commands which are pre-approved and don't require permission prompts:

```bash
# Build the project
zig build

# Run the game (use run_in_background: true to avoid blocking)
zig build run

# Run tests
zig build test
```

When running the game for testing, use the Bash tool with `run_in_background: true` parameter. This allows the game to run without blocking. **Always clean up after validating** by killing the background process:

```bash
pkill -f zig_3d_game
```

## Libraries

These are the libraries in use:

- [Zig](https://ziglang.org/)
- [Raylib](https://www.raylib.com/)
- [Raylib-zig](https://github.com/raylib-zig/raylib-zig)
- [zig-gamedev](https://github.com/zig-gamedev)

Ensure you check what we get for free in these libraries, especially raylib, before reinventing the wheel.

## Game Architecture

This is a Zig + Raylib + Jolt Physics based 3d game. Consider what is conventional in _modern_ game development, zig, and raylib specifically.

## Project Structure

```
src/
  main.zig              # Game loop, input, window/camera management
  math.zig              # Math utilities (randomRotation, etc.)
  entities/
    cube.zig            # Cube: definition + SoA storage (Cubes struct)
    ground.zig          # Ground: definition + spawn
  scene/
    mod.zig             # Scene lifecycle, owns entity storage
    renderer.zig        # Drawing logic (uses Raylib)
  physics/
    mod.zig             # Physics system wrapper (init/update/destroy)
    layers.zig          # Collision layer definitions
    filters.zig         # Collision filter callbacks
```

## Terminology

- **Entity** = A thing that can exist (cube, ground, player)
- **Scene** = What currently exists (spawned entities, their state)
- **Renderer** = How to draw entities (visual representation)
- **Physics** = Laws, forces, simulation rules (how things move)

## Separation of Concerns

### `entities/` - Thing definitions AND storage
- What a cube/ground/player IS (constants, shape, properties)
- SoA storage struct for instances (e.g., `Cubes` with parallel arrays)
- Spawn functions, physics sync

**Keeps the concept contained** - everything about "cube" in one file.

### `scene/` - Orchestration and rendering
- `mod.zig` - Owns entity storage instances, lifecycle (init/deinit)
- `renderer.zig` - Draws entities using Raylib

**Uses:** entity storage structs, physics for positions

### `physics/` - Low-level physics primitives
- Physics engine configuration
- Collision layer definitions
- Collision filter rules

**Does NOT know about:** game concepts like "ground", "player", "cubes"

### `main.zig` - Orchestration
- Initializes all systems
- Game loop (update physics → render scene)
- Input handling
- Window/camera management

## Data-Oriented Design (DoD)

This project follows Data-Oriented Design principles for performance and clarity.

### Why DoD?

- **Cache efficiency** - process data in contiguous arrays, not scattered objects
- **Explicit data flow** - no hidden state, functions transform data
- **Zig-idiomatic** - aligns with Zig's philosophy of explicit control

### SoA with `std.MultiArrayList`

Use `std.MultiArrayList` for Structure of Arrays storage. Define a struct for the data, and MultiArrayList stores each field as a separate contiguous array:

```zig
const CubeData = struct {
    position: [3]f32,
    rotation: [4]f32,
    body_id: zphy.BodyId,
};

pub const Cubes = struct {
    data: std.MultiArrayList(CubeData),
    // ...
};
```

**Accessing field slices:**
```zig
const slice = self.data.slice();
const positions = slice.items(.position);  // [][3]f32
const rotations = slice.items(.rotation);  // [][4]f32
```

**Appending (keeps arrays in sync):**
```zig
try self.data.append(allocator, .{
    .position = pos,
    .rotation = rot,
    .body_id = id,
});
```

### Adding New Entity Types

1. Create `entities/foo.zig` with:
   - Constants (SIZE, etc.)
   - `FooData` struct for instance data
   - `Foos` struct wrapping `MultiArrayList(FooData)`
   - Spawn functions, `syncFromPhysics()` if dynamic
2. Add `foos: foo.Foos` to `Scene` struct
3. Init/deinit in Scene, call sync in game loop
4. Add draw function in `renderer.zig`

### When to Consider ECS

Migrate to ECS (e.g., `zig-ecs`) when:
- Entities need runtime composition (add/remove components dynamically)
- Complex queries needed ("all entities with Health but not Shield")
- Entity count grows to 1000+ with varied behaviors

## Zig Conventions

1. **Prefer pure Zig** - choose pure Zig libraries over C/C++ bindings when available
2. **Use `std.MultiArrayList`** - idiomatic Zig SoA, keeps parallel arrays in sync
3. **Use library types directly** - e.g., `zphy.MotionType` instead of wrapping it
4. **Flat structure** - avoid deep folder nesting unless clearly needed
5. **Colocate related code** - keep types near their usage, not in separate `types.zig` files
6. **No dumping grounds** - avoid generic `constants.zig` or `utils.zig` (exception: `math.zig` for genuine math utilities)

## Code Style

- Prefer "grug brain" simplicity: YAGNI, single responsibility, WET, etc.
- Include helpful comments for learning (this is an educational project)
- Use conventional Zig patterns and organization
