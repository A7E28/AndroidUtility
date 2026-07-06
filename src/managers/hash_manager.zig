const std = @import("std");
const types = @import("../types.zig");

const HashAlgorithm = types.HashAlgorithm;

const BufferSize = 1024 * 1024;
const SharedState = struct {
    file: std.Io.File,
    io: std.Io,

    buf_a: [BufferSize]u8 = undefined,
    buf_b: [BufferSize]u8 = undefined,
    len_a: usize = 0,
    len_b: usize = 0,

    ready_a: bool = false,
    ready_b: bool = false,

    mutex: std.Io.Mutex = .init,
    cond_reader: std.Io.Condition = .init,
    cond_hasher: std.Io.Condition = .init,

    eof: bool = false,
    read_error: ?anyerror = null,
};

fn readerThreadFn(state: *SharedState) void {
    var read_buf_a = true;

    while (true) {
        const target_buf = if (read_buf_a) &state.buf_a else &state.buf_b;
        const slices = &[_][]u8{target_buf};

        const amt = std.Io.File.readStreaming(state.file, state.io, slices) catch |err| {
            state.mutex.lockUncancelable(state.io);
            defer state.mutex.unlock(state.io);
            if (err == error.EndOfStream) {
                state.eof = true;
            } else {
                state.read_error = err;
                state.eof = true;
            }
            state.cond_hasher.signal(state.io);
            return;
        };

        state.mutex.lockUncancelable(state.io);
        if (read_buf_a) {
            while (state.ready_a) {
                state.cond_reader.waitUncancelable(state.io, &state.mutex);
            }
            state.len_a = amt;
            state.ready_a = true;
        } else {
            while (state.ready_b) {
                state.cond_reader.waitUncancelable(state.io, &state.mutex);
            }
            state.len_b = amt;
            state.ready_b = true;
        }
        state.mutex.unlock(state.io);

        state.cond_hasher.signal(state.io);
        read_buf_a = !read_buf_a;
    }
}

pub const HashManager = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn calculateFileHash(self: Self, file_path: []const u8, algorithm: HashAlgorithm) ![]u8 {
        var io_threaded = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .global },
        });
        defer io_threaded.deinit();
        const io = io_threaded.io();

        const file = try std.Io.Dir.openFileAbsolute(io, file_path, .{});
        defer std.Io.File.close(file, io);

        var state = try self.allocator.create(SharedState);
        defer self.allocator.destroy(state);
        state.* = .{
            .file = file,
            .io = io,
        };

        var md5_hasher = std.crypto.hash.Md5.init(.{});
        var sha1_hasher = std.crypto.hash.Sha1.init(.{});
        var sha256_hasher = std.crypto.hash.sha2.Sha256.init(.{});

        const thread = try std.Thread.spawn(.{}, readerThreadFn, .{state});

        var process_buf_a = true;
        while (true) {
            var len: usize = 0;
            var data: []u8 = undefined;

            state.mutex.lockUncancelable(io);
            while (true) {
                if (process_buf_a) {
                    if (state.ready_a) {
                        len = state.len_a;
                        data = state.buf_a[0..len];
                        break;
                    }
                } else {
                    if (state.ready_b) {
                        len = state.len_b;
                        data = state.buf_b[0..len];
                        break;
                    }
                }

                if (state.eof) {
                    state.mutex.unlock(io);
                    if (state.read_error) |err| return err;
                    break;
                }

                state.cond_hasher.waitUncancelable(io, &state.mutex);
            }

            if (len == 0) break;

            if (process_buf_a) {
                state.ready_a = false;
            } else {
                state.ready_b = false;
            }

            state.mutex.unlock(io);
            state.cond_reader.signal(io);

            switch (algorithm) {
                .MD5 => md5_hasher.update(data),
                .SHA1 => sha1_hasher.update(data),
                .SHA256 => sha256_hasher.update(data),
            }
            process_buf_a = !process_buf_a;
        }

        thread.join();

        switch (algorithm) {
            .MD5 => {
                var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
                md5_hasher.final(&digest);
                const hex_digest = std.fmt.bytesToHex(digest, .lower);
                return try self.allocator.dupe(u8, &hex_digest);
            },
            .SHA1 => {
                var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
                sha1_hasher.final(&digest);
                const hex_digest = std.fmt.bytesToHex(digest, .lower);
                return try self.allocator.dupe(u8, &hex_digest);
            },
            .SHA256 => {
                var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
                sha256_hasher.final(&digest);
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
