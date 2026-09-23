#!/usr/bin/env python3
"""Transport one immutable Nupp fleet checkout to a worker.

The controller sends the same framed request and Git bundle through each
transport.  A small, fixed bootstrap verifies both before it runs the worker
from the received checkout.  Endpoint configuration selects a transport; it
never supplies a command for the bootstrap to execute.
"""

from __future__ import annotations

import hashlib
import base64
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Mapping, MutableMapping, Optional, Tuple


PROTOCOL_VERSION = 1
_MAX_REQUEST_BYTES = 16 * 1024 * 1024
_ID = re.compile(r"^[A-Za-z0-9._-]+$")
_SSH_HOST = re.compile(r"^[A-Za-z0-9_.:%-]+$")
_DOCKER_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_DOCKER_IMAGE = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._/:@-]*@sha256:[0-9a-fA-F]{64}$"
)
_PLATFORM = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./-]*$")


class TransportError(RuntimeError):
    """The fleet request could not safely reach or return from a worker."""


def _bootstrap_source() -> str:
    # Keep this program independent of this module: it is also run on an SSH
    # host and in a container which have received no checkout yet.
    return r'''
import hashlib
import json
import os
import shutil
import signal
import struct
import subprocess
import sys
import tempfile

MAX_REQUEST = 16 * 1024 * 1024
child = None

def fail(message):
    sys.stderr.write("test-fleet bootstrap: " + str(message) + "\n")
    raise SystemExit(125)

def read_exact(stream, length):
    pieces = []
    remaining = length
    while remaining:
        piece = stream.read(min(1024 * 1024, remaining))
        if not piece:
            fail("unexpected end of transport stream")
        pieces.append(piece)
        remaining -= len(piece)
    return b"".join(pieces)

def terminate_child(signum, _frame):
    global child
    if child is None or child.poll() is not None:
        return
    try:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(child.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            os.killpg(child.pid, signum if signum in (signal.SIGINT, signal.SIGTERM) else signal.SIGTERM)
    except (OSError, ValueError):
        try:
            child.terminate()
        except OSError:
            pass

for signal_name in ("SIGHUP", "SIGINT", "SIGTERM"):
    selected = getattr(signal, signal_name, None)
    if selected is not None:
        signal.signal(selected, terminate_child)

stream = sys.stdin.buffer
length_bytes = read_exact(stream, 8)
request_length = struct.unpack(">Q", length_bytes)[0]
if request_length == 0 or request_length > MAX_REQUEST:
    fail("invalid request length")
request_bytes = read_exact(stream, request_length)
try:
    request = json.loads(request_bytes.decode("utf-8"))
except (UnicodeDecodeError, json.JSONDecodeError) as problem:
    fail("invalid request JSON: " + str(problem))
if not isinstance(request, dict) or request.get("schemaVersion") != 1:
    fail("unsupported request schema")
source = request.get("source")
if not isinstance(source, dict):
    fail("request has no bundle identity")
bundle_bytes = source.get("bytes")
bundle_digest = source.get("bundleSha256")
if not isinstance(bundle_bytes, int) or bundle_bytes < 1:
    fail("invalid bundle byte count")
if not isinstance(bundle_digest, str) or len(bundle_digest) != 64:
    fail("invalid bundle digest")

temporary = tempfile.mkdtemp(prefix="nupp-fleet-")
try:
    bundle_path = os.path.join(temporary, "snapshot.bundle")
    digest = hashlib.sha256()
    remaining = bundle_bytes
    with open(bundle_path, "wb") as output:
        while remaining:
            piece = stream.read(min(1024 * 1024, remaining))
            if not piece:
                fail("unexpected end of bundle")
            output.write(piece)
            digest.update(piece)
            remaining -= len(piece)
    if stream.read(1):
        fail("trailing bytes after bundle")
    if digest.hexdigest() != bundle_digest.lower():
        fail("bundle SHA-256 mismatch")

    checkout = os.path.join(temporary, "checkout")
    clone = subprocess.run(
        ["git", "clone", "--quiet", "--no-checkout", "--branch", "snapshot", bundle_path, checkout],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if clone.returncode != 0:
        fail("cannot clone bundle: " + clone.stderr.strip())
    subprocess.run(
        ["git", "-C", checkout, "config", "core.autocrlf", "false"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    checked_out = subprocess.run(
        ["git", "-C", checkout, "checkout", "--quiet", "--force", "HEAD"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if checked_out.returncode != 0:
        fail("cannot check out bundle: " + checked_out.stderr.strip())
    tree = subprocess.run(
        ["git", "-C", checkout, "rev-parse", "HEAD^{tree}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if tree.returncode != 0 or tree.stdout.strip() != source.get("treeOid"):
        fail("bundle tree does not match snapshot identity")

    request_path = os.path.join(temporary, "request.json")
    with open(request_path, "wb") as output:
        output.write(request_bytes)
        output.write(b"\n")
    worker = os.path.join(checkout, "scripts", "test-fleet")
    if not os.path.isfile(worker):
        fail("received checkout has no scripts/test-fleet worker")
    creationflags = 0
    start_new_session = False
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    else:
        start_new_session = True
    environment = os.environ.copy()
    environment["NUPP_FLEET_SNAPSHOT_ID"] = source["snapshotSha256"]
    cache = request.get("workerCache") or environment.get("NUPP_FLEET_CACHE") or os.path.join(os.path.expanduser("~"), ".cache", "nupp-test-fleet")
    cache = os.path.abspath(os.path.expanduser(cache))
    child = subprocess.Popen(
        [sys.executable, worker, "worker", "--request", request_path, "--cache", cache],
        cwd=checkout,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=sys.stdout,
        stderr=sys.stderr,
        creationflags=creationflags,
        start_new_session=start_new_session,
    )
    raise SystemExit(child.wait())
finally:
    terminate_child(signal.SIGTERM, None)
    shutil.rmtree(temporary, ignore_errors=True)
'''.lstrip()


