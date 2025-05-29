const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;

extern "urlmon" fn URLDownloadToFileA(
    pCaller: ?*anyopaque,
    szURL: [*:0]const u8,
    szFileName: [*:0]const u8,
    dwReserved: windows.DWORD,
    lpfnCB: ?*anyopaque,
) callconv(WINAPI) windows.HRESULT;

extern "shell32" fn SHGetFolderPathA(
    hwnd: ?windows.HWND,
    csidl: i32,
    hToken: ?windows.HANDLE,
    dwFlags: windows.DWORD,
    pszPath: [*]u8,
) callconv(WINAPI) windows.HRESULT;

extern "user32" fn SendMessageTimeoutA(
    hWnd: windows.HWND,
    Msg: windows.UINT,
    wParam: windows.WPARAM,
    lParam: windows.LPARAM,
    fuFlags: windows.UINT,
    uTimeout: windows.UINT,
    lpdwResult: ?*windows.DWORD,
) callconv(WINAPI) windows.LRESULT;

const CSIDL_PROFILE: i32 = 40;
const MAX_PATH: usize = 260;
const S_OK: windows.HRESULT = 0;
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
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    pub fn getFileSize(self: Self, path: []const u8) !u64 {
        _ = self;
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        return stat.size;
    }

    pub fn deleteFile(self: Self, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().deleteFile(path);
    }

    // Notify system of PATH changes
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
