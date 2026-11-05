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

function M.explicitLocalAliasesScopeTheirLinksAndLaterHeadings()
    local source = '<a id="usage"></a>\n\n## Examples\n\n[Alias](#usage) and [Heading](#examples).\n\n## Returns\n'
    for _, scope in ipairs({"first.read", "second.read"}) do
        local rendered = html.markdownHtml(source, nil, nil, scope)
        assert(rendered:find('id="' .. scope .. '.usage"', 1, true), rendered)
        assert(rendered:find('href="#' .. scope .. '.usage"', 1, true), rendered)
        assert(not rendered:find('href="#usage"', 1, true), rendered)
        assert(not rendered:find('href="#examples"', 1, true), rendered)
        assert(rendered:find('id="' .. scope .. '.returns"', 1, true), rendered)
    end
end

function M.generatedMemberAnchorsKeepTheirCanonicalPaths()
    local source = '<a id="sample.Reader.read"></a>\n\n### `read` _method_\n\n'
        .. '<a id="usage"></a>\n\n#### Examples\n\n[Example](#usage) and [Member](#sample.Reader.read).\n'
    local rendered = html.markdownHtml(source, nil, nil, "sample.Reader")
    assert(rendered:find('id="sample.Reader.read"', 1, true), rendered)
    assert(rendered:find('id="sample.Reader.read.usage"', 1, true), rendered)
    assert(rendered:find('href="#sample.Reader.read.usage"', 1, true), rendered)
    assert(rendered:find('href="#sample.Reader.read"', 1, true), rendered)
    local _, count = rendered:gsub('id="sample%.Reader%.read"', "")
    assert(count == 1, rendered)
end

function M.overviewSectionsContainTheirHeadingsAndPreserveScopedLinks()
    local source = "## Earlier\n\nUnrelated prose.\n\n## Members\n\n"
        .. "::: api-overview\n**fields**\n\n- [`name`](#sample.name)\n:::\n\n"
        .. "[Members](#members).\n\n## Later\n"
    local rendered = html.markdownHtml(source, nil, 0, "sample")
    local section = assert(rendered:match('(<section class="nuppdoc%-overview%-section".-</section>)'), rendered)
    assert(section:find('aria-labelledby="sample.members"', 1, true), section)
    assert(section:find('<h2 class="nuppdoc-overview-title" id="sample.members">Members', 1, true), section)
    assert(section:find('<div class="nuppdoc-overview nuppdoc-overview-1">', 1, true), section)
    assert(not section:find('Earlier', 1, true) and not section:find('Later', 1, true), section)
    assert(not section:find('Unrelated prose', 1, true), section)
    assert(rendered:find('href="#sample.members">Members</a>', 1, true), rendered)
    local _, count = rendered:gsub('id="sample%.members"', "")
    assert(count == 1, rendered)
end

function M.overviewSectionsPreserveExplicitMemberOverviewAnchors()
    local source = '<a id="sample.members-overview"></a>\n#### Members\n\n'
        .. '::: api-overview\n**fields**\n\n- [`members`](#sample.members)\n:::\n'
    local rendered = html.markdownHtml(source, nil, 0, "sample")
    assert(rendered:find('aria-labelledby="sample.members-overview"', 1, true), rendered)
    assert(rendered:find('class="nuppdoc-overview-title" id="sample.members-overview"', 1, true), rendered)
    assert(rendered:find('href="#sample.members"><code>members</code></a>', 1, true), rendered)
    local _, count = rendered:gsub('id="sample%.members%-overview"', "")
    assert(count == 1, rendered)
end

function M.overviewsWithoutHeadingsStillHaveASection()
    local rendered = html.markdownHtml('::: api-overview\n**functions**\n\n- `run`\n:::\n')
    assert(rendered:find('<section class="nuppdoc-overview-section"><div class="nuppdoc-overview', 1, true), rendered)
    assert(not rendered:find('aria-labelledby', 1, true), rendered)
end

return M
