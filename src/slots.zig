const std = @import("std");
const clipboard = @import("clipboard.zig");
const database = @import("database.zig");
const ClipboardObject = clipboard.ClipboardObject;

pub const NUM_SLOTS = 10;

var slots: [NUM_SLOTS]std.ArrayList(ClipboardObject) = @splat(.empty);

pub fn clear(allocator: std.mem.Allocator, slot: u4) void {
    const list = &slots[slot];
    for (list.items) |obj| obj.deinit(allocator);
    list.clearRetainingCapacity();
}

pub fn store(allocator: std.mem.Allocator, slot: u4, objects: []const ClipboardObject) !void {
    clear(allocator, slot);
    try slots[slot].appendSlice(allocator, objects);

    database.clearSlotRows(slot) catch |err| {
        std.debug.print("DB clear failed for slot {d}: {}\n", .{ slot, err });
    };
    for (objects, 0..) |obj, i| {
        const kind: []const u8, const value: []const u8 = switch (obj) {
            .text => |v| .{ "text", v },
            .file => |v| .{ "file", v },
            .directory => |v| .{ "directory", v },
        };
        database.insertRow(slot, i, kind, value) catch |err| {
            std.debug.print("DB insert failed for slot {d}: {}\n", .{ slot, err });
        };
    }
}

pub fn get(slot: u4) []const ClipboardObject {
    return slots[slot].items;
}

pub fn isEmpty(slot: u4) bool {
    return slots[slot].items.len == 0;
}
pub fn deinitAll(allocator: std.mem.Allocator) void {
    var slot: u4 = 0;
    while (slot < NUM_SLOTS) : (slot += 1) {
        clear(allocator, slot);
        slots[slot].deinit(allocator);
    }
}
