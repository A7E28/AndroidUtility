const std = @import("std");
const windows = std.os.windows;

const HKEY_CURRENT_USER: windows.HKEY = @ptrFromInt(0x80000001);
const KEY_READ: windows.DWORD = 0x20019;
const KEY_WRITE: windows.DWORD = 0x20006;
const REG_SZ: windows.DWORD = 1;

extern "advapi32" fn RegOpenKeyExA(
    hKey: windows.HKEY,
    lpSubKey: [*:0]const u8,
    ulOptions: windows.DWORD,
    samDesired: windows.DWORD,
    phkResult: *windows.HKEY,
) callconv(.winapi) windows.DWORD;

extern "advapi32" fn RegQueryValueExA(
    hKey: windows.HKEY,
    lpValueName: ?[*:0]const u8,
    lpReserved: ?*windows.DWORD,
    lpType: ?*windows.DWORD,
    lpData: ?[*]u8,
    lpcbData: ?*windows.DWORD,
) callconv(.winapi) windows.DWORD;

extern "advapi32" fn RegSetValueExA(
    hKey: windows.HKEY,
    lpValueName: [*:0]const u8,
    Reserved: windows.DWORD,
    dwType: windows.DWORD,
    lpData: [*]const u8,
    cbData: windows.DWORD,
) callconv(.winapi) windows.DWORD;

extern "advapi32" fn RegCloseKey(hKey: windows.HKEY) callconv(.winapi) windows.DWORD;

pub const RegistryManager = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn getValue(self: Self, key_path: [*:0]const u8, value_name: [*:0]const u8) ![]u8 {
        var hkey: windows.HKEY = undefined;

        const result = RegOpenKeyExA(HKEY_CURRENT_USER, key_path, 0, KEY_READ, &hkey);
        if (result != 0) return error.RegistryError;
        defer _ = RegCloseKey(hkey);

        var data_size: windows.DWORD = 0;
        var value_type: windows.DWORD = 0;

        const first_result = RegQueryValueExA(hkey, value_name, null, &value_type, null, &data_size);
        if (first_result != 0) return error.RegistryError;

        const buffer = try self.allocator.alloc(u8, data_size);

        const query_result = RegQueryValueExA(hkey, value_name, null, &value_type, buffer.ptr, &data_size);
        if (query_result != 0) {
            self.allocator.free(buffer);
            return error.RegistryError;
        }

        return self.allocator.realloc(buffer, data_size);
    }

    pub fn setValue(self: Self, key_path: [*:0]const u8, value_name: [*:0]const u8, value: []const u8) !void {
        var hkey: windows.HKEY = undefined;

        const result = RegOpenKeyExA(HKEY_CURRENT_USER, key_path, 0, KEY_READ | KEY_WRITE, &hkey);
        if (result != 0) return error.RegistryError;
        defer _ = RegCloseKey(hkey);

        const value_with_null = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{value});
        defer self.allocator.free(value_with_null);

        const set_result = RegSetValueExA(hkey, value_name, 0, REG_SZ, value_with_null.ptr, @intCast(value_with_null.len));
        if (set_result != 0) return error.RegistryError;
    }
};
