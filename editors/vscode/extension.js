"use strict";

const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

const clients = new Map();
let nextClientId = 1;
let traceDiagnostics;

// Generated artifacts open as read-only documents under their own scheme. The
// source they came from travels in the query string, because a virtual document
// belongs to no workspace folder and `clientForDocument` has nothing else to
// find a server with.
const GENERATED_SCHEME = "nupp-generated";
const generated = new Map();
let generatedEvents;

function clientForUri(uri) {
  const folder = vscode.workspace.getWorkspaceFolder(uri);
  return folder && clients.get(folder.uri.toString());
}

function clientForDocument(document) {
  return clientForUri(originOf(document.uri));
}

// A generated document answers for the file it was made from; every other
// document answers for itself.
function originOf(uri) {
  if (uri.scheme !== GENERATED_SCHEME) {
    return uri;
  }
  const source = new URLSearchParams(uri.query).get("source");
  return source ? vscode.Uri.parse(source) : uri;
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

async function migrateAnnotatedLua(target) {
  const editor = vscode.window.activeTextEditor;
  const document = target && target.uri
    ? await vscode.workspace.openTextDocument(target.uri)
    : editor && editor.document;
  if (!document || document.uri.scheme !== "file"
    || !document.uri.fsPath.endsWith(".lua")) {
    void vscode.window.showInformationMessage("Open an annotated .lua file to migrate it to Nupp.");
    return;
  }
  const running = clientForDocument(document);
  if (!running) {
    void vscode.window.showErrorMessage("No Nupp migration service is running for this file.");
    return;
  }
  const dialect = vscode.workspace
    .getConfiguration("nupp", document.uri)
    .get("luaMigrationDialect", "auto");
  let plan;
  try {
    plan = await running.client.sendRequest("$/nupp/migrateAnnotatedLua", {
      textDocument: { uri: document.uri.toString() },
      text: document.getText(),
      dialect
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(`Annotated Lua migration failed: ${detail}`);
    return;
  }
  if (!plan || !plan.ok) {
    void vscode.window.showErrorMessage(
      `Annotated Lua migration failed: ${plan?.error || "no migration plan was returned"}`
    );
    return;
  }
  const destination = vscode.Uri.parse(plan.destinationUri);
  try {
    await vscode.workspace.fs.stat(destination);
    void vscode.window.showErrorMessage(`Migration destination already exists: ${destination.fsPath}`);
    return;
  } catch {
    // Missing is the required state: migration never replaces a destination.
  }
  const warningCount = (plan.warnings || []).length;
  const confirm = await vscode.window.showWarningMessage(
    `Create ${path.basename(destination.fsPath)} and remove ${path.basename(document.uri.fsPath)}`
      + (warningCount ? ` (${warningCount} recoverable warning${warningCount === 1 ? "" : "s"})?` : "?"),
    { modal: true },
    "Migrate"
  );
  if (confirm !== "Migrate") {
    return;
  }
  const edit = new vscode.WorkspaceEdit();
  edit.createFile(destination, { ignoreIfExists: false, overwrite: false });
  edit.insert(destination, new vscode.Position(0, 0), plan.text);
  edit.deleteFile(document.uri, { ignoreIfNotExists: false, recursive: false });
  if (!await vscode.workspace.applyEdit(edit)) {
    void vscode.window.showErrorMessage("VS Code could not apply the annotated Lua migration.");
    return;
  }
  const migrated = await vscode.workspace.openTextDocument(destination);
  await vscode.window.showTextDocument(migrated);
}

const ARTIFACT_LABELS = { lua: "Generated Lua", bytecode: "Bytecode" };

// A generated document's URI. The path decides the tab title and, for Lua, the
// extension VS Code picks a highlighter from; the query carries everything the
// commands need to refresh or compare it without re-deriving anything.
function generatedUri(sourceUri, kind, optLevel) {
  const base = path.basename(sourceUri.fsPath);
  const suffix = kind === "lua" ? ".lua" : ".bc";
  const query = new URLSearchParams({
    source: sourceUri.toString(),
    kind,
    optLevel: String(optLevel)
  });
  return vscode.Uri.parse(
    `${GENERATED_SCHEME}:/${base}.O${optLevel}${suffix}?${query.toString()}`
  );
}

async function resolveArtifact(sourceUri, kind, optLevel) {
  const running = clientForUri(sourceUri);
  if (!running) {
    throw new Error("No Nupp language server is running for this file.");
  }
  // The server answers from its own copy of the buffer, so the document has to
  // be open for it to have one.
  await vscode.workspace.openTextDocument(sourceUri);
  return running.client.sendRequest("$/nupp/artifact", {
    textDocument: { uri: sourceUri.toString() },
    kind,
    optLevel
  });
}

// Resolves into the cache the content provider reads, and tells VS Code the
// document changed so an already-open tab re-reads it.
async function refreshArtifact(uri) {
  const query = new URLSearchParams(uri.query);
  const sourceUri = vscode.Uri.parse(query.get("source"));
  const kind = query.get("kind");
  const optLevel = Number(query.get("optLevel")) || 0;
  const artifact = await resolveArtifact(sourceUri, kind, optLevel);
  generated.set(uri.toString(), artifact);
  generatedEvents.fire(uri);
  return artifact;
}

async function openArtifact(sourceUri, kind, optLevel, options) {
  const uri = generatedUri(sourceUri, kind, optLevel);
  let artifact;
  try {
    artifact = await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Window,
        title: `Nupp: resolving ${ARTIFACT_LABELS[kind] || kind}`
      },
      () => refreshArtifact(uri)
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(`Could not resolve the artifact: ${detail}`);
    return undefined;
  }
  if (!artifact.available) {
    const reason = artifact.unavailable || {};
    // An unavailable artifact is a sentence, not an empty tab. A file that
    // checks can still fail to lower, and saying which is the whole point.
    void vscode.window.showWarningMessage(
      `${ARTIFACT_LABELS[kind] || kind} is not available: ${reason.detail || reason.reason}`
    );
    return undefined;
  }
  const document = await vscode.workspace.openTextDocument(uri);
  if (artifact.languageId) {
    await vscode.languages.setTextDocumentLanguage(document, artifact.languageId)
      .then(undefined, () => undefined);
  }
  // A line-aligned artifact only lines up with the source once the rows a
  // multi-instruction line needed are folded away, so it opens folded. Folding
  // acts on the focused editor, so focus moves there and comes back.
  const collapse = artifact.mapping && artifact.mapping.kind === "lines-collapsible";
  const shown = await vscode.window.showTextDocument(document, {
    viewColumn: vscode.ViewColumn.Beside,
    preview: false,
    preserveFocus: !collapse,
    ...(options || {})
  });
  if (collapse) {
    await vscode.commands.executeCommand("editor.foldAll").then(undefined, () => undefined);
    const origin = vscode.window.visibleTextEditors.find(
      (candidate) => candidate.document.uri.toString() === sourceUri.toString()
    );
    if (origin) {
      await vscode.window.showTextDocument(origin.document, {
        viewColumn: origin.viewColumn,
        preview: false
      });
    }
  }
  void shown;
  return uri;
}

// Which generated line stands for a source line, and the other way round.
//
// `line-identity` is the Lua emitter's guarantee that it never changes the line
// count, so the answer is the line itself. A bytecode listing is a rendering and
// carries entries; a source line usually produced several, and the first of them
// is what a reader wants revealed.
function generatedLineFor(artifact, sourceLine) {
  if (!artifact || !artifact.mapping) {
    return undefined;
  }
  if (artifact.mapping.kind === "line-identity") {
    return sourceLine;
  }
  let best;
  for (const entry of artifact.mapping.entries || []) {
    if (entry.sourceLine === sourceLine && entry.role !== "synthetic") {
      best = best === undefined ? entry.generatedLine : Math.min(best, entry.generatedLine);
    }
  }
  return best;
}

function sourceLineFor(artifact, generatedLine) {
  if (!artifact || !artifact.mapping) {
    return undefined;
  }
  if (artifact.mapping.kind === "line-identity") {
    return generatedLine;
  }
  for (const entry of artifact.mapping.entries || []) {
    // Synthetic lines stand for compiler-owned work rather than for anything
    // the reader wrote, so selecting one reveals nothing rather than lying.
    if (entry.generatedLine === generatedLine && entry.role !== "synthetic") {
      return entry.sourceLine;
    }
  }
  return undefined;
}

function revealLine(editor, line) {
  const at = new vscode.Position(Math.max(0, line - 1), 0);
  editor.selection = new vscode.Selection(at, at);
  editor.revealRange(new vscode.Range(at, at), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}

// Selecting in either view reveals the matching line in the other. Guarded so
// that the reveal this performs does not come back as another selection.
let synchronizing = false;

function synchronizeSelection(event) {
  if (synchronizing) {
    return;
  }
  const document = event.textEditor.document;
  const line = event.selections[0].active.line + 1;
  if (document.uri.scheme === GENERATED_SCHEME) {
    const artifact = generated.get(document.uri.toString());
    const sourceLine = sourceLineFor(artifact, line);
    const sourceUri = originOf(document.uri).toString();
    const editor = vscode.window.visibleTextEditors.find(
      (candidate) => candidate.document.uri.toString() === sourceUri
    );
    if (editor && sourceLine !== undefined) {
      synchronizing = true;
      revealLine(editor, sourceLine);
      synchronizing = false;
    }
    return;
  }
  for (const editor of vscode.window.visibleTextEditors) {
    if (editor.document.uri.scheme !== GENERATED_SCHEME) {
      continue;
    }
    if (originOf(editor.document.uri).toString() !== document.uri.toString()) {
      continue;
    }
    const generatedLine = generatedLineFor(generated.get(editor.document.uri.toString()), line);
    if (generatedLine !== undefined) {
      synchronizing = true;
      revealLine(editor, generatedLine);
      synchronizing = false;
    }
  }
}

function activeNuppUri(target) {
  if (target && target.uri) {
    return target.uri instanceof vscode.Uri ? target.uri : vscode.Uri.parse(String(target.uri));
  }
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    return undefined;
  }
  const origin = originOf(editor.document.uri);
  return origin.fsPath.endsWith(".nupp") ? origin : undefined;
}

async function openGeneratedArtifact(kind, target) {
  const uri = activeNuppUri(target);
  if (!uri) {
    void vscode.window.showInformationMessage("Open a Nupp file to inspect what it compiles to.");
    return;
  }
  await openArtifact(uri, kind, artifactOptLevel(uri));
}

function artifactOptLevel(uri) {
  return vscode.workspace.getConfiguration("nupp", uri).get("artifactOptimizationLevel", 0);
}

// One entry point behind the lens, rather than a button per kind. The server
// says what it can produce here; most kinds do not apply to most functions, and
// a row of six buttons over every function would be five dead links.
async function inspectCompiledFunction(target) {
  const uri = activeNuppUri(target);
  if (!uri) {
    void vscode.window.showInformationMessage("Open a Nupp file to inspect what it compiles to.");
    return;
  }
  const running = clientForUri(uri);
  if (!running) {
    void vscode.window.showErrorMessage("No Nupp language server is running for this file.");
    return;
  }
  const position = target && target.position
    ? target.position
    : vscode.window.activeTextEditor && vscode.window.activeTextEditor.selection.active;
  let available;
  try {
    available = await running.client.sendRequest("$/nupp/artifacts", {
      textDocument: { uri: uri.toString() },
      position
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(`Could not list compiled artifacts: ${detail}`);
    return;
  }
  const items = (available.artifacts || []).map((entry) => ({
    label: entry.label,
    description: entry.scope === "function" ? target?.name : "whole file",
    kind: entry.kind
  }));
  if (items.length === 0) {
    void vscode.window.showInformationMessage("This server produces no artifacts for this file.");
    return;
  }
  const picked = await vscode.window.showQuickPick(items, {
    title: target && target.name ? `Inspect ${target.name}` : "Inspect compiled output",
    placeHolder: "What this compiles to"
  });
  if (!picked) {
    return;
  }
  const opened = await openArtifact(uri, picked.kind, artifactOptLevel(uri));
  // A function lens opened it, so put the reader at that function rather than
  // at the top of a file-sized artifact.
  if (opened && target && target.position) {
    const artifact = generated.get(opened.toString());
    const line = generatedLineFor(artifact, target.position.line + 1);
    const editor = vscode.window.visibleTextEditors.find(
      (candidate) => candidate.document.uri.toString() === opened.toString()
    );
    if (editor && line !== undefined) {
      revealLine(editor, line);
    }
  }
}

// The same artifact under two configurations, in VS Code's own diff.
async function compareGeneratedArtifacts(target) {
  const uri = activeNuppUri(target);
  if (!uri) {
    void vscode.window.showInformationMessage("Open a Nupp file to compare what it compiles to.");
    return;
  }
  const kind = await vscode.window.showQuickPick(
    Object.entries(ARTIFACT_LABELS).map(([value, label]) => ({ label, value })),
    { title: "Compare which artifact?" }
  );
  if (!kind) {
    return;
  }
  const levels = ["0", "1", "2"].map((value) => ({ label: `-O${value}`, value: Number(value) }));
  const left = await vscode.window.showQuickPick(levels, { title: "Compare from" });
  if (!left) {
    return;
  }
  const right = await vscode.window.showQuickPick(
    levels.filter((entry) => entry.value !== left.value),
    { title: "Compare to" }
  );
  if (!right) {
    return;
  }
  const leftUri = generatedUri(uri, kind.value, left.value);
  const rightUri = generatedUri(uri, kind.value, right.value);
  try {
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Window, title: `Nupp: resolving ${kind.label}` },
      async () => {
        await refreshArtifact(leftUri);
        await refreshArtifact(rightUri);
      }
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    void vscode.window.showErrorMessage(`Could not resolve the artifacts: ${detail}`);
    return;
  }
  await vscode.commands.executeCommand(
    "vscode.diff",
    leftUri,
    rightUri,
    `${kind.label}: -O${left.value} ↔ -O${right.value}`
  );
}

// ---------------------------------------------------------------------------
// Tests and coverage
// ---------------------------------------------------------------------------

function runNupp(launch, args) {
  return new Promise((resolve) => {
    execFile(
      launch.command,
      args,
      { cwd: launch.cwd, env: launch.env, maxBuffer: 64 * 1024 * 1024 },
      (error, stdout, stderr) => resolve({ error, stdout, stderr })
    );
  });
}

// Coverage arrives as one report over the whole project rather than per test, so
// the detail VS Code asks for later is held here until the next run replaces it.
const coverageDetail = new Map();

function fileCoverageFor(file, folder) {
  const uri = vscode.Uri.joinPath(folder.uri, file.path);
  const statements = new vscode.TestCoverageCount(file.lines.covered, file.lines.total);
  const branches = new vscode.TestCoverageCount(file.branches.covered, file.branches.total);
  const declarations = new vscode.TestCoverageCount(file.functions.covered, file.functions.total);
  return new vscode.FileCoverage(uri, statements, branches, declarations);
}

// Turns the report's sites into what VS Code renders in the gutter. Positions
// are lines: a site is counted where it starts, which is where the compiler
// records it and where a reader looks for it.
function detailedCoverageFor(file) {
  const details = [];
  for (const site of file.sites || []) {
    const line = Math.max(0, (site.line || 1) - 1);
    if (site.kind === "statement") {
      details.push(new vscode.StatementCoverage(site.count, new vscode.Position(line, 0)));
    } else if (site.kind === "branch") {
      details.push(
        new vscode.StatementCoverage(site.count, new vscode.Position(line, 0), [
          new vscode.BranchCoverage(site.trueCount || 0, new vscode.Position(line, 0), "true"),
          new vscode.BranchCoverage(site.falseCount || 0, new vscode.Position(line, 0), "false")
        ])
      );
    } else if (site.kind === "function") {
      const end = Math.max(line, (site.endLine || site.line || 1) - 1);
      details.push(
        new vscode.DeclarationCoverage(
          site.name || "<anonymous>",
          site.count,
          new vscode.Range(line, 0, end, 0)
        )
      );
    }
  }
  return details;
}

async function discoverSuites(controller, folder, launch) {
  const { error, stdout } = await runNupp(launch, ["test", "--list-suites"]);
  if (error) {
    return;
  }
  const item = controller.items.get(folder.uri.toString())
    || controller.createTestItem(folder.uri.toString(), folder.name, folder.uri);
  item.children.replace(
    stdout
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.includes(" "))
      .map((suite) => controller.createTestItem(`${folder.uri.toString()}/${suite}`, suite))
  );
  controller.items.add(item);
}

function selectedSuites(controller, request) {
  const suites = [];
  const consider = (item) => {
    if (item.children.size > 0) {
      item.children.forEach(consider);
    } else {
      suites.push(item);
    }
  };
  if (request.include) {
    request.include.forEach(consider);
  } else {
    controller.items.forEach(consider);
  }
  const excluded = new Set((request.exclude || []).map((item) => item.id));
  return suites.filter((item) => !excluded.has(item.id));
}

async function runTests(controller, folder, launch, request, token, withCoverage) {
  const run = controller.createTestRun(request);
  const suites = selectedSuites(controller, request);
  suites.forEach((item) => run.enqueued(item));
  const names = suites.map((item) => item.label);
  const reportDir = path.join(launch.cwd, "build", "reports", "coverage");
  const args = withCoverage
    ? ["test", "--coverage", "--coverage-out", reportDir, ...names]
    : ["test", "--json", ...names];
  suites.forEach((item) => run.started(item));
  const { error, stdout, stderr } = await runNupp(launch, args);
  if (token.isCancellationRequested) {
    run.end();
    return;
  }
  if (!withCoverage) {
    reportTestResults(run, suites, folder, stdout, stderr, error);
  } else if (error) {
    // A failing suite under coverage still produced a report; say what went
    // wrong and publish the report anyway rather than losing both.
    run.appendOutput(asTerminal(stderr || stdout));
    suites.forEach((item) => run.failed(item, new vscode.TestMessage("the coverage run failed")));
  } else {
    suites.forEach((item) => run.passed(item));
  }
  if (withCoverage) {
    await publishCoverage(run, folder, launch, reportDir);
  }
  run.end();
}

// `nupp test --json` prints one record for the whole run, with a `tests` array
// naming each case, the suite it belongs to, and where it is. Results are rolled
// up per suite rather than per case, because a suite is what was enqueued: the
// cases are not discovered until the run has already produced them.
function reportTestResults(run, suites, folder, stdout, stderr, error) {
  const record = lastJsonRecord(stdout);
  const bySuite = new Map(suites.map((item) => [item.label, item]));
  const outcomes = new Map();
  for (const test of (record && record.tests) || []) {
    const item = bySuite.get(test.suite);
    if (!item) {
      continue;
    }
    const outcome = outcomes.get(item) || { duration: 0, failures: [], ran: 0, skipped: 0 };
    outcome.duration += test.durationMs || 0;
    outcome.ran += 1;
    if (test.status === "failed") {
      // A failure says where the error came from, which is often not where the
      // test is written; prefer it, and fall back to the test's own position.
      const failure = test.failure || {};
      const message = new vscode.TestMessage(`${test.name}: ${failure.message || "failed"}`);
      const where = failure.file || test.file;
      const at = failure.file ? failure.line : test.line;
      if (where) {
        // The runner reports paths relative to the project it ran in.
        const file = path.isAbsolute(where)
          ? vscode.Uri.file(where)
          : vscode.Uri.joinPath(folder.uri, where);
        message.location = new vscode.Location(
          file,
          new vscode.Position(Math.max(0, (at || 1) - 1), 0)
        );
      }
      outcome.failures.push(message);
    } else if (test.status === "skipped") {
      outcome.skipped += 1;
    }
    outcomes.set(item, outcome);
  }
  if (outcomes.size === 0) {
    run.appendOutput(asTerminal(stderr || stdout));
    const message = new vscode.TestMessage(error ? "the test run failed" : "the run reported no tests");
    suites.forEach((item) => run.failed(item, message));
    return;
  }
  for (const item of suites) {
    const outcome = outcomes.get(item);
    if (!outcome) {
      run.skipped(item);
    } else if (outcome.failures.length > 0) {
      run.failed(item, outcome.failures, outcome.duration);
    } else if (outcome.skipped === outcome.ran) {
      run.skipped(item);
    } else {
      run.passed(item, outcome.duration);
    }
  }
}

// The runner writes progress before its record, so the record is the last line
// that parses as one.
function lastJsonRecord(stdout) {
  for (const line of stdout.split("\n").reverse()) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("{")) {
      continue;
    }
    try {
      return JSON.parse(trimmed);
    } catch {
      // Not the record: keep looking further back.
    }
  }
  return undefined;
}

