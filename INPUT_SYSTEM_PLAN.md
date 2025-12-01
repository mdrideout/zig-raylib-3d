# Fixed Timestep with Buffered Input System

## Problem Statement
Clicks and inputs are being missed because:
1. The game uses a naive variable timestep loop
2. Input is polled with `isKeyPressed()` inside the render loop
3. If a click happens between frames, it may be cleared before being processed

## Solution: Three-Layer Architecture

Implement the canonical game loop with a **Buffered Action Mapping** input system:

```
┌─────────────────────────────────────────────────────────────┐
│                     RENDER LOOP (Variable)                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Layer 1: INPUT COLLECTOR                                ││
│  │ - Runs every render frame (highest frequency)           ││
│  │ - Drains OS event queue                                 ││
│  │ - LATCHES trigger inputs (jump, shoot stay true)        ││
│  │ - Updates continuous inputs (move_x, move_y)            ││
│  └─────────────────────────────────────────────────────────┘│
│                              ↓                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Layer 2: FIXED TIMESTEP LOOP (while accumulator >= dt)  ││
│  │ - Store previous state for interpolation                ││
│  │ - Read from INPUT BUFFER (not hardware!)                ││
│  │ - Run physics with fixed dt                             ││
│  │ - CONSUME trigger inputs (reset after processing)       ││
│  └─────────────────────────────────────────────────────────┘│
│                              ↓                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Layer 3: RENDER                                         ││
│  │ - Calculate interpolation alpha                         ││
│  │ - Draw with interpolated positions                      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Terminology
- **Polling Rate (Hardware/OS):** Frequency at which OS reports input (mouse: 1000Hz)
- **Tick Rate (Simulation):** Frequency of game logic updates (our choice: 120Hz)
- **Frame Rate (Render):** How often we draw to screen (variable, e.g., 60-144Hz)

### Input Latching Pattern
Trigger actions (jump, shoot) are "sticky" - they stay `true` until the logic loop consumes them. This guarantees no inputs are ever missed between ticks.

```zig
// Layer 1: Collect (runs at render rate)
if (rl.isKeyPressed(.space)) input_buffer.jump = true;  // LATCH it

// Layer 2: Consume (runs at logic rate)
if (input_buffer.jump) {
    performJump();
}
input_buffer.consumeTriggers();  // Reset after processing
```

## Implementation

### Phase 1: Input System (`src/input/mod.zig`)

```zig
/// Semantic input actions decoupled from physical keys.
/// Trigger actions (jump, shoot) are LATCHED - they stay true until consumed.
/// Continuous actions (move) reflect current state.
pub const InputActions = struct {
    // Movement (continuous, -1 to 1)
    move_x: f32 = 0.0,
    move_z: f32 = 0.0,

    // Camera (continuous)
    look_delta_x: f32 = 0.0,
    look_delta_y: f32 = 0.0,

    // Triggers (latched until consumed)
    jump: bool = false,
    interact: bool = false,

    // Mode switches (UI, not gameplay - consumed immediately)
    toggle_free_camera: bool = false,
    toggle_player_mode: bool = false,
    release_cursor: bool = false,
    toggle_debug: bool = false,

    /// Reset trigger actions after physics tick consumes them.
    pub fn consumeTriggers(self: *InputActions) void {
        self.jump = false;
        self.interact = false;
    }

    /// Reset mode switches after they're processed (once per frame).
    pub fn consumeModeInputs(self: *InputActions) void {
        self.toggle_free_camera = false;
        self.toggle_player_mode = false;
        self.release_cursor = false;
        self.toggle_debug = false;
    }
};
```

### Phase 2: Time System (`src/time/mod.zig`)

```zig
/// Fixed timestep for logic/physics updates (120Hz = 8.33ms per tick)
pub const FIXED_TIMESTEP: f32 = 1.0 / 120.0;

/// Maximum frame time to prevent spiral of death (250ms = 4 FPS floor)
pub const MAX_FRAME_TIME: f32 = 0.25;

