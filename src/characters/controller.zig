//! Controller - Character controller logic.
//!
//! Handles ground detection, rotation updates, and coordinates
//! movement with the physics system.

const std = @import("std");
const zphy = @import("zphysics");
const character = @import("character.zig");
const movement = @import("movement.zig");

/// Update a character based on input.
/// Call this once per frame for the player (or for AI-controlled NPCs).
pub fn updateCharacter(
    characters: *character.Characters,
    index: usize,
    input_dir: [3]f32,
    delta_time: f32,
    config: movement.MovementConfig,
) void {
    const body_id = characters.getBodyId(index);
    const body_interface = characters.physics_system.getBodyInterfaceMut();

    // Apply movement velocity
    movement.applyMovement(body_interface, body_id, input_dir, config, delta_time);

    // Update facing rotation (smoothly turn toward movement direction)
    updateFacingRotation(characters, index, input_dir, config.turn_speed, delta_time);

    // Update grounded state
    const grounded = checkGrounded(characters.physics_system, body_id);
    characters.setGrounded(index, grounded);

    // Lock rotation on physics body (prevent tipping over)
    lockPhysicsRotation(body_interface, body_id);
}

/// Update the player character specifically.
/// Convenience function that looks up the player index.
pub fn updatePlayer(
    characters: *character.Characters,
    input_dir: [3]f32,
    delta_time: f32,
) void {
    if (characters.getPlayerIndex()) |player_idx| {
        updateCharacter(characters, player_idx, input_dir, delta_time, movement.default_config);
    }
}

/// Smoothly rotate character to face movement direction.
fn updateFacingRotation(
    characters: *character.Characters,
    index: usize,
    input_dir: [3]f32,
    turn_speed: f32,
    delta_time: f32,
) void {
    // Only update rotation if there's movement input
    const has_input = (input_dir[0] != 0 or input_dir[2] != 0);
    if (!has_input) return;

    const current_rot = characters.getRotation(index);
    const target_rot = movement.rotationFromDirection(input_dir);

    // Interpolate toward target rotation
    const new_rot = movement.slerpRotation(current_rot, target_rot, turn_speed * delta_time);
    characters.setRotation(index, new_rot);
}

/// Check if a character is on the ground using a short raycast.
/// Note: For now, just assume grounded - proper ray filtering requires BodyFilter setup.
fn checkGrounded(physics_system: *zphy.PhysicsSystem, body_id: zphy.BodyId) bool {
    _ = physics_system;
    _ = body_id;
    // TODO: Implement proper ground detection with ray filtering
    // For now, assume always grounded (good enough for walking on flat ground)
    return true;
}

/// Prevent the physics body from rotating (keep upright).
/// Characters should not tip over like rigid bodies.
fn lockPhysicsRotation(body_interface: *zphy.BodyInterface, body_id: zphy.BodyId) void {
    // Zero out angular velocity to prevent spinning
    body_interface.setAngularVelocity(body_id, .{ 0, 0, 0 });
}
