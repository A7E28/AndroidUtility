const std = @import("std");

pub const XmlUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn extractVersionFromXml(self: Self, xml_content: []const u8) !?[]u8 {
        const package_start = std.mem.indexOf(u8, xml_content, "path=\"platform-tools\"") orelse return null;

        const block_start = std.mem.lastIndexOfScalar(u8, xml_content[0..package_start], '<') orelse return null;
        const block_end = std.mem.indexOf(u8, xml_content[package_start..], "</remotePackage>") orelse return null;

        const package_block = xml_content[block_start .. package_start + block_end];

        const revision_start = std.mem.indexOf(u8, package_block, "<revision>") orelse return null;
        const revision_end = std.mem.indexOf(u8, package_block[revision_start..], "</revision>") orelse return null;

        const revision_block = package_block[revision_start .. revision_start + revision_end];

        const major = self.extractValueBetweenTags(revision_block, "<major>", "</major>") orelse return null;
        const minor = self.extractValueBetweenTags(revision_block, "<minor>", "</minor>") orelse return null;
        const micro = self.extractValueBetweenTags(revision_block, "<micro>", "</micro>") orelse return null;

        return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}", .{ major, minor, micro });
    }

    fn extractValueBetweenTags(self: Self, content: []const u8, start_tag: []const u8, end_tag: []const u8) ?[]const u8 {
        _ = self;
        const start_pos = std.mem.indexOf(u8, content, start_tag) orelse return null;
        const value_start = start_pos + start_tag.len;
        const value_end = std.mem.indexOf(u8, content[value_start..], end_tag) orelse return null;

        return std.mem.trim(u8, content[value_start .. value_start + value_end], " \t\n\r");
    }
};
