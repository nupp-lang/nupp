#!/usr/bin/env python3
"""Execute the ordinary derived check command in a VM image.

Usage: cli-execution-smoke.py IMAGE [BINARY] [--repository]
The image entry is nupp.compiler.vm.cli. No compiler process is launched.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path.cwd()
image = str(Path(sys.argv[1]).resolve())
binary = str(Path(sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "--repository"
                  else "build/rust/target/release/nupp-vm").resolve())
env = dict(os.environ, NO_JIT="1", NUPP_CHECK_JOBS="1", NUPP_COMPILER_ROOT=str(root), PATH="")


def command(directory, *args, status=0):
    result = subprocess.run([binary, "exec", image, "nupp.compiler.vm.cli", *args],
                            cwd=directory, env=env, capture_output=True, text=True, timeout=1800)
    assert result.returncode == status, (args, result.returncode, result.stdout[-12000:], result.stderr[-12000:])
    return result


with tempfile.TemporaryDirectory(prefix="nupp-vm-cli-") as directory:
    directory = Path(directory)
    (directory / "valid file.nupp").write_text("local answer: integer = 42\nexport = answer\n")
    (directory / "invalid.nupp").write_text('local answer: integer = "wrong"\nexport = answer\n')
    valid = command(directory, "--json", "valid file.nupp")
    assert not valid.stderr, valid.stderr
    assert json.loads(valid.stdout)["ok"] is True
    invalid = command(directory, "--json", "invalid.nupp", status=1)
    report = json.loads(invalid.stdout)
    assert report["ok"] is False and report["diagnostics"], report
    assert any(item["severity"] == "error" for item in report["diagnostics"]), report
    control_name = "invalid\x01name.nupp"
    (directory / control_name).write_text('local answer: integer = "wrong"\nexport = answer\n')
    escaped = json.loads(command(directory, "--json", control_name, status=1).stdout)
    assert any(control_name in item["file"] for item in escaped["diagnostics"]), escaped
    missing = command(directory, "--json", "absent.nupp", status=1)
    assert json.loads(missing.stdout)["ok"] is False
    usage = command(directory, "--unknown-option", status=2)
    assert "unknown option" in usage.stderr
    help_text = command(directory, "--help")
    assert "nupp check" in help_text.stdout
    schema = json.loads(command(directory, "--schema").stdout)
    assert schema["type"] == "object" and "diagnostics" in schema["properties"]
    (directory / "c-types.nupp").write_text(
        'local ffi = require("ffi")\n'
        'ffi.cdef[[typedef struct { int x; } CliProbe;]]\n'
        'local point = ffi.new("CliProbe")\npoint.x = 42\nexport = point.x\n')
    assert json.loads(command(directory, "--json", "c-types.nupp").stdout)["ok"] is True
    (directory / "invalid-c-type.nupp").write_text(
        'local ffi = require("ffi")\nlocal point = ffi.new("MissingCliType")\nexport = point\n')
    invalid_c = json.loads(command(directory, "--json", "invalid-c-type.nupp", status=1).stdout)
    assert any(item["code"] == "NUPP2304" for item in invalid_c["diagnostics"]), invalid_c
    (directory / "src").mkdir()
    (directory / "src/main.nupp").write_text("module main\nexport = 42\n")
    (directory / "nupp.lua").write_text('return {include = {"src"}}\n')
    project = json.loads(command(directory, "--json").stdout)
    assert project["ok"] is True, project
    print("VM check: files, diagnostics, JSON, schema, help, usage, and project passed", flush=True)

if "--repository" in sys.argv:
    result = command(root, "--json")
    report = json.loads(result.stdout)
    assert report["ok"] is True, report
    print("Repository-wide interpreted VM check passed", flush=True)
