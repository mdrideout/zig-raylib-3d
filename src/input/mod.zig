//! Input Module - Buffered Action Mapping System
//!
//! This module implements the "Buffered Action Mapping" pattern used by
//! professional game engines like Unreal and Godot. Instead of checking
//! raw hardware state (isKeyDown) directly in game logic, we:
//!
//! 1. **Collect** input once per render frame (highest frequency)
//! 2. **Map** physical keys to semantic actions (Space → Jump, not KEY_SPACE)
//! 3. **Buffer** trigger inputs using "latching" (stays true until consumed)
//! 4. **Consume** triggers in the fixed timestep loop
//!
//! ## Why Latching?
//! Without latching, if you click between frames, the input might be cleared
//! before your game logic ever sees it. With latching:
//!
//! 1. Frame 1: User clicks. `input.shoot = true` (latched)
//! 2. Physics tick: Sees `shoot = true`, fires bullet, calls `consumeTriggers()`
//! 3. Frame 2: `shoot` is now `false`, ready for next click
//!
//! ## Action Types
//! - **Triggers**: One-shot actions (jump, shoot) - latched until consumed
//! - **Continuous**: Held state (movement, look) - updated every frame
//! - **Mode Switches**: UI actions (toggle debug) - consumed once per frame
//!
//! ## Usage
//! ```zig
//! var input = InputActions{};
//!
//! while (!windowShouldClose()) {
//!     // Layer 1: Collect (every render frame)
//!     collectInput(&input);
//!
//!     // Handle UI/mode inputs (once per frame)
//!     if (input.toggle_debug) { debug_visible = !debug_visible; }
//!     input.consumeModeInputs();
//!
//!     // Layer 2: Fixed timestep loop
//!     while (clock.shouldStepLogic()) {
//!         if (input.jump) { player.jump(); }
//!         // ... physics ...
//!         input.consumeTriggers();  // Reset after processing
//!     }
//! }
//! ```

const std = @import("std");
const rl = @import("raylib");

// =============================================================================
// InputActions - Semantic Action Buffer
// =============================================================================

/// Semantic input actions decoupled from physical keys.
///
/// This struct represents "what the player wants to do" rather than
/// "what buttons are pressed". This decoupling enables:
/// - Key rebinding without changing game logic
/// - Gamepad support (same actions, different input device)
/// - Input recording/playback for replays
/// - Network input synchronization
pub const InputActions = struct {
    // =========================================================================
    // Movement (Continuous)
    // Range: -1.0 to 1.0, updated every frame from current key state
    // =========================================================================

    /// Horizontal movement input. Negative = left (A), Positive = right (D).
    move_x: f32 = 0.0,

    /// Depth movement input. Negative = forward (W), Positive = backward (S).
    /// Note: In our coordinate system, -Z is forward.
    move_z: f32 = 0.0,

    // =========================================================================
    // Camera Look (Continuous)
    // Mouse delta since last frame, in pixels
    // =========================================================================

    /// Horizontal mouse movement for camera yaw.
    look_delta_x: f32 = 0.0,

    /// Vertical mouse movement for camera pitch.
    look_delta_y: f32 = 0.0,

    // =========================================================================
    // Gameplay Triggers (Latched)
    // These stay TRUE until explicitly consumed by game logic.
    // Use isKeyPressed() to detect the moment of press, not held state.
    // =========================================================================

    /// Jump action (typically Space). Latched until consumed.
    jump: bool = false,

    /// Interact action (typically E). Latched until consumed.
    interact: bool = false,

    // =========================================================================
    // Mode Switches (Latched, UI layer)
    // These are consumed once per frame, not per physics tick.
    // Prevents toggle_debug from firing 5x if physics runs 5 steps.
    // =========================================================================

    /// Switch to free camera mode (Key 1).
    toggle_free_camera: bool = false,

    /// Switch to player control mode (Key 2).
    toggle_player_mode: bool = false,

    /// Release mouse cursor (Escape).
    release_cursor: bool = false,

    /// Toggle debug UI overlay (F3).
    toggle_debug: bool = false,

    // =========================================================================
    // Methods
    // =========================================================================

    /// Reset gameplay trigger actions after the physics tick consumes them.
    ///
    /// Call this at the END of each fixed timestep iteration, after
    /// all gameplay logic has had a chance to read the triggers.
    ///
    /// Note: Does NOT reset continuous inputs (move_x, etc.) because
    /// those represent "current state" not "events".
    ///
    /// Note: Does NOT reset mode switches because those are handled
    /// separately in the render loop, not physics loop.
    pub fn consumeTriggers(self: *InputActions) void {
        self.jump = false;
        self.interact = false;
    }

    /// Reset mode switch actions after they're processed.
    ///
    /// Call this once per frame (in the render loop) after handling
    /// UI/mode changes. This prevents a single keypress from toggling
    /// a mode multiple times if the physics loop runs multiple steps.
    pub fn consumeModeInputs(self: *InputActions) void {
        self.toggle_free_camera = false;
        self.toggle_player_mode = false;
        self.release_cursor = false;
        self.toggle_debug = false;
    }

    /// Get the movement direction as a normalized 3D vector.
    ///
    /// Combines move_x and move_z into a direction vector and normalizes it
    /// so diagonal movement isn't faster than cardinal movement.
    ///
    /// Returns [0, 0, 0] if no movement input.
    pub fn getMoveDirection(self: *const InputActions) [3]f32 {
        const raw = [3]f32{ self.move_x, 0.0, self.move_z };

        // Calculate length
        const len_sq = raw[0] * raw[0] + raw[2] * raw[2];
        if (len_sq < 0.0001) {
            return .{ 0.0, 0.0, 0.0 };
        }

        // Normalize
        const len = @sqrt(len_sq);
        return .{ raw[0] / len, 0.0, raw[2] / len };
    }

    /// Check if any movement input is active.
    pub fn hasMovementInput(self: *const InputActions) bool {
        return self.move_x != 0.0 or self.move_z != 0.0;
    }
};

