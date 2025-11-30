//! Renderer - Draws the scene using Raylib.
//!
//! Uses meshes with transform matrices for proper rotation support.
//! Mesh + Material created once, reused for all cubes.

const rl = @import("raylib");
const Scene = @import("mod.zig").Scene;
const ground_def = @import("../entities/ground.zig");
const cube_def = @import("../entities/cube.zig");

/// Renderer holds GPU resources (meshes, materials) that persist across frames.
pub const Renderer = struct {
    cube_mesh: rl.Mesh,
    cube_material: rl.Material,

    /// Initialize renderer resources. Call once at startup.
    pub fn init() !Renderer {
        const cube_mesh = rl.genMeshCube(cube_def.SIZE, cube_def.SIZE, cube_def.SIZE);
        const cube_material = try rl.loadMaterialDefault();

        // Set the cube color to red
        cube_material.maps[@intFromEnum(rl.MaterialMapIndex.albedo)].color = rl.Color.red;

        return .{
            .cube_mesh = cube_mesh,
            .cube_material = cube_material,
        };
    }

    /// Clean up GPU resources.
    pub fn deinit(self: *Renderer) void {
        rl.unloadMesh(self.cube_mesh);
        rl.unloadMaterial(self.cube_material);
    }

    /// Draw the entire scene.
    /// Call this between beginMode3D() and endMode3D().
    pub fn draw(self: *Renderer, scene: *Scene) void {
        drawGround();
        self.drawCubes(scene);
    }

    /// Draw all cubes with proper rotation using mesh + transform matrix.
    fn drawCubes(self: *Renderer, scene: *Scene) void {
        const render_data = scene.cubes.getRenderData();

        for (render_data.positions, render_data.rotations) |pos, rot| {
            // Build transform matrix: translation * rotation
            // Order matters! We translate first, then rotate around the cube's center
            const translation = rl.Matrix.translate(pos[0], pos[1], pos[2]);
            const rotation = rl.Quaternion.init(rot[0], rot[1], rot[2], rot[3]).toMatrix();
            const transform = rotation.multiply(translation);

            rl.drawMesh(self.cube_mesh, self.cube_material, transform);
        }
    }
};

/// Draw the ground plane.
fn drawGround() void {
    const pos = ground_def.POSITION;
    const size = rl.Vector3.init(ground_def.WIDTH, ground_def.HEIGHT, ground_def.DEPTH);
    const position = rl.Vector3.init(pos[0], pos[1], pos[2]);

    rl.drawCubeV(position, size, rl.Color.dark_gray);
    rl.drawCubeWiresV(position, size, rl.Color.black);
}
