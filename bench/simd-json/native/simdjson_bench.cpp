#include "simdjson_bench.h"

#include <climits>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <string_view>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}
#include <simdjson.h>

#if defined(_WIN32)
#define NUPP_SIMDJSON_EXPORT __declspec(dllexport)
#else
#define NUPP_SIMDJSON_EXPORT __attribute__((visibility("default")))
#endif

struct nupp_simdjson_parser {
    simdjson::dom::parser dom;
    simdjson::ondemand::parser ondemand;
    std::vector<char> padded;
    size_t length{0};
    uint64_t sink{0};
};

namespace {

constexpr const char *LAZY_METATABLE = "nupp.simdjson.lazy";

struct lazy_document {
    simdjson::dom::parser parser;
    simdjson::dom::element root;
};

struct lazy_node {
    std::shared_ptr<lazy_document> document;
    simdjson::dom::element value;
};

static int table_capacity(size_t size) noexcept {
    return size > static_cast<size_t>(INT_MAX)
        ? INT_MAX
        : static_cast<int>(size);
}

static bool push_element(
    lua_State *L,
    simdjson::dom::element value,
    int null_index,
    const char **failure
) {
    if (!lua_checkstack(L, 4)) {
        *failure = "Lua stack capacity exceeded";
        return false;
    }

    switch (value.type()) {
        case simdjson::dom::element_type::ARRAY: {
            simdjson::dom::array array;
            const auto error = value.get_array().get(array);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            lua_createtable(L, table_capacity(array.size()), 0);
            const int table_index = lua_gettop(L);
            int index = 1;
            for (const auto child : array) {
                if (!push_element(L, child, null_index, failure)) {
                    return false;
                }
                lua_rawseti(L, table_index, index++);
            }
            return true;
        }
        case simdjson::dom::element_type::OBJECT: {
            simdjson::dom::object object;
            const auto error = value.get_object().get(object);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            lua_createtable(L, 0, table_capacity(object.size()));
            const int table_index = lua_gettop(L);
            for (const auto field : object) {
                const std::string_view key = field.key;
                lua_pushlstring(L, key.data(), key.size());
                if (!push_element(L, field.value, null_index, failure)) {
                    return false;
                }
                lua_rawset(L, table_index);
            }
            return true;
        }
        case simdjson::dom::element_type::STRING: {
            std::string_view string;
            const auto error = value.get_string().get(string);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            lua_pushlstring(L, string.data(), string.size());
            return true;
        }
        case simdjson::dom::element_type::INT64:
        case simdjson::dom::element_type::UINT64:
        case simdjson::dom::element_type::DOUBLE: {
            double number = 0;
            const auto error = value.get_double().get(number);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            lua_pushnumber(L, number);
            return true;
        }
        case simdjson::dom::element_type::BIGINT: {
            std::string_view raw;
            const auto error = value.get_bigint().get(raw);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            const std::string terminated(raw);
            char *end = nullptr;
            const double number = std::strtod(terminated.c_str(), &end);
            if (end != terminated.c_str() + terminated.size()) {
                *failure = "could not convert a JSON integer to a Lua number";
                return false;
            }
            lua_pushnumber(L, number);
            return true;
        }
        case simdjson::dom::element_type::BOOL: {
            bool boolean = false;
            const auto error = value.get_bool().get(boolean);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            lua_pushboolean(L, boolean ? 1 : 0);
            return true;
        }
        case simdjson::dom::element_type::NULL_VALUE:
            if (null_index == 0) {
                lua_pushnil(L);
            } else {
                lua_pushvalue(L, null_index);
            }
            return true;
    }

    *failure = "unknown simdjson element type";
    return false;
}

static const char *element_type_name(simdjson::dom::element_type type) noexcept {
    switch (type) {
        case simdjson::dom::element_type::ARRAY: return "array";
        case simdjson::dom::element_type::OBJECT: return "object";
        case simdjson::dom::element_type::STRING: return "string";
        case simdjson::dom::element_type::INT64:
        case simdjson::dom::element_type::UINT64:
        case simdjson::dom::element_type::DOUBLE:
        case simdjson::dom::element_type::BIGINT: return "number";
        case simdjson::dom::element_type::BOOL: return "boolean";
        case simdjson::dom::element_type::NULL_VALUE: return "null";
    }
    return "unknown";
}

static lazy_node *checked_lazy(lua_State *L, int index) {
    return static_cast<lazy_node *>(luaL_checkudata(L, index, LAZY_METATABLE));
}

static void push_lazy_node(
    lua_State *L,
    const std::shared_ptr<lazy_document> &document,
    simdjson::dom::element value,
    int parent_index
) {
    void *storage = lua_newuserdata(L, sizeof(lazy_node));
    new (storage) lazy_node{document, value};
    luaL_getmetatable(L, LAZY_METATABLE);
    lua_setmetatable(L, -2);
    if (parent_index != 0) {
        lua_getfenv(L, parent_index);
        lua_setfenv(L, -2);
    }
}

static bool push_lazy_value(
    lua_State *L,
    lazy_node *parent,
    simdjson::dom::element value,
    const char **failure
) {
    const auto type = value.type();
    if (type == simdjson::dom::element_type::ARRAY || type == simdjson::dom::element_type::OBJECT) {
        push_lazy_node(L, parent->document, value, 1);
        return true;
    }
    lua_getfenv(L, 1);
    lua_getfield(L, -1, "null");
    lua_remove(L, -2);
    const int null_index = lua_gettop(L);
    if (!push_element(L, value, null_index, failure)) {
        return false;
    }
    lua_remove(L, null_index);
    return true;
}

static int lua_decode(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    const int null_index = lua_gettop(L) >= 2 ? 2 : 0;
    const int base = lua_gettop(L);
    const char *failure = nullptr;

    try {
        static thread_local simdjson::dom::parser parser;
        simdjson::dom::element document;
        const auto error = parser.parse(source, length, true).get(document);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            push_element(L, document, null_index, &failure);
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }

    if (failure != nullptr) {
        lua_settop(L, base);
        return luaL_error(L, "simdjson Lua DOM: %s", failure);
    }

    return 1;
}

static int lua_lazy(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    const int base = lua_gettop(L);
    const char *failure = nullptr;

    try {
        auto document = std::make_shared<lazy_document>();
        const auto error = document->parser.parse(source, length, true).get(document->root);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            push_lazy_node(L, document, document->root, 0);
            lua_createtable(L, 0, 1);
            if (base >= 2) {
                lua_pushvalue(L, 2);
            } else {
                lua_pushnil(L);
            }
            lua_setfield(L, -2, "null");
            lua_setfenv(L, -2);
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }

    if (failure != nullptr) {
        lua_settop(L, base);
        return luaL_error(L, "simdjson lazy DOM: %s", failure);
    }

    return 1;
}

static int lua_lazy_gc(lua_State *L) {
    checked_lazy(L, 1)->~lazy_node();
    return 0;
}

static int lua_lazy_index(lua_State *L) {
    lazy_node *node = checked_lazy(L, 1);
    simdjson::dom::element child;
    bool found = false;

    if (node->value.type() == simdjson::dom::element_type::ARRAY && lua_type(L, 2) == LUA_TNUMBER) {
        const lua_Number requested = lua_tonumber(L, 2);
        const lua_Integer index = lua_tointeger(L, 2);
        if (requested >= 1 && requested == static_cast<lua_Number>(index)) {
            simdjson::dom::array array;
            if (!node->value.get_array().get(array)) {
                found = !array.at(static_cast<size_t>(index - 1)).get(child);
            }
        }
    } else if (node->value.type() == simdjson::dom::element_type::OBJECT && lua_type(L, 2) == LUA_TSTRING) {
        size_t length = 0;
        const char *key = lua_tolstring(L, 2, &length);
        const std::string_view wanted(key, length);
        simdjson::dom::object object;
        if (!node->value.get_object().get(object)) {
            for (const auto field : object) {
                if (field.key == wanted) {
                    child = field.value;
                    found = true;
                }
            }
        }
    }

    if (!found) {
        lua_pushnil(L);
        return 1;
    }

    const char *failure = nullptr;
    try {
        push_lazy_value(L, node, child, &failure);
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) {
        lua_settop(L, 2);
        return luaL_error(L, "simdjson lazy DOM: %s", failure);
    }
    return 1;
}

static int lua_lazy_length(lua_State *L) {
    lazy_node *node = checked_lazy(L, 1);
    size_t size = 0;
    if (node->value.type() == simdjson::dom::element_type::ARRAY) {
        simdjson::dom::array array;
        if (!node->value.get_array().get(array)) {
            size = array.size();
        }
    } else if (node->value.type() == simdjson::dom::element_type::OBJECT) {
        simdjson::dom::object object;
        if (!node->value.get_object().get(object)) {
            size = object.size();
        }
    }
    lua_pushnumber(L, static_cast<lua_Number>(size));
    return 1;
}

static int lua_lazy_newindex(lua_State *L) {
    return luaL_error(L, "simdjson lazy DOM values are read-only");
}

static int lua_lazy_materialize(lua_State *L) {
    lazy_node *node = checked_lazy(L, 1);
    lua_getfenv(L, 1);
    lua_getfield(L, -1, "null");
    lua_remove(L, -2);
    const int null_index = lua_gettop(L);
    const char *failure = nullptr;
    try {
        push_element(L, node->value, null_index, &failure);
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) {
        lua_settop(L, 1);
        return luaL_error(L, "simdjson lazy DOM: %s", failure);
    }
    lua_remove(L, null_index);
    return 1;
}

static int lua_lazy_type(lua_State *L) {
    const char *name = element_type_name(checked_lazy(L, 1)->value.type());
    lua_pushstring(L, name);
    return 1;
}

static void set_function(lua_State *L, const char *name, lua_CFunction function) {
    lua_pushcfunction(L, function);
    lua_setfield(L, -2, name);
}

} // namespace

