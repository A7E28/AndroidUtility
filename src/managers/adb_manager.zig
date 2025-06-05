const std = @import("std");
const types = @import("../types.zig");
const FileUtils = @import("../utils/file_utils.zig").FileUtils;
const ZipUtils = @import("../utils/zip_utils.zig").ZipUtils;
const CommandUtils = @import("../utils/command_utils.zig").CommandUtils;
const PathManager = @import("path_manager.zig").PathManager;
const XmlUtils = @import("../utils/parse_xml.zig").XmlUtils;
const Console = @import("../utils/console.zig").Console;

const AdbInfo = types.AdbInfo;
const AppError = types.AppError;

pub const AdbManager = struct {
    allocator: std.mem.Allocator,
    file_utils: FileUtils,
    zip_utils: ZipUtils,
    command_utils: CommandUtils,
    path_manager: PathManager,
    xml_utils: XmlUtils,

    const Self = @This();
    const PLATFORM_TOOLS_URL = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip";
    const REPO_URL = "https://dl.google.com/android/repository/repository2-1.xml";

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .file_utils = FileUtils.init(allocator),
            .zip_utils = ZipUtils.init(allocator),
            .command_utils = CommandUtils.init(allocator),
            .path_manager = PathManager.init(allocator),
            .xml_utils = XmlUtils.init(allocator),
        };
    }

    pub fn checkInstallation(self: Self) !AdbInfo {
        var adb_info = AdbInfo.init();

        if (try self.command_utils.executeCommand("adb version")) |version_output| {
            adb_info.installed = true;
            adb_info.version = version_output;

            if (try self.command_utils.executeCommand("where adb")) |path_output| {
                adb_info.path = path_output;
            } else if (std.mem.indexOf(u8, version_output, "Installed as ")) |pos| {
                const path_start = pos + "Installed as ".len;
                const line_end = std.mem.indexOfAny(u8, version_output[path_start..], "\r\n") orelse version_output.len - path_start;
                const path = std.mem.trim(u8, version_output[path_start .. path_start + line_end], " \t");
                adb_info.path = try self.allocator.dupe(u8, path);
            }
        }

        return adb_info;
    }

    fn getLatestAdbVersion(self: Self) !?[]u8 {
        const temp_dir = std.fs.getAppDataDir(self.allocator, "AndroidUtility") catch {
            return try self.getLatestAdbVersionFallback();
        };
        defer self.allocator.free(temp_dir);

        std.fs.cwd().makePath(temp_dir) catch {};

        const temp_file = try std.fmt.allocPrint(self.allocator, "{s}\\android_repo.xml", .{temp_dir});
        defer self.allocator.free(temp_file);

        if (!try self.file_utils.downloadFile(REPO_URL, temp_file)) {
            std.debug.print("Failed to download repository information.\n", .{});
            return null;
        }

        const file = std.fs.cwd().openFile(temp_file, .{}) catch {
            std.debug.print("Failed to open repository file.\n", .{});
            return null;
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            std.debug.print("Failed to read repository file.\n", .{});
            return null;
        };
        defer self.allocator.free(content);

        const version = try self.xml_utils.extractVersionFromXml(content);

        self.file_utils.deleteFile(temp_file) catch {};

        if (version == null) {
            std.debug.print("Failed to parse version information from repository.\n", .{});
        }

        return version;
    }

    fn getLatestAdbVersionFallback(self: Self) !?[]u8 {
        const home = try self.file_utils.getUserHomeDir();
        defer self.allocator.free(home);

        const temp_file = try std.fmt.allocPrint(self.allocator, "{s}\\android_repo.xml", .{home});
        defer self.allocator.free(temp_file);

        if (!try self.file_utils.downloadFile(REPO_URL, temp_file)) {
            return null;
        }

        const file = std.fs.cwd().openFile(temp_file, .{}) catch return null;
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch return null;
        defer self.allocator.free(content);

        const version = try self.xml_utils.extractVersionFromXml(content);
        self.file_utils.deleteFile(temp_file) catch {};

        return version;
    }

    fn extractCurrentBuildVersion(self: Self, version_output: []const u8) !?[]u8 {
        const version_start = std.mem.indexOf(u8, version_output, "Version ") orelse return null;
        const line_start = version_start + "Version ".len;

        var line_end = line_start;
        while (line_end < version_output.len) {
            const c = version_output[line_end];
            if (c == '\n' or c == '\r') break;
            line_end += 1;
        }

        const version_line = version_output[line_start..line_end];

        var version_end: usize = 0;
        for (version_line, 0..) |c, i| {
            if (c == '-' or c == ' ' or c == '\t') {
                version_end = i;
                break;
            }
        }

        if (version_end == 0) version_end = version_line.len;

        const version_str = std.mem.trim(u8, version_line[0..version_end], " \t\n\r");
        return try self.allocator.dupe(u8, version_str);
    }

    fn removeExistingAdbFromPath(self: Self) !void {
        var current_adb = try self.checkInstallation();
        defer current_adb.deinit(self.allocator);

        if (!current_adb.installed or current_adb.path.len == 0) {
            return;
        }

        if (std.mem.lastIndexOfScalar(u8, current_adb.path, '\\')) |last_slash| {
            const adb_dir = current_adb.path[0..last_slash];
            std.debug.print("Removing existing ADB directory from PATH: {s}\n", .{adb_dir});
            try self.path_manager.removeFromPath(adb_dir);
        }
    }

    pub fn install(self: Self) !bool {
        var current_adb = try self.checkInstallation();
        defer current_adb.deinit(self.allocator);

        if (current_adb.installed) {
            Console.printWarning("ADB is already installed", .{});
            std.debug.print("Version: {s}\n", .{current_adb.version});
            std.debug.print("Path: {s}\n", .{current_adb.path});
            Console.printInfo("Use 'Update ADB' option if you want to update to latest version", .{});
            return true;
        }

        return try self.downloadAndInstall();
    }

    pub fn update(self: Self) !bool {
        var current_adb = try self.checkInstallation();
        defer current_adb.deinit(self.allocator);

        if (!current_adb.installed) {
            std.debug.print("ADB not found. Installing...\n", .{});
            return try self.downloadAndInstall();
        }

        const latest_version = try self.getLatestAdbVersion();
        if (latest_version == null) {
            std.debug.print("Could not determine latest ADB version.\n", .{});
            return false;
        }
        defer if (latest_version) |v| self.allocator.free(v);

        const current_build_version = try self.extractCurrentBuildVersion(current_adb.version);
        if (current_build_version == null) {
            std.debug.print("Could not parse current ADB version.\n", .{});
            return false;
        }
        defer if (current_build_version) |v| self.allocator.free(v);

        if (std.mem.eql(u8, current_build_version.?, latest_version.?)) {
            std.debug.print("ADB is already up to date (version {s}).\n", .{current_adb.version});
            return true;
        }

        std.debug.print("Current ADB version: {s}\n", .{current_adb.version});
        std.debug.print("Latest ADB version: {s}\n", .{latest_version.?});
        std.debug.print("Updating ADB...\n", .{});

        try self.removeExistingAdbFromPath();

        return try self.downloadAndInstall();
    }

    fn downloadAndInstall(self: Self) !bool {
        Console.printInfo("Downloading ADB platform-tools...", .{});

        const home = try self.file_utils.getUserHomeDir();
        defer self.allocator.free(home);

        const download_path = try std.fmt.allocPrint(self.allocator, "{s}\\Downloads\\platform-tools.zip", .{home});
        defer self.allocator.free(download_path);

        const extract_path = home;

        if (!try self.file_utils.downloadFile(PLATFORM_TOOLS_URL, download_path)) {
            Console.printError("Download failed", .{});
            return false;
        }

        if (!self.file_utils.fileExists(download_path)) {
            Console.printError("Downloaded file doesn't exist", .{});
            return false;
        }

        const file_size = try self.file_utils.getFileSize(download_path);
        if (file_size < 1000000) {
            Console.printError("Downloaded file seems too small. Might be corrupted", .{});
            return false;
        }

        Console.printInfo("Extracting ADB tools...", .{});

        if (!try self.zip_utils.extractZip(download_path, extract_path)) {
            Console.printError("Extraction failed", .{});
            return false;
        }

        Console.printInfo("Updating system PATH...", .{});
        const platform_tools_path = try std.fmt.allocPrint(self.allocator, "{s}\\platform-tools", .{home});
        defer self.allocator.free(platform_tools_path);

        if (!try self.path_manager.addToPath(platform_tools_path)) {
            Console.printError("Failed to update PATH", .{});
            return false;
        }

        Console.printInfo("Cleaning up temporary files...", .{});
        self.file_utils.deleteFile(download_path) catch |err| {
            Console.printWarning("Could not delete temporary file: {}", .{err});
        };

        Console.printSuccess("ADB platform-tools installed successfully!", .{});
        Console.printInfo("Note: You may need to restart your terminal to use ADB commands", .{});
        return true;
    }
};
