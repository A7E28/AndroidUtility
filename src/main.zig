const std = @import("std");
const MenuManager = @import("managers/menu_manager.zig").MenuManager;
const Console = @import("utils/console.zig").Console;

pub fn main() !void {
    const builtin = @import("builtin");
    const allocator = if (builtin.mode == .Debug)
        blk: {
            var dbg: std.heap.DebugAllocator(.{}) = .init;
            break :blk dbg.allocator();
        }
    else
        std.heap.smp_allocator;

    const menu_manager = MenuManager.init(allocator);

    Console.clearScreen();
    while (true) {
        menu_manager.displayMainMenu();
        const choice = try Console.getUserChoice();

        if (choice == 6) {
            _ = try menu_manager.handleMainMenuChoice(choice);
            break;
        }

        const should_continue = try menu_manager.handleMainMenuChoice(choice);
        if (!should_continue) break;

        if (choice != 5) {
            Console.pause();
        }
        Console.clearScreen();
    }
}


