"use strict";

const fs = require("fs");
const path = require("path");

const extensionRoot = path.resolve(__dirname, "..");
const images = path.resolve(extensionRoot, "../../docs/public/images");

// Keep standalone copies of the extension usable while making the repository
// build consume the canonical Nupp artwork whenever the docs tree is present.
// The marketplace entry needs a raster icon, so the rendered PNG travels with
// the SVG the file explorer uses.
const copies = [
  ["nupp.svg", "nupp.svg"],
  ["nupp-icon.png", "icon.png"],
];

for (const [from, to] of copies) {
  const source = path.join(images, from);
  if (fs.existsSync(source)) {
    fs.copyFileSync(source, path.join(extensionRoot, to));
  }
}
