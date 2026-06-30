const std = @import("std");
const CommandUtils = @import("../utils/command_utils.zig").CommandUtils;
const Console = @import("../utils/console.zig").Console;

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

            if (std.mem.indexOf(u8, trimmed, "\tdevice")) |_| {
                const device_id = std.mem.trim(u8, trimmed[0..std.mem.indexOf(u8, trimmed, "\t").?], " \t");
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

    pub fn clearLogcat(self: Self, device_id: ?[]const u8) !bool {
        var cmd_buf: [128]u8 = undefined;
        const cmd = if (device_id) |id|
            try std.fmt.bufPrint(cmd_buf[0..], "adb -s {s} logcat -c", .{id})
        else
            "adb logcat -c";

        const output = try self.command_utils.executeCommand(cmd);
        if (output) |out| {
            self.allocator.free(out);
            return true;
        }
        return false;
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

        // Parse command into arguments
        var cmd_parts = std.mem.splitScalar(u8, command, ' ');
        var args = std.array_list.Managed([]const u8).init(self.allocator);
        defer args.deinit();

        while (cmd_parts.next()) |part| {
            if (part.len > 0) {
                try args.append(part);
            }
        }

        // Process 1: Open NEW WINDOW for live display
        var display_args = std.array_list.Managed([]const u8).init(self.allocator);
        defer display_args.deinit();

        try display_args.append("cmd.exe");
        try display_args.append("/c");
        try display_args.append("start");
        try display_args.append(""); // Empty window title

        // Add all the original command arguments for display
        for (args.items) |arg| {
            try display_args.append(arg);
        }

        const io_display = std.Io.Threaded.global_single_threaded.io();
        var display_child = std.process.spawn(io_display, .{
            .argv = display_args.items,
            .stdout = .ignore,
            .stderr = .ignore,
            .stdin = .ignore,
        }) catch return false;
        _ = display_child.kill(io_display);
        _ = display_child.wait(io_display) catch {};

        // Process 2: Start file saving in SEPARATE WINDOW too
        // Create a command that saves to file in another window
        const save_command = try std.fmt.allocPrint(self.allocator, "{s} > \"{s}\"", .{ command, filename });
        defer self.allocator.free(save_command);

        var save_args = std.array_list.Managed([]const u8).init(self.allocator);
        defer save_args.deinit();

        try save_args.append("cmd.exe");
        try save_args.append("/c");
        try save_args.append("start");
        try save_args.append(""); // Empty window title
        try save_args.append("cmd.exe");
        try save_args.append("/c");
        try save_args.append(save_command);

        const io_save = std.Io.Threaded.global_single_threaded.io();
        var save_child = std.process.spawn(io_save, .{
            .argv = save_args.items,
            .stdout = .ignore,
            .stderr = .ignore,
            .stdin = .ignore,
        }) catch return false;
        _ = save_child.kill(io_save);
        _ = save_child.wait(io_save) catch {};

        Console.printSuccess("Logcat started in new window", .{});
        Console.printInfo("File saving started in background to: {s}", .{filename});
        Console.printInfo("Close both windows with Ctrl+C to stop", .{});
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

        // Create the output file
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();
        const file = std.Io.Dir.createFile(cwd, io, output_file, .{}) catch |err| {
            Console.printError("Failed to create output file: {}", .{err});
            return false;
        };
        defer std.Io.File.close(file, io);

        // Start logcat process with piped output
        var child = std.process.spawn(io, .{
            .argv = args.items,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch return false;
        defer _ = child.kill(io);

        Console.printSuccess("Logcat capture started", .{});
        Console.printInfo("Output file: {s}", .{output_file});
        Console.printInfo("Press Ctrl+C to stop capture and return to main menu", .{});
        Console.printSeparator();

        var buf: [4096]u8 = undefined;
        var total_bytes: u64 = 0;
        var line_count: u32 = 0;

        const stdout_file = child.stdout orelse unreachable;
        var stdout_reader = stdout_file.readerStreaming(io, &buf);

        while (true) {
            const bytes_read = stdout_reader.interface.take(buf.len) catch |err| {
                if (err == error.EndOfStream) break;
                Console.printError("Error reading logcat output: {}", .{err});
                break;
            };

            if (bytes_read.len == 0) {
                std.Io.sleep(io, std.Io.Duration.fromMilliseconds(10), .awake) catch {};
                continue;
            }

            std.Io.File.writeStreamingAll(file, io, bytes_read) catch |err| {
                Console.printError("Error writing to file: {}", .{err});
                break;
            };

            total_bytes += bytes_read.len;

            for (bytes_read) |byte| {
                if (byte == '\n') line_count += 1;
            }

            if (line_count % 50 == 0 and line_count > 0) {
                Console.printInfo("Captured: {} lines | {} KB", .{ line_count, total_bytes / 1024 });
            }
        }

        _ = child.kill(io);
        _ = child.wait(io) catch {};

        Console.printSeparator();
        Console.printSuccess("Logcat capture ended. Total: {} KB | {} lines", .{ total_bytes / 1024, line_count });
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
        while (true) {
            Console.printSection("Logcat");
            std.debug.print("1. View live logcat (also saves to file)\n", .{});
            std.debug.print("2. Capture logcat to custom file\n", .{});
            std.debug.print("3. Clear logcat buffer\n", .{});
            std.debug.print("4. View filtered logcat (also saves to file)\n", .{});
            std.debug.print("5. Back to main menu\n", .{});
            std.debug.print("Enter your choice: ", .{});

            const choice = try getUserChoice();

            switch (choice) {
                1 => try self.viewLiveLogcat(),
                2 => try self.captureLogcatToFile(),
                3 => try self.clearLogcatBuffer(),
                4 => try self.viewFilteredLogcat(),
                5 => return,
                else => {
                    Console.printError("Invalid choice. Please try again", .{});
                    Console.printSeparator();
                },
            }
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
        Console.printSection("Capture Logcat to File");

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

        const filename = try std.fmt.allocPrint(self.allocator, "logcat_{s}_{d}.txt", .{ device_name, @divTrunc(timestamp.nanoseconds, std.time.ns_per_s) });
        defer self.allocator.free(filename);

        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const io_cwd = std.Io.Threaded.global_single_threaded.io();
        const cwd_len = try std.process.currentPath(io_cwd, cwd_buffer[0..]);
        const cwd = cwd_buffer[0..cwd_len];
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ cwd, std.fs.path.sep, filename });
        defer self.allocator.free(file_path);

        var options = LogcatOptions.init();
        options.device_id = selected_device;

        if (try self.captureLogcat(options, file_path)) {
            Console.printSuccess("Logcat capture completed successfully!", .{});
        } else {
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
            std.debug.print("\nRunning packages (first 10):\n", .{});
            for (packages[0..@min(packages.len, 10)], 0..) |package, i| {
                std.debug.print("  {}. {s}\n", .{ i + 1, package });
            }
            if (packages.len > 10) {
                std.debug.print("  ... and {} more\n", .{packages.len - 10});
            }
        }

        std.debug.print("\nEnter package name to filter (or press Enter for all): ", .{});
        var package_buffer: [256]u8 = undefined;
        if (try getUserInput(package_buffer[0..])) |package_input| {
            var options = LogcatOptions.init();
            options.device_id = selected_device;
            options.min_level = log_level;

            if (package_input.len > 0) {
                options.package_name = package_input;
            }

            _ = try self.captureLogcat(options, null);
        }
    }

    fn clearLogcatBuffer(self: Self) !void {
        Console.printSection("Clear Logcat Buffer");

        const devices = try self.getConnectedDevices();
        defer self.deinit(devices);

        if (devices.len == 0) {
            Console.printError("No devices connected", .{});
            return;
        }

        for (devices) |device| {
            if (try self.clearLogcat(device)) {
                Console.printSuccess("Logcat buffer cleared for device: {s}", .{device});
            } else {
                Console.printError("Failed to clear logcat buffer for device: {s}", .{device});
            }
        }
    }

    fn selectDevice(self: Self, devices: [][]u8) !?[]const u8 {
        _ = self;
        if (devices.len == 1) {
            return devices[0];
        }

        std.debug.print("Select device:\n", .{});
        for (devices, 0..) |device, i| {
            std.debug.print("{}. {s}\n", .{ i + 1, device });
        }
        std.debug.print("Enter device number: ", .{});

        const device_choice = try getUserChoice();
        if (device_choice > 0 and device_choice <= devices.len) {
            return devices[device_choice - 1];
        } else {
            Console.printError("Invalid device selection", .{});
            return null;
        }
    }

    fn selectLogLevel(self: Self) !LogLevel {
        _ = self;
        std.debug.print("Select minimum log level:\n", .{});
        std.debug.print("1. Verbose (V)\n", .{});
        std.debug.print("2. Debug (D)\n", .{});
        std.debug.print("3. Info (I)\n", .{});
        std.debug.print("4. Warning (W)\n", .{});
        std.debug.print("5. Error (E)\n", .{});
        std.debug.print("6. Fatal (F)\n", .{});
        std.debug.print("Enter choice: ", .{});

        const level_choice = try getUserChoice();
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

    fn getUserChoice() !u32 {
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [4096]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);

        const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return 0;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        return std.fmt.parseInt(u32, trimmed, 10) catch 0;
    }

    fn getUserInput(buffer: []u8) !?[]u8 {
        _ = buffer;
        const io = std.Io.Threaded.global_single_threaded.io();
        var read_buffer: [4096]u8 = undefined;
        const stdin_file = std.Io.File.stdin();
        var reader = stdin_file.reader(io, &read_buffer);

        const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return null;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        return @constCast(trimmed);
    }
};
