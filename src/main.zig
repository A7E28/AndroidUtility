const std = @import("std");
const MenuManager = @import("managers/menu_manager.zig").MenuManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const menu_manager = MenuManager.init(allocator);

    while (true) {
        menu_manager.displayMainMenu();
        const choice = try getUserChoice();

        const should_continue = try menu_manager.handleMainMenuChoice(choice);
        if (!should_continue) break;
    }
}

fn getUserChoice() !u32 {
    var read_buffer: [4096]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&read_buffer);
    var stdin = &file_reader.interface;

    const input = stdin.takeDelimiterExclusive('\n') catch |err| {
        if (err == error.EndOfStream) return 0;
        return err;
    };
    const trimmed = std.mem.trim(u8, input, " \t\r");
    return std.fmt.parseInt(u32, trimmed, 10) catch 0;
}
