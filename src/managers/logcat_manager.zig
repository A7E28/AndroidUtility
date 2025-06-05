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

        var devices = std.ArrayList([]u8).init(self.allocator);
        var lines = std.mem.splitScalar(u8, output, '\n');

        // Skip the header line
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

        var packages = std.ArrayList([]u8).init(self.allocator);
        var lines = std.mem.splitScalar(u8, output, '\n');

        // Skip header
        _ = lines.next();

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            // Extract package name from ps output (last column)
            var parts = std.mem.splitScalar(u8, trimmed, ' ');
            var last_part: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (part.len > 0) last_part = part;
            }

            if (last_part) |package| {
                if (std.mem.indexOf(u8, package, ".")) |_| {
                    // Only add if it looks like a package name
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
        var cmd = std.ArrayList(u8).init(self.allocator);
        defer cmd.deinit();

        try cmd.appendSlice("adb ");

        if (options.device_id) |device| {
            try cmd.appendSlice("-s ");
            try cmd.appendSlice(device);
            try cmd.appendSlice(" ");
        }

        try cmd.appendSlice("logcat ");

        // Add format
        try cmd.appendSlice("-v time ");

        // Add log level filter
        if (options.min_level != .verbose) {
            try cmd.appendSlice("*:");
            try cmd.appendSlice(options.min_level.toString());
            try cmd.appendSlice(" ");
        }

        // Add package filter if specified
        if (options.package_name) |package| {
            // First try to get PID for the package
            var pid_cmd_buf: [256]u8 = undefined;
            const pid_cmd = if (options.device_id) |device|
                try std.fmt.bufPrint(pid_cmd_buf[0..], "adb -s {s} shell pidof {s}", .{ device, package })
            else
                try std.fmt.bufPrint(pid_cmd_buf[0..], "adb shell pidof {s}", .{package});

            if (try self.command_utils.executeCommand(pid_cmd)) |pid_output| {
                defer self.allocator.free(pid_output);
                const pid = std.mem.trim(u8, pid_output, " \t\r\n");
                if (pid.len > 0 and !std.mem.startsWith(u8, pid, "pidof:")) {
                    // Valid PID found, use --pid filter
                    try cmd.appendSlice("--pid=");
                    try cmd.appendSlice(pid);
                    try cmd.appendSlice(" ");
                    Console.printInfo("Filtering by PID {s} for package: {s}", .{ pid, package });
                } else {
                    // No PID found, use tag filter instead
                    try cmd.appendSlice(package);
                    try cmd.appendSlice(":* ");
                    Console.printInfo("Package not running, filtering by tag: {s}", .{package});
                }
            } else {
                // Command failed, use tag filter
                try cmd.appendSlice(package);
                try cmd.appendSlice(":* ");
                Console.printInfo("Filtering by tag: {s}", .{package});
            }
        }

        const final_cmd = try cmd.toOwnedSlice();
        defer self.allocator.free(final_cmd);

        Console.printInfo("Executing: {s}", .{final_cmd});

        if (output_file) |file| {
            // For file output, capture continuously
            return try self.executeLogcatToFileRealtime(final_cmd, file);
        } else {
            // For real-time output
            return try self.executeLogcatRealtime(final_cmd);
        }
    }

    fn executeLogcatRealtime(self: Self, command: []const u8) !bool {
        // Generate automatic filename for live logcat too
        const timestamp = std.time.timestamp();
        const filename = try std.fmt.allocPrint(self.allocator, "logcat_live_{d}.txt", .{timestamp});
        defer self.allocator.free(filename);

        // Create the output file
        const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
            Console.printError("Failed to create log file: {}", .{err});
            return false;
        };
        defer file.close();

        var child = std.process.Child.init(&[_][]const u8{ "cmd.exe", "/c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        Console.printInfo("Logcat started. Press Ctrl+C to stop and exit to command prompt.", .{});
        Console.printInfo("Live logs are also being saved to: {s}", .{filename});
        Console.printInfo("(You can restart the app to continue using other features)", .{});
        Console.printSeparator();

        // Simple approach - just read until the process ends or Ctrl+C is pressed
        var buf: [4096]u8 = undefined;
        var total_bytes: u64 = 0;
        var last_progress_report: u64 = 0;

        while (true) {
            if (child.stdout) |stdout| {
                const bytes_read = stdout.read(buf[0..]) catch |err| {
                    if (err == error.EndOfStream) {
                        break; // Normal end of stream
                    }
                    if (err == error.WouldBlock) {
                        std.time.sleep(10 * std.time.ns_per_ms);
                        continue;
                    }
                    break;
                };

                if (bytes_read == 0) {
                    std.time.sleep(10 * std.time.ns_per_ms);
                    continue;
                }

                // Print the output to console (live view)
                std.debug.print("{s}", .{buf[0..bytes_read]});

                // Also write to file
                file.writeAll(buf[0..bytes_read]) catch |err| {
                    Console.printError("Error writing to log file: {}", .{err});
                    // Continue even if file write fails
                };

                total_bytes += bytes_read;

                // Print progress indicator every 100KB (less frequent for live view)
                if (total_bytes - last_progress_report >= 500 * 1024) { // Every 500KB
                    Console.printInfo("[SAVED: {} KB to {s}]", .{ total_bytes / 1024, filename });
                    last_progress_report = total_bytes;
                }
            } else {
                break;
            }
        }

        // Clean up
        _ = child.kill() catch {};
        _ = child.wait() catch {};

        Console.printSuccess("Logcat ended. Total logged: {} KB", .{total_bytes / 1024});
        Console.printSuccess("Log file saved: {s}", .{filename});
        return true;
    }

    fn executeLogcatToFileRealtime(self: Self, command: []const u8, output_file: []const u8) !bool {
        // Create the output file
        const file = std.fs.cwd().createFile(output_file, .{}) catch |err| {
            Console.printError("Failed to create output file: {}", .{err});
            return false;
        };
        defer file.close();

        var child = std.process.Child.init(&[_][]const u8{ "cmd.exe", "/c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        Console.printInfo("Logcat capture started to: {s}", .{output_file});
        Console.printInfo("Press Ctrl+C to stop and exit to command prompt.", .{});
        Console.printInfo("(You can restart the app to continue using other features)", .{});
        Console.printSeparator();

        var buf: [4096]u8 = undefined;
        var total_bytes: u64 = 0;
        var last_progress_report: u64 = 0;
        var line_count: u32 = 0;

        while (true) {
            if (child.stdout) |stdout| {
                const bytes_read = stdout.read(buf[0..]) catch |err| {
                    if (err == error.EndOfStream) {
                        break; // Normal end of stream
                    }
                    if (err == error.WouldBlock) {
                        std.time.sleep(10 * std.time.ns_per_ms);
                        continue;
                    }
                    break;
                };

                if (bytes_read == 0) {
                    std.time.sleep(10 * std.time.ns_per_ms);
                    continue;
                }

                // Write to file
                file.writeAll(buf[0..bytes_read]) catch |err| {
                    Console.printError("Error writing to file: {}", .{err});
                    break;
                };

                total_bytes += bytes_read;

                // Count lines for better progress reporting
                for (buf[0..bytes_read]) |byte| {
                    if (byte == '\n') line_count += 1;
                }

                // Print progress indicator every 100KB or every 1000 lines
                if (total_bytes - last_progress_report >= 100 * 1024) {
                    Console.printInfo("Captured: {} KB | {} lines (Press Ctrl+C to stop)", .{ total_bytes / 1024, line_count });
                    last_progress_report = total_bytes;
                }
            } else {
                break;
            }
        }

        // Clean up
        _ = child.kill() catch {};
        _ = child.wait() catch {};

        Console.printSuccess("Logcat capture ended. Total captured: {} KB | {} lines", .{ total_bytes / 1024, line_count });
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

        // Generate automatic filename with timestamp
        const timestamp = std.time.timestamp();
        const device_name = if (selected_device) |device| device else "unknown";

        const filename = try std.fmt.allocPrint(self.allocator, "logcat_{s}_{d}.txt", .{ device_name, timestamp });
        defer self.allocator.free(filename);

        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(cwd_buffer[0..]);
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

        // Select log level
        const log_level = try self.selectLogLevel();

        // Show running packages
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

        // Optional package filter
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

    // Helper functions
    fn getUserChoice() !u32 {
        const stdin = std.io.getStdIn().reader();
        var buffer: [16]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \t\n\r");
            return std.fmt.parseInt(u32, trimmed, 10) catch {
                return 0;
            };
        }
        return 0;
    }

    fn getUserInput(buffer: []u8) !?[]u8 {
        const stdin = std.io.getStdIn().reader();
        if (try stdin.readUntilDelimiterOrEof(buffer, '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \t\r\n");
            return @constCast(trimmed);
        }
        return null;
    }
};
