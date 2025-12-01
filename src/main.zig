//! Main entry point for the Zig 3D Game.
//!
//! Implements **The Canonical Game Loop** (Fixed Timestep with Interpolation).
//! This is the same architecture used by Unity, Unreal, and Godot.
//! See INPUT_SYSTEM_PLAN.md for detailed documentation.
//!
//! ## The Canonical Game Loop
//!
//! ```
//! ┌─────────────────────────────────────────────────────────────┐
//! │ Phase 1: INPUT PUMP (Per-Frame / Uncapped)                  │
//! │ - Drains OS events, latches actions to the Input Buffer.    │
//! ├─────────────────────────────────────────────────────────────┤
//! │ Phase 2: SIMULATION TICK (Fixed 120Hz)                      │
//! │ - The "Authority." Runs physics, gameplay logic, & consume. │
//! ├─────────────────────────────────────────────────────────────┤
//! │ Phase 3: PRESENTATION (Interpolated)                        │
//! │ - Renders the "Visual State" blended between two ticks.     │
//! └─────────────────────────────────────────────────────────────┘
//! ```

const std = @import("std");
const zig_3d_game = @import("zig_3d_game");
const rl = @import("raylib");

// Game systems
const physics = @import("physics/mod.zig");
const Scene = @import("scene/mod.zig").Scene;
const Renderer = @import("scene/renderer.zig").Renderer;
const lighting = @import("lighting/mod.zig");
const characters = @import("characters/mod.zig");
const camera_mod = @import("camera/mod.zig");
const debug = @import("debug/mod.zig");

// New systems for fixed timestep
const time = @import("time/mod.zig");
const input = @import("input/mod.zig");

