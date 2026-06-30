const std = @import("std");
const types = @import("../types.zig");

const HashAlgorithm = types.HashAlgorithm;

pub const HashManager = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn calculateFileHash(self: Self, file_path: []const u8, algorithm: HashAlgorithm) ![]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        const file = try std.Io.Dir.openFileAbsolute(io, file_path, .{});
        defer std.Io.File.close(file, io);

        var buffer: [65536]u8 = undefined;
        var reader = file.reader(io, &buffer);

        switch (algorithm) {
            .MD5 => {
                var hasher = std.crypto.hash.Md5.init(.{});
                while (true) {
                    const bytes_read = try (&reader.interface).take(buffer.len);
                    if (bytes_read.len == 0) break;
                    hasher.update(bytes_read);
                }
                var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
                hasher.final(&digest);
                const hex_digest = std.fmt.bytesToHex(digest, .lower);
                return try self.allocator.dupe(u8, &hex_digest);
            },
            .SHA1 => {
                var hasher = std.crypto.hash.Sha1.init(.{});
                while (true) {
                    const bytes_read = try (&reader.interface).take(buffer.len);
                    if (bytes_read.len == 0) break;
                    hasher.update(bytes_read);
                }
                var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
                hasher.final(&digest);
                const hex_digest = std.fmt.bytesToHex(digest, .lower);
                return try self.allocator.dupe(u8, &hex_digest);
            },
            .SHA256 => {
                var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                while (true) {
                    const bytes_read = try (&reader.interface).take(buffer.len);
                    if (bytes_read.len == 0) break;
                    hasher.update(bytes_read);
                }
                var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
                hasher.final(&digest);
                const hex_digest = std.fmt.bytesToHex(digest, .lower);
                return try self.allocator.dupe(u8, &hex_digest);
            },
        }
    }

    pub fn calculateMD5(self: Self, file_path: []const u8) ![]u8 {
        return try self.calculateFileHash(file_path, .MD5);
    }

    pub fn calculateSHA1(self: Self, file_path: []const u8) ![]u8 {
        return try self.calculateFileHash(file_path, .SHA1);
    }

    pub fn calculateSHA256(self: Self, file_path: []const u8) ![]u8 {
        return try self.calculateFileHash(file_path, .SHA256);
    }
};
