//! Scene - Manages what exists in the game world.
//!
//! The scene owns SoA storage for each entity type and handles
//! lifecycle (init/deinit) and physics sync.
//!
//! Animation has moved to the lighting module (src/lighting/animation.zig).

const std = @import("std");
const zphy = @import("zphysics");
const physics = @import("../physics/mod.zig");
const ground = @import("../entities/ground.zig");
const cube = @import("../entities/cube.zig");
const characters = @import("../characters/mod.zig");

/// The game scene - owns all entity storage.
pub const Scene = struct {
    cubes: cube.Cubes,
    characters: characters.Characters,
    physics_system: *zphy.PhysicsSystem,

    /// Create the scene with ground only (no entities yet).
    /// Call spawnEntities() after mode selection to spawn cubes and player.
    pub fn init(allocator: std.mem.Allocator, physics_world: *physics.PhysicsWorld) !Scene {
        const scene = Scene{
            .cubes = cube.Cubes.init(allocator, physics_world.system),
            .characters = characters.Characters.init(allocator, physics_world.system),
            .physics_system = physics_world.system,
        };

        // Spawn ground (static, always visible)
        _ = try ground.spawn(scene.physics_system);

        return scene;
    }

    /// Spawn cubes and player character.
    /// Call once after mode selection.
    pub fn spawnEntities(self: *Scene) !void {
        // Spawn the player character
        _ = try self.characters.spawnPlayer(.{ 0, 2, 0 });

        // Spawn initial cubes with random rotations
        try self.cubes.spawnDefault(.{ 0, 5, 0 });
        try self.cubes.spawnRandom(.{ 0.5, 8, 0.2 });
        try self.cubes.spawnDefault(.{ 0, 10, 0 });
        try self.cubes.spawnRandom(.{ -0.3, 11, -0.1 });
        try self.cubes.spawnRandom(.{ -0.3, 16, -0.1 });
    }

    /// Clean up all entities.
    pub fn deinit(self: *Scene) void {
        self.cubes.deinit();
        self.characters.deinit();
    }

    /// Sync all entity positions/rotations from physics.
    /// Call once per frame before rendering.
    pub fn syncFromPhysics(self: *Scene) void {
        self.cubes.syncFromPhysics();
        self.characters.syncFromPhysics();
    }
};
