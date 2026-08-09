#!/usr/bin/env node
// Bundles the playground into dist/. See README.md for what each piece is.
import { build, context } from "esbuild";
import { mkdirSync, copyFileSync, cpSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(root, "dist");
const watch = process.argv.includes("--watch");

mkdirSync(dist, { recursive: true });

// fengari statically requires a few Node built-ins and CLI-only helper
// packages, but only inside `if (typeof process !== "undefined")` branches
// (Node-only extras: real filesystem I/O, dynamic library loading, stdin
// prompts) — its own accommodation for running outside Node. Defining
// `typeof process` as the literal string "undefined" is the same technique
// fengari-web's own webpack config uses to fold those branches away, which
// drops the otherwise-unresolvable requires inside them along with it.
// The alias below is a backstop in case any such require survives folding.
const NODE_ONLY = ["fs", "path", "os", "child_process", "crypto", "readline-sync", "tmp"];

const shared = {
  bundle: true,
  format: "esm",
  target: "es2022",
  sourcemap: true,
  platform: "browser",
  loader: { ".lua": "text", ".nupp": "text" },
  alias: Object.fromEntries(NODE_ONLY.map((name) => [name, path.join(root, "src/empty-shim.js")])),
  // esbuild's constant folding understands `typeof x` against a define'd
  // literal `undefined`, so this alone makes every
  // `typeof process === "undefined"` branch in fengari fold statically —
  // the same effect fengari-web's webpack config gets from a `typeof`-keyed
  // DefinePlugin entry, which esbuild's define doesn't accept directly.
  define: {
    process: "undefined",
    // luaconf.js's very first line reads process.env.FENGARICONF
    // unconditionally (not behind a typeof guard), so replacing bare
    // `process` alone still leaves `undefined.env` there.
    "process.env.FENGARICONF": "undefined",
  },
  logLevel: "info",
};

async function run() {
  const appOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/app.js")],
    outfile: path.join(dist, "app.js"),
  };
  const workerOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/worker.js")],
    outfile: path.join(dist, "worker.js"),
  };

  if (watch) {
    const appCtx = await context(appOpts);
    const workerCtx = await context(workerOpts);
    await Promise.all([appCtx.watch(), workerCtx.watch()]);
    console.log("watching for changes…");
  } else {
    await Promise.all([build(appOpts), build(workerOpts)]);
  }

  cpSync(path.join(root, "static"), dist, { recursive: true });

  const repoRoot = path.join(root, "../..");
  const bootstrapSrc = path.join(repoRoot, "bootstrap/nupp.lua");
  if (!existsSync(bootstrapSrc)) {
    throw new Error(`expected ${bootstrapSrc} — run from a full checkout`);
  }
  // See tools/patch-bootstrap-for-browser.lua for why this needs real
  // LuaJIT (not just any Lua) and this project's own rock tree: it loads
  // bootstrap/nupp.lua to reach the bootstrap compiler's own lexer, the same
  // way bin/nupp does.
  const rocks = path.join(repoRoot, ".rocks");
  execFileSync(
    "luajit",
    [path.join(root, "tools/patch-bootstrap-for-browser.lua"), bootstrapSrc, path.join(dist, "nupp-bootstrap.lua")],
    {
      cwd: repoRoot,
      stdio: "inherit",
      env: {
        ...process.env,
        LUA_PATH: `${rocks}/share/lua/5.1/?.lua;${rocks}/share/lua/5.1/?/init.lua;;`,
        LUA_CPATH: `${rocks}/lib/lua/5.1/?.so;;`,
      },
    }
  );

  copyFileSync(path.join(root, "README.md"), path.join(dist, "README.md"));
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
