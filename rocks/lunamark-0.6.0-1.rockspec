-- Lunamark's published rockspec fetches a Git tag over the unauthenticated
-- git:// protocol, and a tag can be moved. This one names the commit the tag
-- points at, as the archive GitHub serves for it, and `source.md5` is the
-- digest LuaRocks checks that archive against before it unpacks it. This file
-- is pinned by the commit that carries it, so the two together pin what is
-- installed and what `dist` bundles.
--
-- The published dependencies are left out: they include an obsolete native
-- UTF-8 module Nupp does not install, and `nupp.lua` pins the rest itself.
rockspec_format = "3.0"
package = "lunamark"
version = "0.6.0-1"

source = {
   url = "https://github.com/jgm/lunamark/archive/99597c0770b7e4bcd0939a42b225b444c70f4e5e.tar.gz",
   md5 = "1daaf6d2a67a7ae01367af0c74766e1d",
   dir = "lunamark-99597c0770b7e4bcd0939a42b225b444c70f4e5e",
}

description = {
   summary = "General markup format converter using lpeg.",
   homepage = "https://jgm.github.io/lunamark",
   license = "MIT/X11",
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "none",
   install = {
      bin = {
         lunamark = "bin/lunamark",
         lunadoc = "bin/lunadoc",
      },
      lua = {
         lunamark = "lunamark.lua",
         ["lunamark.util"] = "lunamark/util.lua",
         ["lunamark.entities"] = "lunamark/entities.lua",
         ["lunamark.writer"] = "lunamark/writer.lua",
         ["lunamark.writer.generic"] = "lunamark/writer/generic.lua",
         ["lunamark.writer.xml"] = "lunamark/writer/xml.lua",
         ["lunamark.writer.docbook"] = "lunamark/writer/docbook.lua",
         ["lunamark.writer.html"] = "lunamark/writer/html.lua",
         ["lunamark.writer.html5"] = "lunamark/writer/html5.lua",
         ["lunamark.writer.dzslides"] = "lunamark/writer/dzslides.lua",
         ["lunamark.writer.tex"] = "lunamark/writer/tex.lua",
         ["lunamark.writer.latex"] = "lunamark/writer/latex.lua",
         ["lunamark.writer.context"] = "lunamark/writer/context.lua",
         ["lunamark.writer.groff"] = "lunamark/writer/groff.lua",
         ["lunamark.writer.man"] = "lunamark/writer/man.lua",
         ["lunamark.reader"] = "lunamark/reader.lua",
         ["lunamark.reader.markdown"] = "lunamark/reader/markdown.lua",
      },
   },
}
