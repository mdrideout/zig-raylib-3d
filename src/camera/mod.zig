//! Camera module - Manages camera modes and behavior.
//!
//! Provides a unified Camera struct that supports multiple modes:
//! - free: Raylib's built-in free camera (fly around freely)
//! - orbit: Third-person camera that orbits around a target
//!
//! Usage:
//! 1. Create camera with Camera.init()
//! 2. Set camera.mode based on game state
//! 3. Call camera.update(target_pos) each frame
//! 4. Use camera.rl_camera for rendering

const std = @import("std");
const rl = @import("raylib");

pub const orbit = @import("orbit.zig");

/// Camera modes determine how the camera behaves.
pub const CameraMode = enum {
    free, // Raylib's built-in free camera (WASD + mouse to fly)
    orbit, // Third-person orbit around target (mouse rotates view)
};

/// Game camera with support for multiple modes.
pub const Camera = struct {
    rl_camera: rl.Camera3D,
    mode: CameraMode,
    orbit_state: orbit.OrbitState,

    /// Initialize camera with default settings.
    pub fn init() Camera {
        return .{
            .rl_camera = rl.Camera3D{
                .position = rl.Vector3.init(0, 10, 10),
                .target = rl.Vector3.init(0, 0, 0),
                .up = rl.Vector3.init(0, 1, 0),
                .fovy = 45.0,
                .projection = .perspective,
            },
            .mode = .free,
            .orbit_state = orbit.OrbitState.init(),
        };
    }

    /// Update camera based on current mode.
    /// Pass target_pos for modes that follow a target (orbit).
    pub fn update(self: *Camera, target_pos: ?[3]f32) void {
        switch (self.mode) {
            .free => rl.updateCamera(&self.rl_camera, .free),
            .orbit => orbit.update(&self.rl_camera, &self.orbit_state, target_pos),
        }
    }

    /// Get the yaw angle for camera-relative movement.
    /// Only meaningful in orbit mode.
    pub fn getYaw(self: *const Camera) f32 {
        return self.orbit_state.yaw;
    }
};
