#!/usr/bin/env python3
"""Exercise the root CLI image and route nested compiler invocations through it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--installed", action="store_true", help="use the default installed VM package without image environment overrides")
parser.add_argument("--case", action="append", help="run only the named acceptance case")
parser.add_argument("--luarocks", type=Path, help="provisioned LuaRocks executable for real package coverage")
args = parser.parse_args()
root = Path.cwd()
image, binary = args.image.resolve(), args.binary.resolve()
args.output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, NO_JIT="1", NUPP_CHECK_JOBS="1", NUPP_COMPILER_ROOT=str(root),
           NUPP_VM_CLI_IMAGE=str(image), NUPP_VM_BINARY=str(binary), NO_COLOR="1")
package = None
if args.installed:
    generation = (root / ".nupp/vm-cli/current").read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{64}", generation), "invalid installed package selection"
    package = root / ".nupp/vm-cli" / generation
    for supplied, installed in ((binary, package / "runtime"), (image, package / "compiler.image")):
        assert hashlib.sha256(supplied.read_bytes()).digest() == hashlib.sha256(installed.read_bytes()).digest(), "installed package differs from requested evidence artifacts"
    env.pop("NUPP_VM_CLI_IMAGE", None)
    env.pop("NUPP_VM_BINARY", None)
for name in ("EMIT_STUBS", "EMIT_SURVEY", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT"):
    env.pop(name, None)
if args.luarocks:
    env["NUPP_LUAROCKS"] = str(args.luarocks.resolve())
    env["PATH"] = str(args.luarocks.resolve().parent) + os.pathsep + env.get("PATH", "")
results = []

def case(name, argv, cwd, status=0, json_output=False, contains=None, stdin=None, timeout=180):
    if args.case and name not in args.case:
        return
    started = time.monotonic()
    record = dict(name=name, argv=argv)
    try:
        process = subprocess.Popen([str(root / "bin/nupp"), *argv], cwd=cwd, env=env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=os.name != "nt")
        try:
            stdout, stderr = process.communicate(stdin, timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            (args.output / f"{name}.stdout").write_text(stdout)
            (args.output / f"{name}.stderr").write_text(stderr)
            raise TimeoutError(f"command exceeded {timeout} seconds")
        result = subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
        (args.output / f"{name}.stdout").write_text(result.stdout)
        (args.output / f"{name}.stderr").write_text(result.stderr)
        record["exitStatus"] = result.returncode
        assert result.returncode == status, f"expected status {status}, got {result.returncode}: {result.stderr[-6000:]}"
        if json_output:
            value = json.loads(result.stdout)
            assert isinstance(value, (dict, list)), "expected a JSON document"
        if contains is not None:
            assert contains in result.stdout, f"missing {contains!r} in stdout"
        record["status"] = "passed"
    except Exception as error:
        record.update(status="failed", error=str(error))
    record["seconds"] = round(time.monotonic() - started, 3)
    results.append(record)
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(name + ": " + record["status"], flush=True)

with tempfile.TemporaryDirectory(prefix="nupp-vm-root-cli-") as directory:
    work = Path(directory)
    env["NUPP_TOOLCHAIN_CACHE"] = str(work / "toolchain-cache")
    (work / "src").mkdir()
    (work / "nupp.lua").write_text(
        'return {include = {"src"}, build = {outDir = "build", default = "app", '
        'targets = {app = {kind = "modules", entries = {"main"}, layoutTarget = "x86_64-unknown-linux-gnu"}}}, '
        'test = {build = "app", argv = {' + json.dumps(str(root / "bin/nupp")) + ', "run", "src/main.nupp"}}, '
        'tasks = {answer = {argv = {' + json.dumps(str(root / "bin/nupp")) + ', "run", "src/main.nupp"}}}}\n')
    (work / "src/main.nupp").write_text('module main\nlocal answer: integer = 42\nprint(answer)\nexport = answer\n')
    (work / "src/kernel.nupp").write_text('@aot\nlocal function twice(value: number): number\n return value * 2\nend\nreturn twice\n')
    (work / "invalid.nupp").write_text('local value: integer = "wrong"\nexport = value\n')
    (work / "plain.lua").write_text('local answer = 42\nreturn answer\n')
    (work / "header.h").write_text('typedef struct CliPoint { int x; int y; } CliPoint;\nint cli_sum(int a, int b);\n')
    (work / "src/game.nupp").write_text(
        'local game = {}\nstruct game.Position\n x: float\n y: float\nend\nreturn game\n')
    (work / "sandbox.lua").write_text("""
