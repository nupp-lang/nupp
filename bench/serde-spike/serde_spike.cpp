#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <simdjson.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {

constexpr const char *SCHEMA_METATABLE = "nupp.serde_spike.schema";

enum class Kind : uint8_t {
    STRING,
    INTEGER,
    NUMBER,
    BOOLEAN,
};

struct Field {
    std::string logical;
    std::string wire;
    std::string encodedKey;
    uint64_t hash = 0;
    Kind kind = Kind::STRING;
};

struct Schema {
    std::vector<Field> fields;
    std::vector<std::vector<uint32_t>> buckets;
};

uint64_t hashBytes(std::string_view value) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const unsigned char byte : value) {
        hash ^= byte;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

int absoluteIndex(lua_State *state, int index) {
    return index > 0 || index <= LUA_REGISTRYINDEX
        ? index
        : lua_gettop(state) + index + 1;
}

Schema *checkedSchema(lua_State *state, int index) {
    return static_cast<Schema *>(luaL_checkudata(state, index, SCHEMA_METATABLE));
}

Kind parseKind(lua_State *state, int index) {
    const char *kind = luaL_checkstring(state, index);
    if (std::strcmp(kind, "string") == 0) {
        return Kind::STRING;
    }
    if (std::strcmp(kind, "integer") == 0) {
        return Kind::INTEGER;
    }
    if (std::strcmp(kind, "number") == 0) {
        return Kind::NUMBER;
    }
    if (std::strcmp(kind, "boolean") == 0) {
        return Kind::BOOLEAN;
    }
    luaL_error(state, "unknown serde spike kind: %s", kind);
    return Kind::STRING;
}

std::string encodeKey(std::string_view wire) {
    simdjson::builder::string_builder builder;
    builder.escape_and_append_with_quotes(wire);
    builder.append_colon();
    std::string_view encoded;
    const auto error = builder.view().get(encoded);
    if (error) {
        throw std::bad_alloc();
    }
    return std::string(encoded);
}

int compileSchema(lua_State *state) {
    luaL_checktype(state, 1, LUA_TTABLE);
    const size_t count = lua_objlen(state, 1);
    void *storage = lua_newuserdata(state, sizeof(Schema));
    auto *schema = new (storage) Schema();
    try {
        schema->fields.reserve(count);
        for (size_t index = 1; index <= count; ++index) {
            lua_rawgeti(state, 1, static_cast<int>(index));
            luaL_checktype(state, -1, LUA_TTABLE);

            lua_getfield(state, -1, "name");
            size_t logicalLength = 0;
            const char *logical = luaL_checklstring(state, -1, &logicalLength);

            lua_getfield(state, -2, "wire");
            size_t wireLength = 0;
            const char *wire = luaL_checklstring(state, -1, &wireLength);

            lua_getfield(state, -3, "kind");
            const Kind kind = parseKind(state, -1);

            if (!simdjson::validate_utf8(wire, wireLength)) {
                return luaL_error(state, "schema wire name is not UTF-8");
            }

            Field field;
            field.logical.assign(logical, logicalLength);
            field.wire.assign(wire, wireLength);
            field.encodedKey = encodeKey(field.wire);
            field.hash = hashBytes(field.wire);
            field.kind = kind;
            schema->fields.push_back(std::move(field));
            lua_pop(state, 4);
        }

        size_t bucketCount = 1;
        while (bucketCount < count * 2) {
            bucketCount <<= 1;
        }
        schema->buckets.resize(bucketCount);
        for (size_t index = 0; index < schema->fields.size(); ++index) {
            schema->buckets[schema->fields[index].hash & (bucketCount - 1)]
                .push_back(static_cast<uint32_t>(index));
        }
    } catch (const std::bad_alloc &) {
        schema->~Schema();
        return luaL_error(state, "schema allocation failed");
    }

    luaL_getmetatable(state, SCHEMA_METATABLE);
    lua_setmetatable(state, -2);
    return 1;
}

int collectSchema(lua_State *state) {
    checkedSchema(state, 1)->~Schema();
    return 0;
}

void appendValue(
    lua_State *state,
    simdjson::builder::string_builder &builder,
    const Field &field,
    int index
) {
    index = absoluteIndex(state, index);
    switch (field.kind) {
        case Kind::STRING: {
            size_t length = 0;
            const char *value = luaL_checklstring(state, index, &length);
            builder.escape_and_append_with_quotes(std::string_view(value, length));
            return;
        }
        case Kind::INTEGER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value) || std::floor(value) != value) {
                luaL_error(state, "field %s is not an integer", field.logical.c_str());
            }
            builder.append(static_cast<int64_t>(value));
            return;
        }
        case Kind::NUMBER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value)) {
                luaL_error(state, "field %s is not finite", field.logical.c_str());
            }
            builder.append(static_cast<double>(value));
            return;
        }
        case Kind::BOOLEAN:
            luaL_checktype(state, index, LUA_TBOOLEAN);
            builder.append(lua_toboolean(state, index) != 0);
            return;
    }
}

