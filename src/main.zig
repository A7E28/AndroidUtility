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
    const stdin = std.io.getStdIn().reader();
    var buffer: [16]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        return std.fmt.parseInt(u32, trimmed, 10) catch {
            return 0;
        };
    }
    return 0;
}
