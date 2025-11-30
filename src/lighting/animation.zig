//! Light animation behaviors.
//!
//! Contains animation logic for lights. Animation is game logic
//! (how things change over time), not rendering (how things look).

const std = @import("std");
const lights = @import("mod.zig");

/// Animates a light in a circular orbit around the scene.
/// Self-contained: owns its animation state (angle, speed, etc.).
pub const OrbitingLight = struct {
    light_index: usize,
    angle: f32,
    radius: f32,
    height: f32,
    speed: f32, // Radians per second

    /// Create an orbiting light animation for the given light index.
    /// Uses sensible defaults: radius=8, height=2, speed=0.5 rad/s.
    pub fn init(light_index: usize) OrbitingLight {
        return .{
            .light_index = light_index,
            .angle = 0.0,
            .radius = 8.0,
            .height = 2.0,
            .speed = 0.5,
        };
    }

    /// Update the light position. Call once per frame.
    pub fn update(self: *OrbitingLight, lighting: *lights.Lights, delta_time: f32) void {
        if (lighting.getPosition(self.light_index)) |pos| {
            // Update angle
            self.angle += self.speed * delta_time;

            // Wrap angle to avoid floating point overflow after long runs
            if (self.angle > std.math.pi * 2.0) {
                self.angle -= std.math.pi * 2.0;
            }

            // Calculate new position on circular path
            pos[0] = self.radius * @cos(self.angle);
            pos[1] = self.height;
            pos[2] = self.radius * @sin(self.angle);
        }
    }
};
