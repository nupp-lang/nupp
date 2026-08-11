"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const jsonFiles = [
  "package.json",
  "language-configuration.json",
  "syntaxes/nupp.tmLanguage.json"
];

const parsedJson = new Map();
for (const relative of jsonFiles) {
  parsedJson.set(
    relative,
    JSON.parse(fs.readFileSync(path.join(root, relative), "utf8"))
  );
}

const languageConfig = parsedJson.get("language-configuration.json");
new RegExp(languageConfig.wordPattern);
for (const pattern of Object.values(languageConfig.indentationRules)) {
  new RegExp(pattern);
}

const manifest = require(path.join(root, "package.json"));
if (manifest.icon !== "icon.png") {
  throw new Error("extension icon must be icon.png");
}
const icon = fs.readFileSync(path.join(root, manifest.icon));
if (icon.toString("ascii", 1, 4) !== "PNG") {
  throw new Error("extension icon must be a PNG");
}
const iconWidth = icon.readUInt32BE(16);
const iconHeight = icon.readUInt32BE(20);
if (iconWidth !== iconHeight || iconWidth < 128) {
  throw new Error("extension icon must be square and at least 128 pixels");
}
const language = manifest.contributes.languages.find(({ id }) => id === "nupp");
if (!language || language.icon?.light !== "./nupp.svg"
  || language.icon?.dark !== "./nupp.svg") {
  throw new Error("NUPP language must use nupp.svg for light and dark themes");
}
const languageIcon = fs.readFileSync(path.join(root, "nupp.svg"), "utf8");
if (!languageIcon.startsWith("<?xml") || !languageIcon.includes("<svg")) {
  throw new Error("NUPP language icon must be an SVG");
}
const launchSettings = manifest.contributes.configuration.properties;
for (const name of [
  "nupp.serverPath",
  "nupp.serverArgs",
  "nupp.serverCwd",
  "nupp.serverEnvironment"
]) {
  if (!launchSettings[name]) {
    throw new Error(`missing launch setting: ${name}`);
  }
}
for (const relative of manifest.files) {
  if (!fs.existsSync(path.join(root, relative))) {
    throw new Error(`package file does not exist: ${relative}`);
  }
}

for (const relative of ["extension.js", "dist/extension.js"]) {
  execFileSync(process.execPath, ["--check", path.join(root, relative)], {
    stdio: "inherit"
  });
}
