const std = @import("std");
const sqlite = @import("sqlite");

const DB_PATH = "C:\\Windows\\Temp\\clipix.db";

var db: sqlite.Db = undefined;
var io: std.Io = undefined;

pub fn init(io_: std.Io) !void {
    io = io_;
    const cwd: std.Io.Dir = .cwd();
    cwd.deleteFile(io, DB_PATH) catch |err| {
        std.debug.print("Note: could not delete old {s}: {}\n", .{ DB_PATH, err });
    };

    db = try sqlite.Db.init(.{
        .mode = .{ .File = DB_PATH },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS slot_items (
        \\  slot INTEGER NOT NULL,
        \\  position INTEGER NOT NULL,
        \\  kind TEXT NOT NULL,
        \\  value TEXT NOT NULL
        \\);
    , .{}, .{});
}

pub fn deinit() void {
    db.deinit();
    const cwd: std.Io.Dir = .cwd();
    cwd.deleteFile(io, DB_PATH) catch {};
}

pub fn clearSlotRows(slot: u4) !void {
    try db.exec("DELETE FROM slot_items WHERE slot = ?;", .{}, .{ .slot = @as(u32, slot) });
}

pub fn insertRow(slot: u4, position: usize, kind: []const u8, value: []const u8) !void {
    const position_u32: u32 = @intCast(position);
    try db.exec(
        "INSERT INTO slot_items (slot, position, kind, value) VALUES (?, ?, ?, ?);",
        .{},
        .{
            .slot = @as(u32, slot),
            .position = position_u32,
            .kind = kind,
            .value = value,
        },
    );
}
