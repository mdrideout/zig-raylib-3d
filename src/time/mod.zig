//! Time Module - Fixed timestep game loop management.
//!
//! Implements the canonical "Fix Your Timestep!" pattern for deterministic
//! physics simulation with smooth visual interpolation. This is the same
//! architecture used by Unity (FixedUpdate), Unreal (Physics ticking),
//! and Godot (_physics_process).
//!
//! ## The Problem
//! A naive game loop where everything runs at the render frame rate causes:
//! - Non-deterministic physics (different behavior at 30 FPS vs 120 FPS)
//! - Missed inputs (clicks can be lost between slow frames)
//! - Variable movement speed based on frame rate
//!
//! ## The Solution
//! Decouple the Simulation Rate from the Presentation Rate:
//! 1. **Accumulator**: Buffer wall-clock time between frames
//! 2. **Fixed Step Loop**: Run logic updates at a constant rate (120Hz)
//! 3. **Interpolation**: Blend between physics states for smooth rendering
//!
//! ## Usage
//! ```zig
//! var clock = GameClock{};
//!
//! while (!windowShouldClose()) {
//!     clock.beginFrame(getFrameTime());
//!
//!     // Fixed timestep logic loop
//!     while (clock.shouldStepLogic()) {
//!         scene.storePreviousState();
//!         physics.update(FIXED_TIMESTEP);
//!         scene.syncFromPhysics();
//!     }
//!
//!     // Render with interpolation
//!     const alpha = clock.getInterpolationAlpha();
//!     render(alpha);
//! }
//! ```

const std = @import("std");

// =============================================================================
// Constants
// =============================================================================

/// Fixed timestep for logic/physics updates.
///
/// 120Hz (8.33ms per tick) provides:
/// - Smooth simulation with headroom for rendering
/// - Good balance of precision and CPU usage
/// - 2x typical monitor refresh rate for responsive input
///
/// Common alternatives:
/// - 60Hz (16.67ms): Lower CPU, matches most monitors
/// - 144Hz (6.94ms): Matches high refresh monitors, higher CPU
pub const FIXED_TIMESTEP: f32 = 1.0 / 120.0;

/// Maximum frame time to prevent the "Spiral of Death".
///
/// If a frame takes too long (e.g., alt-tab, breakpoint, loading), the
/// accumulator would grow large, causing many physics steps, which take
/// time, causing the next frame to be even longer... until the game freezes.
///
/// By clamping to 250ms (4 FPS floor), we cap physics catch-up at ~30 steps
/// per frame maximum. The game will slow down gracefully rather than freeze.
pub const MAX_FRAME_TIME: f32 = 0.25;

// =============================================================================
// GameClock
// =============================================================================

/// Manages fixed timestep accumulator and frame timing.
///
/// The accumulator stores "leftover" time that hasn't been consumed by
/// physics steps yet. This remainder is used to interpolate between
/// the previous and current physics states for smooth rendering.
pub const GameClock = struct {
    /// Accumulated time waiting to be processed by logic updates.
    /// Range: [0, FIXED_TIMESTEP) after all steps are consumed.
    accumulator: f32 = 0.0,

    /// This frame's (clamped) delta time.
    /// Use for visual-only updates that don't affect gameplay.
    frame_time: f32 = 0.0,

    /// Call at the start of each frame with raw delta time from Raylib.
    ///
    /// This clamps the frame time to prevent spiral of death and adds
    /// the time to the accumulator for the fixed timestep loop.
    pub fn beginFrame(self: *GameClock, raw_delta: f32) void {
        // Clamp to prevent spiral of death after lag spikes
        self.frame_time = @min(raw_delta, MAX_FRAME_TIME);
        self.accumulator += self.frame_time;
    }

    /// Returns true if another fixed timestep should be processed.
    ///
    /// Call this in a while loop. Each call that returns true automatically
    /// decrements the accumulator by FIXED_TIMESTEP.
    ///
    /// Example:
    /// ```zig
    /// while (clock.shouldStepLogic()) {
    ///     // This runs at exactly 120Hz regardless of render frame rate
    ///     physics.update(FIXED_TIMESTEP);
    /// }
    /// ```
    pub fn shouldStepLogic(self: *GameClock) bool {
        if (self.accumulator >= FIXED_TIMESTEP) {
            self.accumulator -= FIXED_TIMESTEP;
            return true;
        }
        return false;
    }

    /// Get the fixed timestep value (constant).
    ///
    /// Use this inside the fixed timestep loop for physics and gameplay logic.
    /// This ensures deterministic behavior regardless of render frame rate.
    pub fn getFixedDeltaTime() f32 {
        return FIXED_TIMESTEP;
    }

    /// Get interpolation factor for rendering (0.0 to 1.0).
    ///
    /// After all fixed steps are consumed, there's usually leftover time
    /// in the accumulator (e.g., frame was 10ms but we only consumed 8.33ms).
    /// This alpha value tells you how far "between" physics states we are.
    ///
    /// Use this to blend between previous and current state:
    /// ```zig
    /// const render_pos = lerpVec3(prev_pos, curr_pos, alpha);
    /// ```
    ///
    /// Without interpolation, objects will appear to "stutter" when the
    /// render rate doesn't align perfectly with the logic rate.
    pub fn getInterpolationAlpha(self: *const GameClock) f32 {
        return self.accumulator / FIXED_TIMESTEP;
    }

    /// Get this frame's (clamped) delta time.
    ///
    /// Use for visual-only updates that don't affect gameplay:
    /// - Camera smoothing
    /// - Particle effects
    /// - UI animations
    /// - Orbiting lights
    ///
    /// Do NOT use for physics or gameplay logic!
    pub fn getFrameTime(self: *const GameClock) f32 {
        return self.frame_time;
    }
};