int encode(lua_State *state, bool slots) {
    Schema *schema = checkedSchema(state, 1);
    luaL_checktype(state, 2, LUA_TTABLE);
    try {
        simdjson::builder::string_builder builder;
        builder.start_object();
        for (size_t index = 0; index < schema->fields.size(); ++index) {
            const auto &field = schema->fields[index];
            if (index != 0) {
                builder.append_comma();
            }
            builder.append_raw(field.encodedKey);
            if (slots) {
                lua_rawgeti(state, 2, static_cast<int>(index + 1));
            } else {
                lua_pushlstring(state, field.logical.data(), field.logical.size());
                lua_rawget(state, 2);
            }
            appendValue(state, builder, field, -1);
            lua_pop(state, 1);
        }
        builder.end_object();
        std::string_view output;
        const auto error = builder.view().get(output);
        if (error) {
            return luaL_error(state, "schema encode failed: %s", simdjson::error_message(error));
        }
        lua_pushlstring(state, output.data(), output.size());
        return 1;
    } catch (const std::bad_alloc &) {
        return luaL_error(state, "schema encode allocation failed");
    }
}

int encodeRecord(lua_State *state) {
    return encode(state, false);
}

int encodeSlots(lua_State *state) {
    return encode(state, true);
}

bool consume(simdjson::ondemand::value &value, const char **failure) {
    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) {
        *failure = simdjson::error_message(error);
        return false;
    }
    if (type == simdjson::ondemand::json_type::array) {
        simdjson::ondemand::array array;
        error = value.get_array().get(array);
        if (error) {
            *failure = simdjson::error_message(error);
            return false;
        }
        for (auto childResult : array) {
            simdjson::ondemand::value child;
            error = childResult.get(child);
            if (error || !consume(child, failure)) {
                if (error) {
                    *failure = simdjson::error_message(error);
                }
                return false;
            }
        }
        return true;
    }
    if (type == simdjson::ondemand::json_type::object) {
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
            std::string_view ignored;
            error = field.unescaped_key().get(ignored);
            if (error) {
                *failure = simdjson::error_message(error);
                return false;
            }
            auto &child = field.value();
            if (!consume(child, failure)) {
                return false;
            }
        }
        return true;
    }
    if (type == simdjson::ondemand::json_type::string) {
        std::string_view ignored;
        error = value.get_string().get(ignored);
    } else if (type == simdjson::ondemand::json_type::number) {
        double ignored = 0;
        error = value.get_double().get(ignored);
    } else if (type == simdjson::ondemand::json_type::boolean) {
        bool ignored = false;
        error = value.get_bool().get(ignored);
    } else if (type == simdjson::ondemand::json_type::null) {
        bool ignored = false;
        error = value.is_null().get(ignored);
    } else {
        *failure = "unknown value type";
        return false;
    }
    if (error) {
        *failure = simdjson::error_message(error);
        return false;
    }
    return true;
}

const Field *findField(Schema *schema, std::string_view key, size_t *expected) {
    if (*expected < schema->fields.size()) {
        const Field &candidate = schema->fields[*expected];
        if (candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            ++*expected;
            return &candidate;
        }
    }
    const uint64_t hash = hashBytes(key);
    const auto &bucket = schema->buckets[hash & (schema->buckets.size() - 1)];
    for (const uint32_t index : bucket) {
        const Field &candidate = schema->fields[index];
        if (candidate.hash == hash && candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            *expected = static_cast<size_t>(index) + 1;
            return &candidate;
        }
    }
    return nullptr;
}

