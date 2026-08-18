#include "simdjson_bench.h"

#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
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

constexpr const char *WRITER_METATABLE = "nupp.simdjson.writer";
constexpr const char *SENTINEL_METATABLE = "nupp.simdjson.sentinel";
static char EMPTY_ARRAY_KEY;
static char EMPTY_OBJECT_KEY;
static char ARRAY_SHAPE_KEY;

struct sentinel {
    const char *name;
};

enum class container_kind {
    array,
    object,
};

struct writer_frame {
    container_kind kind;
    bool first{true};
    bool needs_value{false};
};

struct lua_writer {
    simdjson::builder::string_builder builder;
    std::vector<writer_frame> frames;
    bool root_written{false};
    bool finished{false};
};

enum class emit_result {
    produced,
    dropped,
    failed,
};

enum class table_kind {
    array,
    object,
    invalid,
};

static int absolute_index(lua_State *L, int index) noexcept {
    if (index > 0 || index <= LUA_REGISTRYINDEX) {
        return index;
    }
    return lua_gettop(L) + index + 1;
}

static int table_capacity(size_t size) noexcept {
    return size > static_cast<size_t>(INT_MAX)
        ? INT_MAX
        : static_cast<int>(size);
}

static void push_registered(lua_State *L, void *key) {
    lua_pushlightuserdata(L, key);
    lua_rawget(L, LUA_REGISTRYINDEX);
}

static bool is_registered(lua_State *L, int index, void *key) {
    index = absolute_index(L, index);
    push_registered(L, key);
    const bool equal = lua_rawequal(L, index, -1) != 0;
    lua_pop(L, 1);
    return equal;
}

static void push_empty_array(lua_State *L) {
    push_registered(L, &EMPTY_ARRAY_KEY);
}

static void push_empty_object(lua_State *L) {
    push_registered(L, &EMPTY_OBJECT_KEY);
}

static bool has_null_sentinel(lua_State *L, int null_index) noexcept {
    return null_index != 0 && !lua_isnil(L, null_index);
}

static bool is_null_sentinel(lua_State *L, int index, int null_index) noexcept {
    return has_null_sentinel(L, null_index) && lua_rawequal(L, index, null_index) != 0;
}

static bool table_is_empty(lua_State *L, int index) {
    index = absolute_index(L, index);
    lua_pushnil(L);
    if (lua_next(L, index) == 0) {
        return true;
    }
    lua_pop(L, 2);
    return false;
}