// =============================================================================
// Interpolation Helpers
// =============================================================================

/// Linear interpolation between two 3D vectors.
///
/// Used for smoothly blending positions between physics states.
/// t=0 returns a, t=1 returns b, t=0.5 returns midpoint.
pub fn lerpVec3(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    };
}

/// Spherical linear interpolation between two quaternions.
///
/// SLERP produces constant angular velocity rotation, which looks much
/// smoother than linear interpolation for rotations. Handles the
/// "short path" automatically by flipping the quaternion if needed.
///
/// For small angles, falls back to normalized linear interpolation
/// (NLERP) for better numerical stability.
pub fn slerpQuat(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    // Compute dot product (cosine of angle between quaternions)
    var dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];

    // If dot < 0, negate one quaternion to take the short path
    // (quaternions q and -q represent the same rotation)
    var b_adj = b;
    if (dot < 0.0) {
        b_adj = .{ -b[0], -b[1], -b[2], -b[3] };
        dot = -dot;
    }

    // If quaternions are very close, use normalized linear interpolation
    // to avoid numerical instability in SLERP
    if (dot > 0.9995) {
        var result: [4]f32 = .{
            a[0] + (b_adj[0] - a[0]) * t,
            a[1] + (b_adj[1] - a[1]) * t,
            a[2] + (b_adj[2] - a[2]) * t,
            a[3] + (b_adj[3] - a[3]) * t,
        };
        // Normalize the result
        const len = @sqrt(result[0] * result[0] + result[1] * result[1] +
            result[2] * result[2] + result[3] * result[3]);
        if (len > 0.0) {
            result = .{ result[0] / len, result[1] / len, result[2] / len, result[3] / len };
        }
        return result;
    }

    // Standard SLERP formula
    const theta_0 = std.math.acos(dot); // Angle between quaternions
    const theta = theta_0 * t; // Interpolated angle
    const sin_theta = @sin(theta);
    const sin_theta_0 = @sin(theta_0);

    const s0 = @cos(theta) - dot * sin_theta / sin_theta_0;
    const s1 = sin_theta / sin_theta_0;

    return .{
        a[0] * s0 + b_adj[0] * s1,
        a[1] * s0 + b_adj[1] * s1,
        a[2] * s0 + b_adj[2] * s1,
        a[3] * s0 + b_adj[3] * s1,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "GameClock accumulator works correctly" {
    var clock = GameClock{};

    // Simulate a 16ms frame (60 FPS)
    clock.beginFrame(0.016);

    // With 120Hz fixed timestep (8.33ms), we should get 1 step
    // and have ~7.67ms left in accumulator
    var steps: u32 = 0;
    while (clock.shouldStepLogic()) {
        steps += 1;
    }

    try std.testing.expectEqual(@as(u32, 1), steps);
    try std.testing.expect(clock.accumulator > 0.007);
    try std.testing.expect(clock.accumulator < 0.009);
}

test "GameClock clamps large frame times" {
    var clock = GameClock{};

    // Simulate a 1 second lag spike
    clock.beginFrame(1.0);

    // Should be clamped to MAX_FRAME_TIME
    try std.testing.expectEqual(MAX_FRAME_TIME, clock.frame_time);
}

test "lerpVec3 interpolates correctly" {
    const a = [3]f32{ 0.0, 0.0, 0.0 };
    const b = [3]f32{ 10.0, 20.0, 30.0 };

    const mid = lerpVec3(a, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), mid[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), mid[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), mid[2], 0.001);
}

test "slerpQuat handles identity" {
    const identity = [4]f32{ 0.0, 0.0, 0.0, 1.0 };
    const result = slerpQuat(identity, identity, 0.5);

    // Should return identity (or very close)
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result[3], 0.001);
}
