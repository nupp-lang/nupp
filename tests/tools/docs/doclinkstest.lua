local urls = require("nupp.tools.doc.urls")

local M = {}

local function routed(markdown)
    local page = {source = "docs/start.md", path = "start"}
    local pages = {page, {source = "docs/guide.md", path = "guide", title = "Guide"}}
    return urls.rewriteConfiguredPageLinks(markdown, page, pages, "start/index.html")
end

function M.longerAndTildeFencesPreserveLinksUntilTheirRealCloser()
    for _, code in ipairs({
        "````markdown\n```md\n[Guide](guide.md)\n```\n````",
        "~~~~markdown\n~~~\n[Guide](guide.md)\n```\n~~~~~",
        "```markdown\n[Guide](guide.md)\n````",
        "   ~~~markdown\r\n[Guide](guide.md)\r\n   ~~~~",
    }) do
        local result = routed(code .. "\n[Guide](guide.md)\n")
        assert(result == code .. "\n[Guide](../guide/index.html)\n", result)
    end
    local unclosed = "~~~markdown\n[Guide](guide.md)\n"
    assert(routed(unclosed) == unclosed)
end

function M.inlineCodeRequiresAnExactRunAndLabelsRemainLinks()
    for _, code in ipairs({
        "`[Guide](guide.md)`",
        "``a ` tick [Guide](guide.md)``",
        "`a `` longer run [Guide](guide.md)`",
        "``a\n[Guide](guide.md)``",
        "\\``[Guide](guide.md)`",
    }) do
        local result = routed(code .. " [Guide](guide.md)")
        assert(result == code .. " [Guide](../guide/index.html)", result)
    end
    assert(routed("[`Guide`](guide.md)") == "[`Guide`](../guide/index.html)")
    assert(routed("unmatched ` [Guide](guide.md)") == "unmatched ` [Guide](../guide/index.html)")
    assert(routed("\\`[Guide](guide.md)\\`") == "\\`[Guide](../guide/index.html)\\`")
end

function M.symbolLinksUseTheSameCodeBoundaries()
    local code = "````markdown\n```md\n[](Thing)\n```\n````"

    local function resolve(name)
        return name == "Thing" and "api/thing/index.html" or nil
    end

    local result = urls.rewriteSymbolLinks(code .. "\n[](Thing) [`Thing`](Thing) `[](Thing)`", resolve)
    assert(result == code .. "\n[`Thing`](api/thing/index.html) [`Thing`](api/thing/index.html) `[](Thing)`", result)
end

return M
