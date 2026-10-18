"""Bounded subprocesses for the native executable-memory acceptance gates.

Outputs are exclusive. Every child has its own process group, bound before
reaping; a numeric process group is never rediscovered after its birth anchor
is lost. Full command output survives both command and assertion failures.
"""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

def process_table(deadline):
    remaining = deadline - time.monotonic()
    assert remaining > 0, "Process observation deadline exhausted"
    text = subprocess.check_output(
        ["/bin/ps", "-axo", "pid=,ppid=,pgid=,lstart=,state=,command="],
        text=True, timeout=min(1., remaining))
    result = {}
    for line in text.splitlines():
        fields = line.split(None, 9)
        if len(fields) == 10:
            pid, ppid, pgid = map(int, fields[:3])
            result[pid] = dict(pid=pid, ppid=ppid, pgid=pgid,
                born=" ".join(fields[3:8]), state=fields[8], command=fields[9])
    return result

class Owned:
    # Construction has no observation or subprocess: register before binding.
    # Birth is the macOS ps lstart identity (one-second resolution). A root is
    # first bound while its Popen handle has NEVER been polled/reaped, so its
    # PID cannot have been recycled. Lost groups are never resurrected.
    def __init__(self, child):
        self.child = child
        self.history = {}
        self.root = None
        self.sealed = False
        self.uncertain = False

    def bind(self, deadline):
        table = process_table(deadline)
        root = table.get(self.child.pid)
        assert root is not None and root["pgid"] == self.child.pid, "Cannot bind unreaped child"
        self.root = root
        self.history[root["pid"]] = root
        return self.observe(deadline, table)

    def observe(self, deadline, table=None):
        try:
            if self.root is None:
                raise RuntimeError("Initial child birth was not bound")
            table = process_table(deadline) if table is None else table
            alive = {pid for pid, old in self.history.items()
                     if pid in table and table[pid]["born"] == old["born"]
                     and not (pid == self.child.pid and self.child.returncode is not None)
                     and not table[pid]["state"].startswith("Z")}
            # A birth-matched unreaped zombie root also anchors its group:
            # its PID cannot be recycled while Popen has not reaped it.
            root_row = table.get(self.child.pid)
            root_anchor = self.child.returncode is None and root_row is not None and root_row["born"] == self.root["born"]
            if not alive and not root_anchor:
                self.sealed = True
                return []
            assert not self.sealed, "Refuse ownership resurrection"
            changed = True
            while changed:
                changed = False
                group_anchor = root_anchor or any(table[pid]["pgid"] == self.child.pid for pid in alive)
                for pid, row in table.items():
                    if pid in alive or row["state"].startswith("Z"):
                        continue
                    old = self.history.get(pid)
                    if old is not None and old["born"] != row["born"]:
                        continue
                    if row["ppid"] in alive or (group_anchor and row["pgid"] == self.child.pid):
                        self.history[pid] = row
                        alive.add(pid); changed = True
            for pid in alive:
                self.history[pid] = table[pid]
            return [table[pid] for pid in sorted(alive)]
        except BaseException:
            self.uncertain = True
            raise

    def signal(self, sig, deadline):
        table = process_table(deadline)
        live = self.observe(deadline, table)
        group = [row for row in live if row["pgid"] == self.child.pid]
        if group:
            # This exact fresh table must contain a birth-matched group anchor.
            assert any(row["pid"] in self.history and
                row["born"] == self.history[row["pid"]]["born"] for row in group)
            try: os.killpg(self.child.pid, sig)
            except ProcessLookupError: pass
        for row in live:
            if row["pgid"] == self.child.pid:
                continue
            current = process_table(deadline).get(row["pid"])
            if current and current["born"] == row["born"]:
                try: os.kill(row["pid"], sig)
                except ProcessLookupError: pass

    def cleanup(self, reason):
        result = {"reason": reason}
        if self.root is None:
            # Never signal a numeric group without initial birth. The direct
            # Popen child is still unreaped, so only its own handle is safe.
            self.uncertain = True
            self.child.terminate()
            try: self.child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.child.kill(); self.child.wait(timeout=5)
            result["unboundChildOnly"] = True
            result["ownershipUncertain"] = True
            return result
        for sig, seconds in [(signal.SIGTERM, 10), (signal.SIGKILL, 5)]:
            deadline = time.monotonic() + seconds
            if not self.observe(deadline): break
            self.signal(sig, deadline)
            while self.observe(deadline):
                if deadline - time.monotonic() <= 1.1: break
                time.sleep(.1)
        remaining = self.observe(time.monotonic() + 1.)
        if not remaining:
            self.child.wait(timeout=1.)
        result.update(remaining=remaining, ownershipUncertain=self.uncertain,
                      history=list(self.history.values()))
        return result

