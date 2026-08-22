const output = document.querySelector("#result");
const expected = new URL(location.href).searchParams.get("expect") || "none";

try {
  const manifest = await (await fetch("./nupp-browser-app.json")).json();
  const tiers = manifest.sideModules.map((unit) => unit.tier);
  const expectedTier = expected === "runtime-error" ? "none" : expected === "missing" ? "scalar" : expected;
  if (expectedTier === "none" ? tiers.length !== 0 : !tiers.includes(expectedTier)) {
    throw new Error(`expected ${expected} side modules, found ${tiers.join(",") || "none"}`);
  }
  const started = performance.now();
  const application = await import("./nupp-browser-app.mjs");
  let failure;
  try {
    await application.ready;
  } catch (error) {
    failure = String(error);
  }
  if (expected === "runtime-error") {
    if (!failure?.includes("intentional browser failure")) {
      throw new Error(`expected the application runtime error, found ${failure || "success"}`);
    }
  } else if (expected === "missing") {
    if (!failure?.includes("HTTP 404")) {
      throw new Error(`expected a missing side-module error, found ${failure || "success"}`);
    }
  } else if (failure) {
    throw new Error(failure);
  }
  const result = {ok: true, case: expected, elapsedMs: performance.now() - started, tiers};
  output.dataset.status = "passed";
  output.textContent = JSON.stringify(result);
  document.title = `PASS — Nupp browser application (${expected})`;
} catch (error) {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({ok: false, case: expected, error: String(error)});
  document.title = `FAIL — Nupp browser application (${expected})`;
}
