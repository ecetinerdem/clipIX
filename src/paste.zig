const std = @import("std");
const win32 = @import("win32.zig");
const windows = win32.windows;
const clipboard = @import("clipboard.zig");
const slots = @import("slots.zig");
const capture = @import("capture.zig");

fn sendKey(vk: windows.WORD, key_up: bool) void {
    var input: win32.INPUT = std.mem.zeroes(win32.INPUT);
    input.type = win32.INPUT_KEYBOARD;
    input.u.ki = .{
        .wVk = vk,
        .wScan = 0,
        .dwFlags = if (key_up) win32.KEYEVENTF_KEYUP else 0,
        .time = 0,
        .dwExtraInfo = 0,
    };
    _ = win32.SendInput(1, @ptrCast(&input), @sizeOf(win32.INPUT));
}

/// Synthesizes a real Ctrl+V keystroke. Because it goes through SendInput,
/// Windows marks it LLKHF_INJECTED — our own hook must recognize and ignore
/// these events rather than re-processing them as a fresh chord attempt.
pub fn injectCtrlV() void {
    sendKey(@intCast(win32.VK_CONTROL), false);
    sendKey(@intCast(win32.VK_V), false);
    sendKey(@intCast(win32.VK_V), true);
    sendKey(@intCast(win32.VK_CONTROL), true);
}

/// No digit followed Ctrl+V in time (or Ctrl was released early) — the user
/// meant a normal paste. We already swallowed the real V, so replay it.
/// The real clipboard was never touched, so this is indistinguishable from
/// an unsuppressed Ctrl+V.
pub fn replayNormalPaste() void {
    injectCtrlV();
}

fn writeTextFormat(allocator: std.mem.Allocator, text: []const u8) !void {
    const wide_buf = try allocator.alloc(u16, text.len + 1);
    defer allocator.free(wide_buf);
    const wlen = try windows.wtf8ToWtf16Le(wide_buf, text);

    const total_bytes = (wlen + 1) * 2;
    const hmem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, total_bytes) orelse return error.GlobalAllocFailed;
    const ptr = win32.GlobalLock(hmem) orelse {
        _ = win32.GlobalFree(hmem);
        return error.GlobalLockFailed;
    };
    const dest: [*]u16 = @ptrCast(@alignCast(ptr));
    @memcpy(dest[0..wlen], wide_buf[0..wlen]);
    dest[wlen] = 0;
    _ = win32.GlobalUnlock(hmem);

    if (win32.SetClipboardData(win32.CF_UNICODETEXT, hmem) == null) {
        _ = win32.GlobalFree(hmem);
        return error.SetClipboardDataFailed;
    }
}

fn writeFilesFormat(allocator: std.mem.Allocator, paths: []const []const u8) !void {
    var payload: std.ArrayList(u16) = .empty;
    defer payload.deinit(allocator);

    for (paths) |path| {
        var wide_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
        const wlen = windows.wtf8ToWtf16Le(&wide_buf, path) catch continue;
        try payload.appendSlice(allocator, wide_buf[0..wlen]);
        try payload.append(allocator, 0);
    }
    try payload.append(allocator, 0); // extra terminating null (double-null overall)

    const header_bytes = @sizeOf(win32.DROPFILES);
    const total_bytes = header_bytes + payload.items.len * 2;

    const hmem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, total_bytes) orelse return error.GlobalAllocFailed;
    const ptr = win32.GlobalLock(hmem) orelse {
        _ = win32.GlobalFree(hmem);
        return error.GlobalLockFailed;
    };

    const header: *win32.DROPFILES = @ptrCast(@alignCast(ptr));
    header.* = .{
        .pFiles = header_bytes,
        .pt = .{ .x = 0, .y = 0 },
        .fNC = .FALSE,
        .fWide = .TRUE,
    };
    const dest: [*]u8 = @ptrCast(ptr);
    const payload_bytes = std.mem.sliceAsBytes(payload.items);
    @memcpy(dest[header_bytes..][0..payload_bytes.len], payload_bytes);
    _ = win32.GlobalUnlock(hmem);

    if (win32.SetClipboardData(win32.CF_HDROP, hmem) == null) {
        _ = win32.GlobalFree(hmem);
        return error.SetClipboardDataFailed;
    }
}

/// Writes both CF_HDROP (so Explorer pastes real files) and CF_UNICODETEXT
/// (so text-only apps get the paths as text) in one clipboard session, per
/// the spec's Smart Paste Rules — this covers both destinations without
/// needing to detect which app is focused.
fn setClipboardObjects(allocator: std.mem.Allocator, objects: []const clipboard.ClipboardObject) !void {
    capture.suppress_next_clipboard_event = true;
    if (win32.OpenClipboard(null) == .FALSE) return error.OpenClipboardFailed;

    if (win32.OpenClipboard(null) == .FALSE) return error.OpenClipboardFailed;
    defer _ = win32.CloseClipboard();
    _ = win32.EmptyClipboard();

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);
    var text_parts: std.ArrayList(u8) = .empty;
    defer text_parts.deinit(allocator);

    for (objects, 0..) |obj, i| {
        const value = switch (obj) {
            inline else => |v| v,
        };
        if (i != 0) try text_parts.appendSlice(allocator, "\r\n");
        try text_parts.appendSlice(allocator, value);
        switch (obj) {
            .file, .directory => |v| try paths.append(allocator, v),
            .text => {},
        }
    }

    if (paths.items.len > 0) {
        writeFilesFormat(allocator, paths.items) catch |err| {
            std.debug.print("writeFilesFormat failed: {}\n", .{err});
        };
    }
    if (text_parts.items.len > 0) {
        writeTextFormat(allocator, text_parts.items) catch |err| {
            std.debug.print("writeTextFormat failed: {}\n", .{err});
        };
    }
}

pub fn pasteSlot(allocator: std.mem.Allocator, slot: u4) void {
    const objects = slots.get(slot);
    if (objects.len == 0) {
        std.debug.print("Slot {d} is empty, nothing to paste\n", .{slot});
        return;
    }
    setClipboardObjects(allocator, objects) catch |err| {
        std.debug.print("Failed to write clipboard for paste: {}\n", .{err});
        return;
    };
    win32.Sleep(30); // let the clipboard settle before the app reads it
    injectCtrlV();
}

pub fn pasteBatchAll(allocator: std.mem.Allocator) void {
    var slot: u4 = 1;
    while (slot < slots.NUM_SLOTS) : (slot += 1) {
        if (!slots.isEmpty(slot)) {
            pasteSlot(allocator, slot);
            win32.Sleep(80); // give the target app time to process each paste
        }
    }
}
