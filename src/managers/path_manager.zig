const std = @import("std");
const RegistryManager = @import("registry.zig").RegistryManager;
const FileUtils = @import("../utils/file_utils.zig").FileUtils;

pub const PathManager = struct {
    allocator: std.mem.Allocator,
    registry: RegistryManager,
    file_utils: FileUtils,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .registry = RegistryManager.init(allocator),
            .file_utils = FileUtils.init(allocator),
        };
    }

    pub fn isInPath(self: Self, dir_path: []const u8) !bool {
        const path_value = self.registry.getValue("Environment", "Path") catch |err| switch (err) {
            error.RegistryError => return false,
            else => return err,
        };
        defer self.allocator.free(path_value);

        const clean_path = if (path_value.len > 0 and path_value[path_value.len - 1] == 0)
            path_value[0 .. path_value.len - 1]
        else
            path_value;

        var iterator = std.mem.splitScalar(u8, clean_path, ';');
        while (iterator.next()) |part| {
            const trimmed_part = std.mem.trim(u8, part, " \t");
            if (std.ascii.eqlIgnoreCase(trimmed_part, dir_path)) {
                return true;
            }
        }

        return false;
    }

    pub fn addToPath(self: Self, dir_path: []const u8) !bool {
        if (try self.isInPath(dir_path)) {
            std.debug.print("Path already exists in registry. Skipping PATH update.\n", .{});
            return true;
        }

        const current_path_raw = self.registry.getValue("Environment", "Path") catch |err| switch (err) {
            error.RegistryError => "",
            else => return err,
        };
        defer if (current_path_raw.len > 0) self.allocator.free(current_path_raw);

        const current_path = if (current_path_raw.len > 0 and current_path_raw[current_path_raw.len - 1] == 0)
            current_path_raw[0 .. current_path_raw.len - 1]
        else
            current_path_raw;

        const new_path = if (current_path.len == 0)
            try std.fmt.allocPrint(self.allocator, "{s}", .{dir_path})
        else
            try std.fmt.allocPrint(self.allocator, "{s};{s}", .{ current_path, dir_path });
        defer self.allocator.free(new_path);

        try self.registry.setValue("Environment", "Path", new_path);

        std.debug.print("Broadcasting PATH change to system...\n", .{});
        self.file_utils.broadcastEnvironmentChange();

        return true;
    }

    pub fn removeFromPath(self: Self, dir_path: []const u8) !void {
        const current_path_raw = self.registry.getValue("Environment", "Path") catch |err| switch (err) {
            error.RegistryError => return,
            else => return err,
        };
        defer if (current_path_raw.len > 0) self.allocator.free(current_path_raw);

        const current_path = if (current_path_raw.len > 0 and current_path_raw[current_path_raw.len - 1] == 0)
            current_path_raw[0 .. current_path_raw.len - 1]
        else
            current_path_raw;

        var path_parts = std.ArrayList([]const u8).init(self.allocator);
        defer path_parts.deinit();

        var iterator = std.mem.splitScalar(u8, current_path, ';');
        while (iterator.next()) |part| {
            const trimmed_part = std.mem.trim(u8, part, " \t");
            if (trimmed_part.len > 0 and !std.ascii.eqlIgnoreCase(trimmed_part, dir_path)) {
                try path_parts.append(trimmed_part);
            }
        }

        var new_path = std.ArrayList(u8).init(self.allocator);
        defer new_path.deinit();

        for (path_parts.items, 0..) |part, i| {
            if (i > 0) try new_path.append(';');
            try new_path.appendSlice(part);
        }

        const final_path = try new_path.toOwnedSlice();
        defer self.allocator.free(final_path);

        try self.registry.setValue("Environment", "Path", final_path);

        self.file_utils.broadcastEnvironmentChange();

        std.debug.print("Removed {s} from PATH.\n", .{dir_path});
    }
};
