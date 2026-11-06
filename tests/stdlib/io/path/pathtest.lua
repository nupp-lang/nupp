-- `io.Path` through the real provider.
--
-- One table of answers, recorded from the implementation this replaced. A path
-- library's whole job is to agree with everybody else about what a piece of text
-- names, so the useful test is not that each function does something reasonable
-- but that the answers have not moved.
--
-- The distinction the table is really pinning: a path that is *rebuilt* is
-- normalised, and a path that is *sliced* keeps the spelling the caller wrote.
-- Asking for a path's parent asks about that path, not about a tidier one.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local pathtext = require("nupp.io.path.pathtext")

local M = {}

local path, previous, root
local installedBootstrap = false
local unavailable

local function temporaryRoot()
    local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
    base = base:gsub("\\", "/")
    -- Suite shards start in the same second with the same random seed. Include
    -- a per-process address so one shard cannot remove another shard's root.
    local unique = tostring({}):match("(%x+)$") or "0"

    return (
        base:gsub("/$", "")
    ) .. "/nupp-path-test-" .. tostring(os.time()) .. "-" .. unique .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
    installedBootstrap = false
    math.randomseed(os.time())
    root = temporaryRoot()
    os.execute("mkdir -p '" .. root .. "'")
    -- The VM carries its own provider: the facade reaches it the way a VM
    -- program does.
    path = require("io.internal.path")
end

function M.afterAll()
    -- Restore only a bootstrap this suite replaced.
    if installedBootstrap then
        _G.nupp = previous
        installedBootstrap = false
    end
    if root then
        os.execute("rm -rf '" .. root .. "'")
    end
end

local function ready()
    if unavailable then
        error("skip: " .. unavailable, 0)
    end
    return path
end

-- A path written the awkward way on purpose: a `.` that normalising removes and
-- slicing keeps, a `..` that cancels a name, and a two-dot extension.
local MESSY = "alpha/./beta/../file.tar.gz"

function M.normalizingResolvesWhatItCanWithoutTheFilesystem()
    local module = ready()
    test.eq(module.newpath(MESSY):normalize():tostring(), "alpha/file.tar.gz")
    -- Nothing left means the path described where it already was.
    test.eq(module.newpath("a/.."):normalize():tostring(), ".")
    -- A relative path that starts by going up has nowhere to put the answer.
    test.eq(module.newpath("../../a"):normalize():tostring(), "../../a")
    -- One at the root has nothing to cancel.
    test.eq(module.newpath("/../a"):normalize():tostring(), "/a")
end

function M.readingAPartSlicesRatherThanRebuilds()
    local module = ready()
    local messy = module.newpath(MESSY)
    -- The `./` survives, because this is a question about this path.
    test.eq(messy:parent():tostring(), "alpha/./beta/..")
    test.eq(messy:filename(), "file.tar.gz")
    test.eq(messy:stem(), "file.tar")
    test.eq(messy:extension(), "gz")

    test.eq(module.newpath("/"):parent(), nil, "a root has no parent")
    test.eq(module.newpath("foo"):parent():tostring(), "")
    test.eq(module.newpath("/foo"):parent():tostring(), "/")
    -- A leading dot is a name, not an extension.
    test.eq(module.newpath(".bashrc"):stem(), ".bashrc")
    test.eq(module.newpath(".bashrc"):extension(), nil)
    test.eq(module.newpath("a."):extension(), "")
    test.eq(module.newpath("noext"):extension(), nil)
    -- `..` is not something a caller could rename.
    test.eq(module.newpath("a/.."):filename(), nil)
end

function M.derivingReplacesTheNameOrTheExtension()
    local module = ready()
    local messy = module.newpath(MESSY)
    test.eq(messy:withfilename("other.txt"):tostring(), "alpha/./beta/../other.txt")
    test.eq(messy:withextension("bz2"):tostring(), "alpha/./beta/../file.tar.bz2")
    test.eq(messy:withextension(""):tostring(), "alpha/./beta/../file.tar")
    -- With no file name there is nothing to drop, so the name is added.
    test.eq(module.newpath("a/.."):withfilename("c"):tostring(), "a/../c")