static bool push_dom_element(
    lua_State *L,
    simdjson::dom::element value,
    int null_index,
    const char **failure
) {
    if (!lua_checkstack(L, 6)) {
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
            if (array.size() == 0) {
                push_empty_array(L);
                return true;
            }
            lua_createtable(L, table_capacity(array.size()), 0);
            const int table_index = lua_gettop(L);
            int output_index = 1;
            for (const auto child : array) {
                if (child.type() == simdjson::dom::element_type::NULL_VALUE
                    && !has_null_sentinel(L, null_index)) {
                    continue;
                }
                if (!push_dom_element(L, child, null_index, failure)) {
                    return false;
                }
                lua_rawseti(L, table_index, output_index++);
            }
            if (output_index == 1) {
                lua_pop(L, 1);
                push_empty_array(L);
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
            if (object.size() == 0) {
                push_empty_object(L);
                return true;
            }
            lua_createtable(L, 0, table_capacity(object.size()));
            const int table_index = lua_gettop(L);
            for (const auto field : object) {
                const std::string_view key = field.key;
                lua_pushlstring(L, key.data(), key.size());
                if (field.value.type() == simdjson::dom::element_type::NULL_VALUE
                    && !has_null_sentinel(L, null_index)) {
                    lua_pushnil(L);
                } else if (!push_dom_element(L, field.value, null_index, failure)) {
                    return false;
                }
                lua_rawset(L, table_index);
            }
            if (table_is_empty(L, table_index)) {
                lua_pop(L, 1);
                push_empty_object(L);
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
            if (has_null_sentinel(L, null_index)) {
                lua_pushvalue(L, null_index);
            } else {
                lua_pushnil(L);
            }
            return true;
    }

    *failure = "unknown simdjson element type";
    return false;
}

template<typename Value>
static bool consume_ondemand(Value &value, const char **failure);

template<typename Value>
static emit_result push_ondemand_value(
    lua_State *L,
    Value &value,
    int null_index,
    const char **failure
) {
    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return emit_result::failed;
    }

    switch (type) {
        case simdjson::ondemand::json_type::array: {
            simdjson::ondemand::array array;
            error = value.get_array().get(array);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            lua_createtable(L, 0, 0);
            const int table_index = lua_gettop(L);
            int output_index = 1;
            for (auto child_result : array) {
                simdjson::ondemand::value child;
                error = child_result.get(child);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emit_result::failed;
                }
                const auto emitted = push_ondemand_value(L, child, null_index, failure);
                if (emitted == emit_result::failed) {
                    return emitted;
                }
                if (emitted == emit_result::produced) {
                    lua_rawseti(L, table_index, output_index++);
                }
            }
            if (output_index == 1) {
                lua_pop(L, 1);
                push_empty_array(L);
            }
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::object: {
            simdjson::ondemand::object object;
            error = value.get_object().get(object);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            lua_createtable(L, 0, 0);
            const int table_index = lua_gettop(L);
            for (auto field_result : object) {
                simdjson::ondemand::field field;
                error = std::move(field_result).get(field);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emit_result::failed;
                }
                std::string_view key;
                error = field.unescaped_key().get(key);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emit_result::failed;
                }
                lua_pushlstring(L, key.data(), key.size());
                auto &child = field.value();
                const auto emitted = push_ondemand_value(L, child, null_index, failure);
                if (emitted == emit_result::failed) {
                    return emitted;
                }
                if (emitted == emit_result::dropped) {
                    lua_pushnil(L);
                }
                lua_rawset(L, table_index);
            }
            if (table_is_empty(L, table_index)) {
                lua_pop(L, 1);
                push_empty_object(L);
            }
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::string: {
            std::string_view string;
            error = value.get_string().get(string);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            lua_pushlstring(L, string.data(), string.size());
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::number: {
            double number = 0;
            error = value.get_double().get(number);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            lua_pushnumber(L, number);
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::boolean: {
            bool boolean = false;
            error = value.get_bool().get(boolean);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            lua_pushboolean(L, boolean ? 1 : 0);
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::null: {
            bool is_null = false;
            error = value.is_null().get(is_null);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            if (!has_null_sentinel(L, null_index)) {
                return emit_result::dropped;
            }
            lua_pushvalue(L, null_index);
            return emit_result::produced;
        }
        case simdjson::ondemand::json_type::unknown:
            break;
    }

    *failure = "unknown simdjson On-Demand value type";
    return emit_result::failed;
}

template<typename Value>
static bool consume_ondemand(Value &value, const char **failure) {
    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return false;
    }

    switch (type) {
        case simdjson::ondemand::json_type::array: {
            simdjson::ondemand::array array;
            error = value.get_array().get(array);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            for (auto child_result : array) {
                simdjson::ondemand::value child;
                error = child_result.get(child);
                if (error || !consume_ondemand(child, failure)) {
                    if (error) {
                        *failure = simdjson::error_message(error);
                    }
                    return false;
                }
            }
            return true;
        }
        case simdjson::ondemand::json_type::object: {
            simdjson::ondemand::object object;
            error = value.get_object().get(object);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            for (auto field_result : object) {
                simdjson::ondemand::field field;
                error = std::move(field_result).get(field);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return false;
                }
                std::string_view key;
                error = field.unescaped_key().get(key);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return false;
                }
                auto &child = field.value();
                if (!consume_ondemand(child, failure)) {
                    return false;
                }
            }
            return true;
        }
        case simdjson::ondemand::json_type::string: {
            std::string_view string;
            error = value.get_string().get(string);
            break;
        }
        case simdjson::ondemand::json_type::number: {
            double number = 0;
            error = value.get_double().get(number);
            break;
        }
        case simdjson::ondemand::json_type::boolean: {
            bool boolean = false;
            error = value.get_bool().get(boolean);
            break;
        }
        case simdjson::ondemand::json_type::null: {
            bool is_null = false;
            error = value.is_null().get(is_null);
            break;
        }
        case simdjson::ondemand::json_type::unknown:
            *failure = "unknown simdjson On-Demand value type";
            return false;
    }
    if (error) {
        *failure = simdjson::error_message(error);
        return false;
    }
    return true;
}

