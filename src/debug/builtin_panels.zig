//! Built-in debug panels - game-agnostic utilities.
//!
//! These panels provide system-level debugging information that doesn't
//! depend on any game-specific types. They're automatically registered
//! when the debug system initializes.

const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");
const panels = @import("panels.zig");

// =============================================================================
// Click Log - Module-level state for tracking mouse clicks
// =============================================================================

const MAX_CLICK_LOG = 20;

const ClickEntry = struct {
    x: f32,
    y: f32,
    button: enum { left, right },
    time: f64,
};

var click_log: [MAX_CLICK_LOG]ClickEntry = undefined;
var click_count: usize = 0;
var click_write_idx: usize = 0;

/// Record a mouse click. Called from mod.zig beginFrame().
pub fn recordClick(x: f32, y: f32, is_left: bool) void {
    click_log[click_write_idx] = .{
        .x = x,
        .y = y,
        .button = if (is_left) .left else .right,
        .time = rl.getTime(),
    };
    click_write_idx = (click_write_idx + 1) % MAX_CLICK_LOG;
    if (click_count < MAX_CLICK_LOG) click_count += 1;
}

/// Register all built-in panels with the registry.
pub fn registerAll(registry: *panels.PanelRegistry) !void {
    try registry.registerStatic("Performance", "System", drawPerformance);
    try registry.registerStatic("Click Log", "Input", drawClickLog);
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

/// Click Log panel - shows recent mouse clicks with timestamps.
fn drawClickLog(_: ?*anyopaque) void {
    const now = rl.getTime();

    if (click_count == 0) {
        zgui.textColored(.{ 0.5, 0.5, 0.5, 1.0 }, "No clicks recorded", .{});
        return;
    }

    // Show newest first
    var i: usize = 0;
    while (i < click_count) : (i += 1) {
        const idx = (click_write_idx + MAX_CLICK_LOG - 1 - i) % MAX_CLICK_LOG;
        const entry = click_log[idx];
        const age = now - entry.time;
        const btn = if (entry.button == .left) "LEFT" else "RIGHT";

        zgui.text("[{d:.1}s] {s} @ ({d:.0}, {d:.0})", .{ age, btn, entry.x, entry.y });
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
