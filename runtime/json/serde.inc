namespace {

constexpr const char *SERDE_SCHEMA_METATABLE = "nupp.json.serde-schema";

enum class serdeKind : uint8_t {
    BOOLEAN,
    INTEGER,
    NUMBER,
    STRING,
    OPTIONAL,
    LIST,
    MAP,
    STRUCTURE,
    DOCUMENT,
};

enum class serdeAccess : uint8_t { NONE, RECORD, STRUCT, DYNAMIC };

struct serdeField {
    std::string logical;
    std::string wire;
    std::string encodedKey;
    uint64_t hash{0};
    uint32_t target{0};
    bool required{false};
    int defaultRef{0};
};

struct serdeNode {
    serdeKind kind{serdeKind::STRING};
    serdeAccess access{serdeAccess::NONE};
    std::vector<serdeField> fields;
    std::vector<std::vector<uint32_t>> buckets;
    uint32_t element{0};
    bool hasMinimum{false};
    bool hasMaximum{false};
    int64_t minimum{0};
    int64_t maximum{0};
    int literalRef{0};
    int typeRef{0};
};

struct serdeSchema {
    std::vector<serdeNode> nodes;
    uint32_t root{0};
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
    if (std::strcmp(kind, "integer") == 0
        || std::strcmp(kind, "unsigned") == 0) return serdeKind::INTEGER;
    if (std::strcmp(kind, "number") == 0) return serdeKind::NUMBER;
    if (std::strcmp(kind, "boolean") == 0) return serdeKind::BOOLEAN;
    if (std::strcmp(kind, "optional") == 0) return serdeKind::OPTIONAL;
    if (std::strcmp(kind, "list") == 0) return serdeKind::LIST;
    if (std::strcmp(kind, "map") == 0) return serdeKind::MAP;
    if (std::strcmp(kind, "structure") == 0) return serdeKind::STRUCTURE;
    if (std::strcmp(kind, "document") == 0) return serdeKind::DOCUMENT;
    luaL_error(state, "unsupported prepared JSON kind: %s", kind);
    return serdeKind::STRING;
}

serdeAccess checkSerdeAccess(lua_State *state, int index) {
    const char *access = luaL_checkstring(state, index);
    if (std::strcmp(access, "record") == 0) return serdeAccess::RECORD;
    if (std::strcmp(access, "struct") == 0) return serdeAccess::STRUCT;
    if (std::strcmp(access, "dynamic") == 0) return serdeAccess::DYNAMIC;
    luaL_error(state, "unsupported prepared JSON access: %s", access);
    return serdeAccess::NONE;
}

std::string serdeEncodeKey(std::string_view wire) {
    simdjson::builder::string_builder builder;
    builder.escape_and_append_with_quotes(wire);
    builder.append_colon();
    std::string_view encoded;
    if (builder.view().get(encoded)) throw std::bad_alloc();
    return std::string(encoded);
}

int holdSerdeValue(lua_State *state, int holders, int value) {
    value = value < 0 ? lua_gettop(state) + value + 1 : value;
    const int next = static_cast<int>(lua_objlen(state, holders) + 1);
    lua_pushvalue(state, value);
    lua_rawseti(state, holders, next);
    return next;
}

uint32_t compileSerdeNode(
    lua_State *state,
    serdeSchema *schema,
    int source,
    int holders,
    std::unordered_map<const void *, uint32_t> &seen
) {
    source = source < 0 ? lua_gettop(state) + source + 1 : source;
    const void *identity = lua_topointer(state, source);
    const auto prior = seen.find(identity);
    if (prior != seen.end()) return prior->second;
    const uint32_t id = static_cast<uint32_t>(schema->nodes.size());
    schema->nodes.emplace_back();
    seen.emplace(identity, id);

    serdeNode node;
    lua_getfield(state, source, "kind");
    node.kind = checkSerdeKind(state, -1);
    lua_pop(state, 1);
    lua_getfield(state, source, "minimum");
    node.hasMinimum = !lua_isnil(state, -1);
    if (node.hasMinimum) node.minimum = static_cast<int64_t>(luaL_checknumber(state, -1));
    lua_pop(state, 1);
    lua_getfield(state, source, "maximum");
    node.hasMaximum = !lua_isnil(state, -1);
    if (node.hasMaximum) node.maximum = static_cast<int64_t>(luaL_checknumber(state, -1));
    lua_pop(state, 1);
    lua_getfield(state, source, "hasLiteral");
    const bool hasLiteral = lua_toboolean(state, -1) != 0;
    lua_pop(state, 1);
    if (hasLiteral) {
        lua_getfield(state, source, "literalValue");
        node.literalRef = holdSerdeValue(state, holders, -1);
        lua_pop(state, 1);
    }

    if (node.kind == serdeKind::OPTIONAL || node.kind == serdeKind::LIST) {
        lua_getfield(state, source, "element");
        luaL_checktype(state, -1, LUA_TTABLE);
        node.element = compileSerdeNode(state, schema, -1, holders, seen);
        lua_pop(state, 1);
    } else if (node.kind == serdeKind::MAP) {
        lua_getfield(state, source, "value");
        luaL_checktype(state, -1, LUA_TTABLE);
        node.element = compileSerdeNode(state, schema, -1, holders, seen);
        lua_pop(state, 1);
    } else if (node.kind == serdeKind::STRUCTURE) {
        lua_getfield(state, source, "access");
        node.access = checkSerdeAccess(state, -1);
        lua_pop(state, 1);
        if (node.access != serdeAccess::DYNAMIC) {
            lua_getfield(state, source, "typeObject");
            node.typeRef = holdSerdeValue(state, holders, -1);
            lua_pop(state, 1);
        }
        lua_getfield(state, source, "fields");
        luaL_checktype(state, -1, LUA_TTABLE);
        const int fields = lua_gettop(state);
        const size_t count = lua_objlen(state, fields);
        node.fields.reserve(count);
        for (size_t index = 1; index <= count; ++index) {
            lua_rawgeti(state, fields, static_cast<int>(index));
            const int fieldIndex = lua_gettop(state);
            serdeField field;
            lua_getfield(state, fieldIndex, "name");
            size_t logicalLength = 0;
            const char *logical = luaL_checklstring(state, -1, &logicalLength);
            field.logical.assign(logical, logicalLength);
            lua_pop(state, 1);
            lua_getfield(state, fieldIndex, "wire");
            size_t wireLength = 0;
            const char *wire = luaL_checklstring(state, -1, &wireLength);
            if (!simdjson::validate_utf8(wire, wireLength)) {
                luaL_error(state, "prepared JSON member name is not UTF-8");
            }
            field.wire.assign(wire, wireLength);
            field.encodedKey = serdeEncodeKey(field.wire);
            field.hash = serdeHash(field.wire);
            lua_pop(state, 1);
            lua_getfield(state, fieldIndex, "required");
            field.required = lua_toboolean(state, -1) != 0;
            lua_pop(state, 1);
            lua_getfield(state, fieldIndex, "hasDefault");
            const bool hasDefault = lua_toboolean(state, -1) != 0;
            lua_pop(state, 1);
            if (hasDefault) {
                lua_getfield(state, fieldIndex, "defaultValue");
                field.defaultRef = holdSerdeValue(state, holders, -1);
                lua_pop(state, 1);
            }
            lua_getfield(state, fieldIndex, "target");
            field.target = compileSerdeNode(state, schema, -1, holders, seen);
            lua_pop(state, 1);
            node.fields.push_back(std::move(field));
            lua_pop(state, 1);
        }
        lua_pop(state, 1);
        size_t bucketCount = 1;
        while (bucketCount < count * 2) bucketCount <<= 1;
        node.buckets.resize(bucketCount);
        for (size_t index = 0; index < node.fields.size(); ++index) {
            node.buckets[node.fields[index].hash & (bucketCount - 1)]
                .push_back(static_cast<uint32_t>(index));
        }
    }
    schema->nodes[id] = std::move(node);
    return id;
}

int compileSerde(lua_State *state) {
    luaL_checktype(state, 1, LUA_TTABLE);
    void *storage = lua_newuserdata(state, sizeof(serdeSchema));
    auto *schema = new (storage) serdeSchema();
    try {
        lua_createtable(state, 8, 0);
        const int holders = lua_gettop(state);
        std::unordered_map<const void *, uint32_t> seen;
        schema->root = compileSerdeNode(state, schema, 1, holders, seen);
        const char *unknown = luaL_optstring(state, 2, "reject");
        schema->rejectUnknown = std::strcmp(unknown, "ignore") != 0;
        lua_setfenv(state, -2);
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

void pushSerdeHeld(lua_State *state, int schemaIndex, int reference) {
    schemaIndex = schemaIndex < 0 ? lua_gettop(state) + schemaIndex + 1 : schemaIndex;
    lua_getfenv(state, schemaIndex);
    lua_rawgeti(state, -1, reference);
    lua_remove(state, -2);
}

bool serdeLiteralMatches(lua_State *state, int index, int schemaIndex, int reference) {
    if (reference == 0) return true;
    pushSerdeHeld(state, schemaIndex, reference);
    const bool matches = lua_equal(state, index, -1) != 0;
    lua_pop(state, 1);
    return matches;
}

struct serdeWriterSink {
    lua_State *state;
    int index;
    luaWriter *writer;
};

void drainSerdeWriter(serdeWriterSink *sink) {
    if (sink != nullptr) {
        drainWriterAtThreshold(sink->state, sink->index, sink->writer);
    }
}

void appendSerdeNode(
    lua_State *state,
    simdjson::builder::string_builder &builder,
    const serdeSchema &schema,
    uint32_t nodeId,
    int index,
    int schemaIndex,
    size_t depth,
    serdeWriterSink *sink
) {
    if (depth > 1024) luaL_error(state, "prepared JSON nesting is too deep");
    index = index < 0 ? lua_gettop(state) + index + 1 : index;
    const auto &node = schema.nodes[nodeId];
    if (!serdeLiteralMatches(state, index, schemaIndex, node.literalRef)) {
        luaL_error(state, "prepared JSON value does not match its literal schema");
    }
    switch (node.kind) {
        case serdeKind::STRING: {
            size_t length = 0;
            const char *value = luaL_checklstring(state, index, &length);
            if (!simdjson::validate_utf8(value, length)) {
                luaL_error(state, "prepared JSON string is not UTF-8");
            }
            builder.escape_and_append_with_quotes(std::string_view(value, length));
            return;
        }
        case serdeKind::INTEGER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value) || std::floor(value) != value) {
                luaL_error(state, "prepared JSON value is not an integer");
            }
            if ((node.hasMinimum && value < static_cast<lua_Number>(node.minimum))
                || (node.hasMaximum && value > static_cast<lua_Number>(node.maximum))) {
                luaL_error(state, "prepared JSON integer is outside its schema range");
            }
            builder.append(static_cast<int64_t>(value));
            return;
        }
        case serdeKind::NUMBER: {
            const lua_Number value = luaL_checknumber(state, index);
            if (!std::isfinite(value)) {
                luaL_error(state, "prepared JSON number is not finite");
            }
            builder.append(static_cast<double>(value));
            return;
        }
        case serdeKind::BOOLEAN:
            luaL_checktype(state, index, LUA_TBOOLEAN);
            builder.append(lua_toboolean(state, index) != 0);
            return;
        case serdeKind::OPTIONAL:
            if (lua_isnil(state, index)) builder.append_null();
            else appendSerdeNode(state, builder, schema, node.element, index, schemaIndex, depth + 1, sink);
            return;
        case serdeKind::LIST: {
            luaL_checktype(state, index, LUA_TTABLE);
            const size_t count = lua_objlen(state, index);
            builder.start_array();
            for (size_t item = 1; item <= count; ++item) {
                if (item != 1) builder.append_comma();
                lua_rawgeti(state, index, static_cast<int>(item));
                if (lua_isnil(state, -1)) luaL_error(state, "prepared JSON list is sparse");
                appendSerdeNode(state, builder, schema, node.element, -1, schemaIndex, depth + 1, sink);
                lua_pop(state, 1);
                drainSerdeWriter(sink);
            }
            builder.end_array();
            return;
        }
        case serdeKind::MAP: {
            luaL_checktype(state, index, LUA_TTABLE);
            builder.start_object();
            bool first = true;
            lua_pushnil(state);
            while (lua_next(state, index) != 0) {
                if (lua_type(state, -2) != LUA_TSTRING) {
                    luaL_error(state, "prepared JSON map key must be a string");
                }
                size_t length = 0;
                const char *key = lua_tolstring(state, -2, &length);
                if (!simdjson::validate_utf8(key, length)) {
                    luaL_error(state, "prepared JSON map key must be a UTF-8 string");
                }
                if (!first) builder.append_comma();
                first = false;
                builder.escape_and_append_with_quotes(std::string_view(key, length));
                builder.append_colon();
                appendSerdeNode(state, builder, schema, node.element, -1, schemaIndex, depth + 1, sink);
                lua_pop(state, 1);
                drainSerdeWriter(sink);
            }
            builder.end_object();
            return;
        }
        case serdeKind::STRUCTURE: {
            int values = index;
            if (node.access == serdeAccess::DYNAMIC) {
                lua_getfield(state, index, "token");
                lua_getfield(state, -1, "values");
                lua_remove(state, -2);
                values = lua_gettop(state);
            }
            builder.start_object();
            size_t emitted = 0;
            for (size_t fieldIndex = 0; fieldIndex < node.fields.size(); ++fieldIndex) {
                const auto &field = node.fields[fieldIndex];
                if (node.access == serdeAccess::DYNAMIC) {
                    lua_rawgeti(state, values, static_cast<int>(fieldIndex + 1));
                } else {
                    lua_getfield(state, values, field.logical.c_str());
                }
                if (lua_isnil(state, -1)) {
                    lua_pop(state, 1);
                    if (field.required) {
                        luaL_error(state, "missing required member %s", field.logical.c_str());
                    }
                    continue;
                }
                if (emitted++ != 0) builder.append_comma();
                builder.append_raw(field.encodedKey);
                appendSerdeNode(state, builder, schema, field.target, -1, schemaIndex, depth + 1, sink);
                lua_pop(state, 1);
                drainSerdeWriter(sink);
            }
            builder.end_object();
            if (node.access == serdeAccess::DYNAMIC) lua_pop(state, 1);
            return;
        }
        case serdeKind::DOCUMENT: {
            std::unordered_set<const void *> visiting;
            const char *failure = nullptr;
            if (!appendLuaValue(
                state, builder, index, 0, visiting, depth, &failure
            )) {
                luaL_error(
                    state, "prepared JSON document: %s",
                    failure != nullptr ? failure : "encoding failed"
                );
            }
            return;
        }
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

void appendSerdeRoot(
    lua_State *state,
    simdjson::builder::string_builder &builder,
    serdeSchema *schema,
    int valueIndex,
    serdeWriterSink *sink
) {
    appendSerdeNode(
        state, builder, *schema, schema->root, valueIndex, 1, 0, sink
    );
}

int encodeSerdeCommon(lua_State *state, bool into) {
    auto *schema = checkSerdeSchema(state, 1);
    try {
        // A worker thread reuses its encoder allocation across complete roots. The
        // public Prepared value is immutable; this is operation scratch and is
        // cleared before every traversal, including after a prior Lua error longjmp.
        serdeBuilder.clear();
        appendSerdeRoot(state, serdeBuilder, schema, 2, nullptr);
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

int encodeSerde(lua_State *state) { return encodeSerdeCommon(state, false); }
int encodeSerdeInto(lua_State *state) { return encodeSerdeCommon(state, true); }

int writeSerde(lua_State *state) {
    auto *schema = checkSerdeSchema(state, 1);
    lua_getfield(state, 3, "raw");
    const int raw = lua_gettop(state);
    auto *writer = checkedWriter(state, raw);
    const char *failure = nullptr;
    try {
        if (prepareWriterValue(writer, &failure)) {
            serdeWriterSink sink{state, raw, writer};
            appendSerdeRoot(
                state, writer->backing->builder, schema, 2, &sink
            );
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) return writerError(state, failure);
    drainWriterAtThreshold(state, raw, writer);
    lua_pop(state, 1);
    return 0;
}

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

const serdeField *findSerdeField(const serdeNode &node, std::string_view key, size_t *expected) {
    if (*expected < node.fields.size()) {
        const auto &candidate = node.fields[*expected];
        if (candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            ++*expected;
            return &candidate;
        }
    }
    const uint64_t hash = serdeHash(key);
    const auto &bucket = node.buckets[hash & (node.buckets.size() - 1)];
    for (const uint32_t index : bucket) {
        const auto &candidate = node.fields[index];
        if (candidate.hash == hash && candidate.wire.size() == key.size()
            && std::memcmp(candidate.wire.data(), key.data(), key.size()) == 0) {
            *expected = static_cast<size_t>(index) + 1;
            return &candidate;
        }
    }
    return nullptr;
}

bool checkDecodedLiteral(
    lua_State *state,
    int schemaIndex,
    const serdeNode &node,
    const char **failure
) {
    if (node.literalRef == 0) return true;
    if (!serdeLiteralMatches(state, -1, schemaIndex, node.literalRef)) {
        *failure = "value does not match literal schema";
        lua_pop(state, 1);
        return false;
    }
    return true;
}

bool pushSerdeNode(
    lua_State *state,
    simdjson::ondemand::value &value,
    const serdeSchema &schema,
    uint32_t nodeId,
    int schemaIndex,
    bool rejectUnknown,
    size_t depth,
    const char **failure
) {
    if (depth > 1024) { *failure = "nesting is too deep"; return false; }
    const auto &node = schema.nodes[nodeId];
    simdjson::error_code error = simdjson::SUCCESS;
    switch (node.kind) {
        case serdeKind::STRING: {
            std::string_view result;
            error = value.get_string().get(result);
            if (error) { *failure = simdjson::error_message(error); return false; }
            lua_pushlstring(state, result.data(), result.size());
            return checkDecodedLiteral(state, schemaIndex, node, failure);
        }
        case serdeKind::INTEGER: {
            int64_t result = 0;
            error = value.get_int64().get(result);
            if (!error && ((node.hasMinimum && result < node.minimum)
                || (node.hasMaximum && result > node.maximum))) {
                *failure = "integer outside schema range";
                return false;
            }
            if (error) { *failure = simdjson::error_message(error); return false; }
            lua_pushnumber(state, static_cast<lua_Number>(result));
            return checkDecodedLiteral(state, schemaIndex, node, failure);
        }
        case serdeKind::NUMBER: {
            double result = 0;
            error = value.get_double().get(result);
            if (error) { *failure = simdjson::error_message(error); return false; }
            lua_pushnumber(state, result);
            return checkDecodedLiteral(state, schemaIndex, node, failure);
        }
        case serdeKind::BOOLEAN: {
            bool result = false;
            error = value.get_bool().get(result);
            if (error) { *failure = simdjson::error_message(error); return false; }
            lua_pushboolean(state, result ? 1 : 0);
            return checkDecodedLiteral(state, schemaIndex, node, failure);
        }
        case serdeKind::OPTIONAL: {
            simdjson::ondemand::json_type type;
            error = value.type().get(type);
            if (error) break;
            if (type == simdjson::ondemand::json_type::null) {
                bool ignored = false;
                error = value.is_null().get(ignored);
                if (!error) lua_pushnil(state);
                return !error;
            }
            return pushSerdeNode(
                state, value, schema, node.element, schemaIndex,
                rejectUnknown, depth + 1, failure
            );
        }
        case serdeKind::LIST: {
            simdjson::ondemand::array input;
            error = value.get_array().get(input);
            if (error) break;
            lua_createtable(state, 8, 0);
            const int output = lua_gettop(state);
            int index = 1;
            for (auto result : input) {
                simdjson::ondemand::value child;
                error = result.get(child);
                if (error || !pushSerdeNode(
                    state, child, schema, node.element, schemaIndex,
                    rejectUnknown, depth + 1, failure
                )) {
                    if (error) *failure = simdjson::error_message(error);
                    lua_settop(state, output - 1);
                    return false;
                }
                lua_rawseti(state, output, index++);
            }
            return true;
        }
        case serdeKind::MAP: {
            simdjson::ondemand::object input;
            error = value.get_object().get(input);
            if (error) break;
            lua_createtable(state, 0, 8);
            const int output = lua_gettop(state);
            for (auto result : input) {
                simdjson::ondemand::field field;
                error = std::move(result).get(field);
                if (error) break;
                std::string_view key;
                error = field.unescaped_key().get(key);
                if (error) break;
                lua_pushlstring(state, key.data(), key.size());
                auto &child = field.value();
                if (!pushSerdeNode(
                    state, child, schema, node.element, schemaIndex,
                    rejectUnknown, depth + 1, failure
                )) {
                    lua_settop(state, output - 1);
                    return false;
                }
                lua_rawset(state, output);
            }
            if (!error) return true;
            lua_settop(state, output - 1);
            break;
        }
        case serdeKind::STRUCTURE: {
            simdjson::ondemand::object input;
            error = value.get_object().get(input);
            if (error) break;
            if (node.access == serdeAccess::DYNAMIC) {
                lua_createtable(state, static_cast<int>(node.fields.size()), 0);
            } else {
                pushSerdeHeld(state, schemaIndex, node.typeRef);
                if (lua_istable(state, -1)) {
                    lua_createtable(state, 0, static_cast<int>(node.fields.size()));
                    lua_insert(state, -2);
                    lua_setmetatable(state, -2);
                } else {
                    lua_call(state, 0, 1);
                }
            }
            const int output = lua_gettop(state);
            std::vector<bool> seen(node.fields.size(), false);
            size_t expected = 0;
            for (auto result : input) {
                simdjson::ondemand::field inputField;
                error = std::move(result).get(inputField);
                if (error) break;
                std::string_view key;
                error = inputField.unescaped_key().get(key);
                if (error) break;
                const serdeField *field = findSerdeField(node, key, &expected);
                auto &child = inputField.value();
                if (field == nullptr) {
                    if (rejectUnknown) {
                        lua_pushlstring(state, key.data(), key.size());
                        *failure = lua_tostring(state, -1);
                        lua_settop(state, output - 1);
                        return false;
                    }
                    if (!consumeSerdeValue(child, failure)) {
                        lua_settop(state, output - 1);
                        return false;
                    }
                    continue;
                }
                const size_t fieldIndex = static_cast<size_t>(field - node.fields.data());
                if (seen[fieldIndex]) {
                    *failure = "duplicate member";
                    lua_settop(state, output - 1);
                    return false;
                }
                if (!pushSerdeNode(
                    state, child, schema, field->target, schemaIndex,
                    rejectUnknown, depth + 1, failure
                )) {
                    lua_settop(state, output - 1);
                    return false;
                }
                seen[fieldIndex] = true;
                if (node.access == serdeAccess::DYNAMIC) {
                    lua_rawseti(state, output, static_cast<int>(fieldIndex + 1));
                } else {
                    lua_setfield(state, output, field->logical.c_str());
                }
            }
            if (error) {
                lua_settop(state, output - 1);
                break;
            }
            for (size_t fieldIndex = 0; fieldIndex < node.fields.size(); ++fieldIndex) {
                const auto &field = node.fields[fieldIndex];
                if (seen[fieldIndex]) continue;
                if (field.required) {
                    *failure = field.logical.c_str();
                    lua_settop(state, output - 1);
                    return false;
                }
                if (field.defaultRef != 0) {
                    pushSerdeHeld(state, schemaIndex, field.defaultRef);
                    if (node.access == serdeAccess::DYNAMIC) {
                        lua_rawseti(state, output, static_cast<int>(fieldIndex + 1));
                    } else {
                        lua_setfield(state, output, field.logical.c_str());
                    }
                }
            }
            return true;
        }
        case serdeKind::DOCUMENT: {
            const auto emitted = pushOnDemandValue(state, value, 0, failure);
            if (emitted == emitResult::FAILED) return false;
            if (emitted == emitResult::DROPPED) lua_pushnil(state);
            return true;
        }
    }
    if (error) { *failure = simdjson::error_message(error); return false; }
    return false;
}

int decodeSerdeBytes(
    lua_State *state,
    serdeSchema *schema,
    const char *source,
    size_t length,
    size_t capacity
) {
    const int base = lua_gettop(state);
    const char *failure = nullptr;
    try {
        static thread_local simdjson::ondemand::parser parser;
        simdjson::ondemand::document document;
        auto error = parser.iterate(source, length, capacity).get(document);
        if (error) failure = simdjson::error_message(error);
        else {
            simdjson::ondemand::value root;
            error = document.get(root);
            if (error) failure = simdjson::error_message(error);
            else if (!pushSerdeNode(
                state, root, *schema, schema->root, 1,
                schema->rejectUnknown, 0, &failure
            )) {
                if (failure == nullptr) failure = "value did not match schema";
            }
        }
    } catch (const std::bad_alloc &) {
        failure = "allocation failed";
    }
    if (failure != nullptr) {
        const std::string message(failure);
        lua_settop(state, base);
        lua_pushnil(state);
        lua_pushfstring(state, "prepared JSON decode failed near %s", message.c_str());
        return 2;
    }
    lua_pushnil(state);
    return 2;
}

int decodeSerde(lua_State *state) {
    auto *schema = checkSerdeSchema(state, 1);
    size_t length = 0;
    const char *source = luaL_checklstring(state, 2, &length);
    static thread_local std::vector<char> padded;
    try {
        padded.resize(length + simdjson::SIMDJSON_PADDING);
    } catch (const std::bad_alloc &) {
        lua_pushnil(state);
        lua_pushliteral(state, "prepared JSON decode failed near allocation failed");
        return 2;
    }
    std::memcpy(padded.data(), source, length);
    std::memset(padded.data() + length, 0, simdjson::SIMDJSON_PADDING);
    return decodeSerdeBytes(state, schema, padded.data(), length, padded.size());
}

int decodeSerdeBuffer(lua_State *state) {
    auto *schema = checkSerdeSchema(state, 1);
    if (!hasRegisteredMetatable(state, 2, &BUFFER_METATABLE_KEY)) {
        return luaL_argerror(state, 2, "string.buffer.Buffer expected");
    }
    lua_getfield(state, 2, "reserve");
    lua_pushvalue(state, 2);
    lua_pushinteger(state, simdjson::SIMDJSON_PADDING);
    lua_call(state, 2, 2);
    const size_t trailing = serdeCapacity(state, -1);
    if (trailing < simdjson::SIMDJSON_PADDING) {
        return luaL_error(state, "prepared JSON buffer did not reserve padding");
    }
    std::memset(serdeDestination(state, -2), 0, simdjson::SIMDJSON_PADDING);
    lua_pop(state, 2);

    lua_getfield(state, 2, "ref");
    lua_pushvalue(state, 2);
    lua_call(state, 1, 2);
    const char *source = serdeDestination(state, -2);
    const size_t length = serdeCapacity(state, -1);
    lua_pop(state, 2);
    return decodeSerdeBytes(state, schema, source, length, length + trailing);
}

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
    setSerdeFunction(state, module, "encodeSerde", encodeSerde);
    setSerdeFunction(state, module, "encodeSerdeInto", encodeSerdeInto);
    setSerdeFunction(state, module, "writeSerde", writeSerde);
    setSerdeFunction(state, module, "copySerdeEncoding", copySerdeEncoding);
    setSerdeFunction(state, module, "decodeSerde", decodeSerde);
    setSerdeFunction(state, module, "decodeSerdeBuffer", decodeSerdeBuffer);
}
