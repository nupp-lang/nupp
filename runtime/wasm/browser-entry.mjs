import { runPackagedNuppWasmApp } from "./app-runtime.mjs";

export const ready = runPackagedNuppWasmApp(
  new URL("./nupp-browser-app.json", import.meta.url),
);

export default ready;