extern "C" nupp_simdjson_parser *nupp_simdjson_new(void) {
    return new (std::nothrow) nupp_simdjson_parser();
}

extern "C" void nupp_simdjson_free(nupp_simdjson_parser *parser) {
    delete parser;
}

extern "C" int nupp_simdjson_prepare(
    nupp_simdjson_parser *parser,
    const char *source,
    size_t length
) {
    if (parser == nullptr || source == nullptr) {
        return -1;
    }
    if (length > SIZE_MAX - simdjson::SIMDJSON_PADDING) {
        return -1;
    }
    try {
        parser->padded.resize(length + simdjson::SIMDJSON_PADDING);
    } catch (const std::bad_alloc &) {
        return -1;
    }
    std::memcpy(parser->padded.data(), source, length);
    std::memset(
        parser->padded.data() + length,
        0,
        simdjson::SIMDJSON_PADDING
    );
    parser->length = length;
    return 0;
}

extern "C" int nupp_simdjson_stage1(nupp_simdjson_parser *parser) {
    if (parser == nullptr) {
        return -1;
    }
    simdjson::ondemand::document document;
    const auto error = parser->ondemand.iterate(
        parser->padded.data(),
        parser->length,
        parser->padded.size()
    ).get(document);
    if (error) {
        return static_cast<int>(error);
    }
    parser->sink += 1;
    return 0;
}

