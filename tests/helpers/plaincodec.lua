local native = rawget(_G, "__nupp_plain_codec")
if native then
    return native
end
local loaded, legacy = pcall(require, "nupp.serde.internal.binarycodec")

return loaded and legacy or require("nupp.compiler.project.plaincodec")
