const zphy = @import("zphysics");

/// Object Layers define WHAT TYPE of physics object something is.
/// Used to decide which objects should collide with which.
/// Example: You might not want bullets to collide with other bullets,
/// but you do want them to collide with enemies and walls.
pub const object_layers = struct {
    /// Static objects that never move (ground, walls, platforms)
    pub const non_moving: zphy.ObjectLayer = 0;
    /// Dynamic objects affected by physics (player, blocks, debris)
    pub const moving: zphy.ObjectLayer = 1;
    /// Total number of object layers (used for array sizing)
    pub const len: u32 = 2;
};

/// Broad Phase Layers are buckets for the FIRST, FAST collision check.
/// The physics engine uses bounding boxes to quickly group objects
/// and skip checking pairs that can't possibly collide.
/// Usually mirrors object_layers, but can be different for optimization.
pub const broad_phase_layers = struct {
    pub const non_moving: zphy.BroadPhaseLayer = 0;
    pub const moving: zphy.BroadPhaseLayer = 1;
    pub const len: u32 = 2;
};
