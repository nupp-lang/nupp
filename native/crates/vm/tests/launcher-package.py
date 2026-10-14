#!/usr/bin/env python3
"""Exercise package publication, launcher selection and inherited worker providers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]


def write(path, text, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


class Launcher(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="nupp launcher ")
        self.root = Path(self.temporary.name).resolve()
        for name in ("bin/nupp", "scripts/vm-cli"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, target)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("NUPP_")}
        self.env["TEST_ROOT"] = str(self.root)
        write(self.root / "scripts/toolchain", "#!/bin/sh\necho unexpected legacy toolchain >&2\nexit 91\n", True)
        self.runtime = self.root / "input runtime"
        write(self.runtime, f"#!{sys.executable}\n" + '''import json,os,subprocess,sys
from pathlib import Path
args=sys.argv[1:]
if args[0]=='verify':
    sys.exit(3 if 'BAD' in Path(args[1]).read_text() else 0)
if args[-1]=='--help':
    print('Usage: nupp')
    sys.exit(0)
if args[-1]=='parent':
    if os.environ.get('TEST_NEXT_GENERATION'):
        (Path(os.environ['TEST_ROOT'])/'.nupp/vm-cli/current').write_text(os.environ['TEST_NEXT_GENERATION']+'\\n')
    child=subprocess.check_output([str(Path(os.environ['TEST_ROOT'])/'bin/nupp'),'__comptime-worker-service'],text=True)
    print(json.dumps({'image':args[1],'child':json.loads(child),'root':os.environ.get('NUPP_COMPILER_ROOT')}))
else:
    print(json.dumps({'image':args[1],'arguments':args[3:],'runtime':os.environ.get('NUPP_VM_BINARY')}))
''', True)
        self.image = self.root / "input image"
        write(self.image, "module nupp.tools.vm.root 0 source\nentry 0\n")

    def tearDown(self):
        self.temporary.cleanup()

    def run_command(self, args, ok=True, env=None):
        result = subprocess.run([str(a) for a in args], cwd=self.root, env=env or self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def install(self):
        return Path(self.run_command([self.root / "scripts/vm-cli", "install", "--runtime", self.runtime,
                                      "--image", self.image]).stdout.strip())

    def test_default_package_pins_workers_across_publication_and_source_edits(self):
        self.run_command(["git", "init", "--quiet"])
        first = self.install()
        self.image.write_text(self.image.read_text() + "# another generation\n")
        second = self.install()
        (self.root / ".nupp/vm-cli/current").write_text(first.name + "\n")
        write(self.root / "src/newer.nupp", "new source\n")
        env = dict(self.env, TEST_NEXT_GENERATION=second.name)
        result = json.loads(self.run_command([self.root / "bin/nupp", "parent"], env=env).stdout)
        self.assertEqual(result["image"], str(first / "compiler.image"))
        self.assertEqual(result["child"]["image"], result["image"])
        self.assertEqual(result["child"]["runtime"], str(first / "runtime"))
        self.assertEqual(result["root"], str(self.root))
        next_call = json.loads(self.run_command([self.root / "bin/nupp", "worker request with spaces" ]).stdout)
        self.assertEqual(next_call["image"], str(second / "compiler.image"))
        self.assertEqual(next_call["arguments"], ["worker request with spaces"])
        status = json.loads(self.run_command([self.root / "scripts/vm-cli", "status"]).stdout)
        self.assertEqual(status["package"], str(second))
        self.assertTrue(status["sourceChangedSinceInstall"])

    def test_invalid_install_keeps_current_and_incomplete_package_fails(self):
        first = self.install()
        self.image.write_text("module nupp.tools.vm.project 0 source\n")
        self.run_command([self.root / "scripts/vm-cli", "install", "--runtime", self.runtime, "--image", self.image], ok=False)
        self.image.write_text("module nupp.tools.vm.root 0 source\nBAD\n")
        self.run_command([self.root / "scripts/vm-cli", "install", "--runtime", self.runtime, "--image", self.image], ok=False)
        self.assertEqual((self.root / ".nupp/vm-cli/current").read_text().strip(), first.name)
        (first / "runtime").unlink()
        result = self.run_command([self.root / "bin/nupp", "check"], ok=False)
        self.assertIn("runtime or image is missing", result.stderr)
        self.assertNotIn("legacy", result.stderr)

    def test_cleaned_build_outputs_preserve_installed_compiler(self):
        package = self.install()
        write(self.root / "build/output", "generated project output\n")
        shutil.rmtree(self.root / "build")
        result = json.loads(self.run_command([self.root / "bin/nupp", "check"]).stdout)
        self.assertEqual(result["image"], str(package / "compiler.image"))

    def test_explicit_image_precedes_default_and_status_detects_corruption(self):
        first = self.install()
        env = dict(self.env, NUPP_VM_CLI_IMAGE=str(self.image), NUPP_VM_BINARY=str(self.runtime))
        result = json.loads(self.run_command([self.root / "bin/nupp", "check"], env=env).stdout)
        self.assertEqual(result["image"], str(self.image))
        (first / "compiler.image").write_text("corrupt")
        self.assertIn("does not match", self.run_command([self.root / "scripts/vm-cli", "status"], ok=False).stderr)

    def test_legacy_worker_reuses_parent_provider_after_source_edit(self):
        write(self.root / "scripts/rocks.sh", "link_development_rocks() { :; }\n")
        write(self.root / "scripts/luajit.sh", "select_luajit() { return 0; }\n")
        write(self.root / "build/nupp/tools/main.lua", "unused fake compiler\n")
        write(self.root / "scripts/toolchain", '''#!/bin/sh
case "$1" in
--prefix) printf '%s/toolchain\\n' "$TEST_ROOT" ;;
native-rust) echo build >> "$TEST_ROOT/native-builds"; echo provider > "$TEST_ROOT/provider"; printf '%s/provider\\n' "$TEST_ROOT" ;;
*) exit 92 ;;
esac
''', True)
        write(self.root / "fake-bin/luajit", '''#!/bin/sh
case "$*" in
*__comptime-worker-service*) echo WORKER ;;
*) mkdir -p "$TEST_ROOT/runtime"; echo changed > "$TEST_ROOT/runtime/edit.rs"; exec "$TEST_ROOT/bin/nupp" __comptime-worker-service ;;
esac
''', True)
        env = dict(self.env, PATH=str(self.root / "fake-bin") + os.pathsep + self.env["PATH"])
        result = self.run_command([self.root / "bin/nupp", "--help"], env=env)
        self.assertEqual(result.stdout.strip(), "WORKER")
        self.assertEqual((self.root / "native-builds").read_text().splitlines(), ["build"])
        # A standalone worker did not inherit a selected provider and still provisions.
        self.run_command([self.root / "bin/nupp", "__comptime-worker-service"], env=env)
        self.assertEqual((self.root / "native-builds").read_text().splitlines(), ["build", "build"])


if __name__ == "__main__":
    unittest.main()
