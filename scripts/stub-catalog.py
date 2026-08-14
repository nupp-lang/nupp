#!/usr/bin/env python3
"""Write immutable compiler-host catalog records used by release CI."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


HOST_ABI = 1
HOST_FEATURES = [
    "cjson",
    "lpeg",
    "lua-utf8",
    "native-files",
    "native-process",
    "workers",
]
PLATFORMS = {
    "x86_64-unknown-linux-gnu": "",
    "aarch64-apple-darwin": "",
    "x86_64-pc-windows-msvc": ".exe",
}


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def safe_component(value: str) -> bool:
    return bool(value) and value not in {".", ".."} and "/" not in value and "\\" not in value


def validate_binary(platform: str, data: bytes) -> None:
    if platform == "x86_64-unknown-linux-gnu":
        valid = len(data) >= 20 and data[:5] == b"\x7fELF\x02" and data[18:20] == b">\x00"
    elif platform == "aarch64-apple-darwin":
        valid = len(data) >= 8 and data[:4] == b"\xcf\xfa\xed\xfe" and data[4:8] == b"\x0c\x00\x00\x01"
    else:
        pe_offset = int.from_bytes(data[60:64], "little") if len(data) >= 64 else -1
        valid = (
            data[:2] == b"MZ"
            and pe_offset >= 0
            and data[pe_offset : pe_offset + 6] == b"PE\0\0d\x86"
        )
    if not valid:
        raise SystemExit(f"artifact is not a {platform} executable")


def record(args: argparse.Namespace) -> None:
    if not safe_component(args.catalog_release):
        raise SystemExit("catalog release must be one safe path component")
    expected_suffix = PLATFORMS.get(args.platform)
    if expected_suffix is None:
        raise SystemExit(f"unsupported stub platform {args.platform}")
    if args.executable_suffix != expected_suffix:
        raise SystemExit(
            f"{args.platform} requires executable suffix {expected_suffix!r}"
        )
    artifact = Path(args.artifact)
    data = artifact.read_bytes()
    validate_binary(args.platform, data)
    notice = Path(args.notice_artifact)
    if not notice.is_file():
        raise SystemExit(f"notice artifact does not exist: {notice}")
    write_json(
        Path(args.output),
        {
            "artifact": artifact.name,
            "catalogRelease": args.catalog_release,
            "executableSuffix": args.executable_suffix,
            "hostAbi": HOST_ABI,
            "hostFeatures": HOST_FEATURES,
            "noticeArtifact": notice.name,
            "platform": args.platform,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        },
    )


def catalog(args: argparse.Namespace) -> None:
    if not safe_component(args.catalog_release):
        raise SystemExit("catalog release must be one safe path component")
    records: dict[str, dict[str, object]] = {}
    for name in args.records:
        value = json.loads(Path(name).read_text())
        platform = value["platform"]
        if platform not in PLATFORMS:
            raise SystemExit(f"unsupported stub platform {platform}")
        if platform in records:
            raise SystemExit(f"duplicate stub record for {platform}")
        if value.get("hostAbi") != HOST_ABI:
            raise SystemExit(f"stub record for {platform} has the wrong hostAbi")
        if value.get("catalogRelease") != args.catalog_release:
            raise SystemExit(f"stub record for {platform} has the wrong catalog release")
        if value.get("hostFeatures") != HOST_FEATURES:
            raise SystemExit(f"stub record for {platform} is not a universal host")
        if value.get("executableSuffix") != PLATFORMS[platform]:
            raise SystemExit(f"stub record for {platform} has the wrong executable suffix")
        value["catalogRelease"] = args.catalog_release
        records[platform] = value
    missing = [platform for platform in PLATFORMS if platform not in records]
    if missing:
        raise SystemExit("catalog is missing stub records: " + ", ".join(missing))
    write_json(
        Path(args.output),
        {"catalogRelease": args.catalog_release, "hostAbi": HOST_ABI, "stubs": records},
    )


parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(dest="command", required=True)

record_parser = subparsers.add_parser("record")
record_parser.add_argument("--platform", required=True)
record_parser.add_argument("--catalog-release", required=True)
record_parser.add_argument("--artifact", required=True)
record_parser.add_argument("--notice-artifact", required=True)
record_parser.add_argument("--executable-suffix", default="")
record_parser.add_argument("--output", required=True)
record_parser.set_defaults(run=record)

catalog_parser = subparsers.add_parser("catalog")
catalog_parser.add_argument("--catalog-release", required=True)
catalog_parser.add_argument("--output", required=True)
catalog_parser.add_argument("records", nargs="+")
catalog_parser.set_defaults(run=catalog)

arguments = parser.parse_args()
arguments.run(arguments)
