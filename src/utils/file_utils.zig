const std = @import("std");
const windows = std.os.windows;

/// HRESULT was removed from std.os.windows in Zig 0.16; it's just i32
pub const HRESULT = i32;
/// LRESULT was removed from std.os.windows in Zig 0.16; it's just isize (LONG_PTR)
pub const LRESULT = isize;
pub const WPARAM = usize;

extern "urlmon" fn URLDownloadToFileA(
    pCaller: ?*anyopaque,
    szURL: [*:0]const u8,
    szFileName: [*:0]const u8,
    dwReserved: windows.DWORD,
    lpfnCB: ?*anyopaque,
) callconv(.winapi) HRESULT;

extern "shell32" fn SHGetFolderPathA(
    hwnd: ?windows.HWND,
    csidl: i32,
    hToken: ?windows.HANDLE,
    dwFlags: windows.DWORD,
    pszPath: [*]u8,
) callconv(.winapi) HRESULT;

extern "user32" fn SendMessageTimeoutA(
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
        var path_buffer: [MAX_PATH]u8 = undefined;
        const result = SHGetFolderPathA(null, CSIDL_PROFILE, null, 0, &path_buffer);

        if (result != S_OK) return error.PathError;

        const path_len = std.mem.indexOfScalar(u8, &path_buffer, 0) orelse MAX_PATH;
        return try self.allocator.dupe(u8, path_buffer[0..path_len]);
    }

    pub fn getAppDataDir(self: Self) ![]u8 {
        var path_buffer: [MAX_PATH]u8 = undefined;
        const result = SHGetFolderPathA(null, CSIDL_LOCAL_APPDATA, null, 0, &path_buffer);

        if (result != S_OK) return error.PathError;

        const path_len = std.mem.indexOfScalar(u8, &path_buffer, 0) orelse MAX_PATH;
        return try self.allocator.dupe(u8, path_buffer[0..path_len]);
    }

    pub fn downloadFile(self: Self, url: []const u8, output_path: []const u8) !bool {
        const url_z = try self.allocator.dupeZ(u8, url);
        defer self.allocator.free(url_z);

        const output_z = try self.allocator.dupeZ(u8, output_path);
        defer self.allocator.free(output_z);

        const result = URLDownloadToFileA(null, url_z.ptr, output_z.ptr, 0, null);
        return result == S_OK;
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
        const environment_z = "Environment\x00";
        _ = SendMessageTimeoutA(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            0,
            @intCast(@intFromPtr(environment_z.ptr)),
            SMTO_ABORTIFHUNG,
            5000,
            null,
        );
    }
};
