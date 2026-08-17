"use strict";

const fs = require("fs");
const path = require("path");
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

const clients = new Map();
let nextClientId = 1;
let traceDiagnostics;

function clientForDocument(document) {
  const folder = vscode.workspace.getWorkspaceFolder(document.uri);
  return folder && clients.get(folder.uri.toString());
}

function asRange(range) {
  return new vscode.Range(
    range.start.line,
    range.start.character,
    range.end.line,
    range.end.character
  );
}

async function checkFunctionForTraceBlockers(target) {
  const editor = vscode.window.activeTextEditor;
  const document = target && target.uri
    ? await vscode.workspace.openTextDocument(target.uri)
    : editor && editor.document;
  const position = target && target.position
    ? target.position
    : editor && editor.selection.active;
  if (!document || document.languageId !== "nupp" || !position) {
    void vscode.window.showInformationMessage("Open a Nupp function to check it for JIT trace blockers.");
    return;
  }
  const running = clientForDocument(document);
  if (!running) {
    void vscode.window.showErrorMessage("No Nupp language server is running for this file.");
    return;
  }
  const uri = document.uri;
  traceDiagnostics.delete(uri);
  let result;
  try {
    result = await running.client.sendRequest("$/nupp/traceCheck", {
      textDocument: { uri: uri.toString() },
      position
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(`JIT trace check failed: ${detail}`);
    return;
  }
  if (!result) {
    void vscode.window.showInformationMessage("No checked Nupp function contains the cursor.");
    return;
  }
  const diagnostics = (result.findings || []).map((finding) => {
    const severity = finding.class === "blocker"
      ? vscode.DiagnosticSeverity.Error
      : finding.class === "risk"
        ? vscode.DiagnosticSeverity.Warning
        : vscode.DiagnosticSeverity.Information;
    const path = finding.callPath && finding.callPath.length > 1
      ? ` via ${finding.callPath.join(" → ")}`
      : "";
    const diagnostic = new vscode.Diagnostic(
      finding.range ? asRange(finding.range) : asRange(result.range),
      `${finding.reason}${path}: ${finding.message || finding.class}`,
      severity
    );
    diagnostic.code = finding.reason;
    diagnostic.source = "Nupp JIT Check";
    return diagnostic;
  });
  traceDiagnostics.set(uri, diagnostics);
  let summary;
  if (diagnostics.length === 0) {
    summary = `${result.name}: no catalogued unconditional trace blockers or conditional risks.`;
  } else {
    summary = `${result.name}: ${diagnostics.length} JIT trace finding${diagnostics.length === 1 ? "" : "s"}.`;
  }
  const add = result.addContract ? "Add @jit contract" : undefined;
  const choice = add
    ? await vscode.window.showInformationMessage(summary, add)
    : await vscode.window.showInformationMessage(summary);
  if (choice === add) {
    const edit = new vscode.WorkspaceEdit();
    edit.insert(uri, asRange(result.addContract.range).start, result.addContract.newText);
    await vscode.workspace.applyEdit(edit);
  }
}

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
  traceDiagnostics = vscode.languages.createDiagnosticCollection("nupp-jit-check");
  await Promise.all(
    (vscode.workspace.workspaceFolders || []).map(
      (folder) => startClient(context, folder)
    )
  );

  context.subscriptions.push(
    traceDiagnostics,
    vscode.commands.registerCommand(
      "nupp.checkFunctionForJitTraceBlockers",
      checkFunctionForTraceBlockers
    ),
    vscode.commands.registerCommand("nupp.restartLanguageServer", async () => {
      await restartClients(context);
      void vscode.window.showInformationMessage("Nupp language server restarted.");
    }),
    vscode.languages.registerCodeActionsProvider(
      { language: "nupp", scheme: "file" },
      {
        async provideCodeActions(document, range) {
          const running = clientForDocument(document);
          if (!running) {
            return [];
          }
          const result = await running.client.sendRequest("$/nupp/traceCheck", {
            textDocument: { uri: document.uri.toString() },
            position: range.start
          });
          if (!result) {
            return [];
          }
          const action = new vscode.CodeAction(
            "Check function for JIT trace blockers",
            vscode.CodeActionKind.Empty
          );
          action.command = {
            command: "nupp.checkFunctionForJitTraceBlockers",
            title: action.title,
            arguments: [{ uri: document.uri, position: range.start }]
          };
          return [action];
        }
      }
    ),
    vscode.workspace.onDidChangeTextDocument((event) => {
      traceDiagnostics.delete(event.document.uri);
    }),
    vscode.workspace.onDidCloseTextDocument((document) => {
      traceDiagnostics.delete(document.uri);
    }),
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
