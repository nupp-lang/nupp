-- Run the retained fixtures with the retained compiler, including after grammar
-- removal.
local source = debug.getinfo(1, "S").source:sub(2)
local root = assert(source:match("^(.*)/scripts/[^/]+$"))
local suite = assert(loadfile(root .. "/scripts/migration-fixtures/constructionmigration.lua"))()
local names = {}
for name, test in pairs(suite) do
    if type(test) == "function" then
        names[#names + 1] = name
    end
end
table.sort(names)
for _, name in ipairs(names) do
    suite[name]()
end
print(("%d construction migration tests passed"):format(#names))
