"use strict";

const fs = require("fs");
const path = require("path");

const extensionRoot = path.resolve(__dirname, "..");
const source = path.resolve(extensionRoot, "../../docs/public/images/nupp.svg");
const target = path.join(extensionRoot, "nupp.svg");

// Keep standalone copies of the extension usable while making the repository
// build consume the canonical Nupp artwork whenever the docs tree is present.
if (fs.existsSync(source)) {
  fs.copyFileSync(source, target);
}