extern "C" int nupp_simdjson_dom(nupp_simdjson_parser *parser) {
    if (parser == nullptr) {
        return -1;
    }
    simdjson::dom::element document;
    const auto error = parser->dom.parse(
        parser->padded.data(),
        parser->length,
        false
    ).get(document);
    if (error) {
        return static_cast<int>(error);
    }
    parser->sink += static_cast<uint64_t>(document.type()) + 1;
    return 0;
}

extern "C" const char *nupp_simdjson_error(int code) {
    if (code == -1) {
        return "bridge allocation or argument failure";
    }
    return simdjson::error_message(static_cast<simdjson::error_code>(code));
}

extern "C" const char *nupp_simdjson_version(void) {
    return SIMDJSON_VERSION;
}

extern "C" const char *nupp_simdjson_implementation(void) {
    static std::string implementation;
    implementation = simdjson::get_active_implementation()->name();
    return implementation.c_str();
}

extern "C" NUPP_SIMDJSON_EXPORT int luaopen_simdjson_bench_native(lua_State *L) {
    luaL_newmetatable(L, LAZY_METATABLE);
    set_function(L, "__gc", lua_lazy_gc);
    set_function(L, "__index", lua_lazy_index);
    set_function(L, "__len", lua_lazy_length);
    set_function(L, "__newindex", lua_lazy_newindex);
    lua_pushliteral(L, "simdjson lazy DOM");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);

    lua_createtable(L, 0, 4);
    set_function(L, "decode", lua_decode);
    set_function(L, "lazy", lua_lazy);
    set_function(L, "materialize", lua_lazy_materialize);
    set_function(L, "type", lua_lazy_type);
    return 1;
}
