#include "simdjson_bench.h"

#include <cstring>
#include <new>
#include <string>
#include <vector>

#include <simdjson.h>

struct nupp_simdjson_parser {
    simdjson::dom::parser dom;
    simdjson::ondemand::parser ondemand;
    std::vector<char> padded;
    size_t length{0};
    uint64_t sink{0};
};

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
