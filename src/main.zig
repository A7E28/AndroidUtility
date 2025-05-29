const std = @import("std");
const types = @import("types.zig");
const AdbManager = @import("managers/adb_manager.zig").AdbManager;
const HashManager = @import("managers/hash_manager.zig").HashManager;
const FileDialog = @import("utils/file_dialog.zig").FileDialog;
const Console = @import("utils/console.zig").Console;

const HashAlgorithm = types.HashAlgorithm;

const App = struct {
    allocator: std.mem.Allocator,
    adb_manager: AdbManager,
    hash_manager: HashManager,
    file_dialog: FileDialog,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .adb_manager = AdbManager.init(allocator),
            .hash_manager = HashManager.init(allocator),
            .file_dialog = FileDialog.init(allocator),
        };
    }

    pub fn displayMenu(self: Self) void {
        _ = self;
        Console.printHeader("Android Utility Tool");
        std.debug.print("1. Check ADB installation\n", .{});
        std.debug.print("2. Install ADB\n", .{});
        std.debug.print("3. Update ADB\n", .{});
        std.debug.print("4. Get file checksum\n", .{});
        std.debug.print("5. Exit\n", .{});
        std.debug.print("Enter your choice: ", .{});
    }

    pub fn checkAdbInstallation(self: Self) !void {
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

    pub fn installAdb(self: Self) !void {
        Console.printSection("ADB Installation");
        _ = try self.adb_manager.install();
        Console.printSeparator();
    }

    pub fn updateAdb(self: Self) !void {
        Console.printSection("ADB Update");
        _ = try self.adb_manager.update();
        Console.printSeparator();
    }

    pub fn verifyChecksum(self: Self) !void {
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

            const stdin = std.io.getStdIn().reader();
            var choice_buffer: [16]u8 = undefined;
            if (try stdin.readUntilDelimiterOrEof(choice_buffer[0..], '\n')) |choice_input| {
                const choice = std.mem.trim(u8, choice_input, " \t\n\r");

                const algorithm: HashAlgorithm = switch (choice[0]) {
                    '1' => .MD5,
                    '2' => .SHA1,
                    '3' => .SHA256,
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
            }
        } else {
            Console.printWarning("No file selected", .{});
        }

        Console.printSeparator();
    }

    pub fn getUserChoice(self: Self) !i32 {
        _ = self;
        const stdin = std.io.getStdIn().reader();
        var buffer: [16]u8 = undefined;

        if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \t\n\r");
            return std.fmt.parseInt(i32, trimmed, 10) catch 0;
        }
        return 0;
    }

    pub fn run(self: Self) !void {
        Console.clearScreen();

        while (true) {
            self.displayMenu();
            const choice = try self.getUserChoice();

            switch (choice) {
                1 => try self.checkAdbInstallation(),
                2 => try self.installAdb(),
                3 => try self.updateAdb(),
                4 => try self.verifyChecksum(),
                5 => {
                    Console.printSuccess("Thanks for using Android Utility Tool!", .{});
                    break;
                },
                else => {
                    Console.printError("Invalid choice. Please try again", .{});
                    Console.printSeparator();
                },
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app = App.init(allocator);
    try app.run();
}