// =============================================================================
// Input Collection
// =============================================================================

/// Collect input from hardware. Call once per RENDER frame.
///
/// This function:
/// 1. Updates continuous inputs (movement, look) from current state
/// 2. LATCHES trigger inputs using OR (if pressed, stays true)
/// 3. LATCHES mode switches for once-per-frame handling
///
/// The latching pattern ensures that even if a button is pressed and
/// released between frames, the action will still be registered.
pub fn collectInput(current: *InputActions) void {
    // =========================================================================
    // TRIGGERS (Latched)
    // Use isKeyPressed() which returns true only on the frame the key goes down.
    // OR into existing state so we don't lose presses between physics ticks.
    // =========================================================================

    if (rl.isKeyPressed(.space)) current.jump = true;
    if (rl.isKeyPressed(.e)) current.interact = true;

    // =========================================================================
    // MODE SWITCHES (Latched for single-frame handling)
    // These are UI-level inputs, handled once per render frame.
    // =========================================================================

    if (rl.isKeyPressed(.escape)) current.release_cursor = true;
    if (rl.isKeyPressed(.one)) current.toggle_free_camera = true;
    if (rl.isKeyPressed(.two)) current.toggle_player_mode = true;
    if (rl.isKeyPressed(.f3)) current.toggle_debug = true;

    // =========================================================================
    // CONTINUOUS (Current state)
    // Use isKeyDown() which returns true while the key is held.
    // These are overwritten each frame, not latched.
    // =========================================================================

    current.move_x = 0.0;
    current.move_z = 0.0;

    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) current.move_x += 1.0;
    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) current.move_x -= 1.0;
    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) current.move_z -= 1.0; // Forward is -Z
    if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) current.move_z += 1.0;

    // =========================================================================
    // MOUSE LOOK (Continuous)
    // Mouse delta is automatically accumulated by Raylib between frames.
    // =========================================================================

    const mouse_delta = rl.getMouseDelta();
    current.look_delta_x = mouse_delta.x;
    current.look_delta_y = mouse_delta.y;
}

/// Compute camera-relative movement direction from input.
///
/// Transforms the input movement vector by the camera's yaw angle so that
/// pressing W always moves "forward" relative to where the camera is looking.
///
/// This is the same transformation that was in movement.zig, but now works
/// with the InputActions struct instead of polling keys directly.
pub fn computeCameraRelativeMovement(input: *const InputActions, camera_yaw: f32) [3]f32 {
    const dir = input.getMoveDirection();

    // If no movement input, return zero
    if (dir[0] == 0.0 and dir[2] == 0.0) {
        return .{ 0.0, 0.0, 0.0 };
    }

    // Rotate by camera yaw
    const cos_yaw = @cos(camera_yaw);
    const sin_yaw = @sin(camera_yaw);

    return .{
        dir[0] * cos_yaw - dir[2] * sin_yaw,
        0.0,
        dir[0] * sin_yaw + dir[2] * cos_yaw,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "InputActions defaults to zero" {
    const input = InputActions{};

    try std.testing.expectEqual(@as(f32, 0.0), input.move_x);
    try std.testing.expectEqual(@as(f32, 0.0), input.move_z);
    try std.testing.expectEqual(false, input.jump);
}

test "getMoveDirection normalizes diagonal" {
    var input = InputActions{};
    input.move_x = 1.0;
    input.move_z = 1.0;

    const dir = input.getMoveDirection();

    // Diagonal should be normalized to ~0.707
    const expected = 1.0 / @sqrt(2.0);
    try std.testing.expectApproxEqAbs(expected, dir[0], 0.001);
    try std.testing.expectApproxEqAbs(expected, dir[2], 0.001);
}

test "consumeTriggers resets gameplay actions" {
    var input = InputActions{};
    input.jump = true;
    input.interact = true;
    input.toggle_debug = true; // Mode switch

    input.consumeTriggers();

    // Gameplay triggers should be reset
    try std.testing.expectEqual(false, input.jump);
    try std.testing.expectEqual(false, input.interact);

    // Mode switches should NOT be reset by consumeTriggers
    try std.testing.expectEqual(true, input.toggle_debug);
}

test "consumeModeInputs resets mode switches" {
    var input = InputActions{};
    input.toggle_debug = true;
    input.jump = true; // Gameplay trigger

    input.consumeModeInputs();

    // Mode switches should be reset
    try std.testing.expectEqual(false, input.toggle_debug);

    // Gameplay triggers should NOT be reset by consumeModeInputs
    try std.testing.expectEqual(true, input.jump);
}
