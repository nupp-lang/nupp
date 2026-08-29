const output = document.querySelector("#result");
const expected = new URL(location.href).searchParams.get("expect") || "none";

try {
  const manifest = await (await fetch("./nupp-browser-app.json")).json();
  const tiers = manifest.sideModules.map((unit) => unit.tier);
  const tierFor = {
    "runtime-error": "none",
    http: "none",
    platform: "none",
    cancel: "none",
    derive: "none",
    workers: "none",
    missing: "scalar",
    "workers-scalar": "scalar",
    "workers-simd": "simd128",
  };
  const expectedTier = tierFor[expected] || expected;
  if (expectedTier === "none" ? tiers.length !== 0 : !tiers.includes(expectedTier)) {
    throw new Error(`expected ${expected} side modules, found ${tiers.join(",") || "none"}`);
  }
  const started = performance.now();
  const application = await import("./nupp-browser-app.mjs");
  let failure;
  let returned;
  try {
    if (expected === "cancel") setTimeout(() => application.cancel(), 0);
    returned = await application.ready;
  } catch (error) {
    failure = String(error);
  }
  if (expected === "cancel") {
    if (!failure?.includes("cancel")) {
      throw new Error(`expected application cancellation, found ${failure || "success"}`);
    }
  } else if (expected === "runtime-error") {
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
  if (expected === "http") {
    const document = JSON.parse(returned.body);
    if (returned.status !== 200 || document.message !== "hello from Nupp over fetch" ||
        returned.contentType !== "application/octet-stream") {
      throw new Error(`unexpected structured HTTP result: ${JSON.stringify(returned)}`);
    }
  }
  if (expected === "workers") {
    // Every question the application asked of its lanes, answered where it ran.
    const failed = Object.keys(returned).filter((name) => returned[name] === false);
    if (failed.length > 0) {
      throw new Error(`browser worker tasks reported ${failed.join(", ")} false`);
    }
    if (returned.failedStatus !== "failed" || returned.cancelledStatus !== "cancelled") {
      throw new Error(`unexpected worker task statuses: ${JSON.stringify(returned)}`);
    }
    if (returned.queueBound !== 1024) {
      throw new Error(`expected the 1024-task queue bound, found ${returned.queueBound}`);
    }
    // The task scope's deadline reached the lane and the checkpoint is where it landed,
    // rather than the whole run being abandoned or the child finishing its ten seconds.
    if (returned.deadlineOutcome !== "cancelled" || returned.deadlineMs > 5000) {
      throw new Error(`unexpected worker deadline result: ${JSON.stringify(returned)}`);
    }
  }
  if (expected === "workers-scalar" || expected === "workers-simd") {
    if (returned.kernelAgreed !== true || returned.tasks !== 8 || returned.values !== 64) {
      throw new Error(`unexpected worker kernel result: ${JSON.stringify(returned)}`);
    }
  }
  if (expected === "derive") {
    if (returned.encoded !== '{"sensor_id":7,"label":"intake","samples":[3,1,4]}' ||
        returned.debug !== 'Reading { id = 7, label = "intake", samples = {3, 1, 4} }' ||
        returned.roundTripped !== returned.debug || returned.defaultedLabel !== "unnamed" ||
        returned.missingRefused !== true || returned.repeated !== true) {
      throw new Error(`unexpected derive result: ${JSON.stringify(returned)}`);
    }
  }
  if (expected === "platform") {
    if (returned.elapsed < 0 || returned.randomBytes !== 32 || returned.stored !== "persisted" ||
        returned.sha256 !== "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ||
        returned.hmac !== "9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab" ||
        !/^[0-9a-f-]{36}$/.test(returned.uuid4) || !/^[0-9a-f-]{36}$/.test(returned.uuid7)) {
      throw new Error(`unexpected browser platform result: ${JSON.stringify(returned)}`);
    }
  }
  const result = {ok: true, case: expected, elapsedMs: performance.now() - started, tiers, returned};
  output.dataset.status = "passed";
  output.textContent = JSON.stringify(result);
  document.title = `PASS — Nupp browser application (${expected})`;
} catch (error) {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({ok: false, case: expected, error: String(error)});
  document.title = `FAIL — Nupp browser application (${expected})`;
}