local chunk = assert(loadstring("answer = answer + 1; return answer, function() return answer, io end"))
local environment = {answer = 41}
setfenv(chunk, environment)
local answer, nested = chunk()
assert(answer == 42 and environment.answer == 42 and _G.answer == nil)
local value, unavailable = nested()
assert(value == 42 and unavailable == nil)
local template = require("nupp.tools.template")
for _, source in ipairs({
    'return {description = io.open("escape")} ',
    'return {description = tostring(os.execute("true"))}',
    'require("nupp.compiler.fs") return {}',
    'loadstring("return 1") return {}',
    'return {description = tostring(package.path)}'
}) do
    local manifest, problem = template.manifest(source, "sandbox.lua")
    assert(manifest == nil and problem)
end
local manifest, problem = template.manifest("while true do end", "sandbox.lua")
assert(manifest == nil and problem:find("too long", 1, true))
assert(template.manifest('return {description = "ok"}', "sandbox.lua"))
print(42)
""")
    (work / "fixtures.lua").write_text(
        'local factory = assert(loadstring(' + json.dumps((root / "native/crates/vm/tests/corpus-fixtures.lua").read_text()) + '))()\n' + """
local store = factory.new()
local calls = 0
local path, value, reused = store.resolve("fixture", function(path)
    calls = calls + 1
    assert(io.open(path .. "/data", "wb")):write("bytes"):close()
    return {answer = 42}
end)
assert(value.answer == 42 and not reused)
value.answer = 0
local again, fresh, hit = store.resolve("fixture", function() error("cache missed") end)
assert(again == path and fresh.answer == 42 and hit and calls == 1)
assert(io.open(path .. "/data", "wb")):write("changed"):close()
assert(not pcall(store.resolve, "fixture", function() end))
local failures = 0
for _ = 1, 2 do
    assert(not pcall(store.resolve, "failure", function()
        failures = failures + 1
        error("producer failed")
    end))
