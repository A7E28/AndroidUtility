const std = @import("std");

pub const CommandUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn executeCommand(self: Self, command: []const u8) !?[]u8 {
        var child = std.process.Child.init(&[_][]const u8{ "cmd.exe", "/c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait();

        if (result != .Exited or result.Exited != 0) {
            if (std.mem.indexOf(u8, command, "adb") == null) {
                std.debug.print("Command failed: {s}\n", .{command});
                std.debug.print("Exit code: {}\n", .{result});
                std.debug.print("Stderr: {s}\n", .{stderr});
            }
            self.allocator.free(stdout);
            return null;
        }

        const trimmed = std.mem.trim(u8, stdout, " \t\n\r");
        if (trimmed.len == 0) {
            self.allocator.free(stdout);
            return null;
        }

        const result_string = try self.allocator.dupe(u8, trimmed);
        self.allocator.free(stdout);
        return result_string;
    }

    pub fn isCommandAvailable(self: Self, command: []const u8) bool {
        const check_cmd = std.fmt.allocPrint(self.allocator, "where \"{s}\" >nul 2>nul", .{command}) catch return false;
        defer self.allocator.free(check_cmd);

        var child = std.process.Child.init(&[_][]const u8{ "cmd.exe", "/c", check_cmd }, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        const result = child.spawnAndWait() catch return false;
        return result == .Exited and result.Exited == 0;
    }
};
