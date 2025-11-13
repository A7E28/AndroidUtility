const std = @import("std");
const windows = std.os.windows;

const OPENFILENAMEA = extern struct {
    lStructSize: windows.DWORD,
    hwndOwner: ?windows.HWND,
    hInstance: ?windows.HINSTANCE,
    lpstrFilter: ?[*:0]const u8,
    lpstrCustomFilter: ?[*:0]u8,
    nMaxCustFilter: windows.DWORD,
    nFilterIndex: windows.DWORD,
    lpstrFile: [*:0]u8,
    nMaxFile: windows.DWORD,
    lpstrFileTitle: ?[*:0]u8,
    nMaxFileTitle: windows.DWORD,
    lpstrInitialDir: ?[*:0]const u8,
    lpstrTitle: ?[*:0]const u8,
    Flags: windows.DWORD,
    nFileOffset: windows.WORD,
    nFileExtension: windows.WORD,
    lpstrDefExt: ?[*:0]const u8,
    lCustData: windows.LPARAM,
    lpfnHook: ?*anyopaque,
    lpTemplateName: ?[*:0]const u8,
};

extern "comdlg32" fn GetOpenFileNameA(lpofn: *OPENFILENAMEA) callconv(.winapi) windows.BOOL;

const OFN_PATHMUSTEXIST: windows.DWORD = 0x00000800;
const OFN_FILEMUSTEXIST: windows.DWORD = 0x00001000;
const OFN_HIDEREADONLY: windows.DWORD = 0x00000004;

pub const FileDialog = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn openFileDialog(self: Self, title: []const u8) !?[]u8 {
        var file_buffer: [260:0]u8 = std.mem.zeroes([260:0]u8);

        const title_z = try self.allocator.dupeZ(u8, title);
        defer self.allocator.free(title_z);

        var ofn = OPENFILENAMEA{
            .lStructSize = @sizeOf(OPENFILENAMEA),
            .hwndOwner = null,
            .hInstance = null,
            .lpstrFilter = "All Files\x00*.*\x00\x00",
            .lpstrCustomFilter = null,
            .nMaxCustFilter = 0,
            .nFilterIndex = 1,
            .lpstrFile = file_buffer[0..].ptr,
            .nMaxFile = file_buffer.len,
            .lpstrFileTitle = null,
            .nMaxFileTitle = 0,
            .lpstrInitialDir = null,
            .lpstrTitle = title_z.ptr,
            .Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY,
            .nFileOffset = 0,
            .nFileExtension = 0,
            .lpstrDefExt = null,
            .lCustData = 0,
            .lpfnHook = null,
            .lpTemplateName = null,
        };

        if (GetOpenFileNameA(&ofn) != 0) {
            const path_len = std.mem.indexOfScalar(u8, &file_buffer, 0) orelse file_buffer.len;
            return try self.allocator.dupe(u8, file_buffer[0..path_len]);
        }

        return null;
    }

    pub fn saveFileDialog(self: Self, title: []const u8, filter: []const u8) !?[]u8 {
        _ = filter;

        std.debug.print("{s}\n", .{title});
        std.debug.print("Enter full path for output file: ", .{});

        var read_buffer: [4096]u8 = undefined;
        var file_reader = std.fs.File.stdin().reader(&read_buffer);
        var stdin = &file_reader.interface;

        const input = stdin.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) return null;
            return err;
        };
        const trimmed = std.mem.trim(u8, input, " \t\r");
        if (trimmed.len > 0) {
            return try self.allocator.dupe(u8, trimmed);
        }

        return null;
    }
};