static bool push_array_shape(lua_State *L, int shape_index) {
    shape_index = absolute_index(L, shape_index);
    if (!lua_istable(L, shape_index)) {
        return false;
    }
    lua_pushlightuserdata(L, &ARRAY_SHAPE_KEY);
    lua_rawget(L, shape_index);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return false;
    }
    return true;
}

template<typename Value>
static emit_result project_ondemand(
    lua_State *L,
    Value &value,
    int shape_index,
    int null_index,
    const char **failure
) {
    shape_index = absolute_index(L, shape_index);
    if (lua_isboolean(L, shape_index)) {
        if (lua_toboolean(L, shape_index)) {
            return push_ondemand_value(L, value, null_index, failure);
        }
        if (!consume_ondemand(value, failure)) {
            return emit_result::failed;
        }
        return emit_result::dropped;
    }
    if (!lua_istable(L, shape_index)) {
        *failure = "pull shape entries must be true, object shapes, or array shapes";
        return emit_result::failed;
    }

    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return emit_result::failed;
    }

    if (push_array_shape(L, shape_index)) {
        const int item_shape = lua_gettop(L);
        if (type != simdjson::ondemand::json_type::array) {
            lua_pop(L, 1);
            *failure = "pull array shape matched a non-array value";
            return emit_result::failed;
        }
        simdjson::ondemand::array array;
        error = value.get_array().get(array);
        if (error) {
            lua_pop(L, 1);
            *failure = simdjson::error_message(error);
            return emit_result::failed;
        }
        lua_createtable(L, 0, 0);
        const int table_index = lua_gettop(L);
        int output_index = 1;
        for (auto child_result : array) {
            simdjson::ondemand::value child;
            error = child_result.get(child);
            if (error) {
                *failure = simdjson::error_message(error);
                return emit_result::failed;
            }
            const auto emitted = project_ondemand(
                L, child, item_shape, null_index, failure
            );
            if (emitted == emit_result::failed) {
                return emitted;
            }
            if (emitted == emit_result::produced) {
                lua_rawseti(L, table_index, output_index++);
            }
        }
        lua_remove(L, item_shape);
        if (output_index == 1) {
            lua_pop(L, 1);
            push_empty_array(L);
        }
        return emit_result::produced;
    }

    if (type != simdjson::ondemand::json_type::object) {
        *failure = "pull object shape matched a non-object value";
        return emit_result::failed;
    }
    simdjson::ondemand::object object;
    error = value.get_object().get(object);
    if (error) {
        *failure = simdjson::error_message(error);
        return emit_result::failed;
    }
    lua_createtable(L, 0, 0);
    const int table_index = lua_gettop(L);
    for (auto field_result : object) {
        simdjson::ondemand::field field;
        error = std::move(field_result).get(field);
        if (error) {
            *failure = simdjson::error_message(error);
            return emit_result::failed;
        }
        std::string_view key;
        error = field.unescaped_key().get(key);
        if (error) {
            *failure = simdjson::error_message(error);
            return emit_result::failed;
        }
        lua_pushlstring(L, key.data(), key.size());
        lua_pushvalue(L, -1);
        lua_rawget(L, shape_index);
        const int child_shape = lua_gettop(L);
        auto &child = field.value();
        if (lua_isnil(L, child_shape) || !lua_toboolean(L, child_shape)) {
            lua_pop(L, 1);
            lua_pop(L, 1);
            if (!consume_ondemand(child, failure)) {
                return emit_result::failed;
            }
            continue;
        }
        const auto emitted = project_ondemand(
            L, child, child_shape, null_index, failure
        );
        if (emitted == emit_result::failed) {
            return emitted;
        }
        lua_remove(L, child_shape);
        if (emitted == emit_result::dropped) {
            lua_pushnil(L);
        }
        lua_rawset(L, table_index);
    }
    if (table_is_empty(L, table_index)) {
        lua_pop(L, 1);
        push_empty_object(L);
    }
    return emit_result::produced;
}

