# ClipIX

A Windows-native, multi-slot clipboard manager written in Zig, with a
companion status GUI written in Go + Fyne.

ClipIX extends the normal Windows `Ctrl+C` / `Ctrl+V` workflow with **9
independent clipboard slots**, without ever getting in the way of the
clipboard's normal behavior.

```
Ctrl+C            -> normal copy (unchanged)
Ctrl+V            -> normal paste (unchanged)

Ctrl+C, then 1-9   -> copy into slot N
Ctrl+V, then 1-9   -> paste from slot N
Ctrl+Shift+V       -> paste every populated slot, in order

Ctrl+Alt+End       -> quit ClipIX cleanly
```

## Demo


  TODO: add the Loom/YouTube link here once recorded, e.g.:
  [![ClipIX demo](https://youtu.be/YqHpJgyg0So)]
  or simply:
  🎥 [Watch the demo](https://www.veed.io/view/d2090071-19e6-4830-8baa-5eb6b7e32bb4?source=editor&panel=share)

*A short walkthrough video is coming soon — it will cover installing a slot
via `Ctrl+C+N`, pasting it back with `Ctrl+V+N`, batch-pasting with
`Ctrl+Shift+V`, and the live status GUI.*

---

## How it works

ClipIX runs as a background process with no window of its own. It installs a
low-level global keyboard hook (`WH_KEYBOARD_LL`) to watch for its chorded
shortcuts, and a hidden message-only window to listen for clipboard change
notifications (`WM_CLIPBOARDUPDATE`).

**Copy** (`Ctrl+C` → digit): the real `Ctrl+C` is never touched — it fires
and updates the Windows clipboard exactly as it always has. ClipIX watches
for a digit key arriving within ~600ms afterward, and when one does, reads
whatever is currently on the clipboard and stores it in that slot.

**Paste** (`Ctrl+V` → digit): here the real `V` keypress *is* intercepted and
suppressed the instant `Ctrl+V` is pressed, before it reaches the OS. ClipIX
then waits briefly for a digit:
- If a digit arrives in time, the target slot's contents are written to the
  real clipboard and a synthetic `Ctrl+V` is injected via `SendInput`, so the
  focused application pastes the slot's content.
- If no digit arrives (or `Ctrl` is released early), ClipIX replays the
  original, unmodified `Ctrl+V` — indistinguishable from a normal paste from
  the user's perspective.

**Batch paste** (`Ctrl+Shift+V`): pastes every non-empty slot in order, with
a short delay between each so the target application has time to process
them.

Supported clipboard content types, per slot:
- Plain text (`CF_UNICODETEXT`)
- Files and directories (`CF_HDROP`) — multiple items per copy are preserved
  in their original Explorer selection order

## Persistence

Slot contents live in memory for the lifetime of the process, mirrored into a
local SQLite database (`C:\Windows\Temp\clipix.db`) purely so the companion
GUI can read live state without any inter-process communication of its own.

**Nothing is meant to survive a restart.**
- On launch, any leftover database file from a previous run is deleted
  before a fresh one is created.
- On clean shutdown (`Ctrl+Alt+End`), the database is closed and deleted.
- If ClipIX is killed abruptly (crash, Task Manager, `taskkill /F`), cleanup
  on shutdown is skipped, but the startup-time wipe still guarantees no state
  leaks into the next session.

## The GUI

A small Go + Fyne application shows the current contents of all 9 slots, one
line each, e.g.:

```
Slot 1: Revenue Data and Building a D...(9 item(s))
Slot 2: Get-Item C:\Windows\Temp\clip...(text)
Slot 3: (empty)
```

It polls `clipix.db` (read-only) every 500ms and updates automatically. It's
launched automatically by ClipIX on startup, and exits on its own once it
detects `clipix.db` is gone — i.e. once ClipIX itself has shut down.

---

## Project layout

```
clipIX/
├── src/
│   ├── main.zig       -- entry point: installs hook, creates window, runs message loop
│   ├── win32.zig        -- hand-declared Win32 API bindings (types, externs, constants)
│   ├── keyboard.zig      -- low-level keyboard hook + chord detection state machine
│   ├── clipboard.zig     -- reading the real Windows clipboard (text / CF_HDROP)
│   ├── capture.zig       -- shared "read clipboard -> store in slot" logic
│   ├── slots.zig         -- in-memory 9-slot storage
│   ├── paste.zig         -- writing to the clipboard + synthetic Ctrl+V injection
│   ├── database.zig      -- SQLite mirror of slot contents
│   └── root.zig
├── gui/
│   ├── main.go            -- the status GUI (source only — gui.exe is built, not committed)
│   ├── go.mod
│   └── go.sum
├── build.zig
├── build.zig.zon
├── Taskfile.yml          -- task run / task kill / task restart
└── zig-pkg/               -- vendored SQLite dependency source
```

---

## Requirements

- Windows 10/11 (ClipIX is Windows-only by design — no cross-platform support
  is planned)
- [Zig](https://ziglang.org/) 0.16.x
- [Go](https://go.dev/) 1.25+ (for the GUI)
- A C compiler on the Windows side for building the GUI (Fyne uses cgo /
  OpenGL). Any of MSYS2's `gcc`, MinGW, or
  [w64devkit](https://github.com/skeeto/w64devkit) will work — check with
  `gcc --version` first, you may already have one.
- [Task](https://taskfile.dev/) (optional, for the `Taskfile.yml` shortcuts)

This project is developed from WSL2 (Ubuntu), with Zig cross-compiling to
Windows directly, and the Go GUI built separately on native Windows. See the
important note below on **why** the GUI can't be built from WSL.

---

## Building and running — step by step

### 1. Get the code

If you're working from WSL (recommended for the Zig side):

```sh
git clone <this-repo-url> ~/projects/clipIX
cd ~/projects/clipIX
```

### 2. Build and run the Zig process

From the WSL project directory:

```sh
zig build run
```

or, with [Task](https://taskfile.dev/) installed:

```sh
task run       # build + run
task kill       # or: task end — force-stop ClipIX and clean up clipix.db
task restart
```

Zig cross-compiles cleanly to `x86_64-windows` from WSL with no extra setup —
the target is pinned in `build.zig`.

At this point ClipIX will start, but it will print
`Failed to launch GUI: error.FileNotFound` and continue running without the
GUI, since `gui/gui.exe` doesn't exist yet. That's expected — build the GUI
next.

### 3. Build the GUI — **from native Windows, on a real NTFS path**

This is the one genuinely fiddly part. **Go's and SQLite's file-locking
don't work correctly over WSL's `\\wsl.localhost\...` filesystem** (you'll
see errors like `Lock go.mod: Incorrect function` or `SQLiteBusy` if you try)
— neither a mapped drive letter (`net use`) nor `subst` fixes this, since the
limitation is in the underlying WSL 9P filesystem provider itself, not in how
the path is addressed.

The reliable path: **clone the repo a second time directly onto the Windows
filesystem**, and build the GUI there.

Open **PowerShell** (not WSL):

```powershell
git clone <this-repo-url> C:\Users\<you>\clipix
cd C:\Users\<you>\clipix\gui
```

Set up cgo (Fyne needs a real C compiler):

```powershell
$env:CGO_ENABLED = "1"
go build -o gui.exe
```

If `go build`/`go get` fail with `dial tcp: lookup proxy.golang.org: no such
host` or similar — a DNS-resolver quirk seen on some networks — force Go to
use the OS resolver instead of its built-in one:

```powershell
$env:GODEBUG = "netdns=cgo"
go build -o gui.exe
```

If dependencies are missing or `go.sum` entries are incomplete, run:

```powershell
go mod tidy
go build -o gui.exe
```

### 4. Put `gui.exe` where the Zig process expects it

ClipIX launches the GUI via a relative path, `gui/gui.exe`, resolved from
wherever the ClipIX process runs — i.e. your **WSL-hosted** project
directory. Copy the executable you just built on the Windows-native clone
into the WSL project's `gui/` folder:

```powershell
copy gui.exe \\wsl.localhost\Ubuntu\home\<you>\projects\clipIX\gui\gui.exe
```

(Copying a single built `.exe` over this filesystem boundary is fine — it's
only the *build tooling* with its lock files that has trouble, not a plain
file copy.)

### 5. Run it all together

Back in WSL:

```sh
zig build run
```

ClipIX should start, and the GUI window should appear alongside it a moment
later, showing all 9 slots as empty. Try `Ctrl+C`, then `1`, on some text or
files, and watch the corresponding slot update.

---

## Known limitations / not yet implemented

- Only text and file/directory clipboard formats are supported (no images,
  rich text, or URLs — explicitly out of scope for v1, per the original
  design goals).
- Smart-paste destination handling (files pasting as real files in Explorer
  vs. as text paths elsewhere) mirrors the clipboard formats written, but has
  not been exhaustively tested against every application.
- The GUI is read-only and purely informational — there's no way to trigger a
  paste or clear a slot from it (yet).
- No installer / no run-at-startup registration — ClipIX is a developer tool
  for now, run manually per session.

## Development notes

This project was built incrementally as a systems-programming and Zig
learning exercise as much as a practical tool, staged roughly as: Win32
basics → keyboard chord detection → clipboard object model → slot manager →
SQLite mirror → paste engine (keystroke suppression + injection) → GUI.

## License

I do not know. Do whatever you want. It is yours, if you have gone through all the hustle above!
