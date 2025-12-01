//! rlImGui backend bindings - isolates C/C++ interop from the rest of the debug module.
//!
//! This module wraps the rlImGui C API which bridges Dear ImGui to Raylib's rendering.
//! rlImGui handles:
//! - Creating/destroying the ImGui context
//! - Forwarding Raylib input (mouse, keyboard) to ImGui
//! - Rendering ImGui draw lists using Raylib's GPU commands
//!
//! Usage:
//!   backend.setup(true);           // Once at startup (after rl.initWindow)
//!   defer backend.shutdown();
//!   // In game loop:
//!   backend.begin();               // Start ImGui frame
//!   // ... zgui calls here ...
//!   backend.endFrame();            // Render ImGui

const c = @cImport({
    // Disable Font Awesome to match our build.zig configuration
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});

/// Initialize rlImGui and create the ImGui context.
/// Call AFTER rl.initWindow() but BEFORE any zgui calls.
///
/// Parameters:
///   dark_theme: true for dark theme, false for light theme
pub fn setup(dark_theme: bool) void {
    c.rlImGuiSetup(dark_theme);
}

/// Shutdown rlImGui and destroy the ImGui context.
/// Call AFTER all zgui usage is complete, typically via defer.
pub fn shutdown() void {
    c.rlImGuiShutdown();
}

/// Begin a new ImGui frame.
/// Call AFTER rl.beginDrawing() but BEFORE any zgui widget calls.
/// This forwards Raylib input state to ImGui and calls ImGui::NewFrame().
pub fn begin() void {
    c.rlImGuiBegin();
}

/// End the ImGui frame and render.
/// Call AFTER all zgui widget calls, BEFORE rl.endDrawing().
/// This calls ImGui::Render() and draws the result using Raylib.
pub fn endFrame() void {
    c.rlImGuiEnd();
}
