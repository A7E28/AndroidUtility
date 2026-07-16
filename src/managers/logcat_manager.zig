const std = @import("std");
const CommandUtils = @import("../utils/command_utils.zig").CommandUtils;
const Console = @import("../utils/console.zig").Console;

const LogCaptureContext = struct {
    child: *std.process.Child,
    file: std.Io.File,
    io: std.Io,
    total_bytes: *std.atomic.Value(usize),
    line_count: *std.atomic.Value(u32),
    finished: *std.atomic.Value(bool),
};

fn logCaptureThread(ctx: LogCaptureContext) void {
    var read_buf: [4096]u8 = undefined;
    var temp_buf: [4096]u8 = undefined;

    const stdout_file = ctx.child.stdout orelse return;
    var stdout_reader = stdout_file.readerStreaming(ctx.io, &read_buf);

    while (true) {
        const amt = stdout_reader.interface.readSliceShort(&temp_buf) catch |err| {
            if (ctx.finished.load(.unordered)) break;
            Console.print("\n[ERROR] Error reading logcat output: {}\n", .{err});
            break;
        };

        if (amt == 0) break; // EOF

        std.Io.File.writeStreamingAll(ctx.file, ctx.io, temp_buf[0..amt]) catch |err| {
            Console.print("\n[ERROR] Error writing to file: {}\n", .{err});
            break;
        };

        const current_bytes = ctx.total_bytes.fetchAdd(amt, .monotonic) + amt;

        var new_lines: u32 = 0;
        for (temp_buf[0..amt]) |byte| {
            if (byte == '\n') new_lines += 1;
        }
        const current_lines = ctx.line_count.fetchAdd(new_lines, .monotonic) + new_lines;

        if (current_lines % 100 == 0 and current_lines > 0) {
            Console.print("\r[INFO] Captured: {} lines | {} KB  ", .{ current_lines, current_bytes / 1024 });
        }
    }
}

pub const LogLevel = enum {
    verbose,
    debug,
    info,
    warn,
    err,
    fatal,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .verbose => "V",
            .debug => "D",
            .info => "I",
            .warn => "W",
            .err => "E",
            .fatal => "F",
        };
    }

    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "V")) return .verbose;
        if (std.mem.eql(u8, str, "D")) return .debug;
        if (std.mem.eql(u8, str, "I")) return .info;
        if (std.mem.eql(u8, str, "W")) return .warn;
        if (std.mem.eql(u8, str, "E")) return .err;
        if (std.mem.eql(u8, str, "F")) return .fatal;
        return null;
    }
};

pub const LogcatOptions = struct {
    device_id: ?[]const u8 = null,
    package_name: ?[]const u8 = null,
    min_level: LogLevel = .verbose,
    clear_before: bool = false,
    max_lines: ?u32 = null,

    pub fn init() LogcatOptions {
        return LogcatOptions{};
    }
};