function asTerminal(text) {
  return (text || "").replace(/\r?\n/g, "\r\n");
}

async function publishCoverage(run, folder, launch, reportDir) {
  const { error, stdout } = await runNupp(launch, [
    "test", "--coverage", "--report-json", "--coverage-out", reportDir
  ]);
  if (error) {
    run.appendOutput("Nupp: the coverage report could not be read\r\n");
    return;
  }
  let report;
  try {
    report = JSON.parse(stdout);
  } catch {
    run.appendOutput("Nupp: the coverage report was not valid JSON\r\n");
    return;
  }
  coverageDetail.clear();
  offerInlineCoverage();
  for (const file of report.files || []) {
    if (file.status === "non-executable") {
      continue;
    }
    const coverage = fileCoverageFor(file, folder);
    coverageDetail.set(coverage.uri.toString(), file);
    run.addCoverage(coverage);
  }
}

// The gutter is VS Code's own, but it only draws once inline coverage is on and
// that is a toggle with no readable state, so this cannot simply be switched on
// without risking switching it off. Offered once a session instead.
let offeredInlineCoverage = false;

function offerInlineCoverage() {
  if (offeredInlineCoverage) {
    return;
  }
  offeredInlineCoverage = true;
  const show = "Show it inline";
  void vscode.window
    .showInformationMessage("Nupp coverage is ready.", show)
    .then((choice) => {
      if (choice === show) {
        void vscode.commands.executeCommand("testing.coverageToggleInline");
      }
    });
}