pub const GameClock = struct {
    accumulator: f32 = 0.0,
    frame_time: f32 = 0.0,

    pub fn beginFrame(self: *GameClock, raw_delta: f32) void {
        self.frame_time = @min(raw_delta, MAX_FRAME_TIME);
        self.accumulator += self.frame_time;
    }

    pub fn shouldStepLogic(self: *GameClock) bool {
        if (self.accumulator >= FIXED_TIMESTEP) {
            self.accumulator -= FIXED_TIMESTEP;
            return true;
        }
        return false;
    }

    pub fn getInterpolationAlpha(self: *const GameClock) f32 {
        return self.accumulator / FIXED_TIMESTEP;
    }
};
```

### Phase 3: Entity Interpolation

Add previous state to entities for smooth rendering:

```zig
const EntityData = struct {
    position: [3]f32,
    rotation: [4]f32,
    prev_position: [3]f32,  // For interpolation
    prev_rotation: [4]f32,  // For interpolation
    // ... other fields
};

/// Store current as previous (call BEFORE physics update)
pub fn storePreviousState(self: *Entities) void { ... }

/// Get interpolated position for rendering
pub fn getInterpolatedPosition(self: *const Entities, index: usize, alpha: f32) [3]f32 {
    const prev = self.data.items(.prev_position)[index];
    const curr = self.data.items(.position)[index];
    return lerpVec3(prev, curr, alpha);
}

/// Reset interpolation after teleport (prev = curr)
pub fn resetInterpolation(self: *Entities, index: usize) void { ... }
```

### Phase 4: Main Loop Refactor

```zig
var game_clock = time.GameClock{};
var input_buffer = input.InputActions{};

while (!rl.windowShouldClose()) {
    // === LAYER 1: COLLECT INPUT ===
    game_clock.beginFrame(rl.getFrameTime());
    input.collectInput(&input_buffer);

    // Handle mode switches (once per frame)
    if (input_buffer.release_cursor) { ... }
    input_buffer.consumeModeInputs();

    // === LAYER 2: FIXED TIMESTEP LOGIC ===
    while (game_clock.shouldStepLogic()) {
        scene.storePreviousState();  // BEFORE physics

        // Character movement from input buffer
        if (game_mode == .player_control) {
            updatePlayerFromInput(&input_buffer, ...);
        }

        physics_world.update(time.FIXED_TIMESTEP);
        scene.syncFromPhysics();

        input_buffer.consumeTriggers();  // AFTER processing
    }

    // === CALCULATE INTERPOLATION ALPHA ===
    const alpha = game_clock.getInterpolationAlpha();

    // === CAMERA UPDATE (uses INTERPOLATED position!) ===
    if (game_mode == .player_control) {
        const player_pos = scene.characters.getInterpolatedPosition(idx, alpha);
        camera.update(player_pos);
    }

    // === LAYER 3: RENDER WITH INTERPOLATION ===
    rl.beginDrawing();
    game_renderer.draw(&scene, &lights, alpha);
    rl.endDrawing();
}
```

---

## Crucial Edge Cases

### Trap 1: Camera Jitter ("Vibrating Player" Bug)

**Problem:** Camera targets raw physics position while mesh renders at interpolated position.

**Fix:** Camera must use interpolated player position:
```zig
// WRONG - causes jitter
camera.update(scene.characters.getPlayerPosition());

// CORRECT - smooth camera
const alpha = game_clock.getInterpolationAlpha();
camera.update(scene.characters.getInterpolatedPosition(idx, alpha));
```

### Trap 2: Teleport Glitch

**Problem:** When teleporting, interpolation sees huge position delta and entity "flies" across screen.

**Fix:** Call `resetInterpolation()` after any discontinuous position change:
```zig
entity.setPosition(new_spawn_point);
entity.resetInterpolation(index);  // prev = curr, no interpolation
```

---

## Verification Tests

1. Run at 30/60/120 FPS - physics should be identical
2. Click rapidly - every click should register
3. Alt-tab for 5 seconds - should recover gracefully (spiral of death prevention)
4. Watch falling cubes - should be smooth regardless of FPS
5. Player should NOT vibrate when moving (camera jitter test)
6. Respawn should not cause speed glitch (teleport test)

---

## Files

### Created
- `src/time/mod.zig` - GameClock, fixed timestep, interpolation helpers
- `src/input/mod.zig` - Input collection, latching, action mapping

### Modified
- `src/main.zig` - Three-layer game loop
- `src/entities/cube.zig` - prev_* fields, interpolation
- `src/characters/character.zig` - prev_* fields, interpolation
- `src/characters/movement.zig` - Work with InputActions
- `src/scene/mod.zig` - storePreviousState() delegation
- `src/scene/renderer.zig` - Accept alpha, render interpolated