BOOTSTRAP_SOURCE = _bootstrap_source()


def _require_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str) or not _ID.fullmatch(value):
        raise ValueError(f"{field} must contain only letters, digits, dot, underscore, and hyphen")
    return value


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError(f"{field} must be a non-empty string without NUL bytes")
    return value


def sha256_file(path: os.PathLike[str] | str) -> Tuple[str, int]:
    """Return a file's SHA-256 and byte count without loading it into memory."""

    digest = hashlib.sha256()
    size = 0
    with open(path, "rb") as source:
        while True:
            piece = source.read(1024 * 1024)
            if not piece:
                break
            digest.update(piece)
            size += len(piece)
    return digest.hexdigest(), size


def prepare_request(
    request: Mapping[str, Any], bundle_path: os.PathLike[str] | str
) -> Tuple[dict[str, Any], bytes]:
    """Validate and canonically encode a request with its bundle identity."""

    if not isinstance(request, Mapping):
        raise ValueError("request must be an object")
    prepared: MutableMapping[str, Any] = dict(request)
    if prepared.get("schemaVersion") != PROTOCOL_VERSION:
        raise ValueError(f"schemaVersion must be {PROTOCOL_VERSION}")
    for field in ("runId", "jobId"):
        _require_identifier(prepared.get(field), field)
    source = prepared.get("source")
    if not isinstance(source, Mapping):
        raise ValueError("source must be an object")
    source = dict(source)
    tree = source.get("treeOid")
    if not isinstance(tree, str) or not re.fullmatch(r"[0-9a-fA-F]{40,64}", tree):
        raise ValueError("source.treeOid must be a 40- to 64-digit hexadecimal Git tree identity")
    snapshot = source.get("snapshotSha256")
    if not isinstance(snapshot, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", snapshot):
        raise ValueError("source.snapshotSha256 must be a SHA-256 identity")
    source["treeOid"] = tree.lower()
    source["snapshotSha256"] = snapshot.lower()

    digest, size = sha256_file(bundle_path)
    if source.get("bundleSha256") != digest or source.get("bytes") != size:
        raise ValueError("request source bundle identity does not match bundle_path")
    if snapshot.lower() != digest:
        raise ValueError("source.snapshotSha256 must identify the transported bundle")
    prepared["source"] = source
    try:
        encoded = json.dumps(
            prepared, sort_keys=True, separators=(",", ":"), ensure_ascii=True
        ).encode("utf-8")
    except (TypeError, ValueError) as problem:
        raise ValueError(f"request is not JSON-compatible: {problem}") from problem
    if not encoded or len(encoded) > _MAX_REQUEST_BYTES:
        raise ValueError("encoded request is empty or too large")
    return dict(prepared), encoded


def validate_executor(executor: Mapping[str, Any], request: Mapping[str, Any]) -> list[str]:
    """Return the fixed bootstrap argv for one validated endpoint."""

    if not isinstance(executor, Mapping):
        raise ValueError("executor must be an object")
    kind = executor.get("kind")
    if kind == "local":
        unknown = set(executor) - {"kind", "cache", "toolchain"}
        if unknown:
            raise ValueError("unknown local executor fields: " + ", ".join(sorted(unknown)))
        return [sys.executable, "-u", "-c", BOOTSTRAP_SOURCE]

    if kind == "ssh":
        unknown = set(executor) - {"kind", "host", "port", "user", "identityFile", "python", "cache", "toolchain"}
        if unknown:
            raise ValueError("unknown SSH executor fields: " + ", ".join(sorted(unknown)))
        host = _require_string(executor.get("host"), "host")
        if not _SSH_HOST.fullmatch(host) or host.startswith("-"):
            raise ValueError("host is not a safe SSH destination")
        user = executor.get("user")
        if user is not None:
            user = _require_identifier(user, "user")
        destination = f"{user}@{host}" if user else host
        argv = ["ssh", "-T"]
        port = executor.get("port")
        if port is not None:
            if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
                raise ValueError("port must be an integer from 1 through 65535")
            argv.extend(["-p", str(port)])
        identity = executor.get("identityFile")
        if identity is not None:
            argv.extend(["-i", _require_string(identity, "identityFile")])
        python = executor.get("python", "python3")
        if python not in ("python3", "python"):
            raise ValueError("SSH python must be python3 or python")
        # OpenSSH hands its command to the remote login shell.  A base64 wrapper
        # uses only quoting shared by POSIX shells, cmd.exe, and PowerShell, so a
        # native Windows SSH worker receives the same fixed program.  Only owned
        # program text reaches that shell; endpoint configuration does not.
        encoded = base64.b64encode(BOOTSTRAP_SOURCE.encode("utf-8")).decode("ascii")
        remote_source = "import base64;exec(base64.b64decode('" + encoded + "'))"
        remote = python + ' -u -c "' + remote_source + '"'
        argv.extend([destination, remote])
        return argv

    if kind == "docker":
        unknown = set(executor) - {"kind", "image", "platform", "cacheVolume"}
        if unknown:
            raise ValueError("unknown Docker executor fields: " + ", ".join(sorted(unknown)))
        image = _require_string(executor.get("image"), "image")
        if not _DOCKER_IMAGE.fullmatch(image):
            raise ValueError("Docker image must be pinned as name@sha256:<64 hex digits>")
        run_id = _require_identifier(request.get("runId"), "runId")
        job_id = _require_identifier(request.get("jobId"), "jobId")
        name = ("nupp-fleet-" + run_id + "-" + job_id + "-" + str(os.getpid()))[:128]
        argv = ["docker", "run", "--rm", "-i", "--name", name]
        platform = executor.get("platform")
        if platform is not None:
            platform = _require_string(platform, "platform")
            if not _PLATFORM.fullmatch(platform):
                raise ValueError("platform is not a safe Docker platform")
            argv.extend(["--platform", platform])
        volume = executor.get("cacheVolume")
        if volume is None:
            material = (image + "\0" + str(platform or "native")).encode("utf-8")
            volume = "nupp-fleet-" + hashlib.sha256(material).hexdigest()[:16]
        else:
            volume = _require_string(volume, "cacheVolume")
            if not _DOCKER_NAME.fullmatch(volume):
                raise ValueError("cacheVolume must be a Docker volume name")
        argv.extend(["-v", volume + ":/nupp-cache", "-e", "NUPP_FLEET_CACHE=/nupp-cache"])
        argv.extend([image, "python3", "-u", "-c", BOOTSTRAP_SOURCE])
        return argv

    raise ValueError("executor kind must be local, ssh, or docker")


def validate_result(result: Any, request: Mapping[str, Any]) -> dict[str, Any]:
    """Reject a malformed or stale worker result."""

    if not isinstance(result, dict):
        raise TransportError("worker result must be a JSON object")
    if result.get("jobId") != request.get("jobId"):
        raise TransportError("worker result has the wrong jobId")
    expected_source = request.get("source", {}).get("snapshotSha256")
    if result.get("sourceSha256") != expected_source:
        raise TransportError("worker result has the wrong sourceSha256")
    return result


def dispatch(
    executor: Mapping[str, Any],
    request: Mapping[str, Any],
    bundle_path: os.PathLike[str] | str,
    on_start: Optional[Callable[[subprocess.Popen[bytes]], None]] = None,
) -> Tuple[dict[str, Any], str]:
    """Run one worker and return its JSON result and captured diagnostics.

    ``on_start`` receives the live transport process.  A controller can retain
    that handle for cancellation without teaching this module about run leases.
    A worker may use a nonzero exit status to report a failed test job; a valid
    result object is still returned.  A nonzero transport with no valid result
    raises ``TransportError``.
    """

    path = Path(bundle_path)
    if not path.is_file():
        raise ValueError(f"bundle_path is not a file: {path}")
    framed_request = dict(request)
    if executor.get("kind") in ("local", "ssh") and executor.get("cache") is not None:
        framed_request["workerCache"] = _require_string(executor.get("cache"), "cache")
    if executor.get("kind") in ("local", "ssh") and executor.get("toolchain") is not None:
        framed_request["workerToolchain"] = _require_string(executor.get("toolchain"), "toolchain")
    prepared, request_bytes = prepare_request(framed_request, path)
    argv = validate_executor(executor, prepared)
    process = subprocess.Popen(
        argv,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        if on_start is not None:
            on_start(process)
        assert process.stdin is not None
        process.stdin.write(struct.pack(">Q", len(request_bytes)))
        process.stdin.write(request_bytes)
        with path.open("rb") as source:
            while True:
                piece = source.read(1024 * 1024)
                if not piece:
                    break
                process.stdin.write(piece)
        process.stdin.close()
        process.stdin = None
        stdout, stderr = process.communicate()
    except BaseException:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        raise

    stderr_text = stderr.decode("utf-8", errors="replace")
    output = stdout.decode("utf-8", errors="replace").strip()
    try:
        decoded = json.loads(output)
    except json.JSONDecodeError as problem:
        detail = f"transport exited {process.returncode}; worker wrote no valid JSON result: {problem}"
        if output:
            detail += "; stdout: " + output[:1000]
        if stderr_text:
            detail += "; stderr: " + stderr_text[-2000:]
        raise TransportError(detail) from problem
    return validate_result(decoded, prepared), stderr_text


__all__ = [
    "BOOTSTRAP_SOURCE",
    "PROTOCOL_VERSION",
    "TransportError",
    "dispatch",
    "prepare_request",
    "sha256_file",
    "validate_executor",
    "validate_result",
]
