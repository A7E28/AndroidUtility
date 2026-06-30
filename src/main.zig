const std = @import("std");
const MenuManager = @import("managers/menu_manager.zig").MenuManager;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const menu_manager = MenuManager.init(allocator);

    while (true) {
        menu_manager.displayMainMenu();
        const choice = try getUserChoice();

        const should_continue = try menu_manager.handleMainMenuChoice(choice);
        if (!should_continue) break;
    }
}

fn getUserChoice() !u32 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var read_buffer: [4096]u8 = undefined;
    const stdin_file = std.Io.File.stdin();
    var reader = stdin_file.reader(io, &read_buffer);

    const input = reader.interface.takeDelimiterExclusive('\n') catch |err| {
        if (err == error.EndOfStream) return 0;
        return err;
    };
    const trimmed = std.mem.trim(u8, input, " \t\r");
    return std.fmt.parseInt(u32, trimmed, 10) catch 0;
}
