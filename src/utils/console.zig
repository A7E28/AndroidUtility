const std = @import("std");

pub const Console = struct {
    fn writeStdout(comptime format: []const u8, args: anytype) void {
        const io = std.Io.Threaded.global_single_threaded.io();
        const stdout_file = std.Io.File.stdout();
        var buffer: [1024]u8 = undefined;
        var w = stdout_file.writer(io, &buffer);
        w.interface.print(format, args) catch {};
        w.interface.flush() catch {};
    }

    pub fn printSuccess(comptime format: []const u8, args: anytype) void {
        writeStdout("[OK] " ++ format ++ "\n", args);
    }

    pub fn printError(comptime format: []const u8, args: anytype) void {
        writeStdout("[ERROR] " ++ format ++ "\n", args);
    }

    pub fn printWarning(comptime format: []const u8, args: anytype) void {
        writeStdout("[WARNING] " ++ format ++ "\n", args);
    }

    pub fn printInfo(comptime format: []const u8, args: anytype) void {
        writeStdout("[INFO] " ++ format ++ "\n", args);
    }

    pub fn printHeader(comptime text: []const u8) void {
        writeStdout("\n=== {s} ===\n", .{text});
    }

    pub fn printSection(comptime title: []const u8) void {
        writeStdout("\n--- {s} ---\n", .{title});
    }

    pub fn printSeparator() void {
        writeStdout("----------------------------------------\n", .{});
    }

    pub fn clearScreen() void {
        writeStdout("\x1b[2J\x1b[H", .{});
    }

    pub fn pause() void {
        writeStdout("\nPress Enter to continue...", .{});
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [128]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);
        _ = reader.interface.takeDelimiterExclusive('\n') catch {};
    }

    pub fn print(comptime format: []const u8, args: anytype) void {
        writeStdout(format, args);
    }

    pub fn getUserConfirmation(comptime prompt_text: []const u8) bool {
        writeStdout("{s} [Y/n]: ", .{prompt_text});
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [128]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);
        const input = reader.interface.takeDelimiterExclusive('\n') catch return true;
        const trimmed = std.mem.trim(u8, input, " \t\r");
        if (trimmed.len == 0) return true;
        if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N")) return false;
        return true;
    }

    pub fn getUserChoice() !u32 {
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [128]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);

        const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return 0;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        return std.fmt.parseInt(u32, trimmed, 10) catch 0;
    }

    pub fn getUserInput(buffer: []u8) !?[]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [1024]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);

        const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return null;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        if (trimmed.len > buffer.len) {
            return error.BufferTooSmall;
        }
        @memcpy(buffer[0..trimmed.len], trimmed);
        return buffer[0..trimmed.len];
    }
};
