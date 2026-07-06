const std = @import("std");

pub const Console = struct {
    pub fn printSuccess(comptime format: []const u8, args: anytype) void {
        std.debug.print("[OK] ", .{});
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    pub fn printError(comptime format: []const u8, args: anytype) void {
        std.debug.print("[ERROR] ", .{});
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    pub fn printWarning(comptime format: []const u8, args: anytype) void {
        std.debug.print("[WARNING] ", .{});
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    pub fn printInfo(comptime format: []const u8, args: anytype) void {
        std.debug.print("[INFO] ", .{});
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    pub fn printHeader(comptime text: []const u8) void {
        std.debug.print("\n", .{});
        std.debug.print("=== {s} ===\n", .{text});
    }

    pub fn printSection(comptime title: []const u8) void {
        std.debug.print("\n--- {s} ---\n", .{title});
    }

    pub fn printSeparator() void {
        std.debug.print("----------------------------------------\n", .{});
    }

    pub fn clearScreen() void {
        var io_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();

        var child = std.process.spawn(io, .{
            .argv = &[_][]const u8{ "cmd.exe", "/c", "cls" },
            .stdout = .inherit,
            .stderr = .inherit,
            .stdin = .ignore,
        }) catch return;
        defer child.kill(io);

        _ = child.wait(io) catch {};
    }

    pub fn pause() void {
        std.debug.print("\nPress Enter to continue...", .{});
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [128]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);
        _ = reader.interface.takeDelimiterExclusive('\n') catch {};
    }

    pub fn print(comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
    }
    pub fn printBold(comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
    }
};
