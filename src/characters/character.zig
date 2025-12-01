//! Character - Definition and SoA storage for characters (player and NPCs).
//!
//! A character is a humanoid entity with a capsule physics body.
//! Uses the same SoA pattern as cubes for cache-friendly iteration.
//!
//! Body parts (visual composition) are defined here - the renderer draws
//! what characters define, not the other way around.

const std = @import("std");
const zphy = @import("zphysics");
const physics = @import("../physics/mod.zig");
const time = @import("../time/mod.zig");

/// Character physics dimensions (in meters).
pub const CAPSULE_RADIUS: f32 = 0.3;
pub const CAPSULE_HALF_HEIGHT: f32 = 0.6; // Total height ~1.8m with radius caps

/// Player box dimensions (in meters) - asymmetric so rotation is visible.
pub const BODY_WIDTH: f32 = 0.6; // X - side to side
pub const BODY_HEIGHT: f32 = 1.8; // Y - tall
pub const BODY_DEPTH: f32 = 0.3; // Z - front to back (narrow = shows facing)

/// Types of characters.
pub const CharacterType = enum {
    player,
    npc,
};

/// Types of body parts a character can have.
pub const BodyPartType = enum {
    body, // Main body (box shape)
};

/// A visual part of a character (body, arm, etc.)
/// Defines position and rotation relative to character center.
pub const BodyPart = struct {
    part_type: BodyPartType,
    local_offset: [3]f32, // Position relative to character center
    local_rotation: [4]f32, // Rotation relative to character (quaternion)
    scale: [3]f32, // Scale of the part
};

/// Get the body parts for a character type.
/// Returns static part definitions - renderer iterates and draws each.
pub fn getBodyParts(char_type: CharacterType) []const BodyPart {
    return switch (char_type) {
        .player => &player_parts,
        .npc => &npc_parts,
    };
}

// Player body - single box shape
const player_parts = [_]BodyPart{
    .{
        .part_type = .body,
        .local_offset = .{ 0, 0, 0 },
        .local_rotation = .{ 0, 0, 0, 1 },
        .scale = .{ 1, 1, 1 },
    },
};

// NPC body - single box shape
const npc_parts = [_]BodyPart{
    .{
        .part_type = .body,
        .local_offset = .{ 0, 0, 0 },
        .local_rotation = .{ 0, 0, 0, 1 },
        .scale = .{ 1, 1, 1 },
    },
};

/// Data for a single character instance.
/// MultiArrayList stores these as separate arrays (SoA) automatically.
///
/// Includes prev_position and prev_rotation for render interpolation.
/// The renderer blends between prev and current based on accumulator alpha.
const CharacterData = struct {
    position: [3]f32,
    rotation: [4]f32, // quaternion (x, y, z, w) - facing direction
    prev_position: [3]f32, // Previous frame position (for interpolation)
    prev_rotation: [4]f32, // Previous frame rotation (for interpolation)
    body_id: zphy.BodyId,
    character_type: CharacterType,
    is_grounded: bool,
};

