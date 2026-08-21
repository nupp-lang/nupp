#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}
#include <simdjson.h>

namespace {

constexpr const char *SERDE_SCHEMA_METATABLE = "nupp.json.serde-schema";

enum class serdeKind : uint8_t { STRING, INTEGER, NUMBER, BOOLEAN };

struct serdeField {
    std::string logical;
    std::string wire;
    std::string encodedKey;
    uint64_t hash{0};
    serdeKind kind{serdeKind::STRING};
    bool required{false};
    bool hasMinimum{false};
    bool hasMaximum{false};
    int64_t minimum{0};
    int64_t maximum{0};
};

struct serdeSchema {
    std::vector<serdeField> fields;
    std::vector<std::vector<uint32_t>> buckets;
    bool rejectUnknown{true};
};

uint64_t serdeHash(std::string_view value) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const unsigned char byte : value) {
        hash ^= byte;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

serdeSchema *checkSerdeSchema(lua_State *state, int index) {
    return static_cast<serdeSchema *>(luaL_checkudata(state, index, SERDE_SCHEMA_METATABLE));
}

serdeKind checkSerdeKind(lua_State *state, int index) {
    const char *kind = luaL_checkstring(state, index);
    if (std::strcmp(kind, "string") == 0) return serdeKind::STRING;
    if (std::strcmp(kind, "integer") == 0) return serdeKind::INTEGER;
    if (std::strcmp(kind, "number") == 0) return serdeKind::NUMBER;
    if (std::strcmp(kind, "boolean") == 0) return serdeKind::BOOLEAN;
    luaL_error(state, "unsupported prepared JSON kind: %s", kind);
    return serdeKind::STRING;
}

std::string serdeEncodeKey(std::string_view wire) {
    simdjson::builder::string_builder builder;
    builder.escape_and_append_with_quotes(wire);
    builder.append_colon();
    std::string_view encoded;
    if (builder.view().get(encoded)) throw std::bad_alloc();
    return std::string(encoded);
}

int compileSerde(lua_State *state) {
    luaL_checktype(state, 1, LUA_TTABLE);
    const size_t count = lua_objlen(state, 1);
    void *storage = lua_newuserdata(state, sizeof(serdeSchema));
    auto *schema = new (storage) serdeSchema();
    try {
        schema->fields.reserve(count);
        for (size_t index = 1; index <= count; ++index) {
            lua_rawgeti(state, 1, static_cast<int>(index));
            luaL_checktype(state, -1, LUA_TTABLE);
            const int fieldIndex = lua_gettop(state);
            lua_getfield(state, fieldIndex, "name");
            size_t logicalLength = 0;
            const char *logical = luaL_checklstring(state, -1, &logicalLength);
            lua_getfield(state, fieldIndex, "wire");
            size_t wireLength = 0;
            const char *wire = luaL_checklstring(state, -1, &wireLength);
            lua_getfield(state, fieldIndex, "kind");
            const serdeKind kind = checkSerdeKind(state, -1);
            lua_getfield(state, fieldIndex, "required");
            const bool required = lua_toboolean(state, -1) != 0;
            lua_getfield(state, fieldIndex, "minimum");
            const bool hasMinimum = !lua_isnil(state, -1);
            const int64_t minimum = hasMinimum
                ? static_cast<int64_t>(luaL_checknumber(state, -1)) : 0;
            lua_getfield(state, fieldIndex, "maximum");
            const bool hasMaximum = !lua_isnil(state, -1);
            const int64_t maximum = hasMaximum
                ? static_cast<int64_t>(luaL_checknumber(state, -1)) : 0;
            if (!simdjson::validate_utf8(wire, wireLength)) {
                schema->~serdeSchema();
                return luaL_error(state, "prepared JSON member name is not UTF-8");
            }
            serdeField field;
            field.logical.assign(logical, logicalLength);
            field.wire.assign(wire, wireLength);
            field.encodedKey = serdeEncodeKey(field.wire);
            field.hash = serdeHash(field.wire);
            field.kind = kind;
            field.required = required;
            field.hasMinimum = hasMinimum;
            field.hasMaximum = hasMaximum;
            field.minimum = minimum;
            field.maximum = maximum;
            schema->fields.push_back(std::move(field));
            lua_settop(state, fieldIndex - 1);
        }
        size_t bucketCount = 1;
        while (bucketCount < count * 2) bucketCount <<= 1;
        schema->buckets.resize(bucketCount);
        for (size_t index = 0; index < schema->fields.size(); ++index) {
            schema->buckets[schema->fields[index].hash & (bucketCount - 1)]
                .push_back(static_cast<uint32_t>(index));
        }
        const char *unknown = luaL_optstring(state, 2, "reject");
        schema->rejectUnknown = std::strcmp(unknown, "ignore") != 0;
    } catch (const std::bad_alloc &) {
        schema->~serdeSchema();
        return luaL_error(state, "prepared JSON schema allocation failed");
    }
    luaL_getmetatable(state, SERDE_SCHEMA_METATABLE);
    lua_setmetatable(state, -2);
    return 1;
}

int collectSerde(lua_State *state) {
    checkSerdeSchema(state, 1)->~serdeSchema();
    return 0;
}

void appendSerdeValue(
    lua_State *state,
    simdjson::builder::string_builder &builder,
    const serdeField &field,
    int index
) {
    switch (field.kind) {
        case serdeKind::STRING: {
            size_t length = 0;
            const char *value = luaL_checklstring(state, index, &length);
            if (!simdjson::validate_utf8(value, length)) {
                luaL_error(state, "member %s is not UTF-8", field.logical.c_str());
            }
            builder.escape_and_append_with_quotes(std::string_view(value, length));
            return;
        }
        case serdeKind::INTEGER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value) || std::floor(value) != value) {
                luaL_error(state, "member %s is not an integer", field.logical.c_str());
            }
            if ((field.hasMinimum && value < static_cast<lua_Number>(field.minimum))
                || (field.hasMaximum && value > static_cast<lua_Number>(field.maximum))) {
                luaL_error(state, "member %s is outside its integer range", field.logical.c_str());
            }
            builder.append(static_cast<int64_t>(value));
            return;
        }
        case serdeKind::NUMBER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value)) {
                luaL_error(state, "member %s is not finite", field.logical.c_str());
            }
            builder.append(static_cast<double>(value));
            return;
        }
        case serdeKind::BOOLEAN:
            luaL_checktype(state, index, LUA_TBOOLEAN);
            builder.append(lua_toboolean(state, index) != 0);
            return;
    }
}

