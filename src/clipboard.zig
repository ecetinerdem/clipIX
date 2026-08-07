const std = @import("std");
const win32 = @import("win32.zig");
const windows = win32.windows;

pub const ClipboardObject = union(enum) {
    text: []const u8,
    file: []const u8,
    directory: []const u8,

    pub fn deinit(self: ClipboardObject, allocator: std.mem.Allocator) void {
        switch (self) {
            inline else => |payload| allocator.free(payload),
        }
    }
};

pub fn readText(allocator: std.mem.Allocator) ?[]const u8 {
    if (win32.OpenClipboard(null) == .FALSE) return null;
    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(win32.CF_UNICODETEXT) orelse return null;
    const ptr = win32.GlobalLock(handle) orelse return null;
    defer _ = win32.GlobalUnlock(handle);

    const wide_ptr: [*:0]const u16 = @ptrCast(@alignCast(ptr));
    var len: usize = 0;
    while (wide_ptr[len] != 0) : (len += 1) {}

    return std.unicode.wtf16LeToWtf8Alloc(allocator, wide_ptr[0..len]) catch null;
}

pub fn readFiles(allocator: std.mem.Allocator) ?[]ClipboardObject {
    if (win32.OpenClipboard(null) == .FALSE) return null;
    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(win32.CF_HDROP) orelse return null;
    const hdrop: win32.HDROP = @ptrCast(handle);

    const count = win32.DragQueryFileW(hdrop, 0xFFFFFFFF, null, 0);
    if (count == 0) return null;

    var list: std.ArrayList(ClipboardObject) = .empty;
    errdefer {
        for (list.items) |obj| obj.deinit(allocator);
        list.deinit(allocator);
    }

    var path_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
    var i: windows.UINT = 0;
    while (i < count) : (i += 1) {
        const len = win32.DragQueryFileW(hdrop, i, &path_buf, path_buf.len);
        if (len == 0) continue;

        const utf8_path = std.unicode.wtf16LeToWtf8Alloc(allocator, path_buf[0..len]) catch continue;

        const attrs_raw = win32.GetFileAttributesW(&path_buf);
        const is_dir = attrs_raw != windows.INVALID_FILE_ATTRIBUTES and
            (@as(windows.FILE.ATTRIBUTE, @bitCast(attrs_raw))).DIRECTORY;

        const obj: ClipboardObject = if (is_dir) .{ .directory = utf8_path } else .{ .file = utf8_path };
        list.append(allocator, obj) catch {
            allocator.free(utf8_path);
            continue;
        };
    }

    if (list.items.len == 0) {
        list.deinit(allocator);
        return null;
    }
    return list.toOwnedSlice(allocator) catch null;
}
