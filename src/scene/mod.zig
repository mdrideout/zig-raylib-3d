//! Scene - Manages what exists in the game world.
//!
//! The scene owns SoA storage for each entity type and handles
//! lifecycle (init/deinit) and physics sync.

const std = @import("std");
const zphy = @import("zphysics");
const physics = @import("../physics/mod.zig");
const ground = @import("../entities/ground.zig");
const cube = @import("../entities/cube.zig");

/// The game scene - owns all entity storage.
pub const Scene = struct {
    cubes: cube.Cubes,
    physics_system: *zphy.PhysicsSystem,

    /// Create the scene with initial entities.
    pub fn init(allocator: std.mem.Allocator, physics_world: *physics.PhysicsWorld) !Scene {
        // Seed RNG for random spawning
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));

        var scene = Scene{
            .cubes = cube.Cubes.init(allocator, physics_world.system, prng.random()),
            .physics_system = physics_world.system,
        };

        // Spawn ground (static, no tracking needed)
        _ = try ground.spawn(scene.physics_system);

        // Spawn initial cubes with random rotations
        try scene.cubes.spawnDefault(.{ 0, 5, 0 });
        try scene.cubes.spawnRandom(.{ 0.5, 8, 0.2 });
        try scene.cubes.spawnRandom(.{ -0.3, 11, -0.1 });

        return scene;
    }

    /// Clean up all entities.
    pub fn deinit(self: *Scene) void {
        self.cubes.deinit();
    }

    /// Sync all entity positions/rotations from physics.
    /// Call once per frame before rendering.
    pub fn syncFromPhysics(self: *Scene) void {
        self.cubes.syncFromPhysics();
    }
};