return {
    include = {"src"},
    build = {entries = {"nupp.tests.loader", "nupp.tests.loadermissing"}, layoutTarget = "aarch64-apple-darwin"},
}
