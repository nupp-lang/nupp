const output = document.querySelector("#result");

async function supportsSimd() {
  const manifestResponse = await fetch("./simd/nupp-browser-app.json");
  if (!manifestResponse.ok) throw new Error("cannot load the SIMD manifest");
  const manifest = await manifestResponse.json();
  const side = manifest.sideModules.find((unit) => unit.tier === "simd128");
  if (!side) throw new Error("the SIMD package contains no SIMD128 kernel");
  const response = await fetch("./simd/" + side.file);
  if (!response.ok) throw new Error("cannot load the SIMD kernel");
  return WebAssembly.validate(await response.arrayBuffer());
}

try {
  const forceScalar = new URL(location.href).searchParams.has("scalar");
  const selected = !forceScalar && await supportsSimd() ? "simd" : "scalar";
  const application = await import("./" + selected + "/nupp-browser-app.mjs");
  const result = await application.ready;
  output.dataset.status = "passed";
  output.textContent = JSON.stringify({ok: true, selected, result}, null, 2);
} catch (error) {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({
    ok: false,
    error: String(error && error.stack || error),
  }, null, 2);
}
