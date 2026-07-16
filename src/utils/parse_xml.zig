const std = @import("std");

pub const XmlUtils = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn extractVersionFromXml(self: Self, xml_content: []const u8) !?[]u8 {
        var search_pos: usize = 0;
        while (search_pos < xml_content.len) {
            const package_attr = "path=\"platform-tools\"";
            const package_start = std.mem.indexOf(u8, xml_content[search_pos..], package_attr) orelse return null;
            const absolute_start = search_pos + package_start;

            const block_start = std.mem.lastIndexOfScalar(u8, xml_content[0..absolute_start], '<') orelse return null;
            const block_end_rel = std.mem.indexOf(u8, xml_content[absolute_start..], "</remotePackage>") orelse return null;
            const block_end = absolute_start + block_end_rel + "</remotePackage>".len;

            const package_block = xml_content[block_start..block_end];

            if (std.mem.indexOf(u8, package_block, "<channelRef ref=\"channel-0\"/>") != null) {
                const revision_start = std.mem.indexOf(u8, package_block, "<revision>") orelse return null;
                const revision_end = std.mem.indexOf(u8, package_block[revision_start..], "</revision>") orelse return null;

                const revision_block = package_block[revision_start .. revision_start + revision_end];

                const major = self.extractValueBetweenTags(revision_block, "<major>", "</major>") orelse return null;
                const minor = self.extractValueBetweenTags(revision_block, "<minor>", "</minor>") orelse return null;
                const micro = self.extractValueBetweenTags(revision_block, "<micro>", "</micro>") orelse return null;

                return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}", .{ major, minor, micro });
            }

            search_pos = block_end;
        }
        return null;
    }

    fn extractValueBetweenTags(self: Self, content: []const u8, start_tag: []const u8, end_tag: []const u8) ?[]const u8 {
        _ = self;
        const start_pos = std.mem.indexOf(u8, content, start_tag) orelse return null;
        const value_start = start_pos + start_tag.len;
        const value_end = std.mem.indexOf(u8, content[value_start..], end_tag) orelse return null;

        return std.mem.trim(u8, content[value_start .. value_start + value_end], " \t\n\r");
    }
};