end

-- A replacement name or extension is one component. Text carrying a
-- separator, a `..` or a NUL used to be spliced in, so a file name could walk
-- the path out of its directory. Both rule sets refuse it, and the good cases
-- above keep their answers.
function M.derivingRefusesTextThatIsNotOneComponent()
    for _, windows in ipairs({false, true}) do
        local base = windows and "out\\report.tmp" or "out/report.tmp"
        for _, name in ipairs({"../../etc/passwd", "/abs", "a/b", "x\0y", "..", ".", ""}) do
            test.raises(
                function()
                    pathtext.with(base, name, false, windows)
                end,
                "file name"
            )
        end
        for _, extension in ipairs({"json/../../x", "/abs", "x\0y"}) do
            test.raises(
                function()
                    pathtext.with(base, extension, true, windows)
                end,
                "extension"
            )
        end
        test.eq(pathtext.with(base, "other.txt", false, windows), windows and "out/other.txt" or "out/other.txt")
        test.eq(pathtext.with(base, "json", true, windows), "out/report.json")
        test.eq(pathtext.with(base, "", true, windows), "out/report")
    end
    -- Windows reads a backslash as a separator and a colon as a drive or a
    -- stream, so neither is a component there.
    for _, name in ipairs({"..\\x", "C:x", "a:b"}) do
        test.raises(
            function()
                pathtext.with("out\\report.tmp", name, false, true)
            end,
            "file name"
        )
    end
    test.raises(
        function()
            pathtext.with("out\\report.tmp", "a\\b", true, true)
        end,
        "extension"
    )
    -- POSIX names may hold both.
    test.eq(pathtext.with("out/report.tmp", "a\\b:c", false, false), "out/a\\b:c")

    local module = ready()
    local report = module.newpath("out", "report.tmp")
    test.raises(
        function()
            report:withfilename("../../etc/passwd")
        end,
        "file name"
    )
    test.raises(
        function()
            report:withextension("json/../../x")
        end,
        "extension"
    )
end

-- One anchored and one not do not share a coordinate system. An absolute target
-- is still an answer -- it names where it is without reference to the base --
-- and a relative one against an absolute base is not.
function M.relatingNeedsBothPathsAnchoredTheSameWay()
    local module = ready()
    test.eq(module.newpath("/a/b/c"):relativeto("/a/d"):tostring(), "../b/c")
    test.eq(module.newpath("/a/b"):relativeto("a/b"):tostring(), "/a/b")
    test.eq(module.newpath("a/b"):relativeto("/a/b"), nil)
end

-- A path expressed against itself is where the base already is, and `.` is
-- how a path spells that: `""` names nothing a filesystem call accepts.
function M.relatingAPathToItselfAnswersDot()
    local module = ready()
    test.eq(module.newpath("/a/b"):relativeto("/a/b"):tostring(), ".")
    test.eq(module.newpath("a/b"):relativeto("a/b"):tostring(), ".")
    -- Nor does a trailing separator or a `.` component move the answer.
    test.eq(module.newpath("a/b/"):relativeto("a/b"):tostring(), ".")
    test.eq(module.newpath("a/./b"):relativeto("a/b"):tostring(), ".")
end

function M.joiningLetsAnAbsolutePartReplaceWhatCameBefore()
    local module = ready()
    test.eq(module.newpath("src", "main.nupp"):tostring(), "src/main.nupp")
    test.eq(module.newpath("/a", "/b"):tostring(), "/b")
    assert(module.newpath("/a"):isabsolute())
    assert(not module.newpath("a"):isabsolute())
end

function M.filesystemQuestionsUseTheGenericProvider()
    local module = ready()
    local current = assert(module.cwd())
    assert(current:isabsolute())
    test.eq(assert(module.newpath("."):absolute()):tostring(), current:tostring())
    test.eq(assert(module.newpath("alpha//./beta/.."):absolute()):tostring(), current:join("alpha/beta/.."):tostring())

    local canonical = assert(module.newpath(root):canonicalize())
    assert(canonical:isabsolute())
    test.eq(assert(canonical:canonicalize()):tostring(), canonical:tostring())
