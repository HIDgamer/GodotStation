#!/bin/bash
# Builds gamemaker_lua.elf using Zig as a RISC-V cross-compiler.
# Requires: cmake, ninja, zig (0.14.x+) all available on PATH.
set -e

TOOLCHAIN="$PWD/cmake/zig-toolchain.cmake"
ARGS="-DSTRIPPED=ON"
BTYPE="Release"

if ! command -v zig &> /dev/null; then
	echo "zig could not be found on PATH. Install Zig and try again."
	exit 1
fi
if ! command -v cmake &> /dev/null; then
	echo "cmake could not be found on PATH. Install CMake and try again."
	exit 1
fi

while [[ "$#" -gt 0 ]]; do
	case $1 in
		--debug) BTYPE="Debug" ;;
		--no-strip) ARGS="" ;;
		--verbose) ARGS="$ARGS -DCMAKE_VERBOSE_MAKEFILE=ON" ;;
		*) echo "Unknown parameter passed: $1"; exit 1 ;;
	esac
	shift
done

mkdir -p .build
pushd .build
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=$BTYPE $ARGS -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
cmake --build . -j8
popd

echo
echo "Built: .build/gamemaker_lua.elf"