@contextlib.contextmanager
def masked():
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
    try:
        yield previous
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)

class ProcessRunner:
    def __init__(self, output):
        self.output = Path(output).absolute()
        if os.path.lexists(self.output):
            raise FileExistsError("Refuse existing output: " + str(self.output))
        self.output.mkdir(parents=True)
        self.rows = []
        self.active = []
        self.previous = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
        for sig in self.previous:
            signal.signal(sig, self.interrupt)

    def interrupt(self, signum, frame):
        raise SystemExit("Native gate interrupted by signal " + str(signum))

    def save(self):
        temporary = self.output / "commands.writing.json"
        temporary.write_text(json.dumps(self.rows, indent=2, allow_nan=False) + "\n")
        os.replace(temporary, self.output / "commands.json")

    def run(self, command, *, timeout=120, cwd=None, env=None, check=False,
            capture_output=True, text=False, input=None):
        if timeout <= 0 or timeout > 900:
            raise ValueError("A native gate command needs a fixed budget <=900s")
        label = f"command-{len(self.rows) + 1:03d}"
        stdout = self.output / (label + ".stdout")
        stderr = self.output / (label + ".stderr")
        effective = dict(os.environ if env is None else env)
        row = dict(command=list(map(str, command)), cwd=str(Path(cwd or Path.cwd()).resolve()),
                   timeoutSeconds=timeout, startedAt=time.time(),
                   environment={k: v for k, v in effective.items() if k.startswith(
                       ("NUPP_", "CARGO_", "RUST", "JIT_", "AOT_", "GC_", "DYLD_"))
                       or k in ("PATH", "TMPDIR", "NO_JIT", "NO_AOT", "SIMD_INTERPRET")})
        self.rows.append(row)
        owner = None
        failure = None
        start = time.monotonic()
        try:
            with stdout.open("xb") as so, stderr.open("xb") as se:
                stdin_path = self.output / (label + ".stdin")
                if input is not None:
                    stdin_path.write_bytes(input.encode() if isinstance(input, str) else input)
                with (stdin_path.open("rb") if input is not None else open(os.devnull, "rb")) as si:
                    with masked() as mask:
                        child = subprocess.Popen(row["command"], cwd=cwd, env=effective,
                            stdin=si, stdout=so, stderr=se, start_new_session=True,
                            preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, mask))
                        owner = Owned(child)
                        self.active.append(owner)
                        owner.bind(start + timeout)
                        row.update(pid=child.pid, birth=owner.root)
                    while True:
                        owner.observe(start + timeout)
                        if child.poll() is not None:
                            break
                        if time.monotonic() - start >= timeout:
                            raise subprocess.TimeoutExpired(command, timeout)
                        time.sleep(.05)
                    elapsed = time.monotonic() - start
                    row.update(exitCode=child.returncode, observedSeconds=elapsed, terminalAt=time.time())
                    if elapsed > timeout:
                        raise subprocess.TimeoutExpired(command, timeout)
            # Compiler worker watchdogs have a documented seven-second drain.
            # This is child quiescence, never an extension of the command budget.
            drain = time.monotonic() + 10
            while owner.observe(drain):
                if time.monotonic() + 1.1 >= drain:
                    raise RuntimeError("Residual native gate descendants")
                time.sleep(.1)
            if owner.uncertain:
                raise RuntimeError("Uncertain native gate ownership")
            self.active.remove(owner)
            row.update(remainingOwned=[], history=list(owner.history.values()))
        except BaseException as error:
            failure = error
            row["error"] = repr(error)
        finally:
            # Cleanup must precede receipt/output operations, even on SIGTERM or
            # a filesystem error. Never signal an unvalidated numeric group.
            if owner is not None and owner in self.active:
                with masked():
                    try:
                        row["cleanup"] = owner.cleanup("Native gate command finalization")
                        if owner.uncertain or owner.observe(time.monotonic() + 1):
                            raise RuntimeError("Native gate child ownership not terminal")
                        self.active.remove(owner)
                    except BaseException as cleanup_error:
                        row["cleanupError"] = repr(cleanup_error)
                        failure = failure or cleanup_error
            for name, path in (("stdout", stdout), ("stderr", stderr)):
                if path.is_file():
                    row[name] = dict(path=str(path), bytes=path.stat().st_size,
                        sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            self.save()
        if failure is not None:
            raise failure
        result = subprocess.CompletedProcess(command, row["exitCode"], stdout.read_bytes(), stderr.read_bytes())
        if text:
            result.stdout = result.stdout.decode()
            result.stderr = result.stderr.decode()
        if check:
            result.check_returncode()
        return result