function registerTestController(context, folder, launch) {
  const controller = vscode.tests.createTestController(
    `nupp-tests-${folder.uri.toString()}`,
    `Nupp (${folder.name})`
  );
  controller.resolveHandler = async (item) => {
    if (!item) {
      await discoverSuites(controller, folder, launch);
    }
  };
  controller.refreshHandler = () => discoverSuites(controller, folder, launch);
  controller.createRunProfile(
    "Run",
    vscode.TestRunProfileKind.Run,
    (request, token) => runTests(controller, folder, launch, request, token, false),
    true
  );
  const coverageProfile = controller.createRunProfile(
    "Coverage",
    vscode.TestRunProfileKind.Coverage,
    (request, token) => runTests(controller, folder, launch, request, token, true),
    true
  );
  // Per-file detail hangs off the profile, not the controller. VS Code asks for
  // it lazily, when something is actually going to draw a gutter, so the report
  // is turned into ranges once per file opened rather than once per run.
  coverageProfile.loadDetailedCoverage = async (_run, coverage) =>
    detailedCoverageFor(coverageDetail.get(coverage.uri.toString()) || { sites: [] });
  context.subscriptions.push(controller);
  void discoverSuites(controller, folder, launch);
  return controller;
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
  const watchers = ["**/*.nupp", "**/*.lua"].map((pattern) =>
    vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(folder, pattern))
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
      synchronize: { fileEvents: watchers },
      workspaceFolder: folder,
      diagnosticCollectionName: "nupp",
      outputChannelName: `Nupp Language Server (${folder.name})`
    }
  );

  clients.set(key, { client, watchers });
  try {
    await client.start();
  } catch (error) {
    clients.delete(key);
    await client.dispose();
    watchers.forEach((watcher) => watcher.dispose());
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
  running.watchers.forEach((watcher) => watcher.dispose());
}

