const std = @import("std");
const clipboard = @import("clipboard.zig");
const slots = @import("slots.zig");

/// Set by paste.zig right before it writes to the real clipboard, so that
/// self-triggered WM_CLIPBOARDUPDATE notifications don't get mistaken for
/// a real user copy and overwrite a slot with pasted-back content.
pub var suppress_next_clipboard_event: bool = false;

/// Reads whatever is currently on the clipboard and stores it into `slot`.
/// Returns true if something was stored, false if no supported format found.
pub fn tryStore(allocator: std.mem.Allocator, slot: u4) bool {
    if (clipboard.readText(allocator)) |text| {
        const objects = [1]clipboard.ClipboardObject{.{ .text = text }};
        slots.store(allocator, slot, &objects) catch |err| {
            std.debug.print("Failed to store slot {d}: {}\n", .{ slot, err });
            allocator.free(text);
            return false;
        };
        std.debug.print("Stored into slot {d} (text)\n", .{slot});
        return true;
    } else if (clipboard.readFiles(allocator)) |objects| {
        defer allocator.free(objects);
        slots.store(allocator, slot, objects) catch |err| {
            std.debug.print("Failed to store slot {d}: {}\n", .{ slot, err });
            for (objects) |obj| obj.deinit(allocator);
            return false;
        };
        std.debug.print("Stored into slot {d} ({d} item(s))\n", .{ slot, objects.len });
        return true;
    }
    return false;
}
