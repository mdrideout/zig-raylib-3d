//! Movement - Player input handling and movement physics.
//!
//! Handles WASD input relative to camera direction and applies
//! velocity to character physics bodies.

const std = @import("std");
const rl = @import("raylib");
const zphy = @import("zphysics");

/// Configuration for how movement feels.
pub const MovementConfig = struct {
    move_speed: f32 = 5.0, // Units per second
    acceleration: f32 = 20.0, // How fast to reach max speed
    deceleration: f32 = 15.0, // How fast to stop (when no input)
    turn_speed: f32 = 10.0, // How fast character rotates to face direction
};

/// Default movement configuration.
pub const default_config = MovementConfig{};

/// Get movement direction from WASD input, relative to camera yaw angle.
/// This is simpler than the camera-vector approach and works well with orbit camera.
/// Returns normalized direction vector (or zero if no input).
pub fn getInputDirectionFromYaw(camera_yaw: f32) [3]f32 {
    var dir = [3]f32{ 0, 0, 0 };

    // Raw input (W=forward=-Z, S=back=+Z, A=left=-X, D=right=+X)
    if (rl.isKeyDown(.w)) dir[2] -= 1;
    if (rl.isKeyDown(.s)) dir[2] += 1;
    if (rl.isKeyDown(.a)) dir[0] -= 1;
    if (rl.isKeyDown(.d)) dir[0] += 1;

    // Check if there's any input
    const length_sq = dir[0] * dir[0] + dir[2] * dir[2];
    if (length_sq < 0.0001) {
        return .{ 0, 0, 0 };
    }

    // Normalize raw input
    const length = @sqrt(length_sq);
    dir[0] /= length;
    dir[2] /= length;

    // Rotate by NEGATIVE camera yaw (camera looks opposite to its position offset)
    // cos(-x) = cos(x), so only sin needs negation
    const sin_yaw = @sin(-camera_yaw);
    const cos_yaw = @cos(camera_yaw);
    const rotated_x = dir[0] * cos_yaw - dir[2] * sin_yaw;
    const rotated_z = dir[0] * sin_yaw + dir[2] * cos_yaw;

    return .{ rotated_x, 0, rotated_z };
}

/// Get movement direction from WASD keys relative to camera (legacy).
/// Uses camera vectors - works with free camera mode.
/// Returns normalized direction vector (or zero if no input).
pub fn getInputDirection(camera: rl.Camera3D) [3]f32 {
    // Get camera's forward and right vectors (horizontal plane only)
    const cam_forward = rl.Vector3{
        .x = camera.target.x - camera.position.x,
        .y = 0, // Ignore vertical component
        .z = camera.target.z - camera.position.z,
    };
    const forward = cam_forward.normalize();

    // Right vector = forward cross up (in horizontal plane)
    const up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
    const right = forward.crossProduct(up).normalize();

    // Accumulate input direction
    var input_x: f32 = 0;
    var input_z: f32 = 0;

    if (rl.isKeyDown(.w)) {
        input_x += forward.x;
        input_z += forward.z;
    }
    if (rl.isKeyDown(.s)) {
        input_x -= forward.x;
        input_z -= forward.z;
    }
    if (rl.isKeyDown(.d)) {
        input_x += right.x;
        input_z += right.z;
    }
    if (rl.isKeyDown(.a)) {
        input_x -= right.x;
        input_z -= right.z;
    }

    // Normalize if there's any input
    const length_sq = input_x * input_x + input_z * input_z;
    if (length_sq > 0.0001) {
        const length = @sqrt(length_sq);
        return .{ input_x / length, 0, input_z / length };
    }

    return .{ 0, 0, 0 };
}

/// Apply movement to a character's physics body.
/// Uses velocity-based movement with smooth acceleration.
pub fn applyMovement(
    body_interface: *zphy.BodyInterface,
    body_id: zphy.BodyId,
    input_dir: [3]f32,
    config: MovementConfig,
    delta_time: f32,
) void {
    // Get current velocity
    const current_vel = body_interface.getLinearVelocity(body_id);

    // Calculate target velocity from input
    const target_vel_x = input_dir[0] * config.move_speed;
    const target_vel_z = input_dir[2] * config.move_speed;

    // Determine interpolation factor based on input
    const has_input = (input_dir[0] != 0 or input_dir[2] != 0);
    const lerp_factor = if (has_input)
        @min(config.acceleration * delta_time, 1.0)
    else
        @min(config.deceleration * delta_time, 1.0);

    // Interpolate horizontal velocity (preserve vertical for gravity/jumping)
    const new_vel_x = lerp(current_vel[0], target_vel_x, lerp_factor);
    const new_vel_z = lerp(current_vel[2], target_vel_z, lerp_factor);

    // Set the new velocity (keeping Y for gravity)
    body_interface.setLinearVelocity(body_id, .{ new_vel_x, current_vel[1], new_vel_z });
}

/// Linear interpolation helper.
fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Calculate target rotation quaternion from movement direction.
/// Returns identity if direction is zero.
pub fn rotationFromDirection(dir: [3]f32) [4]f32 {
    const length_sq = dir[0] * dir[0] + dir[2] * dir[2];
    if (length_sq < 0.0001) {
        return .{ 0, 0, 0, 1 }; // Identity - no rotation
    }

    // Calculate yaw angle from direction (facing +Z is 0)
    const angle = std.math.atan2(dir[0], dir[2]);

    // Convert to quaternion (rotation around Y axis)
    const half_angle = angle / 2.0;
    return .{
        0, // x
        @sin(half_angle), // y
        0, // z
        @cos(half_angle), // w
    };
}

/// Smoothly interpolate between two rotations (spherical linear interpolation).
/// This is a simplified SLERP for small angle differences.
pub fn slerpRotation(from: [4]f32, to: [4]f32, t: f32) [4]f32 {
    // For small differences, linear interpolation is close enough
    // and much simpler than full SLERP
    var result: [4]f32 = undefined;
    result[0] = lerp(from[0], to[0], t);
    result[1] = lerp(from[1], to[1], t);
    result[2] = lerp(from[2], to[2], t);
    result[3] = lerp(from[3], to[3], t);

    // Normalize to keep it a valid quaternion
    const length = @sqrt(result[0] * result[0] + result[1] * result[1] +
        result[2] * result[2] + result[3] * result[3]);
    if (length > 0.0001) {
        result[0] /= length;
        result[1] /= length;
        result[2] /= length;
        result[3] /= length;
    }

    return result;
}
