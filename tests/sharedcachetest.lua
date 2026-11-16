local test = require("assert")
local sharedcache = require("nupp.core.sharedcache")
local M = {}

-- Windows names its sources by asking git directly, so that answer has to be
-- the one `scripts/shared-cache digest` gives everywhere else.
function M.test_git_digest_matches_the_shared_cache_script()
    local paths = {"scripts", "nupp.lua", "no-such-path"}
    local script = sharedcache.treeDigest(".", paths)
    test.eq(type(script), "string")
    test.eq(sharedcache.gitTreeDigest(".", paths), script)
end

function M.test_git_digest_of_nothing_is_absent()
    test.eq(sharedcache.gitTreeDigest(".", {"no-such-path"}), nil)
end

return M
