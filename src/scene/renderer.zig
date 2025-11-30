//! Renderer - Draws the scene using Raylib with lighting.
//!
//! The renderer only draws - it does not own animation state.
//! Animation is game logic and belongs in the Scene.
//!
//! Uses meshes with transform matrices for proper rotation support.
//! Mesh + Material + Shader created once, reused for all objects.
//!
//! Lighting flow:
//! 1. Load lighting shader (vertex + fragment GLSL)
//! 2. Assign shader to materials
//! 3. Each frame: update light uniforms, then draw meshes
//! 4. GPU runs shader per-pixel to calculate lighting

const std = @import("std");
const rl = @import("raylib");
const Scene = @import("mod.zig").Scene;
const ground_def = @import("../entities/ground.zig");
const cube_def = @import("../entities/cube.zig");
const lights = @import("../lighting/mod.zig");
const characters = @import("../characters/mod.zig");

/// Renderer holds GPU resources (meshes, materials, shaders) that persist across frames.
pub const Renderer = struct {
    // Meshes (vertex data on GPU)
    cube_mesh: rl.Mesh,
    ground_mesh: rl.Mesh,
    capsule_mesh: rl.Mesh,

    // Materials (shader + textures + colors)
    cube_material: rl.Material,
    ground_material: rl.Material,
    player_material: rl.Material,
    npc_material: rl.Material,

    // Shader (shared by all lit materials)
    shader: rl.Shader,

    /// Initialize renderer resources. Call once at startup.
    /// Returns the renderer. Use getShader() to initialize lighting separately.
    pub fn init() !Renderer {
        // === Load the lighting shader ===
        // Vertex shader: transforms vertices, passes normals to fragment shader
        // Fragment shader: calculates per-pixel lighting
        const shader = try rl.loadShader(
            "src/lighting/shaders/lighting.vs",
            "src/lighting/shaders/lighting.fs",
        );

        // === Create cube mesh and material ===
        const cube_mesh = rl.genMeshCube(cube_def.SIZE, cube_def.SIZE, cube_def.SIZE);
        var cube_material = try rl.loadMaterialDefault();
        cube_material.shader = shader; // Use lighting shader!
        cube_material.maps[@intFromEnum(rl.MaterialMapIndex.albedo)].color = rl.Color.red;

        // === Create ground mesh and material ===
        const ground_mesh = rl.genMeshCube(ground_def.WIDTH, ground_def.HEIGHT, ground_def.DEPTH);
        var ground_material = try rl.loadMaterialDefault();
        ground_material.shader = shader; // Use lighting shader!
        ground_material.maps[@intFromEnum(rl.MaterialMapIndex.albedo)].color = rl.Color.init(80, 80, 80, 255);

        // === Create capsule mesh and materials for characters ===
        // Use cylinder as placeholder (raylib-zig doesn't have genMeshCapsule)
        // Total height = 2 * half_height + 2 * radius = 2 * 0.6 + 2 * 0.3 = 1.8m
        const capsule_height = 2 * characters.CAPSULE_HALF_HEIGHT + 2 * characters.CAPSULE_RADIUS;
        const capsule_mesh = rl.genMeshCylinder(characters.CAPSULE_RADIUS, capsule_height, 16);

        var player_material = try rl.loadMaterialDefault();
        player_material.shader = shader;
        player_material.maps[@intFromEnum(rl.MaterialMapIndex.albedo)].color = rl.Color.init(50, 200, 50, 255); // Green

        var npc_material = try rl.loadMaterialDefault();
        npc_material.shader = shader;
        npc_material.maps[@intFromEnum(rl.MaterialMapIndex.albedo)].color = rl.Color.init(50, 100, 200, 255); // Blue

        return .{
            .cube_mesh = cube_mesh,
            .ground_mesh = ground_mesh,
            .capsule_mesh = capsule_mesh,
            .cube_material = cube_material,
            .ground_material = ground_material,
            .player_material = player_material,
            .npc_material = npc_material,
            .shader = shader,
        };
    }

    /// Get the shader for external systems (e.g., lighting setup).
    pub fn getShader(self: *const Renderer) rl.Shader {
        return self.shader;
    }

    /// Clean up GPU resources.
    pub fn deinit(self: *Renderer) void {
        // Clear shader references from materials before unloading
        // (prevents double-free since all materials share the same shader)
        self.cube_material.shader = rl.Shader{ .id = 0, .locs = null };
        self.ground_material.shader = rl.Shader{ .id = 0, .locs = null };
        self.player_material.shader = rl.Shader{ .id = 0, .locs = null };
        self.npc_material.shader = rl.Shader{ .id = 0, .locs = null };

        rl.unloadMaterial(self.cube_material);
        rl.unloadMaterial(self.ground_material);
        rl.unloadMaterial(self.player_material);
        rl.unloadMaterial(self.npc_material);
        rl.unloadMesh(self.cube_mesh);
        rl.unloadMesh(self.ground_mesh);
        rl.unloadMesh(self.capsule_mesh);
        rl.unloadShader(self.shader);
    }

    /// Prepare lighting for GPU. Call once per frame before drawing.
    /// This sends camera position and light data to the shader.
    pub fn prepareLighting(_: *Renderer, lighting: *lights.Lights, camera: rl.Camera3D) void {
        lighting.update(camera);
    }

    /// Draw the entire scene.
    /// Call this between beginMode3D() and endMode3D().
    pub fn draw(self: *Renderer, scene: *Scene, lighting: *const lights.Lights) void {
        self.drawGround();
        self.drawCubes(scene);
        self.drawCharacters(scene);
        drawLightDebug(lighting);
    }

    /// Draw visible spheres at point light positions (for debugging/visualization).
    fn drawLightDebug(lighting: *const lights.Lights) void {
        const render_data = lighting.getRenderData();

        for (render_data.positions, render_data.types, render_data.colors) |pos, light_type, color| {
            // Only draw spheres for point lights (not directional)
            if (light_type == .point) {
                // Draw a small glowing sphere at the light position
                const position = rl.Vector3.init(pos[0], pos[1], pos[2]);
                rl.drawSphere(position, 0.15, lights.normalizedToColor(color));
            }
        }
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

    /// Draw the ground plane with lighting.
    fn drawGround(self: *Renderer) void {
        const pos = ground_def.POSITION;
        const transform = rl.Matrix.translate(pos[0], pos[1], pos[2]);
        rl.drawMesh(self.ground_mesh, self.ground_material, transform);
    }

    /// Draw all characters (player and NPCs) as capsules.
    fn drawCharacters(self: *Renderer, scene: *Scene) void {
        const render_data = scene.characters.getRenderData();

        for (render_data.positions, render_data.rotations, render_data.types) |pos, rot, char_type| {
            // Build transform matrix: translation * rotation
            const translation = rl.Matrix.translate(pos[0], pos[1], pos[2]);
            const rotation = rl.Quaternion.init(rot[0], rot[1], rot[2], rot[3]).toMatrix();
            const transform = rotation.multiply(translation);

            // Use different material based on character type
            const material = if (char_type == .player) self.player_material else self.npc_material;
            rl.drawMesh(self.capsule_mesh, material, transform);
        }
    }
};
