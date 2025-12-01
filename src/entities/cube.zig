//! Cube - Definition and SoA storage for cubes.
//!
//! A cube is a dynamic box that falls and collides. This file contains:
//! - Constants (SIZE)
//! - Physics body creation (spawnBody)
//! - SoA storage for all cube instances (Cubes struct via MultiArrayList)

const std = @import("std");
const zphy = @import("zphysics");
const physics = @import("../physics/mod.zig");
const math = @import("../math.zig");
const time = @import("../time/mod.zig");

/// Cube size (full size, not half-extents)
pub const SIZE: f32 = 1.0;

/// Data for a single cube instance.
/// MultiArrayList stores these as separate arrays (SoA) automatically.
///
/// Includes prev_position and prev_rotation for render interpolation.
/// The renderer blends between prev and current based on accumulator alpha.
const CubeData = struct {
    position: [3]f32,
    rotation: [4]f32, // quaternion (x, y, z, w)
    prev_position: [3]f32, // Previous frame position (for interpolation)
    prev_rotation: [4]f32, // Previous frame rotation (for interpolation)
    body_id: zphy.BodyId,
};

/// SoA storage for all cube entities.
/// Uses std.MultiArrayList for cache-friendly iteration.
pub const Cubes = struct {
    data: std.MultiArrayList(CubeData),
    allocator: std.mem.Allocator,
    physics_system: *zphy.PhysicsSystem,

    pub fn init(allocator: std.mem.Allocator, physics_system: *zphy.PhysicsSystem) Cubes {
        return .{
            .data = .empty,
            .allocator = allocator,
            .physics_system = physics_system,
        };
    }

    pub fn deinit(self: *Cubes) void {
        const body_interface = self.physics_system.getBodyInterfaceMut();
        for (self.data.items(.body_id)) |body_id| {
            body_interface.removeAndDestroyBody(body_id);
        }
        self.data.deinit(self.allocator);
    }

    /// Spawn a cube at position with explicit rotation (quaternion).
    pub fn spawn(self: *Cubes, position: [3]f32, rotation: [4]f32) !void {
        const body_id = try spawnBody(self.physics_system, position, rotation);
        try self.data.append(self.allocator, .{
            .position = position,
            .rotation = rotation,
            // Initialize prev = current to prevent interpolation glitch on first frame
            .prev_position = position,
            .prev_rotation = rotation,
            .body_id = body_id,
        });
    }

    /// Spawn a cube with identity rotation (no rotation).
    pub fn spawnDefault(self: *Cubes, position: [3]f32) !void {
        try self.spawn(position, .{ 0, 0, 0, 1 }); // identity quaternion
    }

    /// Spawn a cube with a random rotation.
    pub fn spawnRandom(self: *Cubes, position: [3]f32) !void {
        // Create fresh PRNG using timestamp - fine for random rotations
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const rotation = math.randomRotation(prng.random());
        try self.spawn(position, rotation);
    }

    /// Sync positions and rotations from physics simulation.
    /// Call this each frame before rendering.
    pub fn syncFromPhysics(self: *Cubes) void {
        const body_interface = self.physics_system.getBodyInterfaceNoLock();
        const slice = self.data.slice();
        const positions = slice.items(.position);
        const rotations = slice.items(.rotation);
        const body_ids = slice.items(.body_id);

        for (body_ids, 0..) |body_id, i| {
            const pos = body_interface.getCenterOfMassPosition(body_id);
            positions[i] = .{ pos[0], pos[1], pos[2] };

            const rot = body_interface.getRotation(body_id);
            rotations[i] = .{ rot[0], rot[1], rot[2], rot[3] };
        }
    }

    /// Number of cubes.
    pub fn count(self: *const Cubes) usize {
        return self.data.len;
    }

    /// Get slices for rendering (positions and rotations).
    pub fn getRenderData(self: *const Cubes) struct { positions: [][3]f32, rotations: [][4]f32 } {
        const slice = self.data.slice();
        return .{
            .positions = slice.items(.position),
            .rotations = slice.items(.rotation),
        };
    }

    // =========================================================================
    // Interpolation Support
    // =========================================================================

    /// Store current state as previous state.
    /// Call this BEFORE each fixed timestep physics update.
    /// This captures the "before" snapshot for render interpolation.
    pub fn storePreviousState(self: *Cubes) void {
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

    /// Get interpolated position for a specific cube.
    /// alpha: 0.0 = previous state, 1.0 = current state
    pub fn getInterpolatedPosition(self: *const Cubes, index: usize, alpha: f32) [3]f32 {
        const slice = self.data.slice();
        const prev = slice.items(.prev_position)[index];
        const curr = slice.items(.position)[index];
        return time.lerpVec3(prev, curr, alpha);
    }

    /// Get interpolated rotation for a specific cube.
    /// alpha: 0.0 = previous state, 1.0 = current state
    pub fn getInterpolatedRotation(self: *const Cubes, index: usize, alpha: f32) [4]f32 {
        const slice = self.data.slice();
        const prev = slice.items(.prev_rotation)[index];
        const curr = slice.items(.rotation)[index];
        return time.slerpQuat(prev, curr, alpha);
    }

    /// Reset interpolation for a cube after teleport.
    /// Sets prev = current so there's no interpolation on next frame.
    /// Call this after any discontinuous position change (teleport, respawn).
    pub fn resetInterpolation(self: *Cubes, index: usize) void {
        const slice = self.data.slice();
        slice.items(.prev_position)[index] = slice.items(.position)[index];
        slice.items(.prev_rotation)[index] = slice.items(.rotation)[index];
    }
};

/// Creates a physics body for a cube.
/// Called internally by Cubes.spawn().
fn spawnBody(physics_system: *zphy.PhysicsSystem, position: [3]f32, rotation: [4]f32) !zphy.BodyId {
    const shape_settings = try zphy.BoxShapeSettings.create(.{
        SIZE / 2.0,
        SIZE / 2.0,
        SIZE / 2.0,
    });
    defer shape_settings.asShapeSettings().release();

    const shape = try shape_settings.asShapeSettings().createShape();
    defer shape.release();

    const body_interface = physics_system.getBodyInterfaceMut();

    return try body_interface.createAndAddBody(.{
        .position = .{ position[0], position[1], position[2], 1.0 },
        .rotation = .{ rotation[0], rotation[1], rotation[2], rotation[3] },
        .shape = shape,
        .motion_type = .dynamic,
        .object_layer = physics.layers.object_layers.moving,
    }, .activate);
}