pub const LogcatManager = struct {
    allocator: std.mem.Allocator,
    command_utils: CommandUtils,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .command_utils = CommandUtils.init(allocator),
        };
    }

    pub fn getConnectedDevices(self: Self) ![][]u8 {
        const output = try self.command_utils.executeCommand("adb devices") orelse {
            return &[_][]u8{};
        };
        defer self.allocator.free(output);

        var devices = std.array_list.Managed([]u8).init(self.allocator);
        var lines = std.mem.splitScalar(u8, output, '\n');

        _ = lines.next();

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            const device_id = parts.next() orelse continue;
            const status = parts.next() orelse continue;

            if (std.mem.eql(u8, status, "device")) {
                try devices.append(try self.allocator.dupe(u8, device_id));
            }
        }

        return devices.toOwnedSlice();
    }

    pub fn getRunningPackages(self: Self, device_id: ?[]const u8) ![][]u8 {
        var cmd_buf: [256]u8 = undefined;
        const cmd = if (device_id) |id|
            try std.fmt.bufPrint(cmd_buf[0..], "adb -s {s} shell ps", .{id})
        else
            "adb shell ps";

        const output = try self.command_utils.executeCommand(cmd) orelse {
            return &[_][]u8{};
        };
        defer self.allocator.free(output);

        var packages = std.array_list.Managed([]u8).init(self.allocator);
        var lines = std.mem.splitScalar(u8, output, '\n');

        _ = lines.next();

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.splitScalar(u8, trimmed, ' ');
            var last_part: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (part.len > 0) last_part = part;
            }

            if (last_part) |package| {
                if (std.mem.indexOf(u8, package, ".")) |_| {
                    try packages.append(try self.allocator.dupe(u8, package));
                }
            }
        }

        return packages.toOwnedSlice();
    }

    pub fn captureLogcat(self: Self, options: LogcatOptions, output_file: ?[]const u8) !bool {
        var cmd = std.array_list.Managed(u8).init(self.allocator);
        defer cmd.deinit();

        try cmd.appendSlice("adb ");

        if (options.device_id) |device| {
            try cmd.appendSlice("-s ");
            try cmd.appendSlice(device);
            try cmd.appendSlice(" ");
        }

        try cmd.appendSlice("logcat ");
        try cmd.appendSlice("-v time ");

        if (options.min_level != .verbose) {
            try cmd.appendSlice("*:");
            try cmd.appendSlice(options.min_level.toString());
            try cmd.appendSlice(" ");
        }

        if (options.package_name) |package| {
            var pid_cmd_buf: [256]u8 = undefined;
            const pid_cmd = if (options.device_id) |device|
                try std.fmt.bufPrint(pid_cmd_buf[0..], "adb -s {s} shell pidof {s}", .{ device, package })
            else
                try std.fmt.bufPrint(pid_cmd_buf[0..], "adb shell pidof {s}", .{package});

            if (try self.command_utils.executeCommand(pid_cmd)) |pid_output| {
                defer self.allocator.free(pid_output);
                const pid = std.mem.trim(u8, pid_output, " \t\r\n");
                if (pid.len > 0 and !std.mem.startsWith(u8, pid, "pidof:")) {
                    try cmd.appendSlice("--pid=");
                    try cmd.appendSlice(pid);
                    try cmd.appendSlice(" ");
                    Console.printInfo("Filtering by PID {s} for package: {s}", .{ pid, package });
                } else {
                    try cmd.appendSlice(package);
                    try cmd.appendSlice(":* ");
                    Console.printInfo("Package not running, filtering by tag: {s}", .{package});
                }
            } else {
                try cmd.appendSlice(package);
                try cmd.appendSlice(":* ");
                Console.printInfo("Filtering by tag: {s}", .{package});
            }
        }

        const final_cmd = try cmd.toOwnedSlice();
        defer self.allocator.free(final_cmd);

        Console.printInfo("Executing: {s}", .{final_cmd});

        if (output_file) |file| {
            return try self.executeLogcatToFileRealtime(final_cmd, file);
        } else {
            return try self.executeLogcatRealtime(final_cmd);
        }
    }

    fn executeLogcatRealtime(self: Self, command: []const u8) !bool {
        const io_ts = std.Io.Threaded.global_single_threaded.io();
        const timestamp = std.Io.Timestamp.now(io_ts, .real);
        const filename = try std.fmt.allocPrint(self.allocator, "logcat_live_{d}.txt", .{@divTrunc(timestamp.nanoseconds, std.time.ns_per_s)});
        defer self.allocator.free(filename);

        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const io_cwd = std.Io.Threaded.global_single_threaded.io();
        const cwd_len = try std.process.currentPath(io_cwd, cwd_buffer[0..]);
        const cwd = cwd_buffer[0..cwd_len];
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ cwd, std.fs.path.sep, filename });
        defer self.allocator.free(file_path);

        // Parse command into arguments
        var cmd_parts = std.mem.splitScalar(u8, command, ' ');
        var args = std.array_list.Managed([]const u8).init(self.allocator);
        defer args.deinit();

        while (cmd_parts.next()) |part| {
            if (part.len > 0) {
                try args.append(part);
            }
        }

        var display_args = std.array_list.Managed([]const u8).init(self.allocator);
        defer display_args.deinit();

        try display_args.append("cmd.exe");
        try display_args.append("/c");
        try display_args.append("start");
        try display_args.append(""); // Empty window title

        for (args.items) |arg| {
            try display_args.append(arg);
        }

        var io_threaded = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();
        var display_child = std.process.spawn(io, .{
            .argv = display_args.items,
            .stdout = .ignore,
            .stderr = .ignore,
            .stdin = .ignore,
        }) catch return false;
        _ = display_child.wait(io) catch {};

        const cwd_dir = std.Io.Dir.cwd();
        const file = std.Io.Dir.createFile(cwd_dir, io, file_path, .{}) catch |err| {
            Console.printError("Failed to create log file: {}", .{err});
            return false;
        };

        _ = std.process.spawn(io, .{
            .argv = args.items,
            .stdout = .{ .file = file },
            .stderr = .ignore,
            .stdin = .close,
        }) catch |err| {
            std.Io.File.close(file, io);
            Console.printError("Failed to start background logger: {}", .{err});
            return false;
        };

        std.Io.File.close(file, io);

        Console.printSuccess("Logcat started in new window", .{});
        Console.printInfo("File saving started silently in background to: {s}", .{file_path});
        Console.printInfo("Returning to main menu...", .{});

        return true;
    }

    fn executeLogcatToFileRealtime(self: Self, command: []const u8, output_file: []const u8) !bool {
        var cmd_parts = std.mem.splitScalar(u8, command, ' ');
        var args = std.array_list.Managed([]const u8).init(self.allocator);
        defer args.deinit();

        while (cmd_parts.next()) |part| {
            if (part.len > 0) {
                try args.append(part);
            }
        }

        var io_threaded = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();
        const cwd = std.Io.Dir.cwd();
        const file = std.Io.Dir.createFile(cwd, io, output_file, .{}) catch |err| {
            Console.printError("Failed to create output file: {}", .{err});
            return false;
        };
        defer std.Io.File.close(file, io);

        var child = std.process.spawn(io, .{
            .argv = args.items,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch return false;
        defer child.kill(io);

        Console.printSuccess("Logcat capture started", .{});
        Console.printInfo("Output file: {s}", .{output_file});
        Console.printInfo("Press Enter to stop capture and return to main menu", .{});
        Console.printSeparator();

        var total_bytes = std.atomic.Value(usize).init(0);
        var line_count = std.atomic.Value(u32).init(0);
        var finished = std.atomic.Value(bool).init(false);

        const thread = try std.Thread.spawn(.{}, logCaptureThread, .{LogCaptureContext{
            .child = &child,
            .file = file,
            .io = io,
            .total_bytes = &total_bytes,
            .line_count = &line_count,
            .finished = &finished,
        }});

        var wait_buf: [4]u8 = undefined;
        _ = try Console.getUserInput(wait_buf[0..]);

        finished.store(true, .unordered);
        child.kill(io);
        thread.join();

        Console.print("\n", .{});
        Console.printSeparator();
        Console.printSuccess("Logcat capture ended. Total: {} KB | {} lines", .{ total_bytes.load(.unordered) / 1024, line_count.load(.unordered) });
        Console.printSuccess("File saved: {s}", .{output_file});

        return true;
    }

    pub fn deinit(self: Self, devices: [][]u8) void {
        for (devices) |device| {
            self.allocator.free(device);
        }
        self.allocator.free(devices);
    }

    pub fn deinitPackages(self: Self, packages: [][]u8) void {
        for (packages) |package| {
            self.allocator.free(package);
        }
        self.allocator.free(packages);
    }

    pub fn showMenu(self: Self) !void {
        Console.clearScreen();
        while (true) {
            Console.printSection("Logcat");
            Console.print("1. View live logcat (also saves to file)\n", .{});
            Console.print("2. Save logs to a file\n", .{});
            Console.print("3. View filtered logcat (also saves to file)\n", .{});
            Console.print("4. Back to main menu\n", .{});
            Console.print("Enter your choice: ", .{});

            const choice = try Console.getUserChoice();

            if (choice == 4) return;

            switch (choice) {
                1 => try self.viewLiveLogcat(),
                2 => try self.captureLogcatToFile(),
                3 => try self.viewFilteredLogcat(),
                else => {
                    Console.printError("Invalid choice. Please try again", .{});
                    Console.printSeparator();
                },
            }
            Console.pause();
            Console.clearScreen();
        }
    }

    fn viewLiveLogcat(self: Self) !void {
        Console.printSection("Live Logcat");

        const devices = try self.getConnectedDevices();
        defer self.deinit(devices);

        if (devices.len == 0) {
            Console.printError("No devices connected", .{});
            return;
        }

        const selected_device = try self.selectDevice(devices);
        if (selected_device == null) return;

        var options = LogcatOptions.init();
        options.device_id = selected_device;

        _ = try self.captureLogcat(options, null);
    }

    fn captureLogcatToFile(self: Self) !void {
        Console.printSection("Save logs to a file");

        const devices = try self.getConnectedDevices();
        defer self.deinit(devices);

        if (devices.len == 0) {
            Console.printError("No devices connected", .{});
            return;
        }

        const selected_device = try self.selectDevice(devices);
        if (selected_device == null) return;

        const io_ts2 = std.Io.Threaded.global_single_threaded.io();
        const timestamp = std.Io.Timestamp.now(io_ts2, .real);
        const device_name = if (selected_device) |device| device else "unknown";

        const default_filename = try std.fmt.allocPrint(self.allocator, "logcat_{s}_{d}.txt", .{ device_name, @divTrunc(timestamp.nanoseconds, std.time.ns_per_s) });
        defer self.allocator.free(default_filename);

        Console.print("Enter log filename (default: {s}): ", .{default_filename});
        var filename_buf: [256]u8 = undefined;
        var filename: []const u8 = default_filename;
        if (try Console.getUserInput(filename_buf[0..])) |input| {
            if (input.len > 0) {
                filename = input;
            }
        }

        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const io_cwd = std.Io.Threaded.global_single_threaded.io();
        const cwd_len = try std.process.currentPath(io_cwd, cwd_buffer[0..]);
        const cwd = cwd_buffer[0..cwd_len];
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ cwd, std.fs.path.sep, filename });
        defer self.allocator.free(file_path);

        var options = LogcatOptions.init();
        options.device_id = selected_device;

        if (try self.captureLogcat(options, file_path)) {} else {
            Console.printError("Failed to capture logcat", .{});
        }
    }

    fn viewFilteredLogcat(self: Self) !void {
        Console.printSection("Filtered Logcat");

        const devices = try self.getConnectedDevices();
        defer self.deinit(devices);

        if (devices.len == 0) {
            Console.printError("No devices connected", .{});
            return;
        }

        const selected_device = try self.selectDevice(devices);
        if (selected_device == null) return;

        const log_level = try self.selectLogLevel();

        Console.printInfo("Getting running packages...", .{});
        const packages = try self.getRunningPackages(selected_device);
        defer self.deinitPackages(packages);

        if (packages.len > 0) {
            Console.print("\nRunning packages (first 10):\n", .{});
            for (packages[0..@min(packages.len, 10)], 0..) |package, i| {
                Console.print("  {}. {s}\n", .{ i + 1, package });
            }
            if (packages.len > 10) {
                Console.print("  ... and {} more\n", .{packages.len - 10});
            }
        }

        Console.print("\nEnter package name to filter (or press Enter for all): ", .{});
        var package_buffer: [256]u8 = undefined;
        if (try Console.getUserInput(package_buffer[0..])) |package_input| {
            var options = LogcatOptions.init();
            options.device_id = selected_device;
            options.min_level = log_level;

            if (package_input.len > 0) {
                options.package_name = package_input;
            }

            _ = try self.captureLogcat(options, null);
        }
    }

    fn selectDevice(self: Self, devices: [][]u8) !?[]const u8 {
        _ = self;
        if (devices.len == 1) {
            return devices[0];
        }

        Console.print("Select device:\n", .{});
        for (devices, 0..) |device, i| {
            Console.print("{}. {s}\n", .{ i + 1, device });
        }
        Console.print("Enter device number: ", .{});

        const device_choice = try Console.getUserChoice();
        if (device_choice > 0 and device_choice <= devices.len) {
            return devices[device_choice - 1];
        } else {
            Console.printError("Invalid device selection", .{});
            return null;
        }
    }

    fn selectLogLevel(self: Self) !LogLevel {
        _ = self;
        Console.print("Select minimum log level:\n", .{});
        Console.print("1. Verbose (V)\n", .{});
        Console.print("2. Debug (D)\n", .{});
        Console.print("3. Info (I)\n", .{});
        Console.print("4. Warning (W)\n", .{});
        Console.print("5. Error (E)\n", .{});
        Console.print("6. Fatal (F)\n", .{});
        Console.print("Enter choice: ", .{});

        const level_choice = try Console.getUserChoice();
        return switch (level_choice) {
            1 => LogLevel.verbose,
            2 => LogLevel.debug,
            3 => LogLevel.info,
            4 => LogLevel.warn,
            5 => LogLevel.err,
            6 => LogLevel.fatal,
            else => LogLevel.info,
        };
    }


};
