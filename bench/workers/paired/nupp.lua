return {
    include = {"src"},
    build = {kind = "binary", stub = "nupp", entries = {"nupp.internal.speedmain"}, output = "paired"}
}