static table_kind classify_table(
    lua_State *L,
    int index,
    size_t *length,
    const char **failure
) {
    index = absolute_index(L, index);
    size_t count = 0;
    size_t highest = 0;
    bool string_keys = false;
    bool number_keys = false;
    lua_pushnil(L);
    while (lua_next(L, index) != 0) {
        ++count;
        if (lua_type(L, -2) == LUA_TSTRING) {
            string_keys = true;
        } else if (lua_type(L, -2) == LUA_TNUMBER) {
            const lua_Number number = lua_tonumber(L, -2);
            if (number < 1 || number != std::floor(number)) {
                lua_pop(L, 2);
                *failure = "JSON array indexes must be positive integers";
                return table_kind::invalid;
            }
            if (number > static_cast<lua_Number>(INT_MAX)) {
                lua_pop(L, 2);
                *failure = "JSON array index exceeds the Lua C API limit";
                return table_kind::invalid;
            }
            const size_t key = static_cast<size_t>(number);
            if (static_cast<lua_Number>(key) != number) {
                lua_pop(L, 2);
                *failure = "JSON array index is out of range";
                return table_kind::invalid;
            }
            number_keys = true;
            if (key > highest) {
                highest = key;
            }
        } else {
            lua_pop(L, 2);
            *failure = "JSON object keys must be strings";
            return table_kind::invalid;
        }
        lua_pop(L, 1);
    }
    if (count == 0) {
        *failure = "empty Lua tables are ambiguous; use empty_array or empty_object";
        return table_kind::invalid;
    }
    if (string_keys && number_keys) {
        *failure = "a JSON container cannot mix array indexes and object keys";
        return table_kind::invalid;
    }
    if (number_keys) {
        if (count != highest) {
            *failure = "JSON arrays cannot contain holes";
            return table_kind::invalid;
        }
        *length = highest;
        return table_kind::array;
    }
    *length = count;
    return table_kind::object;
}

