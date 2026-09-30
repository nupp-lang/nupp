-- LPeg's published rockspec, kept here so that what the documentation rocks are
-- built from is decided by this tree rather than by whatever a rock server
-- hands back on the day. `source.md5` is the digest LuaRocks checks the archive
-- against before it unpacks a byte of it; this file is pinned by the commit
-- that carries it, so the two together pin the bytes. LuaRocks checks no other
-- digest, which is why the pin is MD5 rather than SHA-256.
--
-- The archive is the one `scripts/toolchain.pins` names for the native LPeg, and
-- the MD5 below is of the file whose SHA-256 is `LPEG_SHA256` there.
rockspec_format = "3.0"
package = "lpeg"
version = "1.1.0-2"

source = {
   url = "https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.1.0.tar.gz",
   md5 = "842a538b403b5639510c9b6fffd2c75b",
   dir = "lpeg-1.1.0",
}

description = {
   summary = "Parsing Expression Grammars For Lua",
   homepage = "https://www.inf.puc-rio.br/~roberto/lpeg.html",
   license = "MIT/X11",
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "builtin",
   modules = {
      lpeg = {"lpcap.c", "lpcode.c", "lpcset.c", "lpprint.c", "lptree.c", "lpvm.c"},
      re = "re.lua",
   },
}
