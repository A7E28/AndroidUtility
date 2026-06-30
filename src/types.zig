const std = @import("std");

pub const AdbInfo = struct {
    installed: bool,
    version: []const u8,
    path: []const u8,

    pub fn init() AdbInfo {
        return AdbInfo{
            .installed = false,
            .version = "",
            .path = "",
        };
    }

    pub fn deinit(self: *AdbInfo, allocator: std.mem.Allocator) void {
        if (self.version.len > 0) allocator.free(self.version);
        if (self.path.len > 0) allocator.free(self.path);
    }
};

pub const HashAlgorithm = enum {
    MD5,
    SHA1,
    SHA256,
};

pub const AppError = error{
    DownloadFailed,
    ExtractionFailed,
    PathUpdateFailed,
    FileNotFound,
    RegistryError,
    AllocationError,
};
