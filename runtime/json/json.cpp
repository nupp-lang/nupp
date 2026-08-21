#include "json.h"

#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
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

struct nuppSimdjsonParser {
    simdjson::dom::parser dom;
    simdjson::ondemand::parser ondemand;
    std::vector<char> padded;
    size_t length{0};
    uint64_t sink{0};
};

namespace {

constexpr const char *WRITER_METATABLE = "nupp.simdjson.writer";
constexpr const char *ENCODED_VALUE_METATABLE = "nupp.simdjson.encoded-value";
constexpr const char *ENCODED_STRING_METATABLE = "nupp.simdjson.encoded-string";
static char EMPTY_ARRAY_KEY;
static char EMPTY_OBJECT_KEY;
static char NULL_KEY;
static char ARRAY_SHAPE_KEY;
static char BUFFER_METATABLE_KEY;
static char ENCODED_STRING_INTERN_KEY;
static char VERIFIED_STRING_INTERN_KEY;

enum class containerKind {
    ARRAY,
    OBJECT,
};

struct writerFrame {
    containerKind kind;
    bool first{true};
    bool needsValue{false};
};

struct writerBacking {
    simdjson::builder::string_builder builder;
    std::vector<writerFrame> frames;
    std::unordered_set<const void *> visiting;
};

struct luaWriter {
    writerBacking *backing{nullptr};
    bool rootWritten{false};
    bool finished{false};
};

constexpr size_t WRITER_FLUSH_THRESHOLD = 64 * 1024;
constexpr size_t WRITER_POOL_LIMIT = 32;
static thread_local std::vector<std::unique_ptr<writerBacking>> WRITER_POOL;

struct encodedBytes {};

enum class emitResult {
    PRODUCED,
    DROPPED,
    FAILED,
};

enum class tableKind {
    ARRAY,
    OBJECT,
    INVALID,
};

static int absoluteIndex(lua_State *L, int index) noexcept {
    if (index > 0 || index <= LUA_REGISTRYINDEX) {
        return index;
    }
    return lua_gettop(L) + index + 1;
}

static int tableCapacity(size_t size) noexcept {
    return size > static_cast<size_t>(INT_MAX)
        ? INT_MAX
        : static_cast<int>(size);
}

static void pushRegistered(lua_State *L, void *key) {
    lua_pushlightuserdata(L, key);
    lua_rawget(L, LUA_REGISTRYINDEX);
}

static bool isRegistered(lua_State *L, int index, void *key) {
    index = absoluteIndex(L, index);
    pushRegistered(L, key);
    const bool equal = lua_rawequal(L, index, -1) != 0;
    lua_pop(L, 1);
    return equal;
}

static void pushEmptyArray(lua_State *L) {
    lua_createtable(L, 0, 0);
    pushRegistered(L, &EMPTY_ARRAY_KEY);
    lua_setmetatable(L, -2);
}

static void pushEmptyObject(lua_State *L) {
    lua_createtable(L, 0, 0);
    pushRegistered(L, &EMPTY_OBJECT_KEY);
    lua_setmetatable(L, -2);
}

static bool hasRegisteredMetatable(lua_State *L, int index, void *key) {
    index = absoluteIndex(L, index);
    if (!lua_getmetatable(L, index)) {
        return false;
    }
    pushRegistered(L, key);
    const bool equal = lua_rawequal(L, -1, -2) != 0;
    lua_pop(L, 2);
    return equal;
}

static bool hasNullSentinel(lua_State *L, int nullIndex) noexcept {
    return nullIndex != 0 && !lua_isnil(L, nullIndex);
}

static bool isNullSentinel(lua_State *L, int index, int nullIndex) noexcept {
    return hasNullSentinel(L, nullIndex) && lua_rawequal(L, index, nullIndex) != 0;
}

static bool tableIsEmpty(lua_State *L, int index) {
    index = absoluteIndex(L, index);
    lua_pushnil(L);
    if (lua_next(L, index) == 0) {
        return true;
    }
    lua_pop(L, 2);
    return false;
}

static bool pushDomElement(
    lua_State *L,
    simdjson::dom::element value,
    int nullIndex,
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
                pushEmptyArray(L);
                return true;
            }
            lua_createtable(L, tableCapacity(array.size()), 0);
            const int tableIndex = lua_gettop(L);
            int outputIndex = 1;
            for (const auto child : array) {
                if (child.type() == simdjson::dom::element_type::NULL_VALUE
                    && !hasNullSentinel(L, nullIndex)) {
                    continue;
                }
                if (!pushDomElement(L, child, nullIndex, failure)) {
                    return false;
                }
                lua_rawseti(L, tableIndex, outputIndex++);
            }
            if (outputIndex == 1) {
                lua_pop(L, 1);
                pushEmptyArray(L);
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
                pushEmptyObject(L);
                return true;
            }
            lua_createtable(L, 0, tableCapacity(object.size()));
            const int tableIndex = lua_gettop(L);
            for (const auto field : object) {
                const std::string_view key = field.key;
                lua_pushlstring(L, key.data(), key.size());
                if (field.value.type() == simdjson::dom::element_type::NULL_VALUE
                    && !hasNullSentinel(L, nullIndex)) {
                    lua_pushnil(L);
                } else if (!pushDomElement(L, field.value, nullIndex, failure)) {
                    return false;
                }
                lua_rawset(L, tableIndex);
            }
            if (tableIsEmpty(L, tableIndex)) {
                lua_pop(L, 1);
                pushEmptyObject(L);
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
            if (hasNullSentinel(L, nullIndex)) {
                lua_pushvalue(L, nullIndex);
            } else {
                lua_pushnil(L);
            }
            return true;
    }