end
assert(failures == 1)
store.close()
assert(not require("nupp.io.files").exists(path))
print(42)
""")
    case("root-help", ["--help"], work, contains="nupp")
    case("unknown-command", ["definitely-not-a-command"], work, status=2)
    # Derive the inventory from the root registry; a newly added command gets a case.
    registry = (root / "src/nupp/tools/cli/root.nupp").read_text()
    commands = []
    for module in re.findall(r'require\("(nupp\.tools\.cli\.[^"]+)"\)\.commandType', registry):
        source = (root / "src" / (module.replace(".", "/") + ".nupp")).read_text()
        match = re.search(r'@cli\((?:name\s*=\s*)?"([^"]+)"', source)
        assert match, module
        command = match[1]
        commands.append(command)
        case(command + "-help", [command, "--help"], work, contains=command)
        if "function " in source and ".reportSchema()" in source and command != "lsp":
            case(command + "-schema", [command, "--schema"], work, json_output=True)
    commands.append("help")
    case("help-command", ["help", "check"], work, contains="nupp check")
    for name, argv, status, json_output, contains in [
        ("version-json", ["version", "--json"], 0, True, "Nupp VM"),
        ("version-alias", ["--version", "--json"], 0, True, "Nupp VM"),
        ("ast-file", ["ast", "src/main.nupp"], 0, True, None),
        ("check-file", ["check", "--json", "src/main.nupp"], 0, True, None),
        ("check-project", ["check", "--json"], 0, True, None),
        ("check-project-cached", ["check", "--json"], 0, True, '"compiledModules":0'),
        ("check-invalid", ["check", "--json", "invalid.nupp"], 1, True, None),
        ("check-missing", ["check", "--json", "missing.nupp"], 1, True, None),
        ("build-file", ["build", "--json", "--output", "generated", "src/main.nupp"], 0, True, None),
        ("fmt-file", ["fmt", "--write", "src/main.nupp"], 0, False, None),
        ("lints-json", ["lints", "--json"], 0, True, None),
        ("ownership-file", ["ownership-audit", "--json", "src/main.nupp"], 0, True, None),
        ("explain-code", ["explain", "--json", "NUPP2004"], 0, True, None),
        ("reference-code", ["reference", "--json", "--for", "NUPP2004"], 0, True, None),
        ("completion-script", ["completions", "bash"], 0, False, "__complete bash"),
        ("completion-request", ["__complete", "bash", "2", "check", "--js"], 0, False, "--json"),
        ("templates-list", ["init", "--list", "--json"], 0, True, None),
        ("template-app", ["init", "app", "new-app", "--json"], 0, True, None),
        ("task-list", ["task", "--list", "--json"], 0, True, None),
        ("import-header", ["import-c", "--inspect", "--json", "header.h"], 0, True, None),
        ("migrate-lua", ["migrate", "--json", "plain.lua"], 0, True, None),
        ("lsp-symbols", ["lsp", "symbols", "--json", "--file", "src/main.nupp"], 0, True, None),
        ("run-file", ["run", "src/main.nupp"], 0, False, "42"),
        ("fixture-store", ["run", "fixtures.lua"], 0, False, "42"),
        ("source-sandbox", ["run", "sandbox.lua"], 0, False, "42"),
        ("task-run", ["task", "answer"], 0, False, "42"),
        ("test-run", ["test"], 0, False, "42"),
        ("aot-file", ["aot", "--json", "src/kernel.nupp"], 0, True, None),
        ("bc-file", ["bc", "--json", "src/main.nupp"], 0, True, '"backend":"vm"'),
        ("bc-text", ["bc", "src/main.nupp"], 0, False, "Ret"),
        ("bc-check", ["bc", "--check", "--json", "src/main.nupp"], 0, True, '"backend":"vm"'),
        ("bc-invalid", ["bc", "--json", "invalid.nupp"], 1, True, None),
        ("doc-file", ["doc", "--kind", "markdown", "--json", "-o", "api.md", "src/main.nupp"], 0, True, None),
        ("export-header", ["export-c", "--json", "-o", "game.h", "src/game.nupp", "game.Position"], 0, True, None),
        ("bench-list", ["bench", "--list", "--json", "--file", str(root / "tests/fixtures/bench_fixed_records.nupp")], 0, True, "fixed"),
        ("bench-protocol", ["bench", "--json", "--forks", "1", "--file", str(root / "tests/fixtures/bench_protocol.nupp")], 0, True, "protocol"),
        ("bench-run", ["bench", "--json", "--forks", "1", "--case", "fixed", "--file", str(root / "tests/fixtures/bench_fixed_records.nupp")], 0, True, "fixed"),
        ("fixpoint-unconfigured", ["fixpoint", "--json"], 1, True, None),
        ("rock-missing", ["rock", "pack"], 1, False, None),
        ("clean-dry", ["clean", "--dry-run", "--json"], 0, True, None),
    ]:
        case(name, argv, work, status, json_output, contains)
    if args.luarocks:
        case("template-library", ["init", "lib", "sample-lib", "--json"], work, json_output=True)
        case("rock-pack", ["rock", "pack"], work / "sample-lib", contains="Packed ")
        case("rock-test", ["rock", "test"], work / "sample-lib", contains="Checked ")
    request = {"source": "comptime do return 42 end"}
    (work / "comptime.json").write_text(json.dumps(request))
    case("comptime-worker", ["__comptime-worker", "comptime.json"], work,
         json_output=True, contains='"ok":true')
    payload = json.dumps(request, separators=(",", ":"))
    case("comptime-service", ["__comptime-worker-service"], work,
         stdin=f"{len(payload)}\n{payload}", contains='"ok":true')
    (work / "provider.lua").write_text('return function(request) request.write("generated.txt", request.read("input.txt")) end\n')
    (work / "input.txt").write_text("generated by a VM child")
    (work / "generator-out").mkdir()
    request = dict(name="fixture", entry="provider", path=str(work / "?.lua"),
                   inputRoot=str(work), outputRoot=str(work / "generator-out"),
                   inputs=[str(work / "input.txt")])
    (work / "generator.json").write_text(json.dumps(request))
    case("generator-worker", ["__generator-worker", "generator.json", "generator-result.json"], work)
    if results and results[-1]["name"] == "generator-worker" and results[-1]["status"] == "passed":
        assert json.loads((work / "generator-result.json").read_text())["ok"] is True
        assert (work / "generator-out/generated.txt").read_text() == "generated by a VM child"
    messages = [dict(jsonrpc="2.0", id=1, method="initialize", params={}),
                dict(jsonrpc="2.0", id=2, method="shutdown"), dict(jsonrpc="2.0", method="exit")]
    frames = "".join(f"Content-Length: {len(body)}\r\n\r\n{body}"
                     for body in [json.dumps(message) for message in messages])
    case("lsp-serve", ["lsp", "serve"], work, stdin=frames, contains='"capabilities"')
    body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    frame = f"Content-Length: {len(body)}\r\n\r\n{body}"
    case("lsp-reader", ["__lsp-reader"], work, stdin=frame, contains=body)
    parallel = work / "parallel"
    (parallel / "src").mkdir(parents=True)
    (parallel / "nupp.lua").write_text('return {include = {"src"}, build = {outDir = "build"}}\n')
    (parallel / "src/value.nupp").write_text('module value\nexport = 42\n')
    (parallel / "src/main.nupp").write_text('module main\nlocal value = require("value")\nexport = value\n')
    env["NUPP_CHECK_JOBS"] = "2"
    case("parallel-check", ["check", "--json"], parallel, json_output=True, contains='"mode":"parallel"')
    documented = work / "documented"
    (documented / "src/documented").mkdir(parents=True)
    (documented / "nupp.lua").write_text('return {include = {"src"}}\n')
    (documented / "src/documented/errors.nupp").write_text(
        'module documented.errors\nexport record Problem\n message: string\nend\n')
    (documented / "src/documented/api.nupp").write_text(
        'module documented.api\nexport interface Reader\n'
        ' --- Reads the next value.\n'
        ' --- @raises documented.errors.Problem when the input is invalid\n'
        ' read: function(self): string\nend\n')
    (documented / "src/documented/othererrors.nupp").write_text(
        'module documented.othererrors\nexport record Problem\n message: string\nend\n')
    (documented / "src/documented/exported.nupp").write_text(
        'module documented.exported\n'
        '--- @raises documented.othererrors.Problem when the input is invalid\n'
        'export function read(): string return "" end\n')
    case("parallel-doc-check", ["check", "--json"], documented, json_output=True, contains='"mode":"parallel"')
    env["NUPP_CHECK_JOBS"] = "1"
    case("clean-run", ["clean", "--json"], work, json_output=True)

if args.case:
    assert set(args.case) == {row["name"] for row in results}, "unknown acceptance case"
summary = dict(launcherMode="installed" if args.installed else "explicit-image", package=str(package) if package else None,
               imageSha256=hashlib.sha256(image.read_bytes()).hexdigest(),
               binarySha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
               commands=commands, cases=len(results), passed=sum(row["status"] == "passed" for row in results))
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
assert summary["passed"] == summary["cases"], "root CLI failures; see results.json"
