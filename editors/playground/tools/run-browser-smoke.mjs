#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const [url] = process.argv.slice(2);
if (!url) throw new Error("usage: run-browser-smoke.mjs URL");

const chrome = process.env.CHROME || "google-chrome";
const profile = mkdtempSync(path.join(os.tmpdir(), "nupp-chromium-"));
const child = spawn(chrome, [
  "--headless=new",
  "--no-sandbox",
  "--disable-gpu",
  "--no-first-run",
  "--no-default-browser-check",
  `--user-data-dir=${profile}`,
  "--remote-debugging-port=0",
  url,
], {stdio: ["ignore", "ignore", "pipe"]});

const deadline = Date.now() + 90000;
let browserSocket;
let stderr = "";
child.stderr.setEncoding("utf8");
child.stderr.on("data", (chunk) => {
  stderr += chunk;
  const match = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
  if (match) browserSocket = match[1];
});

const pause = () => new Promise((resolve) => setTimeout(resolve, 100));

async function waitFor(test, description) {
  while (Date.now() < deadline) {
    const result = await test();
    if (result) return result;
    await pause();
  }
  throw new Error(`timed out waiting for ${description}`);
}

function evaluate(socket, expression, id) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.removeEventListener("message", receive);
      reject(new Error("timed out waiting for Chrome DevTools evaluation"));
    }, 5000);
    const receive = (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== id) return;
      clearTimeout(timer);
      socket.removeEventListener("message", receive);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result.result.value);
    };
    socket.addEventListener("message", receive);
    socket.send(JSON.stringify({
      id,
      method: "Runtime.evaluate",
      params: {expression, returnByValue: true},
    }));
  });
}

try {
  await waitFor(() => browserSocket, "Chrome DevTools");
  const port = new URL(browserSocket).port;
  const page = await waitFor(async () => {
    try {
      const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      return pages.find((candidate) => candidate.url === url);
    } catch {
      return null;
    }
  }, "the smoke page");

  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, {once: true});
    socket.addEventListener("error", reject, {once: true});
  });
  let request = 0;
  const status = await waitFor(async () => {
    const value = await evaluate(
      socket,
      "document.querySelector('#result')?.dataset.status",
      ++request,
    );
    return value && value !== "running" ? value : null;
  }, "the browser smoke result");
  const text = await evaluate(
    socket,
    "document.querySelector('#result')?.textContent",
    ++request,
  );
  socket.close();
  const result = JSON.parse(text);
  if (status !== "passed" || !result.ok) {
    throw new Error(result.error || `browser smoke ended with ${status}`);
  }
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
} finally {
  if (child.exitCode === null) {
    child.kill("SIGTERM");
    await Promise.race([
      new Promise((resolve) => child.once("exit", resolve)),
      delay(5000),
    ]);
  }
  if (child.exitCode === null) child.kill("SIGKILL");
  rmSync(profile, {recursive: true, force: true, maxRetries: 20, retryDelay: 100});
}
