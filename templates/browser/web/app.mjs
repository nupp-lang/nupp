const output = document.querySelector("#result");

try {
  const application = await import("./nupp-browser-app.mjs");
  const result = await application.ready;
  output.dataset.status = "passed";
  output.textContent = JSON.stringify({ok: true, result}, null, 2);
} catch (error) {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({
    ok: false,
    error: String(error && error.stack || error),
  }, null, 2);
}