/// SoA storage for all character entities.
/// Uses std.MultiArrayList for cache-friendly iteration.
pub const Characters = struct {
    data: std.MultiArrayList(CharacterData),
    allocator: std.mem.Allocator,
    physics_system: *zphy.PhysicsSystem,
    player_index: ?usize, // Track which index is the player (if any)

    pub fn init(allocator: std.mem.Allocator, physics_system: *zphy.PhysicsSystem) Characters {
        return .{
            .data = .empty,
            .allocator = allocator,
            .physics_system = physics_system,
            .player_index = null,
        };
    }

    pub fn deinit(self: *Characters) void {
        const body_interface = self.physics_system.getBodyInterfaceMut();
        for (self.data.items(.body_id)) |body_id| {
            body_interface.removeAndDestroyBody(body_id);
        }
        self.data.deinit(self.allocator);
    }

    /// Spawn a character at position. Returns the index of the new character.
    pub fn spawn(self: *Characters, position: [3]f32, char_type: CharacterType) !usize {
        const body_id = try spawnBody(self.physics_system, position);
        const index = self.data.len;
        const identity_rot = [4]f32{ 0, 0, 0, 1 };

        try self.data.append(self.allocator, .{
            .position = position,
            .rotation = identity_rot, // Identity quaternion (facing +Z)
            // Initialize prev = current to prevent interpolation glitch on first frame
            .prev_position = position,
            .prev_rotation = identity_rot,
            .body_id = body_id,
            .character_type = char_type,
            .is_grounded = false,
        });

        // Track player index
        if (char_type == .player) {
            self.player_index = index;
        }

        return index;
    }

    /// Spawn the player character at position.
    pub fn spawnPlayer(self: *Characters, position: [3]f32) !usize {
        return self.spawn(position, .player);
    }

    /// Spawn an NPC at position.
    pub fn spawnNPC(self: *Characters, position: [3]f32) !usize {
        return self.spawn(position, .npc);
    }

    /// Get the player character index, if one exists.
    pub fn getPlayerIndex(self: *const Characters) ?usize {
        return self.player_index;
    }

    /// Sync positions and rotations from physics simulation.
    /// Call this each frame before rendering.
    pub fn syncFromPhysics(self: *Characters) void {
        const body_interface = self.physics_system.getBodyInterfaceNoLock();
        const slice = self.data.slice();
        const positions = slice.items(.position);
        const body_ids = slice.items(.body_id);
        // Note: We manage rotation separately (facing direction), not from physics

        for (body_ids, 0..) |body_id, i| {
            const pos = body_interface.getCenterOfMassPosition(body_id);
            positions[i] = .{ pos[0], pos[1], pos[2] };
        }
    }

    /// Number of characters.
    pub fn count(self: *const Characters) usize {
        return self.data.len;
    }

    /// Get slices for rendering.
    pub const RenderData = struct {
        positions: [][3]f32,
        rotations: [][4]f32,
        types: []CharacterType,
    };

    pub fn getRenderData(self: *const Characters) RenderData {
        const slice = self.data.slice();
        return .{
            .positions = slice.items(.position),
            .rotations = slice.items(.rotation),
            .types = slice.items(.character_type),
        };
    }

    /// Get body ID for a character (for movement/physics).
    pub fn getBodyId(self: *const Characters, index: usize) zphy.BodyId {
        return self.data.items(.body_id)[index];
    }

    /// Set grounded state for a character.
    pub fn setGrounded(self: *Characters, index: usize, grounded: bool) void {
        self.data.items(.is_grounded)[index] = grounded;
    }

    /// Check if a character is grounded.
    pub fn isGrounded(self: *const Characters, index: usize) bool {
        return self.data.items(.is_grounded)[index];
    }

    /// Set facing rotation for a character.
    pub fn setRotation(self: *Characters, index: usize, rotation: [4]f32) void {
        self.data.items(.rotation)[index] = rotation;
    }

    /// Get facing rotation for a character.
    pub fn getRotation(self: *const Characters, index: usize) [4]f32 {
        return self.data.items(.rotation)[index];
    }

    // =========================================================================
    // Interpolation Support
    // =========================================================================

    /// Store current state as previous state.
    /// Call this BEFORE each fixed timestep physics update.
    /// This captures the "before" snapshot for render interpolation.
    pub fn storePreviousState(self: *Characters) void {
        const slice = self.data.slice();
        const positions = slice.items(.position);
        const rotations = slice.items(.rotation);
        const prev_positions = slice.items(.prev_position);
        const prev_rotations = slice.items(.prev_rotation);

        for (positions, rotations, prev_positions, prev_rotations) |pos, rot, *prev_pos, *prev_rot| {
            prev_pos.* = pos;
            prev_rot.* = rot;
        }
    }

    /// Get interpolated position for a specific character.
    /// alpha: 0.0 = previous state, 1.0 = current state
    pub fn getInterpolatedPosition(self: *const Characters, index: usize, alpha: f32) [3]f32 {
        const slice = self.data.slice();
        const prev = slice.items(.prev_position)[index];
        const curr = slice.items(.position)[index];
        return time.lerpVec3(prev, curr, alpha);
    }

    /// Get interpolated rotation for a specific character.
    /// alpha: 0.0 = previous state, 1.0 = current state
    pub fn getInterpolatedRotation(self: *const Characters, index: usize, alpha: f32) [4]f32 {
        const slice = self.data.slice();
        const prev = slice.items(.prev_rotation)[index];
        const curr = slice.items(.rotation)[index];
        return time.slerpQuat(prev, curr, alpha);
    }

    /// Reset interpolation for a character after teleport.
    /// Sets prev = current so there's no interpolation on next frame.
    /// Call this after any discontinuous position change (teleport, respawn).
    pub fn resetInterpolation(self: *Characters, index: usize) void {
        const slice = self.data.slice();
        slice.items(.prev_position)[index] = slice.items(.position)[index];
        slice.items(.prev_rotation)[index] = slice.items(.rotation)[index];
    }
};

/// Creates a capsule physics body for a character.
fn spawnBody(physics_system: *zphy.PhysicsSystem, position: [3]f32) !zphy.BodyId {
    // Capsule shape: half_height is the cylinder part, radius is the caps
    // Total height = 2 * half_height + 2 * radius = 2 * 0.6 + 2 * 0.3 = 1.8m
    const shape_settings = try zphy.CapsuleShapeSettings.create(CAPSULE_HALF_HEIGHT, CAPSULE_RADIUS);
    defer shape_settings.asShapeSettings().release();

    const shape = try shape_settings.asShapeSettings().createShape();
    defer shape.release();

    const body_interface = physics_system.getBodyInterfaceMut();

    return try body_interface.createAndAddBody(.{
        .position = .{ position[0], position[1], position[2], 1.0 },
        .rotation = .{ 0, 0, 0, 1 }, // Identity quaternion
        .shape = shape,
        .motion_type = .dynamic,
        .object_layer = physics.layers.object_layers.moving,
        .friction = 0.5,
        .restitution = 0.0, // No bounce
        .linear_damping = 0.0, // We handle deceleration manually
        .angular_damping = 1.0, // Prevent spinning
    }, .activate);
}
