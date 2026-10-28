#!/usr/bin/env python3
"""Test acceptance preparation and parsing without executing workloads or timers."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import measure_runtime as gate


class AcceptanceTests(unittest.TestCase):
    def test_mode_and_checksum_are_required(self):
        text = 'compiled frame entries: 0\nload 0.20 ms\tfirst call 12.500 ms\tobjects live 5 allocated 9\tcycles 2\n'
        self.assertEqual(gate.result('832040\n', text, 832040)['firstCallMs'], 12.5)
        for stdout, stderr in [('832041', text), ('832040', text.replace('entries: 0', 'entries: 1')),
                               ('832040', text + 'guest jit: compiled 1\n'), ('832040', text + text),
                               ('832040', text.replace('12.500', '0.000')), ('832040', text.replace('compiled frame entries: 0\n', ''))]:
            with self.assertRaises(AssertionError):
                gate.result(stdout, stderr, 832040)

    def test_environment_has_only_requested_provider(self):
        with patch.dict(os.environ, {'NUPP_RAW_CORE': 'wrong', 'JIT_OPT': 'speed', 'GC_STRESS': '1',
                                     'NO_THREADED': '1', 'AOT_ONLY': '1', 'SIMD_INTERPRET': '1',
                                     'TRACE_OPS': '1', 'NO_DIRECT': '1'}, clear=True):
            self.assertEqual(gate.clean_env(), {'NO_JIT': '1', 'NO_AOT': '1'})
            self.assertEqual(gate.clean_env('/closed/bundle.json'),
                             {'NO_JIT': '1', 'NO_AOT': '1', 'NUPP_RAW_CORE': '/closed/bundle.json'})

    def test_three_percent_uses_paired_upper_bound(self):
        for ratio, expected in [(1, True), (1.02, True), (1.04, False)]:
            pairs = [dict(linked=dict(firstCallMs=n), owned=dict(firstCallMs=n * ratio)) for n in range(10, 22)]
            row = gate.summarize(pairs)
            self.assertEqual(row['withinThreePercent'], expected)
            self.assertAlmostEqual(row['ownedToLinked'], ratio)
            self.assertAlmostEqual(row['ownedToLinkedInterval'][1], ratio)

    def test_ignored_provider_is_refused_before_measurement(self):
        with tempfile.TemporaryDirectory() as temp:
            report = dict(runtime='/fake/runtime', bundle='/fake/bundle', workloads=[dict(image='/fake/image')])
            process = gate.subprocess.CompletedProcess([], 0, 'verified 4 functions', '')
            with patch.object(gate.subprocess, 'run', return_value=process) as run:
                with self.assertRaisesRegex(AssertionError, 'ignored provider'):
                    gate.preflight(report, Path(temp))
                self.assertEqual(run.call_count, 1)

    def fixture(self, directory):
        def write(name, data):
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data) if isinstance(data, dict) else data)
            return path
        runtime = write('runtime', 'fake executable: never run')
        bundle = write('owned/bundle.json', dict(outputWords=105, architecture='aarch64', code='code.bin', data='data.bin'))
        code, data = write('owned/code.bin', 'fake code'), write('owned/data.bin', '')
        core = dict(runtimeFunctions=438, artifacts={})
        paths = [runtime, bundle, code, data]
        for key, name in [('runtimeClif', 'runtime.clif'), ('coreObject', 'runtime.o'), ('coreSidecar', 'runtime.o.rs')]:
            path = write(name, name)
            core['artifacts'][key] = dict(path=str(path), sha256=gate.digest(path))
            paths.append(path)
        guest = dict(cases=[])
        for name in gate.NAMES:
            source = write(name + '.nupp', name)
            image = write(name + '/workload.image', name + ' image')
            guest['cases'].append(dict(name=name, source=str(source), sourceSha256=gate.digest(source),
                                       imageSha256=gate.digest(image), checksum=1))
        return runtime, bundle, write('guests.json', guest), write('core.json', core), write('proof.json',
            dict(source='frozen-test-source', artifacts={str(path): gate.digest(path) for path in paths}))

    def test_prepare_freezes_inputs_and_detects_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = self.fixture(root)
            with patch.object(gate.subprocess, 'run', side_effect=AssertionError('workload execution forbidden')):
                report = gate.prepare(*args, root / 'prepared')
            self.assertEqual(report['status'], 'prepared')
            self.assertEqual(len(report['workloads']), 6)
            gate.verify(report)
            Path(report['workloads'][0]['image']).write_text('changed')
            with self.assertRaises(AssertionError):
                gate.verify(report)

    def test_proof_cannot_omit_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = self.fixture(root)
            proof = json.loads(args[4].read_text())
            del proof['artifacts'][str(args[0])]
            args[4].write_text(json.dumps(proof))
            with self.assertRaisesRegex(AssertionError, 'build proof omits'):
                gate.prepare(*args, root / 'prepared')

    def test_stale_workload_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = self.fixture(root)
            (root / 'fib/workload.image').write_text('drift')
            with self.assertRaisesRegex(AssertionError, 'input drift'):
                gate.prepare(*args, root / 'prepared')


if __name__ == '__main__':
    unittest.main()
