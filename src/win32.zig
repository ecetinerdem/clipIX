const std = @import("std");
pub const windows = std.os.windows;

pub const HWND = windows.HWND;
pub const UINT = windows.UINT;
pub const WPARAM = windows.ULONG_PTR;
pub const LPARAM = windows.LPARAM;
pub const LRESULT = windows.ULONG_PTR;
pub const HINSTANCE = windows.HINSTANCE;
pub const ATOM = windows.WORD;
pub const HHOOK = *opaque {};
pub const BOOL = windows.BOOL;
pub const HDROP = *opaque {};

pub const WH_KEYBOARD_LL: c_int = 13;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_CLIPBOARDUPDATE = 0x031D;
pub const HWND_MESSAGE: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -3))));

pub const VK_LCONTROL: windows.DWORD = 0xA2;
pub const VK_RCONTROL: windows.DWORD = 0xA3;
pub const VK_CONTROL: windows.DWORD = 0x11;
pub const VK_C: windows.DWORD = 0x43;
pub const VK_V: windows.DWORD = 0x56;
pub const VK_0: windows.DWORD = 0x30;
pub const VK_9: windows.DWORD = 0x39;
pub const VK_NUMPAD0: windows.DWORD = 0x60;
pub const VK_NUMPAD9: windows.DWORD = 0x69;
pub const VK_LSHIFT: windows.DWORD = 0xA0;
pub const VK_RSHIFT: windows.DWORD = 0xA1;
pub const VK_SHIFT: windows.DWORD = 0x10;
pub const LLKHF_INJECTED: windows.DWORD = 0x00000010;
pub const WM_TIMER = 0x0113;
pub const INPUT_KEYBOARD: windows.DWORD = 1;
pub const KEYEVENTF_KEYUP: windows.DWORD = 0x0002;

pub const VK_MENU: windows.DWORD = 0x12; // generic Alt
pub const VK_LMENU: windows.DWORD = 0xA4;
pub const VK_RMENU: windows.DWORD = 0xA5;
pub const VK_END: windows.DWORD = 0x23;

pub const CF_UNICODETEXT: windows.UINT = 13;
pub const CF_HDROP: windows.UINT = 15;
pub const GMEM_MOVEABLE: windows.UINT = 0x0002;

pub const POINT = extern struct {
    x: windows.LONG,
    y: windows.LONG,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lparam: LPARAM,
    time: windows.DWORD,
    pt: POINT,
};

pub const KBDLLHOOKSSTRUCT = extern struct {
    vkCode: windows.DWORD,
    scanCode: windows.DWORD,
    flags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE,
    hIcon: ?windows.HICON = null,
    hCursor: ?windows.HCURSOR = null,
    hbrBackground: ?windows.HBRUSH = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: ?windows.HICON = null,
};

pub const DROPFILES = extern struct {
    pFiles: windows.DWORD,
    pt: POINT,
    fNC: BOOL,
    fWide: BOOL,
};

pub const MOUSEINPUT = extern struct {
    dx: windows.LONG,
    dy: windows.LONG,
    mouseData: windows.DWORD,
    dwFlags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const HARDWAREINPUT = extern struct {
    uMsg: windows.DWORD,
    wParamL: windows.WORD,
    wParamH: windows.WORD,
};

pub const KEYBDINPUT = extern struct {
    wVk: windows.WORD,
    wScan: windows.WORD,
    dwFlags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const INPUT = extern struct {
    type: windows.DWORD,
    u: extern union {
        mi: MOUSEINPUT,
        ki: KEYBDINPUT,
        hi: HARDWAREINPUT,
    },
};

pub extern "user32" fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: windows.DWORD,
    lpClassName: [*:0]const u16,
    lpWindowName: ?[*:0]const u16,
    dwStyle: windows.DWORD,
    X: c_int,
    Y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?windows.HMENU,
    hInstance: HINSTANCE,
    lpParam: ?windows.LPVOID,
) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn AddClipboardFormatListener(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn RemoveClipboardFormatListener(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn SetWindowsHookExW(idHook: c_int, lpfn: *const fn (c_int, WPARAM, LPARAM) callconv(.winapi) LRESULT, hmod: ?HINSTANCE, dwThreadId: windows.DWORD) callconv(.winapi) ?HHOOK;
pub extern "user32" fn UnhookWindowsHookEx(hhk: HHOOK) callconv(.winapi) BOOL;
pub extern "user32" fn CallNextHookEx(hhk: ?HHOOK, nCode: c_int, wParam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.winapi) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn GetClipboardData(uFormat: windows.UINT) callconv(.winapi) ?windows.HANDLE;
pub extern "user32" fn IsClipboardFormatAvailable(format: windows.UINT) callconv(.winapi) BOOL;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?windows.HMODULE;
pub extern "kernel32" fn GlobalLock(hMem: windows.HANDLE) callconv(.winapi) ?windows.LPVOID;
pub extern "kernel32" fn GlobalUnlock(hMem: windows.HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileAttributesW(lpFileName: [*:0]const u16) callconv(.winapi) windows.DWORD;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;

pub extern "shell32" fn DragQueryFileW(
    hDrop: HDROP,
    iFile: windows.UINT,
    lpszFile: ?[*]u16,
    cch: windows.UINT,
) callconv(.winapi) windows.UINT;

pub extern "user32" fn SetTimer(hWnd: ?HWND, nIDEvent: usize, uElapse: windows.UINT, lpTimerFunc: ?*anyopaque) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.winapi) BOOL;

pub extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn SetClipboardData(uFormat: windows.UINT, hMem: windows.HANDLE) callconv(.winapi) ?windows.HANDLE;

pub extern "kernel32" fn GlobalAlloc(uFlags: windows.UINT, dwBytes: usize) callconv(.winapi) ?windows.HANDLE;
pub extern "kernel32" fn GlobalFree(hMem: windows.HANDLE) callconv(.winapi) ?windows.HANDLE;
pub extern "kernel32" fn Sleep(dwMilliseconds: windows.DWORD) callconv(.winapi) void;

pub extern "user32" fn SendInput(cInputs: windows.UINT, pInputs: [*]INPUT, cbSize: c_int) callconv(.winapi) windows.UINT;
