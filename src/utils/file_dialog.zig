const std = @import("std");
const windows = std.os.windows;

const OPENFILENAMEW = extern struct {
    lStructSize: windows.DWORD,
    hwndOwner: ?windows.HWND,
    hInstance: ?windows.HINSTANCE,
    lpstrFilter: ?[*:0]const u16,
    lpstrCustomFilter: ?[*:0]u16,
    nMaxCustFilter: windows.DWORD,
    nFilterIndex: windows.DWORD,
    lpstrFile: [*:0]u16,
    nMaxFile: windows.DWORD,
    lpstrFileTitle: ?[*:0]u16,
    nMaxFileTitle: windows.DWORD,
    lpstrInitialDir: ?[*:0]const u16,
    lpstrTitle: ?[*:0]const u16,
    Flags: windows.DWORD,
    nFileOffset: windows.WORD,
    nFileExtension: windows.WORD,
    lpstrDefExt: ?[*:0]const u16,
    lCustData: windows.LPARAM,
    lpfnHook: ?*anyopaque,
    lpTemplateName: ?[*:0]const u16,
};

extern "comdlg32" fn GetOpenFileNameW(lpofn: *OPENFILENAMEW) callconv(.winapi) windows.BOOL;

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
        var file_buffer: [260:0]u16 = std.mem.zeroes([260:0]u16);

        const title_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, title);
        defer self.allocator.free(title_w);

        const filter_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, "All Files\x00*.*\x00\x00");
        defer self.allocator.free(filter_w);

        var ofn = OPENFILENAMEW{
            .lStructSize = @sizeOf(OPENFILENAMEW),
            .hwndOwner = null,
            .hInstance = null,
            .lpstrFilter = filter_w.ptr,
            .lpstrCustomFilter = null,
            .nMaxCustFilter = 0,
            .nFilterIndex = 1,
            .lpstrFile = file_buffer[0..].ptr,
            .nMaxFile = file_buffer.len,
            .lpstrFileTitle = null,
            .nMaxFileTitle = 0,
            .lpstrInitialDir = null,
            .lpstrTitle = title_w.ptr,
            .Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY,
            .nFileOffset = 0,
            .nFileExtension = 0,
            .lpstrDefExt = null,
            .lCustData = 0,
            .lpfnHook = null,
            .lpTemplateName = null,
        };

        if (@intFromEnum(GetOpenFileNameW(&ofn)) != 0) {
            const path_len = std.mem.indexOfScalar(u16, &file_buffer, 0) orelse file_buffer.len;
            return try std.unicode.utf16LeToUtf8Alloc(self.allocator, file_buffer[0..path_len]);
        }

        return null;
    }
};
