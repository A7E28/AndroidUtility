const std = @import("std");

pub const CommandUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn executeCommand(self: Self, command: []const u8) !?[]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();

        var child = std.process.spawn(io, .{
            .argv = &[_][]const u8{ "cmd.exe", "/c", command },
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch return null;
        defer _ = child.kill(io);

        var stdout_buf: [4096]u8 = undefined;
        const stdout_file = child.stdout orelse unreachable;
        var stdout_reader = stdout_file.readerStreaming(io, &stdout_buf);

        var stderr_buf: [4096]u8 = undefined;
        const stderr_file = child.stderr orelse unreachable;
        var stderr_reader = stderr_file.readerStreaming(io, &stderr_buf);

        // Read stdout into an ArrayList
        var stdout_list: std.ArrayList(u8) = .empty;
        errdefer self.allocator.free(stdout_list.items);
        while (true) {
            const data = stdout_reader.interface.take(1024) catch break;
            if (data.len == 0) break;
            try stdout_list.appendSlice(self.allocator, data);
        }

        // Read stderr into an ArrayList
        var stderr_list: std.ArrayList(u8) = .empty;
        errdefer self.allocator.free(stderr_list.items);
        while (true) {
            const data = stderr_reader.interface.take(1024) catch break;
            if (data.len == 0) break;
            try stderr_list.appendSlice(self.allocator, data);
        }

        const result = child.wait(io) catch std.process.Child.Term{ .exited = 1 };

        if (result != .exited or result.exited != 0) {
            if (std.mem.indexOf(u8, command, "adb") == null) {
                std.debug.print("Command failed: {s}\n", .{command});
                std.debug.print("Exit code: {}\n", .{result});
                std.debug.print("Stderr: {s}\n", .{stderr_list.items});
            }
            self.allocator.free(stdout_list.items);
            return null;
        }

        const trimmed = std.mem.trim(u8, stdout_list.items, " \t\n\r");
        if (trimmed.len == 0) {
            self.allocator.free(stdout_list.items);
            return null;
        }

        const result_string = try self.allocator.dupe(u8, trimmed);
        self.allocator.free(stdout_list.items);
        return result_string;
    }

    pub fn isCommandAvailable(self: Self, command: []const u8) bool {
        const check_cmd = std.fmt.allocPrint(self.allocator, "where \"{s}\" >nul 2>nul", .{command}) catch return false;
        defer self.allocator.free(check_cmd);

        const io = std.Io.Threaded.global_single_threaded.io();

        var child = std.process.spawn(io, .{
            .argv = &[_][]const u8{ "cmd.exe", "/c", check_cmd },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch return false;
        defer _ = child.kill(io);

        const result = child.wait(io) catch return false;
        return result == .exited and result.exited == 0;
    }
};
