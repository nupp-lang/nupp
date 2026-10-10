return {
    include = {"src"},
    build = {
        kind = "component",
        description = "The native host channel workloads, driven by bench.c",
        entries = {"framebench"},
        exports = {
            "framebench.setup",
            "framebench.pushPointerMove",
            "framebench.iterate",
            "framebench.renderPacket",
            "framebench.nextImageCommand",
            "framebench.nextCapture",
            "framebench.nextModelUpload",
            "framebench.crashed",
            "framebench.frame",
            "framebench.startLoop",
            "framebench.pollLoop",
            "framebench.received",
        },
    },
}
