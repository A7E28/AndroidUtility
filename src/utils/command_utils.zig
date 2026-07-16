const std = @import("std");
const FileUtils = @import("file_utils.zig").FileUtils;
const RegistryManager = @import("../managers/registry.zig").RegistryManager;

pub const CommandUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    fn findAdbOnSystem(self: Self) !?[]u8 {
        var file_utils = FileUtils.init(self.allocator);
        var registry = RegistryManager.init(self.allocator);

        // Check user registry PATH
        if (registry.getValue("Environment", "Path")) |path_val| {
            defer self.allocator.free(path_val);
            const clean_path = if (path_val.len > 0 and path_val[path_val.len - 1] == 0)
                path_val[0 .. path_val.len - 1]
            else
                path_val;

            var iterator = std.mem.splitScalar(u8, clean_path, ';');
            while (iterator.next()) |part| {
                const trimmed_part = std.mem.trim(u8, part, " \t");
                if (trimmed_part.len == 0) continue;
                const check_file = try std.fmt.allocPrint(self.allocator, "{s}\\adb.exe", .{trimmed_part});
                defer self.allocator.free(check_file);

                if (file_utils.fileExists(check_file)) {
                    return try self.allocator.dupe(u8, check_file);
                }
            }
        } else |_| {}

        // Check default platform-tools
        if (file_utils.getUserHomeDir()) |home| {
            defer self.allocator.free(home);
            const check_file = try std.fmt.allocPrint(self.allocator, "{s}\\platform-tools\\adb.exe", .{home});
            defer self.allocator.free(check_file);

            if (file_utils.fileExists(check_file)) {
                return try self.allocator.dupe(u8, check_file);
            }
        } else |_| {}

        return null;
    }

    pub fn executeCommand(self: Self, command: []const u8) !?[]u8 {
        // Special case: if the command is "where adb" and adb is not on PATH,
        // we can try to find it on system first to return its path directly!
        if (std.mem.eql(u8, command, "where adb")) {
            if (try self.findAdbOnSystem()) |adb_path| {
                return adb_path;
            }
        }

        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(self.allocator);

        var in_quote = false;
        var start: usize = 0;
        var i: usize = 0;
        while (i < command.len) : (i += 1) {
            const c = command[i];
            if (c == '"') {
                in_quote = !in_quote;
            } else if (c == ' ' and !in_quote) {
                if (i > start) {
                    const arg = command[start..i];
                    const trimmed_arg = std.mem.trim(u8, arg, "\"");
                    if (trimmed_arg.len > 0) {
                        try args.append(self.allocator, trimmed_arg);
                    }
                }
                start = i + 1;
            }
        }
        if (i > start) {
            const arg = command[start..i];
            const trimmed_arg = std.mem.trim(u8, arg, "\"");
            if (trimmed_arg.len > 0) {
                try args.append(self.allocator, trimmed_arg);
            }
        }

        if (args.items.len == 0) return null;

        var io_threaded = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();

        // Try spawning directly
        var child_opt = std.process.spawn(io, .{
            .argv = args.items,
            .stdout = .pipe,
            .stderr = .pipe,
        });

        // If it failed with FileNotFound and the program is "adb", try to locate it and retry
        if (child_opt == error.FileNotFound and std.mem.eql(u8, args.items[0], "adb")) {
            if (try self.findAdbOnSystem()) |adb_path| {
                defer self.allocator.free(adb_path);
                // Replace "adb" with absolute path
                const original_first = args.items[0];
                args.items[0] = adb_path;
                child_opt = std.process.spawn(io, .{
                    .argv = args.items,
                    .stdout = .pipe,
                    .stderr = .pipe,
                });
                args.items[0] = original_first; // restore if needed
            }
        }

        var child = try child_opt;
        defer _ = child.kill(io);

        var stdout_buf: [4096]u8 = undefined;
        const stdout_file = child.stdout orelse unreachable;
        var stdout_reader = stdout_file.readerStreaming(io, &stdout_buf);

        var stderr_buf: [4096]u8 = undefined;
        const stderr_file = child.stderr orelse unreachable;
        var stderr_reader = stderr_file.readerStreaming(io, &stderr_buf);

        // Read stdout into an ArrayList
        var stdout_list = std.array_list.Managed(u8).init(self.allocator);
        defer stdout_list.deinit();
        var temp_buf: [1024]u8 = undefined;
        while (true) {
            const amt = try stdout_reader.interface.readSliceShort(&temp_buf);
            if (amt == 0) break;
            try stdout_list.appendSlice(temp_buf[0..amt]);
        }

        // Read stderr into an ArrayList
        var stderr_list = std.array_list.Managed(u8).init(self.allocator);
        defer stderr_list.deinit();
        var temp_err_buf: [1024]u8 = undefined;
        while (true) {
            const amt = try stderr_reader.interface.readSliceShort(&temp_err_buf);
            if (amt == 0) break;
            try stderr_list.appendSlice(temp_err_buf[0..amt]);
        }

        const result = child.wait(io) catch std.process.Child.Term{ .exited = 1 };

        if (result != .exited or result.exited != 0) {
            return null;
        }

        const trimmed = std.mem.trim(u8, stdout_list.items, " \t\n\r");
        if (trimmed.len == 0) {
            return null;
        }

        const result_string = try self.allocator.dupe(u8, trimmed);
        return result_string;
    }

    pub fn isCommandAvailable(self: Self, command: []const u8) bool {
        var io_threaded = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();

        var child = std.process.spawn(io, .{
            .argv = &[_][]const u8{ "where.exe", command },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch return false;
        defer _ = child.kill(io);

        const result = child.wait(io) catch return false;
        return result == .exited and result.exited == 0;
    }
};
