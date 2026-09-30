-- Cosmo's published rockspec names a Git branch, which is a name and not a
-- set of bytes. This one names the commit that release tag points at, as the
-- archive GitHub serves for it, and `source.md5` is the digest LuaRocks checks
-- that archive against before it unpacks it. This file is pinned by the commit
-- that carries it, so the two together pin what is installed and what `dist`
-- bundles.
rockspec_format = "3.0"
package = "cosmo"
version = "16.06.04-1"

source = {
   url = "https://github.com/mascarenhas/cosmo/archive/e6118c8850b0ba1fc22b66294beb40c591d2a752.tar.gz",
   md5 = "8b7f56cdb720c5836a19c5138fb3656e",
   dir = "cosmo-e6118c8850b0ba1fc22b66294beb40c591d2a752",
}

description = {
   summary = "Safe templates for Lua",
   homepage = "https://github.com/mascarenhas/cosmo",
   license = "MIT/X11",
}

dependencies = {
   "lpeg >= 0.9",
}

build = {
   type = "builtin",
   modules = {
      cosmo = "src/cosmo.lua",
      ["cosmo.fill"] = "src/cosmo/fill.lua",
      ["cosmo.grammar"] = "src/cosmo/grammar.lua",
   },
}
