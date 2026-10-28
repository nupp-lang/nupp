"""Exercise diagnostic controls without requiring Windows or GDB."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_frame_debug', ROOT / '.github/scripts/native-frame-debug.py')
debug = importlib.util.module_from_spec(spec)
spec.loader.exec_module(debug)


class FrameDebugTest(unittest.TestCase):
    def test_preserves_capture_and_runs_plain_controls_before_debugger(self):
        with tempfile.TemporaryDirectory(prefix='nupp debug with spaces ') as temp:
            root = Path(temp).resolve()
            out = root / 'evidence'
            out.mkdir()
            binary = root / 'test executable.exe'
            binary.write_bytes(b'frozen product')
            (out / 'allocator-cargo.log').write_text(f'Running unittests src/lib.rs ({binary})\n')
            calls = []

            def execute(command, cwd, env, logfile, timeout):
                calls.append((command, env, logfile))
                self.assertEqual(cwd, root)
                self.assertIn('--test-threads=1', command)
                self.assertTrue(all(name not in env for name in debug.CONTROLS))
                return {'exitCode': 0xC0000005 if len(calls) == 1 else 0, 'timedOut': False}

            with patch.dict(os.environ, {name: '1' for name in debug.CONTROLS}), patch.object(debug, 'execute', execute):
                result = debug.diagnose(root, out, 'gdb executable.exe')
            self.assertEqual(len(calls), 8)
            self.assertEqual([item['name'] for item in result['runs']], [
                'exact-reentry-capture-plain', 'exact-reentry-nocapture-plain',
                'serial-library-capture-plain', 'serial-library-nocapture-plain',
                'exact-reentry-capture-gdb', 'exact-reentry-nocapture-gdb',
                'serial-library-capture-gdb', 'serial-library-nocapture-gdb'])
            for index, (command, _, _) in enumerate(calls):
                self.assertEqual('--nocapture' in command, index % 2 == 1)
                self.assertNotIn('-ex', command)
                if index < 4:
                    self.assertEqual(command[0], str(binary))
                else:
                    self.assertEqual(command[:2], ['gdb executable.exe', '--batch'])
                    self.assertEqual(command[2], '-x')
                    self.assertEqual(Path(command[3]).read_text(), debug.GDB_COMMANDS)
                    self.assertEqual(command[4:6], ['--args', str(binary)])
                    self.assertEqual(command[5:], calls[index - 4][0])
            saved = json.loads((out / 'reentry-diagnostics.json').read_text())
            self.assertEqual(saved, result)
            self.assertEqual(result['runs'][0]['exitCode'], 0xC0000005)
            self.assertEqual(len(list(out.glob('*-command.json'))), 8)

    def test_refuses_missing_executable_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            (root / 'allocator-cargo.log').write_text('no compiled library test')
            with self.assertRaisesRegex(ValueError, 'No compiled library'):
                debug.diagnose(root, root, 'gdb')
            (root / 'allocator-cargo.log').write_text('Running unittests src/lib.rs (missing.exe)\n')
            with self.assertRaisesRegex(ValueError, 'Missing recorded executable'):
                debug.diagnose(root, root, 'gdb')

    def test_retains_failed_process_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            log = root / 'failed.log'
            result = debug.execute([sys.executable, '-c', 'print("failure evidence"); exit(7)'],
                                   root, dict(os.environ), log, 10)
            self.assertEqual(result, {'exitCode': 7, 'timedOut': False})
            self.assertIn('failure evidence', log.read_text())
            self.assertIn('Process exit: 7', log.read_text())

    def test_timeout_is_recorded_and_process_is_reaped(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            result = debug.execute([sys.executable, '-c', 'import time; time.sleep(60)'],
                                   root, dict(os.environ), root / 'timeout.log', 0.05)
            self.assertTrue(result['timedOut'])
            self.assertIsInstance(result['exitCode'], int)


if __name__ == '__main__':
    unittest.main()
