const std = @import("std");
const zig_3d_game = @import("zig_3d_game");
const rl = @import("raylib");
const physics = @import("physics/mod.zig");
const Scene = @import("scene/mod.zig").Scene;
const Renderer = @import("scene/renderer.zig").Renderer;
const lighting = @import("lighting/mod.zig");
const characters = @import("characters/mod.zig");
const camera_mod = @import("camera/mod.zig");
const debug = @import("debug/mod.zig");

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

    // Lock the game to 60 frames per second so it doesn't melt your CPU
    // NOTE: If mouse clicks feel laggy, try increasing this or setting to 0 (unlimited)
    // This is a known Raylib issue on macOS: https://github.com/raysan5/raylib/issues/4749
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

    // Game state - start in free camera mode with cursor enabled for initial debug access
    var game_mode: GameMode = .free_camera;
    var entities_spawned: bool = false;
    var cursor_captured: bool = false; // Whether mouse is captured for camera control

    // === RENDER LOOP ===============================================================
    while (!rl.windowShouldClose()) {
        // === Update Phase (Calculate physics, move camera, read inputs) ============
        const delta_time = rl.getFrameTime();

        // === Global Input Handling ===
        // ESC frees the mouse for debug UI interaction
        if (rl.isKeyPressed(.escape)) {
            cursor_captured = false;
            rl.enableCursor();
        }

        // 1 key: Switch to free camera mode
        if (rl.isKeyPressed(.one)) {
            if (!entities_spawned) {
                try scene.spawnEntities();
                entities_spawned = true;
            }
            game_mode = .free_camera;
            cursor_captured = true;
            rl.disableCursor();
        }

        // 2 key: Switch to player control mode
        if (rl.isKeyPressed(.two)) {
            if (!entities_spawned) {
                try scene.spawnEntities();
                entities_spawned = true;
            }
            game_mode = .player_control;
            cursor_captured = true;
            rl.disableCursor();
        }

        // === Mode-based Camera/Movement Update ===
        // Only update camera when cursor is captured
        if (cursor_captured) {
            switch (game_mode) {
                .free_camera => {
                    camera.mode = .free;
                    camera.update(null);
                },
                .player_control => {
                    camera.mode = .orbit;

                    // Get player position for camera target
                    const player_pos: ?[3]f32 = if (scene.characters.getPlayerIndex()) |idx|
                        scene.characters.data.items(.position)[idx]
                    else
                        null;

                    camera.update(player_pos);

                    // Camera-relative movement using yaw angle
                    const input_dir = characters.movement.getInputDirectionFromYaw(camera.getYaw());
                    characters.controller.updatePlayer(&scene.characters, input_dir, camera.getYaw(), delta_time);
                },
            }
        }

        // Step physics simulation
        try physics_world.update(delta_time);

        // Sync entity positions from physics simulation
        scene.syncFromPhysics();

        // Update orbiting light animation
        if (orbiting_light) |*orbit| {
            orbit.update(&lights, delta_time);
        }

        // === Begin Drawing =========================================================
        rl.beginDrawing();
        defer rl.endDrawing();

        // Debug UI frame management (F3 toggles visibility)
        debug_ui.beginFrame();
        defer debug_ui.endFrame();

        // Clear the previous frame (darker background for better contrast with lit objects)
        rl.clearBackground(rl.Color.init(40, 44, 52, 255)); // Dark gray-blue

        // === Prepare Lighting for GPU ==============================================
        // Send camera position and light data to shader
        game_renderer.prepareLighting(&lights, camera.rl_camera);

        // === Draw 3D Things (always render scene) =================================
        rl.beginMode3D(camera.rl_camera);
        game_renderer.draw(&scene, &lights);
        rl.endMode3D();

        // === Draw 2D Things =======================================================
        rl.drawFPS(10, 10);

        // Always show minimal help text (non-blocking)
        const help_y: i32 = 30;
        const mode_indicator = if (game_mode == .free_camera) ">" else " ";
        const mode_indicator2 = if (game_mode == .player_control) ">" else " ";

        rl.drawText("[1] Free Camera", 10, help_y, 16, if (game_mode == .free_camera) rl.Color.green else rl.Color.gray);
        rl.drawText(mode_indicator, 2, help_y, 16, rl.Color.green);

        rl.drawText("[2] Player Control", 10, help_y + 18, 16, if (game_mode == .player_control) rl.Color.green else rl.Color.gray);
        rl.drawText(mode_indicator2, 2, help_y + 18, 16, rl.Color.green);

        rl.drawText("[Esc] Use Mouse", 10, help_y + 36, 16, if (!cursor_captured) rl.Color.yellow else rl.Color.gray);
        rl.drawText("[F3] Debug UI", 10, help_y + 54, 16, rl.Color.gray);

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
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
