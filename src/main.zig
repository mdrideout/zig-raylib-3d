const std = @import("std");
const zig_3d_game = @import("zig_3d_game");
const rl = @import("raylib");
const physics = @import("physics/mod.zig");
const Scene = @import("scene/mod.zig").Scene;
const Renderer = @import("scene/renderer.zig").Renderer;
const lighting = @import("lighting/mod.zig");

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

    // Define the camera
    var camera = rl.Camera3D{
        .position = rl.Vector3.init(0, 10, 10),
        .target = rl.Vector3.init(0, 0, 0), // Looking at the center
        .up = rl.Vector3.init(0, 1, 0), // Y is up
        .fovy = 45.0, // Field of view (how wide the lens is)
        .projection = .perspective, // Normal 3D view
    };

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

    // Vars
    var mouse_captured: bool = false;

    // === RENDER LOOP ===============================================================
    while (!rl.windowShouldClose()) {
        // === Update Phase (Calculate physics, move camera, read inputs) ============
        const delta_time = rl.getFrameTime();
        try physics_world.update(delta_time);

        // Sync entity positions from physics simulation
        scene.syncFromPhysics();

        // Update orbiting light animation
        if (orbiting_light) |*orbit| {
            orbit.update(&lights, delta_time);
        }

        // If we click inside the window, capture the mouse
        if (rl.isMouseButtonPressed(.left)) {
            rl.disableCursor();
            mouse_captured = true;
        }

        // If we press ESC, release the mouse
        if (rl.isKeyPressed(.escape)) {
            rl.enableCursor();
            mouse_captured = false;
        }

        // Update Camera ONLY if the mouse is captured
        if (mouse_captured) {
            rl.updateCamera(&camera, .free);
        }

        // === Begin Drawing =========================================================
        rl.beginDrawing();
        defer rl.endDrawing();

        // Clear the previous frame (darker background for better contrast with lit objects)
        rl.clearBackground(rl.Color.init(40, 44, 52, 255)); // Dark gray-blue

        // === Prepare Lighting for GPU ==============================================
        // Send camera position and light data to shader
        game_renderer.prepareLighting(&lights, camera);

        // === Draw 3D Things =======================================================
        rl.beginMode3D(camera);
        game_renderer.draw(&scene, &lights);
        rl.endMode3D();

        // === Draw 2D Things =======================================================
        rl.drawFPS(10, 10);
        rl.drawText(if (mouse_captured) "Mouse: CAPTURED" else "Mouse: FREE", 10, 30, 20, rl.Color.white);
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
