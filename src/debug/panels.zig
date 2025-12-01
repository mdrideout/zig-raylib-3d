//! Panel registration system - game-agnostic interface for debug panels.
//!
//! This module provides a way for game systems to register debug panels without
//! the debug module needing to know about game-specific types. Panels are
//! registered with a callback function and optional context pointer.
//!
//! The registration pattern uses type-erasure: game systems provide a typed
//! callback, which gets cast to a generic function pointer for storage.
//!
//! Example usage:
//!   // In lighting module:
//!   pub fn drawDebugPanel(self: *Lights) void {
//!       zgui.text("Light count: {d}", .{self.data.len});
//!   }
//!
//!   // In main.zig:
//!   try registry.register(Lights, &lights, "Lighting", "Rendering", Lights.drawDebugPanel);

const std = @import("std");
const zgui = @import("zgui");

/// Type-erased callback signature for debug panels.
/// The ctx pointer is cast back to the original type in the callback.
pub const PanelFn = *const fn (ctx: ?*anyopaque) void;

/// Metadata for a registered debug panel.
pub const Panel = struct {
    /// Display name (also used as ImGui window title)
    name: [:0]const u8,
    /// Category for grouping in menu (e.g., "Rendering", "Physics", "System")
    category: [:0]const u8,
    /// Callback to draw panel contents
    draw_fn: PanelFn,
    /// Type-erased context pointer (null for static panels)
    ctx: ?*anyopaque,
    /// Whether this panel is currently visible
    enabled: bool,
};

/// Registry for debug panels.
/// Stores panels and provides iteration for drawing.
pub const PanelRegistry = struct {
    panels: std.ArrayList(Panel),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PanelRegistry {
        return .{
            .panels = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PanelRegistry) void {
        self.panels.deinit(self.allocator);
    }

    /// Register a debug panel with typed context.
    /// The draw function receives a pointer to the context type.
    ///
    /// Example:
    ///   try registry.register(Lights, &lights, "Lighting", "Rendering", Lights.drawDebugPanel);
    pub fn register(
        self: *PanelRegistry,
        comptime T: type,
        ctx: *T,
        name: [:0]const u8,
        category: [:0]const u8,
        comptime draw_fn: *const fn (*T) void,
    ) !void {
        // Wrap the typed function to match PanelFn signature
        const wrapper = struct {
            fn call(raw_ctx: ?*anyopaque) void {
                const typed_ctx: *T = @ptrCast(@alignCast(raw_ctx.?));
                draw_fn(typed_ctx);
            }
        };

        try self.panels.append(self.allocator, .{
            .name = name,
            .category = category,
            .draw_fn = wrapper.call,
            .ctx = ctx,
            .enabled = false, // Panels start hidden
        });
    }

    /// Register a panel without context (for static/global panels).
    ///
    /// Example:
    ///   try registry.registerStatic("Performance", "System", drawPerformancePanel);
    pub fn registerStatic(
        self: *PanelRegistry,
        name: [:0]const u8,
        category: [:0]const u8,
        draw_fn: PanelFn,
    ) !void {
        try self.panels.append(self.allocator, .{
            .name = name,
            .category = category,
            .draw_fn = draw_fn,
            .ctx = null,
            .enabled = false,
        });
    }

    /// Draw all enabled panels.
    /// Each panel is drawn in its own ImGui window.
    pub fn drawAll(self: *PanelRegistry) void {
        for (self.panels.items) |*panel| {
            if (panel.enabled) {
                // The window can be closed via the X button, which sets enabled to false
                if (zgui.begin(panel.name, .{ .popen = &panel.enabled, .flags = .{} })) {
                    panel.draw_fn(panel.ctx);
                }
                zgui.end();
            }
        }
    }

    /// Draw the debug menu bar for panel selection.
    /// Shows a "Debug Panels" menu with toggles for each registered panel.
    pub fn drawMenu(self: *PanelRegistry) void {
        if (zgui.beginMainMenuBar()) {
            if (zgui.beginMenu("Debug Panels", true)) {
                for (self.panels.items) |*panel| {
                    if (zgui.menuItem(panel.name, .{ .selected = panel.enabled })) {
                        panel.enabled = !panel.enabled;
                    }
                }
                zgui.endMenu();
            }
            zgui.endMainMenuBar();
        }
    }

    /// Toggle a panel by name. Returns true if panel was found.
    pub fn toggle(self: *PanelRegistry, name: [:0]const u8) bool {
        for (self.panels.items) |*panel| {
            if (std.mem.eql(u8, panel.name, name)) {
                panel.enabled = !panel.enabled;
                return true;
            }
        }
        return false;
    }
};
