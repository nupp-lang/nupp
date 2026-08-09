-- Scintillua is not published on LuaRocks, so this rockspec stands in for the
-- one upstream does not ship. It names a release archive rather than a branch,
-- so the version this installs is the version this file says it installs.
--
-- The lexers are data as much as code: `lexer.lua` finds its siblings by path,
-- through the `scintillua.lexers` property, rather than by `require`. So they
-- are installed as a directory that stays a directory, and `nupp.compiler.doc.highlight`
-- locates it by resolving `scintillua.lexers.lexer` on the search path and
-- taking the directory that answer sits in.
rockspec_format = "3.0"
package = "scintillua"
version = "6.7-1"

source = {
   url = "https://github.com/orbitalquark/scintillua/releases/download/"
      .. "scintillua_6.7/scintillua_6.7.zip",
   dir = "scintillua",
}

description = {
   summary = "Lexers for over 150 languages, written with LPeg.",
   detailed = [[
      Scintillua's lexers, packaged for use as a library. Nupp uses them to
      highlight fenced code blocks in generated documentation.
   ]],
   homepage = "https://github.com/orbitalquark/scintillua",
   license = "MIT",
}

dependencies = {
   "lua >= 5.1",
   "lpeg >= 0.12",
}

-- `cp -R` rather than a module map: there are 160 lexers, the set changes with
-- every upstream release, and listing them here would be a file to forget to
-- update rather than a fact worth stating.
build = {
   type = "command",
   build_command = "true",
   install_command = "mkdir -p $(LUADIR)/scintillua && "
      .. "cp -R lexers $(LUADIR)/scintillua/ && "
      .. "cp LICENSE $(LUADIR)/scintillua/",
}