static bool append_lua_value(
    lua_State *L,
    simdjson::builder::string_builder &builder,
    int index,
    int null_index,
    std::unordered_set<const void *> &visiting,
    size_t depth,
    const char **failure
) {
    index = absolute_index(L, index);
    null_index = null_index == 0 ? 0 : absolute_index(L, null_index);
    if (depth > simdjson::DEFAULT_MAX_DEPTH) {
        *failure = "JSON serialization nesting exceeds simdjson's limit";
        return false;
    }
    if (is_registered(L, index, &EMPTY_ARRAY_KEY)) {
        builder.start_array();
        builder.end_array();
        return true;
    }
    if (is_registered(L, index, &EMPTY_OBJECT_KEY)) {
        builder.start_object();
        builder.end_object();
        return true;
    }
    if (is_null_sentinel(L, index, null_index)) {
        builder.append_null();
        return true;
    }

    switch (lua_type(L, index)) {
        case LUA_TBOOLEAN:
            builder.append(lua_toboolean(L, index) != 0);
            return true;
        case LUA_TNUMBER: {
            const lua_Number number = lua_tonumber(L, index);
            if (!std::isfinite(number)) {
                *failure = "JSON numbers must be finite";
                return false;
            }
            constexpr double MAX_EXACT_INTEGER = 9007199254740991.0;
            if (number == std::floor(number)
                && std::abs(number) <= MAX_EXACT_INTEGER
                && !(number == 0 && std::signbit(number))) {
                builder.append(static_cast<int64_t>(number));
            } else {
                builder.append(number);
            }
            return true;
        }
        case LUA_TSTRING: {
            size_t length = 0;
            const char *string = lua_tolstring(L, index, &length);
            if (!simdjson::validate_utf8(string, length)) {
                *failure = "JSON strings must contain valid UTF-8";
                return false;
            }
            builder.escape_and_append_with_quotes(std::string_view(string, length));
            return true;
        }
        case LUA_TTABLE: {
            const void *identity = lua_topointer(L, index);
            if (!visiting.insert(identity).second) {
                *failure = "cannot serialize a cyclic Lua table";
                return false;
            }
            size_t length = 0;
            const auto kind = classify_table(L, index, &length, failure);
            bool ok = kind != table_kind::invalid;
            if (kind == table_kind::array) {
                builder.start_array();
                for (size_t item = 1; ok && item <= length; ++item) {
                    if (item > 1) {
                        builder.append_comma();
                    }
                    lua_rawgeti(L, index, static_cast<int>(item));
                    ok = append_lua_value(
                        L, builder, -1, null_index, visiting, depth + 1, failure
                    );
                    lua_pop(L, 1);
                }
                builder.end_array();
            } else if (kind == table_kind::object) {
                builder.start_object();
                bool first = true;
                lua_pushnil(L);
                while (ok && lua_next(L, index) != 0) {
                    size_t key_length = 0;
                    const char *key = lua_tolstring(L, -2, &key_length);
                    if (!simdjson::validate_utf8(key, key_length)) {
                        *failure = "JSON object keys must contain valid UTF-8";
                        ok = false;
                    } else {
                        if (!first) {
                            builder.append_comma();
                        }
                        first = false;
                        builder.escape_and_append_with_quotes(
                            std::string_view(key, key_length)
                        );
                        builder.append_colon();
                        ok = append_lua_value(
                            L, builder, -1, null_index, visiting, depth + 1, failure
                        );
                    }
                    lua_pop(L, 1);
                }
                if (!ok && lua_gettop(L) > index) {
                    lua_pop(L, 1);
                }
                builder.end_object();
            }
            visiting.erase(identity);
            return ok;
        }
        case LUA_TNIL:
            *failure = "nil has no JSON representation; use null() or a null sentinel";
            return false;
        default:
            *failure = "value has no JSON representation";
            return false;
    }
}

static lua_writer *checked_writer(lua_State *L, int index) {
    return static_cast<lua_writer *>(luaL_checkudata(L, index, WRITER_METATABLE));
}

static bool prepare_writer_value(lua_writer *writer, const char **failure) {
    if (writer->finished) {
        *failure = "writer is already finished";
        return false;
    }
    if (writer->frames.empty()) {
        if (writer->root_written) {
            *failure = "writer already has a root value";
            return false;
        }
        writer->root_written = true;
        return true;
    }
    auto &frame = writer->frames.back();
    if (frame.kind == container_kind::array) {
        if (!frame.first) {
            writer->builder.append_comma();
        }
        frame.first = false;
        return true;
    }
    if (!frame.needs_value) {
        *failure = "an object value must follow key()";
        return false;
    }
    frame.needs_value = false;
    return true;
}

static int writer_error(lua_State *L, const char *failure) {
    return luaL_error(L, "simdjson writer: %s", failure);
}

static int lua_writer_gc(lua_State *L) {
    checked_writer(L, 1)->~lua_writer();
    return 0;
}

