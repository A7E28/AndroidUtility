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
        var child = std.process.Child.init(&[_][]const u8{ "cmd", "/c", "cls" }, std.heap.page_allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = child.spawnAndWait() catch {};
    }

    pub fn print(comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
    }
    pub fn printBold(comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
    }
};
