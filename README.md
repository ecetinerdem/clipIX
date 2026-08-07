# ClipIX

> Extend Windows' clipboard without replacing it.

ClipIX is a Windows clipboard manager written in Zig using only the Win32 API.

The project aims to explore low-level Windows programming while extending the traditional Ctrl+C / Ctrl+V workflow with nine independent clipboard slots.

## Goals

- Learn Zig
- Learn Win32 API
- Learn Windows internals
- Build a systems programming portfolio project

## Version 1

- 9 clipboard slots
- Global keyboard hooks
- Text, files and directories
- Batch paste
- Runtime SQLite storage
- No third-party libraries