const std = @import("std");
const win32 = @import("win32.zig");
const windows = win32.windows;
const paste = @import("paste.zig");
const capture = @import("capture.zig");

const CHORD_TIMEOUT_MS: windows.DWORD = 600;
pub const PASTE_TIMER_ID: usize = 1001;

pub var hook_handle: ?win32.HHOOK = null;
pub var pending_slot: ?u4 = null;
pub var allocator: std.mem.Allocator = undefined;
pub var hidden_hwnd: ?win32.HWND = null;

var ctrl_held: bool = false;
var shift_held: bool = false;
var alt_held: bool = false;
var awaiting_digit: bool = false;
var c_pressed_at: windows.DWORD = 0;
pub var awaiting_digit_paste: bool = false;
var v_pressed_at: windows.DWORD = 0;
var v_suppressed: bool = false;
var digit_suppressed: bool = false;

pub fn hookProc(nCode: c_int, wParam: win32.WPARAM, lparam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (nCode < 0) {
        return win32.CallNextHookEx(hook_handle, nCode, wParam, lparam);
    }
    const kb: *const win32.KBDLLHOOKSSTRUCT = @ptrFromInt(@as(usize, @bitCast(lparam)));

    // Never re-process our own synthesized keystrokes, or we'd suppress
    // ourselves forever.
    if (kb.flags & win32.LLKHF_INJECTED != 0) {
        return win32.CallNextHookEx(hook_handle, nCode, wParam, lparam);
    }

    switch (wParam) {
        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => {
            switch (kb.vkCode) {
                win32.VK_LCONTROL, win32.VK_RCONTROL, win32.VK_CONTROL => {
                    ctrl_held = true;
                },
                win32.VK_LSHIFT, win32.VK_RSHIFT, win32.VK_SHIFT => {
                    shift_held = true;
                },
                win32.VK_LMENU, win32.VK_RMENU, win32.VK_MENU => {
                    alt_held = true;
                },
                win32.VK_END => {
                    if (ctrl_held and alt_held) {
                        std.debug.print("Quit hotkey pressed (Ctrl+Alt+End) — shutting down\n", .{});
                        win32.PostQuitMessage(0);
                        return 1; // swallow so it doesn't leak to the focused app
                    }
                },
                win32.VK_C => {
                    if (ctrl_held) {
                        awaiting_digit = true;
                        c_pressed_at = kb.time;
                    }
                },
                win32.VK_V => {
                    if (ctrl_held) {
                        v_suppressed = true;
                        if (shift_held) {
                            std.debug.print("Batch paste chord detected (Ctrl+Shift+V)\n", .{});
                            paste.pasteBatchAll(allocator);
                            awaiting_digit_paste = false;
                        } else {
                            awaiting_digit_paste = true;
                            v_pressed_at = kb.time;
                            if (hidden_hwnd) |hwnd| {
                                _ = win32.SetTimer(hwnd, PASTE_TIMER_ID, CHORD_TIMEOUT_MS + 50, null);
                            }
                        }
                        return 1; // suppress the real V
                    }
                },
                win32.VK_0...win32.VK_9, win32.VK_NUMPAD0...win32.VK_NUMPAD9 => {
                    const slot_num = if (kb.vkCode >= win32.VK_NUMPAD0)
                        kb.vkCode - win32.VK_NUMPAD0
                    else
                        kb.vkCode - win32.VK_0;

                    if (ctrl_held and awaiting_digit) {
                        const elapsed = kb.time -% c_pressed_at;
                        if (elapsed <= CHORD_TIMEOUT_MS) {
                            const slot: u4 = @intCast(slot_num);
                            if (!capture.tryStore(allocator, slot)) {
                                // Clipboard not ready yet (rare) — fall back to catching
                                // the async notification when it eventually arrives.
                                pending_slot = slot;
                                std.debug.print("Armed copy for slot {d} (waiting for clipboard)\n", .{slot});
                            }
                        }
                    }

                    var handled_paste = false;
                    if (ctrl_held and awaiting_digit_paste) {
                        const elapsed = kb.time -% v_pressed_at;
                        if (elapsed <= CHORD_TIMEOUT_MS) {
                            if (hidden_hwnd) |hwnd| _ = win32.KillTimer(hwnd, PASTE_TIMER_ID);
                            std.debug.print("Paste chord confirmed -> slot {d}\n", .{slot_num});
                            paste.pasteSlot(allocator, @intCast(slot_num));
                            digit_suppressed = true;
                            handled_paste = true;
                        }
                    }
                    awaiting_digit = false;
                    awaiting_digit_paste = false;
                    if (handled_paste) return 1; // suppress the digit itself
                },
                else => {},
            }
        },
        win32.WM_KEYUP, win32.WM_SYSKEYUP => {
            switch (kb.vkCode) {
                win32.VK_LCONTROL, win32.VK_RCONTROL, win32.VK_CONTROL => {
                    if (awaiting_digit_paste) {
                        // Ctrl released before a digit arrived: no chord,
                        // just replay the normal paste immediately instead
                        // of waiting out the full timeout.
                        if (hidden_hwnd) |hwnd| _ = win32.KillTimer(hwnd, PASTE_TIMER_ID);
                        awaiting_digit_paste = false;
                        paste.replayNormalPaste();
                    }
                    ctrl_held = false;
                    awaiting_digit = false;
                },
                win32.VK_LSHIFT, win32.VK_RSHIFT, win32.VK_SHIFT => {
                    shift_held = false;
                },
                win32.VK_LMENU, win32.VK_RMENU, win32.VK_MENU => {
                    alt_held = false;
                },
                win32.VK_V => {
                    if (v_suppressed) {
                        v_suppressed = false;
                        return 1;
                    }
                },
                win32.VK_0...win32.VK_9, win32.VK_NUMPAD0...win32.VK_NUMPAD9 => {
                    if (digit_suppressed) {
                        digit_suppressed = false;
                        return 1;
                    }
                },
                else => {},
            }
        },
        else => {},
    }

    return win32.CallNextHookEx(hook_handle, nCode, wParam, lparam);
}
