//! Built-in debug panels - game-agnostic utilities.
//!
//! These panels provide system-level debugging information that doesn't
//! depend on any game-specific types. They're automatically registered
//! when the debug system initializes.

const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");
const panels = @import("panels.zig");

/// Register all built-in panels with the registry.
pub fn registerAll(registry: *panels.PanelRegistry) !void {
    try registry.registerStatic("Performance", "System", drawPerformance);
    try registry.registerStatic("ImGui Demo", "System", drawDemo);
}

/// Performance panel - FPS, frame time, and basic system info.
fn drawPerformance(_: ?*anyopaque) void {
    const fps = rl.getFPS();
    const frame_time = rl.getFrameTime() * 1000.0; // Convert to ms

    zgui.text("FPS: {d}", .{fps});
    zgui.text("Frame Time: {d:.2} ms", .{frame_time});

    zgui.separator();

    // Frame time graph would go here with ImPlot
    // For now, just show target info
    zgui.text("Target: 120 FPS ({d:.2} ms)", .{1000.0 / 120.0});

    if (fps < 110) {
        zgui.textColored(.{ 1.0, 0.3, 0.3, 1.0 }, "Warning: Below target FPS", .{});
    }
}

/// ImGui Demo window - useful for exploring available widgets.
fn drawDemo(_: ?*anyopaque) void {
    zgui.text("Open the demo window to explore ImGui features.", .{});
    zgui.text("This is useful for learning what widgets are available.", .{});

    // We can't easily show the demo window from here since it needs
    // to be called at the top level. Instead, we'll add a flag in Debug.
    zgui.textColored(.{ 0.7, 0.7, 0.7, 1.0 }, "(Demo window controlled via Debug.show_demo)", .{});
}
