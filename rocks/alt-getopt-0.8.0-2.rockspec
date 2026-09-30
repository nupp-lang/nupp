-- alt-getopt's published rockspec names a Git tag, which can be moved. This
-- one names the commit the tag points at, as the archive GitHub serves for it,
-- and `source.md5` is the digest LuaRocks checks that archive against before
-- it unpacks it. This file is pinned by the commit that carries it, so the two
-- together pin what is installed.
rockspec_format = "3.0"
package = "alt-getopt"
version = "0.8.0-2"

source = {
   url = "https://github.com/cheusov/lua-alt-getopt/archive/f495c21d6a203ab280603aa5799e636fb5651ae7.tar.gz",
   md5 = "6be0473af463f356f1343b5b84ffbc4e",
   dir = "lua-alt-getopt-f495c21d6a203ab280603aa5799e636fb5651ae7",
}

description = {
   summary = "Process application arguments the same way as getopt_long",
   homepage = "https://github.com/cheusov/lua-alt-getopt",
   license = "MIT/X11",
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "builtin",
   modules = {
      alt_getopt = "alt_getopt.lua",
   },
}
