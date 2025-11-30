//! Lighting system - manages light sources and GPU shader communication.
//!
//! This module owns everything lighting-related:
//! - Light data management (SoA layout via MultiArrayList)
//! - Light animation (OrbitingLight)
//! - Shaders (GLSL files co-located in shaders/)
//!
//! Architecture:
//! - LightData: hot data that changes during gameplay (position, color, etc.)
//! - UniformLocs: cold data set once at light creation (shader uniform handles)
//!
//! Key concepts:
//! - Lights live on the CPU as SoA arrays
//! - Each frame, we send light data to the shader via SetShaderValue
//! - The shader receives this data as uniform arrays
//! - Fragment shader does per-pixel lighting calculations

const std = @import("std");
const rl = @import("raylib");

// Re-export animation for convenience
pub const OrbitingLight = @import("animation.zig").OrbitingLight;

/// Maximum lights supported (must match MAX_LIGHTS in shader)
pub const MAX_LIGHTS = 4;

/// Light types (must match shader #defines)
pub const LightType = enum(i32) {
    directional = 0, // Sun: parallel rays, no distance falloff
    point = 1, // Lamp: radiates from position, has falloff
};

/// Hot data - changes during gameplay.
/// Stored in MultiArrayList for SoA layout.
const LightData = struct {
    light_type: LightType,
    enabled: bool,
    position: [3]f32,
    target: [3]f32,
    color: [4]f32, // Normalized 0-1 (r, g, b, a)
};

/// Cold data - set once at light creation, never changes.
/// Stored in fixed array indexed by light index.
const UniformLocs = struct {
    enabled_loc: c_int,
    type_loc: c_int,
    position_loc: c_int,
    target_loc: c_int,
    color_loc: c_int,
};