async function restartClients(context) {
  const running = Array.from(clients.values());
  clients.clear();
  await Promise.allSettled(running.map(({ client }) => client.stop()));
  running.forEach(({ watchers }) => watchers.forEach((watcher) => watcher.dispose()));
  await Promise.all(
    (vscode.workspace.workspaceFolders || []).map(
      (folder) => startClient(context, folder)
    )
  );
}

async function activate(context) {
  traceDiagnostics = vscode.languages.createDiagnosticCollection("nupp-jit-check");
  generatedEvents = new vscode.EventEmitter();
  await Promise.all(
    (vscode.workspace.workspaceFolders || []).map(
      (folder) => startClient(context, folder)
    )
  );
  for (const folder of vscode.workspace.workspaceFolders || []) {
    if (folder.uri.scheme === "file") {
      registerTestController(context, folder, serverLaunch(context, folder));
    }
  }

  context.subscriptions.push(
    traceDiagnostics,
    generatedEvents,
    // A content provider rather than a webview: what opens is an ordinary
    // read-only editor, so search, folding, diff and every editor command keep
    // working on generated code.
    vscode.workspace.registerTextDocumentContentProvider(GENERATED_SCHEME, {
      onDidChange: generatedEvents.event,
      provideTextDocumentContent(uri) {
        const artifact = generated.get(uri.toString());
        return artifact && artifact.available ? artifact.text : "";
      }
    }),
    vscode.commands.registerCommand(
      "nupp.checkFunctionForJitTraceBlockers",
      checkFunctionForTraceBlockers
    ),
    vscode.commands.registerCommand("nupp.migrateAnnotatedLua", migrateAnnotatedLua),
    vscode.commands.registerCommand("nupp.inspectCompiledFunction", inspectCompiledFunction),
    vscode.commands.registerCommand("nupp.openGeneratedLua", (target) =>
      openGeneratedArtifact("lua", target)),
    vscode.commands.registerCommand("nupp.openBytecode", (target) =>
      openGeneratedArtifact("bytecode", target)),
    vscode.commands.registerCommand("nupp.compareGeneratedArtifacts", compareGeneratedArtifacts),
    vscode.commands.registerCommand("nupp.restartLanguageServer", async () => {
      await restartClients(context);
      void vscode.window.showInformationMessage("Nupp language server restarted.");
    }),
    vscode.window.onDidChangeTextEditorSelection(synchronizeSelection),
    // An edit invalidates every open artifact made from that file. They are
    // re-resolved when something asks, not on the keystroke.
    vscode.workspace.onDidChangeTextDocument((event) => {
      const source = event.document.uri.toString();
      for (const [key, artifact] of generated) {
        if (artifact && artifact.uri === source) {
          generated.set(key, { ...artifact, stale: true });
        }
      }
    }),
    vscode.languages.registerCodeActionsProvider(
      { language: "lua", scheme: "file" },
      {
        provideCodeActions(document) {
          if (!document.uri.fsPath.endsWith(".lua")) {
            return [];
          }
          const action = new vscode.CodeAction(
            "Migrate annotated Lua to Nupp",
            vscode.CodeActionKind.RefactorRewrite
          );
          action.command = {
            command: "nupp.migrateAnnotatedLua",
            title: action.title,
            arguments: [{ uri: document.uri }]
          };
          return [action];
        }
      },
      { providedCodeActionKinds: [vscode.CodeActionKind.RefactorRewrite] }
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
      for (const folder of event.added) {
        if (folder.uri.scheme === "file") {
          registerTestController(context, folder, serverLaunch(context, folder));
        }
      }
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
  running.forEach(({ watchers }) => watchers.forEach((watcher) => watcher.dispose()));
}

module.exports = { activate, deactivate };