static thread_local simdjson::builder::string_builder serdeBuilder;

char *serdeDestination(lua_State *state, int index) {
    const void *storage = lua_topointer(state, index);
    if (storage == nullptr) {
        luaL_error(state, "prepared JSON destination is not a byte pointer");
    }
    return *static_cast<char *const *>(storage);
}

size_t serdeCapacity(lua_State *state, int index) {
    const lua_Number value = luaL_checknumber(state, index);
    if (!std::isfinite(value) || value < 0
        || value > static_cast<lua_Number>(SIZE_MAX)) {
        luaL_error(state, "prepared JSON destination capacity is invalid");
    }
    return static_cast<size_t>(value);
}

int encodeSerde(lua_State *state, bool slots, bool into) {
    auto *schema = checkSerdeSchema(state, 1);
    try {
        // A worker thread reuses its encoder allocation across complete roots. The
        // public Prepared value is immutable; this is operation scratch and is
        // cleared before every traversal, including after a prior Lua error longjmp.
        serdeBuilder.clear();
        serdeBuilder.start_object();
        size_t emitted = 0;
        for (size_t index = 0; index < schema->fields.size(); ++index) {
            const auto &field = schema->fields[index];
            if (slots) {
                lua_rawgeti(state, 2, static_cast<int>(index + 1));
            } else {
                lua_getfield(state, 2, field.logical.c_str());
            }
            if (lua_isnil(state, -1)) {
                lua_pop(state, 1);
                if (field.required) {
                    return luaL_error(state, "missing required member %s", field.logical.c_str());
                }
                continue;
            }
            if (emitted++ != 0) serdeBuilder.append_comma();
            serdeBuilder.append_raw(field.encodedKey);
            appendSerdeValue(state, serdeBuilder, field, -1);
            lua_pop(state, 1);
        }
        serdeBuilder.end_object();
        std::string_view output;
        const auto error = serdeBuilder.view().get(output);
        if (error) return luaL_error(state, "prepared JSON encode failed: %s", simdjson::error_message(error));
        if (into) {
            const size_t capacity = serdeCapacity(state, 4);
            if (output.size() <= capacity && !output.empty()) {
                std::memcpy(serdeDestination(state, 3), output.data(), output.size());
            }
            lua_pushnumber(state, static_cast<lua_Number>(output.size()));
            return 1;
        }
        lua_pushlstring(state, output.data(), output.size());
        return 1;
    } catch (const std::bad_alloc &) {
        return luaL_error(state, "prepared JSON encode allocation failed");
    }
}

