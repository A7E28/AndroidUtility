const std = @import("std");
const Console = @import("console.zig").Console;

pub const ZipUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn extractZip(self: Self, zip_path: []const u8, dest_path: []const u8) !bool {
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();

        const file = std.Io.Dir.openFile(cwd, io, zip_path, .{}) catch |err| {
            Console.print("Failed to open ZIP file: {}\n", .{err});
            return false;
        };
        defer std.Io.File.close(file, io);

        std.Io.Dir.createDirPath(cwd, io, dest_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                Console.print("Failed to create destination directory: {}\n", .{err});
                return false;
            },
        };

        const platform_tools_path = try std.fmt.allocPrint(self.allocator, "{s}\\platform-tools", .{dest_path});
        defer self.allocator.free(platform_tools_path);

        std.Io.Dir.deleteTree(cwd, io, platform_tools_path) catch |err| switch (err) {
            error.AccessDenied => {
                Console.print("Warning: Could not remove existing platform-tools directory (access denied).\n", .{});
                Console.print("Please close any programs using ADB and try again.\n", .{});
                return false;
            },
            else => {
                Console.print("Note: Could not remove existing platform-tools directory: {}\n", .{err});
            },
        };

        const dest_dir = std.Io.Dir.openDir(cwd, io, dest_path, .{ .iterate = true }) catch |err| {
            Console.print("Failed to open destination directory: {}\n", .{err});
            return false;
        };
        defer std.Io.Dir.close(dest_dir, io);

        var buffer: [8192]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        std.zip.extract(dest_dir, &file_reader, .{}) catch |err| {
            Console.print("ZIP extraction failed: {}\n", .{err});
            return false;
        };

        Console.print("ZIP extraction completed successfully.\n", .{});
        return true;
    }
};
