//! Debug module - ImGui integration for Raylib via zgui + rlImGui.
//!
//! This module provides a debug overlay system for tool-first development.
//! It integrates Dear ImGui (via zgui) with Raylib (via rlImGui) to provide:
//! - Runtime parameter tuning via sliders, inputs, etc.
//! - Visual inspection of game state
//! - Performance monitoring
//!
//! Architecture:
//! - rlImGui owns the ImGui context and handles the Raylib backend
//! - zgui provides a Zig-idiomatic API for ImGui widgets
//! - Panels are registered by game systems via callbacks (decoupled design)
//!
//! Usage in main.zig:
//!   const debug = @import("debug/mod.zig");
//!
//!   var debug_ui = try debug.Debug.init(allocator);
//!   defer debug_ui.deinit();
//!
//!   // Register game system panels
//!   try debug_ui.registry.register(Lights, &lights, "Lighting", "Rendering", Lights.drawDebugPanel);
//!
//!   while (!rl.windowShouldClose()) {
//!       rl.beginDrawing();
//!       defer rl.endDrawing();
//!
//!       debug_ui.beginFrame();    // F3 toggles visibility
//!       defer debug_ui.endFrame();
//!
//!       // ... game rendering ...
//!
//!       debug_ui.draw();          // Draw ImGui panels (if visible)
//!   }

const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");
const input = @import("../input/mod.zig");

pub const backend = @import("backend.zig");
pub const panels = @import("panels.zig");
pub const builtin_panels = @import("builtin_panels.zig");

// Re-exports for convenience
pub const PanelRegistry = panels.PanelRegistry;
pub const PanelFn = panels.PanelFn;

/// Debug overlay system.
/// Manages ImGui lifecycle and panel visibility.
pub const Debug = struct {
    /// Panel registry - game systems register their debug panels here
    registry: PanelRegistry,
    /// Allocator used for zgui and panel storage
    allocator: std.mem.Allocator,
    /// Whether the debug overlay is visible (toggled with F3)
    visible: bool,
    /// Whether to show the ImGui demo window (useful for learning)
    show_demo: bool,

    /// Initialize the debug system.
    /// Call AFTER rl.initWindow() but BEFORE other game systems if they
    /// need to register panels during their init.
    pub fn init(allocator: std.mem.Allocator) !Debug {
        // rlImGui creates the ImGui context and sets up the Raylib backend
        backend.setup(true); // true = dark theme

        // zgui uses the existing context (doesn't create a new one)
        // This is critical - zgui.initNoContext just sets up zgui's internal buffers
        zgui.initNoContext(allocator);

        var debug_sys = Debug{
            .registry = PanelRegistry.init(allocator),
            .allocator = allocator,
            .visible = false,
            .show_demo = false,
        };

        // Register built-in panels (Performance, etc.)
        try builtin_panels.registerAll(&debug_sys.registry);

        return debug_sys;
    }

    /// Cleanup the debug system.
    /// Call via defer after init.
    pub fn deinit(self: *Debug) void {
        self.registry.deinit();
        zgui.deinitNoContext();
        backend.shutdown();
    }

    /// Begin a debug frame.
    /// Call AFTER rl.beginDrawing().
    /// Handles F3 toggle, forwards latched mouse events, and starts ImGui frame if visible.
    ///
    /// The input_buffer parameter contains latched mouse events collected early in the frame.
    /// We forward these to ImGui BEFORE rlImGuiBegin() to ensure fast clicks aren't missed.
    pub fn beginFrame(self: *Debug, input_buffer: *const input.InputActions) void {
        // Toggle debug overlay with F3
        if (rl.isKeyPressed(.f3)) {
            self.visible = !self.visible;
        }

        // Only start ImGui frame if visible
        if (self.visible) {
            // Forward latched mouse events BEFORE rlImGuiBegin()
            // This ensures ImGui sees clicks that happened earlier in the frame.
            // Without this, fast clicks can be missed because rlImGui uses single-frame detection.
            if (input_buffer.mouse_left_pressed) {
                zgui.io.addMouseButtonEvent(.left, true);
            }
            if (input_buffer.mouse_left_released) {
                zgui.io.addMouseButtonEvent(.left, false);
            }
            if (input_buffer.mouse_right_pressed) {
                zgui.io.addMouseButtonEvent(.right, true);
            }
            if (input_buffer.mouse_right_released) {
                zgui.io.addMouseButtonEvent(.right, false);
            }

            backend.begin();
        }
    }

    /// Draw debug UI.
    /// Call between beginFrame() and endFrame().
    /// Does nothing if debug overlay is hidden.
    pub fn draw(self: *Debug) void {
        if (!self.visible) return;

        // Draw the menu bar with panel toggles
        self.registry.drawMenu();

        // Draw all enabled panels
        self.registry.drawAll();

        // Optionally show the ImGui demo window
        if (self.show_demo) {
            zgui.showDemoWindow(&self.show_demo);
        }
    }

    /// End the debug frame.
    /// Call BEFORE rl.endDrawing().
    pub fn endFrame(self: *Debug) void {
        if (self.visible) {
            backend.endFrame();
        }
    }

    /// Check if ImGui wants to capture mouse input.
    /// Use this to prevent game input when interacting with debug UI.
    pub fn wantCaptureMouse(self: *const Debug) bool {
        if (!self.visible) return false;
        return zgui.getIO().want_capture_mouse;
    }

    /// Check if ImGui wants to capture keyboard input.
    /// Use this to prevent game input when typing in debug UI.
    pub fn wantCaptureKeyboard(self: *const Debug) bool {
        if (!self.visible) return false;
        return zgui.getIO().want_capture_keyboard;
    }
};
