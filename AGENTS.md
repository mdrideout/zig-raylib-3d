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
  main.zig              # Game loop, input, window management
  math.zig              # Math utilities (randomRotation, etc.)
  camera/
    mod.zig             # Camera modes (free, orbit), public API
    orbit.zig           # Orbit camera behavior (third-person)
  characters/
    mod.zig             # Characters module public API
    character.zig       # Character definition, body parts, SoA storage
    movement.zig        # Input handling, movement physics
    controller.zig      # Character controller logic
  entities/
    cube.zig            # Cube: definition + SoA storage (Cubes struct)
    ground.zig          # Ground: definition + spawn
  lighting/
    mod.zig             # Lights struct (SoA), public API
    animation.zig       # OrbitingLight animation logic
    shaders/
      lighting.fs       # Fragment shader (Phong lighting)
      lighting.vs       # Vertex shader
  scene/
    mod.zig             # Scene lifecycle, owns entity storage
    renderer.zig        # Drawing logic only (no animation state)
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

### `scene/` - Orchestration, animation, and rendering
- `mod.zig` - Owns entity storage instances, lifecycle (init/deinit), animations
- `renderer.zig` - Draws entities using Raylib (no animation state!)

Animation is game logic (how things change), not rendering (how things look).
This separation keeps the renderer pure and allows multiple animated elements.

**Uses:** entity storage structs, physics for positions, lights for animation

### Renderer vs Entity Separation

**Entities/Characters** define:
- What something IS (shape, size, body parts)
- Behavior and state
- Visual composition (which parts make up the entity)

**Renderer** handles:
- HOW to draw things (meshes, materials, transforms)
- GPU resources (shaders, textures)
- Drawing order and optimization

The renderer draws what entities define. It does not invent visual elements.

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

### Always Use SoA (MultiArrayList)

Use `std.MultiArrayList` for **all** entity/object collections, regardless of size.

**Why consistency > micro-optimization:**
- One pattern to learn and maintain
- Boilerplate cost is ~zero with LLM assistance
- Performance difference for small collections is negligible
- Natural progression if collection grows

**Pattern:**
```zig
const FooData = struct {
    position: [3]f32,
    velocity: [3]f32,
    // ... hot data
};

pub const Foos = struct {
    data: std.MultiArrayList(FooData),
    allocator: std.mem.Allocator,
    // ... cold data or fixed-size arrays
};
```

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

## Vertical Slice Architecture

*Note: We refer here to "Vertical Slice Architecture" as a code organization pattern, distinct from the "Vertical Slice" production term (which refers to a playable demo of a game level).*

Co-locate related files by feature, not by file type. This aligns with Zig's philosophy of locality and explicit dependency management.

**Why co-locate?**
- Everything about a feature in one place
- Explicit dependencies - you can see what files a feature needs
- When a feature changes, related files are nearby
- Easier to understand, modify, or remove a feature as a unit

### Directory Structure

**`src/core/`** - Cross-cutting infrastructure used by all slices:
- Math utilities
- Basic Transform structs
- Logging, Allocators
- **Must NOT contain feature-specific game logic**

**Feature Slices** - Game features as sibling folders to `core`:
- `lighting/`, `physics/`, `entities/`, etc.
- Each contains its own Logic, Data, and Assets (Shaders) co-located together

**Example: Lighting**
```
src/lighting/           # Everything lighting-related
  mod.zig               # Public API (Lights struct)
  animation.zig         # Animation behaviors (OrbitingLight)
  shaders/              # GPU shaders for this feature
    lighting.fs
    lighting.vs
```

**Anti-pattern: Type-based separation**
```
src/
  systems/lighting.zig  # Lighting logic here...
resources/
  shaders/lighting.fs   # ...but shaders way over here
```

This principle applies to any self-contained feature that has multiple related files (code, shaders, assets, configs).

### Reference Resources

- **[Vertical Slice Architecture](https://www.jimmybogard.com/vertical-slice-architecture/)** (Jimmy Bogard)
  > "Minimize coupling between slices, and maximize coupling inside a slice."

- **[Game Programming Patterns - Component](https://gameprogrammingpatterns.com/component.html)** (Robert Nystrom)
  > Demonstrates how decoupling domains allows a single entity to span multiple domains (Physics, Graphics) without monolithic inheritance, enabling modular file structures.

- **[Organizing Code by Feature](https://codeopinion.com/organizing-code-by-feature-using-vertical-slices/)** (Derek Comartin)
  > "Folders should represent the capabilities of your application, not technical implementation details."

## Code Style

- Prefer "grug brain" simplicity: YAGNI, single responsibility, WET, etc.
- Include helpful comments for learning (this is an educational project)
- Use conventional Zig patterns and organization

## No Visual Hacks

Do not add "temporary" or "quick iteration" visual hacks. If a feature belongs in a certain module (e.g., character arms belong in `characters/`), implement it there properly from the start. Shortcuts create technical debt and violate separation of concerns.

**Bad:** "Add arms in renderer with TODO comment"
**Good:** Define body parts in character module, renderer draws them