bool pushValue(
    lua_State *state,
    simdjson::ondemand::value &value,
    const Field &field,
    const char **failure
) {
    simdjson::error_code error;
    switch (field.kind) {
        case Kind::STRING: {
            std::string_view result;
            error = value.get_string().get(result);
            if (!error) {
                lua_pushlstring(state, result.data(), result.size());
            }
            break;
        }
        case Kind::INTEGER: {
            int64_t result = 0;
            error = value.get_int64().get(result);
            if (!error) {
                lua_pushnumber(state, static_cast<lua_Number>(result));
            }
            break;
        }
        case Kind::NUMBER: {
            double result = 0;
            error = value.get_double().get(result);
            if (!error) {
                lua_pushnumber(state, result);
            }
            break;
        }
        case Kind::BOOLEAN: {
            bool result = false;
            error = value.get_bool().get(result);
            if (!error) {
                lua_pushboolean(state, result ? 1 : 0);
            }
            break;
        }
    }
    if (error) {
        *failure = simdjson::error_message(error);
        return false;
    }
    return true;
}

int decode(lua_State *state, bool slots) {
    Schema *schema = checkedSchema(state, 1);
    size_t length = 0;
    const char *source = luaL_checklstring(state, 2, &length);
    const int base = lua_gettop(state);
    const char *failure = nullptr;
    try {
        static thread_local std::vector<char> padded;
        static thread_local simdjson::ondemand::parser parser;
        padded.resize(length + simdjson::SIMDJSON_PADDING);
        std::memcpy(padded.data(), source, length);
        std::memset(padded.data() + length, 0, simdjson::SIMDJSON_PADDING);

        simdjson::ondemand::document document;
        auto error = parser.iterate(padded.data(), length, padded.size()).get(document);
        if (error) {
            failure = simdjson::error_message(error);
        } else {
            simdjson::ondemand::object object;
            error = document.get_object().get(object);
            if (error) {
                failure = simdjson::error_message(error);
            } else {
                lua_createtable(
                    state,
                    slots ? static_cast<int>(schema->fields.size()) : 0,
                    slots ? 0 : static_cast<int>(schema->fields.size())
                );
                const int output = lua_gettop(state);
                size_t expected = 0;
                for (auto fieldResult : object) {
                    simdjson::ondemand::field inputField;
                    error = std::move(fieldResult).get(inputField);
                    if (error) {
                        failure = simdjson::error_message(error);
                        break;
                    }
                    std::string_view key;
                    error = inputField.unescaped_key().get(key);
                    if (error) {
                        failure = simdjson::error_message(error);
                        break;
                    }
                    const Field *field = findField(schema, key, &expected);
                    auto &inputValue = inputField.value();
                    if (field == nullptr) {
                        if (!consume(inputValue, &failure)) {
                            break;
                        }
                        continue;
                    }
                    if (!pushValue(state, inputValue, *field, &failure)) {
                        break;
                    }
                    const size_t index = static_cast<size_t>(field - schema->fields.data());
                    if (slots) {
                        lua_rawseti(state, output, static_cast<int>(index + 1));
                    } else {
                        lua_pushlstring(state, field->logical.data(), field->logical.size());
                        lua_insert(state, -2);
                        lua_rawset(state, output);
                    }
                }
                if (failure == nullptr && !slots && lua_gettop(state) >= 3
                    && !lua_isnil(state, 3)) {
                    lua_pushvalue(state, 3);
                    lua_setmetatable(state, output);
                }
            }
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) {
        lua_settop(state, base);
        return luaL_error(state, "schema decode failed: %s", failure);
    }
    return 1;
}

int decodeRecord(lua_State *state) {
    return decode(state, false);
}

int decodeSlots(lua_State *state) {
    return decode(state, true);
}

const luaL_Reg FUNCTIONS[] = {
    {"compile", compileSchema},
    {"encodeRecord", encodeRecord},
    {"encodeSlots", encodeSlots},
    {"decodeRecord", decodeRecord},
    {"decodeSlots", decodeSlots},
    {nullptr, nullptr},
};

} // namespace

extern "C" int luaopen_serde_spike_native(lua_State *state) {
    luaL_newmetatable(state, SCHEMA_METATABLE);
    lua_pushcfunction(state, collectSchema);
    lua_setfield(state, -2, "__gc");
    lua_pop(state, 1);
    luaL_register(state, "serde_spike_native", FUNCTIONS);
    return 1;
}

