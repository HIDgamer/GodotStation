cmake_minimum_required(VERSION 3.18)
project(gamemaker-lua)

# Fetch godot-sandbox for add_sandbox_program and other functions
include(FetchContent)
FetchContent_Declare(
	godot-sandbox
	GIT_REPOSITORY https://github.com/libriscv/godot-sandbox.git
	GIT_TAG        main
	SOURCE_SUBDIR  "program/cpp/cmake"
)
FetchContent_MakeAvailable(godot-sandbox)

# Build the godot-sandbox program `gamemaker_lua.elf`:
add_sandbox_program(gamemaker_lua.elf
	"src/main.cpp"
)

target_include_directories(gamemaker_lua.elf PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/vendor/LuaJIT/src
)

# build.sh always compiles via `zig cc`/`zig c++` (see build.sh) - use the
# LuaJIT static lib built with the same Zig toolchain to avoid ABI mismatches.
# If you switch to a native riscv64-linux-gnu-g++ toolchain instead, swap this
# for vendor/libluajit.a.
target_link_libraries(gamemaker_lua.elf PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/vendor/zig-libluajit.a)