int encodeSerdeRecord(lua_State *state) { return encodeSerde(state, false, false); }
int encodeSerdeSlots(lua_State *state) { return encodeSerde(state, true, false); }
int encodeSerdeRecordInto(lua_State *state) { return encodeSerde(state, false, true); }
int encodeSerdeSlotsInto(lua_State *state) { return encodeSerde(state, true, true); }

int copySerdeEncoding(lua_State *state) {
    std::string_view output;
    const auto error = serdeBuilder.view().get(output);
    if (error) {
        return luaL_error(
            state, "prepared JSON buffered copy failed: %s",
            simdjson::error_message(error)
        );
    }
    const size_t capacity = serdeCapacity(state, 2);
    if (output.size() > capacity) {
        return luaL_error(state, "prepared JSON destination is too small");
    }
    if (!output.empty()) {
        std::memcpy(serdeDestination(state, 1), output.data(), output.size());
    }
    return 0;
}

bool consumeSerdeValue(simdjson::ondemand::value &value, const char **failure) {
    simdjson::ondemand::json_type type;
    auto error = value.type().get(type);
    if (error) { *failure = simdjson::error_message(error); return false; }
    if (type == simdjson::ondemand::json_type::array) {
        simdjson::ondemand::array array;
        error = value.get_array().get(array);
        if (error) { *failure = simdjson::error_message(error); return false; }
        for (auto result : array) {
            simdjson::ondemand::value child;
            error = result.get(child);
            if (error || !consumeSerdeValue(child, failure)) {
                if (error) *failure = simdjson::error_message(error);
                return false;
            }
        }
        return true;
    }
    if (type == simdjson::ondemand::json_type::object) {
        simdjson::ondemand::object object;
        error = value.get_object().get(object);
        if (error) { *failure = simdjson::error_message(error); return false; }
        for (auto result : object) {
            simdjson::ondemand::field field;
            error = std::move(result).get(field);
            if (error) { *failure = simdjson::error_message(error); return false; }
            std::string_view ignored;
            error = field.unescaped_key().get(ignored);
            if (error) { *failure = simdjson::error_message(error); return false; }
            auto &child = field.value();
            if (!consumeSerdeValue(child, failure)) return false;
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
    } else {
        bool ignored = false;
        error = value.is_null().get(ignored);
    }
    if (error) { *failure = simdjson::error_message(error); return false; }
    return true;
}

const serdeField *findSerdeField(serdeSchema *schema, std::string_view key, size_t *expected) {
    if (*expected < schema->fields.size()) {
        const auto &candidate = schema->fields[*expected];
        if (candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            ++*expected;
            return &candidate;
        }
    }
    const uint64_t hash = serdeHash(key);
    const auto &bucket = schema->buckets[hash & (schema->buckets.size() - 1)];
    for (const uint32_t index : bucket) {
        const auto &candidate = schema->fields[index];
        if (candidate.hash == hash && candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            *expected = static_cast<size_t>(index) + 1;
            return &candidate;
        }
    }
    return nullptr;
}

bool pushSerdeValue(
    lua_State *state,
    simdjson::ondemand::value &value,
    const serdeField &field,
    const char **failure
) {
    simdjson::error_code error;
    switch (field.kind) {
        case serdeKind::STRING: {
            std::string_view result;
            error = value.get_string().get(result);
            if (!error) lua_pushlstring(state, result.data(), result.size());
            break;
        }
        case serdeKind::INTEGER: {
            int64_t result = 0;
            error = value.get_int64().get(result);
            if (!error && ((field.hasMinimum && result < field.minimum)
                || (field.hasMaximum && result > field.maximum))) {
                *failure = "integer outside schema range";
                return false;
            }
            if (!error) lua_pushnumber(state, static_cast<lua_Number>(result));
            break;
        }
        case serdeKind::NUMBER: {
            double result = 0;
            error = value.get_double().get(result);
            if (!error) lua_pushnumber(state, result);
            break;
        }
        case serdeKind::BOOLEAN: {
            bool result = false;
            error = value.get_bool().get(result);
            if (!error) lua_pushboolean(state, result ? 1 : 0);
            break;
        }
    }
    if (error) { *failure = simdjson::error_message(error); return false; }
    return true;
}

int decodeSerde(lua_State *state, bool slots) {
    auto *schema = checkSerdeSchema(state, 1);
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
        if (error) failure = simdjson::error_message(error);
        else {
            simdjson::ondemand::object object;
            error = document.get_object().get(object);
            if (error) failure = simdjson::error_message(error);
            else {
                if (slots) {
                    lua_createtable(state, static_cast<int>(schema->fields.size()), 0);
                } else if (lua_istable(state, 3)) {
                    lua_createtable(state, 0, static_cast<int>(schema->fields.size()));
                    lua_pushvalue(state, 3);
                    lua_setmetatable(state, -2);
                } else {
                    lua_pushvalue(state, 3);
                    lua_call(state, 0, 1);
                }
                const int output = lua_gettop(state);
                std::vector<bool> seen(schema->fields.size(), false);
                size_t expected = 0;
                for (auto result : object) {
                    simdjson::ondemand::field input;
                    error = std::move(result).get(input);
                    if (error) { failure = simdjson::error_message(error); break; }
                    std::string_view key;
                    error = input.unescaped_key().get(key);
                    if (error) { failure = simdjson::error_message(error); break; }
                    const serdeField *field = findSerdeField(schema, key, &expected);
                    auto &inputValue = input.value();
                    if (field == nullptr) {
                        if (schema->rejectUnknown) {
                            lua_pushlstring(state, key.data(), key.size());
                            failure = lua_tostring(state, -1);
                            break;
                        }
                        if (!consumeSerdeValue(inputValue, &failure)) break;
                        continue;
                    }
                    const size_t index = static_cast<size_t>(field - schema->fields.data());
                    if (seen[index]) { failure = "duplicate member"; break; }
                    if (!pushSerdeValue(state, inputValue, *field, &failure)) break;
                    seen[index] = true;
                    if (slots) lua_rawseti(state, output, static_cast<int>(index + 1));
                    else lua_setfield(state, output, field->logical.c_str());
                }
                if (failure == nullptr) {
                    for (size_t index = 0; index < schema->fields.size(); ++index) {
                        if (schema->fields[index].required && !seen[index]) {
                            failure = schema->fields[index].logical.c_str();
                            break;
                        }
                    }
                }
            }
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) {
        const std::string message(failure);
        lua_settop(state, base);
        return luaL_error(state, "prepared JSON decode failed near %s", message.c_str());
    }
    return 1;
}

int decodeSerdeRecord(lua_State *state) { return decodeSerde(state, false); }
int decodeSerdeSlots(lua_State *state) { return decodeSerde(state, true); }

void setSerdeFunction(lua_State *state, int module, const char *name, lua_CFunction function) {
    lua_pushcfunction(state, function);
    lua_setfield(state, module, name);
}

} // namespace

extern "C" void nuppInstallJsonSerde(lua_State *state, int module) {
    luaL_newmetatable(state, SERDE_SCHEMA_METATABLE);
    lua_pushcfunction(state, collectSerde);
    lua_setfield(state, -2, "__gc");
    lua_pushliteral(state, "prepared JSON schema");
    lua_setfield(state, -2, "__metatable");
    lua_pop(state, 1);
    setSerdeFunction(state, module, "compileSerde", compileSerde);
    setSerdeFunction(state, module, "encodeSerdeRecord", encodeSerdeRecord);
    setSerdeFunction(state, module, "encodeSerdeSlots", encodeSerdeSlots);
    setSerdeFunction(state, module, "encodeSerdeRecordInto", encodeSerdeRecordInto);
    setSerdeFunction(state, module, "encodeSerdeSlotsInto", encodeSerdeSlotsInto);
    setSerdeFunction(state, module, "copySerdeEncoding", copySerdeEncoding);
    setSerdeFunction(state, module, "decodeSerdeRecord", decodeSerdeRecord);
    setSerdeFunction(state, module, "decodeSerdeSlots", decodeSerdeSlots);
}
