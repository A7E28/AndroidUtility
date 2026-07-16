const std = @import("std");
const windows = std.os.windows;

pub const HRESULT = i32;
pub const LRESULT = isize;
pub const WPARAM = usize;

extern "shell32" fn SHGetFolderPathW(
    hwnd: ?windows.HWND,
    csidl: i32,
    hToken: ?windows.HANDLE,
    dwFlags: windows.DWORD,
    pszPath: [*]u16,
) callconv(.winapi) HRESULT;

extern "user32" fn SendMessageTimeoutW(
    hWnd: windows.HWND,
    Msg: windows.UINT,
    wParam: WPARAM,
    lParam: windows.LPARAM,
    fuFlags: windows.UINT,
    uTimeout: windows.UINT,
    lpdwResult: ?*windows.DWORD,
) callconv(.winapi) LRESULT;

const CSIDL_PROFILE: i32 = 40;
const CSIDL_LOCAL_APPDATA: i32 = 0x001c;
const MAX_PATH: usize = 260;
const S_OK: HRESULT = 0;
const HWND_BROADCAST: windows.HWND = @ptrFromInt(0xFFFF);
const WM_SETTINGCHANGE: windows.UINT = 0x001A;
const SMTO_ABORTIFHUNG: windows.UINT = 0x0002;

pub const FileUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn getUserHomeDir(self: Self) ![]u8 {
        var path_buffer: [MAX_PATH]u16 = undefined;
        const result = SHGetFolderPathW(null, CSIDL_PROFILE, null, 0, &path_buffer);

        if (result != S_OK) return error.PathError;

        const path_len = std.mem.indexOfScalar(u16, &path_buffer, 0) orelse MAX_PATH;
        return try std.unicode.utf16LeToUtf8Alloc(self.allocator, path_buffer[0..path_len]);
    }

    pub fn getAppDataDir(self: Self) ![]u8 {
        var path_buffer: [MAX_PATH]u16 = undefined;
        const result = SHGetFolderPathW(null, CSIDL_LOCAL_APPDATA, null, 0, &path_buffer);

        if (result != S_OK) return error.PathError;

        const path_len = std.mem.indexOfScalar(u16, &path_buffer, 0) orelse MAX_PATH;
        return try std.unicode.utf16LeToUtf8Alloc(self.allocator, path_buffer[0..path_len]);
    }

    pub fn downloadFile(self: Self, url: []const u8, output_path: []const u8) !bool {
        const io = std.Io.Threaded.global_single_threaded.io();
        var client = std.http.Client{ .allocator = self.allocator, .io = io };
        defer client.deinit();

        const cwd = std.Io.Dir.cwd();
        const file = std.Io.Dir.createFile(cwd, io, output_path, .{}) catch return false;
        defer std.Io.File.close(file, io);

        var writer_buf: [8192]u8 = undefined;
        var f_writer = file.writer(io, &writer_buf);
        var redirect_buf: [1024]u8 = undefined;

        const res = client.fetch(.{
            .location = .{ .url = url },
            .redirect_buffer = &redirect_buf,
            .response_writer = &f_writer.interface,
        }) catch return false;

        f_writer.flush() catch return false;

        return res.status == .ok;
    }

    pub fn fileExists(self: Self, path: []const u8) bool {
        _ = self;
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
        return true;
    }

    pub fn getFileSize(self: Self, path: []const u8) !u64 {
        _ = self;
        const io = std.Io.Threaded.global_single_threaded.io();
        const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
        defer std.Io.File.close(file, io);
        const stat = try file.stat(io);
        return stat.size;
    }

    pub fn deleteFile(self: Self, path: []const u8) !void {
        _ = self;
        const io = std.Io.Threaded.global_single_threaded.io();
        try std.Io.Dir.deleteFileAbsolute(io, path);
    }

    pub fn broadcastEnvironmentChange(self: Self) void {
        _ = self;
        const environment_w = std.unicode.utf8ToUtf16LeStringLiteral("Environment");
        _ = SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            0,
            @intCast(@intFromPtr(environment_w.ptr)),
            SMTO_ABORTIFHUNG,
            5000,
            null,
        );
    }
};