end

function M.pathStagesOnlyTheGenericFilesystemSlice()
    local feature = assert(native.feature("native.path"))
    test.eq(feature.providerFeature, "filesystem")
    test.eq(feature.providerDriver, "native-rust")
    test.eq(feature.provider, "nupp_native")
    test.eq(feature.host, "native-files")
    test.eq(feature.library, "nupp_native")
    test.eq(feature.runtimeModule, "nupp.runtime.provider.nativepath")
    test.eq(table.concat(feature.requires or {}, ","), "runtime.path,runtime.native")
    local runtime = assert(native.feature("runtime.path"))
    test.eq(runtime.runtimeModule, "io.internal.path")
    test.eq(runtime.portableRuntime, true)
    local handle = io.open("runtime/native/c/path.c", "rb")
    if handle then
        handle:close()
        error("the removed path provider still exists")
    end
    local source = assert(io.open("src/io/internal/path.nupp", "rb"))
    local text = source:read("*a")
    source:close()
    assert(not text:find("nupp.runtime.native", 1, true), "the shared path implementation has no provider dependency")
    local provider = assert(io.open("src/nupp/runtime/provider/nativepath.nupp", "rb"))
    local providerText = provider:read("*a")
    provider:close()
    assert(
        providerText:find('require("nupp.vm.files")', 1, true),
        "the native path provider calls the VM's filesystem host"
    )
end

-- The scalar rules take the spelling convention as data, so both platforms are
-- testable on one machine. These are Windows answers even on a POSIX runner.
function M.windowsTextRulesArePlatformIndependent()
    assert(pathtext.isAbsolute("C:\\alpha", true))
    assert(not pathtext.isAbsolute("C:alpha", true))
    assert(pathtext.isAbsolute("\\alpha", true))
    test.eq(pathtext.normalize("C:\\alpha\\.\\beta\\..\\file.txt", true), "C:/alpha/file.txt")
    test.eq(pathtext.normalize("C:alpha\\..\\beta", true), "C:beta")
    test.eq(pathtext.part("C:\\alpha\\.\\beta\\..\\file.tar.gz", 0, true), "C:/alpha/./beta/..")
    test.eq(pathtext.part("C:\\alpha\\file.tar.gz", 3, true), "gz")
    test.eq(pathtext.join({"C:\\alpha", "\\beta"}, true), "C:/beta")
    test.eq(pathtext.join({"C:\\alpha", "D:\\beta"}, true), "D:/beta")
    test.eq(pathtext.clean("C:\\alpha\\.\\\\beta\\..", true), "C:/alpha/beta/..")
    test.eq(assert(pathtext.relative("C:\\alpha\\beta", "C:\\alpha\\other", true)), "../beta")
    test.eq(pathtext.with("C:\\alpha\\file.txt", "bak", true, true), "C:/alpha/file.bak")
end

