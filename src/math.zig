//! Math utilities for the game.

const std = @import("std");

/// Generate a random rotation quaternion (uniformly distributed).
/// Uses axis-angle: pick random axis on sphere, random angle, convert to quaternion.
pub fn randomRotation(rng: std.Random) [4]f32 {
    // Random axis (uniformly distributed on unit sphere)
    const theta = rng.float(f32) * std.math.pi * 2.0; // azimuth [0, 2π]
    const phi = std.math.acos(1.0 - 2.0 * rng.float(f32)); // polar (uniform on sphere)
    const ax = @sin(phi) * @cos(theta);
    const ay = @sin(phi) * @sin(theta);
    const az = @cos(phi);

    // Random angle [0, 2π]
    const angle = rng.float(f32) * std.math.pi * 2.0;

    // Axis-angle to quaternion: q = (sin(a/2)*axis, cos(a/2))
    const half = angle / 2.0;
    const s = @sin(half);
    return .{ ax * s, ay * s, az * s, @cos(half) };
}