    *failure = "unknown simdjson element type";
    return false;
}

template<typename Value>
static bool consumeOnDemand(Value &value, const char **failure);

template<typename Value>
static emitResult pushOnDemandValue(
    lua_State *L,
    Value &value,
    int nullIndex,
    const char **failure
) {
    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return emitResult::FAILED;
    }

    switch (type) {
        case simdjson::ondemand::json_type::array: {
            simdjson::ondemand::array array;
            error = value.get_array().get(array);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            lua_createtable(L, 0, 0);
            const int tableIndex = lua_gettop(L);
            int outputIndex = 1;
            for (auto childResult : array) {
                simdjson::ondemand::value child;
                error = childResult.get(child);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emitResult::FAILED;
                }
                const auto emitted = pushOnDemandValue(L, child, nullIndex, failure);
                if (emitted == emitResult::FAILED) {
                    return emitted;
                }
                if (emitted == emitResult::PRODUCED) {
                    lua_rawseti(L, tableIndex, outputIndex++);
                }
            }
            if (outputIndex == 1) {
                lua_pop(L, 1);
                pushEmptyArray(L);
            }
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::object: {
            simdjson::ondemand::object object;
            error = value.get_object().get(object);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            lua_createtable(L, 0, 0);
            const int tableIndex = lua_gettop(L);
            for (auto fieldResult : object) {
                simdjson::ondemand::field field;
                error = std::move(fieldResult).get(field);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emitResult::FAILED;
                }
                std::string_view key;
                error = field.unescaped_key().get(key);
                if (error) {
                    *failure = simdjson::error_message(error);
                    return emitResult::FAILED;
                }
                lua_pushlstring(L, key.data(), key.size());
                auto &child = field.value();
                const auto emitted = pushOnDemandValue(L, child, nullIndex, failure);
                if (emitted == emitResult::FAILED) {
                    return emitted;
                }
                if (emitted == emitResult::DROPPED) {
                    lua_pushnil(L);
                }
                lua_rawset(L, tableIndex);
            }
            if (tableIsEmpty(L, tableIndex)) {
                lua_pop(L, 1);
                pushEmptyObject(L);
            }
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::string: {
            std::string_view string;
            error = value.get_string().get(string);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            lua_pushlstring(L, string.data(), string.size());
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::number: {
            double number = 0;
            error = value.get_double().get(number);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            lua_pushnumber(L, number);
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::boolean: {
            bool boolean = false;
            error = value.get_bool().get(boolean);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            lua_pushboolean(L, boolean ? 1 : 0);
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::null: {
            bool isNull = false;
            error = value.is_null().get(isNull);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            if (!hasNullSentinel(L, nullIndex)) {
                return emitResult::DROPPED;
            }
            lua_pushvalue(L, nullIndex);
            return emitResult::PRODUCED;
        }
        case simdjson::ondemand::json_type::unknown:
            break;
    }

    *failure = "unknown simdjson On-Demand value type";
    return emitResult::FAILED;
}

template<typename Value>
static bool consumeOnDemand(Value &value, const char **failure) {
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
            for (auto childResult : array) {
                simdjson::ondemand::value child;
                error = childResult.get(child);
                if (error || !consumeOnDemand(child, failure)) {
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
            for (auto fieldResult : object) {
                simdjson::ondemand::field field;
                error = std::move(fieldResult).get(field);
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
                if (!consumeOnDemand(child, failure)) {
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
            bool isNull = false;
            error = value.is_null().get(isNull);
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

static bool pushArrayShape(lua_State *L, int shapeIndex) {
    shapeIndex = absoluteIndex(L, shapeIndex);
    if (!lua_istable(L, shapeIndex)) {
        return false;
    }
    lua_pushlightuserdata(L, &ARRAY_SHAPE_KEY);
    lua_rawget(L, shapeIndex);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return false;
    }
    return true;
}

template<typename Value>
static emitResult projectOnDemand(
    lua_State *L,
    Value &value,
    int shapeIndex,
    int nullIndex,
    const char **failure
) {
    shapeIndex = absoluteIndex(L, shapeIndex);
    if (lua_isboolean(L, shapeIndex)) {
        if (lua_toboolean(L, shapeIndex)) {
            return pushOnDemandValue(L, value, nullIndex, failure);
        }
        if (!consumeOnDemand(value, failure)) {
            return emitResult::FAILED;
        }
        return emitResult::DROPPED;
    }
    if (!lua_istable(L, shapeIndex)) {
        *failure = "pull shape entries must be true, object shapes, or array shapes";
        return emitResult::FAILED;
    }

    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return emitResult::FAILED;
    }

    if (pushArrayShape(L, shapeIndex)) {
        const int itemShape = lua_gettop(L);
        if (type != simdjson::ondemand::json_type::array) {
            lua_pop(L, 1);
            *failure = "pull array shape matched a non-array value";
            return emitResult::FAILED;
        }
        simdjson::ondemand::array array;
        error = value.get_array().get(array);
        if (error) {
            lua_pop(L, 1);
            *failure = simdjson::error_message(error);
            return emitResult::FAILED;
        }
        lua_createtable(L, 0, 0);
        const int tableIndex = lua_gettop(L);
        int outputIndex = 1;
        for (auto childResult : array) {
            simdjson::ondemand::value child;
            error = childResult.get(child);
            if (error) {
                *failure = simdjson::error_message(error);
                return emitResult::FAILED;
            }
            const auto emitted = projectOnDemand(
                L, child, itemShape, nullIndex, failure
            );
            if (emitted == emitResult::FAILED) {
                return emitted;
            }
            if (emitted == emitResult::PRODUCED) {
                lua_rawseti(L, tableIndex, outputIndex++);
            }
        }
        lua_remove(L, itemShape);
        if (outputIndex == 1) {
            lua_pop(L, 1);
            pushEmptyArray(L);
        }
        return emitResult::PRODUCED;
    }

    if (type != simdjson::ondemand::json_type::object) {
        *failure = "pull object shape matched a non-object value";
        return emitResult::FAILED;
    }
    simdjson::ondemand::object object;
    error = value.get_object().get(object);
    if (error) {
        *failure = simdjson::error_message(error);
        return emitResult::FAILED;
    }
    lua_createtable(L, 0, 0);
    const int tableIndex = lua_gettop(L);
    for (auto fieldResult : object) {
        simdjson::ondemand::field field;
        error = std::move(fieldResult).get(field);
        if (error) {
            *failure = simdjson::error_message(error);
            return emitResult::FAILED;
        }
        std::string_view key;
        error = field.unescaped_key().get(key);
        if (error) {
            *failure = simdjson::error_message(error);
            return emitResult::FAILED;
        }
        lua_pushlstring(L, key.data(), key.size());
        lua_pushvalue(L, -1);
        lua_rawget(L, shapeIndex);
        const int childShape = lua_gettop(L);
        auto &child = field.value();
        if (lua_isnil(L, childShape) || !lua_toboolean(L, childShape)) {
            lua_pop(L, 1);
            lua_pop(L, 1);
            if (!consumeOnDemand(child, failure)) {
                return emitResult::FAILED;
            }
            continue;
        }
        const auto emitted = projectOnDemand(
            L, child, childShape, nullIndex, failure
        );
        if (emitted == emitResult::FAILED) {
            return emitted;
        }
        lua_remove(L, childShape);
        if (emitted == emitResult::DROPPED) {
            lua_pushnil(L);
        }
        lua_rawset(L, tableIndex);
    }
    if (tableIsEmpty(L, tableIndex)) {
        lua_pop(L, 1);
        pushEmptyObject(L);
    }
    return emitResult::PRODUCED;
}

static tableKind classifyTable(
    lua_State *L,
    int index,
    size_t *length,
    const char **failure
) {
    index = absoluteIndex(L, index);
    const bool forcedArray = hasRegisteredMetatable(L, index, &EMPTY_ARRAY_KEY);
    const bool forcedObject = hasRegisteredMetatable(L, index, &EMPTY_OBJECT_KEY);
    size_t count = 0;
    size_t highest = 0;
    bool stringKeys = false;
    bool numberKeys = false;
    lua_pushnil(L);
    while (lua_next(L, index) != 0) {
        ++count;
        if (lua_type(L, -2) == LUA_TSTRING) {
            stringKeys = true;
        } else if (lua_type(L, -2) == LUA_TNUMBER) {
            const lua_Number number = lua_tonumber(L, -2);
            if (number < 1 || number != std::floor(number)) {
                lua_pop(L, 2);
                *failure = "JSON array indexes must be positive integers";
                return tableKind::INVALID;
            }
            if (number > static_cast<lua_Number>(INT_MAX)) {
                lua_pop(L, 2);
                *failure = "JSON array index exceeds the Lua C API limit";
                return tableKind::INVALID;
            }
            const size_t key = static_cast<size_t>(number);
            if (static_cast<lua_Number>(key) != number) {
                lua_pop(L, 2);
                *failure = "JSON array index is out of range";
                return tableKind::INVALID;
            }
            numberKeys = true;
            if (key > highest) {
                highest = key;
            }
        } else {
            lua_pop(L, 2);
            *failure = "JSON object keys must be strings";
            return tableKind::INVALID;
        }
        lua_pop(L, 1);
    }
    if (count == 0) {
        *length = 0;
        return forcedArray ? tableKind::ARRAY : tableKind::OBJECT;
    }
    if (stringKeys && numberKeys) {
        *failure = "a JSON container cannot mix array indexes and object keys";
        return tableKind::INVALID;
    }
    if (forcedArray && stringKeys) {
        *failure = "an array-marked table cannot contain object keys";
        return tableKind::INVALID;
    }
    if (forcedObject && numberKeys) {
        *failure = "an object-marked table cannot contain array indexes";
        return tableKind::INVALID;
    }
    if (numberKeys) {
        if (count != highest) {
            *failure = "JSON arrays cannot contain holes";
            return tableKind::INVALID;
        }
        *length = highest;
        return tableKind::ARRAY;
    }
    *length = count;
    return tableKind::OBJECT;
}

static bool appendLuaValue(
    lua_State *L,
    simdjson::builder::string_builder &builder,
    int index,
    int nullIndex,
    std::unordered_set<const void *> &visiting,
    size_t depth,
    const char **failure
) {
    index = absoluteIndex(L, index);
    nullIndex = nullIndex == 0 ? 0 : absoluteIndex(L, nullIndex);
    if (depth > simdjson::DEFAULT_MAX_DEPTH) {
        *failure = "JSON serialization nesting exceeds simdjson's limit";
        return false;
    }
    if (isRegistered(L, index, &EMPTY_ARRAY_KEY)) {
        builder.start_array();
        builder.end_array();
        return true;
    }
    if (isRegistered(L, index, &EMPTY_OBJECT_KEY)) {
        builder.start_object();
        builder.end_object();
        return true;
    }
    if (isNullSentinel(L, index, nullIndex)) {
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
            const auto kind = classifyTable(L, index, &length, failure);
            bool ok = kind != tableKind::INVALID;
            if (kind == tableKind::ARRAY) {
                builder.start_array();
                for (size_t item = 1; ok && item <= length; ++item) {
                    if (item > 1) {
                        builder.append_comma();
                    }
                    lua_rawgeti(L, index, static_cast<int>(item));
                    ok = appendLuaValue(
                        L, builder, -1, nullIndex, visiting, depth + 1, failure
                    );
                    lua_pop(L, 1);
                }
                builder.end_array();
            } else if (kind == tableKind::OBJECT) {
                builder.start_object();
                bool first = true;
                lua_pushnil(L);
                while (ok && lua_next(L, index) != 0) {
                    size_t keyLength = 0;
                    const char *key = lua_tolstring(L, -2, &keyLength);
                    if (!simdjson::validate_utf8(key, keyLength)) {
                        *failure = "JSON object keys must contain valid UTF-8";
                        ok = false;
                    } else {
                        if (!first) {
                            builder.append_comma();
                        }
                        first = false;
                        builder.escape_and_append_with_quotes(
                            std::string_view(key, keyLength)
                        );
                        builder.append_colon();
                        ok = appendLuaValue(
                            L, builder, -1, nullIndex, visiting, depth + 1, failure
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

static void pushEncoded(
    lua_State *L,
    const char *metatable,
    int bytesIndex
) {
    bytesIndex = absoluteIndex(L, bytesIndex);
    new (lua_newuserdata(L, sizeof(encodedBytes))) encodedBytes{};
    luaL_getmetatable(L, metatable);
    lua_setmetatable(L, -2);
    lua_createtable(L, 0, 1);
    lua_pushvalue(L, bytesIndex);
    lua_setfield(L, -2, "bytes");
    lua_setfenv(L, -2);
}

static bool pushEncodedBytes(
    lua_State *L,
    int index,
    const char *metatable,
    std::string_view *bytes
) {
    index = absoluteIndex(L, index);
    if (!lua_getmetatable(L, index)) {
        return false;
    }
    luaL_getmetatable(L, metatable);
    const bool matches = lua_rawequal(L, -1, -2) != 0;
    lua_pop(L, 2);
    if (!matches) {
        return false;
    }
    lua_getfenv(L, index);
    lua_getfield(L, -1, "bytes");
    lua_remove(L, -2);
    size_t length = 0;
    const char *data = lua_tolstring(L, -1, &length);
    if (data == nullptr) {
        luaL_error(L, "simdjson encoded value lost its bytes");
    }
    *bytes = std::string_view(data, length);
    return true;
}

static void appendToBuffer(
    lua_State *L,
    int bufferIndex,
    std::string_view bytes
) {
    if (bytes.empty()) {
        return;
    }
    bufferIndex = absoluteIndex(L, bufferIndex);
    lua_getfield(L, bufferIndex, "reserve");
    lua_pushvalue(L, bufferIndex);
    lua_pushinteger(L, static_cast<lua_Integer>(bytes.size()));
    lua_call(L, 2, 2);
    const void *storage = lua_topointer(L, -2);
    if (storage == nullptr) {
        luaL_error(L, "string.buffer.Buffer.reserve() returned no storage");
    }
    char *destination = *static_cast<char *const *>(storage);
    std::memcpy(destination, bytes.data(), bytes.size());
    lua_pop(L, 2);

    lua_getfield(L, bufferIndex, "commit");
    lua_pushvalue(L, bufferIndex);
    lua_pushinteger(L, static_cast<lua_Integer>(bytes.size()));
    lua_call(L, 2, 1);
    lua_pop(L, 1);
}

static void appendToWriterBuffer(
    lua_State *L,
    int index,
    std::string_view bytes
) {
    if (bytes.empty()) {
        return;
    }
    index = absoluteIndex(L, index);
    lua_getfenv(L, index);
    lua_getfield(L, -1, "out");
    appendToBuffer(L, -1, bytes);
    lua_pop(L, 2);
}

static void drainWriter(lua_State *L, int index, luaWriter *writer) {
    auto *backing = writer->backing;
    std::string_view output;
    const auto error = backing->builder.view().get(output);
    if (error) {
        luaL_error(L, "simdjson writer: %s", simdjson::error_message(error));
    }
    appendToWriterBuffer(L, index, output);
    backing->builder.clear();
}

static void drainWriterAtThreshold(lua_State *L, int index, luaWriter *writer) {
    std::string_view output;
    const auto error = writer->backing->builder.view().get(output);
    if (error) {
        luaL_error(L, "simdjson writer: %s", simdjson::error_message(error));
    }
    if (output.size() >= WRITER_FLUSH_THRESHOLD) {
        drainWriter(L, index, writer);
    }
}

static writerBacking *acquireWriterBacking() {
    if (WRITER_POOL.empty()) {
        return new writerBacking{};
    }
    auto *backing = WRITER_POOL.back().release();
    WRITER_POOL.pop_back();
    return backing;
}

static void releaseWriterBacking(luaWriter *writer) noexcept {
    auto *backing = writer->backing;
    if (backing == nullptr) {
        return;
    }
    backing->builder.clear();
    backing->frames.clear();
    backing->visiting.clear();
    writer->backing = nullptr;
    if (WRITER_POOL.size() < WRITER_POOL_LIMIT) {
        std::unique_ptr<writerBacking> owned(backing);
        try {
            WRITER_POOL.push_back(std::move(owned));
        } catch (...) {
            // `owned` deletes the backing. Cleanup must remain non-throwing.
        }
    } else {
        delete backing;
    }
}

static luaWriter *checkedWriter(lua_State *L, int index) {
    return static_cast<luaWriter *>(luaL_checkudata(L, index, WRITER_METATABLE));
}

static bool prepareWriterValue(luaWriter *writer, const char **failure) {
    if (writer->finished || writer->backing == nullptr) {
        *failure = "writer is already closed";
        return false;
    }
    if (writer->backing->frames.empty()) {
        if (writer->rootWritten) {
            *failure = "writer already has a root value";
            return false;
        }
        writer->rootWritten = true;
        return true;
    }
    auto &frame = writer->backing->frames.back();
    if (frame.kind == containerKind::ARRAY) {
        if (!frame.first) {
            writer->backing->builder.append_comma();
        }
        frame.first = false;
        return true;
    }
    if (!frame.needsValue) {
        *failure = "an object value must follow key()";
        return false;
    }
    frame.needsValue = false;
    return true;
}

static int writerError(lua_State *L, const char *failure) {
    return luaL_error(L, "simdjson writer: %s", failure);
}

static int luaWriterGc(lua_State *L) {
    auto *writer = checkedWriter(L, 1);
    delete writer->backing;
    writer->backing = nullptr;
    writer->~luaWriter();
    return 0;
}

static int luaWriterStartArray(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    const char *failure = nullptr;
    try {
        if (prepareWriterValue(writer, &failure)) {
            writer->backing->builder.start_array();
            writer->backing->frames.push_back({containerKind::ARRAY});
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static int luaWriterStartObject(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    const char *failure = nullptr;
    try {
        if (prepareWriterValue(writer, &failure)) {
            writer->backing->builder.start_object();
            writer->backing->frames.push_back({containerKind::OBJECT});
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static const char *appendWriterKey(
    luaWriter *writer,
    const char *key,
    size_t length
) {
    if (writer->finished || writer->backing == nullptr
        || writer->backing->frames.empty()
        || writer->backing->frames.back().kind != containerKind::OBJECT) {
        return "key() requires an open object";
    } else if (writer->backing->frames.back().needsValue) {
        return "the previous object key has no value";
    } else if (!simdjson::validate_utf8(key, length)) {
        return "JSON object keys must contain valid UTF-8";
    }

    auto &frame = writer->backing->frames.back();
    if (!frame.first) {
        writer->backing->builder.append_comma();
    }
    frame.first = false;
    frame.needsValue = true;
    writer->backing->builder.escape_and_append_with_quotes(
        std::string_view(key, length)
    );
    writer->backing->builder.append_colon();
    return nullptr;
}

static int luaWriterKey(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    const char *failure = nullptr;
    std::string_view encoded;
    if (pushEncodedBytes(L, 2, ENCODED_STRING_METATABLE, &encoded)) {
        if (writer->finished || writer->backing == nullptr
            || writer->backing->frames.empty()
            || writer->backing->frames.back().kind != containerKind::OBJECT) {
            failure = "key() requires an open object";
        } else if (writer->backing->frames.back().needsValue) {
            failure = "the previous object key has no value";
        } else {
            auto &frame = writer->backing->frames.back();
            if (!frame.first) {
                writer->backing->builder.append_comma();
            }
            frame.first = false;
            frame.needsValue = true;
            writer->backing->builder.append_raw(encoded);
            writer->backing->builder.append_colon();
        }
        lua_pop(L, 1);
    } else {
        size_t length = 0;
        const char *key = luaL_checklstring(L, 2, &length);
        failure = appendWriterKey(writer, key, length);
    }
    if (failure) {
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static int luaWriterWrite(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    luaL_checkany(L, 2);
    lua_getfenv(L, 1);
    lua_getfield(L, -1, "null");
    lua_remove(L, -2);
    const int nullIndex = lua_isnil(L, -1) ? 0 : lua_gettop(L);
    const char *failure = nullptr;
    try {
        std::string_view encoded;
        const bool isEncoded = pushEncodedBytes(
            L, 2, ENCODED_VALUE_METATABLE, &encoded
        ) || pushEncodedBytes(L, 2, ENCODED_STRING_METATABLE, &encoded);
        if (prepareWriterValue(writer, &failure)) {
            if (isEncoded) {
                writer->backing->builder.append_raw(encoded);
            } else {
                writer->backing->visiting.clear();
                appendLuaValue(
                    L, writer->backing->builder, 2, nullIndex,
                    writer->backing->visiting, 0, &failure
                );
                writer->backing->visiting.clear();
            }
        }
        if (isEncoded) {
            lua_pop(L, 1);
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        lua_settop(L, 2);
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static int luaWriterNull(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    const char *failure = nullptr;
    if (prepareWriterValue(writer, &failure)) {
        writer->backing->builder.append_null();
    }
    if (failure) {
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static int luaWriterEndContainer(
    lua_State *L,
    containerKind expected,
    const char *operation
) {
    luaWriter *writer = checkedWriter(L, 1);
    const char *failure = nullptr;
    if (writer->finished || writer->backing == nullptr
        || writer->backing->frames.empty()
        || writer->backing->frames.back().kind != expected) {
        failure = operation;
    } else {
        const auto frame = writer->backing->frames.back();
        if (frame.kind == containerKind::OBJECT && frame.needsValue) {
            failure = "the final object key has no value";
        } else {
            writer->backing->frames.pop_back();
            if (frame.kind == containerKind::ARRAY) {
                writer->backing->builder.end_array();
            } else {
                writer->backing->builder.end_object();
            }
        }
    }
    if (failure) {
        return writerError(L, failure);
    }
    drainWriterAtThreshold(L, 1, writer);
    lua_settop(L, 1);
    return 1;
}

static int luaWriterEndArray(lua_State *L) {
    return luaWriterEndContainer(
        L, containerKind::ARRAY, "endArray() requires an open array"
    );
}

static int luaWriterEndObject(lua_State *L) {
    return luaWriterEndContainer(
        L, containerKind::OBJECT, "endObject() requires an open object"
    );
}

static int luaWriterFlush(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    if (writer->finished || writer->backing == nullptr) {
        return writerError(L, "writer is already closed");
    }
    drainWriter(L, 1, writer);
    return 0;
}

static void clearWriterEnvironment(lua_State *L, int index) {
    lua_createtable(L, 0, 0);
    lua_setfenv(L, index);
}

static int luaWriterClose(lua_State *L) {
    luaWriter *writer = checkedWriter(L, 1);
    if (writer->finished || writer->backing == nullptr) {
        return writerError(L, "writer is already closed");
    }
    writer->finished = true;
    const bool complete = writer->rootWritten
        && writer->backing->frames.empty();
    if (!complete) {
        releaseWriterBacking(writer);
        clearWriterEnvironment(L, 1);
        return writerError(L, "close() requires one complete root value");
    }
    drainWriter(L, 1, writer);
    releaseWriterBacking(writer);
    clearWriterEnvironment(L, 1);
    return 0;
}

static int luaDecode(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    const int nullIndex = lua_gettop(L) >= 2 ? 2 : 0;
    const int base = lua_gettop(L);
    const char *failure = nullptr;

    try {
        static thread_local simdjson::dom::parser parser;
        simdjson::dom::element document;
        const auto error = parser.parse(source, length, true).get(document);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            pushDomElement(L, document, nullIndex, &failure);
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

static int luaPull(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    luaL_checkany(L, 2);
    const int nullIndex = lua_gettop(L) >= 3 ? 3 : 0;
    const int base = lua_gettop(L);
    const char *failure = nullptr;
    emitResult emitted = emitResult::FAILED;

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
            emitted = projectOnDemand(
                L, document, 2, nullIndex, &failure
            );
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }

    if (failure || emitted == emitResult::FAILED) {
        lua_settop(L, base);
        return luaL_error(
            L, "simdjson pull: %s",
            failure != nullptr ? failure : "unknown failure"
        );
    }
    if (emitted == emitResult::DROPPED) {
        lua_pushnil(L);
    }
    return 1;
}

static int luaArrayOf(lua_State *L) {
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

static int markTable(lua_State *L, void *key) {
    luaL_checktype(L, 1, LUA_TTABLE);
    pushRegistered(L, key);
    lua_setmetatable(L, 1);
    lua_settop(L, 1);
    return 1;
}

static int luaAsArray(lua_State *L) {
    return markTable(L, &EMPTY_ARRAY_KEY);
}

static int luaAsObject(lua_State *L) {
    return markTable(L, &EMPTY_OBJECT_KEY);
}

static int luaEncode(lua_State *L) {
    luaL_checkany(L, 1);
    int nullIndex = lua_gettop(L) >= 2 ? 2 : 0;
    if (nullIndex == 0) {
        pushRegistered(L, &NULL_KEY);
        nullIndex = lua_gettop(L);
    }
    const int base = lua_gettop(L);
    const char *failure = nullptr;
    try {
        simdjson::builder::string_builder builder;
        std::unordered_set<const void *> visiting;
        if (appendLuaValue(
            L, builder, 1, nullIndex, visiting, 0, &failure
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

static int luaEncoded(lua_State *L) {
    luaEncode(L);
    pushEncoded(L, ENCODED_VALUE_METATABLE, -1);
    return 1;
}

static int luaEncodedString(lua_State *L) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    pushRegistered(L, &ENCODED_STRING_INTERN_KEY);
    const int intern = lua_gettop(L);
    lua_pushvalue(L, 1);
    lua_rawget(L, intern);
    if (!lua_isnil(L, -1)) {
        return 1;
    }
    lua_pop(L, 1);

    if (!simdjson::validate_utf8(source, length)) {
        return luaL_error(L, "simdjson encoded string: invalid UTF-8");
    }
    const char *failure = nullptr;
    try {
        simdjson::builder::string_builder builder;
        builder.escape_and_append_with_quotes(std::string_view(source, length));
        std::string_view output;
        const auto error = builder.view().get(output);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            lua_pushlstring(L, output.data(), output.size());
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return luaL_error(L, "simdjson encoded string: %s", failure);
    }
    pushEncoded(L, ENCODED_STRING_METATABLE, -1);
    lua_pushvalue(L, 1);
    lua_pushvalue(L, -2);
    lua_rawset(L, intern);
    return 1;
}

static int pushVerified(lua_State *L, bool requireString) {
    size_t length = 0;
    const char *source = luaL_checklstring(L, 1, &length);
    const char *failure = nullptr;
    bool isString = false;
    try {
        static thread_local simdjson::dom::parser parser;
        simdjson::dom::element document;
        const auto error = parser.parse(source, length, true).get(document);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            isString = document.type() == simdjson::dom::element_type::STRING;
            if (requireString && !isString) {
                failure = "a JSON string is required";
            }
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure) {
        return luaL_error(L, "simdjson verify: %s", failure);
    }
    pushEncoded(
        L,
        requireString ? ENCODED_STRING_METATABLE : ENCODED_VALUE_METATABLE,
        1
    );
    return 1;
}

static int luaVerified(lua_State *L) {
    return pushVerified(L, false);
}

static int luaVerifiedString(lua_State *L) {
    luaL_checkstring(L, 1);
    pushRegistered(L, &VERIFIED_STRING_INTERN_KEY);
    const int intern = lua_gettop(L);
    lua_pushvalue(L, 1);
    lua_rawget(L, intern);
    if (!lua_isnil(L, -1)) {
        return 1;
    }
    lua_pop(L, 1);
    pushVerified(L, true);
    lua_pushvalue(L, 1);
    lua_pushvalue(L, -2);
    lua_rawset(L, intern);
    return 1;
}

static int luaNewWriter(lua_State *L) {
    if (!hasRegisteredMetatable(L, 1, &BUFFER_METATABLE_KEY)) {
        return luaL_argerror(L, 1, "string.buffer.Buffer expected");
    }
    void *storage = lua_newuserdata(L, sizeof(luaWriter));
    auto *writer = new (storage) luaWriter{};
    try {
        writer->backing = acquireWriterBacking();
    } catch (const std::bad_alloc &) {
        writer->~luaWriter();
        return luaL_error(L, "simdjson writer: allocation failed");
    }
    luaL_getmetatable(L, WRITER_METATABLE);
    lua_setmetatable(L, -2);
    lua_createtable(L, 0, 2);
    lua_pushvalue(L, 1);
    lua_setfield(L, -2, "out");
    if (lua_gettop(L) >= 4 && !lua_isnil(L, 2)) {
        lua_pushvalue(L, 2);
    } else {
        pushRegistered(L, &NULL_KEY);
    }
    lua_setfield(L, -2, "null");
    lua_setfenv(L, -2);
    return 1;
}

static void setFunction(lua_State *L, const char *name, lua_CFunction function) {
    lua_pushcfunction(L, function);
    lua_setfield(L, -2, name);
}

static void installMarker(
    lua_State *L,
    int moduleIndex,
    void *key,
    const char *field
) {
    moduleIndex = absoluteIndex(L, moduleIndex);
    pushRegistered(L, key);
    if (!lua_isnil(L, -1)) {
        lua_setfield(L, moduleIndex, field);
        return;
    }
    lua_pop(L, 1);
    lua_createtable(L, 0, 0);
    lua_pushlightuserdata(L, key);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_setfield(L, moduleIndex, field);
}

static void installBufferMetatable(lua_State *L) {
    pushRegistered(L, &BUFFER_METATABLE_KEY);
    if (!lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return;
    }
    lua_pop(L, 1);

    lua_getglobal(L, "require");
    lua_pushliteral(L, "string.buffer");
    lua_call(L, 1, 1);
    lua_getfield(L, -1, "new");
    lua_call(L, 0, 1);
    if (!lua_getmetatable(L, -1)) {
        luaL_error(L, "string.buffer.new() returned a value without a metatable");
    }
    lua_pushlightuserdata(L, &BUFFER_METATABLE_KEY);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_pop(L, 3);
}

} // namespace

extern "C" nuppSimdjsonParser *nuppSimdjsonNew(void) {
    return new (std::nothrow) nuppSimdjsonParser();
}

extern "C" void nuppSimdjsonFree(nuppSimdjsonParser *parser) {
    delete parser;
}

extern "C" int nuppSimdjsonPrepare(
    nuppSimdjsonParser *parser,
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

extern "C" int nuppSimdjsonStage1(nuppSimdjsonParser *parser) {
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

extern "C" int nuppSimdjsonDom(nuppSimdjsonParser *parser) {
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

extern "C" const char *nuppSimdjsonError(int code) {
    if (code == -1) {
        return "bridge allocation or argument failure";
    }
    return simdjson::error_message(static_cast<simdjson::error_code>(code));
}

extern "C" const char *nuppSimdjsonVersion(void) {
    return SIMDJSON_VERSION;
}

extern "C" const char *nuppSimdjsonImplementation(void) {
    static std::string implementation;
    implementation = simdjson::get_active_implementation()->name();
    return implementation.c_str();
}

extern "C" NUPP_SIMDJSON_EXPORT int luaopen_simdjson_bench_native(lua_State *L) {
    installBufferMetatable(L);
    luaL_newmetatable(L, ENCODED_VALUE_METATABLE);
    lua_pushliteral(L, "simdjson encoded value");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);
    luaL_newmetatable(L, ENCODED_STRING_METATABLE);
    lua_pushliteral(L, "simdjson encoded string");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);
    lua_createtable(L, 0, 0);
    lua_pushlightuserdata(L, &ENCODED_STRING_INTERN_KEY);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);
    lua_createtable(L, 0, 0);
    lua_pushlightuserdata(L, &VERIFIED_STRING_INTERN_KEY);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);
    luaL_newmetatable(L, WRITER_METATABLE);
    setFunction(L, "__gc", luaWriterGc);
    setFunction(L, "startArray", luaWriterStartArray);
    setFunction(L, "startObject", luaWriterStartObject);
    setFunction(L, "key", luaWriterKey);
    setFunction(L, "write", luaWriterWrite);
    setFunction(L, "null", luaWriterNull);
    setFunction(L, "endArray", luaWriterEndArray);
    setFunction(L, "endObject", luaWriterEndObject);
    setFunction(L, "flush", luaWriterFlush);
    setFunction(L, "close", luaWriterClose);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pushliteral(L, "simdjson writer");
    lua_setfield(L, -2, "__metatable");
    lua_pop(L, 1);

    lua_createtable(L, 0, 15);
    const int moduleIndex = lua_gettop(L);
    setFunction(L, "decode", luaDecode);
    setFunction(L, "pull", luaPull);
    setFunction(L, "arrayOf", luaArrayOf);
    setFunction(L, "asArray", luaAsArray);
    setFunction(L, "asObject", luaAsObject);
    setFunction(L, "encode", luaEncode);
    setFunction(L, "serialize", luaEncode);
    setFunction(L, "encoded", luaEncoded);
    setFunction(L, "encodedString", luaEncodedString);
    setFunction(L, "verified", luaVerified);
    setFunction(L, "verifiedString", luaVerifiedString);
    setFunction(L, "writer", luaNewWriter);
    installMarker(L, moduleIndex, &NULL_KEY, "NULL");
    installMarker(L, moduleIndex, &EMPTY_ARRAY_KEY, "EMPTY_ARRAY");
    installMarker(L, moduleIndex, &EMPTY_OBJECT_KEY, "EMPTY_OBJECT");
    return 1;
}

extern "C" NUPP_SIMDJSON_EXPORT int luaopen_jsonNative(lua_State *L) {
    return luaopen_simdjson_bench_native(L);
}