static int lua_writer_start_array(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    const char *failure = nullptr;
    try {
        if (prepare_writer_value(writer, &failure)) {
            writer->builder.start_array();
            writer->frames.push_back({container_kind::array});
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int lua_writer_start_object(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    const char *failure = nullptr;
    try {
        if (prepare_writer_value(writer, &failure)) {
            writer->builder.start_object();
            writer->frames.push_back({container_kind::object});
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int lua_writer_key(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    size_t length = 0;
    const char *key = luaL_checklstring(L, 2, &length);
    const char *failure = nullptr;
    if (writer->finished || writer->frames.empty()
        || writer->frames.back().kind != container_kind::object) {
        failure = "key() requires an open object";
    } else if (writer->frames.back().needs_value) {
        failure = "the previous object key has no value";
    } else if (!simdjson::validate_utf8(key, length)) {
        failure = "JSON object keys must contain valid UTF-8";
    } else {
        auto &frame = writer->frames.back();
        if (!frame.first) {
            writer->builder.append_comma();
        }
        frame.first = false;
        frame.needs_value = true;
        writer->builder.escape_and_append_with_quotes(std::string_view(key, length));
        writer->builder.append_colon();
    }
    if (failure) {
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int lua_writer_write(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    luaL_checkany(L, 2);
    lua_getfenv(L, 1);
    lua_getfield(L, -1, "null");
    lua_remove(L, -2);
    const int null_index = lua_isnil(L, -1) ? 0 : lua_gettop(L);
    const char *failure = nullptr;
    try {
        std::unordered_set<const void *> visiting;
        if (prepare_writer_value(writer, &failure)) {
            append_lua_value(
                L, writer->builder, 2, null_index, visiting, 0, &failure
            );
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        lua_settop(L, 2);
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int lua_writer_null(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    const char *failure = nullptr;
    if (prepare_writer_value(writer, &failure)) {
        writer->builder.append_null();
    }
    if (failure) {
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int lua_writer_close(lua_State *L) {
    lua_writer *writer = checked_writer(L, 1);
    const char *failure = nullptr;
    if (writer->finished || writer->frames.empty()) {
        failure = "close() requires an open array or object";
    } else {
        const auto frame = writer->frames.back();
        if (frame.kind == container_kind::object && frame.needs_value) {
            failure = "the final object key has no value";
        } else {
            writer->frames.pop_back();
            if (frame.kind == container_kind::array) {
                writer->builder.end_array();
            } else {
                writer->builder.end_object();
            }
        }
    }
    if (failure) {
        return writer_error(L, failure);
    }
    lua_settop(L, 1);
    return 1;
}

static int push_writer_chunk(lua_State *L, lua_writer *writer, bool finish) {
    const char *failure = nullptr;
    if (writer->finished) {
        failure = "writer is already finished";
    } else if (finish && (!writer->root_written || !writer->frames.empty())) {
        failure = "finish() requires one complete root value";
    }
    if (failure) {
        return writer_error(L, failure);
    }
    std::string_view output;
    const auto error = writer->builder.view().get(output);
    if (error) {
        return writer_error(L, simdjson::error_message(error));
    }
    lua_pushlstring(L, output.data(), output.size());
    writer->builder.clear();
    writer->finished = finish;
    return 1;
}

static int lua_writer_flush(lua_State *L) {
    return push_writer_chunk(L, checked_writer(L, 1), false);
}

static int lua_writer_finish(lua_State *L) {
    return push_writer_chunk(L, checked_writer(L, 1), true);
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
            push_dom_element(L, document, null_index, &failure);
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }

    if (failure) {
        lua_settop(L, base);
        return luaL_error(L, "simdjson Lua DOM: %s", failure);
    }
    return 1;
}

static int lua_pull(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    luaL_checkany(L, 2);
    const int null_index = lua_gettop(L) >= 3 ? 3 : 0;
    const int base = lua_gettop(L);
    const char *failure = nullptr;
    emit_result emitted = emit_result::failed;

    try {
        std::vector<char> padded(length + simdjson::SIMDJSON_PADDING);
        std::memcpy(padded.data(), source, length);
        std::memset(padded.data() + length, 0, simdjson::SIMDJSON_PADDING);
        simdjson::ondemand::parser parser;
        simdjson::ondemand::document document;
        const auto error = parser.iterate(
            padded.data(), length, padded.size()
        ).get(document);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            emitted = project_ondemand(
                L, document, 2, null_index, &failure
            );
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }

    if (failure || emitted == emit_result::failed) {
        lua_settop(L, base);
        return luaL_error(
            L, "simdjson pull: %s",
            failure != nullptr ? failure : "unknown failure"
        );
    }
    if (emitted == emit_result::dropped) {
        lua_pushnil(L);
    }
    return 1;
}

static int lua_array_shape(lua_State *L) {
    lua_createtable(L, 0, 1);
    lua_pushlightuserdata(L, &ARRAY_SHAPE_KEY);
    if (lua_gettop(L) >= 2) {
        lua_pushvalue(L, 1);
    } else {
        lua_pushboolean(L, 1);
    }
    lua_rawset(L, -3);
    return 1;
}

static int lua_encode(lua_State *L) {
    luaL_checkany(L, 1);
    const int null_index = lua_gettop(L) >= 2 ? 2 : 0;
    const int base = lua_gettop(L);
    const char *failure = nullptr;
    try {
        simdjson::builder::string_builder builder;
        std::unordered_set<const void *> visiting;
        if (append_lua_value(
            L, builder, 1, null_index, visiting, 0, &failure
        )) {
            std::string_view output;
            const auto error = builder.view().get(output);
            if (error) {
                failure = simdjson::error_message(error);
            } else {
                lua_pushlstring(L, output.data(), output.size());
            }
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        lua_settop(L, base);
        return luaL_error(L, "simdjson encode: %s", failure);
    }
    return 1;
}

static int lua_new_writer(lua_State *L) {
    void *storage = lua_newuserdata(L, sizeof(lua_writer));
    new (storage) lua_writer{};
    luaL_getmetatable(L, WRITER_METATABLE);
    lua_setmetatable(L, -2);
    lua_createtable(L, 0, 1);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 1)) {
        lua_pushvalue(L, 1);
        lua_setfield(L, -2, "null");
    }
    lua_setfenv(L, -2);
    return 1;
}

static int lua_sentinel_tostring(lua_State *L) {
    auto *value = static_cast<sentinel *>(
        luaL_checkudata(L, 1, SENTINEL_METATABLE)
    );
    lua_pushstring(L, value->name);
    return 1;
}

static void set_function(lua_State *L, const char *name, lua_CFunction function) {
    lua_pushcfunction(L, function);
    lua_setfield(L, -2, name);
}

static void install_sentinel(
    lua_State *L,
    int module_index,
    void *key,
    const char *field,
    const char *name
) {
    module_index = absolute_index(L, module_index);
    push_registered(L, key);
    if (!lua_isnil(L, -1)) {
        lua_setfield(L, module_index, field);
        return;
    }
    lua_pop(L, 1);
    auto *value = static_cast<sentinel *>(lua_newuserdata(L, sizeof(sentinel)));
    value->name = name;
    luaL_getmetatable(L, SENTINEL_METATABLE);
    lua_setmetatable(L, -2);
    lua_pushlightuserdata(L, key);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_setfield(L, module_index, field);
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
    luaL_newmetatable(L, SENTINEL_METATABLE);
    set_function(L, "__tostring", lua_sentinel_tostring);
    lua_pushliteral(L, "simdjson sentinel");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);

    luaL_newmetatable(L, WRITER_METATABLE);
    set_function(L, "__gc", lua_writer_gc);
    set_function(L, "startArray", lua_writer_start_array);
    set_function(L, "startObject", lua_writer_start_object);
    set_function(L, "key", lua_writer_key);
    set_function(L, "write", lua_writer_write);
    set_function(L, "null", lua_writer_null);
    set_function(L, "close", lua_writer_close);
    set_function(L, "flush", lua_writer_flush);
    set_function(L, "finish", lua_writer_finish);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pushliteral(L, "simdjson writer");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);

    lua_createtable(L, 0, 8);
    const int module_index = lua_gettop(L);
    set_function(L, "decode", lua_decode);
    set_function(L, "pull", lua_pull);
    set_function(L, "array", lua_array_shape);
    set_function(L, "encode", lua_encode);
    set_function(L, "writer", lua_new_writer);
    install_sentinel(
        L, module_index, &EMPTY_ARRAY_KEY,
        "empty_array", "simdjson empty array"
    );
    install_sentinel(
        L, module_index, &EMPTY_OBJECT_KEY,
        "empty_object", "simdjson empty object"
    );
    return 1;
}
