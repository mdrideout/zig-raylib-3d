//! Characters module - Player and NPC character system.
//!
//! This module provides:
//! - Character entity storage (SoA pattern)
//! - Player movement input handling
//! - Character controller logic (ground check, rotation)
//!
//! Usage:
//! 1. Create Characters storage in Scene
//! 2. Spawn player with characters.spawnPlayer()
//! 3. Each frame: get input, call controller.updatePlayer(), sync from physics
//! 4. Render capsules via Renderer

pub const character = @import("character.zig");
pub const movement = @import("movement.zig");
pub const controller = @import("controller.zig");

// Re-export common types for convenience
pub const Characters = character.Characters;
pub const CharacterType = character.CharacterType;
pub const MovementConfig = movement.MovementConfig;

// Re-export body part types
pub const BodyPart = character.BodyPart;
pub const BodyPartType = character.BodyPartType;
pub const getBodyParts = character.getBodyParts;

// Re-export constants
pub const CAPSULE_RADIUS = character.CAPSULE_RADIUS;
pub const CAPSULE_HALF_HEIGHT = character.CAPSULE_HALF_HEIGHT;
pub const BODY_WIDTH = character.BODY_WIDTH;
pub const BODY_HEIGHT = character.BODY_HEIGHT;
pub const BODY_DEPTH = character.BODY_DEPTH;
