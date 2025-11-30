//! Ground - A static platform for objects to rest on.
//!
//! The ground is a large flat box that doesn't move. Objects can
//! land on it and collide with it, but it stays fixed in place.

const zphy = @import("zphysics");
const physics = @import("../physics/mod.zig");

/// Ground dimensions (full size, not half-extents)
pub const WIDTH: f32 = 20.0;
pub const HEIGHT: f32 = 1.0;
pub const DEPTH: f32 = 20.0;

/// Where the ground is positioned (center of the box)
pub const POSITION = [3]f32{ 0.0, -0.5, 0.0 };

/// Creates a static ground plane in the physics world.
/// Returns the body ID (though we typically don't need to track static bodies).
pub fn spawn(physics_system: *zphy.PhysicsSystem) !zphy.BodyId {
    // BoxShapeSettings takes HALF extents
    const shape_settings = try zphy.BoxShapeSettings.create(.{
        WIDTH / 2.0,
        HEIGHT / 2.0,
        DEPTH / 2.0,
    });
    defer shape_settings.asShapeSettings().release();

    const shape = try shape_settings.asShapeSettings().createShape();
    defer shape.release();

    const body_interface = physics_system.getBodyInterfaceMut();

    return try body_interface.createAndAddBody(.{
        .position = .{ POSITION[0], POSITION[1], POSITION[2], 1.0 },
        .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
        .shape = shape,
        .motion_type = .static,
        .object_layer = physics.layers.object_layers.non_moving,
    }, .dont_activate);
}
