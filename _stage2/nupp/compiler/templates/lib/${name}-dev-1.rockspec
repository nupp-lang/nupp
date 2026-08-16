rockspec_format = "3.0"
package = "${name}"
version = "dev-1"

source = {
   url = "git+https://example.invalid/${name}.git",
}

description = {
   summary = "A Nupp library",
   license = "MIT",
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "builtin",
   modules = {
      ["${moduleName}"] = "build/${moduleName}.lua",
   },
   copy_directories = { "nupp" },
}
