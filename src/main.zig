const std = @import("std");
const win32 = @import("win32.zig");
const keyboard = @import("keyboard.zig");
const clipboard = @import("clipboard.zig");
const slots = @import("slots.zig");
const database = @import("database.zig");
const paste = @import("paste.zig");
const capture = @import("capture.zig");

var gpa_allocator: std.mem.Allocator = undefined;

fn wndProc(hWnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_CLIPBOARDUPDATE => {
            if (capture.suppress_next_clipboard_event) {
                capture.suppress_next_clipboard_event = false;
            } else if (keyboard.pending_slot) |slot| {
                _ = capture.tryStore(gpa_allocator, slot);
                keyboard.pending_slot = null;
            }
        },
        win32.WM_TIMER => {
            if (wParam == keyboard.PASTE_TIMER_ID) {
                _ = win32.KillTimer(hWnd, keyboard.PASTE_TIMER_ID);
                if (keyboard.awaiting_digit_paste) {
                    keyboard.awaiting_digit_paste = false;
                    paste.replayNormalPaste();
                }
            }
        },
        else => {},
    }
    return win32.DefWindowProcW(hWnd, msg, wParam, lParam);
}

pub fn main(init: std.process.Init) !void {
    gpa_allocator = init.gpa;

    try database.init(init.io);
    defer database.deinit();

    keyboard.hook_handle = win32.SetWindowsHookExW(win32.WH_KEYBOARD_LL, keyboard.hookProc, null, 0);
    if (keyboard.hook_handle == null) {
        std.debug.print("Failed to install keyboard hook\n", .{});
        return error.HookInstallFailed;
    }
    defer _ = win32.UnhookWindowsHookEx(keyboard.hook_handle.?);
    defer slots.deinitAll(gpa_allocator);

    const hInstance: win32.HINSTANCE = @ptrCast(win32.GetModuleHandleW(null));
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("ClipIXHiddenWindow");

    var wc = win32.WNDCLASSEXW{
        .lpfnWndProc = wndProc,
        .hInstance = hInstance,
        .lpszClassName = class_name,
    };
    _ = win32.RegisterClassExW(&wc);

    const clip_hwnd = win32.CreateWindowExW(
        0,
        class_name,
        null,
        0,
        0,
        0,
        0,
        0,
        win32.HWND_MESSAGE,
        null,
        hInstance,
        null,
    ) orelse return error.WindowCreationFailed;

    _ = win32.AddClipboardFormatListener(clip_hwnd);
    defer _ = win32.RemoveClipboardFormatListener(clip_hwnd);

    keyboard.allocator = gpa_allocator;
    keyboard.hidden_hwnd = clip_hwnd;

    _ = std.process.spawn(init.io, .{
        // Fix this path based on your path to gui.exe
        .argv = &.{"gui/gui.exe"},
    }) catch |err| {
        std.debug.print("Failed to launch GUI: {}\n", .{err});
    };

    std.debug.print("Hook installed. Press keys to see events. Ctrl+C in this console won't stop it — close the window.\n", .{});
    var msg: win32.MSG = undefined;

    while (true) {
        const result: c_int = @intFromEnum(win32.GetMessageW(&msg, null, 0, 0));
        if (result <= 0) break;
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}