/// Game modes - determines how camera/movement input is handled
const GameMode = enum {
    free_camera, // WASD moves camera, mouse controls look
    player_control, // WASD moves player, camera follows
};

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try zig_3d_game.bufferedPrint();

    // Allocator setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(800, 600, "My Zig Game");
    defer rl.closeWindow();

    // Debug UI setup - must be after window init, before other systems
    // Press F3 to toggle debug overlay
    var debug_ui = try debug.Debug.init(allocator);
    defer debug_ui.deinit();

    // Raylib's internal frame limiter - caps render rate
    // The fixed timestep handles physics determinism; this just prevents GPU meltdown
    rl.setTargetFPS(120);

    // Camera setup - uses camera module for mode switching
    var camera = camera_mod.Camera.init();

    // Physics setup
    var physics_world = try physics.PhysicsWorld.create(allocator);
    defer physics_world.destroy();

    // Renderer setup - creates meshes and materials for drawing
    var game_renderer = try Renderer.init();
    defer game_renderer.deinit();

    // Lighting setup - created after renderer to use its shader
    var lights = lighting.Lights.init(allocator, game_renderer.getShader());
    defer lights.deinit();
    lights.setAmbient(0.15, 0.15, 0.15);

    // Add a sun light - warm directional light from above
    _ = lights.addDirectional(
        .{ 10.0, 20.0, 10.0 }, // Position (high up, to the side)
        .{ 0.0, 0.0, 0.0 }, // Target (center of scene)
        rl.Color.init(255, 250, 230, 255), // Warm white sunlight
    );

    // Add a point light that will orbit around the scene
    const point_light_index = lights.addPoint(
        .{ 8.0, 2.0, 0.0 }, // Starting position (will be animated)
        rl.Color.init(150, 200, 255, 255), // Cool blue-white light
    );

    // Create orbiting light animation (owned by main, updated in game loop)
    var orbiting_light = if (point_light_index) |idx|
        lighting.OrbitingLight.init(idx)
    else
        null;

    // Scene setup - creates ground plane and initial objects
    var scene = try Scene.init(allocator, &physics_world);
    defer scene.deinit();

    // Config - Keys
    // Prevent ESC from closing the game immediately (so we can use it to free mouse)
    rl.setExitKey(.null);

    // Game state
    var game_mode: GameMode = .free_camera;
    var entities_spawned: bool = false;
    var cursor_captured: bool = false; // Whether mouse is captured for camera control

    // === NEW: Fixed timestep and input systems ===
    var game_clock = time.GameClock{};
    var input_buffer = input.InputActions{};

    // Click feedback gizmo state (for debugging input registration)
    var click_feedback_pos: ?[2]f32 = null;
    var click_feedback_time: f64 = 0;

    // === RENDER LOOP ===============================================================
    while (!rl.windowShouldClose()) {
        // =========================================================================
        // PHASE 1: INPUT PUMP (Per-Frame / Uncapped)
        // Drains OS events, latches actions to the Input Buffer.
        // =========================================================================

        // Start the frame timer and add delta to accumulator
        game_clock.beginFrame(rl.getFrameTime());

        // Collect input - latches triggers, updates continuous inputs
        input.collectInput(&input_buffer);

        // Update click feedback gizmo (for debugging - shows when clicks are registered)
        if (input_buffer.mouse_left_pressed or input_buffer.mouse_right_pressed) {
            const pos = rl.getMousePosition();
            click_feedback_pos = .{ pos.x, pos.y };
            click_feedback_time = rl.getTime();
        }

        // =========================================================================
        // HANDLE MODE SWITCHES (once per frame, not per physics tick)
        // These are UI-layer inputs that shouldn't fire multiple times per frame
        // =========================================================================

        // ESC frees the mouse for debug UI interaction
        if (input_buffer.release_cursor) {
            cursor_captured = false;
            rl.enableCursor();
        }

        // 1 key: Switch to free camera mode
        if (input_buffer.toggle_free_camera) {
            if (!entities_spawned) {
                try scene.spawnEntities();
                entities_spawned = true;
            }
            game_mode = .free_camera;
            cursor_captured = true;
            rl.disableCursor();
        }

        // 2 key: Switch to player control mode
        if (input_buffer.toggle_player_mode) {
            if (!entities_spawned) {
                try scene.spawnEntities();
                entities_spawned = true;
            }
            game_mode = .player_control;
            cursor_captured = true;
            rl.disableCursor();
        }

        // Consume mode inputs after handling (prevents re-firing)
        input_buffer.consumeModeInputs();

        // =========================================================================
        // PHASE 2: SIMULATION TICK (Fixed 120Hz)
        // The "Authority." Runs physics, gameplay logic, & consumes triggers.
        // =========================================================================

        // This loop runs 0, 1, or more times depending on accumulated time.
        // Each iteration uses FIXED_TIMESTEP for deterministic physics.
        while (game_clock.shouldStepLogic()) {
            const fixed_dt = time.GameClock.getFixedDeltaTime();

            // Store previous state for interpolation (BEFORE physics update)
            scene.storePreviousState();

            // Character movement - only when cursor captured and in player mode
            if (cursor_captured and game_mode == .player_control) {
                // Compute camera-relative movement from input buffer
                const move_dir = input.computeCameraRelativeMovement(&input_buffer, camera.getYaw());
                characters.controller.updatePlayer(&scene.characters, move_dir, camera.getYaw(), fixed_dt);
            }

            // Physics step with FIXED timestep (deterministic!)
            try physics_world.update(fixed_dt);

            // Sync entity positions from physics simulation
            scene.syncFromPhysics();

            // Consume gameplay triggers after physics processes them
            input_buffer.consumeTriggers();
        }

        // =========================================================================
        // PHASE 3: PRESENTATION (Interpolated)
        // Renders the "Visual State" blended between two ticks.
        // =========================================================================

        // Calculate interpolation alpha for smooth rendering
        // alpha: 0.0 = previous physics state, 1.0 = current physics state
        const alpha = game_clock.getInterpolationAlpha();

        // Camera update - MUST use interpolated player position to avoid jitter!
        // Without this, the camera would snap to the "future" physics state while
        // the player mesh renders at the interpolated "past" position = vibrating.
        if (cursor_captured) {
            switch (game_mode) {
                .free_camera => {
                    camera.mode = .free;
                    camera.update(null);
                },
                .player_control => {
                    camera.mode = .orbit;

                    // Get INTERPOLATED player position for camera target
                    // This prevents the "camera jitter" bug where camera and mesh are out of sync
                    const player_pos: ?[3]f32 = if (scene.characters.getPlayerIndex()) |idx|
                        scene.characters.getInterpolatedPosition(idx, alpha)
                    else
                        null;

                    camera.update(player_pos);
                },
            }
        }

        // Orbiting light is purely visual - use frame time, not fixed timestep
        if (orbiting_light) |*orbit| {
            orbit.update(&lights, game_clock.getFrameTime());
        }

        // =========================================================================
        // --- RENDER PASS (within Phase 3) ---
        // =========================================================================

        rl.beginDrawing();
        defer rl.endDrawing();

        // Debug UI frame management (F3 toggles visibility internally)
        // Pass input_buffer so latched mouse events are forwarded to ImGui
        debug_ui.beginFrame(&input_buffer);
        defer {
            debug_ui.endFrame();
            // Consume mouse inputs after ImGui has processed them
            input_buffer.consumeMouseInputs();
        }

        // Clear the previous frame (darker background for better contrast with lit objects)
        rl.clearBackground(rl.Color.init(40, 44, 52, 255)); // Dark gray-blue

        // Prepare lighting for GPU (send camera position and light data to shader)
        game_renderer.prepareLighting(&lights, camera.rl_camera);

        // Draw 3D scene
        // TODO: Pass alpha for interpolated rendering
        rl.beginMode3D(camera.rl_camera);
        game_renderer.draw(&scene, &lights);
        rl.endMode3D();

        // === Click feedback gizmo (debug - shows expanding circle on click) ===
        if (click_feedback_pos) |pos| {
            const click_age: f32 = @floatCast(rl.getTime() - click_feedback_time);
            if (click_age < 0.5) {
                const click_alpha: u8 = @intFromFloat((1.0 - click_age * 2.0) * 255.0);
                const radius: f32 = 10.0 + click_age * 60.0;
                rl.drawCircleLines(
                    @intFromFloat(pos[0]),
                    @intFromFloat(pos[1]),
                    radius,
                    rl.Color.init(0, 255, 0, click_alpha),
                );
            } else {
                click_feedback_pos = null;
            }
        }

        // === Draw 2D HUD =======================================================
        rl.drawFPS(10, 10);

        // Help text panel - smaller font with transparent background
        const help_x: i32 = 6;
        const help_y: i32 = 36;
        const font_size: i32 = 10;
        const line_height: i32 = 12;
        const padding: i32 = 4;
        const panel_width: i32 = 124;
        const panel_height: i32 = line_height * 4 + padding * 2;

        // Semi-transparent dark background for readability
        rl.drawRectangle(
            help_x - padding,
            help_y - padding,
            panel_width,
            panel_height,
            rl.Color.init(0, 0, 0, 160), // RGBA: black at ~63% opacity
        );

        // Mode indicators and labels
        const mode_indicator = if (game_mode == .free_camera) ">" else " ";
        const mode_indicator2 = if (game_mode == .player_control) ">" else " ";

        rl.drawText(mode_indicator, help_x, help_y, font_size, rl.Color.green);
        rl.drawText("[1] Free Camera", help_x + 8, help_y, font_size, if (game_mode == .free_camera) rl.Color.green else rl.Color.gray);

        rl.drawText(mode_indicator2, help_x, help_y + line_height, font_size, rl.Color.green);
        rl.drawText("[2] Player Control", help_x + 8, help_y + line_height, font_size, if (game_mode == .player_control) rl.Color.green else rl.Color.gray);

        rl.drawText("[Esc] Release Mouse", help_x + 8, help_y + line_height * 2, font_size, if (!cursor_captured) rl.Color.yellow else rl.Color.gray);
        rl.drawText("[F3] Debug UI", help_x + 8, help_y + line_height * 3, font_size, rl.Color.gray);

        // Draw debug UI last (on top of everything)
        debug_ui.draw();
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input_data: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input_data));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
