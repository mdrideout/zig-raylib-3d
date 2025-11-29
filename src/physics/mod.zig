//! Physics Module - Wraps Jolt Physics (via zphysics) for the game.
//!
//! Usage:
//!   const physics = @import("physics/mod.zig");
//!   var world = try physics.PhysicsWorld.create(allocator);
//!   defer world.destroy();
//!   // In game loop:
//!   world.update(delta_time);

const std = @import("std");
const zphy = @import("zphysics");

/// Re-export layers so main.zig can use them when creating bodies
/// Example: physics.layers.object_layers.moving
pub const layers = @import("layers.zig");
const filters = @import("filters.zig");

// Filter instances - these MUST live as long as the PhysicsSystem.
// Module-level vars keep them alive for the program's lifetime.
// Jolt holds pointers to these, so they can't be stack variables!
var broad_phase_layer_interface: filters.BroadPhaseLayerInterface = .{};
var object_vs_broad_phase_filter: filters.ObjectVsBroadPhaseLayerFilter = .{};
var object_layer_pair_filter: filters.ObjectLayerPairFilter = .{};

/// Wrapper around Jolt's PhysicsSystem with a simpler API.
/// Handles initialization, cleanup, and provides update method.
pub const PhysicsWorld = struct {
    system: *zphy.PhysicsSystem,

    /// Initialize the physics engine and create a physics world.
    /// Call this once at game startup.
    pub fn create(allocator: std.mem.Allocator) !PhysicsWorld {
        // Initialize Jolt's global state (thread pools, allocators, etc.)
        try zphy.init(allocator, .{});

        // Create the physics simulation with our collision filters
        const system = try zphy.PhysicsSystem.create(
            @ptrCast(&broad_phase_layer_interface.interface),
            @ptrCast(&object_vs_broad_phase_filter.interface),
            @ptrCast(&object_layer_pair_filter.interface),
            .{
                .max_bodies = 1024, // Max physics objects
                .num_body_mutexes = 0, // 0 = auto-detect based on CPU cores
                .max_body_pairs = 1024, // Max simultaneous collision pairs
                .max_contact_constraints = 1024, // Max contact points to solve
            },
        );

        return .{ .system = system };
    }

    /// Clean up physics resources. Call when shutting down.
    pub fn destroy(self: *PhysicsWorld) void {
        self.system.destroy();
        zphy.deinit();
    }

    /// Step the physics simulation forward by delta_time seconds.
    /// Call this once per frame in your game loop, BEFORE rendering.
    pub fn update(self: *PhysicsWorld, delta_time: f32) !void {
        // Note: For deterministic physics, use a fixed timestep (e.g., 1/60).
        // Using frame time is simpler but can cause slight variations.
        _ = try self.system.update(delta_time, .{});
    }
};
