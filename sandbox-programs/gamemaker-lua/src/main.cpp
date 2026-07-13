// gamemaker_lua.elf — a Godot Sandbox (libriscv) program that embeds LuaJIT.
//
// This is the ONLY thing that ever gets compiled for Phase 3c. Game Maker
// (the Electron app) and in-game admins only ever edit/deploy plain Lua text
// files after this — nothing else needs the RISC-V toolchain.
//
// The Lua VM's access to the Godot engine is exactly and only what's exposed
// below (add_function registrations from the host side, plus whatever the
// host explicitly calls into Lua via call_hook). That's the actual sandboxing
// property this whole design exists for — unlike vanilla GDScript, a loaded
// Lua script cannot reach anything not deliberately wired up here.
//
// Based on the official godot-sandbox-programs LuaJIT example
// (https://github.com/libriscv/godot-sandbox-programs/tree/main/programs/luajit),
// extended with call_hook() for clean event dispatch from ScriptingManager.cs.

#include <api.hpp>
#include <algorithm>
#include <array>
#include <cstring>
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

static lua_State *L;
static constexpr bool VERBOSE = false;
static constexpr size_t MAX_ARGS = 8;

static int api_print(lua_State *l) {
	const char *text = luaL_checkstring(l, 1);
	printf("%s", text);
	fflush(stdout);
	return 0;
}

// Pushes a single Variant onto the Lua stack as the closest matching Lua type.
static void push_variant(lua_State *l, const Variant &v) {
	switch (v.get_type()) {
		case Variant::Type::NIL:
			lua_pushnil(l);
			break;
		case Variant::Type::BOOL:
			lua_pushboolean(l, (bool)v);
			break;
		case Variant::Type::INT:
		case Variant::Type::FLOAT:
			lua_pushnumber(l, (double)v);
			break;
		case Variant::Type::STRING:
			lua_pushstring(l, v.as_std_string().c_str());
			break;
		default:
			lua_pushnil(l);
			break;
	}
}

// Converts the Lua value at stack index -1 into a Variant.
static Variant top_to_variant(lua_State *l) {
	switch (lua_type(l, -1)) {
		case LUA_TNIL:
			return Nil;
		case LUA_TBOOLEAN:
			return (bool)lua_toboolean(l, -1);
		case LUA_TNUMBER:
			return lua_tonumber(l, -1);
		case LUA_TSTRING:
			return lua_tostring(l, -1);
		default:
			return Nil;
	}
}

// Evaluates a string of Lua code (e.g. the deployed script's top-level body,
// which defines hook functions like on_damage_taken as globals) and returns
// its single result, if any.
static Variant run(String code) {
	const std::string utf = code.utf8();
	if (luaL_loadbuffer(L, utf.c_str(), utf.size(), "@gamemaker_script") != 0) {
		print("Lua load error: ", lua_tostring(L, -1));
		lua_pop(L, 1);
		return Nil;
	}
	if (lua_pcall(L, 0, 1, 0) != 0) {
		print("Lua runtime error: ", lua_tostring(L, -1));
		lua_pop(L, 1);
		return Nil;
	}
	Variant result = top_to_variant(L);
	lua_pop(L, 1);
	return result;
}

// Calls a previously-defined global Lua function by name with the given
// arguments, if it exists. Silently returns Nil (does nothing) if the
// current script never defined that hook - scripts only need to define the
// hooks they actually care about.
static Variant call_hook(String name, Array args) {
	const std::string fname = name.utf8();
	lua_getglobal(L, fname.c_str());
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1);
		return Nil;
	}

	const int64_t argc = args.size();
	for (int64_t i = 0; i < argc && i < (int64_t)MAX_ARGS; i++) {
		push_variant(L, args[i]);
	}

	if (lua_pcall(L, (int)std::min<int64_t>(argc, MAX_ARGS), 1, 0) != 0) {
		print("Lua hook '", name, "' error: ", lua_tostring(L, -1));
		lua_pop(L, 1);
		return Nil;
	}
	Variant result = top_to_variant(L);
	lua_pop(L, 1);
	return result;
}

// Registers a Godot-side Callable as a callable global function inside the
// Lua VM (e.g. so scripts can call host-provided utility functions). Mirrors
// the official LuaJIT example's argument-marshalling exactly.
static Variant add_function(String function_name, Callable function) {
	struct UserData {
		Variant function;
	};
	UserData *data = new UserData;
	data->function = function;
	data->function.make_permanent();

	lua_pushlightuserdata(L, (void *)data);
	lua_pushcclosure(L, [](lua_State *l) -> int {
		UserData *ud = (UserData *)lua_touserdata(l, lua_upvalueindex(1));
		Variant &function = ud->function;

		std::array<Variant, MAX_ARGS> args;
		size_t arg_count = 0;
		const int nargs = lua_gettop(l);
		for (int i = 1; i <= nargs && arg_count < MAX_ARGS; i++) {
			switch (lua_type(l, i)) {
				case LUA_TNIL:
					break;
				case LUA_TBOOLEAN:
					args.at(arg_count++) = bool(lua_toboolean(l, i));
					break;
				case LUA_TNUMBER:
					args.at(arg_count++) = double(lua_tonumber(l, i));
					break;
				case LUA_TSTRING:
					args.at(arg_count++) = lua_tostring(l, i);
					break;
				default:
					break;
			}
		}

		Variant result;
		function.callp("call", args.data(), arg_count, result);
		switch (result.get_type()) {
			case Variant::Type::NIL:
				return 0;
			case Variant::Type::BOOL:
				lua_pushboolean(l, result);
				return 1;
			case Variant::Type::INT:
			case Variant::Type::FLOAT:
				lua_pushnumber(l, result);
				return 1;
			case Variant::Type::STRING:
				lua_pushstring(l, result.as_std_string().c_str());
				return 1;
			default:
				return 0;
		}
	},
			1);
	lua_setglobal(L, function_name.utf8().c_str());
	return Nil;
}

// Clears all global functions/variables a previous run() defined, so a
// reloaded script starts from a clean slate rather than accumulating stale
// globals across hot-reloads.
static Variant reset_globals() {
	lua_close(L);
	L = luaL_newstate();
	luaL_openlibs(L);
	lua_register(L, "print", api_print);
	return Nil;
}

int main() {
	L = luaL_newstate();
	luaL_openlibs(L);
	lua_register(L, "print", api_print);

	ADD_API_FUNCTION(run, "Variant", "String code", "Evaluates a string of Lua code and returns its result");
	ADD_API_FUNCTION(call_hook, "Variant", "String name, Array args", "Calls a global Lua function by name if it exists; no-op otherwise");
	ADD_API_FUNCTION(add_function, "void", "String function_name, Callable function", "Exposes a Godot Callable as a Lua-callable global function");
	ADD_API_FUNCTION(reset_globals, "void", "", "Clears the Lua VM's global state before a fresh script load");

	halt();
}
