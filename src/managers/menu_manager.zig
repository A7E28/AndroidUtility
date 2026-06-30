const std = @import("std");
const Console = @import("../utils/console.zig").Console;
const AdbManager = @import("adb_manager.zig").AdbManager;
const HashManager = @import("hash_manager.zig").HashManager;
const LogcatManager = @import("logcat_manager.zig").LogcatManager;
const FileDialog = @import("../utils/file_dialog.zig").FileDialog;
const types = @import("../types.zig");

const HashAlgorithm = types.HashAlgorithm;
const LogLevel = @import("logcat_manager.zig").LogLevel;
const LogcatOptions = @import("logcat_manager.zig").LogcatOptions;

pub const MenuManager = struct {
    allocator: std.mem.Allocator,
    adb_manager: AdbManager,
    hash_manager: HashManager,
    logcat_manager: LogcatManager,
    file_dialog: FileDialog,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .adb_manager = AdbManager.init(allocator),
            .hash_manager = HashManager.init(allocator),
            .logcat_manager = LogcatManager.init(allocator),
            .file_dialog = FileDialog.init(allocator),
        };
    }

    pub fn displayMainMenu(self: Self) void {
        _ = self;
        Console.printHeader("Android Utility Tool");
        std.debug.print("1. Check ADB installation\n", .{});
        std.debug.print("2. Install ADB\n", .{});
        std.debug.print("3. Update ADB\n", .{});
        std.debug.print("4. Get file checksum\n", .{});
        std.debug.print("5. Logcat\n", .{});
        std.debug.print("6. Exit\n", .{});
        std.debug.print("Enter your choice: ", .{});
    }

    pub fn handleMainMenuChoice(self: Self, choice: u32) !bool {
        switch (choice) {
            1 => try self.checkAdbInstallation(),
            2 => try self.installAdb(),
            3 => try self.updateAdb(),
            4 => try self.verifyChecksum(),
            5 => try self.showLogcatMenu(),
            6 => {
                Console.printSuccess("Thanks for using Android Utility Tool!", .{});
                return false;
            },
            else => {
                Console.printError("Invalid choice. Please try again", .{});
                Console.printSeparator();
            },
        }
        return true;
    }

    fn checkAdbInstallation(self: Self) !void {
        Console.printSection("ADB Installation Check");

        var adb_info = try self.adb_manager.checkInstallation();
        defer adb_info.deinit(self.allocator);

        if (adb_info.installed) {
            Console.printSuccess("ADB is installed", .{});
            std.debug.print("Version: {s}\n", .{adb_info.version});
            std.debug.print("Path: {s}\n", .{adb_info.path});
        } else {
            Console.printError("ADB is not installed or not in PATH", .{});
            Console.printInfo("Use option 2 to install ADB", .{});
        }

        Console.printSeparator();
    }

    fn installAdb(self: Self) !void {
        Console.printSection("ADB Installation");
        _ = try self.adb_manager.install();
        Console.printSeparator();
    }

    fn updateAdb(self: Self) !void {
        Console.printSection("ADB Update");
        _ = try self.adb_manager.update();
        Console.printSeparator();
    }

    fn verifyChecksum(self: Self) !void {
        Console.printSection("File Checksum Verification");
        Console.printInfo("Select a file to verify checksum...", .{});

        if (try self.file_dialog.openFileDialog("Select file for checksum verification")) |file_path| {
            defer self.allocator.free(file_path);

            std.debug.print("Selected file: {s}\n", .{file_path});
            std.debug.print("\nSelect hash algorithm:\n", .{});
            std.debug.print("1. MD5\n", .{});
            std.debug.print("2. SHA1\n", .{});
            std.debug.print("3. SHA256\n", .{});
            std.debug.print("Enter choice: ", .{});

            const choice = try self.getUserChoice();
            const algorithm: HashAlgorithm = switch (choice) {
                1 => .MD5,
                2 => .SHA1,
                3 => .SHA256,
                else => {
                    Console.printError("Invalid choice", .{});
                    Console.printSeparator();
                    return;
                },
            };

            Console.printInfo("Calculating hash... Please wait", .{});

            const hash = self.hash_manager.calculateFileHash(file_path, algorithm) catch |err| {
                Console.printError("Error calculating hash: {}", .{err});
                Console.printSeparator();
                return;
            };
            defer self.allocator.free(hash);

            const algo_name = switch (algorithm) {
                .MD5 => "MD5",
                .SHA1 => "SHA1",
                .SHA256 => "SHA256",
            };

            Console.printSuccess("Hash calculated successfully", .{});
            std.debug.print("{s}: {s}\n", .{ algo_name, hash });
        } else {
            Console.printWarning("No file selected", .{});
        }

        Console.printSeparator();
    }

    fn showLogcatMenu(self: Self) !void {
        Console.printInfo("Checking ADB installation...", .{});

        var adb_info = try self.adb_manager.checkInstallation();
        defer adb_info.deinit(self.allocator);

        if (!adb_info.installed) {
            Console.printWarning("ADB is not installed", .{});
            Console.printInfo("Installing ADB automatically...", .{});
            Console.printSeparator();

            if (try self.adb_manager.install()) {
                Console.printSuccess("ADB installed successfully!", .{});
                Console.printInfo("You can now use logcat features", .{});
            } else {
                Console.printError("Failed to install ADB automatically", .{});
                Console.printInfo("Please install ADB manually (Main Menu -> Option 2)", .{});
                Console.printSeparator();
                return;
            }
        } else {
            Console.printSuccess("ADB is available (Version: {s})", .{adb_info.version});
        }

        Console.printSeparator();

        try self.logcat_manager.showMenu();
    }

    fn getUserChoice(self: Self) !u32 {
        _ = self;
        var read_buffer: [4096]u8 = undefined;
        var file_reader = std.fs.File.stdin().reader(&read_buffer);
        var stdin = &file_reader.interface;

        const input = stdin.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return 0;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        return std.fmt.parseInt(u32, trimmed, 10) catch 0;
    }
};
