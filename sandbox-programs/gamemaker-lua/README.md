# gamemaker-lua

Godot Sandbox program embedding LuaJIT. This is the one-time C++ compile
target for Phase 3c's scripting layer — everything downstream of this (Game
Maker's Code Editor, in-game hot-reload) only ever edits/deploys plain Lua
text, never touches this C++ or the RISC-V toolchain.

## Building

Requires `cmake`, `ninja`, and `zig` on PATH. From this directory:

```sh
./build.sh
```

This configures via `cmake/zig-toolchain.cmake` (sets `CMAKE_SYSTEM_NAME
Linux` + `CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY` so CMake's compiler
check doesn't try to link a native Windows test binary against a RISC-V
cross-compiler) and builds with Ninja.

Output: `.build/gamemaker_lua.elf`. Copy it to
`UCFGS/Addons/godot-sandbox-scripts/gamemaker_lua.elf` (create that folder
if it doesn't exist) so `ScriptingManager.cs` can load it.

## API exposed to the host (Godot/C#)

- `run(String code) -> Variant` — evaluates a string of Lua code once (used
  to load a script's top-level body, which defines hook functions as
  globals).
- `call_hook(String name, Array args) -> Variant` — calls a previously
  Lua-defined global function by name, if it exists. No-op (returns Nil) if
  the current script never defined that hook.
- `add_function(String name, Callable fn)` — exposes a Godot `Callable` as a
  Lua-callable global function inside the sandbox.
- `reset_globals()` — clears all Lua globals, for a clean slate before
  reloading a script.

## Security model

The Lua VM inside this sandbox program can only reach what this C++ file
explicitly exposes. Don't add `add_function` registrations (or Lua library
loads beyond `luaL_openlibs`'s standard set) that grant more capability than
intended — that's the actual boundary that makes this safer than loading
scripts via vanilla GDScript, which has unrestricted engine access.
