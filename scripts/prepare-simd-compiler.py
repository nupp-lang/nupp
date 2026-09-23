#!/usr/bin/env python3
"""Resolve one real SIMD compiler dialect for a fleet worker."""

import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def command(*names):
    for name in names:
        resolved = shutil.which(name)
        if resolved:
            return str(Path(resolved).resolve())
    return None


def prepare(family):
    if family not in ("clang", "gcc"):
        raise ValueError("compiler family must be clang or gcc")
    system = platform.system().lower()
    clang = command("clang")
    gcc = command("gcc")
    if system == "darwin":
        gcc = command("gcc-16", "gcc-15", "gcc-14", "gcc-13", "gcc-12")
    selected = clang if family == "clang" else gcc
    if selected is None:
        raise RuntimeError(f"no real {family} compiler is installed")
    environment = {"NUPP_NATIVE_CC": selected}
    if system == "windows" and family == "clang":
        if gcc is None:
            raise RuntimeError("Windows Clang SIMD requires a MinGW GCC sysroot")
        target = subprocess.check_output([gcc, "-dumpmachine"], text=True).strip()
        if "mingw" not in target:
            raise RuntimeError(f"Windows GCC target is not MinGW: {target}")
        output = ROOT / "build/fleet-tools/clang-mingw.exe"
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [gcc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/simd/clang-mingw.c"), "-o", str(output)],
            check=True,
        )
        environment.update({
            "NUPP_NATIVE_CC": str(output),
            "NUPP_SIMD_CLANG": clang,
            "NUPP_SIMD_GNU_ROOT": str(Path(gcc).parent.parent),
            "NUPP_SIMD_GNU_TARGET": target,
        })
    version = subprocess.check_output([selected, "--version"], text=True, stderr=subprocess.STDOUT).splitlines()[0]
    lower = version.lower()
    dialect = "clang" if "clang" in lower else "gcc" if "gcc" in lower or "free software foundation" in lower else "unknown"
    if dialect != family:
        raise RuntimeError(f"{selected} reports {dialect}, not requested {family}: {version}")
    return {"family": family, "compiler": environment["NUPP_NATIVE_CC"], "version": version, "env": environment}


if __name__ == "__main__":
    try:
        print(json.dumps(prepare(sys.argv[1]), sort_keys=True))
    except (IndexError, OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit("prepare-simd-compiler: " + str(error))
