const std = @import("std");

pub const ZipUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn extractZip(self: Self, zip_path: []const u8, dest_path: []const u8) !bool {
        const file = std.fs.cwd().openFile(zip_path, .{}) catch |err| {
            std.debug.print("Failed to open ZIP file: {}\n", .{err});
            return false;
        };
        defer file.close();

        std.fs.cwd().makePath(dest_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                std.debug.print("Failed to create destination directory: {}\n", .{err});
                return false;
            },
        };

        const platform_tools_path = try std.fmt.allocPrint(self.allocator, "{s}\\platform-tools", .{dest_path});
        defer self.allocator.free(platform_tools_path);

        std.fs.cwd().deleteTree(platform_tools_path) catch |err| switch (err) {
            error.AccessDenied => {
                std.debug.print("Warning: Could not remove existing platform-tools directory (access denied).\n", .{});
                std.debug.print("Please close any programs using ADB and try again.\n", .{});
                return false;
            },
            else => {
                std.debug.print("Note: Could not remove existing platform-tools directory: {}\n", .{err});
            },
        };

        var dest_dir = std.fs.cwd().openDir(dest_path, .{ .iterate = true }) catch |err| {
            std.debug.print("Failed to open destination directory: {}\n", .{err});
            return false;
        };
        defer dest_dir.close();

        var buffer: [8192]u8 = undefined;
        var file_reader = file.reader(&buffer);
        std.zip.extract(dest_dir, &file_reader, .{}) catch |err| {
            std.debug.print("ZIP extraction failed: {}\n", .{err});
            return false;
        };

        std.debug.print("ZIP extraction completed successfully.\n", .{});
        return true;
    }
};
