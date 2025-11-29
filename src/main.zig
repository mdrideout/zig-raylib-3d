const std = @import("std");
const zig_3d_game = @import("zig_3d_game");
const rl = @import("raylib");
const physics = @import("physics/mod.zig");

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
    var world = try physics.PhysicsWorld.create(allocator);
    defer world.destroy();

    // Config - Keys
    // Prevent ESC from closing the game immediately (so we can use it to toggle mouse)
    rl.setExitKey(.null);

    // Vars
    var mouse_captured: bool = false;

    // === RENDER LOOP ===============================================================
    while (!rl.windowShouldClose()) {
        // === Update Phase (Calculate physics, move camera, read inputs) ============
        const delta_time = rl.getFrameTime();
        try world.update(delta_time);

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

        // Clear the previous frame (Fixes ghosting/trails)
        rl.clearBackground(rl.Color.white);

        // === Draw 3D Things =======================================================
        rl.beginMode3D(camera);
        rl.drawGrid(10, 1.0);
        rl.endMode3D();

        // === Draw 2D Things =======================================================
        rl.drawFPS(10, 10);
        rl.drawText(if (mouse_captured) "Mouse: CAPTURED" else "Mouse: FREE", 10, 30, 20, rl.Color.black);
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
