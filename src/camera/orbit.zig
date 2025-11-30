//! Orbit Camera - Third-person camera that orbits around a target.
//!
//! Uses spherical coordinates (yaw/pitch) to position the camera
//! at a fixed distance from the target. Mouse movement rotates the view.

const std = @import("std");
const rl = @import("raylib");

/// Distance from camera to target (in meters).
pub const DISTANCE: f32 = 10.0;

/// Mouse sensitivity for camera rotation.
pub const SENSITIVITY: f32 = 0.003;

/// Pitch limits to prevent camera flipping.
pub const PITCH_MIN: f32 = -0.8; // Looking up limit
pub const PITCH_MAX: f32 = 1.2; // Looking down limit

/// State for the orbit camera.
pub const OrbitState = struct {
    yaw: f32, // Horizontal angle (radians)
    pitch: f32, // Vertical angle (radians)

    pub fn init() OrbitState {
        return .{
            .yaw = 0,
            .pitch = 0.3, // Start slightly above horizon
        };
    }
};

/// Update the orbit camera based on mouse input.
/// Positions the camera on a sphere around the target position.
pub fn update(camera: *rl.Camera3D, state: *OrbitState, target_pos: ?[3]f32) void {
    // Update angles from mouse movement
    const mouse_delta = rl.getMouseDelta();
    state.yaw -= mouse_delta.x * SENSITIVITY;
    state.pitch -= mouse_delta.y * SENSITIVITY;
    state.pitch = std.math.clamp(state.pitch, PITCH_MIN, PITCH_MAX);

    if (target_pos) |pos| {
        // Target is slightly above the character center (eye level)
        const target = rl.Vector3.init(pos[0], pos[1] + 1, pos[2]);

        // Spherical to Cartesian conversion
        const cos_pitch = @cos(state.pitch);
        camera.target = target;
        camera.position = rl.Vector3.init(
            target.x + @sin(state.yaw) * cos_pitch * DISTANCE,
            target.y + @sin(state.pitch) * DISTANCE,
            target.z + @cos(state.yaw) * cos_pitch * DISTANCE,
        );
    }
}
