const zphy = @import("zphysics");
const layers = @import("layers.zig");

/// Maps each Object Layer to its corresponding Broad Phase Layer.
/// Think of it as: "Which bucket does this type of object go into?"
///
/// Jolt calls these functions during setup and caches the results.
/// The `extern struct` and `callconv(.c)` are required because Jolt
/// is a C++ library - these let Zig code be called from C/C++.
pub const BroadPhaseLayerInterface = extern struct {
    interface: zphy.BroadPhaseLayerInterface = .init(@This()),

    // Lookup table: object_layer -> broad_phase_layer
    object_to_broad_phase: [layers.object_layers.len]zphy.BroadPhaseLayer = init: {
        var arr: [layers.object_layers.len]zphy.BroadPhaseLayer = undefined;
        arr[layers.object_layers.non_moving] = layers.broad_phase_layers.non_moving;
        arr[layers.object_layers.moving] = layers.broad_phase_layers.moving;
        break :init arr;
    },

    /// Returns how many broad phase layers exist (for Jolt's internal arrays)
    pub fn getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.c) u32 {
        return layers.broad_phase_layers.len;
    }

    /// Given an object layer, return which broad phase bucket it belongs to
    pub fn getBroadPhaseLayer(
        iface: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.c) zphy.BroadPhaseLayer {
        // Cast from the zphysics interface back to our wrapper struct
        const self: *const BroadPhaseLayerInterface = @ptrCast(iface);
        return self.object_to_broad_phase[layer];
    }
};

/// Decides if an Object Layer should check for collisions against a Broad Phase bucket.
/// This is the FIRST filter - runs during broad phase to quickly skip impossible pairs.
///
/// Example logic: "Should static ground objects check the moving-objects bucket?"
/// Answer: Yes, because a falling block might land on the ground.
pub const ObjectVsBroadPhaseLayerFilter = extern struct {
    interface: zphy.ObjectVsBroadPhaseLayerFilter = .init(@This()),

    /// Returns true if objects of `layer1` should test against broad phase `layer2`
    pub fn shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.c) bool {
        return switch (layer1) {
            // Static objects only need to check against moving objects
            // (no point checking static vs static - neither can move!)
            layers.object_layers.non_moving => layer2 == layers.broad_phase_layers.moving,
            // Moving objects check against everything (ground + other moving)
            layers.object_layers.moving => true,
            else => unreachable,
        };
    }
};

/// Decides if two specific Object Layers should collide with each other.
/// This is the SECOND filter - runs during narrow phase on pairs that passed broad phase.
///
/// This is where you'd add game-specific rules like:
/// - Bullets don't collide with the player who shot them
/// - Teammates don't collide with each other
/// - Ghosts pass through walls
pub const ObjectLayerPairFilter = extern struct {
    interface: zphy.ObjectLayerPairFilter = .init(@This()),

    /// Returns true if objects of `object1` layer should collide with `object2` layer
    pub fn shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.c) bool {
        return switch (object1) {
            // Static objects only collide with moving objects
            layers.object_layers.non_moving => object2 == layers.object_layers.moving,
            // Moving objects collide with everything
            layers.object_layers.moving => true,
            else => unreachable,
        };
    }
};
