local html = require("nupp.tools.doc.html")
local M = {}

function M.repeatedHeadingsHaveUniqueAnchorsAndMatchingOutlineLinks()
    local source = "## Examples\n\n## Examples 2\n\n## Examples\n\n~~~markdown\n## Examples\n~~~\n\n## Examples\n"
    local rendered = html.markdownHtml(source)
    local outline = html.markdownOutline(source)
    assert(#outline == 4)
    local seen = {}
    for _, heading in ipairs(outline) do
        assert(not seen[heading.path], heading.path .. " is repeated")
        seen[heading.path] = true
        local _, count = rendered:gsub('id="' .. heading.path:gsub("(%W)", "%%%1") .. '"', "")
        assert(count == 1, heading.path .. " must name one rendered heading")
    end
    assert(outline[1].path == "examples" and outline[4].path == "examples-4")
end

function M.separateApiDescriptionsScopeTheirHeadingsAndLocalLinks()
    local source = '## Examples\n\n[Example](#examples) and [Reader](#io.Reader).\n'
    for _, owner in ipairs({"first.read", "second.read"}) do
        local rendered = html.markdownHtml(source, nil, nil, owner)
        assert(rendered:find('id="' .. owner .. '.examples"', 1, true), rendered)
        assert(rendered:find('href="#' .. owner .. '.examples"', 1, true), rendered)
        assert(rendered:find('href="#io.Reader"', 1, true), rendered)
    end
end

function M.explicitHeadingAnchorsAreNotDuplicatedByScoping()
    local rendered = html.markdownHtml('<a id="examples"></a>\n\n## Examples\n', nil, nil, "sample")
    assert(not rendered:find('id="examples"', 1, true), rendered)
    local _, count = rendered:gsub('id="sample%.examples"', "")
    assert(count == 1, rendered)
end

return M
