"use strict";

const fs = require("fs");
const path = require("path");
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

const clients = new Map();
let nextClientId = 1;

function expandSetting(value, root) {
  return value
    .replaceAll("${workspaceFolder}", root)
    .replace(/\$\{env:([^}]+)\}/g, (match, name) => process.env[name] || "");
}

function serverLaunch(context, folder) {
  const root = folder.uri.fsPath;
  const config = vscode.workspace.getConfiguration("nupp", folder.uri);
  const configuredPath = config.get("serverPath", "").trim();
  let command;
  if (configuredPath) {
    command = expandSetting(configuredPath, root);
    if (!path.isAbsolute(command)
      && (command.includes("/") || command.includes("\\"))) {
      command = path.resolve(root, command);
    }
  } else {
    const checkoutCommand = path.resolve(context.extensionPath, "../../bin/nupp");
    command = fs.existsSync(checkoutCommand) ? checkoutCommand : "nupp";
  }

  const configuredArgs = config.get("serverArgs", ["lsp", "serve", "${workspaceFolder}"]);
  const args = (Array.isArray(configuredArgs) ? configuredArgs : [])
    .map((arg) => expandSetting(String(arg), root));
  const configuredCwd = expandSetting(
    config.get("serverCwd", "${workspaceFolder}"),
    root
  );
  const cwd = path.isAbsolute(configuredCwd)
    ? configuredCwd
    : path.resolve(root, configuredCwd);
  const configuredEnvironment = config.get("serverEnvironment", {});
  const env = { ...process.env };
  for (const [name, value] of Object.entries(
    configuredEnvironment && typeof configuredEnvironment === "object"
      ? configuredEnvironment
      : {}
  )) {
    env[name] = expandSetting(String(value), root);
  }

  return { command, args, cwd, env };
}

async function startClient(context, folder) {
  const key = folder.uri.toString();
  if (clients.has(key) || folder.uri.scheme !== "file") {
    return;
   }

  const launch = serverLaunch(context, folder);
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(folder, "**/*.nupp")
  );
  const client = new LanguageClient(
    `nupp-${nextClientId++}`,
    `Nupp (${folder.name})`,
    {
      command: launch.command,
      args: launch.args,
      options: { cwd: launch.cwd, env: launch.env }
    },
    {
      documentSelector: [
        {
          scheme: "file",
          language: "nupp",
          pattern: new vscode.RelativePattern(folder, "**/*.nupp")
        }
      ],
      synchronize: { fileEvents: watcher },
      workspaceFolder: folder,
      diagnosticCollectionName: "nupp",
      outputChannelName: `Nupp Language Server (${folder.name})`
    }
  );

  clients.set(key, { client, watcher });
  try {
    await client.start();
  } catch (error) {
    clients.delete(key);
    await client.dispose();
    watcher.dispose();
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(
      `Could not start the Nupp language server (${launch.command}): ${detail}`
    );
  }
}

async function stopClient(folder) {
  const key = folder.uri.toString();
  const running = clients.get(key);
  if (!running) {
    return;
  }
  clients.delete(key);
  await running.client.stop();
  running.watcher.dispose();
}

async function restartClients(context) {
  const running = Array.from(clients.values());
  clients.clear();
  await Promise.allSettled(running.map(({ client }) => client.stop()));
  running.forEach(({ watcher }) => watcher.dispose());
  await Promise.all(
    (vscode.workspace.workspaceFolders || []).map(
      (folder) => startClient(context, folder)
    )
  );
}

async function activate(context) {
  await Promise.all(
    (vscode.workspace.workspaceFolders || []).map(
      (folder) => startClient(context, folder)
    )
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(async (event) => {
      await Promise.allSettled(event.removed.map(stopClient));
      await Promise.all(event.added.map((folder) => startClient(context, folder)));
    }),
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      const launchChanged = [
        "nupp.serverPath",
        "nupp.serverArgs",
        "nupp.serverCwd",
        "nupp.serverEnvironment"
      ].some((setting) => event.affectsConfiguration(setting));
      if (launchChanged) {
        await restartClients(context);
      }
    })
  );
}

async function deactivate() {
  const running = Array.from(clients.values());
  clients.clear();
  await Promise.allSettled(running.map(({ client }) => client.stop()));
  running.forEach(({ watcher }) => watcher.dispose());
}

module.exports = { activate, deactivate };