/// Manages all lights in the scene using SoA layout.
pub const Lights = struct {
    data: std.MultiArrayList(LightData),
    uniform_locs: [MAX_LIGHTS]UniformLocs,
    allocator: std.mem.Allocator,
    shader: rl.Shader,
    ambient_loc: c_int,
    view_pos_loc: c_int,

    /// Initialize the lighting system with a shader.
    pub fn init(allocator: std.mem.Allocator, shader: rl.Shader) Lights {
        // Get uniform locations for global lighting properties
        const ambient_loc = rl.getShaderLocation(shader, "ambient");
        const view_pos_loc = rl.getShaderLocation(shader, "viewPos");

        // Set up the shader's view position location for Raylib's internal use
        shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = view_pos_loc;

        return .{
            .data = .empty,
            .uniform_locs = undefined, // Will be set when lights are added
            .allocator = allocator,
            .shader = shader,
            .ambient_loc = ambient_loc,
            .view_pos_loc = view_pos_loc,
        };
    }

    /// Clean up resources.
    pub fn deinit(self: *Lights) void {
        self.data.deinit(self.allocator);
    }

    /// Set the ambient light level (minimum light everywhere).
    /// Values typically 0.1-0.3 for subtle ambient.
    pub fn setAmbient(self: *Lights, r: f32, g: f32, b: f32) void {
        const ambient = [4]f32{ r, g, b, 1.0 };
        rl.setShaderValue(self.shader, self.ambient_loc, &ambient, .vec4);
    }

    /// Add a light to the scene. Returns the light index, or null if full.
    pub fn add(
        self: *Lights,
        light_type: LightType,
        position: [3]f32,
        target: [3]f32,
        color: [4]f32,
    ) ?usize {
        if (self.data.len >= MAX_LIGHTS) return null;

        const index = self.data.len;

        // Build uniform names for this light index
        // Format: "lights[0].enabled", "lights[0].type", etc.
        var enabled_name: [32]u8 = undefined;
        var type_name: [32]u8 = undefined;
        var position_name: [32]u8 = undefined;
        var target_name: [32]u8 = undefined;
        var color_name: [32]u8 = undefined;

        const enabled_str = std.fmt.bufPrintZ(&enabled_name, "lights[{}].enabled", .{index}) catch unreachable;
        const type_str = std.fmt.bufPrintZ(&type_name, "lights[{}].type", .{index}) catch unreachable;
        const position_str = std.fmt.bufPrintZ(&position_name, "lights[{}].position", .{index}) catch unreachable;
        const target_str = std.fmt.bufPrintZ(&target_name, "lights[{}].target", .{index}) catch unreachable;
        const color_str = std.fmt.bufPrintZ(&color_name, "lights[{}].color", .{index}) catch unreachable;

        // Store uniform locations (cold data)
        self.uniform_locs[index] = .{
            .enabled_loc = rl.getShaderLocation(self.shader, enabled_str),
            .type_loc = rl.getShaderLocation(self.shader, type_str),
            .position_loc = rl.getShaderLocation(self.shader, position_str),
            .target_loc = rl.getShaderLocation(self.shader, target_str),
            .color_loc = rl.getShaderLocation(self.shader, color_str),
        };

        // Append hot data to MultiArrayList
        self.data.append(self.allocator, .{
            .light_type = light_type,
            .enabled = true,
            .position = position,
            .target = target,
            .color = color,
        }) catch return null;

        // Send initial values to shader
        self.updateShaderValues(index);

        return index;
    }

    /// Convenience: Add a directional light (sun).
    pub fn addDirectional(self: *Lights, position: [3]f32, target: [3]f32, color: rl.Color) ?usize {
        return self.add(.directional, position, target, colorToNormalized(color));
    }

    /// Convenience: Add a point light.
    pub fn addPoint(self: *Lights, position: [3]f32, color: rl.Color) ?usize {
        return self.add(.point, position, .{ 0, 0, 0 }, colorToNormalized(color));
    }

    /// Update all lights in the shader. Call once per frame.
    pub fn update(self: *Lights, camera: rl.Camera3D) void {
        // Update camera position for specular calculations
        const cam_pos = [3]f32{ camera.position.x, camera.position.y, camera.position.z };
        rl.setShaderValue(self.shader, self.view_pos_loc, &cam_pos, .vec3);

        // Update all active lights
        for (0..self.data.len) |i| {
            self.updateShaderValues(i);
        }
    }

    /// Send a single light's data to the GPU.
    fn updateShaderValues(self: *Lights, index: usize) void {
        const slice = self.data.slice();
        const locs = self.uniform_locs[index];

        // Enabled
        const enabled_int: c_int = if (slice.items(.enabled)[index]) 1 else 0;
        rl.setShaderValue(self.shader, locs.enabled_loc, &enabled_int, .int);

        // Light type
        const type_int: c_int = @intFromEnum(slice.items(.light_type)[index]);
        rl.setShaderValue(self.shader, locs.type_loc, &type_int, .int);

        // Position
        rl.setShaderValue(self.shader, locs.position_loc, &slice.items(.position)[index], .vec3);

        // Target
        rl.setShaderValue(self.shader, locs.target_loc, &slice.items(.target)[index], .vec3);

        // Color
        rl.setShaderValue(self.shader, locs.color_loc, &slice.items(.color)[index], .vec4);
    }

    /// Get mutable access to a light's position for animation.
    pub fn getPosition(self: *Lights, index: usize) ?*[3]f32 {
        if (index >= self.data.len) return null;
        return &self.data.slice().items(.position)[index];
    }

    /// Get light type at index.
    pub fn getLightType(self: *const Lights, index: usize) ?LightType {
        if (index >= self.data.len) return null;
        return self.data.slice().items(.light_type)[index];
    }

    /// Get color at index.
    pub fn getColor(self: *const Lights, index: usize) ?[4]f32 {
        if (index >= self.data.len) return null;
        return self.data.slice().items(.color)[index];
    }

    /// Number of lights.
    pub fn count(self: *const Lights) usize {
        return self.data.len;
    }

    /// Get slices for rendering (positions, colors, types).
    pub fn getRenderData(self: *const Lights) struct {
        positions: [][3]f32,
        colors: [][4]f32,
        types: []LightType,
    } {
        const slice = self.data.slice();
        return .{
            .positions = slice.items(.position),
            .colors = slice.items(.color),
            .types = slice.items(.light_type),
        };
    }
};

/// Convert rl.Color (0-255) to normalized [4]f32 (0-1).
fn colorToNormalized(color: rl.Color) [4]f32 {
    return .{
        @as(f32, @floatFromInt(color.r)) / 255.0,
        @as(f32, @floatFromInt(color.g)) / 255.0,
        @as(f32, @floatFromInt(color.b)) / 255.0,
        @as(f32, @floatFromInt(color.a)) / 255.0,
    };
}

/// Convert normalized [4]f32 (0-1) to rl.Color (0-255).
pub fn normalizedToColor(normalized: [4]f32) rl.Color {
    return rl.Color.init(
        @intFromFloat(normalized[0] * 255.0),
        @intFromFloat(normalized[1] * 255.0),
        @intFromFloat(normalized[2] * 255.0),
        @intFromFloat(normalized[3] * 255.0),
    );
}
