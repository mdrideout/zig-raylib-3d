const std = @import("std");
const zig_3d_game = @import("zig_3d_game");
const rl = @import("raylib");
const physics = @import("physics/mod.zig");
const Scene = @import("scene/mod.zig").Scene;
const Renderer = @import("scene/renderer.zig").Renderer;
const lighting = @import("lighting/mod.zig");
const characters = @import("characters/mod.zig");
const camera_mod = @import("camera/mod.zig");

/// Game modes - determines how input is handled
const GameState = enum {
    menu, // Show mode selection, mouse free
    free_camera, // Original behavior - WASD moves camera
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

    // Lock the game to 60 frames per second so it doesn't melt your CPU
    rl.setTargetFPS(60);

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
    // Prevent ESC from closing the game immediately (so we can use it to toggle mouse)
    rl.setExitKey(.null);

    // Game state - start in menu
    var game_state: GameState = .menu;
    var entities_spawned: bool = false;

    // === RENDER LOOP ===============================================================
    while (!rl.windowShouldClose()) {
        // === Update Phase (Calculate physics, move camera, read inputs) ============
        const delta_time = rl.getFrameTime();

        // === State-based Input Handling ===
        switch (game_state) {
            .menu => {
                // Menu input - select mode with keyboard 1 or 2
                if (rl.isKeyPressed(.one)) {
                    if (!entities_spawned) {
                        try scene.spawnEntities();
                        entities_spawned = true;
                    }
                    game_state = .free_camera;
                    rl.disableCursor();
                }
                if (rl.isKeyPressed(.two)) {
                    if (!entities_spawned) {
                        try scene.spawnEntities();
                        entities_spawned = true;
                    }
                    game_state = .player_control;
                    rl.disableCursor();
                }
            },
            .free_camera => {
                // ESC returns to menu
                if (rl.isKeyPressed(.escape)) {
                    game_state = .menu;
                    rl.enableCursor();
                } else {
                    // Free camera mode - use raylib's built-in free camera
                    camera.mode = .free;
                    camera.update(null);
                }
            },
            .player_control => {
                // ESC returns to menu
                if (rl.isKeyPressed(.escape)) {
                    game_state = .menu;
                    rl.enableCursor();
                } else {
                    // Orbit camera mode - mouse controls camera orbit
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
                }
            },
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

        // Draw menu overlay or mode indicator
        switch (game_state) {
            .menu => drawMenu(),
            .free_camera => rl.drawText("Mode: FREE CAMERA (ESC for menu)", 10, 30, 20, rl.Color.white),
            .player_control => rl.drawText("Mode: PLAYER CONTROL (ESC for menu)", 10, 30, 20, rl.Color.white),
        }
    }
}

/// Draw the mode selection menu with semi-transparent overlay.
fn drawMenu() void {
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Semi-transparent overlay over 3D scene
    rl.drawRectangle(0, 0, screen_width, screen_height, rl.Color.init(0, 0, 0, 180));

    // Title
    const title = "SELECT MODE";
    const title_width = rl.measureText(title, 40);
    rl.drawText(title, @divFloor(screen_width - title_width, 2), 150, 40, rl.Color.white);

    // Options - clarify these are keyboard keys
    rl.drawText("Press 1: Free Camera - Fly around freely", 100, 250, 24, rl.Color.green);
    rl.drawText("Press 2: Player Control - Move the character", 100, 290, 24, rl.Color.green);

    // Instructions
    rl.drawText("Press ESC anytime to return to this menu", 100, 400, 18, rl.Color.gray);
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