-- An anchor is compared by what it is rather than how it is spelled: `/` and
-- `\` name the same root, while two drives are two coordinate systems and no
-- count of `..` steps leads from one to the other.
function M.relatingWindowsPathsComparesAnchorsByKind()
    local answer, reason = pathtext.relative("C:\\a", "D:\\b", true)
    test.eq(answer, nil)
    assert(type(reason) == "string" and #reason > 0, "two drives answer why there is no relative form")
    test.eq(assert(pathtext.relative("C:/a", "C:\\b", true)), "../a")
    test.eq(assert(pathtext.relative("\\a", "/b", true)), "../a")
    -- A drive-anchored target against a merely rooted base is the same refusal.
    test.eq(pathtext.relative("C:\\a", "\\b", true), nil)
end

-- A bare drive prefix names a coordinate system rather than a place, so joining
-- onto one stays drive-relative. A share root is a place, and keeps its
-- separator.
function M.joiningOntoABareDriveStaysDriveRelative()
    test.eq(pathtext.pushPart("C:", "foo", true), "C:foo")
    test.eq(pathtext.join({"C:", "foo"}, true), "C:foo")
    test.eq(pathtext.join({"\\\\server\\share", "file"}, true), "//server/share/file")
end

function M.absolutizingADriveRelativePathRequiresTheCurrentDrive()
    local windowsProvider = {
        sep = function()
            return "\\"
        end,
        cwd = function()
            return "C:\\base", nil
        end,
        canonicalize = function(value)
            return value, nil
        end,
    }
    local load = require(
        "helpers.providerstate"
    ).instance({["io.internal.path"] = true, ["io.internal.pathtypes"] = true}, {
        ["nupp.io.path.provider"] = windowsProvider
    })
    local windowsPath = load("io.internal.path")

    test.eq(assert(windowsPath.newpath("c:work"):absolute()):tostring(), "C:/base/work")
    test.eq(assert(windowsPath.newpath("C:"):absolute()):tostring(), "C:/base")
    local answer, reason = windowsPath.newpath("D:work"):absolute()
    test.eq(answer, nil)
    test.matches(reason, "another drive")
end

-- The verbatim form's whole point is that the system does not normalise it,
-- so nothing here may either: no `..` resolution, no separator respelling.
-- The system reads `\\?\` and nothing else -- not `//?/`, and not `/` as a
-- separator after it -- so a rewritten answer names a different thing.
function M.verbatimWindowsPathsAreCarriedUntouched()
    test.eq(pathtext.normalize("\\\\?\\C:\\a\\..\\b", true), "\\\\?\\C:\\a\\..\\b")
    test.eq(pathtext.normalize("\\\\?\\UNC\\server\\share\\a\\..\\b", true), "\\\\?\\UNC\\server\\share\\a\\..\\b")
    test.eq(pathtext.clean("\\\\?\\C:\\a\\.\\\\b", true), "\\\\?\\C:\\a\\.\\\\b")
    test.eq(pathtext.finish("\\\\?\\C:\\a", true), "\\\\?\\C:\\a")
    -- Joining appends the one separator the system reads there.
    test.eq(pathtext.pushPart("\\\\?\\C:\\a", "b", true), "\\\\?\\C:\\a\\b")
    test.eq(pathtext.with("\\\\?\\C:\\a\\file.txt", "bak", true, true), "\\\\?\\C:\\a\\file.bak")
    -- The prefix carries the disk, or the UNC server and share, as Windows
    -- reads it: `\\?\C:` alone names the raw volume, not its root, so the
    -- parent of a file on the disk is `\\?\C:\`, and the root has none.
    test.eq(pathtext.part("\\\\?\\C:\\foo", 0, true), "\\\\?\\C:\\")
    test.eq(pathtext.part("\\\\?\\C:\\foo", 1, true), "foo")
    test.eq(pathtext.part("\\\\?\\C:\\", 0, true), nil)
    test.eq(pathtext.part("\\\\?\\C:\\", 1, true), nil)
    test.eq(pathtext.part("\\\\?\\C:\\a\\b", 0, true), "\\\\?\\C:\\a")
    test.eq(pathtext.part("\\\\?\\UNC\\server\\share\\x", 0, true), "\\\\?\\UNC\\server\\share\\")
    test.eq(pathtext.part("\\\\?\\UNC\\server\\share\\", 1, true), nil)
    test.eq(pathtext.prefixLength("\\\\?\\C:\\foo", true), 6)
    test.eq(pathtext.prefixLength("\\\\?\\UNC\\server\\share\\x", true), 20)
    test.eq(pathtext.prefixLength("\\\\?\\", true), 4)
    test.eq(pathtext.part("\\\\.\\C:\\foo", 0, true), "//./C:/")
    test.eq(pathtext.with("\\\\?\\C:\\foo", "bar", false, true), "\\\\?\\C:\\bar")
    -- Expressing one is exactly the component reasoning verbatim opts out of.
    local answer, reason = pathtext.relative("\\\\?\\C:\\a\\b", "\\\\?\\C:\\a", true)
    test.eq(answer, nil)
    assert(type(reason) == "string" and #reason > 0, "a verbatim path answers why there is no relative form")
end

function M.storageDerivationKeepsItsRootAndPortableComponents()
    local paths = ready()
    local root = paths.browser("data", "example", "notes")
    assert(getmetatable(root) == paths.Path, "app directories use the public Path record")
    assert(root:parent() == nil, "an app root has no accessible parent")
    assert(root:isabsolute() and not root:isrelative())
    assert(rawequal(root:normalize(), root))
    assert(rawequal(assert(root:absolute()), root))
    local file = assert(root:resolve("draft.txt")):withfilename("note.tmp"):withextension("txt")
    test.eq(file:tostring(), "opfs:/data/example/notes/note.txt")
    test.eq(file:filename(), "note.txt")
    test.eq(file:stem(), "note")
    test.eq(file:extension(), "txt")
    test.eq(file:parent(), root)
    test.eq(paths.newpath(root, paths.newpath("note.txt")), file)
    for _, invalid in ipairs({
        "",
        ".",
        "..",
        "/escape",
        "a/b",
        "a\\b",
        "NUL",
        "COM¹.txt",
        "bad?name",
        "bad\0name",
        "tail.",
        "tail ",
        string.char(255)
    }) do
        test.raises(
            function()
                root:join(invalid)
            end,
            "application path component"
        )
        test.raises(
            function()
                file:withfilename(invalid)
            end,
            "application path component"
        )
    end
    test.raises(
        function()
            root:withfilename("other")
        end,
        "storage root"
    )
    test.raises(
        function()
            root:withextension("txt")
        end,
        "storage root"
    )
    test.raises(
        function()
            root:join(file)
        end,
        "application path"
    )
    test.raises(
        function()
            file:withextension("bad:name")
        end,
        "application path component"
    )
    local canonical, reason = file:canonicalize()
    test.eq(canonical, nil)
    assert(reason:find("canonicalize", 1, true))
    local relative, relativeReason = file:relativeto(root)
    test.eq(relative, nil)
    assert(relativeReason:find("relativeto", 1, true))
end

function M.pathCachingNeverGrantsStorageAuthorityFromText()
    local paths = ready()
    local app = paths.browser("data", "example", "notes")
    local ordinary = paths.newpath(app:tostring())
    assert(not rawequal(app, ordinary))
    assert(app ~= ordinary, "equal display text is not equal storage authority")
    assert(not paths.isapplication(ordinary))
    assert(not paths.isapplication(ordinary:join("file"):normalize()))
    assert(not paths.isapplication(paths.newpath("", app)))
    assert(paths.isapplication(paths.newpath(app, "file")))
    local otherRoot = paths.native("opfs:", "data", "example"):join("notes")
    if paths.sep() == "/" then
        test.eq(otherRoot:tostring(), app:tostring())
    end
    assert(otherRoot ~= app, "providers with identical display text stay distinct")
    local a = paths.native("/base", "org", "app"):join("file")
    local b = paths.native("/base/org", "app", "file")
    test.eq(a:tostring(), b:tostring())
    assert(a ~= b, "different storage roots stay distinct")
    for index = 1, 1100 do
        paths.newpath("evict-" .. index)
    end
    local rebuilt = paths.newpath(app:tostring())
    assert(not paths.isapplication(rebuilt))
    assert(rebuilt ~= app)
    test.eq(app:join("file"):parent(), app)
    local descriptor = paths.descriptor(app)
    descriptor.parts[1] = "elsewhere"
    test.eq(paths.descriptor(app).parts[1], "data", "descriptor consumers cannot mutate a path")
end

function M.interningPromotesCacheHitsAndEvictsTheLeastRecentPath()
    local paths = ready()
    local prefix = "nupp-cache-path/"
    local hot = paths.newpath(prefix .. "hot")
    local cold = paths.newpath(prefix .. "cold")
    for index = 1, 1022 do
        paths.newpath(prefix .. index)
    end
    assert(rawequal(paths.newpath(prefix .. "hot"), hot))
    paths.newpath(prefix .. "newest")
    assert(not rawequal(paths.newpath(prefix .. "cold"), cold))
    assert(rawequal(paths.newpath(prefix .. "hot"), hot))
end

return M
